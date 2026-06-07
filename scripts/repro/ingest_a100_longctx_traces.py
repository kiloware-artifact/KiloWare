#!/usr/bin/env python3
"""Ingest verified A100 long-context traces into a replay result directory.

This script does not generate traces and does not run RTL replay. It stages the
already-verified A100 trace artifacts into the longctx replay directory layout,
reuses the local 4K/8K/16K benchmark specs, and creates 32K proxy specs for
prebuilt-trace replay. The prebuilt trace manifests remain the authoritative
source for 32K replay workloads.
"""

from __future__ import annotations

import argparse
import csv
import json
import shutil
import statistics
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_TRACE_ROOT = ROOT / "delivery" / "paper" / "trace_from_A100" / "_check_extract"
DEFAULT_SOURCE_MAIN = ROOT / "delivery" / "paper" / "repro_audit" / "longctx_main_4k_8k_16k_20260603"
DEFAULT_OUT = ROOT / "delivery" / "paper" / "repro_audit" / "longctx_main_4k_8k_16k_32k_20260604"
BASELINE_CFG = "fpga_h2o_plus_service_cvr_group_fill_v251"
HV_CFG = "fpga_kiloscore_hv_opt5_global_winner"
MODELS = [
    "qwen2p5_7b_instruct",
    "mistral_7b_instruct_v0p3",
    "llama3p1_8b_instruct",
    "qwen2p5_14b_instruct",
]
LENGTH_ORDER = {"4k": 0, "8k": 1, "16k": 2, "32k": 3}


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT)).replace("\\", "/")
    except ValueError:
        return str(path.resolve()).replace("\\", "/")


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as fp:
        return list(csv.DictReader(fp))


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        raise ValueError(f"no rows for {path}")
    with path.open("w", newline="", encoding="utf-8") as fp:
        writer = csv.DictWriter(fp, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def copytree_fresh(src: Path, dst: Path) -> None:
    if not src.exists():
        raise FileNotFoundError(src)
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)


def grouped_summary(rows: list[dict[str, str]]) -> list[dict[str, Any]]:
    by_key: dict[tuple[str, str], list[int]] = {}
    for row in rows:
        by_key.setdefault((row["model_alias"], row["length_label"]), []).append(int(row["actual_prompt_tokens"]))
    out: list[dict[str, Any]] = []
    for (model, length), vals in sorted(by_key.items(), key=lambda item: (LENGTH_ORDER.get(item[0][1], 99), item[0][0])):
        out.append(
            {
                "model_alias": model,
                "length_label": length,
                "workload_rows": len(vals),
                "min_prompt_tokens": min(vals),
                "median_prompt_tokens": statistics.median(vals),
                "max_prompt_tokens": max(vals),
            }
        )
    return out


def build_32k_proxy_specs(out_dir: Path, rows32: list[dict[str, str]]) -> None:
    rows_by_model: dict[str, list[dict[str, str]]] = {}
    for row in rows32:
        rows_by_model.setdefault(row["model_alias"], []).append(row)
    for model in MODELS:
        manifest_rel = f"text_tracegen/32k/{model}/manifest.json"
        manifest_path = out_dir / manifest_rel
        if not manifest_path.exists():
            raise FileNotFoundError(manifest_path)
        workloads = []
        for row in rows_by_model.get(model, []):
            workloads.append(
                {
                    "name": row["workload"],
                    "max_new_tokens": int(row["decode_tokens"]),
                    "metadata": {
                        "model_alias": model,
                        "length_label": "32k",
                        "task_type": row["task"],
                        "original_workload": row["original_workload"],
                        "actual_prompt_tokens": int(row["actual_prompt_tokens"]),
                        "target_prompt_tokens": int(row["target_prompt_tokens"]),
                        "prebuilt_trace_manifest": manifest_rel,
                    },
                }
            )
        payload = {
            "schema": "kiloware_longctx_prebuilt_replay_proxy_spec_v1",
            "benchmark": f"longctx_32k_prebuilt_{model}",
            "model": model,
            "source": "A100 prebuilt trace manifest; prompts are not needed for local replay",
            "prebuilt_trace_manifest": manifest_rel,
            "workloads": workloads,
        }
        write_json(out_dir / "specs" / "32k" / f"{model}_32k_all_tasks.json", payload)


