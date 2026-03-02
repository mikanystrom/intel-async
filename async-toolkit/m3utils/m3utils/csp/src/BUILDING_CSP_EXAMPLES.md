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

### Stack size fix for complex examples

The Scheme compiler uses deep recursion during AST processing and
function inlining.  Complex processes (e.g. Collatz WORKER with struct
pack/unpack) exhaust the default 8 MB macOS stack, causing segfaults.

The fix is to patch the `cspc` binary's Mach-O header to request a
4 GB main-thread stack:

```python
python3 -c "
import struct
with open('csp/ARM64_DARWIN/cspc', 'rb') as f:
    data = bytearray(f.read())
offset = 32  # skip Mach-O 64-bit header
ncmds = struct.unpack_from('<I', data, 16)[0]
for i in range(ncmds):
    cmd, cmdsize = struct.unpack_from('<II', data, offset)
    if cmd == 0x80000028:  # LC_MAIN
        struct.pack_into('<Q', data, offset + 16, 0x100000000)  # 4 GB
        break
    offset += cmdsize
with open('csp/ARM64_DARWIN/cspc', 'wb') as f:
    f.write(data)
"
codesign --force --sign - csp/ARM64_DARWIN/cspc
```

On Linux this is not needed — `ulimit -s unlimited` works there.
On macOS the kernel hard-limits `ulimit -s` to ~64 MB, which is still
not enough, so the Mach-O `LC_MAIN.stacksize` field must be used.

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
../ARM64_DARWIN/sim
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

## Collatz example

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
../ARM64_DARWIN/sim
```

**Note:** This requires the stack size fix described above.  Without
it, `cspc` segfaults during compilation of the WORKER process.

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
../ARM64_DARWIN/sim -scm
```

This builds the simulation and drops into a Scheme REPL where you can
inspect and control the simulation programmatically.  The simulation
environment provides `(go)` to retrieve the process table.

## Tested examples

| Example | Status |
|---------|--------|
| `simple.HELLOWORLD` | Compiles, builds, and runs end-to-end |
| `collatz.COLLATZ(20,44)` | Compiles, builds, and runs (requires stack fix) |
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
