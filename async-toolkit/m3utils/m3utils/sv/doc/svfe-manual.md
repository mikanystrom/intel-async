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

**LALR(1) mode** (optional, ~31× faster build):

```
$ setenv yaccLALR 1    # or: export yaccLALR=1
$ cm3 -override
```

By default, kyacc builds a canonical LR(1) parser (~68,000 states,
~5 min).  Setting `yaccLALR` activates DeRemer-Pennello LALR(1)
construction, producing 1,162 states in ~11 seconds.  Both modes
generate parsers that produce identical results on all test suites.

**Prerequisites:**

- CM3 compiler with parserlib installed
- A `.top` file in the m3utils root (see cm3 documentation)
- The `m3overrides` file (included)


## 3. Usage

### 3.1 Command-line options

```
svfe [--scm] [--lex] [--no-lines] [--name <module>] <file.sv>
```

| Option | Description |
|--------|-------------|
| `--scm` | Emit S-expression output (default mode) |
| `--lex` | Emit lexer token stream (for debugging) |
| `--no-lines` | Suppress `(@ N ...)` line number wrappers in output |
| `--name` | Set the module name for error messages |

With no flags, svfe checks syntax only and prints `filename: syntax ok`.

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

### 4.9 SystemVerilog Assertions (SVA)

svfe implements comprehensive SVA support covering the large majority of
IEEE 1800-2017 §16 and Annex A §A.2.10.

#### Assertion statements

| Construct | Context |
|-----------|---------|
| `assert property (...)` | Module item and statement |
| `assume property (...)` | Module item and statement |
| `cover property (...)` | Module item and statement |
| `cover sequence (...)` | Module item and statement |
| `restrict property (...)` | Module item and statement |
| `expect (...)` | Statement only |
| `label: assert property (...)` | Labeled (module item and statement) |
| `label: assume property (...)` | Labeled |
| `label: cover property (...)` | Labeled |

#### Property spec

```
[clocking_event] [disable iff (expr)] property_expr
```

The `property_spec` wrapper inside `assert property(...)` etc. supports
an optional clocking event and an optional `disable iff` clause.

#### Property operators (by precedence, lowest first)

| Operator | Syntax | Associativity |
|----------|--------|---------------|
| `iff` | `p iff q` | Right |
| `implies` | `p implies q` | Right |
| `until`, `s_until`, `until_with`, `s_until_with` | `p until q` | Right |
| `or` | `p or q` | Left |
| `and`, `intersect` | `p and q`, `p intersect q` | Left |
| `not` | `not p` | Prefix |
| `\|->`, `\|=>`, `#-#`, `#=#` | `seq \|-> prop` | Infix |

#### Temporal operators (prefix, inside `prop_temporal_expr`)

| Operator | Syntax |
|----------|--------|
| `nexttime` | `nexttime p`, `nexttime [N] p` |
| `s_nexttime` | `s_nexttime p`, `s_nexttime [N] p` |
| `always` | `always p`, `always [lo:hi] p` |
| `s_always` | `s_always [lo:hi] p` |
| `eventually` | `eventually [lo:hi] p` |
| `s_eventually` | `s_eventually p`, `s_eventually [lo:hi] p` |
| `accept_on` | `accept_on (expr) p` |
| `reject_on` | `reject_on (expr) p` |
| `sync_accept_on` | `sync_accept_on (expr) p` |
| `sync_reject_on` | `sync_reject_on (expr) p` |
| `if`/`else` | `if (expr) p else q` |
| `case` | `case (expr) val: p; ... endcase` |

#### Sequence operators

| Operator | Syntax |
|----------|--------|
| `within` | `s1 within s2` |
| `throughout` | `expr throughout seq` |
| `##` (delay) | `s1 ##N s2`, `s1 ##[lo:hi] s2`, `##[*] s`, `##[+] s` |
| `strong`/`weak` | `strong(seq)`, `weak(seq)` |
| `first_match` | `first_match(seq)` |

#### Boolean abbreviations (repetition)

| Syntax | Meaning |
|--------|---------|
| `expr [*N]` | Consecutive repetition (exact) |
| `expr [*lo:hi]` | Consecutive repetition (range) |
| `expr [*]` | Zero or more consecutive |
| `expr [+]` | One or more consecutive |
| `expr [->N]` | Goto repetition (exact) |
| `expr [->lo:hi]` | Goto repetition (range) |
| `expr [=N]` | Non-consecutive repetition (exact) |
| `expr [=lo:hi]` | Non-consecutive repetition (range) |

#### Named declarations

