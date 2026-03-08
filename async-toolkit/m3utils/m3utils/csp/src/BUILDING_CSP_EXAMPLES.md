# Building CSP Examples

Instructions for compiling and running the CSP (Communicating Sequential
Processes) examples.  These assume you have already built CM3 and m3utils.

## Overview

The CSP compiler (`cspc`) compiles Fulcrum-CSP hardware process
descriptions into Modula-3 simulation code.  There are two ways to
build a CSP system:

**Method 1: `.sys` files (recommended for new designs).**
Write a `.sys` system description referencing `.csp` process files.
`build-system!` handles the full pipeline: parsing, frontend
compilation via `cspfe`, code generation, and CM3 build.

**Method 2: `.procs` files (Java-era intermediate form).**
Pre-generated `.il/` directories contain `.procs` and `.scm` files
produced by the Java frontend.  `drive!` compiles these through the
Scheme backend and generates a buildable simulator.

Both methods produce the same output: a native simulator binary.

## Prerequisites

```sh
export M3UTILS="$HOME/cm3/intel-async/async-toolkit/m3utils/m3utils"
export PATH="$HOME/cm3/install/bin:/usr/bin:/bin:$PATH"
```

Make sure `cspc` and `cspfe` have been built (`gmake` from the m3utils
root, or `cm3 -build -override` in `csp/src` and `csp/cspparse/src`).

The `cspc` binary is at `csp/<TARGET>/cspc` and `cspfe` at
`csp/cspparse/<TARGET>/cspfe`, where `<TARGET>` is the CM3 target
directory (e.g., `ARM64_DARWIN`, `AMD64_LINUX`).

### Stack size on macOS

The Scheme compiler uses deep recursion during AST processing and
function inlining.  On macOS the CM3 ARM64\_DARWIN config sets 512 MB
via the linker flag (`-Wl,-stack_size,0x20000000`).  On Linux,
`ulimit -s unlimited` is sufficient.

## Method 1: Building from `.sys` files

`build-system!` handles the entire pipeline from a single `.sys` file:
parsing, running `cspfe` on each process, code generation, and CM3
build.

### Quick start

```sh
cd /path/to/my-project
cspc -scm /dev/stdin <<'EOF'
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))
(load (string-append (Env.Get "M3UTILS") "/csp/src/cspbuild.scm"))
(build-system! "example.sys")
(exit)
EOF
build/$(../../m3arch.sh)/sim
```

Or use `build.sh` if the project provides one (e.g., `csp/mips/build.sh`).

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

Inline CSP bodies are delimited by `%[%` and `%]%`.  Comments use
`(* ... *)` (nestable) or `// ...` (to end of line).

### Example: Hello World

```
system Hello;
  process Hello = %[% print("hello, world!") %]%;
begin
  var h : Hello;
end.
```

### Example: Producer-Consumer

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

### Example: MiniMIPS processor

Seven-process asynchronous MIPS I processor (see `csp/mips/`):

```sh
cd $M3UTILS/csp/mips
bash build.sh
cp tests/count10k.hex program.hex
cp tests/count10k_data.hex data.hex
build/$(../../m3arch.sh)/sim
```

## Method 2: Building from `.procs` files

Pre-generated intermediate forms from the Java frontend are in
`simplecsp/cast/*.il/`.  Each `.il/` directory contains:

- A `.procs` file describing the process graph (instances, types,
  channel bindings)
- One `.scm` file per process type (S-expression AST)

`drive!` reads the `.procs` file, compiles all referenced `.scm` files,
and generates a complete buildable project.

### Quick start

```sh
cd $M3UTILS/csp/simplecsp/cast/<example>.il
mkdir -p build/src

cspc -scm /dev/stdin <<'EOF'
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))
(drive! "<procs-file>.procs")
(exit)
EOF

cd build/src
cm3 -build -override
../$(../../m3arch.sh)/sim
```

### Example: HELLOWORLD

One process, no channels.

