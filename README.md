# Custom IP Module for Tiled GEMM — 8x8 Systolic Array

A reusable Vivado IP module I developed from scratch for my graduate course at NYU (ECE: IP Design).

The IP packages a complete 8x8 weight-stationary systolic array, written entirely in SystemVerilog at the register-transfer level, with an AXI-Lite control interface for host communication. The full design — RTL, verification suite, AXI wrapper, and the packaged IP archive — is in this repo and can be dropped into any Vivado block design like a standard Xilinx IP.

**Target device:** Xilinx Zynq-7020 (PYNQ-Z2 board)
**Toolchain:** Vivado / Vitis 2023.2

---

## 1. IP Interface Definition

### Mathematical operation

The IP computes one tile of a tiled General Matrix Multiplication (GEMM):

```
C[8][8] = A[8][8] × B[8][8]
```

Where:
- **A** is an 8×8 tile of 16-bit signed integers (one operand)
- **B** is an 8×8 tile of 16-bit signed integers (weights)
- **C** is the resulting 8×8 tile of 32-bit signed integers (accumulator width)

For a larger matrix multiplication M_big × N_big, the host tiles the matrices into 8×8 chunks and invokes this IP per tile pair, accumulating partial products in host memory.

### Top-level IP interface

| Port group | Signals | Direction | Width | Role |
|---|---|---|---|---|
| AXI-Lite slave | `s_axi_aclk`, `s_axi_aresetn` | input | 1 each | Clock and reset (active-low) |
| AXI-Lite AW channel | `s_axi_awaddr`, `s_axi_awvalid`, `s_axi_awready` | mixed | 9, 1, 1 | Write address |
| AXI-Lite W channel | `s_axi_wdata`, `s_axi_wstrb`, `s_axi_wvalid`, `s_axi_wready` | mixed | 32, 4, 1, 1 | Write data |
| AXI-Lite B channel | `s_axi_bresp`, `s_axi_bvalid`, `s_axi_bready` | mixed | 2, 1, 1 | Write response |
| AXI-Lite AR channel | `s_axi_araddr`, `s_axi_arvalid`, `s_axi_arready` | mixed | 9, 1, 1 | Read address |
| AXI-Lite R channel | `s_axi_rdata`, `s_axi_rresp`, `s_axi_rvalid`, `s_axi_rready` | mixed | 32, 2, 1, 1 | Read data |
| A buffer write port | `a_wr_en`, `a_wr_addr`, `a_wr_data[N]` | input | 1, 3, 128 | Pre-load A tile |
| B buffer write port | `b_wr_en`, `b_wr_addr`, `b_wr_data[N]` | input | 1, 3, 128 | Pre-load B tile |

### AXI-Lite register map

The host communicates with the IP through memory-mapped registers in a 4 KB AXI-Lite slave window.

| Offset | Name | Access | Description |
|---|---|---|---|
| `0x000` | `CTRL` | Write | Bit 0 = `start` (write 1 to begin compute) |
| `0x004` | `STATUS` | Read | Bit 0 = `done` (1 = compute complete, latched until next start) |
| `0x010` – `0x10C` | `C_TILE[0..63]` | Read | 64 memory-mapped 32-bit registers holding the C tile. `C[row][col]` at offset `0x010 + (row*8 + col)*4` |

### Host ↔ IP transaction sequence

1. Host pre-loads A and B tiles through `a_wr_*` and `b_wr_*` ports (8 cycles each, one row per cycle in parallel)
2. Host writes `1` to `CTRL` (offset `0x000`) over AXI-Lite — fires a 1-cycle `start_pulse`
3. The IP's internal FSM runs through: `LOAD_WEIGHTS` → `STREAM` (8 cycles) → `DRAIN` (6 cycles) → `DONE`
4. Host polls `STATUS` (offset `0x004`) until bit 0 reads back as 1
5. Host reads the 64 C-tile registers (`0x010` through `0x10C`) over AXI-Lite

Total IP latency: **15 cycles from start_pulse to done assertion** at 100 MHz = **150 ns per tile**. (Breakdown: 1 cycle LOAD_WEIGHTS + 8 cycles STREAM + 6 cycles DRAIN. The `done` flag asserts at the start of cycle 16 — the cycle immediately after DRAIN completes — and stays latched until the next `start_pulse`.)

