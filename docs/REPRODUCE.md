# Reproduction Notes

The repository is organized for three reviewer use cases:

1. verify the exact paper numbers quickly;
2. inspect which RTL implements each paper policy;
3. rerun heavier trace/RTL flows locally if the required tools and model
   checkpoints are available.

For the first two use cases, download or clone the whole repository and start
from the commands below. Do not download individual `.sv` or `.csv` files in
isolation.

## Quick Verification

```bash
python scripts/verify_paper_results.py
```

This checks the locked 432-row 32/32 result freeze used by the current paper.

Expected output:

```text
32/32_AUTHORITY_VERIFY_PASS
rows=432
matched_l1=23.96 kw_l1=62.11
matched_miss=33.90 kw_miss=17.55
matched_cycles=4.023 kw_cycles=3.914
qor_matched_lut=21576 qor_kw_lut=20580
```

This is the fastest reproducibility check and requires only Python 3.

## Inspect The Main RTL

Open:

```text
rtl/POLICY_MAP.md
rtl/README_RTL.md
```

The main KiloWare-HV path is:

```text
rtl/wrappers/kcmu_parameterized_paper_top.sv
rtl/core/kcmu_kiloscore_native.sv
rtl/core/kcmu_l2_ctrl.sv
rtl/tb/tb_kcmu_system_eval.sv
```

The matched baseline path is:

```text
rtl/wrappers/policy_h2o_cvr_gf_matched_top.sv
rtl/tb/tb_kcmu_system_eval.sv
```

`rtl/POLICY_MAP.md` maps every Table 1 policy row to its result config ID,
wrapper, replay macro, and core implementation files.

## Inspect Results

Primary result directory:

```text
results/longctx_32_32_authority_freeze_20260606/
```

Important files:

- `VERIFY_OUTPUT.txt`: expected verifier output.
- `AUTHORITY_NOTE_20260606.md`: provenance note.
- `data/table1_32_32_full_preview.csv`: config-level table data.
- `data/extended_aggregate_by_model_size_length.csv`: model/context summary.
- `data/F32_size_sweep.csv`: size-sweep figure data.
- `data/F32_context_summary.csv`: context figure data.
- `data/F32_model_summary.csv`: model-breadth figure data.

The paper figures are included as final PDFs/PNGs under `paper_figures/`.
The small CSVs used to rebuild the final result figures are under
`scripts/paper_figures/`.

## Trace Archives

```text
traces/kiloware_longctx_text_tracegen_20260603.tar.gz
traces/kiloware_longctx32_text_tracegen_20260604.tar.gz
```

These archives contain descriptor traces and runtime metadata, not model
weights. Full regeneration requires local model checkpoints.

## Heavier Rerun Boundary

The repository contains the source and frozen inputs needed to inspect the
paper's claims. A complete trace regeneration requires local model checkpoints,
CUDA-capable GPU inference, and `scripts/tracegen/hf_runtime_tracegen.py`.

A complete cycle-level replay or Vivado/xsim rerun requires a local
simulator/FPGA toolchain and the replay testbench
`rtl/tb/tb_kcmu_system_eval.sv`. Generated Vivado databases, xsim directories,
waveforms, HuggingFace caches, and model weights are intentionally excluded.

The paper's latency evidence is cycle-level RTL service time with a
parameterized backend model; it is not a board-level HBM measurement.
