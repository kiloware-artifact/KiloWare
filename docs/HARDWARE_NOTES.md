# Hardware Boundary Notes

The RTL files under `rtl/` are a curated paper-facing KCMU source snapshot used
for the paper's cycle-level replay and VCU128 OOC QoR evidence. The directory is
split into `core/`, `wrappers/`, `tb/`, and `constraints/` so reviewers do not
need to sort through historical exploratory top-level wrappers.

The mapping from paper policy rows to RTL files and replay macros is in
`rtl/POLICY_MAP.md`.

For the main KiloWare-HV path, inspect
`rtl/wrappers/kcmu_parameterized_paper_top.sv`,
`rtl/core/kcmu_kiloscore_native.sv`, `rtl/core/kcmu_l2_ctrl.sv`, and
`rtl/tb/tb_kcmu_system_eval.sv`.

The paper's reported latency numbers are serialized cycle-level RTL service
times under a parameterized backend model. The reported QoR numbers are OOC
KCMU control/metadata results. Payload storage, real HBM timing, board-level
datapaths, and multi-outstanding backend traffic are outside this artifact's
measurement boundary.

The selected 32/32 KiloWare-HV implementation reported by the locked freeze is:

```text
LUT: 20,580
WNS: +0.288 ns
Fmax: 102.965 MHz
```

The matched KCMU baseline uses the same CVR/GF contracts and H2O-derived
lossless score metadata for controlled scorer isolation.
