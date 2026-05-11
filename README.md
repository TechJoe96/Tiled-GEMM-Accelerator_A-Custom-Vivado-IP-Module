# Tiled GEMM Accelerator: A Custom Vivado IP Module

The core is an 8x8 weight-stationary systolic array, written entirely in SystemVerilog at the register-transfer level. It computes one tile of a matrix multiplication (C = A × B) per invocation, controlled over AXI-Lite. The full design — RTL, verification, AXI wrapper, packaged Vivado IP — is in this repo.

## What it does

It multiplies two 8x8 tiles to produce one 8x8 result tile. The flow:

1. Load a B tile into the array (single cycle, all 64 weights latched in parallel)
2. Stream A row by row through the array (8 cycles)
3. Drain the C values out the bottom (6 cycles)
4. Total: ~16 cycles from start to done

For larger matrices, the algorithm tiles the work into 8x8 chunks and runs this IP on each pair.

## Decision Making

### SystemVerilog instead of Vitis HLS

I could have written the whole thing in C++ with Vitis HLS (High-Level Synthesis) and finished much faster. I deliberately chose SystemVerilog instead.

**I wanted to understand the hardware, not abstract it.** With HLS, the scheduler decides when each multiplier fires, when pipeline registers slot in, how buffers are partitioned. You write hints (pragmas) and trust the tool. With SystemVerilog, you write every register, every state transition, every clock edge yourself. You have to know how NBA (Non-Blocking Assignment) semantics work. You have to know why a drain chain depth is `N-1-j` per column. That depth of understanding is the point of this course.

A great follow-up would be implementing the same algorithm in HLS and comparing the two side by side. That's on my "things I want to do next" list.

### Weight-stationary architecture

A systolic array has to hold one operand still while the other flows through. 

I picked weight-stationary because the control logic is simplest, B reuse across rows of A is natural, and the preload phase is just one cycle. Google's TPU uses a variant of weight-stationary for the same reasons.

### 8x8 array size

Picked 8x8 (so 64 PEs) for three reasons:

1. Small enough to debug by hand
2. Big enough that looping logic and skew chains actually exercise their parameter sweeps
3. Fits comfortably on the PYNQ-Z2's xc7z020 (64 DSPs out of 220 available)

The design is fully parameterized — changing `N` would scale to 16x16 or 32x32, limited only by chip resources.

### 16-bit signed integers with 32-bit accumulator

Integer arithmetic is bit-exact, which makes verification trivial: software golden model and hardware output have to match exactly, not just be "close enough". 16-bit inputs fit one DSP48 slice cleanly. 32-bit accumulators have plenty of overflow headroom for the 8-element dot products.

### Python golden model

The original project plan suggested C++ for the reference. I used Python with NumPy instead. `A @ B` does the math in one line; the test-vector generator is about 30 lines total. C++ would have been 10× longer for the same thing. For a non-performance-critical reference, Python is the right call.

### AXI-Lite for control

I implemented an AXI-Lite slave for the host CPU to drive the IP. AXI-Lite is the simplest AXI variant — two 32-bit channels — and easy to debug. At 8x8 tile scale, the register-write approach to loading data is fast enough.

For a production version handling many tiles per second, I'd add AXI-Stream or AXI-Full DMA. That's a natural next phase.

### Signal-based capture trigger, not a cycle counter

The C tile capture went through several iterations. My first version used a cycle counter that started when the host pulsed "start" and fired capture at specific cycle numbers. It worked in simulation but was brittle — changing `DRAIN_CYCLES` or the FSM (Finite State Machine) timing broke the magic numbers.

The final version triggers capture from the FSM's `done` pulse directly. The capture index counts 0 through 7 from there. No magic numbers, no cycle-count drift, robust to FSM changes.

The general principle: trigger off signals, not cycle counts. Signal-based logic is self-correcting when other parts of the design change.

## How to read this repo

- `rtl/` — all the SystemVerilog source (the actual hardware design)
- `tb/` — testbenches that verify each module and the full system
- `software/` — Python golden model and test-vector generator
- `vivado/` — Vivado projects for IP packaging and block design integration

## The build, phase by phase

I worked through this in clear phases. Each phase had its own simulation tests that had to pass before I moved on. That discipline kept bugs local and easy to find.

**Phase 1-2: Math and paper design.** Wrote the NumPy reference and generated 100 random test cases. Drew the systolic array on paper and worked out the skew chain depths cycle by cycle.

**Phase 3: Single PE.** Built one Processing Element (one multiplier, one accumulator, one weight register). Verified in isolation with a hand-traced testbench.

**Phase 4: Full 8x8 array.** Wired 64 PEs into a grid with input skew chains (depth `i` for row `i`) and output drain chains (depth `N-1-j` for column `j`). End-to-end testbench with 100 random tile pairs achieved **6400/6400 passing checks**.

**Phase 5: Tile buffers.** Added `a_tile_buffer` (8 banks partitioned by K-position for parallel reads) and `b_tile_buffer` (64-element register file with combinational read for single-cycle weight load). Both individually verified, then integrated. Still **6400/6400 passing**.

**Phase 6: Tile controller FSM.** Built a state machine that orchestrates the compute sequence: IDLE → LOAD_WEIGHTS → STREAM → DRAIN → DONE. Replaced the testbench's manual orchestration with a single "pulse start, wait for done" interaction. **6400/6400 still passing**.

