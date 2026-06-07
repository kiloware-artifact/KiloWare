# KiloWare 32/32 Authority Freeze (2026-06-06)

This directory is the authority snapshot for the current 32-line L1 / 32-line
L2 long-context paper revision. It supersedes the earlier 2026-06-04 long-context
freeze as the source for the paper's headline numbers. The 2026-06-04 package
remains an archive of the pre-32/32 mainline.

## Scope

- Main replay point: L1/L2 = 32/32.
- Matched comparison: `fpga_h2o_plus_service_cvr_group_fill_v251` vs.
  `fpga_kiloscore_hv_opt5_global_winner`.
- Replay coverage: four text models x four prompt lengths (4K, 8K, 16K, 32K)
  x 27 replay instances = 432 rows.
- Latency metric: cycle-level RTL simulation with the serialized replay driver
  and a parameterized backend model.
- QoR: VCU128 out-of-context post-route receipts at L1/L2 = 32/32.

## Locked Headline Values

- Strict L1 hit: 23.96% -> 62.11%.
- Hierarchy miss: 33.90% -> 17.55%.
- RTL service latency: 4.023 -> 3.914 cycles/access.
- KiloWare-HV QoR: 20,580 LUTs, WNS +0.288 ns, estimated Fmax 102.965 MHz.
- Matched baseline QoR: 21,576 LUTs, WNS +0.131 ns, estimated Fmax 101.327 MHz.
- Negative hierarchy-miss/backend-read/RTL-latency rows for the selected 32/32
  matched replay: zero.

## Size-Sweep Boundary

`F32_size_sweep.csv` is the completed Qwen2.5-7B representative L1/L2 sweep.
It should be described as a size-dependence and operating-region boundary study,
not as an all-model universal sweep. The all-model result is the separate 432-row
32/32 matched replay.

## GF Interpretation

The 32/32 aggregate shows that adding GF to the H2O-derived CVR baseline is
neutral in the main replay: the H2O + clean-victim row and the CVR+GF matched row
have the same L1 hit, hierarchy miss, RTL cycles, and HBM-read counts. This
supports wording that treats GF as a conservative safe fill protocol, while CVR
and KiloScore drive the measured aggregate gains.

## How to Verify

Run:

```bash
python results/longctx_32_32_authority_freeze_20260606/verify_32_32_authority.py
```

Expected output includes `32/32_AUTHORITY_VERIFY_PASS`.

The file inventory is `MANIFEST.csv`; per-file SHA-256 hashes are in
`SHA256SUMS.csv`.
