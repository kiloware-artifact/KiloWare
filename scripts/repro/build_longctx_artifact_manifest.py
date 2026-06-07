#!/usr/bin/env python3
"""Build a SHA256 manifest for the current long-context evidence bundle.

The script is intentionally read-only with respect to KiloWare mechanisms and
trace/replay outputs. It hashes the files already present in the longctx bundle
and checks that the archived short-trace/code-freeze directories are still
present and recoverable.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "delivery" / "paper" / "repro_audit" / "longctx_main_4k_8k_16k_32k_20260604"
OLD_FREEZE_DIR = ROOT / "delivery" / "paper" / "repro_audit" / "old_mainline_shorttrace_freeze_20260603_170226"
CODE_FREEZE_DIR = ROOT / "delivery" / "paper" / "repro_audit" / "current_code_freeze_20260603_171214"
CODE_FREEZE_ZIP = CODE_FREEZE_DIR / "kiloware_current_code_freeze_20260603_171214.zip"
CODE_FREEZE_MANIFEST = CODE_FREEZE_DIR / "current_code_freeze_manifest.txt"
EXPECTED_CODE_ZIP_SHA256 = "B70DEB44E7317EC434DC010DA2A397CF02ABADE09000839C39C9B3DF0E82502B"

MANIFEST_OUTPUT_NAMES = {
    "longctx_artifact_manifest.csv",
    "longctx_artifact_manifest.json",
    "LONGCTX_ARTIFACT_MANIFEST_20260603.md",
    "LONGCTX_ARTIFACT_MANIFEST_20260604.md",
}

MANIFEST_FIELDS = [
    "path",
    "bytes",
    "sha256",
    "category",
]


def rel_to_root(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT)).replace("\\", "/")
    except ValueError:
        return str(path.resolve()).replace("\\", "/")


def rel_to_out(path: Path, out_dir: Path) -> str:
    try:
        return str(path.resolve().relative_to(out_dir.resolve())).replace("\\", "/")
    except ValueError:
        return rel_to_root(path)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fp:
        for chunk in iter(lambda: fp.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def count_files(path: Path) -> int:
    if not path.exists():
        return 0
    return sum(1 for p in path.rglob("*") if p.is_file())


def line_count(path: Path) -> int:
    if not path.exists():
        return 0
    with path.open("r", encoding="utf-8-sig", errors="replace") as fp:
        return sum(1 for _ in fp)


def categorize(rel_path: str) -> str:
    parts = rel_path.split("/")
    first = parts[0] if parts else rel_path
    name = parts[-1].lower() if parts else rel_path.lower()
    flat = rel_path.lower()

    if first == "specs":
        return "spec"
    if first == "multimodal_smolvlm_runtime":
        return "smolvlm_runtime"
    if first == "pilot":
        return "pilot"
    if first == "pilot32_replay_reports" or first == "pilot_one_trace_32k_qwen2p5_7b":
        return "pilot32"
    if first == "backend_latency_sweep_reports" or "backend_latency_sweep" in flat:
        return "backend_latency_sweep"
    if first == "multimodal_smolvlm_replay_reports":
        return "smolvlm_replay_reports"
    if first == "tracegen_pilot":
        return "tracegen_pilot"
    if first == "tracegen_smoke":
        return "tracegen_smoke"
    if first == "text_runner_logs":
        return "text_runner_logs"
    if first == "text_tracegen":
        return "text_tracegen"
    if "spec_summary" in flat:
        return "spec_summary"
    if "execution_plan" in flat:
        return "execution_plan"
    if "evidence_audit" in flat or name == "longctx_text_cell_status.csv":
        return "evidence_audit"
    if "result_tables" in flat or name.startswith("workload_summary") or "per_row" in flat or "aggregate" in flat:
        return "result_tables"
    if "strict_verify" in flat:
        return "strict_verify"
    if "latency_probe_summary" in flat:
        return "latency_probe_summary"
    if "formula_vs_rtl" in flat:
        return "formula_vs_rtl"
    if "latency_readiness" in flat:
        return "latency_readiness"
    if "smolvlm_runtime_matched_pair_summary" in flat:
        return "smolvlm_replay_summary"
    if name.startswith("p0_") or name.startswith("p1_") or name.startswith("p4_"):
        return "phase_note"
    if name.startswith("longctx_current_status") or name.startswith("longctx_status_update") or name.startswith("longctx_gpu_runbook"):
        return "status_note"
    return "other"


def discover_files(out_dir: Path) -> list[Path]:
    if not out_dir.exists():
        return []
    files = []
    for path in sorted(out_dir.rglob("*")):
        if not path.is_file():
            continue
        if path.name in MANIFEST_OUTPUT_NAMES:
            continue
        files.append(path)
    return files


def build_manifest_rows(out_dir: Path) -> list[dict[str, Any]]:
    rows = []
    for path in discover_files(out_dir):
        rel_path = rel_to_out(path, out_dir)
        rows.append(
            {
                "path": rel_path,
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
                "category": categorize(rel_path),
            }
        )
    return rows


def manifest_set_sha256(rows: list[dict[str, Any]]) -> str:
    h = hashlib.sha256()
    for row in rows:
        line = f"{row['sha256']}  {row['bytes']}  {row['path']}\n"
        h.update(line.encode("utf-8"))
    return h.hexdigest().upper()


def audit_freezes(expected_code_zip_sha256: str) -> dict[str, Any]:
    zip_exists = CODE_FREEZE_ZIP.exists()
    zip_sha = sha256_file(CODE_FREEZE_ZIP) if zip_exists else None
    return {
        "old_shorttrace_freeze": {
            "path": rel_to_root(OLD_FREEZE_DIR),
            "exists": OLD_FREEZE_DIR.exists(),
            "file_count": count_files(OLD_FREEZE_DIR),
        },
        "current_code_freeze": {
            "path": rel_to_root(CODE_FREEZE_DIR),
            "exists": CODE_FREEZE_DIR.exists(),
            "snapshot_file_count": count_files(CODE_FREEZE_DIR / "snapshot"),
            "manifest_path": rel_to_root(CODE_FREEZE_MANIFEST),
            "manifest_exists": CODE_FREEZE_MANIFEST.exists(),
            "manifest_rows": line_count(CODE_FREEZE_MANIFEST),
            "zip_path": rel_to_root(CODE_FREEZE_ZIP),
            "zip_exists": zip_exists,
            "zip_bytes": CODE_FREEZE_ZIP.stat().st_size if zip_exists else 0,
            "zip_sha256": zip_sha,
            "expected_zip_sha256": expected_code_zip_sha256,
            "zip_sha256_match": zip_sha == expected_code_zip_sha256 if zip_sha else False,
        },
    }


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fp:
        writer = csv.DictWriter(fp, fieldnames=MANIFEST_FIELDS)
        writer.writeheader()
        writer.writerows(rows)


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def write_markdown(path: Path, payload: dict[str, Any]) -> None:
    category_counts = payload["category_counts"]
    freeze = payload["freeze_audit"]
    code = freeze["current_code_freeze"]
    old = freeze["old_shorttrace_freeze"]
    lines = [
        "# KiloWare Longctx Artifact Manifest",
        "",
        f"Date: {payload['date']}",
        "",
        "## Summary",
        "",
        f"- Longctx bundle: `{payload['out_dir']}`",
        f"- Manifested files: {payload['file_count']}",
        f"- Manifested bytes: {payload['total_bytes']}",
        f"- Manifest-set SHA256: `{payload['manifest_set_sha256']}`",
        "",
        "## Category Counts",
        "",
        "| category | files |",
        "|---|---:|",
    ]
    for category, count in sorted(category_counts.items()):
        lines.append(f"| {category} | {count} |")
    lines.extend(
        [
            "",
            "## Freeze Audit",
            "",
            "| item | status | detail |",
            "|---|---|---|",
            f"| old short-trace freeze | {'PASS' if old['exists'] and old['file_count'] > 0 else 'MISSING'} | files={old['file_count']}, path=`{old['path']}` |",
            f"| current code freeze snapshot | {'PASS' if code['exists'] and code['snapshot_file_count'] > 0 else 'MISSING'} | files={code['snapshot_file_count']}, path=`{code['path']}` |",
            f"| current code freeze manifest | {'PASS' if code['manifest_exists'] and code['manifest_rows'] > 0 else 'MISSING'} | rows={code['manifest_rows']}, path=`{code['manifest_path']}` |",
            f"| current code freeze zip | {'PASS' if code['zip_sha256_match'] else 'FAIL'} | bytes={code['zip_bytes']}, sha256=`{code['zip_sha256']}` |",
            "",
            "## Notes",
            "",
            "- The manifest excludes the manifest outputs themselves so reruns remain stable.",
            "- This records artifact identity and freeze recoverability; replay completeness is checked by the strict verifier.",
            "- The 2026-06-04 bundle treats 4K/8K/16K as the complete main matrix and 32K as a documented Qwen7B stress subset.",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--date", default="2026-06-04")
    parser.add_argument("--expected-code-zip-sha256", default=EXPECTED_CODE_ZIP_SHA256)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    out_dir = args.out_dir.resolve()
    rows = build_manifest_rows(out_dir)
    category_counts = dict(Counter(row["category"] for row in rows))
    payload = {
        "out_dir": rel_to_root(out_dir),
        "date": args.date,
        "file_count": len(rows),
        "total_bytes": sum(int(row["bytes"]) for row in rows),
        "manifest_set_sha256": manifest_set_sha256(rows),
        "category_counts": category_counts,
        "freeze_audit": audit_freezes(args.expected_code_zip_sha256.upper()),
        "files": rows,
    }

    csv_path = out_dir / "longctx_artifact_manifest.csv"
    json_path = out_dir / "longctx_artifact_manifest.json"
    compact_date = args.date.replace("-", "")
    md_path = out_dir / f"LONGCTX_ARTIFACT_MANIFEST_{compact_date}.md"
    write_csv(csv_path, rows)
    write_json(json_path, payload)
    write_markdown(md_path, payload)

    status = {
        "manifest_csv": rel_to_root(csv_path),
        "manifest_json": rel_to_root(json_path),
        "manifest_md": rel_to_root(md_path),
        "file_count": payload["file_count"],
        "total_bytes": payload["total_bytes"],
        "manifest_set_sha256": payload["manifest_set_sha256"],
        "code_freeze_zip_sha256_match": payload["freeze_audit"]["current_code_freeze"]["zip_sha256_match"],
    }
    print(json.dumps(status, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
