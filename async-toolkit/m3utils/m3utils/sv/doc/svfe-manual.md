# svfe -- SystemVerilog Frontend

Mika Nystroem, March 2026


## 1. Overview

svfe is a SystemVerilog parser that produces S-expression output suitable for
processing by Scheme scripts.  It is built on the CM3 parserlib metacompiler
and supports the synthesizable subset of IEEE 1800-2017 SystemVerilog as
accepted by Synopsys Design Compiler and Cadence Genus.

The tool is part of a pipeline:

    SystemVerilog source (.sv / .v / .vh)
      --> svfe --scm          parse and emit S-expressions
      --> mscheme              analyze, lint, transform

The S-expression output preserves the full structure of the source code and
can be consumed by any Scheme implementation.  The companion script
`svread.scm` provides analysis and lint checks for use with mscheme.


## 2. Building

svfe is built with the CM3 Modula-3 compiler.  From the `sv/svparse/`
directory:

```
$ cm3 -override
```

This invokes the parserlib metacompiler to generate the lexer (from `sv.l`),
parser (from `sv.y`), and extensions (from `svLexExt.e`, `svParseExt.e`),
then compiles and links the svfe binary.

The binary is placed in `sv/svparse/AMD64_LINUX/svfe` (or the appropriate
platform directory).

**Prerequisites:**

- CM3 compiler with parserlib installed
- A `.top` file in the m3utils root (see cm3 documentation)
- The `m3overrides` file (included)


## 3. Usage

### 3.1 Command-line options

```
svfe [--scm] [--lex] [--name <module>] <file.sv>
```

| Option | Description |
|--------|-------------|
| `--scm` | Emit S-expression output (default mode) |
| `--lex` | Emit lexer token stream (for debugging) |
| `--name` | Set the module name for error messages |

### 3.2 Basic usage

```
$ svfe --scm mymodule.sv
```

This parses the file and writes S-expressions to standard output, one per
top-level construct.  Errors are reported to standard error with line numbers.

### 3.3 Piping to Scheme

```
$ svfe --scm mymodule.sv > /tmp/ast.scm
```

Then in mscheme:

```scheme
> (load "sv/src/svread.scm")
> (define ast (read-sv-file "/tmp/ast.scm"))
> (lint-all ast)
=== Module: mymodule ===
  Ports: 8 (in: 5 out: 3)
  Local signals: 12
  Assigned signals: 14
```


## 4. Supported Language Constructs

### 4.1 Declarations

| Construct | Description |
|-----------|-------------|
| `module` / `endmodule` | Module declarations (ANSI ports) |
| `package` / `endpackage` | Package declarations |
| `interface` / `endinterface` | Interface declarations |
| `modport` | Interface modport declarations |
| `import pkg::item` | Package imports (including `::*`) |
| `import` before ports | Module-level import declarations |
| `typedef` | Type aliases |
| `parameter`, `localparam` | Compile-time constants |
| `function` / `endfunction` | Function declarations (automatic) |
| `task` / `endtask` | Task declarations (automatic) |

### 4.2 Types

| Type | Description |
|------|-------------|
| `logic`, `wire`, `reg` | Net and variable types |
| `integer` | 32-bit integer type |
| `bit`, `byte`, `shortint` | Small integer types |
| `int`, `longint` | Sized integer types |
| `string`, `void` | Other built-in types |
| `signed`, `unsigned` | Signedness qualifiers |
| `enum` | Enumerated types |
| `struct packed` | Packed structures |
| `[N:M]` | Packed bit ranges |
| `[N:M][P:Q]` | Multi-dimensional packed arrays |
| `[0:N-1]` | Unpacked array dimensions |
| User-defined types | Via typedef or package import |

### 4.3 Statements

