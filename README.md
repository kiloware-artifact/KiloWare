# KiloWare Artifact

Anonymous review artifact for:

> KiloWare: A Lossless FPGA KV-Cache Memory Hierarchy for Long-Context Inference

Repository URL used by the paper:

`https://github.com/kiloware-artifact/KiloWare`

This snapshot contains the paper-facing RTL subset, frozen descriptor traces,
paper-result CSVs, final figure assets, and a quick verifier for the headline
numbers used by the submission. It intentionally does not include model
weights, Vivado/xsim working directories, waveforms, HuggingFace caches, paper
TeX sources, historical exploratory RTL wrappers, or any author-identifying
material.

## Start Here

Download or clone the whole repository. Individual files are not meant to be
downloaded one by one because the quick verifier reads the locked result tree
and the paper-policy map points into the RTL tree.

If you only want to check the paper's headline numbers, run:

```bash
python scripts/verify_paper_results.py
```

If you want to inspect the main KiloWare RTL, open these files first:

- `rtl/POLICY_MAP.md`: maps each paper policy row to the RTL/replay config.
- `rtl/wrappers/kcmu_parameterized_paper_top.sv`: paper-facing top wrapper for
  the selected KiloWare-HV configuration path.
- `rtl/core/kcmu_kiloscore_native.sv`: KiloScore-HV scorer logic.
- `rtl/core/kcmu_l2_ctrl.sv`: replacement/admission, CVR, and GF integration.
- `rtl/tb/tb_kcmu_system_eval.sv`: trace-driven replay testbench and config
  macros.

The selected KiloWare-HV config ID in the frozen results is
`fpga_kiloscore_hv_opt5_global_winner`; the matched baseline config ID is
`fpga_h2o_plus_service_cvr_group_fill_v251`.

## Quick Check

From the repository root:

```bash
python scripts/verify_paper_results.py
```

Expected output:

```text
32/32_AUTHORITY_VERIFY_PASS
rows=432
matched_l1=23.96 kw_l1=62.11
matched_miss=33.90 kw_miss=17.55
matched_cycles=4.023 kw_cycles=3.914
qor_matched_lut=21576 qor_kw_lut=20580
```

## Included Files

- `rtl/`: curated SystemVerilog KCMU source, paper-facing wrappers,
  trace-driven testbenches, and small constraint files. See `rtl/README_RTL.md`
  and `rtl/POLICY_MAP.md`.
- `traces/`: frozen long-context descriptor trace archives:
  - `kiloware_longctx_text_tracegen_20260603.tar.gz` for 4K/8K/16K.
  - `kiloware_longctx32_text_tracegen_20260604.tar.gz` for 32K.
  - adjacent `.sha256` files copied from the trace-generation host.
- `results/longctx_32_32_authority_freeze_20260606/`: locked 32-line L1 /
  32-line L2 result freeze used by the current paper.
- `scripts/`: selected scripts for verification, trace generation provenance,
  result aggregation, and final paper figure data.
- `paper_figures/`: final anonymous figure assets used by the paper, including
  the current KV-pressure motivation figure.
- `docs/`: concise reproducibility and hardware-boundary notes.
- `MANIFEST.csv` and `SHA256SUMS.txt`: inventory and checksum ledger for this
  exact upload tree.

## Main Numbers Covered

The paper's current headline uses the 32-line L1 / 32-line L2 operating point
and matched scorer isolation:

- baseline: matched KCMU with H2O-derived lossless score metadata.
- KiloWare-HV: same CVR/GF KCMU contracts with KiloScore-HV.

Across four language models, four context lengths (4K/8K/16K/32K), and 432
replay rows, the included freeze reports:

- strict L1 hit rate: `23.96% -> 62.11%`
- hierarchy miss rate: `33.90% -> 17.55%`
- serialized RTL service time: `4.023 -> 3.914 cycles/access`
- selected KiloWare-HV QoR: `20,580 LUT`, `WNS +0.288 ns`, `102.965 MHz`

These are trace-driven replay and cycle-level RTL simulation results with a
parameterized backend model. They are not FPGA-board measurements, real-HBM
measurements, or end-to-end model-accuracy claims.

## Check File Integrity

Linux/macOS:

```bash
sha256sum -c SHA256SUMS.txt
```

Windows PowerShell:

```powershell
Get-FileHash -Algorithm SHA256 .\traces\kiloware_longctx_text_tracegen_20260603.tar.gz
Get-FileHash -Algorithm SHA256 .\traces\kiloware_longctx32_text_tracegen_20260604.tar.gz
```

## Inspect Trace Archives

```bash
tar -tzf traces/kiloware_longctx_text_tracegen_20260603.tar.gz | head
tar -tzf traces/kiloware_longctx32_text_tracegen_20260604.tar.gz | head
```

The first archive contains 4K/8K/16K text traces; the second contains 32K text
traces generated later as the long-context stress setting.

## More Detail

- `ARTIFACT.md`: artifact guide and expected quick-check behavior.
- `docs/REPRODUCE.md`: practical reproduction tiers and exact files to inspect.
- `docs/TRACES.md`: trace archive boundaries.
- `docs/HARDWARE_NOTES.md`: RTL/QoR and backend-model boundary.
- `docs/PAPER_FIGURES.md`: final figure asset inventory.
