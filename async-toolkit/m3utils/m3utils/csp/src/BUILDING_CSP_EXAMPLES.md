# Building CSP Examples

Instructions for compiling and running the CSP (Communicating Sequential
Processes) examples on ARM64\_DARWIN.  These assume you have already built
CM3 and m3utils as described in `../../BUILDING_DARWIN_2026_03_02.md`.

## Overview

The CSP compiler (`cspc`) compiles Fulcrum-CSP hardware process
descriptions into Modula-3 simulation code.  The compilation pipeline
has three stages:

1. **Java frontend** (not included here) — converts `.cast` files into
   Scheme S-expression intermediate form (`.scm` files inside `.il/`
   directories).
2. **Scheme compiler** (`cspc -scm`) — compiles the intermediate form
   through 9 optimisation passes and generates Modula-3 `.i3`/`.m3`
   source.
3. **CM3 build** — compiles the generated Modula-3 into a native
   simulator binary.

Pre-generated intermediate forms are provided in `simplecsp/cast/*.il/`
so you can run stages 2 and 3 without the Java frontend.

## Prerequisites

```sh
export M3UTILS="$HOME/cm3/intel-async/async-toolkit/m3utils/m3utils"
export PATH="$HOME/cm3/install/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"
```

Make sure `cspc` has been built (`make std` or `cm3 -build -override`
in `csp/src`).

### Stack size on macOS

The Scheme compiler uses deep recursion during AST processing and
function inlining.  Complex processes (e.g. Collatz WORKER with struct
pack/unpack) exhaust the default 8 MB macOS stack, causing segfaults.

On Linux this is not a problem — `ulimit -s unlimited` works there.
On macOS the kernel hard-limits `ulimit -s` to ~64 MB, which is still
not enough.  The Apple linker's `-stack_size` flag caps out at 512 MB
on arm64.

The CM3 ARM64\_DARWIN config sets 512 MB via the linker flag
(`-Wl,-stack_size,0x20000000`).  This is sufficient for the Scheme
interpreter.

> **Note:** An earlier version used `bin/macho-set-stacksize` to
> post-link patch the binary to 8 GB, but this caused intermittent
> SIGTRAP crashes on ARM64 macOS (the kernel cannot always map an
> 8 GB stack region).  The post-link step has been removed.

## Quick start: HELLOWORLD

The simplest example.  One process, no channels, just prints a message.

```sh
cd $M3UTILS/csp/simplecsp/cast/simple.HELLOWORLD.il
mkdir -p build/src

# Stage 2: Scheme compiler → Modula-3
cspc -scm /dev/stdin <<'EOF'
(load "$M3UTILS/csp/src/setup.scm")
(drive! "simple_46_HELLOWORLD.procs")
EOF

# Stage 3: CM3 → native binary
cd build/src
cm3 -build -override

# Run the simulator
../$(../../m3arch.sh)/sim
```

Expected output:

```
1: x: hello, world!
```

## Step-by-step compilation

You can also run the compiler stages individually, which is useful for
debugging or inspecting intermediate results.

### Loading and compiling a single process

```sh
cd $M3UTILS/csp/simplecsp/cast/simple.HELLOWORLD.il
mkdir -p build/src

cspc -scm /dev/stdin <<'EOF'
(load "$M3UTILS/csp/src/setup.scm")

;; Load the intermediate form
(loaddata! "simple_46_HELLOWORLD.scm")

;; Run the 9-pass compiler front-end
(compile!)

;; Generate Modula-3 code into build/src/
(do-m3!)
EOF
```

The generated files appear in `build/src/`:

| File | Description |
|------|-------------|
| `m3__*.i3` | Modula-3 interface (ports, Build/Start procedures) |
| `m3__*.m3` | Modula-3 implementation (state machine blocks) |
| `CspDebug.i3` | Debug configuration interface |

### Using `drive!` (recommended for full systems)

`drive!` is the high-level entry point.  It reads a `.procs` file that
describes the process graph (instances, types, and channel bindings),
compiles all referenced process types, and generates a complete
buildable project including `SimMain.m3` and `m3makefile`.

```scheme
(drive! "process_graph.procs")
```

The `.procs` file format is one line per process instance:

```
instance_name  cell_type  escaped_type_name  port=channel port=channel ...
```

## Building from `.sys` files (recommended)