| Construct | Description |
|-----------|-------------|
| `property name [...]; ... endproperty` | Named property declaration |
| `sequence name [...]; ... endsequence` | Named sequence declaration |

Both support optional port lists and optional end labels
(`endproperty : name`).

#### Not supported (LALR parser limitations)

- **Inline clocking events** in sequence expressions
  (`@(posedge clk) a ##1 @(posedge clk2) b`).
  The `@(event)` syntax is shared with `always @(...)` and
  event-control statements; LALR state merging makes them
  indistinguishable.

- **Sequence match-item assignments** (`(expr, x = val)`) as in
  IEEE §16.10.  The `(expr,` prefix is ambiguous with parenthesized
  expressions and function argument lists.

- **`checker` construct** (`checker ... endchecker`).  Not implemented;
  mechanically similar to `module` but low priority.

See `svparse/svfe_sva_ieee_comparison.md` for a detailed comparison
against the IEEE 1800-2017 formal grammar.


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

### 5.8 SVA (assertions and properties)

#### Assertion statements

```scheme
(assert-property <property-expr> <action-block>)
(assume-property <property-expr> <action-block>)
(cover-property <property-expr>)
(cover-sequence <property-expr>)
(restrict-property <property-expr>)
(expect-property <property-expr> <action-block>)
(labeled <name> (assert-property ...))     ;; labeled assertion
```

#### Property operators

```scheme
(|-> <seq> <prop>)                         ;; overlapping implication
(|=> <seq> <prop>)                         ;; non-overlapping implication
(#-# <seq> <prop>)                         ;; followed-by (overlapping)
(#=# <seq> <prop>)                         ;; followed-by (non-overlapping)
(sva-and <p> <q>)                          ;; property/sequence AND
(sva-or <p> <q>)                           ;; property/sequence OR
(intersect <p> <q>)                        ;; sequence intersect
(not <p>)                                  ;; property negation
(iff <p> <q>)                              ;; property if-and-only-if
(implies <p> <q>)                          ;; property implies (keyword)
(until <p> <q>)                            ;; until
(s_until <p> <q>)                          ;; strong until
(until_with <p> <q>)                       ;; until_with
(s_until_with <p> <q>)                     ;; strong until_with
```

#### Temporal operators

```scheme
(nexttime <p>)                             ;; next cycle
(nexttime [<n>] <p>)                       ;; N cycles ahead
(s_nexttime <p>)                           ;; strong nexttime
(sva-always <p>)                           ;; always (unbounded)
(sva-always [<lo>:<hi>] <p>)              ;; always (bounded range)
(s_always [<lo>:<hi>] <p>)                ;; strong always
(eventually [<lo>:<hi>] <p>)              ;; eventually (bounded)
(s_eventually <p>)                         ;; strong eventually (unbounded)
(s_eventually [<lo>:<hi>] <p>)            ;; strong eventually (bounded)
(accept_on <expr> <p>)                     ;; abort (accept)
(reject_on <expr> <p>)                     ;; abort (reject)
(sync_accept_on <expr> <p>)               ;; synchronous abort (accept)
(sync_reject_on <expr> <p>)               ;; synchronous abort (reject)
```

#### Sequence operators

```scheme
(## <N> <lhs> <rhs>)                       ;; cycle delay
(##[<lo>:<hi>] <lhs> <rhs>)              ;; range delay
(##[*] <lhs> <rhs>)                       ;; zero-or-more delay
(##[+] <lhs> <rhs>)                       ;; one-or-more delay
(## <N> <rhs>)                             ;; initial delay (no LHS)
(within <s1> <s2>)                         ;; sequence within
(throughout <expr> <seq>)                  ;; expression throughout
(strong <seq>)                             ;; strong sequence
(weak <seq>)                               ;; weak sequence
(first_match <seq>)                        ;; first match
```

#### Boolean abbreviations (repetition)

```scheme
(rep* <expr>)                              ;; [*] zero or more
(rep* <expr> <N>)                          ;; [*N] exact
(rep* <expr> <lo>:<hi>)                   ;; [*lo:hi] range
(rep+ <expr>)                              ;; [+] one or more
(rep-> <expr> <N>)                         ;; [->N] goto
(rep-> <expr> <lo>:<hi>)                  ;; [->lo:hi] goto range
(rep= <expr> <N>)                          ;; [=N] non-consecutive
(rep= <expr> <lo>:<hi>)                   ;; [=lo:hi] non-consecutive range
```

#### Declarations