---

## 2. IP Design

### Module hierarchy

```
gemm_top.sv                  ← Top-level IP (AXI-Lite slave + internal modules)
├── axi_lite_ctrl.sv         ← AXI-Lite protocol slave (5-channel)
├── tile_ctrl.sv             ← Tile controller FSM (IDLE→LOAD_WEIGHTS→STREAM→DRAIN→DONE)
├── a_tile_buffer.sv         ← A operand tile buffer (8 banks for parallel reads)
│   └── tile_buffer.sv  (×8)   Generic dual-port memory primitive
├── b_tile_buffer.sv         ← B operand tile buffer (64-element register file)
└── systolic_array.sv        ← 8x8 PE grid with skew chains
    ├── shift_reg.sv  (×N)     Input skew chains (depth-per-row)
    ├── shift_reg.sv  (×N)     Output drain chains (depth N-1-j per column)
    └── pe.sv         (×N²=64) Processing Elements (multiplier + accumulator + weight register)
```

### Data flow

```
                                  ┌─────────────────────────┐
                                  │   Host (Zynq PS or TB)  │
                                  └──┬──────┬──────────┬────┘
                                     │      │          │
                  buffer writes  ────┘      │          └──── AXI-Lite control & C readback
                                            │
   ┌────────────────────────────────────────┼────────────────────────────┐
   │                                        │                            │
   │   ┌──────────┐  rd_data[N]   ┌─────────▼────────┐                   │
   │   │a_tile_   │ ───parallel──►│                  │                   │
   │   │ buffer   │   8 wires     │                  │                   │
   │   └──────────┘               │  Systolic Array  │  c_out[N]         │
   │                              │   (8×8 PE grid)  │ ─────►┌─────────┐ │
   │   ┌──────────┐ rd_data[N][N] │                  │       │   C     │ │
   │   │b_tile_   │ ──parallel───►│                  │       │ capture │ │
   │   │ buffer   │  64 wires     │                  │       └────┬────┘ │
   │   └──────────┘               └──────────────────┘            │      │
   │                                                              │      │
   │   ┌──────────┐                                               ▼      │
   │   │tile_ctrl │ ────── control ──────────────►────┐  c_latched[N][N] │
   │   │  (FSM)   │                                    │                  │
   │   └──────────┘                                    │                  │
   │                                                   │                  │
   │   ┌──────────────────────────────────────────────┴─────────────────┐ │
   │   │             axi_lite_ctrl (AXI-Lite slave)                     │ │
   │   └────────────────────────────────────────────────────────────────┘ │
   └──────────────────────────────────────────────────────────────────────┘
                                  gemm_top
```

### Parallelism and pipelining

The IP exploits several layers of parallelism. Each claim below points to the specific RTL source file that implements it.

**Spatial parallelism (PE grid):** 64 PEs operate in parallel each cycle. Every cycle of the STREAM phase, 8 multiplications and 8 additions execute simultaneously across each row of the array.
→ See the nested `genvar` loop in `rtl/systolic_array.sv` that instantiates `N*N=64` instances of `rtl/pe.sv`. Each PE's `always_ff` block in `rtl/pe.sv` contains the `c_reg <= c_reg + (a_in * b_reg)` multiply-accumulate, which Vivado maps to one DSP48E1 slice — confirmed by the 64-DSP utilization number below.

**Buffer partitioning:** `a_tile_buffer` is partitioned into 8 banks indexed by K-position, exposing all 8 row-r values in parallel on each cycle. `b_tile_buffer` holds 64 individual flip-flops with all 64 weights presented simultaneously on a single read.
→ See the 8-instance `generate` block in `rtl/a_tile_buffer.sv` (one `rtl/tile_buffer.sv` per K-bank) and the `logic signed [DATA_WIDTH-1:0] mem [N][N]` declaration in `rtl/b_tile_buffer.sv`. The combinational `assign` for `rd_data` in `b_tile_buffer.sv` is what gives the 0-cycle 64-wire weight read.

