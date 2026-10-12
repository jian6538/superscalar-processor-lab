# RV32I superscalar hardware

This is a new educational out-of-order backend with a standard RV32I frontend. The separately integrated, unmodified PicoRV32 core provides a reference comparison. It is not an alteration of PicoRV32's internal pipeline.

## Instruction set and execution environment

The core implements all 40 RV32I base instruction forms: LUI, AUIPC, JAL, JALR; BEQ, BNE, BLT, BGE, BLTU, BGEU; LB, LH, LW, LBU, LHU; SB, SH, SW; ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI; ADD, SUB, SLL, SLT, SLTU, XOR, OR, AND, SRL, SRA; FENCE, ECALL, EBREAK. Registers x0..x31 and the PC are 32 bits; x0 is hardwired zero. PCs and effective addresses are byte addresses. Arithmetic wraps at 32 bits. Register shifts use only the low five shift-count bits.

The specification reference is [RV32I version 2.1](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html). Zicsr, Zifencei, compressed instructions, division, atomics, counters, and privileged instructions are separate extensions and are unsupported here. Reserved encodings trap.

`ENABLE_MUL=0` is the strict RV32I default. `ENABLE_MUL=1` adds the complete Zmmul multiplication subset: MUL, MULH, MULHSU, MULHU. It does not add DIV/REM or the full M extension. Reuse experiments explicitly use Zmmul.

This lab uses a minimal execution environment:

| Byte addresses | Behavior |
|---|---|
| `0x0000..0x03ff` | 256-word, execute-only instruction ROM, initialized by host writes while reset is asserted |
| `0x1000..0x13ff` | 256-word little-endian data RAM behind an eight-line data cache |
| Other addresses | Instruction/data access fault |

The instruction and data memories have separate host initialization ports; instruction memory cannot be read through the data port or modified by program stores. There is no OS, runtime loader, MMU, interrupt controller, or trap-handler vector. Misaligned halfword/word accesses trap rather than being emulated. Instruction alignment is four bytes.

ECALL and EBREAK produce precise stopping exceptions; the environment reports ECALL cause11 and EBREAK cause3. This convention does not imply a privileged machine-mode implementation. EBREAK ends each successful test; it is not a custom HALT instruction and does not retire as an ordinary instruction.

Fault outputs provide `fault_pc`, `fault_cause`, and `fault_value`. Causes are instruction alignment0, instruction access1, illegal instruction2, breakpoint3, load alignment4/access5, store alignment6/access7, and environment call11. Illegal-instruction value is the raw word; address faults report the effective address/target. Jumps with misaligned targets fault on the jump and do not commit the link register. Not-taken branches do not check target alignment. JALR clears bit0, then checks four-byte alignment.

## Fetch and decode

Fetch reads two contiguous words, increments the PC by four bytes, and uses a four-entry FIFO. Control flow ends the bundle. The frontend predicts conditional direction using not-taken, BTFNT, bimodal, gshare, local two-level, or a local/gshare tournament. A tagged 64-entry BTB predicts indirect targets. Indexing uses instruction-address bits `[7:2]`; BTB tags preserve the remaining address bits. There is no instruction cache or return-address stack.

Decode identifies R/I/S/B/U/J fields, sign-extends immediates, checks legal function fields, and maps standard instructions to internal operations. These internal operation numbers are implementation details, not an external custom ISA. The four-entry decode queue transfers up to two instructions per cycle.

## Dispatch and renaming

Dispatch allocates in program order. A 32-entry RAT and committed map track 64 physical registers; a bitmap allocates free destinations. Sources bind before changing the destination mapping. The second operation in a bundle sees the first one's new mapping. Sixteen ROB entries and sixteen reservation-station-style window entries hold the live instructions. Capacity exhaustion causes backpressure.

Renaming removes WAR/WAW name collisions while preserving RAW dependencies. The optional `RENAME=0` configuration instead uses conservative scoreboard interlocks and captured source operands. It blocks conflicting destination writers at dispatch.

## Issue and execution

`OOO=1` selects the oldest ready eligible instruction and can bypass a blocked older operation. `OOO=0` must select the oldest waiting instruction. Both allow two issue slots, at most one multiply initiation, and at most one load/store initiation per cycle. Both retain renaming, speculation and a ROB so this A/B comparison isolates scheduling. Long-latency completion may be out of order even with ordered issue.

