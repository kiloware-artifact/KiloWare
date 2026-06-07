#!/usr/bin/env python3
"""Extended summarizer for long-context L1/L2 size-sweep runs.

The runner writes one status CSV per batch. This script merges one or more
status CSVs, extracts completed RTL replay metrics, and writes the extended
review tables requested for model/size/length inspection. It does not run
simulation or edit RTL.
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
RUNNER_PATH = ROOT / "automation" / "repro" / "run_longctx_l1_l2_size_sweep.py"
DEFAULT_OUT = ROOT / "delivery" / "paper" / "repro_audit" / "longctx_l1_l2_size_sweep_ext_20260605"


def load_runner() -> Any:
    spec = importlib.util.spec_from_file_location("kw_size_sweep_runner", RUNNER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot import runner from {RUNNER_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


R = load_runner()


def write_csv(path: Path, rows: list[dict[str, Any]], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fp:
        writer = csv.DictWriter(fp, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as fp:
        return list(csv.DictReader(fp))


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT)).replace("\\", "/")
    except ValueError:
        return str(path.resolve()).replace("\\", "/")


def resolve_existing(path_text: str) -> Path | None:
    if not path_text:
        return None
    path = Path(path_text)
    if not path.is_absolute():
        path = ROOT / path
    return path if path.exists() else None


def summarize_fail_reason(status: dict[str, str]) -> tuple[str, str, str]:
    status_text = status.get("replay_status", "")
    stderr = resolve_existing(status.get("replay_stderr", ""))
    stdout = resolve_existing(status.get("replay_stdout", ""))
    candidates = []
    if stderr:
        candidates.extend(stderr.read_text(encoding="utf-8", errors="replace").splitlines())
    if stdout:
        candidates.extend(stdout.read_text(encoding="utf-8", errors="replace").splitlines())
    interesting = [
        line.strip()
        for line in candidates
        if any(token in line.upper() for token in ["ERROR", "FAIL", "FATAL", "MISMATCH", "ASSERT", "DESCRIPTOR"])
    ]
    hint = interesting[-1] if interesting else status_text
    phase = "replay"
    if "xvlog" in hint.lower() or "xelab" in hint.lower():
        phase = "compile/elab"
    elif "xsim" in hint.lower() or "mismatch" in hint.lower() or "assert" in hint.lower():
        phase = "rtl_sim"
    error_class = status_text or "MISSING_STATUS"
    return phase, error_class, hint[:500]


def collect_failed_cells(status_rows: list[dict[str, str]], per_row: list[dict[str, Any]]) -> list[dict[str, Any]]:
    parsed_cells = {
        (
            str(row["model_alias"]),
            str(row["length_label"]),
            str(row["l1_lines"]),
            str(row["l2_lines"]),
        )
        for row in per_row
    }
    failed: list[dict[str, Any]] = []
    for status in status_rows:
        key = (
            str(status.get("model_alias", "")),
            str(status.get("length_label", "")),
            str(status.get("l1_lines", "")),
            str(status.get("l2_lines", "")),
        )
        replay_status = status.get("replay_status", "")
        is_pass = replay_status.startswith("PASS")
        if is_pass and key in parsed_cells:
            continue
        phase, error_class, reason = summarize_fail_reason(status)
        if is_pass:
            phase = "summary_parse"
            error_class = "PASS_BUT_NO_PARSED_ROWS"
            reason = "Replay status was PASS, but no paired hit/miss rows were parsed from its summary."
        failed.append(
            {
                "model_alias": key[0],
                "length_label": key[1],
                "l1_lines": key[2],
                "l2_lines": key[3],
                "size": f"{key[2]}/{key[3]}",
                "replay_status": replay_status,
                "phase": phase,
                "error_class": error_class,
                "key_log_path": rel(Path(status.get("replay_stderr") or status.get("replay_stdout") or "")),
                "short_reason": reason,
                "replay_run_dir": status.get("replay_run_dir", ""),
            }
        )
    return failed


def count_valid_cells(per_row: list[dict[str, Any]]) -> int:
    return len({(r["model_alias"], r["length_label"], r["l1_lines"], r["l2_lines"]) for r in per_row})


def count_status_cells(status_rows: list[dict[str, str]]) -> int:
    return len({(r.get("model_alias"), r.get("length_label"), r.get("l1_lines"), r.get("l2_lines")) for r in status_rows})


def fmt_pair(row: dict[str, Any], a: str, b: str, digits: int = 2) -> str:
    return f"{float(row[a]):.{digits}f}->{float(row[b]):.{digits}f}"


def write_markdown(
    out_dir: Path,
    status_csv: Path,
    per_row: list[dict[str, Any]],
    failed: list[dict[str, Any]],
    agg_size: list[dict[str, Any]],
    agg_model_size: list[dict[str, Any]],
) -> Path:
    md = out_dir / "EXTENDED_L1_L2_SIZE_SWEEP_PREVIEW_20260605_CN.md"
    lines = [
        "# Extended Longctx L1/L2 Size Sweep Preview",
        "",
        f"- Combined status CSV: `{rel(status_csv)}`",
        f"- Status cells: {count_status_cells(read_csv(status_csv))}",
        f"- Valid parsed cells: {count_valid_cells(per_row)}",
        f"- Failed/unparsed cells: {len(failed)}",
        f"- Parsed paired rows: {len(per_row)}",
        "- Method: xsim RTL simulation with testbench-only `KCMU_TB_L1_LINES` / `KCMU_TB_L2_LINES`; no DUT/scorer/threshold/trace edits.",
        "- Matched configs: `fpga_h2o_plus_service_cvr_group_fill_v251` vs `fpga_kiloscore_hv_opt5_global_winner`.",
        "",
        "## Aggregate By Size",
        "",
        "| L1/L2 | cells | rows | L1 hit base->KW (%) | Hier. miss base->KW (%) | RTL latency base->KW (cycles) | Lat. gain (%) | HBM save (%) | neg lat rows |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in agg_size:
        lines.append(
            f"| {row['size']} | {row['cells']} | {row['rows']} | "
            f"{fmt_pair(row, 'base_l1_hit_pct', 'kw_l1_hit_pct')} | "
            f"{fmt_pair(row, 'base_hier_miss_pct', 'kw_hier_miss_pct')} | "
            f"{fmt_pair(row, 'base_latency_cycles', 'kw_latency_cycles', 3)} | "
            f"{float(row['latency_gain_pct']):.2f} | {float(row['hbm_read_saving_pct']):.2f} | "
            f"{row['negative_latency_rows']} |"
        )
    lines += [
        "",
        "## Aggregate By Model And Size",
        "",
        "| Model | L1/L2 | cells | rows | L1 hit base->KW (%) | Hier. miss base->KW (%) | RTL latency base->KW (cycles) | Lat. gain (%) | HBM save (%) | neg lat rows |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in agg_model_size:
        lines.append(
            f"| {row['model_alias']} | {row['size']} | {row['cells']} | {row['rows']} | "
            f"{fmt_pair(row, 'base_l1_hit_pct', 'kw_l1_hit_pct')} | "
            f"{fmt_pair(row, 'base_hier_miss_pct', 'kw_hier_miss_pct')} | "
            f"{fmt_pair(row, 'base_latency_cycles', 'kw_latency_cycles', 3)} | "
            f"{float(row['latency_gain_pct']):.2f} | {float(row['hbm_read_saving_pct']):.2f} | "
            f"{row['negative_latency_rows']} |"
        )
    if failed:
        lines += [
            "",
            "## Failed Or Unparsed Cells",
            "",
            "| Model | Context | L1/L2 | Status | Phase | Reason |",
            "|---|---:|---:|---|---|---|",
        ]
        for row in failed[:80]:
            reason = str(row["short_reason"]).replace("|", "/")
            lines.append(
                f"| {row['model_alias']} | {row['length_label']} | {row['size']} | "
                f"{row['replay_status']} | {row['phase']} | {reason} |"
            )
        if len(failed) > 80:
            lines.append(f"| ... | ... | ... | ... | ... | {len(failed) - 80} more rows in failed_cells.csv |")
    md.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return md


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--status-csv", action="append", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()

    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    status_rows: list[dict[str, str]] = []
    for path in args.status_csv:
        status_rows.extend(read_csv(path.resolve()))
    combined_status = out_dir / "extended_status_combined.csv"
    write_csv(combined_status, status_rows, R.STATUS_FIELDS)

    per_row = R.build_per_row(combined_status)
    failed = collect_failed_cells(status_rows, per_row)

    per_row_fields = [
        "model_alias",
        "length_label",
        "l1_lines",
        "l2_lines",
        "size",
        "workload",
        "base_l1_hit_pct",
        "kw_l1_hit_pct",
        "base_hier_miss_pct",
        "kw_hier_miss_pct",
        "hier_miss_reduction_pp",
        "base_latency_cycles",
        "kw_latency_cycles",
        "latency_gain_pct",
        "base_wall_cycles",
        "kw_wall_cycles",
        "wall_cycle_gain_pct",
        "base_hbm_reads",
        "kw_hbm_reads",
        "hbm_read_saving_pct",
        "negative_hier_miss",
        "negative_latency",
        "negative_hbm",
        "replay_run_dir",
        "hit_miss_csv",
    ]
    agg_fields = [
        "model_alias",
        "size",
        "length_label",
        "l1_lines",
        "l2_lines",
        "rows",
        "cells",
        "models",
        "lengths",
        "base_l1_hit_pct",
        "kw_l1_hit_pct",
        "base_hier_miss_pct",
        "kw_hier_miss_pct",
        "hier_miss_reduction_pp",
        "base_latency_cycles",
        "kw_latency_cycles",
        "latency_gain_pct",
        "base_wall_cycles",
        "kw_wall_cycles",
        "wall_cycle_gain_pct",
        "base_hbm_reads",
        "kw_hbm_reads",
        "hbm_read_saving_pct",
        "negative_hier_miss_rows",
        "negative_latency_rows",
        "negative_hbm_rows",
    ]
    fail_fields = [
        "model_alias",
        "length_label",
        "l1_lines",
        "l2_lines",
        "size",
        "replay_status",
        "phase",
        "error_class",
        "key_log_path",
        "short_reason",
        "replay_run_dir",
    ]

    agg_size = [R.rounded_row(row) for row in R.aggregate(per_row, ["size", "l1_lines", "l2_lines"])]
    agg_model_size = [
        R.rounded_row(row) for row in R.aggregate(per_row, ["model_alias", "size", "l1_lines", "l2_lines"])
    ]
    agg_model_size_length = [
        R.rounded_row(row)
        for row in R.aggregate(per_row, ["model_alias", "size", "length_label", "l1_lines", "l2_lines"])
    ]

    write_csv(out_dir / "extended_per_row.csv", [R.rounded_row(row) for row in per_row], per_row_fields)
    write_csv(
        out_dir / "extended_aggregate_by_size.csv",
        agg_size,
        [field for field in agg_fields if field not in {"model_alias", "length_label"}],
    )
    write_csv(
        out_dir / "extended_aggregate_by_model_size.csv",
        agg_model_size,
        [field for field in agg_fields if field != "length_label"],
    )
    write_csv(out_dir / "extended_aggregate_by_model_size_length.csv", agg_model_size_length, agg_fields)
    write_csv(out_dir / "failed_cells.csv", failed, fail_fields)
    md = write_markdown(out_dir, combined_status, per_row, failed, agg_size, agg_model_size)

    print("EXT_SIZE_SWEEP_STATUS_CSV=" + str(combined_status))
    print("EXT_SIZE_SWEEP_PER_ROW_CSV=" + str(out_dir / "extended_per_row.csv"))
    print("EXT_SIZE_SWEEP_AGG_SIZE_CSV=" + str(out_dir / "extended_aggregate_by_size.csv"))
    print("EXT_SIZE_SWEEP_AGG_MODEL_SIZE_CSV=" + str(out_dir / "extended_aggregate_by_model_size.csv"))
    print("EXT_SIZE_SWEEP_AGG_MODEL_SIZE_LENGTH_CSV=" + str(out_dir / "extended_aggregate_by_model_size_length.csv"))
    print("EXT_SIZE_SWEEP_FAILED_CSV=" + str(out_dir / "failed_cells.csv"))
    print("EXT_SIZE_SWEEP_MD=" + str(md))
    print(f"EXT_SIZE_SWEEP_STATUS_CELLS={count_status_cells(status_rows)}")
    print(f"EXT_SIZE_SWEEP_VALID_CELLS={count_valid_cells(per_row)}")
    print(f"EXT_SIZE_SWEEP_FAILED_OR_UNPARSED_CELLS={len(failed)}")
    print(f"EXT_SIZE_SWEEP_ROWS={len(per_row)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