**Input skew chains:** Row `i` of A enters the array `i` cycles after row 0. This staggered entry, combined with PE-internal pipeline registers, ensures every PE sees its inputs at the right cycle and the dot-product accumulation completes correctly.
→ Implemented in `rtl/systolic_array.sv` via a `generate` loop that instantiates `rtl/shift_reg.sv` per row with `DEPTH = i`.

**Output drain chains:** Column `j` of C exits through a shift register of depth `N-1-j`. This depth-per-column scheme realigns the staggered output so all 8 columns of one row appear simultaneously on `c_out[N]`.
→ Implemented in `rtl/systolic_array.sv` via a per-column `generate` loop that instantiates `rtl/shift_reg.sv` with `DEPTH = N-1-j`.

**Pipeline structure of one tile compute (15 cycles total):**

```
   Cycle:     1     2-9        10-15    | 16
   Phase:   load   stream     drain     | done asserted
            (1)    (8 cycles) (6 cycles)| (latched flag)
```

`done` asserts at the start of cycle 16 and remains latched until the next `start_pulse`. The 15-cycle compute window is the actual latency reported in Section 3's analysis.

### Resource budget (target xc7z020, 220 DSP slices available)

| Resource | Use | Quantity |
|---|---|---|
| DSP48E1 | 1 per PE (16x16 multiply-add) | 64 |
| BRAM | A-buffer storage (parameterizable, currently LUTRAM) | minimal |
| Flip-flops | PE weight/a_in_reg/c_reg, FSM state, AXI registers | <5000 |

Resource utilization fits with ample headroom — under 30% DSP, well within LUT/BRAM budgets for the xc7z020.

### Quantitative design tradeoffs

The architectural choices above were not made by intuition alone. Each one was driven by concrete numerical tradeoffs against the target chip's resource budget and the project's latency goal.

**Array size: why 8×8 specifically?**

| Array size | DSPs needed | % of 220 budget | STREAM cycles | Per-tile latency | Verdict |
|---|---|---|---|---|---|
| 4×4 | 16 | 7.3% | 4 | ~8 cycles | Underutilizes chip; 4× more tiles to compute |
| **8×8** | **64** | **29.1%** | **8** | **15 cycles** | **Chosen — best balance** |
| 12×12 | 144 | 65.5% | 12 | 22 cycles | Heavy DSP use; less room for multi-IP |
| 16×16 | 256 | 116% | 16 | 28 cycles | **Exceeds DSP budget — won't fit** |

8×8 gives 4× the throughput of 4×4 (64 PEs vs 16) while leaving 156 DSP slices (71%) free for future expansion (a second IP instance, FIR filter, etc.). 16×16 is the obvious next jump but won't fit on the xc7z020 — that's a Zynq-Ultrascale class problem.

**Dataflow: why weight-stationary?**

| Dataflow | What's reused in PE | Buffer load cost | C readback cost | Picked? |
|---|---|---|---|---|
| **Weight-stationary** | B weight (held in PE) | 1 cycle (load all 64 weights) | Stream out via drain chain | **Yes** |
| Output-stationary | C accumulator (held in PE) | Stream both A and B every cycle | Direct read from PE register | No |
| Input-stationary | A input (held in PE) | Stream B and accumulate | Stream out via drain chain | No |

For a single tile, all three need 8 cycles of compute. The differentiator is buffer complexity. Weight-stationary needs the B buffer presented combinationally for **1 cycle** (load_weight), then never accessed again — the simplest possible B-buffer interface. Output-stationary would need both A and B streamed every cycle for all 8 cycles, doubling the buffer read bandwidth requirement.

**Buffer memory: why LUTRAM over BRAM?**

The A-tile buffer stores 64 × 16-bit = 1,024 bits. A single BRAM18K block is 18,432 bits. Using one BRAM for the A-tile buffer would waste **94.4%** of the block. Vivado's automatic memory inference correctly picks LUTRAM (distributed memory) instead — the synthesis report shows 427 LUT-as-Memory entries and zero BRAM consumed. This frees all 140 BRAM tiles for future use.

**Numerical format: int16 in / int32 out**

