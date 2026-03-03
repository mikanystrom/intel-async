# cspfe User Manual

`cspfe` is a CSP (Communicating Sequential Processes) frontend that parses
`.csp` source files.  It can check syntax or emit S-expression output
consumable by `cspc`'s `loaddata!` function.

## Usage

```
cspfe [options] <file.csp>
```

### Options

| Flag | Description |
|---|---|
| (none) | Parse the file and report whether the syntax is valid. |
| `--scm` | Parse and emit S-expression output to stdout. |
| `--name CELLNAME` | Set the cell name in the S-expression output. Default: filename without extension. |
| `--lex` | Dump the token stream (debugging). |

### Examples

Syntax check:

```
$ cspfe hello.csp
hello.csp: syntax ok
```

Emit S-expression:

```
$ cspfe --scm hello.csp
("hello"
  (csp
    () () () () () (eval (apply (id print) "hello, world!")))
  (cellinfo "hello" "hello" () ()))
```

Override the cell name:

```
$ cspfe --scm --name simple.HELLOWORLD hello.csp
("simple.HELLOWORLD"
  (csp
    () () () () () (eval (apply (id print) "hello, world!")))
  (cellinfo "simple.HELLOWORLD" "simple.HELLOWORLD" () ()))
```

Pipe into cspc:

```
$ cspfe --scm --name mycell prog.csp > /tmp/mycell.scm
$ cspc
> (loaddata! "/tmp/mycell.scm")
```

## CSP Language Reference

### Comments

```
/* block comment */
// line comment
```

### Types

| Type | Syntax | Examples |
|---|---|---|
| Integer | `int`, `int(N)` | `int`, `int(8)`, `int(32)` |
| Signed integer | `sint(N)` | `sint(8)`, `sint(32)` |
| Boolean | `bool`, `boolean` | `bool`, `boolean` |
| String | `string` | `string` |

Prefix `const` for constant declarations: `const int x = 42`.

### Declarations

```
int x                      // uninitialized
int x = 5                  // with initializer
int x, y, z                // multiple declarators
int(8) -a, +b              // with bit width and directions
const bool flag = true     // constant
sint(32) counter = 0       // signed integer
int d[3]                   // array dimension
int m[3][6]                // multi-dimensional
```

Direction prefixes on declarators:

| Prefix | Meaning |
|---|---|
| (none) | no direction |
| `-` | input |
| `+` | output |
| `+-` or `-+` | input/output |

### Statements

#### Assignment

```
x = expr
x += expr    x -= expr    x *= expr    x /= expr    x %= expr
x &= expr   x |= expr    x ^= expr
x <<= expr  x >>= expr
x++          x--
```

#### Boolean set/clear

```
flag+        // set to true
flag-        // set to false
```

#### Channel operations

```
ch ! expr          // send expr on ch
ch ! expr, expr    // send multiple
ch !               // send (no value)
ch ? var           // receive into var
ch ?               // receive (discard)
```

#### Skip and error

```
skip
error
```

#### Function call (expression statement)

```
print("hello")
f(x, y, z)
```

#### Parenthesized (sequence)

```
(s1; s2; s3)
```

### Composition

Semicolon `;` is sequential composition.  Comma `,` is parallel composition.
Parallel binds tighter than sequential:

```
a; b, c; d        // a; (b, c); d — b and c run in parallel
a; (b; c), d      // a; ((b; c), d) — use parens to override
```

Trailing semicolons are permitted: `a; b;`

### Expressions

#### Literals

```
42              // decimal integer
0xFF            // hexadecimal
0b1010          // binary
10_42           // radix notation (radix 10, value 42)
true  false     // boolean
"hello"         // string (with \" escapes)
```

#### Operators (by precedence, low to high)

+------------+---------------------------------+---------------+
| Precedence | Operators                       | Associativity |
+============+=================================+===============+
| 1          | `||`                            | left          |
+------------+---------------------------------+---------------+
| 2          | `&&`                            | left          |
+------------+---------------------------------+---------------+
| 3          | `|`                             | left          |
+------------+---------------------------------+---------------+
| 4          | `^`                             | left          |
+------------+---------------------------------+---------------+
| 5          | `&`                             | left          |
+------------+---------------------------------+---------------+
| 6          | `==`  `!=`                      | left          |
+------------+---------------------------------+---------------+
| 7          | `<`  `>`  `<=`  `>=`            | left          |
+------------+---------------------------------+---------------+
| 8          | `<<`  `>>`                      | left          |
+------------+---------------------------------+---------------+
| 9          | `+`  `-`                        | left          |
+------------+---------------------------------+---------------+
| 10         | `*`  `/`  `%`                   | left          |
+------------+---------------------------------+---------------+
| 11         | `-` (unary)  `~` (bitwise not)  | right         |
+------------+---------------------------------+---------------+
| 12         | `**` (exponent)                 | right         |
+------------+---------------------------------+---------------+