`build-system!` is a higher-level entry point that handles the entire
pipeline from a single `.sys` file: parsing the system description,
running `cspfe` on each process, patching cellinfo, generating `.procs`,
and invoking `drive!` and `cm3`.

```sh
cd /tmp/my-example
cspc -scm /dev/stdin <<'EOF'
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))
(load (string-append (Env.Get "M3UTILS") "/csp/src/cspbuild.scm"))
(build-system! "example.sys")
(exit)
EOF
build/$(../../m3arch.sh)/sim
```

### `.sys` file format

```
system Name;
  var ch : channel(WIDTH);                (* channel declaration      *)
  var ch : channel(WIDTH) slack N;        (* channel with slack       *)
  process P = "file.csp"                  (* external CSP source      *)
    port out R : channel(WIDTH);          (* output port              *)
  process Q = %[% print("hello") %]%     (* inline CSP body          *)
    port in L : channel(WIDTH);           (* input port               *)
begin
  var p : P(R => ch);                     (* instance with binding    *)
  var q : Q(L => ch);
end.
```

Inline CSP bodies are delimited by `%[%` and `%]%`.  The text between
the delimiters is passed to `cspfe` verbatim.  The sequence `%[%` cannot
appear in legal CSP, so there is no ambiguity.  (If `%]%` appears inside
a CSP string literal, the scanner handles it correctly.)

Comments use `(* ... *)` (nestable) or `// ...` (to end of line).

### Hello World

```
system Hello;
  process Hello = %[% print("hello, world!") %]%;
begin
  var h : Hello;
end.
```

### Producer-Consumer

```
system ProdCons;
  var ch : channel(32);
  process Producer = "producer.csp"
    port out R : channel(32);
  process Consumer = "consumer.csp"
    port in L : channel(32);
begin
  var p : Producer(R => ch);
  var c : Consumer(L => ch);
end.
```

### Collatz sequence (single process)

```
system Collatz;
  process Seq = %[%
    int n;
    n = 27;
    print("" + n);
    *[ n != 1 -> [ n % 2 == 0 -> n = n / 2
                 [] n % 2 != 0 -> n = n * 3 + 1 ];
       print("" + n) ]
  %]%;
begin
  var c : Seq;
end.
```

## Collatz example (pre-generated)

A larger example: 20 worker processes computing Collatz sequences in
parallel, coordinated by a manager and a tree of splitters (59 process
instances total).

```sh
cd $M3UTILS/csp/simplecsp/cast/collatz.COLLATZ_20_44.il
mkdir -p build/src

cspc -scm /dev/stdin <<'EOF'
(load "$M3UTILS/csp/src/setup.scm")
(drive! "collatz_46_COLLATZ_40_20_44_44_41_.procs")
EOF

cd build/src
cm3 -build -override
../$(../../m3arch.sh)/sim
```

The simulation runs 20 workers computing Collatz sequences for odd
numbers up to 2^44, reporting longest chains as they are found.
It runs until all phases complete (takes a while).

## Simulator options

The generated `sim` binary accepts several command-line options:

| Flag | Description |
|------|-------------|
| `-scm` | Enter the Scheme REPL after building the simulation |
| `-mt N` | Use N threads for simulation |
| `-greedy` | Use greedy scheduling |
| `-nondet` | Use nondeterministic scheduling |
| `-master N cmd` | Distributed simulation: master with N workers |
| `-worker id` | Distributed simulation: worker process |

### Interactive Scheme session

```sh
../$(../../m3arch.sh)/sim -scm
```

This builds the simulation and drops into a Scheme REPL where you can
inspect and control the simulation programmatically.  The simulation
environment provides `(go)` to retrieve the process table.

## Tested examples

| Example | Status |
|---------|--------|
| `simple.HELLOWORLD` | Compiles, builds, and runs end-to-end |
| `collatz.COLLATZ(20,44)` | Compiles, builds, and runs |
| `first.SYSTEM` | Not yet tested (4096 processes, large) |

## Notes

- The `build/src/m3overrides` generated by `drive!` points back to the
  m3utils `m3overrides`, so all library dependencies are resolved
  automatically.
- The `first.SYSTEM` example instantiates 4096 processes in a ring
  pipeline and would generate a very large `SimMain.m3`.
- The `.cast` source files in `simplecsp/cast/` are provided for
  reference but require the Java frontend (`csp2java`) to regenerate
  the `.il/` intermediate forms.
