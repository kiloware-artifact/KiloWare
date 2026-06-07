#!/usr/bin/env python3
"""Run and summarize 32/32 long-context Table 1 control-config replay.

This is a thin orchestration wrapper around the existing
run_kiloware_paper_benchmark_eval.ps1 flow. It only supplies testbench capacity
defines and config lists; it does not edit RTL DUT, scorer thresholds, or traces.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import statistics
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
LONGCTX_OUT = ROOT / "delivery" / "paper" / "repro_audit" / "longctx_main_4k_8k_16k_32k_20260604"
DEFAULT_OUT = ROOT / "delivery" / "paper" / "repro_audit" / "longctx_table1_32_32_perf_20260605"

MISSING_CONTROL_CONFIGS = [
    "baseline",
    "fpga_true_h2o_pure",
    "fpga_h2o_plus_service_clean_victim_cache16_v245",
    "fpga_h2o_plus_service_strict_miss_prefetch_v206",
]

MATCHED_BASE = "fpga_h2o_plus_service_cvr_group_fill_v251"
MATCHED_KW = "fpga_kiloscore_hv_opt5_global_winner"

TABLE_LABELS = {
    "baseline": "Traditional cache",
    "fpga_true_h2o_pure": "Pure H2O",
    "fpga_h2o_plus_service_clean_victim_cache16_v245": "H2O + victim cache",
    "fpga_h2o_plus_service_strict_miss_prefetch_v206": "H2O + guarded prefetch",
    MATCHED_BASE: "CVR+GF baseline (matched)",
    MATCHED_KW: "KiloWare-HV",
}

STATUS_FIELDS = [
    "timestamp",
    "length_label",
    "model_alias",
    "workload_rows",
    "spec_path",
    "trace_manifest",
    "configs",
    "replay_status",
    "replay_run_dir",
    "replay_summary",
    "replay_stdout",
    "replay_stderr",
    "backend_service_cycles",
    "mem_read_latency",
    "extra_defines",
]


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as fp:
        return list(csv.DictReader(fp))


def write_csv(path: Path, rows: list[dict[str, Any]], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fp:
        writer = csv.DictWriter(fp, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT)).replace("\\", "/")
    except ValueError:
        return str(path.resolve()).replace("\\", "/")


def resolve_path(path_text: str) -> Path:
    path = Path(path_text)
    if path.is_absolute():
        return path.resolve()
    return (ROOT / path).resolve()


def default_python() -> str:
    candidate = ROOT / ".venv-ml" / "Scripts" / "python.exe"
    if candidate.exists():
        return str(candidate)
    return sys.executable


def split_filter(text: str) -> set[str]:
    return {item.strip() for item in text.split(",") if item.strip()}


def invoke_logged(cmd: list[str], stdout_path: Path, stderr_path: Path, env: dict[str, str]) -> int:
    stdout_path.parent.mkdir(parents=True, exist_ok=True)
    with stdout_path.open("w", encoding="utf-8") as stdout_fp, stderr_path.open("w", encoding="utf-8") as stderr_fp:
        proc = subprocess.run(cmd, cwd=str(ROOT), stdout=stdout_fp, stderr=stderr_fp, env=env, check=False)
    return int(proc.returncode)


def parse_replay_stdout(path: Path) -> tuple[str, str, str]:
    if not path.exists():
        return "", "", ""
    text = path.read_text(encoding="utf-8", errors="replace")
    run_match = re.search(r"KILOWARE_PAPER_BENCHMARK_EVAL_RUN_DIR=(.+)", text)
    summary_match = re.search(r"KILOWARE_PAPER_BENCHMARK_EVAL_SUMMARY=(.+)", text)
    status_match = re.search(r"KILOWARE_PAPER_BENCHMARK_EVAL_STATUS=(.+)", text)
    return (
        run_match.group(1).strip() if run_match else "",
        summary_match.group(1).strip() if summary_match else "",
        status_match.group(1).strip() if status_match else "PASS_NO_STATUS_LINE",
    )


def run(args: argparse.Namespace) -> int:
    out_dir = args.out_dir.resolve()
    plan_csv = args.plan_csv.resolve()
    eval_script = ROOT / "automation" / "run_kiloware_paper_benchmark_eval.ps1"
    python_path = args.python_path or default_python()
    rows = read_csv(plan_csv)
    model_filter = split_filter(args.models)
    length_filter = split_filter(args.lengths)
    selected = [
        row
        for row in rows
        if (not model_filter or row["model_alias"] in model_filter)
        and (not length_filter or row["length_label"] in length_filter)
    ]
    if args.max_cells > 0:
        selected = selected[: args.max_cells]
    if not selected:
        raise RuntimeError("No cells selected")

    configs = [c.strip() for c in args.configs.split(",") if c.strip()]
    config_text = ",".join(configs)
    extra_defines = "KCMU_TB_L1_LINES=32 KCMU_TB_L2_LINES=32"
    status_csv = out_dir / "runner_logs" / f"table1_perf_status_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    status_rows: list[dict[str, Any]] = []
    env_base = os.environ.copy()
    report_root = out_dir / "replay_reports" / "table1_controls_32_32"

    for cell in selected:
        model = cell["model_alias"]
        length = cell["length_label"]
        spec_path = resolve_path(cell["spec_path"])
        trace_manifest = resolve_path(cell["tracegen_manifest"])
        log_dir = out_dir / "runner_logs" / "table1_controls_32_32" / length / model
        stdout_path = log_dir / "replay_stdout.log"
        stderr_path = log_dir / "replay_stderr.log"
        cmd = [
            args.powershell_path,
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(eval_script),
            "-ProjectRoot",
            str(ROOT),
            "-PythonPath",
            python_path,
            "-Model",
            model,
            "-BenchmarkManifest",
            str(spec_path),
            "-PrebuiltTraceManifest",
            str(trace_manifest),
            "-Configs",
            config_text,
            "-BackendServiceCycles",
            str(args.backend_service_cycles),
            "-MemReadLatency",
            str(args.mem_read_latency),
            "-ExtraDefines",
            extra_defines,
            "-SkipLatestAlias",
        ]
        if MATCHED_BASE in configs:
            insert_at = cmd.index("-BackendServiceCycles")
            cmd[insert_at:insert_at] = ["-PrimaryCompareConfigOverride", MATCHED_BASE]
        print(f"TABLE1_CELL_START length={length} model={model} configs={len(configs)}", flush=True)
        env = env_base.copy()
        env["KILOWARE_BENCHMARK_EVAL_REPORT_ROOT"] = str(report_root)
        exit_code = invoke_logged(cmd, stdout_path, stderr_path, env)
        replay_run_dir, replay_summary, parsed_status = parse_replay_stdout(stdout_path)
        if exit_code != 0:
            replay_status = f"FAIL_EXIT_{exit_code}"
            if parsed_status.startswith("PASS") and parsed_status != "PASS_NO_STATUS_LINE":
                replay_status = parsed_status
        else:
            replay_status = parsed_status
        status_rows.append(
            {
                "timestamp": datetime.now().isoformat(timespec="seconds"),
                "length_label": length,
                "model_alias": model,
                "workload_rows": cell.get("workload_rows", ""),
                "spec_path": str(spec_path),
                "trace_manifest": str(trace_manifest),
                "configs": config_text,
                "replay_status": replay_status,
                "replay_run_dir": replay_run_dir,
                "replay_summary": replay_summary,
                "replay_stdout": str(stdout_path),
                "replay_stderr": str(stderr_path),
                "backend_service_cycles": args.backend_service_cycles,
                "mem_read_latency": args.mem_read_latency,
                "extra_defines": extra_defines,
            }
        )
        write_csv(status_csv, status_rows, STATUS_FIELDS)
        print(f"TABLE1_CELL_DONE length={length} model={model} replay={replay_status}", flush=True)
    print("LONGCTX_TABLE1_PERF_STATUS_CSV=" + str(status_csv), flush=True)
    return 0


def f(row: dict[str, str], key: str) -> float:
    return float(row.get(key, "0") or 0)


def i(row: dict[str, str], key: str) -> int:
    return int(round(float(row.get(key, "0") or 0)))


def collect_per_row(status_csv: Path) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for status in read_csv(status_csv):
        if not status.get("replay_status", "").startswith("PASS"):
            continue
        summary_path = Path(status.get("replay_summary", ""))
        if not summary_path.exists() and status.get("replay_run_dir"):
            summary_path = Path(status["replay_run_dir"]) / "benchmark_eval_summary.json"
        if not summary_path.exists():
            continue
        summary = read_json(summary_path)
        if summary.get("Status") != "PASS":
            continue
        hit_csv = Path(summary.get("HitMissAmatSummaryCsv") or summary_path.parent / "hit_miss_amat_summary.csv")
        if not hit_csv.exists():
            continue
        for row in read_csv(hit_csv):
            cfg = row["Config"]
            out.append(
                {
                    "model_alias": status["model_alias"],
                    "length_label": status["length_label"],
                    "workload": row["Workload"],
                    "config": cfg,
                    "table_label": TABLE_LABELS.get(cfg, cfg),
                    "l1_hit_pct": f(row, "L1HitRate"),
                    "hier_miss_pct": f(row, "HierarchyMissRate"),
                    "latency_cycles": f(row, "MeasuredLatency"),
                    "wall_cycles": f(row, "WallCycles"),
                    "hbm_reads": i(row, "HbmReads"),
                    "hit_miss_csv": rel(hit_csv),
                }
            )
    return out


def load_matched_main32(out_dir: Path) -> list[dict[str, Any]]:
    path = out_dir / "main32_preview" / "extended_per_row.csv"
    if not path.exists():
        return []
    rows = []
    for row in read_csv(path):
        common = {
            "model_alias": row["model_alias"],
            "length_label": row["length_label"],
            "workload": row["workload"],
        }
        rows.append(
            {
                **common,
                "config": MATCHED_BASE,
                "table_label": TABLE_LABELS[MATCHED_BASE],
                "l1_hit_pct": f(row, "base_l1_hit_pct"),
                "hier_miss_pct": f(row, "base_hier_miss_pct"),
                "latency_cycles": f(row, "base_latency_cycles"),
                "wall_cycles": f(row, "base_wall_cycles"),
                "hbm_reads": i(row, "base_hbm_reads"),
                "hit_miss_csv": row.get("hit_miss_csv", ""),
            }
        )
        rows.append(
            {
                **common,
                "config": MATCHED_KW,
                "table_label": TABLE_LABELS[MATCHED_KW],
                "l1_hit_pct": f(row, "kw_l1_hit_pct"),
                "hier_miss_pct": f(row, "kw_hier_miss_pct"),
                "latency_cycles": f(row, "kw_latency_cycles"),
                "wall_cycles": f(row, "kw_wall_cycles"),
                "hbm_reads": i(row, "kw_hbm_reads"),
                "hit_miss_csv": row.get("hit_miss_csv", ""),
            }
        )
    return rows


def aggregate(rows: list[dict[str, Any]], keys: list[str]) -> list[dict[str, Any]]:
    groups: dict[tuple[Any, ...], list[dict[str, Any]]] = {}
    for row in rows:
        groups.setdefault(tuple(row[k] for k in keys), []).append(row)
    out = []
    for key, vals in sorted(groups.items(), key=lambda item: item[0]):
        item = {k: v for k, v in zip(keys, key)}
        item.update(
            {
                "rows": len(vals),
                "cells": len({(v["model_alias"], v["length_label"]) for v in vals}),
                "l1_hit_pct": statistics.mean(float(v["l1_hit_pct"]) for v in vals),
                "hier_miss_pct": statistics.mean(float(v["hier_miss_pct"]) for v in vals),
                "latency_cycles": statistics.mean(float(v["latency_cycles"]) for v in vals),
                "wall_cycles": statistics.mean(float(v["wall_cycles"]) for v in vals),
                "hbm_reads": sum(int(v["hbm_reads"]) for v in vals),
            }
        )
        out.append(item)
    return out


def summarize(args: argparse.Namespace) -> int:
    out_dir = args.out_dir.resolve()
    status_csv = args.status_csv.resolve()
    control_rows = collect_per_row(status_csv)
    matched_rows = load_matched_main32(args.main32_out.resolve())
    all_rows = control_rows + matched_rows
    if not all_rows:
        raise RuntimeError("No rows parsed")

    per_row_fields = [
        "model_alias",
        "length_label",
        "workload",
        "config",
        "table_label",
        "l1_hit_pct",
        "hier_miss_pct",
        "latency_cycles",
        "wall_cycles",
        "hbm_reads",
        "hit_miss_csv",
    ]
    agg_fields = [
        "config",
        "table_label",
        "rows",
        "cells",
        "l1_hit_pct",
        "hier_miss_pct",
        "latency_cycles",
        "wall_cycles",
        "hbm_reads",
    ]
    per_row_csv = out_dir / "table1_32_32_perf_per_row.csv"
    agg_csv = out_dir / "table1_32_32_perf_aggregate.csv"
    write_csv(per_row_csv, all_rows, per_row_fields)
    agg_rows = aggregate(all_rows, ["config", "table_label"])
    order = list(TABLE_LABELS)
    agg_rows = sorted(agg_rows, key=lambda r: order.index(r["config"]) if r["config"] in order else 99)
    write_csv(agg_csv, agg_rows, agg_fields)

    md = out_dir / "TABLE1_32_32_PERF_PREVIEW_20260605_CN.md"
    lines = [
        "# Table 1 32/32 Performance Preview",
        "",
        f"- Control status CSV: `{rel(status_csv)}`",
        f"- Control rows parsed: {len(control_rows)}",
        f"- Matched rows reused from main32: {len(matched_rows)}",
        "- Method: xsim RTL replay with testbench-only `KCMU_TB_L1_LINES=32 KCMU_TB_L2_LINES=32`; no DUT/scorer/threshold/trace edits.",
        "",
        "| Table label | Config | Rows | Cells | L1 hit (%) | Hierarchy miss (%) | Latency (cycles) | HBM reads |",
        "|---|---|---:|---:|---:|---:|---:|---:|",
    ]
    for row in agg_rows:
        lines.append(
            f"| {row['table_label']} | `{row['config']}` | {row['rows']} | {row['cells']} | "
            f"{float(row['l1_hit_pct']):.2f} | {float(row['hier_miss_pct']):.2f} | "
            f"{float(row['latency_cycles']):.3f} | {int(row['hbm_reads'])} |"
        )
    lines += [
        "",
        "## Provenance",
        "",
        f"- Per-row CSV: `{rel(per_row_csv)}`",
        f"- Aggregate CSV: `{rel(agg_csv)}`",
    ]
    md.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"TABLE1_PERF_PER_ROW_CSV={per_row_csv}")
    print(f"TABLE1_PERF_AGGREGATE_CSV={agg_csv}")
    print(f"TABLE1_PERF_MD={md}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)
    p_run = sub.add_parser("run")
    p_run.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    p_run.add_argument("--plan-csv", type=Path, default=LONGCTX_OUT / "longctx_text_execution_plan.csv")
    p_run.add_argument("--python-path", default="")
    p_run.add_argument("--powershell-path", default="powershell.exe")
    p_run.add_argument("--configs", default=",".join(MISSING_CONTROL_CONFIGS))
    p_run.add_argument("--models", default="")
    p_run.add_argument("--lengths", default="")
    p_run.add_argument("--max-cells", type=int, default=0)
    p_run.add_argument("--backend-service-cycles", type=int, default=1)
    p_run.add_argument("--mem-read-latency", type=int, default=3)
    p_run.set_defaults(func=run)

    p_sum = sub.add_parser("summarize")
    p_sum.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    p_sum.add_argument("--status-csv", type=Path, required=True)
    p_sum.add_argument("--main32-out", type=Path, default=ROOT / "delivery" / "paper" / "repro_audit" / "longctx_l1_l2_size_sweep_ext_20260605")
    p_sum.set_defaults(func=summarize)

    args = parser.parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