The 32-bit accumulator has 16 bits of headroom over the input width. An 8-element dot-product of two int16 vectors has a worst-case magnitude of 8 × (2^15)² = 2³¹, which exactly fits in int32 without saturation. Going to int8 inputs would halve the DSP utilization (one DSP could hold two int8 multiplies) but the verification harness is simpler with int16 because NumPy's default integer type matches.

These choices were not all reached on the first try — the 8×8 array size, in particular, was settled on after experimenting with the math of skew-chain depth and DRAIN_CYCLES for the 4×4 and 6×6 cases during Phase 4.

---

## 3. Verification & Evaluation

### Verification strategy

Each module was verified in isolation, then integrated upward with increasing scope. The testbench hierarchy mirrored the module hierarchy.

| Testbench | Scope | Test coverage |
|---|---|---|
| `pe_tb.sv` | Single PE | Hand-traced multiply-accumulate with known weights |
| `systolic_array_tb.sv` | 8x8 array (no buffers) | Direct-drive A inputs against C++ golden model |
| `array_full_buf_tb.sv` | Array + buffers (no FSM) | Buffer-fed compute against golden model |
| `array_ctrl_tb.sv` | Array + buffers + FSM | FSM-driven compute against golden model |
| `gemm_axi_tb.sv` | Full IP (AXI master testbench) | AXI-driven compute against golden model |

### Test vectors

The Python golden model (`software/dump_test_vectors.py`) generates 100 random A and B tile pairs using NumPy and dumps:

- `tb/data/a_tile.hex` — 100 tiles × 64 elements × int16 = 6400 hex values
- `tb/data/b_tile.hex` — same format
- `tb/data/c_expected.hex` — 6400 expected int32 result values

Each SystemVerilog testbench reads these via `$readmemh` and compares the IP's output against the expected values bit-exactly.

### Simulation results

| Stage | Testbench | Result |
|---|---|---|
| Phase 4 — Systolic array only | `systolic_array_tb` | **6400/6400 passing** |
| Phase 5 — With tile buffers | `array_full_buf_tb` | **6400/6400 passing** |
| Phase 6 — FSM-driven | `array_ctrl_tb` | **6400/6400 passing** |
| Phase 7 — Full AXI path | `gemm_axi_tb` | **6400/6400 passing** |

100 random tile pairs × 64 cells each = 6400 individual bit-exact comparisons against the NumPy golden model. Result: all four levels of integration pass cleanly.

### Synthesis results (Vivado 2023.2, target xc7z020clg400-1)

| Metric | Value | Notes |
|---|---|---|
| Slice LUT utilization | 1,734 / 53,200 | 3.3% |
| LUT-as-Memory (LUTRAM) | 427 / 17,400 | 2.5% (A-tile buffer storage) |
| BRAM utilization | 0 / 140 | 0% (buffers map to LUTRAM, not BRAM) |
| DSP utilization | 64 / 220 | 29% (one DSP per PE) |
| Flip-Flop utilization | 4,968 / 106,400 | 4.7% |
| Max clock frequency | 116 MHz | WNS = +1.377 ns at 100 MHz target (timing met) |
| Bitstream | Generated successfully | `write_bitstream` completed without errors |

Resource utilization is well under target on every dimension. The bitstream completed cleanly and meets timing at 100 MHz with 1.377 ns of positive slack — the design could be pushed to ~116 MHz without resynthesis if needed.

### Raw report excerpts

The numbers above are summarized from Vivado's place-and-route reports. Below are the relevant excerpts so they can be verified without opening Vivado.

**Utilization (excerpt from `vivado/gemm_bd/gemm_bd.runs/impl_1/design_1_wrapper_utilization_placed.rpt`):**

