# Paper Policy Map

The paper and result CSVs retain historical `config` identifiers for
provenance. Public RTL filenames in this artifact use descriptive names instead
of internal version numbers.

## Table 1 / Main Policy Rows

| Paper row | Result config ID | Scorer | CVR | GF | Public RTL / code location |
|---|---|---:|---:|---:|---|
| Traditional cache | `baseline` | No | No | No | Replay config in `tb/tb_kcmu_system_eval.sv` under `KCMU_CFG_BASELINE`; shared cache datapath in `core/`. |
| H2O-score cache | `fpga_true_h2o_pure` | H2O-derived lossless metadata | No | No | `wrappers/policy_h2o_lossless_top.sv`; replay macro `KCMU_CFG_FPGA_TRUE_H2O_PURE`. |
| H2O + clean-victim retention | `fpga_h2o_plus_service_clean_victim_cache16_v245` | H2O-derived lossless metadata | Yes | No | `wrappers/policy_h2o_cvr_top.sv`; replay macro `KCMU_CFG_FPGA_H2O_PLUS_SERVICE_CLEAN_VICTIM_CACHE16_V245`. |
| H2O + strict miss prefetch | `fpga_h2o_plus_service_strict_miss_prefetch_v206` | H2O-derived lossless metadata | No | No | Replay config in `tb/tb_kcmu_system_eval.sv` under `KCMU_CFG_FPGA_H2O_PLUS_SERVICE_STRICT_MISS_PREFETCH_V206`; prefetch controls are wired through `TRUE_H2O_*PREFETCH*` parameters into the shared core. This is a strict miss-prefetch control, not GF. |
| CVR+GF baseline (matched) | `fpga_h2o_plus_service_cvr_group_fill_v251` | H2O-derived lossless metadata | Yes | Yes | `wrappers/policy_h2o_cvr_gf_matched_top.sv`; replay macro `KCMU_CFG_FPGA_H2O_PLUS_SERVICE_CVR_GROUP_FILL_V251`. |
| KiloWare-HV | `fpga_kiloscore_hv_opt5_global_winner` | KiloScore-HV | Yes | Yes | `wrappers/kcmu_parameterized_paper_top.sv` plus replay macro `KCMU_CFG_FPGA_KILOSCORE_HV_OPT5_GLOBAL_WINNER`; scorer logic in `core/kcmu_kiloscore_native.sv`; replacement/admission integration in `core/kcmu_l2_ctrl.sv`. |

## Naming Notes

- CVR means clean-victim retention: clean L2 victims can be kept in a read-only
  spillway and later promoted back.
- GF means guarded fill: a separate protocol guard can admit one follow-on
  line into the group buffer path after a miss. GF is not directly gated by
  KiloScore.
- GB means group buffer: the small holder for an accepted GF line.
- Historical suffixes such as `v245` and `v251` remain only inside locked
  result config IDs and replay macros. They are not used as public file names.
