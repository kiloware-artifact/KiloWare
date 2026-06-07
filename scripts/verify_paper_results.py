#!/usr/bin/env python3
"""Top-level verifier for the KiloWare anonymous artifact.

This wrapper keeps the reviewer quickstart stable while delegating the actual
checks to the locked 32/32 authority freeze used by the current paper.
"""
from __future__ import annotations

import runpy
from pathlib import Path


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    verifier = (
        root
        / "results"
        / "longctx_32_32_authority_freeze_20260606"
        / "verify_32_32_authority.py"
    )
    if not verifier.exists():
        raise FileNotFoundError(f"Missing authority verifier: {verifier}")
    runpy.run_path(str(verifier), run_name="__main__")


if __name__ == "__main__":
    main()