```scheme
(property-decl <name> <ports> <body>)      ;; property ... endproperty
(sequence-decl <name> <ports> <body>)      ;; sequence ... endsequence
```

#### Property spec wrapper

```scheme
;; bare property (no clocking)
<prop-expr>

;; with clocking event
(sens ...) <prop-expr>

;; with clocking and disable iff
(sens ...) (disable-iff <expr>) <prop-expr>
```

### 5.9 Example

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
| `svsop.scm` | BDD-to-SOP equation emitter (minimized sum-of-products) |
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
| `(bdd->sop b)` | Minimized SOP equation string |
| `(bdd->sop-raw b)` | Unminimized SOP equation string |
| `(bdd->sop-terms b)` | Product term count after minimization |

The SOP primitives use the Caltech SOP library (`caltech-other/sop`),
which converts BDDs to sum-of-products form via Shannon expansion
(`SopBDD.ConvertBool`) and then applies greedy literal/term removal
(`invariantSimplify`) to minimize the result.

### 8.3 SOP equation output (svsop)

```
$ sv/svsop/run-svsop.sh [--cut N] [pp-flags...] input.sv
```

Parses a combinational SV module, builds BDDs for each output bit,
then converts each BDD to a minimized sum-of-products equation.

The `--cut N` flag enables BDD decomposition: when a BDD exceeds N
nodes, it is replaced by a fresh intermediate variable.  The cut
variables' equations are emitted first, then the output equations.
This keeps all SOPs bounded in size.  Recommended: `--cut 30` for
arithmetic-heavy designs (adders, ALUs).

Three-tier output based on BDD size:
- ≤200 nodes: minimized SOP (Espresso-style simplification)
- 201–500 nodes: raw SOP (ConvertBool only, no minimization)
- >500 nodes: skipped with a comment

Example output for a 4-bit comparator:

```
gt = a[3] & ~b[3] | a[2] & ~b[2] & ~b[3] | ...;
  // 15 product terms, 40 BDD nodes
lt = ~a[3] & b[3] | ~a[2] & ~a[3] & b[2] | ...;
  // 15 product terms, 39 BDD nodes
```

Example on the 6502 ALU (`--cut 30`):

```
--- Cut variables (67 intermediate wires) ---
_cut_carry_3_0 = a_in[3] & operand[3] | a_in[2] & operand[2] & operand[3] | ...;
  // 15 products, 39 BDD nodes
...
--- Output equations ---
sign_out = _cut_mux_result_7_66 | ...;
  // 4 products, 12 BDD nodes
=== 67 cuts, 6 outputs ===
```

### 8.4 Test suites

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

### 9.2 Running all 6502 tests

```
$ sv/6502/run-6502-tests.sh
```

This runs three tests in sequence:

1. **BDD-to-C generation**: Parses ALU.sv, builds BDDs, emits C eval functions
2. **Exhaustive ALU verification**: Compares BDD-generated C against a reference
   C implementation for all 15 ops × 256 × 256 × 2 = 1,966,080 test vectors
3. **Dormann functional test**: Runs the reference emulator (fake6502) through
   Klaus Dormann's 6502 functional test suite (~30M instructions, 96M cycles)

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
The generated header contains ~12,900 temp variables across 5 output
functions (result, carry_out, zero_out, sign_out, overflow_out).

### 9.5 Exhaustive ALU test

```
$ gcc -O2 -o test_alu sv/6502/emu/test_alu.c -I sv/6502/emu
$ ./test_alu
```

Verifies every BDD-generated eval function against a hand-written
reference C implementation of the 6502 ALU.  Tests all 15 ALU operations
across all 8-bit input combinations with both carry states.


## 10. Preprocessor (svpp)

svpp is a standalone SystemVerilog preprocessor written in Modula-3.
It handles all IEEE 1800 preprocessor directives needed for synthesis
and emits preprocessed source to stdout with line numbers preserved.

### 10.1 Usage

```
svpp [-I dir]... [-D NAME[=VALUE]]... file.sv
```

| Option | Description |
|--------|-------------|
| `-I dir` | Add `dir` to include file search path (searched in order) |
| `-D NAME` | Define macro `NAME` with value `1` |
| `-D NAME=VALUE` | Define macro `NAME` with value `VALUE` |

Both `-I` and `-D` accept the flag and argument either separated by a
space (`-I dir`) or joined (`-Idir`).

Output goes to stdout.  Errors go to stderr.

### 10.2 Supported directives

