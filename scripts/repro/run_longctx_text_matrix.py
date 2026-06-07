#!/usr/bin/env python3
"""Cross-platform runner for the KiloWare longctx text trace/replay matrix.

The PowerShell runner remains useful on the Windows/Vivado host. This Python
runner exists for GPU or larger-memory hosts, where only text trace generation
may be feasible. It reads the same execution-plan CSV but resolves paths against
the local project root and, when used from the handoff zip, the local `longctx/`
artifact directory.
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "delivery" / "paper" / "repro_audit" / "longctx_main_4k_8k_16k_20260603"
MARKER = "delivery/paper/repro_audit/longctx_main_4k_8k_16k_20260603/"

BASELINE_CFG = "fpga_h2o_plus_service_cvr_group_fill_v251"
HV_CFG = "fpga_kiloscore_hv_opt5_global_winner"

STATUS_FIELDS = [
    "timestamp",
    "length_label",
    "model_alias",
    "workload_rows",
    "spec_path",
    "tracegen_manifest",
    "tracegen_status",
    "replay_status",
    "replay_run_dir",
    "replay_summary",
    "tracegen_stdout",
    "tracegen_stderr",
    "replay_stdout",
    "replay_stderr",
    "backend_service_cycles",
    "mem_read_latency",
]


def split_filter(text: str) -> set[str]:
    return {item.strip() for item in text.split(",") if item.strip()}


def command_text(cmd: list[str]) -> str:
    return " ".join(quote_arg(item) for item in cmd)


def quote_arg(text: str) -> str:
    if not text:
        return "''"
    if re.search(r"\s|['\"()]", text):
        return "'" + text.replace("'", "'\"'\"'") + "'"
    return text


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as fp:
        return list(csv.DictReader(fp))


def write_status(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fp:
        writer = csv.DictWriter(fp, fieldnames=STATUS_FIELDS)
        writer.writeheader()
        writer.writerows(rows)


def default_python(project_root: Path) -> str:
    candidates = [
        project_root / ".venv-ml" / "Scripts" / "python.exe",
        project_root / ".venv-ml" / "bin" / "python",
    ]
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    return sys.executable


def default_plan_csv(project_root: Path) -> Path:
    candidates = [
        DEFAULT_OUT / "longctx_text_execution_plan.csv",
        project_root / "longctx" / "longctx_text_execution_plan.csv",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()
    return candidates[0].resolve()


def suffix_after_marker(path_text: str) -> str | None:
    norm = path_text.replace("\\", "/")
    if MARKER in norm:
        return norm.split(MARKER, 1)[1]
    return None


def resolve_artifact_path(path_text: str, project_root: Path, plan_dir: Path) -> Path:
    text = path_text.strip()
    suffix = suffix_after_marker(text)
    raw = Path(text)

    candidates: list[Path] = []
    if raw.is_absolute():
        candidates.append(raw)
    else:
        candidates.append(project_root / raw)
        candidates.append(plan_dir / raw)

    if suffix is not None:
        candidates.append(plan_dir / suffix)

    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()

    if suffix is not None:
        return (plan_dir / suffix).resolve()
    return candidates[0].resolve()


def invoke_logged(
    cmd: list[str],
    cwd: Path,
    stdout_path: Path,
    stderr_path: Path,
    dry_run: bool,
    env: dict[str, str] | None = None,
) -> int:
    stdout_path.parent.mkdir(parents=True, exist_ok=True)
    if dry_run:
        print("DRYRUN " + command_text(cmd))
        stdout_path.write_text("DRYRUN " + command_text(cmd) + "\n", encoding="utf-8")
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


def build_tracegen_cmd(
    python_path: str,
    tracegen_script: Path,
    trace_out_dir: Path,
    model: str,
    spec_path: Path,
    attention_capture: str,
    device: str,
    torch_threads: int,
) -> list[str]:
    return [
        python_path,
        str(tracegen_script),
        "--out-dir",
        str(trace_out_dir),
        "--mode",
        "suite",
        "--model",
        model,
        "--spec-file",
        str(spec_path),
        "--query-summary-profile",
        "stable",
        "--service-criticality-profile",
        "current",
        "--attention-capture",
        attention_capture,
        "--device",
        device,
        "--torch-threads",
        str(torch_threads),
    ]


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
        "-SkipLatestAlias",
    ]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=ROOT)
    parser.add_argument("--plan-csv", type=Path, default=None)
    parser.add_argument("--python-path", default="")
    parser.add_argument("--powershell-path", default="powershell.exe" if os.name == "nt" else "pwsh")
    parser.add_argument("--lengths", default="4k,8k,16k")
    parser.add_argument("--models", default="")
    parser.add_argument("--max-cells", type=int, default=0)
    parser.add_argument("--attention-capture", choices=["prefill_and_decode", "decode_only"], default="decode_only")
    parser.add_argument("--device", choices=["cpu", "cuda", "auto"], default="auto")
    parser.add_argument("--torch-threads", type=int, default=1)
    parser.add_argument("--backend-service-cycles", type=int, default=1)
    parser.add_argument("--mem-read-latency", type=int, default=3)
    parser.add_argument("--tracegen-only", action="store_true")
    parser.add_argument("--replay-only", action="store_true")
    parser.add_argument("--force-tracegen", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    project_root = args.project_root.resolve()
    plan_csv = args.plan_csv.resolve() if args.plan_csv else default_plan_csv(project_root)
    python_path = args.python_path or default_python(project_root)

    if not plan_csv.exists():
        raise FileNotFoundError(f"Plan CSV not found: {plan_csv}")
    if not Path(python_path).exists() and python_path != sys.executable:
        raise FileNotFoundError(f"Python path not found: {python_path}")

    tracegen_script = project_root / "software" / "tracegen" / "hf_runtime_tracegen.py"
    eval_script = project_root / "automation" / "run_kiloware_paper_benchmark_eval.ps1"
    if not args.replay_only and not tracegen_script.exists():
        raise FileNotFoundError(f"HF tracegen script not found: {tracegen_script}")
    if not args.tracegen_only and not args.dry_run and not eval_script.exists():
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
        raise RuntimeError(f"No longctx cells selected from {plan_csv}")

    plan_dir = plan_csv.parent
    replay_report_root = plan_dir / "text_replay_reports"
    runner_log_dir = plan_dir / "text_runner_logs"
    runner_log_dir.mkdir(parents=True, exist_ok=True)
    run_stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    status_csv = runner_log_dir / f"longctx_text_runner_status_{run_stamp}.csv"
    status_rows: list[dict[str, Any]] = []

    env = os.environ.copy()
    old_report_root = env.get("KILOWARE_BENCHMARK_EVAL_REPORT_ROOT", "")
    env["KILOWARE_BENCHMARK_EVAL_REPORT_ROOT"] = str(replay_report_root)

    for cell in selected:
        model = str(cell["model_alias"])
        length = str(cell["length_label"])
        spec_path = resolve_artifact_path(str(cell["spec_path"]), project_root, plan_dir)
        trace_out_dir = resolve_artifact_path(str(cell["tracegen_out_dir"]), project_root, plan_dir)
        trace_manifest = resolve_artifact_path(str(cell["tracegen_manifest"]), project_root, plan_dir)
        cell_log_dir = runner_log_dir / length / model
        cell_log_dir.mkdir(parents=True, exist_ok=True)
        print(f"LONGCTX_CELL_START length={length} model={model}")

        trace_status = "SKIPPED"
        replay_status = "SKIPPED"
        replay_run_dir = ""
        replay_summary = ""
        trace_stdout = cell_log_dir / "tracegen_stdout.log"
        trace_stderr = cell_log_dir / "tracegen_stderr.log"
        replay_stdout = cell_log_dir / "replay_stdout.log"
        replay_stderr = cell_log_dir / "replay_stderr.log"

        if not args.replay_only:
            need_tracegen = args.force_tracegen or not trace_manifest.exists()
            if need_tracegen:
                trace_out_dir.mkdir(parents=True, exist_ok=True)
                trace_cmd = build_tracegen_cmd(
                    python_path=python_path,
                    tracegen_script=tracegen_script,
                    trace_out_dir=trace_out_dir,
                    model=model,
                    spec_path=spec_path,
                    attention_capture=args.attention_capture,
                    device=args.device,
                    torch_threads=args.torch_threads,
                )
                trace_exit = invoke_logged(trace_cmd, project_root, trace_stdout, trace_stderr, args.dry_run, env=env)
                if args.dry_run:
                    trace_status = "DRYRUN"
                elif trace_exit != 0:
                    trace_status = f"FAIL_EXIT_{trace_exit}"
                    print(f"LONGCTX_TRACEGEN_FAIL length={length} model={model} exit={trace_exit}", file=sys.stderr)
                elif not trace_manifest.exists():
                    trace_status = "FAIL_NO_MANIFEST"
                    print(f"LONGCTX_TRACEGEN_NO_MANIFEST length={length} model={model} manifest={trace_manifest}", file=sys.stderr)
                else:
                    trace_status = "PASS"
            else:
                trace_status = "PASS_EXISTING"

        if not args.tracegen_only and (args.dry_run or trace_manifest.exists()):
            replay_cmd = build_replay_cmd(
                powershell_path=args.powershell_path,
                eval_script=eval_script,
                project_root=project_root,
                python_path=python_path,
                model=model,
                spec_path=spec_path,
                trace_manifest=trace_manifest,
                backend_service_cycles=args.backend_service_cycles,
                mem_read_latency=args.mem_read_latency,
            )
            replay_exit = invoke_logged(replay_cmd, project_root, replay_stdout, replay_stderr, args.dry_run, env=env)
            if args.dry_run:
                replay_status = "DRYRUN"
            elif replay_exit != 0:
                replay_status = f"FAIL_EXIT_{replay_exit}"
                print(f"LONGCTX_REPLAY_FAIL length={length} model={model} exit={replay_exit}", file=sys.stderr)
            else:
                replay_run_dir, replay_summary, replay_status = parse_replay_stdout(replay_stdout)

        status_rows.append(
            {
                "timestamp": datetime.now().isoformat(timespec="seconds"),
                "length_label": length,
                "model_alias": model,
                "workload_rows": cell.get("workload_rows", ""),
                "spec_path": str(spec_path),
                "tracegen_manifest": str(trace_manifest),
                "tracegen_status": trace_status,
                "replay_status": replay_status,
                "replay_run_dir": replay_run_dir,
                "replay_summary": replay_summary,
                "tracegen_stdout": str(trace_stdout),
                "tracegen_stderr": str(trace_stderr),
                "replay_stdout": str(replay_stdout),
                "replay_stderr": str(replay_stderr),
                "backend_service_cycles": args.backend_service_cycles,
                "mem_read_latency": args.mem_read_latency,
            }
        )
        write_status(status_csv, status_rows)
        print(f"LONGCTX_CELL_DONE length={length} model={model} tracegen={trace_status} replay={replay_status}")

    if old_report_root:
        env["KILOWARE_BENCHMARK_EVAL_REPORT_ROOT"] = old_report_root
    print("LONGCTX_TEXT_RUNNER_STATUS_CSV=" + str(status_csv))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
