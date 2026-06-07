# Artifact Guide

This repository is an anonymous review artifact for KiloWare. It is organized
for reviewer inspection rather than for redistributing model weights, complete
tool-generated build databases, or historical RTL exploration branches.

## One-Minute Verification

Run:

```bash
python scripts/verify_paper_results.py
```

The script reads the locked CSVs under:

`results/longctx_32_32_authority_freeze_20260606/`

and checks the current paper headline values:

```text
32/32_AUTHORITY_VERIFY_PASS
rows=432
matched_l1=23.96 kw_l1=62.11
matched_miss=33.90 kw_miss=17.55
matched_cycles=4.023 kw_cycles=3.914
qor_matched_lut=21576 qor_kw_lut=20580
```

## Reproducibility Tiers

1. Quick check: run `scripts/verify_paper_results.py`.
2. Data inspection: inspect `results/.../data/*.csv` and the trace archives.
3. Figure provenance: inspect `paper_figures/` and
   `scripts/paper_figures/`.
4. RTL inspection: inspect `rtl/README_RTL.md` and `rtl/POLICY_MAP.md`, then
   `rtl/core/`, `rtl/wrappers/`, and `rtl/tb/`.
5. Full trace regeneration: requires local model weights and GPU inference; the
   model weights and HuggingFace caches are not redistributed here.
6. Full Vivado/xsim rerun: requires a local FPGA/simulator toolchain; generated
   xsim/Vivado work directories are intentionally excluded.

## Boundaries

This artifact supports the paper's lossless KCMU residency/service claim under
trace-driven replay and cycle-level RTL simulation with a parameterized backend
model. It does not support claims about:

- board-level execution,
- real HBM timing,
- multi-outstanding AXI/HBM throughput,
- end-to-end LLM answer accuracy,
- lossy KV compression,
- model-weight redistribution.

## Anonymity

The upload tree omits paper TeX sources, author metadata, local user paths in
generated PDFs, and private review notes. The included scripts may mention
generic local paths in comments or provenance strings from the original working
tree; these are not author identities and are not needed for the quick check.
