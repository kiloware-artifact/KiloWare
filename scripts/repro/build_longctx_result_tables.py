#!/usr/bin/env python3
"""Build paper-side longctx result tables from completed replay reports.

The script is read-only with respect to trace/replay artifacts. It can be run
before text replay exists, in which case it emits empty text result tables and
an explicit incomplete status.
"""

from __future__ import annotations

import argparse
import csv
import json
import statistics
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "delivery" / "paper" / "repro_audit" / "longctx_main_4k_8k_16k_20260603"
BASELINE_CFG = "fpga_h2o_plus_service_cvr_group_fill_v251"
HV_CFG = "fpga_kiloscore_hv_opt5_global_winner"


TEXT_PER_ROW_FIELDS = [
    "model_alias",
    "length_label",
    "task_type",
    "workload",
    "original_workload",
    "actual_prompt_tokens",
    "decode_tokens",
    "baseline_hbm_reads",
    "hv_hbm_reads",
    "hv_hbm_read_saving_pct",
    "baseline_l1_hit_pct",
    "hv_l1_hit_pct",
    "l1_hit_delta_pp",
    "baseline_l2_hit_pct",
    "hv_l2_hit_pct",
    "l2_hit_delta_pp",
    "baseline_hier_miss_pct",
    "hv_hier_miss_pct",
    "hier_miss_reduction_pp",
    "baseline_amat",
    "hv_amat",
    "hv_amat_improve_pct",
    "baseline_effective_latency",
    "hv_effective_latency",
    "hv_effective_latency_improve_pct",
    "baseline_measured_latency",
    "hv_measured_latency",
    "hv_measured_latency_improve_pct",
    "baseline_measured_read_latency",
    "hv_measured_read_latency",
    "hv_measured_read_latency_improve_pct",
    "baseline_measured_l1_latency",
    "hv_measured_l1_latency",
    "baseline_measured_l2_latency",
    "hv_measured_l2_latency",
    "baseline_measured_cvr_latency",
    "hv_measured_cvr_latency",
    "baseline_measured_gf_latency",
    "hv_measured_gf_latency",
    "baseline_measured_l3_latency",
    "hv_measured_l3_latency",
    "baseline_wall_cycles",
    "hv_wall_cycles",
    "hv_wall_cycle_improve_pct",
    "baseline_wall_opc",
    "hv_wall_opc",
    "baseline_backend_service_cycles",
    "hv_backend_service_cycles",
    "baseline_mem_read_latency",
    "hv_mem_read_latency",
    "baseline_l2_read_latency",
    "hv_l2_read_latency",
    "negative_hbm",
    "negative_amat",
    "negative_effective_latency",
    "negative_measured_latency",
    "negative_wall_cycles",
    "replay_run_dir",
    "hit_miss_csv",
]


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT)).replace("\\", "/")
    except ValueError:
        return str(path.resolve()).replace("\\", "/")


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as fp:
        return list(csv.DictReader(fp))