ALUs execute combinationally and register completion at the issue edge. Dependent instructions can use the registered result on the following cycle, not in zero cycles. Signed comparisons and arithmetic shifts explicitly use signed values; byte/halfword loads perform sign or zero extension after lane selection.

The optional multiplier computes a full arithmetic product when issued, then delays result/tag/valid through four registers. It is not a balanced four-stage arithmetic multiplier. Signed/unsigned high-half products are supported. Generic synthesis can duplicate arithmetic across issue lanes; a one-per-cycle admission limit is not a promise of exactly one physical multiplier instance.

Writeback updates the physical register, readiness, and ROB result. There can be two immediate completions plus a multiply and load response in one cycle; finite common-data-bus arbitration is not modeled.

## Memory ordering and cache

ROB metadata forms the load/store ordering structure. Stores compute byte addresses, aligned data, and byte enables speculatively, but update memory only at ordered retirement. Loads wait for unknown older stores by default and may bypass known nonaliasing stores. Forwarding selects the youngest matching older store that covers every requested byte. A partially overlapping older store causes a wait until retirement; bytes are not incorrectly synthesized from incomplete forwarding data.

`MEM_SPEC=1` permits bypassing unknown older stores. When a store resolves an overlapping byte range after a younger load has executed, the core squashes that load and its younger consumers and re-fetches from the load. Alias checks compare word addresses and byte masks. The policy always speculates; there is no learned dependence predictor.

FENCE issues only when it reaches the ROB head and blocks younger memory operations while live. This is stronger ordering than the base requires. With one thread and no external devices/coherence, there is no modeled device or multiprocessor behavior.

The data cache has eight direct-mapped, one-word lines, write-through/write-allocate stores, and one outstanding read. Partial stores merge enabled bytes into backing RAM and the cached word. Nominal hit/miss delays are 2/12 cycles, followed by one registered interface cycle. Backing memory is on-chip RAM with delay counters, not a DRAM controller.

## Retirement, recovery and optional speculation

Up to two completed ROB-head instructions commit per cycle. Retirement updates architectural registers and the committed map, frees old physical mappings, and sends stores to the cache. A fault stops at the head; all older work has committed and younger work is suppressed.

Recovery preserves the older ROB prefix, clears younger queue/multiply entries, and reconstructs the RAT/free list from the committed map and surviving ROB in program order. The reconstruction is combinational rather than a constant-time checkpoint RAM. A pending load response is matched against both its ROB slot and its 32-bit sequence ID, protecting reused slots from late squashed responses. Age comparisons assume sequence IDs do not wrap during a run.

`REUSE=1` caches exact PC/operand multiply results. `VALUE_PRED=1` uses a confidence-gated last-value load predictor: consumers may execute with a predicted value, actual formatted load data validates it, and a mismatch squashes younger consumers. Only the real response can complete/retire the load. Predictor state is nonarchitectural and may receive wrong-path training.

## Interfaces and evidence

`processor_system` is the educational top level. `host_addr` and `debug_addr` select memory words; CPU addresses are bytes. Hold reset during instruction/data initialization, then hold `run` asserted until trapped. Pausing mid-request and host writes during execution are unsupported. Memories do not reset themselves to zero.

`debug_reg` is five bits and reads committed x registers. Stage events pack 14 enable bits, fourteen 32-bit PCs, and fourteen 32-bit dynamic IDs. The order is fetch2, decode2, dispatch2, issue2, writeback4, retire2. `run_lab.py` decodes these into cycle traces.

The runner checks all 32 registers, all 256 memory words, complete ordered retirement PCs, and precise exception PC/cause/value against an independent sequential interpreter. It also checks per-cycle ROB/window/rename invariants. `run_picorv32.py` compares successful terminating programs with the pinned upstream PicoRV32 core using the same instruction ROM and data cache. PicoRV32 exposes no equivalent external access-fault channel here, so fault tests use the independent interpreter rather than claiming identical PicoRV32 fault behavior.

Yosys checks elaboration, process lowering, structural consistency, and absence of inferred latches. This does not establish FPGA timing, placement/routing, power, area, formal equivalence, exhaustive ISA compliance, or silicon readiness.