#### Lvalue suffixes

```
a[i]            // array access
a[i,j]          // multi-dimensional (nested)
a.field         // member access
a.0             // member by integer index
a::field        // structure access
a{i}            // single-bit extract
a{lo:hi}        // bit range
f(x, y)         // function call / apply
```

#### Receive and probe expressions

```
ch?             // receive expression (value of received data)
#ch             // probe (true if channel has pending data)
#ch?            // peek (read value without consuming)
```

#### Loop expressions

```
<+ i : 0..N : expr>     // sum
<* i : 0..N : expr>     // product
<& i : 0..N : expr>     // bitwise AND
<| i : 0..N : expr>     // bitwise OR
<^ i : 0..N : expr>     // bitwise XOR
```

### Selection (guards)

Deterministic:

```
[ guard1 -> body1
[] guard2 -> body2
[] else -> body3
]
```

Non-deterministic:

```
[ guard1 -> body1
: guard2 -> body2
]
```

Wait (blocks until expression is true):

```
[expr]
```

Hash-prefixed guards (for peek selection):

```
#[guard1 -> body1 [] guard2 -> body2]
```

### Repetition

Guarded loop:

```
*[ guard1 -> body1
[] guard2 -> body2
]
```

Infinite loop:

```
*[ body ]
```

### Loop statements

Sequential loop (angle bracket with `;`):

```
<i : 0..9 : body>
<; i : 0..9 : body>
```

Parallel loop (angle bracket with `,`):

```
<, i : 0..9 : body>
<|| i : 0..9 : body>
```

Range forms:

```
lo..hi          // from lo to hi inclusive
N               // shorthand for 0..N-1
```

### Functions

```
function name(type1 a, b; type2 -c) : returntype = body;
function name(type a) = body;    // no return type
function name() = body;          // no parameters
```

Parameters are grouped by semicolons.  Each group shares a type.
Within a group, commas separate declarators.

### Structures

```
structure Point = (int x; int y);
structure Packet = (int(8) data[4]; bool valid);
```

### Linkage (for timed/annotated guards)

```
[ guard @(link_expr) -> body
: guard @(link_expr) -> body
: @(link_expr)
]
```

Linkage expressions can include member access, array access, and tilde
negation (`~`).  Linkage loops use `<,` syntax:

```
@(<, i : 0..N : expr>)
```

## S-Expression Output Format

### Top-level envelope

```scheme
("cell-name"
  (csp
    (func1 func2 ...)                ; functions
    (struct1 struct2 ...)            ; structures
    ()                                ; refparents (unused)
    ()                                ; declparents (unused)
    ()                                ; inits (unused)
    body)                             ; main body
  (cellinfo "cell-name" "cell-name" () ()))
```

### Statements

| CSP              | S-expression                        |
|------------------|-------------------------------------|
| `x = expr`       | `(assign (id x) expr)`              |
| `x += expr`      | `(assign-operate + (id x) expr)`    |
| `x++`            | `(assign-operate + (id x) 10_1)`    |
| `x--`            | `(assign-operate - (id x) 10_1)`    |
| `x+`             | `(assign (id x) #t)`                |
| `x-`             | `(assign (id x) #f)`                |
| `ch ! expr`      | `(send (id ch) expr)`               |
| `ch ? x`         | `(recv (id ch) (id x))`             |
| `ch !`           | `(send (id ch) ())`                 |
| `ch ?`           | `(recv (id ch) ())`                 |
| `skip`           | `skip`                              |
| `error`          | `(error)`                           |
| `f(args)` (stmt) | `(eval (apply (id f) args))`        |
| `(body)`         | `(sequence body)`                   |
| `s1 ; s2`        | items in enclosing `(sequence ...)` |
| `s1 , s2`        | `(parallel s1 s2)`                  |

### Guards and loops