```
+-------------------------+------+-------+-----------+-------+
|        Site Type        | Used | Fixed | Available | Util% |
+-------------------------+------+-------+-----------+-------+
| Slice LUTs              | 1734 |     0 |     53200 |  3.26 |
|   LUT as Logic          | 1307 |     0 |     53200 |  2.46 |
|   LUT as Memory         |  427 |     0 |     17400 |  2.45 |
| Slice Registers         | 4968 |     0 |    106400 |  4.67 |
|   Register as Flip Flop | 4968 |     0 |    106400 |  4.67 |
|   Register as Latch     |    0 |     0 |    106400 |  0.00 |
| F7 Muxes                |  244 |     0 |     26600 |  0.92 |
| F8 Muxes                |   56 |     0 |     13300 |  0.42 |
+-------------------------+------+-------+-----------+-------+

+----------------+------+-------+-----------+-------+
|    Site Type   | Used | Fixed | Available | Util% |
+----------------+------+-------+-----------+-------+
| Block RAM Tile |    0 |     0 |       140 |  0.00 |
|   RAMB36/FIFO  |    0 |     0 |       140 |  0.00 |
|   RAMB18       |    0 |     0 |       280 |  0.00 |
| DSPs           |   64 |     0 |       220 | 29.09 |
+----------------+------+-------+-----------+-------+
```

The 64 DSPs directly correspond to the 64 PE instances in `rtl/systolic_array.sv` — one DSP per PE, exactly as the design intends. The 0 BRAM and 427 LUT-as-Memory indicate Vivado mapped the tile buffers to distributed RAM rather than block RAM, which is the right call for an 8×8 buffer.

**Timing summary (excerpt from `vivado/gemm_bd/gemm_bd.runs/impl_1/design_1_wrapper_timing_summary_routed.rpt`):**

```
Design Timing Summary
-----------------------------------------------------------------------
       Setup        |        Hold       |    Pulse Width
---------------+-----------------------+--------------------------------
 WNS:    1.377 ns  | WHS:    0.035 ns  | WPWS:    3.750 ns
 TNS:    0.000 ns  | THS:    0.000 ns  | TPWS:    0.000 ns
 Failing EP: 0     | Failing EP: 0     | Failing EP: 0
 Total EP: 15862   | Total EP: 15822   | Total EP: 5676

All user specified timing constraints are met.
```

WNS (Worst Negative Slack) of +1.377 ns at a 10 ns (100 MHz) clock period means the design has 1.377 ns of headroom at every register-to-register path. WHS (Worst Hold Slack) of +0.035 ns is small but positive — hold time is met across all 15,822 endpoints. The design is fully timing-clean.

### Latency and throughput analysis

**Per-tile latency** (cycles from `start_pulse` to `done` assertion):

| Phase | Cycles | Description |
|---|---|---|
| LOAD_WEIGHTS | 1 | Latch all 64 B values into PE weight registers |
| STREAM | 8 | Feed 8 rows of A through the array |
| DRAIN | 6 | Allow accumulator pipeline to drain |
| Total | **15 cycles** | From start to done assertion |

**Throughput** (at 100 MHz operating frequency):

- Per-tile time: 15 × 10 ns = **150 ns / tile**
- Tiles per second: ~6.67 million
- Theoretical peak MACs/sec: 64 PEs × 6.67M tiles/sec × 8 MACs/tile = **3.4 GMAC/s** (≈ 6.8 GOP/s for int16)

### Comparison to initial design goals

| Goal | Target | Achieved | Status |
|---|---|---|---|
| Bit-exact correctness | 100% pass on randomized tests | 6400/6400 (100%) | ✅ |
| Fit on xc7z020 | <50% LUT, <50% DSP | 3.3% LUT, 29% DSP | ✅ |
| Operating frequency | 100 MHz minimum | 116 MHz (met at 100 MHz with +1.377 ns slack) | ✅ |
| Tile latency | <30 cycles | 15 cycles | ✅ |
| Packaged as reusable IP | Drop-in Vivado IP archive | Yes, via IP Packager | ✅ |

---

## 4. Organization & Documentation

### Repository structure

