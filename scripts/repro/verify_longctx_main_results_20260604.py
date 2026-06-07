#!/usr/bin/env python3
"""Strict verifier for the 2026-06-04 long-context KiloWare evidence bundle.

This verifier is intentionally read-only. It checks that the A100 trace ingest,
4K/8K/16K main replay matrix, complete 32K stress matrix, RTL cycle-level
latency outputs, backend-latency sweep, SmolVLM smoke replay, and freeze/artifact
manifests are all present and internally consistent.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "delivery" / "paper" / "repro_audit" / "longctx_main_4k_8k_16k_32k_20260604"

BASELINE_CFG = "fpga_h2o_plus_service_cvr_group_fill_v251"
HV_CFG = "fpga_kiloscore_hv_opt5_global_winner"
EXPECTED_MODELS = {
    "qwen2p5_7b_instruct",
    "mistral_7b_instruct_v0p3",
    "llama3p1_8b_instruct",
    "qwen2p5_14b_instruct",
}
EXPECTED_MAIN_LENGTHS = {"4k", "8k", "16k"}
EXPECTED_ALL_LENGTHS = {"4k", "8k", "16k", "32k"}
EXPECTED_TASKS = {"multi_document_qa", "long_context_qa", "conversation_memory_qa"}
EXPECTED_SPEC_ROWS = 432
EXPECTED_PLAN_ROWS = 16
EXPECTED_MAIN_REPLAY_ROWS = 324
EXPECTED_32K_REPLAY_ROWS = 108
EXPECTED_TOTAL_REPLAY_ROWS = EXPECTED_MAIN_REPLAY_ROWS + EXPECTED_32K_REPLAY_ROWS
EXPECTED_AGG_ROWS = 32
EXPECTED_WORKLOAD_SUMMARY_ROWS = 13
EXPECTED_A100_SHA = "A945A8D543ACFEE838E385A552ACD84944D2775B6A1E58675078972AFD5A66F9"
EXPECTED_A100_32_SHA = "986C5ECFBF2A8C5627E6B24DAB4FB13F97A0917FFCFCC73CD0FA215C58C3409F"
EXPECTED_CODE_ZIP_SHA = "B70DEB44E7317EC434DC010DA2A397CF02ABADE09000839C39C9B3DF0E82502B"


@dataclass
class Check:
    name: str
    status: str
    detail: str


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT)).replace("\\", "/")
    except ValueError:
        return str(path.resolve()).replace("\\", "/")


def resolve_path(value: str | Path) -> Path:
    path = Path(value)
    return path if path.is_absolute() else ROOT / path


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8-sig") as fp:
        return list(csv.DictReader(fp))


def read_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8-sig"))


def add(checks: list[Check], name: str, passed: bool, detail: str) -> None:
    checks.append(Check(name=name, status="PASS" if passed else "FAIL", detail=detail))


def parse_float(value: Any) -> float:
    return float(str(value).strip())


def parse_int(value: Any) -> int:
    return int(float(str(value).strip()))


def boolish(value: Any) -> bool:
    return str(value).strip().lower() in {"true", "false", "0", "1"}


def count_by(rows: list[dict[str, str]], field: str) -> dict[str, int]:
    return dict(Counter(r.get(field, "") for r in rows))


def verify_a100_archives(out_dir: Path, checks: list[Check]) -> None:
    archive_sha = out_dir / "a100_longctx_archive.sha256"
    archive32_sha = out_dir / "a100_longctx32_archive.sha256"
    sums = out_dir / "a100_longctx_text_tracegen_sha256sums.txt"
    sums32 = out_dir / "a100_longctx32_text_tracegen_sha256sums.txt"
    archive_text = archive_sha.read_text(encoding="utf-8-sig", errors="replace").upper() if archive_sha.exists() else ""
    archive32_text = archive32_sha.read_text(encoding="utf-8-sig", errors="replace").upper() if archive32_sha.exists() else ""
    add(checks, "a100_archive_sha_exists", archive_sha.exists(), rel(archive_sha))
    add(checks, "a100_archive_sha_matches", EXPECTED_A100_SHA in archive_text, archive_text.strip())
    add(checks, "a100_32k_archive_sha_exists", archive32_sha.exists(), rel(archive32_sha))
    add(checks, "a100_32k_archive_sha_matches", EXPECTED_A100_32_SHA in archive32_text, archive32_text.strip())
    add(checks, "a100_internal_sha_list_exists", sums.exists() and sums.stat().st_size > 0, rel(sums))
    add(checks, "a100_32k_internal_sha_list_exists", sums32.exists() and sums32.stat().st_size > 0, rel(sums32))


def verify_specs(out_dir: Path, checks: list[Check]) -> tuple[list[dict[str, str]], set[str]]:
    spec_csv = out_dir / "longctx_spec_summary.csv"
    spec_dir = out_dir / "specs"
    rows = read_csv(spec_csv)
    spec_files = sorted(spec_dir.rglob("*.json")) if spec_dir.exists() else []
    models = {r.get("model_alias", "") for r in rows}
    lengths = {r.get("length_label", "") for r in rows}
    tasks = {r.get("task", "") for r in rows}
    workloads = {r.get("workload", "") for r in rows}
    by_length = count_by(rows, "length_label")
    by_model_length = Counter((r.get("model_alias", ""), r.get("length_label", "")) for r in rows)
    bad_tolerance = [r.get("workload", "") for r in rows if str(r.get("tolerance_ok", "")).lower() != "true"]
    bad_decode = [r.get("workload", "") for r in rows if str(r.get("decode_tokens", "")) != "64"]

    add(checks, "spec_csv_exists", spec_csv.exists(), rel(spec_csv))
    add(checks, "spec_rows_432", len(rows) == EXPECTED_SPEC_ROWS, f"rows={len(rows)}")
    add(checks, "spec_files_16", len(spec_files) == EXPECTED_PLAN_ROWS, f"files={len(spec_files)}")
    add(checks, "spec_models", models == EXPECTED_MODELS, f"models={sorted(models)}")
    add(checks, "spec_lengths", lengths == EXPECTED_ALL_LENGTHS, f"lengths={sorted(lengths)}")
    add(checks, "spec_tasks", tasks == EXPECTED_TASKS, f"tasks={sorted(tasks)}")
    add(checks, "spec_rows_per_length", by_length == {"4k": 108, "8k": 108, "16k": 108, "32k": 108}, f"by_length={by_length}")
    add(
        checks,
        "spec_rows_per_model_length",
        len(by_model_length) == EXPECTED_PLAN_ROWS and all(v == 27 for v in by_model_length.values()),
        f"groups={len(by_model_length)} counts={dict(by_model_length)}",
    )
    add(checks, "spec_tolerance_all_ok", not bad_tolerance, f"bad={bad_tolerance[:5]}")
    add(checks, "spec_decode_64", not bad_decode, f"bad={bad_decode[:5]}")
    add(checks, "spec_unique_workloads", len(workloads) == len(rows), f"unique={len(workloads)} rows={len(rows)}")
    return rows, workloads


def verify_execution_plan(out_dir: Path, checks: list[Check]) -> list[dict[str, str]]:
    plan_csv = out_dir / "longctx_text_execution_plan.csv"
    rows = read_csv(plan_csv)
    by_length = count_by(rows, "length_label")
    add(checks, "execution_plan_exists", plan_csv.exists(), rel(plan_csv))
    add(checks, "execution_plan_rows_16", len(rows) == EXPECTED_PLAN_ROWS, f"rows={len(rows)}")
    add(checks, "execution_plan_rows_per_length", by_length == {"4k": 4, "8k": 4, "16k": 4, "32k": 4}, f"by_length={by_length}")
    add(
        checks,
        "execution_plan_status_verified",
        bool(rows) and all(r.get("tracegen_status") == "A100_PREBUILT_VERIFIED" for r in rows),
        f"statuses={sorted({r.get('tracegen_status', '') for r in rows})}",
    )
    add(
        checks,
        "execution_plan_matched_pair",
        bool(rows) and all(f"{BASELINE_CFG},{HV_CFG}" in r.get("replay_command_template", "") for r in rows),
        f"expected={BASELINE_CFG},{HV_CFG}",
    )
    add(
        checks,
        "execution_plan_cycle_args",
        bool(rows)
        and all("-BackendServiceCycles 1" in r.get("replay_command_template", "") for r in rows)
        and all("-MemReadLatency 3" in r.get("replay_command_template", "") for r in rows),
        "expected default RTL latency replay arguments",
    )
    return rows


def verify_text_manifests(plan_rows: list[dict[str, str]], spec_workloads: set[str], checks: list[Check]) -> set[str]:
    manifest_workloads: set[str] = set()
    bad_cells: list[str] = []
    complete_cells = 0
    for row in plan_rows:
        manifest_path = resolve_path(row.get("tracegen_manifest", ""))
        cell = f"{row.get('length_label')}/{row.get('model_alias')}"
        expected_rows = parse_int(row.get("workload_rows", "0") or 0)
        manifest = read_json(manifest_path)
        workloads = manifest.get("workloads", [])
        names = {str(w.get("name", "")) for w in workloads}
        manifest_workloads.update(names)
        if manifest_path.exists() and len(workloads) == expected_rows and manifest.get("attention_capture") == "decode_only":
            complete_cells += 1
        else:
            bad_cells.append(f"{cell}:exists={manifest_path.exists()},rows={len(workloads)}/{expected_rows},attention={manifest.get('attention_capture')}")
    add(checks, "text_manifests_complete_16", complete_cells == EXPECTED_PLAN_ROWS, f"complete={complete_cells} bad={bad_cells[:4]}")
    add(
        checks,
        "text_manifest_workloads_match_specs",
        manifest_workloads == spec_workloads and len(manifest_workloads) == EXPECTED_SPEC_ROWS,
        f"manifest_workloads={len(manifest_workloads)} spec_workloads={len(spec_workloads)}",
    )
    return manifest_workloads


def verify_tables(out_dir: Path, spec_rows: list[dict[str, str]], checks: list[Check]) -> None:
    status_json = out_dir / "longctx_result_tables_status.json"
    per_row_csv = out_dir / "longctx_text_per_row_saving.csv"
    agg_csv = out_dir / "longctx_text_aggregate.csv"
    workload_csv = out_dir / "workload_summary_longctx.csv"
    workload_md = out_dir / "workload_summary_longctx.md"
    status = read_json(status_json)
    per_rows = read_csv(per_row_csv)
    agg_rows = read_csv(agg_csv)
    workload_rows = read_csv(workload_csv)
    per_workloads = {r.get("workload", "") for r in per_rows}
    spec_by_length = defaultdict(set)
    for row in spec_rows:
        spec_by_length[row.get("length_label", "")].add(row.get("workload", ""))
    per_by_length = defaultdict(set)
    for row in per_rows:
        per_by_length[row.get("length_label", "")].add(row.get("workload", ""))
    by_length_count = count_by(per_rows, "length_label")

    add(checks, "result_status_exists", status_json.exists(), rel(status_json))
    add(checks, "per_row_csv_exists", per_row_csv.exists(), rel(per_row_csv))
    add(checks, "per_row_rows_432", len(per_rows) == EXPECTED_TOTAL_REPLAY_ROWS, f"rows={len(per_rows)}")
    add(checks, "per_row_main_4_8_16_complete", sum(by_length_count.get(k, 0) for k in EXPECTED_MAIN_LENGTHS) == EXPECTED_MAIN_REPLAY_ROWS, f"by_length={by_length_count}")
    add(checks, "per_row_32k_complete", by_length_count.get("32k", 0) == EXPECTED_32K_REPLAY_ROWS, f"by_length={by_length_count}")
    add(
        checks,
        "per_row_main_workloads_match_specs",
        all(per_by_length[length] == spec_by_length[length] for length in EXPECTED_MAIN_LENGTHS),
        f"main_counts={{k: len(per_by_length[k]) for k in EXPECTED_MAIN_LENGTHS}}",
    )
    add(
        checks,
        "per_row_32k_models_complete",
        {r.get("model_alias", "") for r in per_rows if r.get("length_label") == "32k"} == EXPECTED_MODELS,
        "32K replay covers all four text models",
    )
    add(checks, "result_status_expected_rows_432", parse_int(status.get("text_expected_rows", -1)) == EXPECTED_SPEC_ROWS, f"expected={status.get('text_expected_rows')}")
    add(checks, "result_status_rows_432", parse_int(status.get("text_per_row_rows", -1)) == EXPECTED_TOTAL_REPLAY_ROWS, f"rows={status.get('text_per_row_rows')}")
    add(checks, "result_status_text_complete_true", status.get("text_complete") is True, f"text_complete={status.get('text_complete')}")
    add(checks, "aggregate_rows_32", len(agg_rows) == EXPECTED_AGG_ROWS, f"rows={len(agg_rows)}")
    add(checks, "workload_summary_rows_13", len(workload_rows) == EXPECTED_WORKLOAD_SUMMARY_ROWS, f"rows={len(workload_rows)}")
    add(checks, "workload_summary_md_exists", workload_md.exists(), rel(workload_md))

    text_rows = [r for r in workload_rows if r.get("suite", "").startswith("text_")]
    main_status = [r for r in text_rows if not r.get("suite", "").startswith("text_32k_")]
    rows32 = [r for r in text_rows if r.get("suite", "").startswith("text_32k_")]
    add(checks, "workload_summary_main_replay_pass", len(main_status) == 9 and all(r.get("status") == "replay_pass" for r in main_status), f"rows={len(main_status)}")
    add(checks, "workload_summary_32k_replay_pass", len(rows32) == 3 and all(r.get("status") == "replay_pass" for r in rows32), f"statuses={sorted(r.get('status', '') for r in rows32)}")

    numeric_fields = [
        "baseline_hbm_reads",
        "hv_hbm_reads",
        "hv_hbm_read_saving_pct",
        "baseline_l1_hit_pct",
        "hv_l1_hit_pct",
        "baseline_l2_hit_pct",
        "hv_l2_hit_pct",
        "baseline_hier_miss_pct",
        "hv_hier_miss_pct",
        "baseline_amat",
        "hv_amat",
        "baseline_measured_latency",
        "hv_measured_latency",
        "baseline_measured_read_latency",
        "hv_measured_read_latency",
        "baseline_wall_cycles",
        "hv_wall_cycles",
        "baseline_backend_service_cycles",
        "hv_backend_service_cycles",
        "baseline_mem_read_latency",
        "hv_mem_read_latency",
    ]
    positive_fields = [
        "baseline_measured_latency",
        "hv_measured_latency",
        "baseline_measured_read_latency",
        "hv_measured_read_latency",
        "baseline_wall_cycles",
        "hv_wall_cycles",
        "baseline_backend_service_cycles",
        "hv_backend_service_cycles",
        "baseline_mem_read_latency",
        "hv_mem_read_latency",
    ]
    bad_numeric = []
    bad_positive = []
    bad_bool = []
    for row in per_rows:
        for field in numeric_fields:
            try:
                parse_float(row.get(field, ""))
            except ValueError:
                bad_numeric.append((row.get("workload", ""), field))
        for field in positive_fields:
            try:
                if parse_float(row.get(field, "")) <= 0:
                    bad_positive.append((row.get("workload", ""), field, row.get(field, "")))
            except ValueError:
                bad_positive.append((row.get("workload", ""), field, row.get(field, "")))
        for field in ["negative_hbm", "negative_amat", "negative_effective_latency", "negative_measured_latency", "negative_wall_cycles"]:
            if not boolish(row.get(field, "")):
                bad_bool.append((row.get("workload", ""), field))
    add(checks, "per_row_numeric_fields", not bad_numeric, f"bad={bad_numeric[:5]}")
    add(checks, "per_row_positive_latency_fields", not bad_positive, f"bad={bad_positive[:5]}")
    add(checks, "per_row_negative_flags_bool", not bad_bool, f"bad={bad_bool[:5]}")
    add(checks, "per_row_negative_counts_match_status", sum(r.get("negative_hbm") == "True" for r in per_rows) == parse_int(status.get("text_negative_hbm_rows", -1)), f"status={status}")


def verify_p0_formula_vs_rtl(out_dir: Path, checks: list[Check]) -> None:
    csv_path = out_dir / "p0_formula_vs_rtl_one_trace.csv"
    json_path = out_dir / "p0_formula_vs_rtl_one_trace.json"
    md_path = out_dir / "P0_FORMULA_VS_RTL_ONE_TRACE_20260604_CN.md"
    rows = read_csv(csv_path)
    row = rows[0] if rows else {}
    summary_path = resolve_path(row.get("summary_json", "")) if row else Path("")
    summary = read_json(summary_path) if row else {}
    add(checks, "p0_formula_vs_rtl_csv_exists", csv_path.exists(), rel(csv_path))
    add(checks, "p0_formula_vs_rtl_json_exists", json_path.exists(), rel(json_path))
    add(checks, "p0_formula_vs_rtl_md_exists", md_path.exists(), rel(md_path))
    add(checks, "p0_formula_vs_rtl_rows_1", len(rows) == 1, f"rows={len(rows)}")
    add(checks, "p0_formula_vs_rtl_pass", row.get("status") == "PASS", f"status={row.get('status')}")
    add(checks, "p0_matched_pair", row.get("baseline_config") == BASELINE_CFG and row.get("hv_config") == HV_CFG, f"base={row.get('baseline_config')} hv={row.get('hv_config')}")
    add(checks, "p0_serialized_driver", row.get("wall_driver") == "serialized_request", f"driver={row.get('wall_driver')}")
    add(checks, "p0_has_formula_and_rtl_metrics", bool(row) and parse_float(row.get("baseline_formula_amat", 0)) > 0 and parse_float(row.get("baseline_measured_latency", 0)) > 0 and parse_float(row.get("baseline_wall_cycles", 0)) > 0, "formula/rtl/wall positive")
    add(checks, "p0_replay_summary_pass", summary.get("Status") == "PASS", f"summary={rel(summary_path) if summary_path else 'missing'} status={summary.get('Status')}")


def verify_backend_sweep(out_dir: Path, checks: list[Check]) -> None:
    csv_path = out_dir / "backend_latency_sweep_4k_qwen7.csv"
    json_path = out_dir / "backend_latency_sweep_4k_qwen7.json"
    md_path = out_dir / "BACKEND_LATENCY_SWEEP_20260604.md"
    rows = read_csv(csv_path)
    by_mem = {parse_int(r.get("mem_read_latency", -1)): r for r in rows if r.get("mem_read_latency")}
    add(checks, "backend_sweep_csv_exists", csv_path.exists(), rel(csv_path))
    add(checks, "backend_sweep_json_exists", json_path.exists(), rel(json_path))
    add(checks, "backend_sweep_md_exists", md_path.exists(), rel(md_path))
    add(checks, "backend_sweep_rows_4", len(rows) == 4, f"rows={len(rows)}")
    add(checks, "backend_sweep_mem_points", set(by_mem) == {3, 8, 100, 300}, f"mem={sorted(by_mem)}")
    bad = []
    for mem, row in by_mem.items():
        for field in ["baseline_measured_latency", "hv_measured_latency", "measured_latency_improve_pct", "baseline_wall_cycles", "hv_wall_cycles", "wall_cycle_improve_pct"]:
            try:
                value = parse_float(row.get(field, ""))
                if field.endswith("improve_pct"):
                    continue
                if value <= 0:
                    bad.append((mem, field, value))
            except ValueError:
                bad.append((mem, field, row.get(field, "")))
        summary = read_json(resolve_path(row.get("summary_json", "")))
        if summary.get("Status") != "PASS":
            bad.append((mem, "summary_status", summary.get("Status")))
    add(checks, "backend_sweep_runs_pass_and_positive", not bad, f"bad={bad[:5]}")
    add(
        checks,
        "backend_sweep_high_latency_effect_stronger",
        300 in by_mem and 8 in by_mem and parse_float(by_mem[300]["measured_latency_improve_pct"]) > parse_float(by_mem[8]["measured_latency_improve_pct"]),
        f"mem8={by_mem.get(8, {}).get('measured_latency_improve_pct')} mem300={by_mem.get(300, {}).get('measured_latency_improve_pct')}",
    )


def verify_smolvlm(out_dir: Path, checks: list[Check]) -> None:
    manifest_path = out_dir / "multimodal_smolvlm_runtime" / "manifest.json"
    summary_csv = out_dir / "smolvlm_runtime_matched_pair_summary.csv"
    note_path = out_dir / "P4_SMOLVLM_RUNTIME_REPLAY_20260604_CN.md"
    replay_summaries = list((out_dir / "multimodal_smolvlm_replay_reports").rglob("benchmark_eval_summary.json"))
    manifest = read_json(manifest_path)
    rows = read_csv(summary_csv)
    replay = read_json(replay_summaries[0]) if replay_summaries else {}
    configs = {str(c.get("Name", "")) for c in replay.get("Configs", [])}
    add(checks, "smolvlm_manifest_exists", manifest_path.exists(), rel(manifest_path))
    add(checks, "smolvlm_manifest_workloads_3", len(manifest.get("workloads", [])) == 3, f"workloads={len(manifest.get('workloads', []))}")
    add(checks, "smolvlm_summary_rows_3", len(rows) == 3, f"rows={len(rows)}")
    add(checks, "smolvlm_note_exists", note_path.exists(), rel(note_path))
    add(checks, "smolvlm_replay_summary_copied", len(replay_summaries) == 1, f"summaries={[rel(p) for p in replay_summaries]}")
    add(checks, "smolvlm_replay_pass", replay.get("Status") == "PASS", f"status={replay.get('Status')}")
    add(checks, "smolvlm_matched_pair", replay.get("PrimaryCompareConfig") == BASELINE_CFG and {BASELINE_CFG, HV_CFG}.issubset(configs), f"primary={replay.get('PrimaryCompareConfig')} configs={sorted(configs)}")


def verify_testbench_only_changes(checks: list[Check]) -> None:
    tb_path = ROOT / "kiloware_paper.srcs" / "sources_1" / "new" / "tb_kcmu_system_eval.sv"
    text = tb_path.read_text(encoding="utf-8-sig", errors="replace") if tb_path.exists() else ""
    desc = re.search(r"DESC_PAYLOAD_MAX\s*=\s*(\d+)", text)
    timeout = re.search(r"RESP_TIMEOUT\s*=\s*(\d+)", text)
    add(checks, "tb_system_eval_exists", tb_path.exists(), rel(tb_path))
    add(checks, "tb_desc_payload_max_131072", bool(desc) and desc.group(1) == "131072", f"value={desc.group(1) if desc else 'missing'}")
    add(checks, "tb_resp_timeout_1024", bool(timeout) and timeout.group(1) == "1024", f"value={timeout.group(1) if timeout else 'missing'}")


def verify_rtl_mechanism_boundary(out_dir: Path, checks: list[Check]) -> None:
    json_path = out_dir / "rtl_mechanism_boundary_audit_20260604.json"
    md_path = out_dir / "RTL_MECHANISM_BOUNDARY_AUDIT_20260604.md"
    payload = read_json(json_path)
    add(checks, "rtl_mechanism_boundary_json_exists", json_path.exists(), rel(json_path))
    add(checks, "rtl_mechanism_boundary_md_exists", md_path.exists(), rel(md_path))
    add(checks, "rtl_mechanism_boundary_pass", payload.get("pass") is True, f"pass={payload.get('pass')}")
    add(checks, "rtl_sources_no_dut_changes", payload.get("rtl_sources", {}).get("pass") is True and int(payload.get("rtl_sources", {}).get("checked", 0) or 0) > 0, f"rtl={payload.get('rtl_sources')}")
    add(checks, "post_route_scripts_no_changes", payload.get("vivado_tcl", {}).get("pass") is True and payload.get("constraints", {}).get("pass") is True, f"tcl={payload.get('vivado_tcl')} xdc={payload.get('constraints')}")


def verify_freeze_and_artifacts(out_dir: Path, checks: list[Check]) -> None:
    old_freeze = ROOT / "delivery" / "paper" / "repro_audit" / "old_mainline_shorttrace_freeze_20260603_170226"
    code_zip = ROOT / "delivery" / "paper" / "repro_audit" / "current_code_freeze_20260603_171214" / "kiloware_current_code_freeze_20260603_171214.zip"
    artifact_csv = out_dir / "longctx_artifact_manifest.csv"
    artifact_json = out_dir / "longctx_artifact_manifest.json"
    artifact_md = out_dir / "LONGCTX_ARTIFACT_MANIFEST_20260604.md"
    artifact = read_json(artifact_json)
    files = {str(r.get("path", "")) for r in artifact.get("files", [])}
    code = artifact.get("freeze_audit", {}).get("current_code_freeze", {})
    old = artifact.get("freeze_audit", {}).get("old_shorttrace_freeze", {})
    required = {
        "longctx_spec_summary.csv",
        "longctx_text_execution_plan.csv",
        "longctx_result_tables_status.json",
        "workload_summary_longctx.csv",
        "workload_summary_longctx.md",
        "longctx_text_per_row_saving.csv",
        "longctx_text_aggregate.csv",
        "LONGCTX_MAIN_STATUS_20260604_CN.md",
        "p0_formula_vs_rtl_one_trace.csv",
        "backend_latency_sweep_4k_qwen7.csv",
        "smolvlm_runtime_matched_pair_summary.csv",
        "P4_SMOLVLM_RUNTIME_REPLAY_20260604_CN.md",
        "LONGCTX_MAIN_FREEZE_20260604_CN.md",
        "RTL_MECHANISM_BOUNDARY_AUDIT_20260604.md",
        "rtl_mechanism_boundary_audit_20260604.json",
    }
    add(checks, "old_shorttrace_freeze_exists", old_freeze.exists() and any(old_freeze.rglob("*")), rel(old_freeze))
    add(checks, "code_freeze_zip_exists", code_zip.exists(), rel(code_zip))
    add(checks, "artifact_manifest_csv_exists", artifact_csv.exists(), rel(artifact_csv))
    add(checks, "artifact_manifest_json_exists", artifact_json.exists(), rel(artifact_json))
    add(checks, "artifact_manifest_md_exists", artifact_md.exists(), rel(artifact_md))
    add(checks, "artifact_manifest_has_files", parse_int(artifact.get("file_count", 0) or 0) > 0 and len(files) > 0, f"file_count={artifact.get('file_count')}")
    add(checks, "artifact_manifest_required_files", required.issubset(files), f"missing={sorted(required - files)}")
    add(checks, "artifact_manifest_old_freeze", bool(old.get("exists")) and parse_int(old.get("file_count", 0) or 0) > 0, f"old={old}")
    add(checks, "artifact_manifest_code_zip_sha", bool(code.get("zip_sha256_match")) and str(code.get("zip_sha256", "")).upper() == EXPECTED_CODE_ZIP_SHA, f"sha={code.get('zip_sha256')}")


def write_report(out_dir: Path, checks: list[Check], passed: bool) -> None:
    payload = {
        "schema": "kiloware_longctx_strict_verify_20260604_v1",
        "out_dir": rel(out_dir),
        "status": "PASS" if passed else "FAIL",
        "checks_total": len(checks),
        "checks_failed": sum(1 for c in checks if c.status != "PASS"),
        "checks": [asdict(c) for c in checks],
    }
    json_path = out_dir / "longctx_strict_verify_report_20260604.json"
    md_path = out_dir / "LONGCTX_STRICT_VERIFY_REPORT_20260604.md"
    json_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    lines = [
        "# KiloWare Longctx Strict Verify Report 20260604",
        "",
        f"Status: {payload['status']}",
        f"Checks: {payload['checks_total'] - payload['checks_failed']} pass / {payload['checks_total']} total",
        "",
        "| check | status | detail |",
        "|---|---|---|",
    ]
    for check in checks:
        lines.append(f"| {check.name} | {check.status} | {check.detail.replace('|', '\\|')} |")
    lines.append("")
    md_path.write_text("\n".join(lines), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--allow-incomplete", action="store_true", help="write a FAIL report but return exit code 0")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    out_dir = args.out_dir.resolve()
    checks: list[Check] = []
    verify_a100_archives(out_dir, checks)
    spec_rows, spec_workloads = verify_specs(out_dir, checks)
    plan_rows = verify_execution_plan(out_dir, checks)
    verify_text_manifests(plan_rows, spec_workloads, checks)
    verify_tables(out_dir, spec_rows, checks)
    verify_p0_formula_vs_rtl(out_dir, checks)
    verify_backend_sweep(out_dir, checks)
    verify_smolvlm(out_dir, checks)
    verify_testbench_only_changes(checks)
    verify_rtl_mechanism_boundary(out_dir, checks)
    verify_freeze_and_artifacts(out_dir, checks)
    passed = all(c.status == "PASS" for c in checks)
    write_report(out_dir, checks, passed)
    summary = {
        "status": "PASS" if passed else "FAIL",
        "checks_total": len(checks),
        "checks_failed": sum(1 for c in checks if c.status != "PASS"),
        "report_json": rel(out_dir / "longctx_strict_verify_report_20260604.json"),
        "report_md": rel(out_dir / "LONGCTX_STRICT_VERIFY_REPORT_20260604.md"),
    }
    print(json.dumps(summary, indent=2))
    return 0 if passed or args.allow_incomplete else 1


if __name__ == "__main__":
    raise SystemExit(main())