def write_csv(path: Path, rows: list[dict[str, Any]], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fp:
        writer = csv.DictWriter(fp, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def pct_improve(old: float, new: float) -> float:
    if old == 0:
        return 0.0
    return round((old - new) / old * 100.0, 6)


def f(row: dict[str, str], key: str) -> float:
    return float(row.get(key, "0") or 0)


def i(row: dict[str, str], key: str) -> int:
    return int(round(float(row.get(key, "0") or 0)))


def load_workload_meta(out_dir: Path) -> dict[str, dict[str, Any]]:
    meta: dict[str, dict[str, Any]] = {}
    for spec_path in sorted((out_dir / "specs").rglob("*.json")):
        spec = read_json(spec_path)
        for workload in spec.get("workloads", []):
            wmeta = dict(workload.get("metadata", {}) or {})
            name = str(workload.get("name", ""))
            meta[name] = {
                "model_alias": wmeta.get("model_alias", spec.get("model", "")),
                "length_label": wmeta.get("length_label", ""),
                "task_type": wmeta.get("task_type", ""),
                "workload": name,
                "original_workload": wmeta.get("original_workload", ""),
                "actual_prompt_tokens": wmeta.get("actual_prompt_tokens_tokenizer", wmeta.get("actual_prompt_tokens", "")),
                "decode_tokens": workload.get("max_new_tokens", spec.get("decode_tokens", "")),
                "spec_path": rel(spec_path),
            }
    return meta


def find_text_reports(out_dir: Path) -> list[Path]:
    report_roots = [
        out_dir / "text_replay_reports",
        out_dir / "pilot32_replay_reports",
    ]
    reports: list[Path] = []
    for report_root in report_roots:
        if report_root.exists():
            reports.extend(report_root.rglob("benchmark_eval_summary.json"))
    return sorted(reports)


def pair_hit_rows(rows: list[dict[str, str]]) -> dict[str, tuple[dict[str, str], dict[str, str]]]:
    by_workload: dict[str, dict[str, dict[str, str]]] = {}
    for row in rows:
        by_workload.setdefault(row["Workload"], {})[row["Config"]] = row
    pairs: dict[str, tuple[dict[str, str], dict[str, str]]] = {}
    for workload, cfgs in by_workload.items():
        if BASELINE_CFG in cfgs and HV_CFG in cfgs:
            pairs[workload] = (cfgs[BASELINE_CFG], cfgs[HV_CFG])
    return pairs


def build_text_per_row(out_dir: Path, workload_meta: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    out_rows: list[dict[str, Any]] = []
    for summary_path in find_text_reports(out_dir):
        summary = read_json(summary_path)
        if summary.get("Status") != "PASS":
            continue
        hit_csv_raw = summary.get("HitMissAmatSummaryCsv") or str(summary_path.parent / "hit_miss_amat_summary.csv")
        hit_csv = Path(str(hit_csv_raw))
        if not hit_csv.is_absolute():
            hit_csv = summary_path.parent / hit_csv
        if not hit_csv.exists():
            continue
        for workload, (base, hv) in pair_hit_rows(read_csv(hit_csv)).items():
            meta = workload_meta.get(workload, {})
            baseline_hbm = i(base, "HbmReads")
            hv_hbm = i(hv, "HbmReads")
            baseline_amat = f(base, "AMAT")
            hv_amat = f(hv, "AMAT")
            baseline_eff = f(base, "EffectiveLatency")
            hv_eff = f(hv, "EffectiveLatency")
            baseline_meas = f(base, "MeasuredLatency")
            hv_meas = f(hv, "MeasuredLatency")
            baseline_read_meas = f(base, "MeasuredReadLatency")
            hv_read_meas = f(hv, "MeasuredReadLatency")
            baseline_wall = f(base, "WallCycles")
            hv_wall = f(hv, "WallCycles")
            row = {
                "model_alias": meta.get("model_alias", summary.get("Model", "")),
                "length_label": meta.get("length_label", ""),
                "task_type": meta.get("task_type", ""),
                "workload": workload,
                "original_workload": meta.get("original_workload", ""),
                "actual_prompt_tokens": meta.get("actual_prompt_tokens", ""),
                "decode_tokens": meta.get("decode_tokens", ""),
                "baseline_hbm_reads": baseline_hbm,
                "hv_hbm_reads": hv_hbm,
                "hv_hbm_read_saving_pct": pct_improve(float(baseline_hbm), float(hv_hbm)),
                "baseline_l1_hit_pct": f(base, "L1HitRate"),
                "hv_l1_hit_pct": f(hv, "L1HitRate"),
                "l1_hit_delta_pp": round(f(hv, "L1HitRate") - f(base, "L1HitRate"), 6),
                "baseline_l2_hit_pct": f(base, "L2HitRate"),
                "hv_l2_hit_pct": f(hv, "L2HitRate"),
                "l2_hit_delta_pp": round(f(hv, "L2HitRate") - f(base, "L2HitRate"), 6),
                "baseline_hier_miss_pct": f(base, "HierarchyMissRate"),
                "hv_hier_miss_pct": f(hv, "HierarchyMissRate"),
                "hier_miss_reduction_pp": round(f(base, "HierarchyMissRate") - f(hv, "HierarchyMissRate"), 6),
                "baseline_amat": baseline_amat,
                "hv_amat": hv_amat,
                "hv_amat_improve_pct": pct_improve(baseline_amat, hv_amat),
                "baseline_effective_latency": baseline_eff,
                "hv_effective_latency": hv_eff,
                "hv_effective_latency_improve_pct": pct_improve(baseline_eff, hv_eff),
                "baseline_measured_latency": baseline_meas,
                "hv_measured_latency": hv_meas,
                "hv_measured_latency_improve_pct": pct_improve(baseline_meas, hv_meas),
                "baseline_measured_read_latency": baseline_read_meas,
                "hv_measured_read_latency": hv_read_meas,
                "hv_measured_read_latency_improve_pct": pct_improve(baseline_read_meas, hv_read_meas),
                "baseline_measured_l1_latency": f(base, "MeasuredL1Latency"),
                "hv_measured_l1_latency": f(hv, "MeasuredL1Latency"),
                "baseline_measured_l2_latency": f(base, "MeasuredL2Latency"),
                "hv_measured_l2_latency": f(hv, "MeasuredL2Latency"),
                "baseline_measured_cvr_latency": f(base, "MeasuredCvrLatency"),
                "hv_measured_cvr_latency": f(hv, "MeasuredCvrLatency"),
                "baseline_measured_gf_latency": f(base, "MeasuredGfLatency"),
                "hv_measured_gf_latency": f(hv, "MeasuredGfLatency"),
                "baseline_measured_l3_latency": f(base, "MeasuredL3Latency"),
                "hv_measured_l3_latency": f(hv, "MeasuredL3Latency"),
                "baseline_wall_cycles": baseline_wall,
                "hv_wall_cycles": hv_wall,
                "hv_wall_cycle_improve_pct": pct_improve(baseline_wall, hv_wall),
                "baseline_wall_opc": f(base, "WallOpc"),
                "hv_wall_opc": f(hv, "WallOpc"),
                "baseline_backend_service_cycles": i(base, "BackendServiceCycles"),
                "hv_backend_service_cycles": i(hv, "BackendServiceCycles"),
                "baseline_mem_read_latency": i(base, "MemReadLatency"),
                "hv_mem_read_latency": i(hv, "MemReadLatency"),
                "baseline_l2_read_latency": i(base, "L2ReadLatency"),
                "hv_l2_read_latency": i(hv, "L2ReadLatency"),
                "negative_hbm": hv_hbm > baseline_hbm,
                "negative_amat": hv_amat > baseline_amat,
                "negative_effective_latency": hv_eff > baseline_eff,
                "negative_measured_latency": hv_meas > baseline_meas,
                "negative_wall_cycles": hv_wall > baseline_wall,
                "replay_run_dir": rel(summary_path.parent),
                "hit_miss_csv": rel(hit_csv),
            }
            out_rows.append(row)
    return sorted(out_rows, key=lambda r: (str(r["length_label"]), str(r["model_alias"]), str(r["task_type"]), str(r["workload"])))


def aggregate(rows: list[dict[str, Any]], keys: list[str]) -> list[dict[str, Any]]:
    groups: dict[tuple[Any, ...], list[dict[str, Any]]] = {}
    for row in rows:
        groups.setdefault(tuple(row.get(k, "") for k in keys), []).append(row)
    out = []
    for key, vals in sorted(groups.items()):
        item = {k: v for k, v in zip(keys, key)}
        item.update(
            {
                "rows": len(vals),
                "avg_hbm_read_saving_pct": round(statistics.mean(float(v["hv_hbm_read_saving_pct"]) for v in vals), 6),
                "avg_l1_hit_delta_pp": round(statistics.mean(float(v["l1_hit_delta_pp"]) for v in vals), 6),
                "avg_l2_hit_delta_pp": round(statistics.mean(float(v["l2_hit_delta_pp"]) for v in vals), 6),
                "avg_hier_miss_reduction_pp": round(statistics.mean(float(v["hier_miss_reduction_pp"]) for v in vals), 6),
                "avg_amat_improve_pct": round(statistics.mean(float(v["hv_amat_improve_pct"]) for v in vals), 6),
                "avg_effective_latency_improve_pct": round(
                    statistics.mean(float(v["hv_effective_latency_improve_pct"]) for v in vals), 6
                ),
                "avg_measured_latency_improve_pct": round(
                    statistics.mean(float(v["hv_measured_latency_improve_pct"]) for v in vals), 6
                ),
                "avg_wall_cycle_improve_pct": round(
                    statistics.mean(float(v["hv_wall_cycle_improve_pct"]) for v in vals), 6
                ),
                "negative_hbm_rows": sum(1 for v in vals if str(v["negative_hbm"]).lower() == "true"),
                "negative_amat_rows": sum(1 for v in vals if str(v["negative_amat"]).lower() == "true"),
                "negative_effective_latency_rows": sum(
                    1 for v in vals if str(v["negative_effective_latency"]).lower() == "true"
                ),
                "negative_measured_latency_rows": sum(
                    1 for v in vals if str(v["negative_measured_latency"]).lower() == "true"
                ),
                "negative_wall_cycle_rows": sum(1 for v in vals if str(v["negative_wall_cycles"]).lower() == "true"),
            }
        )
        out.append(item)
    return out


def workload_summary(
    out_dir: Path, workload_meta: dict[str, dict[str, Any]], per_row: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    specs = read_csv(out_dir / "longctx_spec_summary.csv")
    suite_groups: dict[tuple[str, str], list[dict[str, str]]] = {}
    length_order = {"4k": 0, "8k": 1, "16k": 2, "32k": 3}
    for row in specs:
        suite_groups.setdefault((row["length_label"], row["task"]), []).append(row)
    out = []
    for (length, task), rows in sorted(suite_groups.items(), key=lambda item: (length_order.get(item[0][0], 99), item[0][1])):
        prompt_vals = [int(r["actual_prompt_tokens"]) for r in rows]
        models = sorted({r["model_alias"] for r in rows})
        completed_rows = sum(1 for r in per_row if r.get("length_label") == length and r.get("task_type") == task)
        if completed_rows == len(rows):
            status = "replay_pass"
        elif completed_rows:
            status = f"replay_partial_{completed_rows}_of_{len(rows)}"
        else:
            trace_manifests = {
                out_dir / "text_tracegen" / length / r["model_alias"] / "manifest.json"
                for r in rows
            }
            if trace_manifests and all(path.exists() for path in trace_manifests):
                status = "trace_ready_replay_missing"
            else:
                status = "spec_ready_trace_missing"
        out.append(
            {
                "suite": f"text_{length}_{task}",
                "models": ";".join(models),
                "task_type": task,
                "context_length_range_tokens": f"{min(prompt_vals)}-{max(prompt_vals)}",
                "context_length_median_tokens": statistics.median(prompt_vals),
                "decode_length": 64,
                "rows": len(rows),
                "status": status,
                "provenance": rel(out_dir / "longctx_spec_summary.csv"),
            }
        )

    smol_manifest = out_dir / "multimodal_smolvlm_runtime" / "manifest.json"
    if smol_manifest.exists():
        manifest = read_json(smol_manifest)
        seq_lens = []
        for workload in manifest.get("workloads", []):
            runtime_file = out_dir / "multimodal_smolvlm_runtime" / str(workload.get("runtime_meta_file", ""))
            if runtime_file.exists():
                seq_lens.append(int(read_json(runtime_file).get("seq_len", 0)))
        out.append(
            {
                "suite": "multimodal_smolvlm_prefix",
                "models": "smolvlm_500m_instruct",
                "task_type": "multimodal-prefix",
                "context_length_range_tokens": f"{min(seq_lens)}-{max(seq_lens)}" if seq_lens else "",
                "context_length_median_tokens": statistics.median(seq_lens) if seq_lens else "",
                "decode_length": "single_forward_attention_export",
                "rows": len(manifest.get("workloads", [])),
                "status": "replay_pass",
                "provenance": rel(smol_manifest),
            }
        )
    return out


def write_outputs(out_dir: Path) -> dict[str, Any]:
    workload_meta = load_workload_meta(out_dir)
    expected_rows = len(read_csv(out_dir / "longctx_spec_summary.csv"))
    per_row = build_text_per_row(out_dir, workload_meta)
    agg_model_length = aggregate(per_row, ["model_alias", "length_label"])
    agg_task_length = aggregate(per_row, ["task_type", "length_label"])
    agg_all = aggregate(per_row, ["length_label"])
    workloads = workload_summary(out_dir, workload_meta, per_row)

    per_row_path = out_dir / "longctx_text_per_row_saving.csv"
    aggregate_path = out_dir / "longctx_text_aggregate.csv"
    workload_path = out_dir / "workload_summary_longctx.csv"
    md_path = out_dir / "LONGCTX_RESULT_TABLES_20260604.md"
    json_path = out_dir / "longctx_result_tables_status.json"

    write_csv(per_row_path, per_row, TEXT_PER_ROW_FIELDS)
    aggregate_fields = [
        "group",
        "model_alias",
        "task_type",
        "length_label",
        "rows",
        "avg_hbm_read_saving_pct",
        "avg_l1_hit_delta_pp",
        "avg_l2_hit_delta_pp",
        "avg_hier_miss_reduction_pp",
        "avg_amat_improve_pct",
        "avg_effective_latency_improve_pct",
        "avg_measured_latency_improve_pct",
        "avg_wall_cycle_improve_pct",
        "negative_hbm_rows",
        "negative_amat_rows",
        "negative_effective_latency_rows",
        "negative_measured_latency_rows",
        "negative_wall_cycle_rows",
    ]
    aggregate_rows = []
    for group_name, rows in [("model_length", agg_model_length), ("task_length", agg_task_length), ("length", agg_all)]:
        for row in rows:
            aggregate_rows.append({"group": group_name, "model_alias": "", "task_type": "", **row})
    write_csv(aggregate_path, aggregate_rows, aggregate_fields)
    write_csv(
        workload_path,
        workloads,
        [
            "suite",
            "models",
            "task_type",
            "context_length_range_tokens",
            "context_length_median_tokens",
            "decode_length",
            "rows",
            "status",
            "provenance",
        ],
    )

    status = {
        "text_per_row_rows": len(per_row),
        "text_expected_rows": expected_rows,
        "text_complete": len(per_row) == expected_rows,
        "text_negative_hbm_rows": sum(1 for r in per_row if r["negative_hbm"]),
        "text_negative_amat_rows": sum(1 for r in per_row if r["negative_amat"]),
        "text_negative_effective_latency_rows": sum(1 for r in per_row if r["negative_effective_latency"]),
        "text_negative_measured_latency_rows": sum(1 for r in per_row if r["negative_measured_latency"]),
        "text_negative_wall_cycle_rows": sum(1 for r in per_row if r["negative_wall_cycles"]),
        "workload_summary_rows": len(workloads),
        "per_row_csv": rel(per_row_path),
        "aggregate_csv": rel(aggregate_path),
        "workload_summary_csv": rel(workload_path),
    }
    json_path.write_text(json.dumps(status, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    lines = [
        "# KiloWare Longctx Result Tables",
        "",
        "Generated from currently available replay artifacts. Empty text result tables mean text replay has not completed yet.",
        "",
        f"- text per-row rows: {len(per_row)} / {expected_rows}",
        f"- text complete: {status['text_complete']}",
        f"- workload summary rows: {len(workloads)}",
        f"- per-row CSV: `{rel(per_row_path)}`",
        f"- aggregate CSV: `{rel(aggregate_path)}`",
        f"- workload summary CSV: `{rel(workload_path)}`",
        "",
        "## Current Interpretation",
        "",
    ]
    if per_row:
        lines.extend(
            [
                f"- negative HBM rows: {status['text_negative_hbm_rows']}",
                f"- negative AMAT rows: {status['text_negative_amat_rows']}",
                f"- negative effective-latency rows: {status['text_negative_effective_latency_rows']}",
            ]
        )
    else:
        lines.append("- No completed text replay rows are present under `text_replay_reports/`.")
    lines.extend(
        [
            "",
            "SmolVLM real multimodal-prefix replay is tracked separately in `smolvlm_runtime_matched_pair_summary.csv` and the P4 note.",
        ]
    )
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return status


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    status = write_outputs(args.out_dir.resolve())
    print(json.dumps(status, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
