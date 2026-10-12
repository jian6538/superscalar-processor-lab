# Book technique coverage

Reference: Shen & Lipasti, *Modern Processor Design: Fundamentals of Superscalar Processors*. This is an educational RV32I superscalar implementation of selected mechanisms; it does not implement every technique in the book.

| Area | Status | Implementation |
|---|---|---|
| Pipelined front end and wide processing | Implemented with simplifications | Two-wide fetch/decode/dispatch/issue/retire, finite queues, backpressure; ALU execute and completion share an issue edge |
| Register renaming | Implemented | 32 architectural / 64 physical registers, RAT, committed map, free bitmap, same-bundle dependencies |
| Dynamic scheduling | Implemented | 16-entry centralized tag-based window, oldest-ready selection, in-order-issue switch, resource admission limits |
| Precise state | Implemented | 16-entry ROB, ordered commitment, stores at retirement, precise supported faults |
| Control speculation | Selected variants | Six direction predictors, tagged indirect BTB, wrong-path execution and prefix recovery |
| Memory dependence handling | Implemented with simplifications | Unknown-store waits, known nonalias bypass, covered-byte forwarding, optional unknown-store speculation and byte-overlap replay |
| Instruction reuse | Selected technique | Exact static-PC and operand multiply reuse; requires optional Zmmul |
| Value prediction | Selected technique | Confidence-gated last-value loads, validation and consumer squash |
| Memory hierarchy | Simplified | Tiny direct-mapped data L1, backing RAM, single outstanding read, configured latency counters |
| Fetch optimizations | Omitted families | No instruction cache, trace cache, multiblock/eager fetch, return stack, fusion or microcode |
| Alternative scheduling organizations | Omitted alternatives | No full original Tomasulo CDB, distributed scheduler, finite writeback bus arbitration, or complete family of dependence predictors |
| Commercial case studies | Not replicated | No PowerPC620/P6 replica; PicoRV32 is a separate scalar reference, not the modified OoO backend |
| Privilege, virtual memory, OS | Outside scope | No Zicsr, interrupts, trap handlers, MMU/TLB, paging or operating system |
| Multithreading / multiprocessors | Outside scope | No SMT, helper threads, coherence, multiprocessor consistency, atomics or DMA |
| Physical implementation | Not established | Structural synthesis only; no balanced arithmetic multiplier pipeline, FPGA placement/routing, measured frequency or power |

The RTL implements RV32I's 40 base instructions in a documented minimal execution environment. Multiplication is an optional complete Zmmul extension, not part of RV32I. [The architecture guide](docs/ARCHITECTURE.md) explains instructions, interfaces, timing, recovery and limitations.

Use the recorded manifest and logs to inspect what was actually tested. Passing directed/random programs and structural checks is not exhaustive or formal verification.