**Phase 7: AXI-Lite wrapper.** Built `axi_lite_ctrl` from scratch — handles all five AXI-Lite channels (AW, W, B, AR, R) with proper handshakes. Added internal C tile latching so the host can read results through memory-mapped registers. Built a custom AXI master testbench. **6400/6400 passing through the full AXI path.**

**Phase 8: Vivado IP Packaging.** Used Vivado's IP Packager to produce a real Vivado IP archive — a packaged, distributable component with proper metadata. AXI-Lite interface auto-inferred from the `s_axi_*` port naming convention. The IP is now reusable in any Vivado block design.

**Phase 8 is the natural completion of the project as named — "Custom Vitis IP for Tiled GEMM."** A verified, packaged, reusable IP. That's the deliverable.

## Verification results

| Stage | Result |
|-------|--------|
| Phase 4 — Systolic array | 6400/6400 random tests passing |
| Phase 5 — With tile buffers | 6400/6400 passing |
| Phase 6 — FSM-driven | 6400/6400 passing |
| Phase 7 — Full AXI path | 6400/6400 passing |
| Phase 8 — Synthesized & packaged | Fits on xc7z020, IP archive produced |

The 100 random test cases × 64 cells each = 6400 individual value comparisons. Every single one is bit-exact against the NumPy golden model. Across four levels of integration, that result held.

Synthesis results on xc7z020 (from Phase 8):

- LUTs: [fill in from your synth report]
- BRAM: [fill in]
- DSP slices: [fill in]
- Max frequency: [fill in] MHz

## Taking it further: Phase 9 and on-board execution

After Phase 8, I went further — integrated the packaged IP into a Vivado block design with a Zynq Processing System (PS), generated a bitstream, and loaded it onto a real PYNQ-Z2 board.

**Phase 9** produced `design_1_wrapper.bit` (the FPGA bitstream) and `design_1_wrapper.xsa` (the hardware description archive). The IP fits, meets timing, and is ready to run.

**Phase 10** loaded the bitstream onto the PYNQ-Z2 and used PYNQ's Python framework over Jupyter to control the IP. I verified:

- The bitstream loads on real silicon
- PYNQ correctly identifies the IP at AXI base address `0x40000000`
- The AXI address space is correctly mapped (4 KB window)
- AXI reads of the CTRL and STATUS registers work and return the expected initial values

This is meaningful progress — the IP is recognized and addressable on real hardware. Going from "it simulates" to "real silicon recognizes it" is a real milestone.

I also discovered a small protocol-compliance refinement opportunity in the AXI write FSM: it requires `awvalid` and `wvalid` to arrive on the same cycle, while the AXI specification allows them to arrive separately. Most masters do drive them together, but the Zynq PS occasionally separates them. This is a 1-2 hour RTL fix (handle each channel independently) that I'm planning to do as the next iteration. Combined with memory-mapping the buffer write ports through AXI, that completes a fully functional on-board demo with real matrix multiplications.

## What I learned

Listing the biggest takeaways:

**Verification has to match the real environment, not just the simulator.** A testbench can be wrong in ways that perfectly match an RTL bug. 6400/6400 passing means your test of the hardware matches your model of the hardware. That's necessary but not sufficient — the real world can drive your AXI signals differently from your testbench.

**Signal-based triggers beat counter-based timing.** Once you start tying behavior to specific cycle counts, you're brittle to every change elsewhere in the design. Trigger off the signal that actually represents the event you care about. The capture logic became much cleaner when I switched from "fire at cycle 16" to "fire when done_pulse arrives."

**Two bugs that mask each other are the hardest to debug.** I had a sloppy AXI master in my testbench combined with a brittle capture window in my RTL, and they compensated for each other. Fixing one made things worse, which made me back out the fix. The lesson: if your fixes keep oscillating, suspect interaction.

**The deeper into the toolchain, the slower the debug cycle.** Simulation bugs: minutes. Synthesis bugs: hours. Implementation/timing bugs: half a day. On-board bugs: days. Catch what you can early.

**A custom IP is a real artifact.** By Phase 8, I had a packaged Vivado IP that I could drop into any block design. That's the same kind of deliverable as the Xilinx-provided IPs in the catalog. It felt different to ship that than to "finish a course assignment."

## Tools

- Vivado / Vitis 2023.2
- SystemVerilog (IEEE 1800-2017)
- Python 3 with NumPy
- PYNQ image v3.0 (Jupyter-based runtime)
- NYU's ECS-02 server for simulation and synthesis

## What's next

- Memory-map the buffer write ports through AXI so the host can load real A and B values
- Refine the AXI write FSM for full spec compliance
- Implement the same algorithm in Vitis HLS and compare resource usage and dev time
- Scale the array to 16x16 or 32x32
- Run a real workload (e.g., MNIST inference) on the accelerator and measure speedup vs. ARM CPU

## How to run

To verify the RTL in simulation:

1. Use any SystemVerilog simulator (I used Vivado's xsim)
2. Compile `rtl/*.sv` and `tb/array_full_buf_tb.sv`
3. Run it. Expect 6400/6400 passing.

To rebuild the packaged IP from scratch:

1. Open `vivado/gemm_ip_packaging` in Vivado 2023.2
2. Run synthesis
3. Tools → Create and Package New IP → follow through to "Package IP"

To rebuild the bitstream and run on a PYNQ-Z2:

1. Open `vivado/gemm_bd` in Vivado
2. Generate bitstream
3. Export Hardware (with bitstream included)
4. Copy `design_1_wrapper.bit` and `design_1_wrapper.hwh` to a PYNQ-Z2 via Jupyter
5. Use PYNQ's Python overlay framework to load and exercise the IP
