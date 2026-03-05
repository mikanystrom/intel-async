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
  SystemVerilog        S-expression AST          Gate Netlist
  source file    -->   (via svfe --scm)    -->   (via svsynth)
      |                      |                        |
      |                 svbase.scm                    |
      |                 svlint.scm              svgates.scm
      |                 svgen.scm               svverify.scm
      |                 svsynth.scm              svfec.scm
      |                      |                        |
      +------+---------------+------------------------+
             |
        Verification
        (iverilog / Scheme FEC / exhaustive eval)
```

### Components

| File | Language | Description |
|------|----------|-------------|
| `sv/svparse/` | Modula-3 | LR(1) parser for SystemVerilog (`.t`/`.l`/`.y`/`.e` grammar) |
| `sv/svparse/.../svfe` | Binary | Parser frontend: `svfe [--scm] file.sv` |
| `sv/svsynth/` | Modula-3 | `svsynth` interpreter = mscheme + BDD primitives |
| `sv/svsynth/.../BDDPrims.m3` | Modula-3 | BDD primitives for mscheme (26 primitives) |
| `sv/src/svbase.scm` | Scheme | AST navigation, file I/O, utility functions |
| `sv/src/svsynth.scm` | Scheme | RTL-to-BDD compiler (expression/statement/module) |
| `sv/src/svgates.scm` | Scheme | Gate library + BDD-to-gate technology mapper |
| `sv/src/svverify.scm` | Scheme | Exhaustive functional equivalence verifier |
| `sv/src/svfec.scm` | Scheme | BDD-based Formal Equivalence Checking (FEC) |
| `sv/src/svlint.scm` | Scheme | Lint checks on ASTs |
| `sv/src/svgen.scm` | Scheme | SystemVerilog regeneration from AST |
| `sv/tests/verify/` | Verilog/Scheme | Test designs, gate netlists, iverilog testbenches |

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

## Synthesis Pipeline

The BDD-to-gate technology mapper (`svgates.scm`) performs
Shannon expansion with pattern recognition:

1. **Parse** RTL to S-expression AST (svfe --scm)
2. **Build BDDs** for each output signal (svsynth.scm)
3. **Map** BDD nodes to gate instances (svgates.scm):
   - BDD TRUE → TIEH
   - BDD FALSE → TIEL
   - ITE(v, TRUE, FALSE) → wire (pure variable)
   - ITE(v, FALSE, TRUE) → INV
   - ITE(a, b, FALSE) → AND2
   - ITE(a, TRUE, b) → OR2
   - ITE(a, NOT b, TRUE) → NAND2
   - ITE(a, FALSE, NOT b) → NOR2
   - ITE(a, NOT b, b) → XOR2
   - ITE(a, b, NOT b) → XNOR2
   - General case → MUX2(A=low, B=high, S=var)
4. **Emit** structural Verilog netlist

---

## Verification Methods

Three independent verification approaches confirm correctness:

### 1. Exhaustive Simulation (svverify.scm)

The Scheme-based functional verifier evaluates **both** the BDD
and the gate netlist for every possible input combination and
compares results.

- Runs inside mscheme — no external simulator required
- Provides exact counterexample vectors on failure
- Practical for designs up to ~20 inputs (2^20 = 1M vectors)
- Tests the gate evaluator independently of the BDD library

### 2. Formal Equivalence Checking (svfec.scm)

BDD-based FEC proves equivalence for **all** input combinations
without enumerating them:

1. Build BDD from the original RTL expressions ("golden" reference)
2. Rebuild BDD from the gate netlist by interpreting each gate
   as a Boolean equation (INV→NOT, AND2→AND, MUX2→ITE, etc.)
3. Compare with `bdd-equal?` — canonical BDDs are equal iff the
   functions are identical

This is the same methodology used by commercial FEC tools
(Synopsys Formality, Cadence Conformal).  It scales to
arbitrarily many inputs since there is no enumeration.

For **sequential designs**, the combinational cones between
register Q outputs (treated as primary inputs) and register D
inputs (treated as primary outputs) form the equivalence points.
This register-to-register FEC is planned but not yet implemented
in the automated pipeline.

### 3. iverilog Simulation

Standard Verilog simulation using Icarus Verilog:

- Compiles both RTL and gate-level netlist with cell library
- Testbench exhaustively applies all input combinations
- Cycle-by-cycle output comparison
- Validates that emitted Verilog is syntactically correct and
  accepted by a third-party tool

---

## Test Results

### Unit Tests (17 tests each)

| Test | svverify | svfec |
|------|----------|-------|
| const-true | PASS | EQUIVALENT |
| const-false | PASS | EQUIVALENT |
| wire | PASS | EQUIVALENT |
| NOT | PASS | EQUIVALENT |
| AND | PASS | EQUIVALENT |
| OR | PASS | EQUIVALENT |
| XOR | PASS | EQUIVALENT |
| NAND | PASS | EQUIVALENT |
| NOR | PASS | EQUIVALENT |
| XNOR | PASS | EQUIVALENT |
| IMPLIES | PASS | EQUIVALENT |
| ITE | PASS | EQUIVALENT |
| MUX4 | PASS | EQUIVALENT |
| XOR-chain | PASS | EQUIVALENT |
| complex | PASS | EQUIVALENT |
| majority | PASS | EQUIVALENT |
| parity | PASS | EQUIVALENT |

### RTL Design Tests (12 designs)

| Design | Inputs | Outputs | Gates | Vectors | svverify | svfec | iverilog |
|--------|--------|---------|-------|---------|----------|-------|----------|
| test_and2 | 2 | 1 | 1 | 4 | PASS | EQUIV | PASS |
| test_or2 | 2 | 1 | 1 | 4 | PASS | EQUIV | — |
| test_xor_chain | 4 | 1 | 5 | 16 | PASS | EQUIV | PASS |
| test_mixed | 4 | 2 | 6 | 16 | PASS | EQUIV | PASS |
| test_mux4 | 6 | 1 | 3 | 64 | PASS | EQUIV | PASS |
| test_majority | 3 | 1 | 3 | 8 | PASS | EQUIV | — |
| test_priority | 4 | 2 | 4 | 16 | PASS | EQUIV | — |
| test_adder | 3 | 2 | 6 | 8 | PASS | EQUIV | PASS |
| test_alu1 | 4 | 1 | 6 | 16 | PASS | EQUIV | PASS |
| test_compare | 2 | 3 | 5 | 4 | PASS | EQUIV | PASS |
| test_decoder | 2 | 4 | 6 | 4 | PASS | EQUIV | PASS |
| test_parity8 | 8 | 1 | 13 | 256 | PASS | EQUIV | PASS |

Total: **416 simulation vectors**, all passing.
FEC: **12 modules, 19 outputs**, all formally proven equivalent.

### Parser Test Results

The svfe parser was tested on 25 open-source SystemVerilog files
from ibex, cva6, PULP, PicoRV32, ZipCPU, and Surelog test suites:

- **3/25 pass** (surelog_enum.sv, surelog_generate.sv, eth_mac_1g.v)
- **22/25 fail** — common failure causes:
  - Package imports (`import pkg::*`)
  - `typedef` / `enum` / `struct` in module scope
  - SystemVerilog `unique case`, `inside` operator
  - Multi-dimensional arrays, parameterized types
  - `for` loop variable declarations
  - Interface/modport references

The parser handles the core SV subset (modules, ports, wires,
assigns, always blocks, basic expressions) but many real-world
constructs remain unsupported.

---

## Bug Fixes This Session

1. **BDD wire cache collision** — `cache-lookup` used `bdd-id`
   which returns the root variable id (not unique per node).
   Multi-output modules got wrong results.  Fixed: use
   `bdd-equal?` for cache key comparison.

2. **FEC variable identity** — `netlist-to-bdds` created fresh
   BDD variables with `bdd-var`, getting different internal ids
   from the RTL-side variables.  Fixed: reuse variables from
   `*bdd-env*` so BDDs are directly comparable.

---

## Pending Work

- [ ] Extend parser for remaining SV constructs (packages, typedefs, etc.)
- [ ] Register-to-register FEC automation (parse sequential RTL,
      identify register boundaries, verify combinational cones)
- [ ] Multi-bit signal support in synthesizer
- [ ] Gate count optimization (common subexpression sharing across outputs)
- [ ] Timing-aware synthesis / area optimization