```
.
├── README.md                    ← Top-level documentation (this file)
├── Makefile                     ← One-command build automation (sim, ip, bitstream)
├── rtl/                         ← SystemVerilog source files (9 modules)
│   ├── pe.sv
│   ├── shift_reg.sv
│   ├── systolic_array.sv
│   ├── tile_buffer.sv
│   ├── a_tile_buffer.sv
│   ├── b_tile_buffer.sv
│   ├── tile_ctrl.sv
│   ├── axi_lite_ctrl.sv
│   └── gemm_top.sv
├── tb/                          ← Testbenches
│   ├── pe_tb.sv
│   ├── systolic_array_tb.sv
│   ├── array_full_buf_tb.sv
│   ├── array_ctrl_tb.sv
│   ├── gemm_axi_tb.sv
│   └── data/                    ← Generated hex test vectors
│       ├── a_tile.hex
│       ├── b_tile.hex
│       └── c_expected.hex
├── software/                    ← Python golden model
│   └── dump_test_vectors.py
├── scripts/                     ← Vivado batch-mode automation
│   ├── build_ip.tcl             ← Tcl script: package IP from RTL
│   └── build_bd.tcl             ← Tcl script: block design + bitstream
├── docs/                        ← Phase-by-phase design walkthroughs (HTML)
│   ├── Phase4_*.html
│   ├── Phase5_*.html
│   └── ... (covering all phases)
└── vivado/                      ← Vivado project files (generated, gitignored)
    ├── gemm_ip_packaging/       ← Output of `make ip` (packaged IP)
    └── gemm_bd/                 ← Output of `make bitstream` (.bit + .xsa)
```

### Automated verification flow

The full pipeline runs from a clean clone with a single command:

```bash
source /opt/Xilinx/Vivado/2023.2/settings64.sh   # or wherever Vivado lives
make all
```

`make all` runs the four-stage pipeline sequentially:

```
1. make vectors    →  python3 software/dump_test_vectors.py
                      writes deterministic hex vectors to tb/data/
2. make sim        →  xvlog + xelab + xsim on array_full_buf_tb
                      asserts "RESULT: ALL TESTS PASSED" (6400/6400)
3. make ip         →  vivado -mode batch -source scripts/build_ip.tcl
                      packages gemm_top into vivado/gemm_ip_packaging/ip_repo/
4. make bitstream  →  vivado -mode batch -source scripts/build_bd.tcl
                      generates design_1_wrapper.bit + design_1_wrapper.xsa
```

Individual targets can be run in isolation:

```bash
make sim TB=gemm_axi_tb     # run a specific testbench
make ip                     # rebuild only the packaged IP
make bitstream              # rebuild only the bitstream
make clean                  # remove build artifacts
make help                   # full target listing
```

The Python golden model uses a fixed NumPy random seed, so the hex test vectors are byte-identical across runs and machines — every regression is reproducible bit-exact.

### Detailed phase walkthroughs

Each major design phase has its own walkthrough document in `docs/` covering motivation, design decisions, code fragments with reasoning, the complete updated source file, and verification results. Topics covered:

- Phase 4: Systolic array construction and skew chain math
- Phase 5: Tile buffer design (A operand partitioned for parallel reads, B operand combinational)
- Phase 6: Tile controller FSM and integration
- Phase 7: AXI-Lite wrapper design (slave protocol, memory-mapped C readout, AXI master testbench)
- Phase 7.3 post-mortem: Debugging interaction between testbench bug and RTL timing
- Phase 8: Vivado IP packaging walkthrough

---

## Design decisions (rationale)

### SystemVerilog instead of Vitis HLS

I could have written the IP in C++ with Vitis HLS and finished much faster. I deliberately chose direct RTL in SystemVerilog because (1) the course emphasizes register-transfer-level understanding, and (2) hand-tuned RTL is typically 1.5-3× more area-efficient than HLS output for well-understood structures like systolic arrays.

### Weight-stationary architecture

B tile stays in the PE weight registers across an entire tile compute; A streams through; C drains out. Simplest control logic of the three "stationary" choices and natural fit for B-reuse across many A rows. Google's TPU uses a variant of weight-stationary for the same reasons.

### 8×8 array size

Big enough that skew chains and loop structures exercise their parameter sweeps (catching off-by-one bugs); small enough to debug by hand (one A value can be traced cycle by cycle); fits comfortably on the target xc7z020 with ~30% DSP utilization.

### Int16 inputs with int32 accumulator

Integer arithmetic is bit-exact, making verification against the NumPy golden model trivial. Fits cleanly into one DSP48E1 slice per PE. 32-bit accumulator has plenty of overflow headroom for the 8-element dot products.