def build_execution_plan(out_dir: Path, summary_rows: list[dict[str, str]]) -> None:
    plan_rows: list[dict[str, Any]] = []
    for row in grouped_summary(summary_rows):
        model = row["model_alias"]
        length = row["length_label"]
        spec_path = out_dir / "specs" / length / f"{model}_{length}_all_tasks.json"
        trace_out = out_dir / "text_tracegen" / length / model
        manifest = trace_out / "manifest.json"
        plan_rows.append(
            {
                **row,
                "spec_path": rel(spec_path),
                "tracegen_out_dir": rel(trace_out),
                "tracegen_manifest": rel(manifest),
                "tracegen_status": "A100_PREBUILT_VERIFIED",
                "replay_command_template": (
                    f"& '{ROOT / 'automation' / 'run_kiloware_paper_benchmark_eval.ps1'}' "
                    f"-ProjectRoot '{ROOT}' -PythonPath '{ROOT / '.venv-ml' / 'Scripts' / 'python.exe'}' "
                    f"-Model '{model}' -BenchmarkManifest '{spec_path}' "
                    f"-PrebuiltTraceManifest '{manifest}' -Configs '{BASELINE_CFG},{HV_CFG}' "
                    f"-PrimaryCompareConfigOverride '{BASELINE_CFG}' -BackendServiceCycles 1 "
                    f"-MemReadLatency 3 -SkipLatestAlias"
                ),
            }
        )
    write_csv(out_dir / "longctx_text_execution_plan.csv", plan_rows)


def write_readiness_note(out_dir: Path, summary_rows: list[dict[str, str]]) -> None:
    grouped = grouped_summary(summary_rows)
    total_rows = sum(int(row["workload_rows"]) for row in grouped)
    lines = [
        "# A100 Longctx Trace Ingest Readiness",
        "",
        "Scope: staging of verified A100 prebuilt descriptor traces for local RTL replay.",
        "",
        f"- Result root: `{rel(out_dir)}`",
        f"- Cells: `{len(grouped)}`",
        f"- Workload rows: `{total_rows}`",
        f"- Matched pair: `{BASELINE_CFG}` vs `{HV_CFG}`",
        "- Trace generation: not rerun locally; using verified A100 prebuilt manifests.",
        "- 32K specs: proxy specs for prebuilt replay only; the prebuilt trace manifest is authoritative.",
        "",
        "| length | model | rows | prompt min | prompt median | prompt max |",
        "|---|---|---:|---:|---:|---:|",
    ]
    for row in grouped:
        lines.append(
            "| {length_label} | {model_alias} | {workload_rows} | {min_prompt_tokens} | {median_prompt_tokens} | {max_prompt_tokens} |".format(
                **row
            )
        )
    lines.extend(
        [
            "",
            "Next gate: run one 4K cell replay and check `hit_miss_amat_summary.csv` contains formula AMAT plus RTL measured latency fields.",
        ]
    )
    (out_dir / "P0_A100_TRACE_INGEST_READINESS_20260604_CN.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def ingest(args: argparse.Namespace) -> None:
    out_dir = args.out_dir.resolve()
    trace_root = args.trace_root.resolve()
    source_main = args.source_main.resolve()

    out_dir.mkdir(parents=True, exist_ok=True)
    for length in ("4k", "8k", "16k"):
        copytree_fresh(source_main / "specs" / length, out_dir / "specs" / length)
        copytree_fresh(trace_root / "longctx" / "text_tracegen" / length, out_dir / "text_tracegen" / length)
    copytree_fresh(trace_root / "longctx32" / "text_tracegen" / "32k", out_dir / "text_tracegen" / "32k")

    rows_main = read_csv(source_main / "longctx_spec_summary.csv")
    rows32 = read_csv(trace_root / "longctx32" / "longctx32_spec_summary.csv")
    summary_rows = rows_main + rows32
    write_csv(out_dir / "longctx_spec_summary.csv", summary_rows)
    write_csv(out_dir / "longctx_spec_summary_4k_8k_16k.csv", rows_main)
    write_csv(out_dir / "longctx32_spec_summary.csv", rows32)

    build_32k_proxy_specs(out_dir, rows32)
    build_execution_plan(out_dir, summary_rows)
    write_readiness_note(out_dir, summary_rows)

    for src, name in [
        (trace_root / "longctx" / "text_tracegen_sha256sums.txt", "a100_longctx_text_tracegen_sha256sums.txt"),
        (trace_root / "longctx32" / "text_tracegen_sha256sums.txt", "a100_longctx32_text_tracegen_sha256sums.txt"),
        (trace_root.parent / "kiloware_longctx_text_tracegen_20260603.tar.gz.sha256", "a100_longctx_archive.sha256"),
        (trace_root.parent / "kiloware_longctx32_text_tracegen_20260604.tar.gz.sha256", "a100_longctx32_archive.sha256"),
    ]:
        if src.exists():
            shutil.copy2(src, out_dir / name)

    manifest_count = len(list((out_dir / "text_tracegen").rglob("manifest.json")))
    print(f"A100_LONGCTX_INGEST_OUT={out_dir}")
    print(f"A100_LONGCTX_INGEST_MANIFESTS={manifest_count}")
    print(f"A100_LONGCTX_INGEST_ROWS={len(summary_rows)}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trace-root", type=Path, default=DEFAULT_TRACE_ROOT)
    parser.add_argument("--source-main", type=Path, default=DEFAULT_SOURCE_MAIN)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    ingest(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
