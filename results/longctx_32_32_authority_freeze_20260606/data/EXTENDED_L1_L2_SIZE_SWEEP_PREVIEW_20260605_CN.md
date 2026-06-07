# Extended Longctx L1/L2 Size Sweep Preview

- Combined status CSV: `delivery/paper/repro_audit/longctx_l1_l2_size_sweep_ext_20260605/extended_status_combined.csv`
- Status cells: 40
- Valid parsed cells: 25
- Failed/unparsed cells: 15
- Parsed paired rows: 675
- Method: xsim RTL simulation with testbench-only `KCMU_TB_L1_LINES` / `KCMU_TB_L2_LINES`; no DUT/scorer/threshold/trace edits.
- Matched configs: `fpga_h2o_plus_service_cvr_group_fill_v251` vs `fpga_kiloscore_hv_opt5_global_winner`.

## Aggregate By Size

| L1/L2 | cells | rows | L1 hit base->KW (%) | Hier. miss base->KW (%) | RTL latency base->KW (cycles) | Lat. gain (%) | HBM save (%) | neg lat rows |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 16/32 | 4 | 108 | 9.07->17.86 | 37.74->32.73 | 4.050->4.017 | 0.79 | 13.27 | 2 |
| 16/64 | 4 | 108 | 9.07->17.01 | 12.09->10.38 | 3.871->3.861 | 0.27 | 14.14 | 24 |
| 32/32 | 4 | 108 | 23.72->59.46 | 33.42->18.51 | 4.018->3.918 | 2.48 | 44.62 | 0 |
| 32/64 | 4 | 108 | 23.72->59.85 | 11.13->8.12 | 3.864->3.847 | 0.46 | 27.05 | 1 |
| 64/256 | 1 | 27 | 90.83->90.83 | 0.10->0.10 | 3.764->3.764 | 0.00 | 0.00 | 0 |
| 64/64 | 4 | 108 | 91.08->91.43 | 5.43->4.24 | 3.827->3.819 | 0.20 | 21.89 | 2 |
| 8/16 | 4 | 108 | 2.09->4.62 | 69.83->62.26 | 4.272->4.224 | 1.12 | 10.84 | 5 |

## Aggregate By Model And Size

| Model | L1/L2 | cells | rows | L1 hit base->KW (%) | Hier. miss base->KW (%) | RTL latency base->KW (cycles) | Lat. gain (%) | HBM save (%) | neg lat rows |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| qwen2p5_7b_instruct | 16/32 | 4 | 108 | 9.07->17.86 | 37.74->32.73 | 4.050->4.017 | 0.79 | 13.27 | 2 |
| qwen2p5_7b_instruct | 16/64 | 4 | 108 | 9.07->17.01 | 12.09->10.38 | 3.871->3.861 | 0.27 | 14.14 | 24 |
| qwen2p5_7b_instruct | 32/32 | 4 | 108 | 23.72->59.46 | 33.42->18.51 | 4.018->3.918 | 2.48 | 44.62 | 0 |
| qwen2p5_7b_instruct | 32/64 | 4 | 108 | 23.72->59.85 | 11.13->8.12 | 3.864->3.847 | 0.46 | 27.05 | 1 |
| qwen2p5_7b_instruct | 64/256 | 1 | 27 | 90.83->90.83 | 0.10->0.10 | 3.764->3.764 | 0.00 | 0.00 | 0 |
| qwen2p5_7b_instruct | 64/64 | 4 | 108 | 91.08->91.43 | 5.43->4.24 | 3.827->3.819 | 0.20 | 21.89 | 2 |
| qwen2p5_7b_instruct | 8/16 | 4 | 108 | 2.09->4.62 | 69.83->62.26 | 4.272->4.224 | 1.12 | 10.84 | 5 |

## Failed Or Unparsed Cells