```sh
cd $M3UTILS/csp/simplecsp/cast/simple.HELLOWORLD.il
mkdir -p build/src

cspc -scm /dev/stdin <<'EOF'
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))
(drive! "simple_46_HELLOWORLD.procs")
(exit)
EOF

cd build/src
cm3 -build -override
../$(../../m3arch.sh)/sim
```

Output:
```
1: x: hello, world!
```

### Example: 4096-process ring pipeline

4096 processes connected in a ring, passing random data.

```sh
cd $M3UTILS/csp/simplecsp/cast/first.SYSTEM.il
mkdir -p build/src

cspc -scm /dev/stdin <<'EOF'
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))
(drive! "first_46_SYSTEM.procs")
(exit)
EOF

cd build/src
cm3 -build -override
../$(../../m3arch.sh)/sim
```

Output (runs indefinitely, Ctrl-C to stop):
```
8193: x.p[0]: i = 0 x = 957704962
16385: x.p[0]: i = 1 x = 1878784121
24577: x.p[0]: i = 2 x = 261057686
...
```

### Example: Parallel Collatz (20 workers)

59 process instances: 20 workers, a tree of splitters, a tree of
mergers, and a manager.  Searches for longest Collatz chains.

```sh
cd $M3UTILS/csp/simplecsp/cast/collatz.COLLATZ_20_44.il
mkdir -p build/src

cspc -scm /dev/stdin <<'EOF'
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))
(drive! "collatz_46_COLLATZ_40_20_44_44_41_.procs")
(exit)
EOF

cd build/src
cm3 -build -override
../$(../../m3arch.sh)/sim
```

Output (runs until all phases complete):
```
11: x.wrkr[0]: id = 0
...
29: x.mgr: num = 39 ; chain = 34 : total steps = 34 wall = 1 ksteps/s = 0
...
145: x.mgr: phase 1 complete, re-launching...
```

## Step-by-step compilation

You can also run the compiler stages individually, which is useful for
debugging or inspecting intermediate results.

```sh
cd $M3UTILS/csp/simplecsp/cast/simple.HELLOWORLD.il
mkdir -p build/src

cspc -scm /dev/stdin <<'EOF'
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))

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
| `SimMain.m3` | Simulator main program |
| `m3makefile` | CM3 build file |
| `CspDebug.i3` | Debug configuration interface |

## Simulator options

The generated `sim` binary accepts several command-line options:

| Flag | Description |
|------|-------------|
| `-scm` | Enter the Scheme REPL after building the simulation |
| `-mt N` | Use N threads for simulation |
| `-greedy` | Use greedy scheduling |
| `-nondet` | Use nondeterministic scheduling |
| `-eager` | Eager scheduling (bypass queue when 1 process ready) |
| `-master N cmd` | Distributed simulation: master with N workers |
| `-worker id` | Distributed simulation: worker process |

## Available examples

### Pre-generated `.il/` examples (no Java frontend needed)

| Example | Procs | Channels | Description | Status |
|---------|-------|----------|-------------|--------|
| `simple.HELLOWORLD` | 1 | 0 | Prints "hello, world!" | Tested |
| `first.SYSTEM` | 4096 | 4096 | Ring pipeline, random data | Tested |
| `collatz.COLLATZ_20_44` | 59 | ~80 | Parallel Collatz search | Tested |

### `.sys` test suite

26 tests in `csp/src/tests/sys/` covering parsing, building, and error
detection.  Run with `sh run_sys_tests.sh`.

### MiniMIPS processor

Seven-process MIPS I processor in `csp/mips/` with 11 test programs
(assembly and C).  See `csp/mips/README.md`.

### CAST source files (require Java frontend)

41 `.cast` source files in `simplecsp/cast/` cover a wide range of
language features: arrays, structs, bit operations, functions, loops,
parallelism, probes, and more.  These require the Java frontend
(`csp2java`) to regenerate `.il/` intermediate forms.

## Notes

- The `build/src/m3overrides` generated by `drive!` and `build-system!`
  points back to the m3utils `m3overrides`, so all library dependencies
  are resolved automatically.
- The `.procs` file format is one line per process instance:
  `instance_name  cell_type  escaped_type_name  port=channel ...`