### Signal-driven C tile capture

The output capture is triggered by the FSM's `done_pulse` rather than by a free-running cycle counter. This makes the capture self-correcting if `DRAIN_CYCLES`, `N`, or start-pulse timing changes — a robustness lesson learned during Phase 7.3 debugging.

---

## Extension work beyond the core IP

After completing the packaged IP (the project deliverable), I extended into:

**Phase 9 — Block design and bitstream.** Wired the packaged IP to a Zynq PS in Vivado's block designer, generated `design_1_wrapper.bit` (FPGA bitstream) and `design_1_wrapper.xsa` (hardware description archive).

**Phase 10 — On-board execution.** Loaded the bitstream onto a real PYNQ-Z2 board and used PYNQ's Python overlay framework over Jupyter. Verified that the bitstream loads on real silicon, that PYNQ correctly identifies the IP at AXI base address `0x40000000`, that the AXI address space is correctly mapped, and that AXI reads of CTRL and STATUS registers return expected initial values.

A next-iteration refinement of the AXI write FSM (handling AW and W channels independently) plus memory-mapping the buffer write ports through AXI is documented as the path to a fully functional on-board demonstration.

---

## Lessons learned

**Simulation is necessary but not sufficient.** A testbench can be wrong in ways that perfectly mirror an RTL bug. 6400/6400 passing means your test of the hardware matches your model of the hardware. Necessary, not sufficient. The on-board AXI write timing issue is a real example — both my testbench and my RTL assumed simultaneous AW/W, so they passed each other.

**Signal-driven triggers beat cycle-count-based timing.** When other parts of the design change (DRAIN_CYCLES, N, FSM structure), cycle-count-based logic breaks silently. Signal-driven logic is self-correcting.

**Interaction bugs are the hardest to debug.** Two bugs that mask each other (sloppy testbench AXI handshake + capture-window tuned to compensate) keep your fixes oscillating because each individual fix makes symptoms appear to worsen. Lesson: if you can't converge, suspect interaction.

**Tool depth amplifies debug time.** Simulation bugs: minutes. Synthesis bugs: hours. Implementation: half a day. On-board: days. The discipline of catching issues at the earliest stage pays exponential returns.

---

## Tools and toolchain

- **Vivado / Vitis 2023.2** (RTL synthesis, IP Packager, block design, bitstream generation)
- **SystemVerilog** (IEEE 1800-2017)
- **Python 3 with NumPy** (golden reference model and test vector generation)
- **PYNQ image v3.0** (on-board Python runtime)

---

## Quick reproduction guide

The entire flow — from clean clone to a working bitstream — is one command:

```bash
git clone https://github.com/TechJoe96/Custom-Vitis-IP-for-Tiled-GEMM.git
cd Custom-Vitis-IP-for-Tiled-GEMM
source /opt/Xilinx/Vivado/2023.2/settings64.sh   # adjust to your Vivado path
make all
```

This runs vectors → simulation → IP packaging → bitstream end-to-end and produces:

- `tb/data/*.hex` — deterministic test vectors from the NumPy golden model
- `build/sim/sim.log` — simulation log with `"RESULT: ALL TESTS PASSED"` and 6400/6400
- `vivado/gemm_ip_packaging/ip_repo/gemm_top.zip` — packaged IP archive
- `vivado/gemm_bd/gemm_bd.runs/impl_1/design_1_wrapper.bit` — FPGA bitstream
- `vivado/gemm_bd/design_1_wrapper.xsa` — hardware platform archive (.bit + .hwh)

**To run individual stages:**

```bash
make vectors                # only regenerate test vectors
make sim TB=gemm_axi_tb     # only run the AXI-level testbench
make ip                     # only package the IP
make bitstream              # only generate the bitstream
make clean                  # remove all build artifacts
```

**To deploy on a PYNQ-Z2 board:**

```python
from pynq import Overlay
overlay = Overlay("design_1_wrapper.bit")    # .hwh is auto-loaded from same dir
gemm = overlay.gemm_top_0
# Drive via the register map in Section 1: write 0x000 to start, poll 0x004
# for done, read C tile from 0x010-0x10C
```