| Model | Context | L1/L2 | Status | Phase | Reason |
|---|---:|---:|---|---|---|
| qwen2p5_7b_instruct | 4k | 16/128 | FAIL_EXIT_1 | replay | Time: 554255 ns  Iteration: 0  Process: /tb_kcmu_system_eval/do_descriptor  Scope: tb_kcmu_system_eval.do_descriptor  File: D:/Kiloware/kiloware_paper/kiloware_paper.srcs/sources_1/new/tb_kcmu_system_eval.sv Line: 9679 |
| qwen2p5_7b_instruct | 8k | 16/128 | FAIL_EXIT_1 | replay | Time: 1130405 ns  Iteration: 0  Process: /tb_kcmu_system_eval/do_descriptor  Scope: tb_kcmu_system_eval.do_descriptor  File: D:/Kiloware/kiloware_paper/kiloware_paper.srcs/sources_1/new/tb_kcmu_system_eval.sv Line: 9679 |
| qwen2p5_7b_instruct | 16k | 16/128 | FAIL_EXIT_1 | replay | Time: 2227315 ns  Iteration: 0  Process: /tb_kcmu_system_eval/do_descriptor  Scope: tb_kcmu_system_eval.do_descriptor  File: D:/Kiloware/kiloware_paper/kiloware_paper.srcs/sources_1/new/tb_kcmu_system_eval.sv Line: 9679 |
| qwen2p5_7b_instruct | 32k | 16/128 | FAIL_EXIT_1 | replay | Time: 4252555 ns  Iteration: 0  Process: /tb_kcmu_system_eval/do_descriptor  Scope: tb_kcmu_system_eval.do_descriptor  File: D:/Kiloware/kiloware_paper/kiloware_paper.srcs/sources_1/new/tb_kcmu_system_eval.sv Line: 9679 |
| qwen2p5_7b_instruct | 4k | 32/128 | FAIL_EXIT_1 | replay | Time: 554255 ns  Iteration: 0  Process: /tb_kcmu_system_eval/do_descriptor  Scope: tb_kcmu_system_eval.do_descriptor  File: D:/Kiloware/kiloware_paper/kiloware_paper.srcs/sources_1/new/tb_kcmu_system_eval.sv Line: 9679 |
| qwen2p5_7b_instruct | 8k | 32/128 | FAIL_EXIT_1 | replay | Time: 1130405 ns  Iteration: 0  Process: /tb_kcmu_system_eval/do_descriptor  Scope: tb_kcmu_system_eval.do_descriptor  File: D:/Kiloware/kiloware_paper/kiloware_paper.srcs/sources_1/new/tb_kcmu_system_eval.sv Line: 9679 |
| qwen2p5_7b_instruct | 16k | 32/128 | FAIL_EXIT_1 | replay | Time: 2226455 ns  Iteration: 0  Process: /tb_kcmu_system_eval/do_descriptor  Scope: tb_kcmu_system_eval.do_descriptor  File: D:/Kiloware/kiloware_paper/kiloware_paper.srcs/sources_1/new/tb_kcmu_system_eval.sv Line: 9679 |
| qwen2p5_7b_instruct | 32k | 32/128 | FAIL_EXIT_1 | replay | Time: 4252555 ns  Iteration: 0  Process: /tb_kcmu_system_eval/do_descriptor  Scope: tb_kcmu_system_eval.do_descriptor  File: D:/Kiloware/kiloware_paper/kiloware_paper.srcs/sources_1/new/tb_kcmu_system_eval.sv Line: 9679 |
| qwen2p5_7b_instruct | 4k | 64/128 | FAIL_EXIT_1 | replay | Time: 554205 ns  Iteration: 0  Process: /tb_kcmu_system_eval/do_descriptor  Scope: tb_kcmu_system_eval.do_descriptor  File: D:/Kiloware/kiloware_paper/kiloware_paper.srcs/sources_1/new/tb_kcmu_system_eval.sv Line: 9679 |
| qwen2p5_7b_instruct | 8k | 64/128 | FAIL_EXIT_1 | replay | Time: 1131055 ns  Iteration: 0  Process: /tb_kcmu_system_eval/do_descriptor  Scope: tb_kcmu_system_eval.do_descriptor  File: D:/Kiloware/kiloware_paper/kiloware_paper.srcs/sources_1/new/tb_kcmu_system_eval.sv Line: 9679 |
| qwen2p5_7b_instruct | 16k | 64/128 | FAIL_EXIT_1 | replay | Time: 2224005 ns  Iteration: 0  Process: /tb_kcmu_system_eval/do_descriptor  Scope: tb_kcmu_system_eval.do_descriptor  File: D:/Kiloware/kiloware_paper/kiloware_paper.srcs/sources_1/new/tb_kcmu_system_eval.sv Line: 9679 |
| qwen2p5_7b_instruct | 32k | 64/128 | FAIL_EXIT_1 | replay | Time: 4252505 ns  Iteration: 0  Process: /tb_kcmu_system_eval/do_descriptor  Scope: tb_kcmu_system_eval.do_descriptor  File: D:/Kiloware/kiloware_paper/kiloware_paper.srcs/sources_1/new/tb_kcmu_system_eval.sv Line: 9679 |
| qwen2p5_7b_instruct | 4k | 64/256 | FAIL_EXIT_1 | replay | Time: 528025 ns  Iteration: 0  Process: /tb_kcmu_system_eval/do_descriptor  Scope: tb_kcmu_system_eval.do_descriptor  File: D:/Kiloware/kiloware_paper/kiloware_paper.srcs/sources_1/new/tb_kcmu_system_eval.sv Line: 9679 |
| qwen2p5_7b_instruct | 16k | 64/256 | FAIL_EXIT_1 | replay | Time: 2110165 ns  Iteration: 0  Process: /tb_kcmu_system_eval/do_descriptor  Scope: tb_kcmu_system_eval.do_descriptor  File: D:/Kiloware/kiloware_paper/kiloware_paper.srcs/sources_1/new/tb_kcmu_system_eval.sv Line: 9679 |
| qwen2p5_7b_instruct | 32k | 64/256 | FAIL_EXIT_1 | replay | Time: 4221285 ns  Iteration: 0  Process: /tb_kcmu_system_eval/do_descriptor  Scope: tb_kcmu_system_eval.do_descriptor  File: D:/Kiloware/kiloware_paper/kiloware_paper.srcs/sources_1/new/tb_kcmu_system_eval.sv Line: 9679 |
