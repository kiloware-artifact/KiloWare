#!/usr/bin/env python3
"""Run and summarize RTL-measured L1/L2 size sweeps on long-context traces.

This runner is intentionally thin: it reuses the existing benchmark-eval
PowerShell flow and only supplies testbench capacity defines. It does not edit
the RTL DUT, scorer, thresholds, or frozen trace artifacts.
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
DEFAULT_OUT = ROOT / "delivery" / "paper" / "repro_audit" / "longctx_l1_l2_size_sweep_20260604"
BASELINE_CFG = "fpga_h2o_plus_service_cvr_group_fill_v251"
HV_CFG = "fpga_kiloscore_hv_opt5_global_winner"

STATUS_FIELDS = [
    "timestamp",
    "l1_lines",
    "l2_lines",
    "length_label",
    "model_alias",
    "workload_rows",
    "spec_path",
    "trace_manifest",
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
        writer = csv.DictWriter(fp, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT)).replace("\\", "/")
    except ValueError:
        return str(path.resolve()).replace("\\", "/")


def split_filter(text: str) -> set[str]:
    return {item.strip() for item in text.split(",") if item.strip()}


def parse_sizes(text: str) -> list[tuple[int, int]]:
    out: list[tuple[int, int]] = []
    for item in text.split(","):
        item = item.strip().lower()
        if not item:
            continue
        match = re.fullmatch(r"(\d+)\s*[:x/]\s*(\d+)", item)
        if not match:
            raise ValueError(f"Bad size point '{item}'. Use L1:L2, e.g. 16:32.")
        out.append((int(match.group(1)), int(match.group(2))))
    if not out:
        raise ValueError("No size points selected.")
    return out


def default_python(project_root: Path) -> str:
    candidates = [
        project_root / ".venv-ml" / "Scripts" / "python.exe",
        project_root / ".venv-ml" / "bin" / "python",
    ]
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    return sys.executable


def command_text(cmd: list[str]) -> str:
    def q(arg: str) -> str:
        if not arg:
            return "''"
        if re.search(r"\s|['\"()]", arg):
            return "'" + arg.replace("'", "'\"'\"'") + "'"
        return arg

    return " ".join(q(str(part)) for part in cmd)


def invoke_logged(
    cmd: list[str],
    cwd: Path,
    stdout_path: Path,
    stderr_path: Path,
    dry_run: bool,
    env: dict[str, str],
) -> int:
    stdout_path.parent.mkdir(parents=True, exist_ok=True)
    if dry_run:
        line = "DRYRUN " + command_text(cmd)
        print(line)
        stdout_path.write_text(line + "\n", encoding="utf-8")
        stderr_path.write_text("", encoding="utf-8")
        return 0
    with stdout_path.open("w", encoding="utf-8") as stdout_fp, stderr_path.open("w", encoding="utf-8") as stderr_fp:
        proc = subprocess.run(cmd, cwd=str(cwd), stdout=stdout_fp, stderr=stderr_fp, env=env, check=False)
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


def resolve_path(path_text: str, project_root: Path) -> Path:
    raw = Path(path_text)
    if raw.is_absolute():
        return raw.resolve()
    return (project_root / raw).resolve()


def build_replay_cmd(
    powershell_path: str,
    eval_script: Path,
    project_root: Path,
    python_path: str,
    model: str,
    spec_path: Path,
    trace_manifest: Path,
    backend_service_cycles: int,
    mem_read_latency: int,
    extra_defines: str,
) -> list[str]:
    prefix = [powershell_path, "-NoProfile"]
    if os.name == "nt":
        prefix += ["-ExecutionPolicy", "Bypass"]
    return prefix + [
        "-File",
        str(eval_script),
        "-ProjectRoot",
        str(project_root),
        "-PythonPath",
        python_path,
        "-Model",
        model,
        "-BenchmarkManifest",
        str(spec_path),
        "-PrebuiltTraceManifest",
        str(trace_manifest),
        "-Configs",
        f"{BASELINE_CFG},{HV_CFG}",
        "-PrimaryCompareConfigOverride",
        BASELINE_CFG,
        "-BackendServiceCycles",
        str(backend_service_cycles),
        "-MemReadLatency",
        str(mem_read_latency),
        "-ExtraDefines",
        extra_defines,
        "-SkipLatestAlias",
    ]


def run_sweep(args: argparse.Namespace) -> int:
    project_root = args.project_root.resolve()
    out_dir = args.out_dir.resolve()
    longctx_out = args.longctx_out.resolve()
    plan_csv = args.plan_csv.resolve() if args.plan_csv else longctx_out / "longctx_text_execution_plan.csv"
    python_path = args.python_path or default_python(project_root)
    eval_script = project_root / "automation" / "run_kiloware_paper_benchmark_eval.ps1"
    if not plan_csv.exists():
        raise FileNotFoundError(f"Plan CSV not found: {plan_csv}")
    if not eval_script.exists():
        raise FileNotFoundError(f"Benchmark eval script not found: {eval_script}")

    rows = read_csv(plan_csv)
    length_filter = split_filter(args.lengths)
    model_filter = split_filter(args.models)
    selected = [
        row
        for row in rows
        if (not length_filter or row.get("length_label", "") in length_filter)
        and (not model_filter or row.get("model_alias", "") in model_filter)
    ]
    if args.max_cells > 0:
        selected = selected[: args.max_cells]
    if not selected:
        raise RuntimeError(f"No cells selected from {plan_csv}")

    sizes = parse_sizes(args.sizes)
    runner_log_root = out_dir / "runner_logs"
    runner_log_root.mkdir(parents=True, exist_ok=True)
    status_csv = runner_log_root / f"longctx_l1_l2_size_sweep_status_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    status_rows: list[dict[str, Any]] = []
    env_base = os.environ.copy()

    for l1_lines, l2_lines in sizes:
        extra_defines = f"KCMU_TB_L1_LINES={l1_lines} KCMU_TB_L2_LINES={l2_lines}"
        size_tag = f"l1_{l1_lines}_l2_{l2_lines}"
        replay_report_root = out_dir / "replay_reports" / size_tag
        for cell in selected:
            model = str(cell["model_alias"])
            length = str(cell["length_label"])
            spec_path = resolve_path(str(cell["spec_path"]), project_root)
            trace_manifest = resolve_path(str(cell["tracegen_manifest"]), project_root)
            if not spec_path.exists():
                raise FileNotFoundError(f"Spec not found: {spec_path}")
            if not trace_manifest.exists():
                raise FileNotFoundError(f"Trace manifest not found: {trace_manifest}")

            cell_log_dir = runner_log_root / size_tag / length / model
            replay_stdout = cell_log_dir / "replay_stdout.log"
            replay_stderr = cell_log_dir / "replay_stderr.log"
            print(f"SIZE_SWEEP_CELL_START size={size_tag} length={length} model={model}")

            env = env_base.copy()
            env["KILOWARE_BENCHMARK_EVAL_REPORT_ROOT"] = str(replay_report_root)
            cmd = build_replay_cmd(
                powershell_path=args.powershell_path,
                eval_script=eval_script,
                project_root=project_root,
                python_path=python_path,
                model=model,
                spec_path=spec_path,
                trace_manifest=trace_manifest,
                backend_service_cycles=args.backend_service_cycles,
                mem_read_latency=args.mem_read_latency,
                extra_defines=extra_defines,
            )
            replay_exit = invoke_logged(cmd, project_root, replay_stdout, replay_stderr, args.dry_run, env=env)
            if args.dry_run:
                replay_status = "DRYRUN"
                replay_run_dir = ""
                replay_summary = ""
            elif replay_exit != 0:
                replay_status = f"FAIL_EXIT_{replay_exit}"
                replay_run_dir, replay_summary, parsed_status = parse_replay_stdout(replay_stdout)
                if parsed_status and parsed_status.startswith("PASS") and parsed_status != "PASS_NO_STATUS_LINE":
                    replay_status = parsed_status
            else:
                replay_run_dir, replay_summary, replay_status = parse_replay_stdout(replay_stdout)

            status_rows.append(
                {
                    "timestamp": datetime.now().isoformat(timespec="seconds"),
                    "l1_lines": l1_lines,
                    "l2_lines": l2_lines,
                    "length_label": length,
                    "model_alias": model,
                    "workload_rows": cell.get("workload_rows", ""),
                    "spec_path": str(spec_path),
                    "trace_manifest": str(trace_manifest),
                    "replay_status": replay_status,
                    "replay_run_dir": replay_run_dir,
                    "replay_summary": replay_summary,
                    "replay_stdout": str(replay_stdout),
                    "replay_stderr": str(replay_stderr),
                    "backend_service_cycles": args.backend_service_cycles,
                    "mem_read_latency": args.mem_read_latency,
                    "extra_defines": extra_defines,
                }
            )
            write_csv(status_csv, status_rows, STATUS_FIELDS)
            print(f"SIZE_SWEEP_CELL_DONE size={size_tag} length={length} model={model} replay={replay_status}")

    print("LONGCTX_L1_L2_SIZE_SWEEP_STATUS_CSV=" + str(status_csv))
    return 0


def f(row: dict[str, str], key: str) -> float:
    return float(row.get(key, "0") or 0)


def i(row: dict[str, str], key: str) -> int:
    return int(round(float(row.get(key, "0") or 0)))


def pct_improve(old: float, new: float) -> float:
    if old == 0:
        return 0.0
    return (old - new) / old * 100.0


def pair_hit_rows(rows: list[dict[str, str]]) -> dict[str, tuple[dict[str, str], dict[str, str]]]:
    by_workload: dict[str, dict[str, dict[str, str]]] = {}
    for row in rows:
        by_workload.setdefault(row["Workload"], {})[row["Config"]] = row
    pairs: dict[str, tuple[dict[str, str], dict[str, str]]] = {}
    for workload, cfgs in by_workload.items():
        if BASELINE_CFG in cfgs and HV_CFG in cfgs:
            pairs[workload] = (cfgs[BASELINE_CFG], cfgs[HV_CFG])
    return pairs


def latest_status_csv(out_dir: Path) -> Path:
    candidates = sorted((out_dir / "runner_logs").glob("longctx_l1_l2_size_sweep_status_*.csv"))
    if not candidates:
        raise FileNotFoundError(f"No status CSV found under {out_dir / 'runner_logs'}")
    return candidates[-1]


def build_per_row(status_csv: Path) -> list[dict[str, Any]]:
    status_rows = read_csv(status_csv)
    out: list[dict[str, Any]] = []
    for status in status_rows:
        if status.get("replay_status", "").startswith("FAIL") or status.get("replay_status", "") == "DRYRUN":
            continue
        summary_text = status.get("replay_summary", "").strip()
        summary_path = Path(summary_text) if summary_text else Path("__missing_summary__")
        if not summary_path.exists():
            run_text = status.get("replay_run_dir", "").strip()
            if not run_text:
                continue
            run_dir = Path(run_text)
            summary_path = run_dir / "benchmark_eval_summary.json"
        if not summary_path.exists():
            continue
        summary = read_json(summary_path)
        if summary.get("Status") != "PASS":
            continue
        hit_csv = Path(str(summary.get("HitMissAmatSummaryCsv") or summary_path.parent / "hit_miss_amat_summary.csv"))
        if not hit_csv.is_absolute():
            hit_csv = summary_path.parent / hit_csv
        if not hit_csv.exists():
            continue
        for workload, (base, hv) in pair_hit_rows(read_csv(hit_csv)).items():
            base_hbm = i(base, "HbmReads")
            hv_hbm = i(hv, "HbmReads")
            base_lat = f(base, "MeasuredLatency")
            hv_lat = f(hv, "MeasuredLatency")
            base_wall = f(base, "WallCycles")
            hv_wall = f(hv, "WallCycles")
            out.append(
                {
                    "l1_lines": int(status["l1_lines"]),
                    "l2_lines": int(status["l2_lines"]),
                    "size": f'{status["l1_lines"]}/{status["l2_lines"]}',
                    "length_label": status["length_label"],
                    "model_alias": status["model_alias"],
                    "workload": workload,
                    "base_l1_hit_pct": f(base, "L1HitRate"),
                    "kw_l1_hit_pct": f(hv, "L1HitRate"),
                    "base_hier_miss_pct": f(base, "HierarchyMissRate"),
                    "kw_hier_miss_pct": f(hv, "HierarchyMissRate"),
                    "hier_miss_reduction_pp": f(base, "HierarchyMissRate") - f(hv, "HierarchyMissRate"),
                    "base_latency_cycles": base_lat,
                    "kw_latency_cycles": hv_lat,
                    "latency_gain_pct": pct_improve(base_lat, hv_lat),
                    "base_wall_cycles": base_wall,
                    "kw_wall_cycles": hv_wall,
                    "wall_cycle_gain_pct": pct_improve(base_wall, hv_wall),
                    "base_hbm_reads": base_hbm,
                    "kw_hbm_reads": hv_hbm,
                    "hbm_read_saving_pct": pct_improve(float(base_hbm), float(hv_hbm)),
                    "negative_hier_miss": f(hv, "HierarchyMissRate") > f(base, "HierarchyMissRate"),
                    "negative_latency": hv_lat > base_lat,
                    "negative_hbm": hv_hbm > base_hbm,
                    "replay_run_dir": rel(summary_path.parent),
                    "hit_miss_csv": rel(hit_csv),
                }
            )
    return out


def aggregate(rows: list[dict[str, Any]], keys: list[str]) -> list[dict[str, Any]]:
    groups: dict[tuple[Any, ...], list[dict[str, Any]]] = {}
    for row in rows:
        groups.setdefault(tuple(row[k] for k in keys), []).append(row)

    out: list[dict[str, Any]] = []
    for key, vals in sorted(groups.items(), key=lambda item: item[0]):
        base_hbm = sum(int(v["base_hbm_reads"]) for v in vals)
        kw_hbm = sum(int(v["kw_hbm_reads"]) for v in vals)
        item = {k: v for k, v in zip(keys, key)}
        item.update(
            {
                "rows": len(vals),
                "cells": len({(v["length_label"], v["model_alias"]) for v in vals}),
                "base_l1_hit_pct": statistics.mean(float(v["base_l1_hit_pct"]) for v in vals),
                "kw_l1_hit_pct": statistics.mean(float(v["kw_l1_hit_pct"]) for v in vals),
                "base_hier_miss_pct": statistics.mean(float(v["base_hier_miss_pct"]) for v in vals),
                "kw_hier_miss_pct": statistics.mean(float(v["kw_hier_miss_pct"]) for v in vals),
                "hier_miss_reduction_pp": statistics.mean(float(v["hier_miss_reduction_pp"]) for v in vals),
                "base_latency_cycles": statistics.mean(float(v["base_latency_cycles"]) for v in vals),
                "kw_latency_cycles": statistics.mean(float(v["kw_latency_cycles"]) for v in vals),
                "latency_gain_pct": statistics.mean(float(v["latency_gain_pct"]) for v in vals),
                "base_wall_cycles": statistics.mean(float(v["base_wall_cycles"]) for v in vals),
                "kw_wall_cycles": statistics.mean(float(v["kw_wall_cycles"]) for v in vals),
                "wall_cycle_gain_pct": statistics.mean(float(v["wall_cycle_gain_pct"]) for v in vals),
                "base_hbm_reads": base_hbm,
                "kw_hbm_reads": kw_hbm,
                "hbm_read_saving_pct": pct_improve(float(base_hbm), float(kw_hbm)),
                "negative_hier_miss_rows": sum(1 for v in vals if bool(v["negative_hier_miss"])),
                "negative_latency_rows": sum(1 for v in vals if bool(v["negative_latency"])),
                "negative_hbm_rows": sum(1 for v in vals if bool(v["negative_hbm"])),
                "models": ";".join(sorted({str(v["model_alias"]) for v in vals})),
                "lengths": ";".join(sorted({str(v["length_label"]) for v in vals}, key=lambda x: {"4k": 0, "8k": 1, "16k": 2, "32k": 3}.get(x, 9))),
            }
        )
        out.append(item)
    return out


def rounded_row(row: dict[str, Any]) -> dict[str, Any]:
    out = dict(row)
    for key, value in list(out.items()):
        if isinstance(value, float):
            out[key] = round(value, 6)
    return out


def write_markdown(out_dir: Path, status_csv: Path, agg_size: list[dict[str, Any]], agg_size_length: list[dict[str, Any]]) -> Path:
    md_path = out_dir / "LONGCTX_L1_L2_SIZE_SWEEP_PREVIEW_20260604_CN.md"
    lines = [
        "# Longctx L1/L2 Size Sweep RTL Simulation Preview",
        "",
        f"- Status CSV: `{rel(status_csv)}`",
        "- Scope: matched baseline `fpga_h2o_plus_service_cvr_group_fill_v251` vs `fpga_kiloscore_hv_opt5_global_winner`.",
        "- Method: xsim RTL simulation with testbench-only capacity defines; no RTL DUT/scorer/threshold/trace edits.",
        "- Metrics are row means except HBM reads, which are total reads over included rows. Latency is `MeasuredLatency` cycles from `SYS_SUMMARY` parsing.",
        "",
        "## Aggregate By Size",
        "",
        "| L1/L2 lines | cells | rows | L1 hit base->KW (%) | Hier. miss base->KW (%) | RTL latency base->KW (cycles) | Lat. gain (%) | HBM read saving (%) | neg latency rows |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in agg_size:
        lines.append(
            "| {size} | {cells} | {rows} | {b_l1:.2f}->{k_l1:.2f} | {b_m:.2f}->{k_m:.2f} | {b_lat:.3f}->{k_lat:.3f} | {lat:.2f} | {hbm:.2f} | {neg} |".format(
                size=row["size"],
                cells=row["cells"],
                rows=row["rows"],
                b_l1=row["base_l1_hit_pct"],
                k_l1=row["kw_l1_hit_pct"],
                b_m=row["base_hier_miss_pct"],
                k_m=row["kw_hier_miss_pct"],
                b_lat=row["base_latency_cycles"],
                k_lat=row["kw_latency_cycles"],
                lat=row["latency_gain_pct"],
                hbm=row["hbm_read_saving_pct"],
                neg=row["negative_latency_rows"],
            )
        )
    lines += [
        "",
        "## Aggregate By Size And Length",
        "",
        "| L1/L2 lines | length | cells | rows | L1 hit base->KW (%) | Hier. miss base->KW (%) | RTL latency base->KW (cycles) | Lat. gain (%) |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in agg_size_length:
        lines.append(
            "| {size} | {length} | {cells} | {rows} | {b_l1:.2f}->{k_l1:.2f} | {b_m:.2f}->{k_m:.2f} | {b_lat:.3f}->{k_lat:.3f} | {lat:.2f} |".format(
                size=row["size"],
                length=row["length_label"],
                cells=row["cells"],
                rows=row["rows"],
                b_l1=row["base_l1_hit_pct"],
                k_l1=row["kw_l1_hit_pct"],
                b_m=row["base_hier_miss_pct"],
                k_m=row["kw_hier_miss_pct"],
                b_lat=row["base_latency_cycles"],
                k_lat=row["kw_latency_cycles"],
                lat=row["latency_gain_pct"],
            )
        )
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return md_path


def summarize_sweep(args: argparse.Namespace) -> int:
    out_dir = args.out_dir.resolve()
    status_csv = args.status_csv.resolve() if args.status_csv else latest_status_csv(out_dir)
    per_row = build_per_row(status_csv)
    if not per_row:
        raise RuntimeError(f"No completed size-sweep rows found from {status_csv}")
    per_row_fields = [
        "l1_lines",
        "l2_lines",
        "size",
        "length_label",
        "model_alias",
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
    agg_size = [rounded_row(row) for row in aggregate(per_row, ["size", "l1_lines", "l2_lines"])]
    agg_size_length = [rounded_row(row) for row in aggregate(per_row, ["size", "length_label", "l1_lines", "l2_lines"])]
    per_row_path = out_dir / "longctx_l1_l2_size_sweep_per_row.csv"
    agg_size_path = out_dir / "longctx_l1_l2_size_sweep_aggregate_by_size.csv"
    agg_size_length_path = out_dir / "longctx_l1_l2_size_sweep_aggregate_by_size_length.csv"
    write_csv(per_row_path, [rounded_row(row) for row in per_row], per_row_fields)
    write_csv(agg_size_path, agg_size, [field for field in agg_fields if field != "length_label"])
    write_csv(agg_size_length_path, agg_size_length, agg_fields)
    md_path = write_markdown(out_dir, status_csv, agg_size, agg_size_length)
    print("LONGCTX_L1_L2_SIZE_SWEEP_PER_ROW_CSV=" + str(per_row_path))
    print("LONGCTX_L1_L2_SIZE_SWEEP_AGG_SIZE_CSV=" + str(agg_size_path))
    print("LONGCTX_L1_L2_SIZE_SWEEP_AGG_SIZE_LENGTH_CSV=" + str(agg_size_length_path))
    print("LONGCTX_L1_L2_SIZE_SWEEP_MD=" + str(md_path))
    print(f"LONGCTX_L1_L2_SIZE_SWEEP_ROWS={len(per_row)}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["run", "summarize"])
    parser.add_argument("--project-root", type=Path, default=ROOT)
    parser.add_argument("--longctx-out", type=Path, default=LONGCTX_OUT)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--plan-csv", type=Path, default=None)
    parser.add_argument("--status-csv", type=Path, default=None)
    parser.add_argument("--python-path", default="")
    parser.add_argument("--powershell-path", default="powershell.exe" if os.name == "nt" else "pwsh")
    parser.add_argument("--lengths", default="4k,8k,16k,32k")
    parser.add_argument("--models", default="")
    parser.add_argument("--max-cells", type=int, default=0)
    parser.add_argument("--sizes", default="8:16,16:32,32:64,64:128")
    parser.add_argument("--backend-service-cycles", type=int, default=1)
    parser.add_argument("--mem-read-latency", type=int, default=3)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.mode == "run":
        return run_sweep(args)
    return summarize_sweep(args)


if __name__ == "__main__":
    raise SystemExit(main())
