# RTL Snapshot

This directory contains the paper-facing RTL subset for reviewer inspection. It
is not a dump of every historical experiment wrapper from the development tree.

## Layout

- `core/`: shared synthesizable KCMU modules, including the L1/L2/CVR/GF
  datapath, backend model interface, trace descriptor plumbing, and KiloScore
  logic.
- `wrappers/`: top-level paper wrappers for the final KCMU path and the main
  Table 1 comparison points that have explicit RTL wrappers.
- `tb/`: trace-driven and contract testbenches used to inspect behavior and
  cycle counters.
- `constraints/`: small VCU128/ZCU-style constraint files retained for QoR
  context.

For a direct paper-policy mapping, see `POLICY_MAP.md`.

## Wrapper Map

- `kcmu_parameterized_paper_top.sv`: generic paper top used by the final KCMU
  configuration path and parameter sweeps.
- `policy_h2o_lossless_top.sv`: lossless H2O-derived
  metadata service wrapper used for the pure H2O-style comparison point.
- `policy_h2o_cvr_top.sv`: H2O-score KCMU plus clean-victim
  retention.
- `policy_h2o_cvr_gf_matched_top.sv`: matched CVR+GF KCMU baseline with
  H2O-derived lossless score metadata.

The current paper's selected KiloWare-HV result is the same KCMU service path
with KiloScore-HV enabled; the KiloScore logic is in
`core/kcmu_kiloscore_native.sv` and the locked result row is
`fpga_kiloscore_hv_opt5_global_winner` in the CSV freeze under `results/`.

Historical wrapper files from the design search, such as older numbered
variants, are intentionally omitted from this upload to keep the public artifact
focused on the final paper evidence.

The main replay testbench, `tb/tb_kcmu_system_eval.sv`, still contains locked
`CONFIG_NAME` strings for older frozen-result branches so that result provenance
is inspectable. Those strings are not separate released top-level wrappers.

## Boundary

The released RTL supports inspection of the KCMU control/metadata design and
trace-driven replay boundary. It does not include generated Vivado projects,
xsim work directories, waveforms, model weights, or board-level HBM integration.