| Directive | Description |
|-----------|-------------|
| `` `define NAME body`` | Define a simple macro |
| `` `define NAME(a,b) body`` | Define a parameterized macro |
| `` `define NAME(a,b=default) body`` | Parameters with default values |
| `` `undef NAME`` | Undefine a macro |
| `` `ifdef NAME`` | Conditional: true if `NAME` is defined |
| `` `ifndef NAME`` | Conditional: true if `NAME` is not defined |
| `` `elsif NAME`` | Else-if branch |
| `` `else`` | Else branch |
| `` `endif`` | End conditional |
| `` `include "file"`` | Include a file |

### 10.3 Macro expansion

Macros are expanded iteratively to a fixed point (up to 50 iterations).
Backtick-prefixed identifiers (`` `NAME``) are looked up in the macro
table and replaced with their expansion bodies.

**Parameterized macros** support positional arguments with optional
defaults:

```systemverilog
`define BUS(width, name) logic [width-1:0] name
`define REG(name, width=8) logic [width-1:0] name

`BUS(32, data_bus)        // -> logic [32-1:0] data_bus
`REG(counter)             // -> logic [8-1:0] counter (default width)
`REG(addr, 16)            // -> logic [16-1:0] addr
```

**Token pasting** (` `` `) concatenates adjacent tokens in macro bodies:

```systemverilog
`define MAKE_SIGNAL(prefix, suffix) logic prefix``_``suffix
`MAKE_SIGNAL(data, valid)   // -> logic data_valid
```

**Multi-line macros** use backslash continuation:

```systemverilog
`define ASSERT_PROP(name, prop) \
  name: assert property (prop) \
    else $error("Assertion name failed");
```

**Multi-line macro invocations** are supported: if a parameterized macro
call has unclosed parentheses at end of line, svpp joins subsequent lines
until the closing `)` is found.

### 10.4 Inline conditional expansion

After macro expansion, svpp processes any inline conditional directives
that appear within the expanded text.  This handles the common pattern
of macros that expand to conditionally-compiled code:

```systemverilog
`define OPTIONAL_DEBUG `ifdef DEBUG $display("debug"); `endif
```

### 10.5 Include file search

For `` `include "file"`` directives, svpp searches:

1. The directory containing the current source file
2. Each `-I` directory, in command-line order

Circular includes are detected and silently skipped (each file is
processed at most once).

### 10.6 Line number preservation

svpp preserves source line numbers so that downstream parser error
messages refer to the original source:

- Directive lines are replaced with blank lines in the output
- Multi-line macro definitions emit one blank per source line consumed
- If macro expansion produces more output lines than source lines,
  svpp emits a `` `line`` directive to resynchronize

### 10.7 Ignored directives

The following directives are recognized and silently consumed (emitting
a blank line):

`` `timescale``, `` `resetall``, `` `default_nettype``,
`` `celldefine``, `` `endcelldefine``

### 10.8 Pipeline usage

svpp is typically the first stage in the svfe pipeline:

```sh
svpp -I rtl/include -D SYNTHESIS design.sv | svfe --scm /dev/stdin
```

Or using a shell wrapper that chains both steps:

```sh
svpp -I rtl/include -D SYNTHESIS design.sv > /tmp/pp.sv
svfe --scm /tmp/pp.sv
```


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
| `checker` / `endchecker` | SVA checker construct |
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
| `sv/svparse/src/sv.y` | Grammar (LR(1)/LALR(1), ~640 lines) |
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
| `sv/src/svsop.scm` | SOP equation output driver |
| `sv/src/svsynth.scm` | Logic synthesis using BDDs |
| `sv/svsynth/src/Main.m3` | svsynth command-line driver |
| `sv/svsynth/src/BDDPrims.m3` | BDD primitives for mscheme |
| `sv/svlint/run-svlint.sh` | svlint shell wrapper |
| `sv/sveqc/run-sveqc.sh` | sveqc shell wrapper |
| `sv/svsop/run-svsop.sh` | svsop shell wrapper |
| `sv/6502/rtl/ALU.sv` | 6502 combinational ALU |
| `sv/6502/rtl/cpu.sv` | 6502 CPU FSM |
| `sv/6502/emu/` | 6502 C emulator + test harness |
| `sv/svparse/svfe_sva_ieee_comparison.md` | SVA grammar vs IEEE 1800-2017 |
| `sv/doc/svfe-manual.md` | This file |


## 13. See Also

- `PLAN.txt` -- Detailed project plan and scope
- `svbase.scm` -- Scheme API documentation (in-file comments)
- `csp/cspparse/` -- Reference CSP parser (same architecture)
- `parserlib/IMPLEMENTATION_GUIDE.md` -- CM3 parserlib documentation