| Statement | Description |
|-----------|-------------|
| `assign` | Continuous assignments |
| `always @(...)` | Classic sensitivity lists |
| `always_comb` | Combinational blocks |
| `always_ff @(posedge ...)` | Sequential (flip-flop) blocks |
| `always_latch` | Latch blocks |
| `if` / `else` | Conditional statements |
| `case`, `casez`, `casex` | Case statements |
| `unique case`, `priority case` | SV case qualifiers |
| `begin` / `end` | Block grouping (with optional names) |
| `=` (blocking) | Blocking assignment |
| `<=` (non-blocking) | Non-blocking assignment |
| `for` | For loops (with `int`/`genvar`) |
| `while`, `repeat`, `forever` | Other loops |
| `return` | Function return |
| `++`, `--` | Pre/post increment/decrement |
| `+=`, `-=`, `*=`, `/=`, `%=` | Compound assignment operators |
| `&=`, `\|=`, `^=`, `<<=`, `>>=` | Bitwise compound assignments |

### 4.4 Expressions

| Category | Operators |
|----------|-----------|
| Arithmetic | `+` `-` `*` `/` `%` `**` |
| Logical | `&&` `\|\|` `!` |
| Bitwise | `&` `\|` `^` `~` `~&` `~\|` `~^` |
| Shift | `<<` `>>` `<<<` `>>>` |
| Relational | `==` `!=` `<` `>` `<=` `>=` |
| Identity | `===` `!==` |
| Wildcard | `==?` `!=?` |
| Ternary | `? :` |
| Concat | `{ }` |
| Replication | `{N{expr}}` |
| Part select | `[+:]` `[-:]` |
| Member | `expr.field` (struct access) |
| Function | `func(args)` |
| System | `$clog2()`, `$bits()`, `$signed()`, etc. |

### 4.5 Number literals

| Format | Example |
|--------|---------|
| Verilog format | `8'hFF`, `32'd0`, `4'b1010`, `16'shFFFF` |
| Unsized | `'h3F`, `'0`, `'1`, `'x`, `'z` |
| Plain decimal | `42`, `1_000_000` |

### 4.6 Generate

| Construct | Description |
|-----------|-------------|
| `generate` / `endgenerate` | Generate regions |
| `for` generate | Parameterized replication |
| `if` generate | Conditional instantiation |
| `genvar` | Generate variables |
| `begin : name ... end` | Named generate blocks |

### 4.7 Module instantiation

| Style | Syntax |
|-------|--------|
| Named ports | `.port(signal)` |
| Implicit named | `.port` (shorthand for `.port(port)`) |
| Positional | `signal` |
| Wildcard | `.*` |
| Parameters | `#(.PARAM(val))` |

### 4.8 Other

| Feature | Description |
|---------|-------------|
| `//` and `/* */` | Comments (stripped by lexer) |
| `` `directive `` | Compiler directives (preserved as `(directive)` nodes) |
| Hierarchical ids | `a.b`, `pkg::name` |


## 5. S-Expression Format

The output is standard Scheme S-expressions.  Each top-level construct
produces one form.  The key node types are documented in `svread.scm` and
summarized here.

### 5.1 Top-level forms

```scheme
(module <name> [<import>...] <params> <ports> <body>...)
(package <name> <items>...)
(interface <name> <params> <ports> <items>...)
(typedef <type-def> <name>)
(import <items>)
```

### 5.2 Module body items

```scheme
(decl <type> (id <name> [<dims>]) ...)
(assign (= <lvalue> <expr>))
(always_ff <sensitivity> <statement>)
(always_comb <statement>)
(always_latch <sensitivity> <statement>)
(generate <items>...)
(ident-item <type-or-module> ...)
(function ...)
(directive)
```

### 5.3 Statements

```scheme
(= <lvalue> <expr>)                ;; blocking assignment
(<= <lvalue> <expr>)               ;; non-blocking assignment
(begin [<name>] <stmts>...)        ;; sequential block
(if <cond> <then> [<else>])        ;; conditional
(case <expr> (<match> <stmt>)...)  ;; case statement
(casez <expr> (<match> <stmt>)...) ;; casez statement
(for <init> <cond> <step> <body>)  ;; for loop
(null)                             ;; null statement
(return [<expr>])                  ;; function return
```

### 5.4 Expressions

```scheme
(id <name>)                        ;; identifier
(scoped <pkg> <name>)              ;; package-scoped id
(+ <a> <b>)                        ;; addition (similarly for all binary operators)
(~ <a>)                            ;; bitwise NOT
(! <a>)                            ;; logical NOT
(?: <cond> <then> <else>)          ;; ternary
(index <expr> <idx>)               ;; bit/array select
(range <expr> <hi> <lo>)           ;; part select
(+: <expr> <base> <width>)         ;; ascending part select
(-: <expr> <base> <width>)         ;; descending part select
(field <expr> <member>)            ;; struct member access
(concat <exprs>...)                ;; concatenation
(replicate <count> <exprs>...)     ;; replication
(call <func> <args>...)            ;; function call
(sys <name>)                       ;; system function
```

### 5.5 Types in declarations

```scheme
(logic <signing> <packed-dims>)
(reg <signing> <packed-dims>)
(bit <signing> <packed-dims>)
(int <signing>)
(integer)
(enum <base-type> <members>...)
(struct <members>...)
```

### 5.6 Port declarations

```scheme
(ports
  (port <dir> <type> <signing> <dims> (id <name> [<dims>]))
  (port-ident <name>)
  (port-if <interface.modport> (id <name>))
  ...)
