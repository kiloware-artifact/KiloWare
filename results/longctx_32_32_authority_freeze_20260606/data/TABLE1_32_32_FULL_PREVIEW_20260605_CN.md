# Table 1 32/32 Full Preview

- Scope: 4 models x 4 context lengths x 27 replay instances = 432 rows, L1/L2 = 32/32.
- Performance source: xsim RTL replay, testbench-only KCMU_TB_L1_LINES=32 KCMU_TB_L2_LINES=32.
- QoR source: VCU128 OOC post-route run for each Table 1 config at L1/L2 = 32/32.
- Status: 16/16 control cells PASS; matched baseline and KiloWare-HV reused from the locked main32 replay.
- No DUT/scorer/threshold/trace edits were made for these measurements.

| Config | Scorer | CVR | GF | L1 hit (%) | Hier. miss (%) | Latency (cycles) | HBM reads | LUT | WNS (ns) | Fmax (MHz) |
|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| Traditional cache | - | - | - | 24.29 | 47.78 | 4.163 | 653758 | 16250 | 0.465 | 104.877 |
| Pure H2O | H2O | - | - | 24.29 | 51.33 | 4.186 | 695338 | 19224 | 0.344 | 103.563 |
| H2O + victim cache | H2O | Y | - | 23.96 | 33.90 | 4.023 | 449915 | 21246 | 0.220 | 102.249 |
| H2O + guarded prefetch | H2O | - | - | 23.98 | 51.13 | 4.143 | 680524 | 19546 | 0.029 | 100.291 |
| CVR+GF baseline (matched) | H2O | Y | Y | 23.96 | 33.90 | 4.023 | 449915 | 21576 | 0.131 | 101.327 |
| KiloWare-HV | KiloScore | Y | Y | 62.11 | 17.55 | 3.914 | 232843 | 20580 | 0.288 | 102.965 |

## Files

- Full preview CSV: delivery\paper\repro_audit\longctx_table1_32_32_perf_20260605\table1_32_32_full_preview.csv
- Performance aggregate CSV: delivery\paper\repro_audit\longctx_table1_32_32_perf_20260605\table1_32_32_perf_aggregate.csv
- Performance per-row CSV: delivery\paper\repro_audit\longctx_table1_32_32_perf_20260605\table1_32_32_perf_per_row.csv
- QoR CSV: delivery\paper\repro_audit\longctx_l1_l2_size_sweep_ext_20260605\main32_preview\table1_32_32_qor_review_20260605.csv
- Control status CSV: delivery\paper\repro_audit\longctx_table1_32_32_perf_20260605\runner_logs\table1_perf_status_20260605_144758.csv