| CSP                   | S-expression                                        |
|-----------------------|-----------------------------------------------------|
| `[g -> c [] ...]`     | `(if (g (sequence c)) ...)`                         |
| `[g -> c : ...]`      | `(nondet-if (g (sequence c)) ...)`                  |
| `*[g -> c [] ...]`    | `(do (g (sequence c)) ...)`                         |
| `*[g -> c : ...]`     | `(nondet-do (g (sequence c)) ...)`                  |
| `*[body]`             | `(do (#t (sequence body)))`                         |
| `[] else -> c`        | `(else (sequence c))`                               |
| `[expr]`              | `(if (expr (sequence skip)))`                       |
| `<; i:lo..hi: body>`  | `(sequential-loop i (range lo hi) (sequence body))` |
| `<, i:lo..hi: body>`  | `(parallel-loop i (range lo hi) (sequence body))`   |

### Expressions

| CSP              | S-expression                                         |
|------------------|------------------------------------------------------|
| `42`             | `10_42`                                              |
| `0xFF`           | `16_FF`                                              |
| `0b1010`         | `10_10`                                              |
| `true` / `false` | `#t` / `#f`                                         |
| `"hello"`        | `"hello"`                                            |
| `x`              | `(id x)`                                             |
| `a + b`          | `(+ (id a) (id b))`                                  |
| `a ** b`         | `(** (id a) (id b))`                                 |
| `-x`             | `(- (id x))`                                         |
| `~x`             | `(not (id x))`                                       |
| `a[i]`           | `(array-access (id a) (id i))`                       |
| `a[i,j]`         | `(array-access (array-access (id a) (id i)) (id j))` |
| `a.field`        | `(member-access (id a) field)`                       |
| `a.0`            | `(member-access (id a) 10_0)`                        |
| `a::field`       | `(structure-access (id a) field)`                    |
| `a{i}`           | `(bits (id a) () (id i))`                            |
| `a{lo:hi}`       | `(bits (id a) (id lo) (id hi))`                      |
| `f(x,y)`         | `(apply (id f) (id x) (id y))`                       |
| `ch?`            | `(recv-expression (id ch))`                          |
| `#ch`            | `(probe (id ch))`                                    |
| `#ch?`           | `(peek (id ch))`                                     |
| `<+ i:r: e>`     | `(loop-expression i range + e)`                      |

### Declarations

| CSP                | S-expression                                             |
|--------------------|----------------------------------------------------------|
| `int x`            | `(var1 (decl1 (id x) (integer #f #f () ()) none))`      |
| `int x = 5`        | `(var1 ...) (assign (id x) 10_5)`                       |
| `const int(8) -x`  | `(var1 (decl1 (id x) (integer #t #f 10_8 ()) in))`     |
| `bool flag`        | `(var1 (decl1 (id flag) (boolean #f) none))`             |
| `sint(32) n`       | `(var1 (decl1 (id n) (integer #f #t 10_32 ()) none))`   |

### Types

| CSP                 | S-expression               |
|---------------------|----------------------------|
| `int`               | `(integer #f #f () ())`    |
| `int(32)`           | `(integer #f #f 10_32 ())` |
| `sint(32)`          | `(integer #f #t 10_32 ())` |
| `const int`         | `(integer #t #f () ())`    |
| `bool` / `boolean`  | `(boolean #f)`             |
| `string`            | `(string #f)`              |

### Functions

```scheme
(function name (param-groups) return-type (sequence body))
```

Parameter groups are separated by `;` in the source.  Each group is wrapped in
parentheses.  The whole parameter list is wrapped in an outer pair:

```
function f(int a, b; bool c) : int = body;
```
produces:
```scheme
(function f
  (((var1 (decl1 (id a) (integer #f #f () ()) none))
    (var1 (decl1 (id b) (integer #f #f () ()) none)))
   ((var1 (decl1 (id c) (boolean #f) none))))
  (integer #f #f () ())
  (sequence body))
```

Functions with no return type use `()` in the return-type position.

### Structures

```scheme
(structure-decl Name (field-groups))
```

Field groups follow the same grouping rules as function parameters.

## Building

Requires a working CM3 installation with `parserlib` and `cit_util`.

```
cd csp/cspparse/src
cm3 -build -override
```

The built binary is at `../ARM64_DARWIN/cspfe` (or the appropriate target
directory).

## Testing

```
cd csp/cspparse/src
bash run_tests.sh
```

The test suite covers 116 syntax-checking cases across all language constructs.
