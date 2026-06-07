#!/usr/bin/env python3
"""Verify the 32/32 authority snapshot used by the paper draft.

This is an audit verifier, not a simulator runner. It checks that the CSV files
staged in this authority freeze contain the headline values used by the paper:
the 432-row 32/32 matched replay, the Table 1 control rows, the QoR receipts,
and the representative size-sweep boundary table.
"""

from __future__ import annotations

import csv
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"


def read_csv(name: str) -> list[dict[str, str]]:
    path = DATA / name
    if not path.exists():
        raise AssertionError(f"missing {path}")
    with path.open(newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def find_row(rows: list[dict[str, str]], key: str, value: str) -> dict[str, str]:
    matches = [r for r in rows if r.get(key) == value]
    if len(matches) != 1:
        raise AssertionError(f"expected one row with {key}={value}, found {len(matches)}")
    return matches[0]


def assert_close(actual: str, expected: float, tol: float = 0.005, label: str = "") -> None:
    value = float(actual)
    if not math.isclose(value, expected, abs_tol=tol):
        raise AssertionError(f"{label}: expected {expected}, got {value}")


def assert_equal(actual: str, expected: str, label: str = "") -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")


def main() -> None:
    # Paper Table 1 and abstract headline values.
    table1 = read_csv("table1_32_32_full_preview.csv")
    matched = find_row(table1, "label", "CVR+GF baseline (matched)")
    kw = find_row(table1, "label", "KiloWare-HV")
    victim = find_row(table1, "label", "H2O + victim cache")

    assert_close(matched["l1_hit_pct"], 23.96, label="matched L1 hit")
    assert_close(matched["hierarchy_miss_pct"], 33.90, label="matched hierarchy miss")
    assert_close(matched["latency_cycles"], 4.023, label="matched RTL cycles")
    assert_equal(matched["hbm_reads"], "449915", "matched HBM reads")

    assert_close(kw["l1_hit_pct"], 62.11, label="KiloWare L1 hit")
    assert_close(kw["hierarchy_miss_pct"], 17.55, label="KiloWare hierarchy miss")
    assert_close(kw["latency_cycles"], 3.914, label="KiloWare RTL cycles")
    assert_equal(kw["hbm_reads"], "232843", "KiloWare HBM reads")

    # GF is neutral in the matched H2O-derived aggregate; this supports the
    # paper wording that downgrades GF to a safe fill protocol.
    for col in ["l1_hit_pct", "hierarchy_miss_pct", "latency_cycles", "hbm_reads"]:
        assert_equal(matched[col], victim[col], f"GF-neutral aggregate {col}")

    # 432-row replay authority line and zero negative rows.
    replay = read_csv("main32_replay_qor_review_20260605.csv")
    all_row = find_row(replay, "section", "all")
    assert_equal(all_row["rows"], "432", "all replay rows")
    assert_close(all_row["base_l1_hit_pct"], 23.958558, tol=0.0005, label="all base L1")
    assert_close(all_row["kw_l1_hit_pct"], 62.113699, tol=0.0005, label="all KW L1")
    assert_close(all_row["base_hierarchy_miss_pct"], 33.902405, tol=0.0005, label="all base miss")
    assert_close(all_row["kw_hierarchy_miss_pct"], 17.545389, tol=0.0005, label="all KW miss")
    assert_close(all_row["base_latency_cycles"], 4.023494, tol=0.0005, label="all base cycles")
    assert_close(all_row["kw_latency_cycles"], 3.914359, tol=0.0005, label="all KW cycles")
    assert_close(all_row["latency_gain_pct"], 2.708864, tol=0.0005, label="all latency gain")
    assert_equal(all_row["negative_latency_rows"], "0", "negative latency rows")

    # Representative size sweep. The paper must describe this as a completed
    # Qwen2.5-7B sweep plus all-model 32/32 replay, not as a universal sweep.
    sweep = read_csv("F32_size_sweep.csv")
    assert_equal(str(len(sweep)), "6", "size sweep row count")
    selected = find_row(sweep, "size", "32/32")
    assert_equal(selected["rows"], "108", "32/32 representative sweep rows")
    assert_close(selected["hier_miss_reduction_pp"], 14.9136, tol=0.0005, label="32/32 sweep miss reduction")
    assert_close(selected["latency_gain_pct"], 2.4753, tol=0.0005, label="32/32 sweep latency gain")
    assert_equal(selected["negative_latency_rows"], "0", "32/32 sweep negative latency rows")

    # QoR receipts for the matched pair.
    qor = read_csv("table1_32_32_qor_review_20260605.csv")
    qmatched = find_row(qor, "label", "CVR+GF baseline (matched)")
    qkw = find_row(qor, "label", "KiloWare-HV")
    assert_equal(qmatched["status"], "PASS", "matched QoR status")
    assert_equal(qkw["status"], "PASS", "KiloWare QoR status")
    assert_close(qmatched["wns_ns"], 0.131, tol=0.0005, label="matched WNS")
    assert_close(qkw["wns_ns"], 0.288, tol=0.0005, label="KiloWare WNS")
    assert_equal(qmatched["lut"], "21576", "matched LUT")
    assert_equal(qkw["lut"], "20580", "KiloWare LUT")

    print("32/32_AUTHORITY_VERIFY_PASS")
    print("rows=432")
    print("matched_l1=23.96 kw_l1=62.11")
    print("matched_miss=33.90 kw_miss=17.55")
    print("matched_cycles=4.023 kw_cycles=3.914")
    print("qor_matched_lut=21576 qor_kw_lut=20580")


if __name__ == "__main__":
    main()
