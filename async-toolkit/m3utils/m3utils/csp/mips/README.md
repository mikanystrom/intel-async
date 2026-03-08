# MiniMIPS II

An asynchronous MIPS I processor implemented as a network of seven
communicating sequential processes, following Martin's synthesis
methodology.

## Architecture

Seven processes connected by 26 point-to-point channels:

| Process    | File            | Role                                    |
|------------|-----------------|-----------------------------------------|
| Fetch      | `fetch.csp`     | PC management, instruction memory       |
| Decode     | `decode.csp`    | Field extraction, register file reads   |
| Execute    | `execute.csp`   | ALU, branches, syscalls, HI/LO regs     |
| MemStage   | `memstage.csp`  | Load/store routing via DataMem server    |
| Writeback  | `writeback.csp` | Register file writes, branch feedback   |
| RegFile    | `regfile.csp`   | 32-register file (2 read, 1 write port) |
| DataMem    | `dmem.csp`      | 64KB byte-addressable memory            |

Execute sends results to MemStage via a single 107-bit struct-typed
channel (`EmData`), packing seven fields into one communication.

The system is composed in `minimips.sys`.

## Building the simulator

Prerequisites: cm3 (Modula-3 compiler), cspc (CSP compiler, built from
`csp/src`), cspfe (CSP parser, built from `csp/cspparse`).

```sh
bash build.sh
```

This parses all `.csp` files, compiles them through cspc, generates
Modula-3 simulation code, and invokes cm3 to produce
`build/<TARGET>/sim`.

## Running

The simulator reads `program.hex` (instruction memory) and `data.hex`
(data memory) from the current directory.

```sh
cp tests/count10k.hex program.hex
cp tests/count10k_data.hex data.hex
./build/$(../../m3arch.sh)/sim
```

## Cross-compiling C programs

Prerequisites: LLVM with MIPS target (`brew install llvm lld`).

```sh
make tests/fibonacci.hex    # compile a single test
make all                    # compile all tests
make run-fibonacci          # compile and run
```

The toolchain: clang (mipsel-unknown-elf, `-mcpu=mips1`) -> ld.lld
(custom `link.ld`) -> `mips2hex.py` (ELF to hex).

Support files:
- `crt0.s` -- startup code (init `$sp`, call `main`, halt)
- `syscalls.c` -- `print_int()`, `print_char()`, `halt()` via MIPS SYSCALL
- `link.ld` -- linker script (.text at 0, .data at 0x10000)
- `mips2hex.py` -- extracts .text and .data sections to hex files

## Test programs

| Test       | Source | Description                              |
|------------|--------|------------------------------------------|
| trivial    | asm    | ADDIU, SYSCALL                           |
| arith      | asm    | ALU operations                           |
| branch     | asm    | BEQ, BNE, J, delay slots                |
| loop       | asm    | BEQ loop, sum 1..5                       |
| memory     | asm    | SW, LW                                   |
| jal        | asm    | JAL, JR, delay slots                     |
| fibonacci  | C      | Iterative Fibonacci (10 terms)           |
| collatz    | C      | Collatz sequence from 27                 |
| sort       | C      | Bubble sort with .data initialization    |
| count10k   | C      | Count to 10,000 (performance benchmark)  |
| count100k  | C      | Count to 100,000 (performance benchmark) |

## Performance

On Apple M3 (single-threaded), counting to 10,000 (90K MIPS instructions):

- 0.41s wall clock, ~220K MIPS instructions/s
- ~38 simulation events per MIPS instruction
- ~8.3M events/s

## Documentation

`minimips.tex` contains a detailed writeup (16 pages) covering the
architecture, decomposition from sequential specification, correctness
argument, syscall interface, and performance analysis.

```sh
pdflatex minimips.tex && pdflatex minimips.tex
```
