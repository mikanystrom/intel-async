# SV Toolkit Status Report

**Date:** March 2026
**Branch:** `claude_edits`

## Tool Overview

The SV toolkit is a SystemVerilog frontend, logic synthesizer, and
verification system built on the CM3 `parserlib` metacompiler and
`mscheme` Scheme interpreter.  All tools interoperate through
S-expression ASTs.

### Architecture

```
  SystemVerilog        S-expression AST          Gate Netlist / C eval
  source file    -->   (via svfe --scm)    -->   (via svsynth)
      |                      |                        |
   svpp                 svbase.scm              svemit.scm (gate SV)
  (preprocessor)        svbv.scm (BDD)          svemit-c.scm (C code)
      |                 svlint.scm                    |
      |                 svgen.scm               Verification
      |                      |                  (FEC / exhaustive / C)
      +------+---------------+------------------------+
             |
        sveqc (equivalence checking)
        svlint (RTL lint)
```

### Components

| File | Language | Description |
|------|----------|-------------|
| `sv/svparse/` | Modula-3 | LR(1) parser for SystemVerilog (`.t`/`.l`/`.y`/`.e` grammar) |
| `sv/svparse/.../svfe` | Binary | Parser frontend: `svfe [--scm] file.sv` |
| `sv/svsynth/` | Modula-3 | `svsynth` interpreter = mscheme + BDD primitives (22 primitives) |
| `sv/svpp/` | Modula-3 | Standalone preprocessor (`` `define ``, `` `ifdef ``, `` `include ``, etc.) |
| `sv/src/svbase.scm` | Scheme | AST navigation, file I/O, signal collection, utility functions |
| `sv/src/svbv.scm` | Scheme | Bit-level BDD synthesis engine (multi-bit, LRM-correct widths) |
| `sv/src/svemit.scm` | Scheme | BDD-to-gate-level SV emitter (Shannon expansion MUX decomposition) |
| `sv/src/svemit-c.scm` | Scheme | BDD-to-C emitter (generates static inline eval functions) |
| `sv/src/svsop.scm` | Scheme | BDD-to-SOP equation emitter (minimized sum-of-products) |
| `sv/src/svlint.scm` | Scheme | RTL lint checks (7 rules) |
| `sv/src/svgen.scm` | Scheme | SystemVerilog regeneration from AST |

### Tools

| Tool | Script | Description |
|------|--------|-------------|
| svlint | `sv/svlint/run-svlint.sh` | RTL lint (undriven, unused, multi-driver, latches, loops, widths, blocking-in-ff) |
| sveqc | `sv/sveqc/run-sveqc.sh` | Self-equivalence check (RTL → BDD → gate SV → BDD → compare) |
| svsop | `sv/svsop/run-svsop.sh` | SOP equation output (RTL → BDD → minimized sum-of-products) |
| 6502 gen | `sv/6502/gen-c-eval.sh` | Generate C eval functions from ALU BDDs |
| 6502 test | `sv/6502/run-6502-tests.sh` | Full 6502 test suite (BDD gen + ALU exhaustive + Dormann) |

---

## Parser Status

The svfe parser supports a broad subset of SystemVerilog including:
modules, packages, interfaces, modports, typedefs, enums, structs,
always_ff/comb/latch, if/case/for/while/generate, functions/tasks,
delay controls, event controls, real/time types, float literals,
full expression hierarchy, module instantiation, signed/unsigned,
type casts, streaming operators, DPI-C export, escaped identifiers,
unique/priority case.

### Parser Test Results

| Test Suite | Files | Pass | Status |
|------------|-------|------|--------|
| sv/tests/verify/ | 21 | 21 | 100% |
| ibex/rtl/ | 30 | 30 | 100% |
| ibex prim/rtl/ | 161 | 161 | 100% |

---

## BDD Synthesis Engine (svbv.scm)

The bit-level BDD synthesis engine handles:
- Multi-bit signals with LRM-correct width inference
- Arithmetic (+, -, *), bitwise (&, |, ^, ~), comparison (<, <=, ==, !=)
- Concatenation on both LHS and RHS
- Part-select (range), bit-select (index)
- Reduction operators (&, |, ^)
- Shift operators (<<, >>)
- Ternary (? :), case statements with default
- localparam/parameter constant evaluation
- always_comb, always @(*) combinational blocks

### BDD Synthesis Tests (8 modules)

| Design | Description | Status |
|--------|-------------|--------|
| 4-bit adder | Carry-chain addition | PASS |
| 4-bit subtractor | Two's complement subtraction | PASS |
| 4-bit bitwise ops | AND/OR/XOR/NOT | PASS |
| 4-bit comparator | All comparison operators | PASS |
| 4-bit wide mux | 4-input multiplexer | PASS |
| 8-bit reductions | Reduction AND/OR/XOR | PASS |
| 4-bit shifts | Logical left/right shifts | PASS |
| 8-bit range/index | Part-select and bit-select | PASS |

### Round-trip Verification

Behavioral SV → BDDs → gate-level SV → BDDs → compare:
all outputs match (symbolic BDD comparison, not enumeration).

### SOP Minimization

BDD → SOP conversion using Caltech `sop` library
(`SopBDD.ConvertBool` + `invariantSimplify`).  Exposed via three
svsynth primitives: `bdd->sop`, `bdd->sop-raw`, `bdd->sop-terms`.

Tool: `sv/svsop/run-svsop.sh` — generates minimized SOP equations
for all combinational outputs.  Supports `--cut N` flag for BDD
decomposition on arithmetic-heavy designs.

Two-tier output strategy based on BDD size:
- ≤50 nodes: minimized SOP (`invariantSimplify`)
- >50 nodes: MUX tree (syntax-directed BDD walk, one wire per node)

BDD cuts in `bv-eq` and reduction operators prevent blowup on
wide equality tests (e.g., zero flag `val == 8'd0`).

### SOP Test Results

| Design | Cuts | Outputs | Status |
|--------|------|---------|--------|
| 6502 ALU | 70 | 6 | PASS (all equations, ~30s with --cut 30) |
| 6502 CPU | 417 | 18 (56 bits) | PASS (all equations, ~30s with --cut 30) |
| test_add4 | 0 | 1 | PASS (no cuts needed) |
| test_cmp4 | 0 | 4 | PASS |
| test_mux4w | 0 | 1 | PASS |

### Case Decomposition

Large case statements and if-else chains (exceeding
`*bv-decomp-threshold*`, default 8 arms) use decoder+MUX
architecture: each arm's match condition and body are compiled
independently, then combined with one-hot OR (case) or priority
MUX (if-else), with `bdd-maybe-cut` applied during accumulation.
This avoids BDD blowup on wide decoders.

---

## Gate Library

Standard cell library with behavioral Verilog models for simulation:

| Cell | Function | Ports | Area |
|------|----------|-------|------|
| INV | NOT | A→Y | 1 |
| BUF | buffer | A→Y | 1 |
| NAND2 | a NAND b | A,B→Y | 2 |
| NOR2 | a NOR b | A,B→Y | 2 |
| AND2 | a AND b | A,B→Y | 2 |
| OR2 | a OR b | A,B→Y | 2 |
| XOR2 | a XOR b | A,B→Y | 3 |
| XNOR2 | a XNOR b | A,B→Y | 3 |
| MUX2 | S?B:A | A,B,S→Y | 4 |
| TIEH | constant 1 | →Y | 0 |
| TIEL | constant 0 | →Y | 0 |
| DFF | D flip-flop | D,CK→Q | 6 |
| DFFR | DFF + async reset | D,CK,RN→Q | 7 |
| DFFS | DFF + async set | D,CK,SN→Q | 7 |
| DFFRS | DFF + reset + set | D,CK,RN,SN→Q | 8 |

---

## 6502 CPU Model

### ALU (sv/6502/rtl/ALU.sv)

Pure combinational ALU supporting 15 operations (ADC, SBC, AND, ORA,
EOR, ASL, LSR, ROL, ROR, INC, DEC, CMP, BIT, PASS_A, PASS).

BDD synthesis produces ~17K total BDD nodes across 5 output signals.
The BDD-to-C emitter generates ~12K temp variables in the C eval header.

### Exhaustive ALU Verification

The BDD-generated C evaluation functions are verified against a
reference C implementation for all input combinations:

- 15 ops × 256 a × 256 operand × 2 carry = **1,966,080 test vectors**
- Checks: result, carry_out, zero_out, sign_out, overflow_out
- **All pass (0 failures)**

### Reference Emulator (fake6502)

The fake6502 reference emulator passes Klaus Dormann's 6502 functional
test suite:
- **30,646,179 instructions, 96,561,376 cycles**
- Success at PC = 0x3469

---

## RTL Lint (svlint)

Seven lint rules operating on ASTs:

| Rule | Description |
|------|-------------|
| Undriven outputs | Output ports with no driver |
| Unused signals | Declared signals never read |
| Multiple drivers | Same signal assigned in >1 always/assign |
| Latch inference | Incomplete if/case in always_comb |
| Combinational loops | Cycle in assign dependency graph |
| Width mismatches | LHS/RHS width differ in assignments |
| Blocking in FF | Blocking `=` in always_ff |

Test suite: 7/7 tests pass.

---

## Equivalence Checking (sveqc)

Self-equivalence check pipeline:
1. Parse RTL → build BDDs for each output
2. Emit gate-level SV from BDDs
3. Re-parse gate-level SV → rebuild BDDs (sharing input variables)
4. Compare output BDDs bit-by-bit with `bdd-equal?`

Test results: **8/8 modules verified** (self-equivalence).

---

## Pending Work

- [ ] Synthesize full 6502 CPU combinational cones (decoder, address gen)
- [ ] Multi-backend 6502 emulator (BDD-eval vs reference cycle comparison)
- [ ] Register-to-register FEC automation
- [ ] Gate count optimization (common subexpression sharing)
- [ ] Extend parser: import "DPI-C", packed unions
