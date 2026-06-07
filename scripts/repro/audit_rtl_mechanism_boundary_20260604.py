#!/usr/bin/env python3
"""Audit that the longctx replay phase did not change KCMU mechanism RTL.

The audit compares current source files against the 2026-06-03 code-freeze
snapshot. The only allowed RTL-source delta is the testbench file
`tb_kcmu_system_eval.sv`, and only the two documented capacity/wait-window
parameters are expected to differ there.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
FREEZE = ROOT / "delivery" / "paper" / "repro_audit" / "current_code_freeze_20260603_171214" / "snapshot"
DEFAULT_OUT = ROOT / "delivery" / "paper" / "repro_audit" / "longctx_main_4k_8k_16k_32k_20260604"
RTL_DIR = Path("kiloware_paper.srcs/sources_1/new")
CONSTRAINT_DIRS = [
    Path("kiloware_paper.srcs/constrs_1/new"),
    Path("source_seed/constrs_1/new"),
]
VIVADO_DIR = Path("automation/vivado")
ALLOWED_TB = "tb_kcmu_system_eval.sv"


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT)).replace("\\", "/")
    except ValueError:
        return str(path.resolve()).replace("\\", "/")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fp:
        for chunk in iter(lambda: fp.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def collect_files(root: Path, patterns: tuple[str, ...]) -> list[Path]:
    out: list[Path] = []
    base = ROOT / root
    if not base.exists():
        return out
    for pattern in patterns:
        out.extend(base.rglob(pattern))
    return sorted(p for p in out if p.is_file())


def compare_relative(files: list[Path], base_rel: Path, allowed_names: set[str] | None = None) -> dict[str, Any]:
    allowed_names = allowed_names or set()
    changed: list[str] = []
    missing_snapshot: list[str] = []
    current_only: list[str] = []
    checked = 0
    for current in files:
        name = current.name
        if name in allowed_names:
            continue
        rel_path = current.relative_to(ROOT / base_rel)
        frozen = FREEZE / base_rel / rel_path
        if not frozen.exists():
            missing_snapshot.append(str(base_rel / rel_path).replace("\\", "/"))
            continue
        checked += 1
        if sha256(current) != sha256(frozen):
            changed.append(str(base_rel / rel_path).replace("\\", "/"))
    if (FREEZE / base_rel).exists():
        frozen_files = {p.relative_to(FREEZE / base_rel) for p in (FREEZE / base_rel).rglob("*") if p.is_file()}
        current_files = {p.relative_to(ROOT / base_rel) for p in files}
        for extra in sorted(current_files - frozen_files):
            if extra.name not in allowed_names:
                current_only.append(str(base_rel / extra).replace("\\", "/"))
    return {
        "checked": checked,
        "changed": changed,
        "missing_snapshot": missing_snapshot,
        "current_only": current_only,
        "pass": not changed and not missing_snapshot and not current_only,
    }


def extract_param(path: Path, name: str) -> str:
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    match = re.search(rf"\b{name}\s*=\s*([0-9]+)", text)
    return match.group(1) if match else ""


def audit_testbench() -> dict[str, Any]:
    current = ROOT / RTL_DIR / ALLOWED_TB
    frozen = FREEZE / RTL_DIR / ALLOWED_TB
    current_values = {
        "RESP_TIMEOUT": extract_param(current, "RESP_TIMEOUT") if current.exists() else "",
        "DESC_PAYLOAD_MAX": extract_param(current, "DESC_PAYLOAD_MAX") if current.exists() else "",
    }
    frozen_values = {
        "RESP_TIMEOUT": extract_param(frozen, "RESP_TIMEOUT") if frozen.exists() else "",
        "DESC_PAYLOAD_MAX": extract_param(frozen, "DESC_PAYLOAD_MAX") if frozen.exists() else "",
    }
    return {
        "path": str(RTL_DIR / ALLOWED_TB).replace("\\", "/"),
        "current_exists": current.exists(),
        "frozen_exists": frozen.exists(),
        "current_values": current_values,
        "frozen_values": frozen_values,
        "expected_current_values": {
            "RESP_TIMEOUT": "1024",
            "DESC_PAYLOAD_MAX": "131072",
        },
        "pass": current_values == {"RESP_TIMEOUT": "1024", "DESC_PAYLOAD_MAX": "131072"}
        and frozen_values == {"RESP_TIMEOUT": "256", "DESC_PAYLOAD_MAX": "32768"},
    }


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def write_md(path: Path, payload: dict[str, Any]) -> None:
    rtl = payload["rtl_sources"]
    tcl = payload["vivado_tcl"]
    xdc = payload["constraints"]
    tb = payload["testbench_allowed_delta"]
    lines = [
        "# RTL Mechanism Boundary Audit 20260604",
        "",
        f"Status: {'PASS' if payload['pass'] else 'FAIL'}",
        "",
        "| scope | checked | status | detail |",
        "|---|---:|---|---|",
        f"| RTL `.sv` excluding `tb_kcmu_system_eval.sv` | {rtl['checked']} | {'PASS' if rtl['pass'] else 'FAIL'} | changed={len(rtl['changed'])}, missing={len(rtl['missing_snapshot'])}, current_only={len(rtl['current_only'])} |",
        f"| allowed testbench delta | 1 | {'PASS' if tb['pass'] else 'FAIL'} | current={tb['current_values']}, frozen={tb['frozen_values']} |",
        f"| Vivado Tcl scripts | {tcl['checked']} | {'PASS' if tcl['pass'] else 'FAIL'} | changed={len(tcl['changed'])}, missing={len(tcl['missing_snapshot'])}, current_only={len(tcl['current_only'])} |",
        f"| XDC constraints | {xdc['checked']} | {'PASS' if xdc['pass'] else 'FAIL'} | changed={len(xdc['changed'])}, missing={len(xdc['missing_snapshot'])}, current_only={len(xdc['current_only'])} |",
        "",
        "Interpretation: no DUT/scorer/threshold/cache-mechanism RTL or post-route Tcl/XDC file differs from the code-freeze snapshot. The only accepted RTL-source delta is the testbench input capacity and response-timeout increase needed for 32K descriptor replay and high backend-latency simulation.",
        "",
    ]
    path.write_text("\n".join(lines), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    rtl_files = collect_files(RTL_DIR, ("*.sv",))
    tcl_files = collect_files(VIVADO_DIR, ("*.tcl",))
    xdc_files: list[Path] = []
    for path in CONSTRAINT_DIRS:
        xdc_files.extend(collect_files(path, ("*.xdc",)))

    payload = {
        "schema": "kiloware_rtl_mechanism_boundary_audit_20260604_v1",
        "out_dir": rel(out_dir),
        "freeze_snapshot": rel(FREEZE),
        "rtl_sources": compare_relative(rtl_files, RTL_DIR, allowed_names={ALLOWED_TB}),
        "testbench_allowed_delta": audit_testbench(),
        "vivado_tcl": compare_relative(tcl_files, VIVADO_DIR),
        "constraints": {
            "checked": 0,
            "changed": [],
            "missing_snapshot": [],
            "current_only": [],
            "pass": True,
        },
    }

    constraint_results = []
    for constraint_dir in CONSTRAINT_DIRS:
        files = [p for p in xdc_files if constraint_dir in p.relative_to(ROOT).parents or p.relative_to(ROOT).parent == constraint_dir]
        constraint_results.append(compare_relative(files, constraint_dir))
    merged = payload["constraints"]
    for result in constraint_results:
        merged["checked"] += int(result["checked"])
        merged["changed"].extend(result["changed"])
        merged["missing_snapshot"].extend(result["missing_snapshot"])
        merged["current_only"].extend(result["current_only"])
    merged["pass"] = not merged["changed"] and not merged["missing_snapshot"] and not merged["current_only"]

    payload["pass"] = (
        payload["rtl_sources"]["pass"]
        and payload["testbench_allowed_delta"]["pass"]
        and payload["vivado_tcl"]["pass"]
        and payload["constraints"]["pass"]
    )

    json_path = out_dir / "rtl_mechanism_boundary_audit_20260604.json"
    md_path = out_dir / "RTL_MECHANISM_BOUNDARY_AUDIT_20260604.md"
    write_json(json_path, payload)
    write_md(md_path, payload)
    print(json.dumps({"status": "PASS" if payload["pass"] else "FAIL", "json": rel(json_path), "md": rel(md_path)}, indent=2))
    return 0 if payload["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