```

### 5.7 Sensitivity lists

```scheme
(sens (posedge <expr>) (negedge <expr>) ...)
(sens *)
```

### 5.8 Example

Given this SystemVerilog:

```systemverilog
module counter #(parameter W = 8) (
  input  logic       clk,
  input  logic       rst_n,
  output logic [W-1:0] count
);
  logic [W-1:0] cnt_q;
  assign count = cnt_q;
  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) cnt_q <= '0;
    else        cnt_q <= cnt_q + 1;
endmodule
```

svfe `--scm` produces:

```scheme
(module counter
  (parameters (parameter () W 8))
  (ports (port input logic (id clk))
         (port input logic (id rst_n))
         (port output logic [(- (id W) 1):0] (id count)))
  (decl (logic [(- (id W) 1):0]) (id cnt_q))
  (assign (= (id count) (id cnt_q)))
  (always_ff (sens (posedge (id clk)) (negedge (id rst_n)))
    (if (! (id rst_n))
        (<= (id cnt_q) '0)
        (<= (id cnt_q) (+ (id cnt_q) 1)))))
```


## 6. RTL Lint Tool (svlint)

The svlint tool performs static analysis on SystemVerilog RTL, checking
for common coding errors and synthesis pitfalls.

### 6.1 Usage

```
$ sv/svlint/run-svlint.sh [--pp-flags FLAGS] input.sv [input2.sv ...]
```

The tool preprocesses, parses, and analyzes each input file, reporting
warnings to standard output.

### 6.2 Checks

| Check | Description |
|-------|-------------|
| Undriven outputs | Output ports with no driver |
| Unused signals | Declared signals or input ports never read |
| Multiple drivers | Signal assigned in more than one always/assign block |
| Latch inference | Incomplete if/case in always_comb / always @(*) |
| Blocking in always_ff | Blocking (=) in sequential blocks |
| Non-blocking in always_comb | Non-blocking (<=) in combinational blocks |
| Width mismatches | LHS/RHS widths differ in assignments |

### 6.3 Example output

```
=== Module: my_design ===
  WARNING: output 'valid' is never driven
  WARNING: signal 'debug_cnt' is declared but never used
  WARNING: possible latch on 'state_next' in always_comb (incomplete if/case)
  Ports: 8 (in: 5 out: 3)
  Local signals: 12
  Assigned signals: 14

Total warnings: 3
```

### 6.4 Implementation

Lint checks are implemented in `sv/src/svlint.scm`, loaded by the driver
`sv/src/svlint-driver.scm`.  The driver is invoked via svsynth (mscheme
with BDD primitives), though lint checks are pure AST analysis and do not
use BDDs.

### 6.5 Test suite

```
$ sv/tests/lint/run-lint-tests.sh    # 7 targeted tests
```

The lint tool has been validated on all 30 ibex RTL files (those that parse).


## 7. Equivalence Checking Tool (sveqc)

The sveqc tool performs formal equivalence checking of combinational
SystemVerilog modules using BDD-based symbolic comparison.

### 7.1 Usage

**Self-check** (synthesize to BDDs, optionally emit gate-level SV):

```
$ sv/sveqc/run-sveqc.sh [--gate-out gates.sv] input.sv
```

**Two-file comparison** (compare two designs):

```
$ sv/sveqc/run-sveqc.sh input.sv reference.sv
```

### 7.2 How it works

1. Parse both designs (or one for self-check) to S-expression ASTs
2. Build BDDs for each output of each design, sharing input BDD variables
3. Compare output BDDs bit-by-bit using `bdd-equal?`
4. Report MATCH/MISMATCH per output

For single-file mode, the tool synthesizes BDDs and reports BDD node
counts per output.  With `--gate-out`, it also emits gate-level SV
using Shannon expansion (MUX decomposition).

### 7.3 Round-trip verification

The tool supports a round-trip flow:

    behavioral SV → BDDs → gate-level SV → BDDs → compare

This verifies that the gate-level emission is correct: both the
original behavioral design and the synthesized gate-level netlist
produce identical BDDs.

### 7.4 Test suite

```
$ sv/tests/run-eqc-tests.sh    # 8 self-check + 8 round-trip tests
```

### 7.5 Limitations

BDD-based equivalence checking works well for modules with fewer than
~24 input bits.  Larger modules may experience exponential BDD growth.
Only combinational logic is verified; sequential elements (always_ff)
are excluded.


## 8. BDD Logic Synthesis (svsynth)

The svsynth tool extends mscheme with BDD primitives, enabling
logic synthesis and formal verification of combinational SV.

### 8.1 Scheme libraries

| File | Description |
|------|-------------|
| `svbase.scm` | AST navigation, signal collection, utilities |
| `svbv.scm` | Bit-level BDD synthesis engine (multi-bit, LRM-correct widths) |
| `svemit.scm` | BDD-to-gate-level SV emitter (Shannon expansion) |
| `svemit-c.scm` | BDD-to-C emitter (generates evaluation functions) |
| `svlint.scm` | Lint checks (AST-only, no BDDs) |
| `svgen.scm` | SV code regeneration from AST |

### 8.2 BDD primitives

Available in svsynth's mscheme:

| Function | Description |
|----------|-------------|
| `(bdd-var name)` | Create a new BDD variable |
| `(bdd-and a b)` | Boolean AND |
| `(bdd-or a b)` | Boolean OR |
| `(bdd-not a)` | Boolean NOT |
| `(bdd-equal? a b)` | Test BDD equality |
| `(bdd-true? b)` | Test if constant true |
| `(bdd-false? b)` | Test if constant false |
| `(bdd-size b)` | Count BDD nodes |
| `(bdd-node-var b)` | Get decision variable |
| `(bdd-high b)` | Get high (then) child |
| `(bdd-low b)` | Get low (else) child |
| `(bdd-name v)` | Get variable name string |

### 8.3 Test suites

```
$ sv/tests/run-bvsynth-tests.sh     # 8 bit-level synthesis tests
$ sv/tests/run-roundtrip-test.sh    # Combinational round-trip
$ sv/tests/run-flop-demo.sh         # Sequential ALU pipeline demo
```


## 9. MOS 6502 Demo

A complete MOS 6502 CPU model written from scratch in SystemVerilog,
with a C reference emulator and BDD-synthesized ALU.

### 9.1 Components

| Path | Description |
|------|-------------|
| `sv/6502/rtl/ALU.sv` | Combinational ALU (15 operations, 21 input bits) |
| `sv/6502/rtl/cpu.sv` | Full CPU FSM (32 states, async reset) |
| `sv/6502/emu/fake6502.c` | C reference model (public domain, BCD-fixed) |
| `sv/6502/emu/emu6502.c` | Test harness (64KB memory, Dormann test) |
| `sv/6502/emu/alu_bdd_eval.h` | Generated C functions from BDD synthesis |

### 9.2 Running the emulator

```
$ sv/6502/run-6502-test.sh
```

This builds the emulator, runs the Klaus Dormann 6502 functional test
suite (~30M instructions), and verifies parse of the SV models.

### 9.3 ALU synthesis

```
$ sv/6502/run-6502-synth.sh
```

Parses ALU.sv and cpu.sv through svfe, synthesizes ALU to BDDs, and
analyzes combinational cones of the CPU.

### 9.4 C code generation

```
$ sv/6502/gen-c-eval.sh
```

Generates `alu_bdd_eval.h` — C functions that evaluate the ALU
combinational logic using ternary expressions derived from BDDs.


## 10. Preprocessor (svpp.py)

A standalone Python preprocessor for SystemVerilog:

```
$ python3 sv/src/svpp.py [-D MACRO] [-I path] input.sv
```

Supports:
- `` `define `` with parameters
- `` `ifdef `` / `` `ifndef `` / `` `elsif `` / `` `else `` / `` `endif ``
- `` `include ``
- `` `` `` token pasting
- Inline conditionals

The preprocessor is run before svfe in all tool pipelines.


## 11. Excluded Constructs

The following SystemVerilog features are not supported, as they are not part
of the synthesis subset:

| Construct | Category |
|-----------|----------|
| `class` / `endclass` | OOP constructs (UVM) |
| `constraint` | Constrained random |
| `covergroup` / `coverpoint` | Functional coverage |
| `program` / `endprogram` | Testbench programs |
| `fork` / `join` | Parallel threads |
| `force` / `release` | Simulation overrides |
| `#delay` | Time delays |
| DPI (`import "DPI-C"`) | Foreign function interface |
| `bind` | Verification binding |
| `sequence` / `property` | SVA assertions |
| `mailbox`, `semaphore` | Verification synchronization |

Also not yet supported:

| Construct | Notes |
|-----------|-------|
| `union packed` | Packed unions |
| `import "DPI-C"` | DPI function prototypes |


## 12. Files

| File | Description |
|------|-------------|
| `sv/svparse/src/sv.t` | Token definitions |
| `sv/svparse/src/sv.l` | Lexer specification (DFA) |
| `sv/svparse/src/sv.y` | Grammar (LR(1), ~640 lines) |
| `sv/svparse/src/svLexExt.e` | Lexer extension (token values) |
| `sv/svparse/src/svParseExt.e` | Parser extension (S-expr output) |
| `sv/svparse/src/Main.m3` | Command-line driver |
| `sv/svparse/src/m3makefile` | Build configuration |
| `sv/src/svbase.scm` | Base utilities and AST navigation |
| `sv/src/svlint.scm` | Lint checks |
| `sv/src/svgen.scm` | SystemVerilog regeneration from AST |
| `sv/src/svread.scm` | Backward-compatible loader |
| `sv/src/svbv.scm` | Bit-level BDD synthesis engine |
| `sv/src/svemit.scm` | BDD-to-gate-level SV emitter |
| `sv/src/svemit-c.scm` | BDD-to-C emitter |
| `sv/src/svlint-driver.scm` | Standalone lint driver |
| `sv/src/sveqc-driver.scm` | Equivalence checking driver |
| `sv/src/svsynth.scm` | Logic synthesis using BDDs |
| `sv/svsynth/src/Main.m3` | svsynth command-line driver |
| `sv/svsynth/src/BDDPrims.m3` | BDD primitives for mscheme |
| `sv/svlint/run-svlint.sh` | svlint shell wrapper |
| `sv/sveqc/run-sveqc.sh` | sveqc shell wrapper |
| `sv/6502/rtl/ALU.sv` | 6502 combinational ALU |
| `sv/6502/rtl/cpu.sv` | 6502 CPU FSM |
| `sv/6502/emu/` | 6502 C emulator + test harness |
| `sv/doc/svfe-manual.md` | This file |


## 13. See Also

- `PLAN.txt` -- Detailed project plan and scope
- `svbase.scm` -- Scheme API documentation (in-file comments)
- `csp/cspparse/` -- Reference CSP parser (same architecture)
- `parserlib/IMPLEMENTATION_GUIDE.md` -- CM3 parserlib documentation
