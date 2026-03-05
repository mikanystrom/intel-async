# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

m3utils is a large collection of Modula-3 libraries and programs built with the CM3 (Critical Mass Modula-3) compiler. It spans domains including CSP (Communicating Sequential Processes) simulation, SPICE circuit analysis, VLSI design, financial trading, signal processing, and many other utilities. The CM3 compiler source lives at `~/cm3-git/`.

## Build System

### Quick Build

```sh
setenv CM3 yes        # or: export CM3=yes
gmake                 # builds "std" target (libraries then programs)
gmake regress         # builds regression/extended targets
```

### How It Works

The top-level `Makefile` (GNU Make) orchestrates building via `Make.defs`:

1. When `CM3` env var is set, uses `cm3 -override` as the build command
2. Generates `.top` file setting `TOP="$PWD"` — referenced by `m3overrides`
3. Builds in phases: **SHIPDIRS** (M3 libraries, built+shipped) → **M3SUBS** (M3 programs) → **REGSUBS** (regression targets)

### Building a Single Package

```sh
cd <package>/src      # e.g., csp/cspgrammar/src
cm3 -override         # build
cm3 -override -clean  # clean
cm3 -override -ship   # install to CM3 package pool
```

The `-override` flag tells cm3 to read `m3overrides` files, which map package names to local source directories (essential for resolving intra-repo dependencies without shipping to the system package pool).

### m3overrides

The top-level `m3overrides` file (written in Quake, the CM3 build language):
- Includes `.top` to get the `TOP` variable
- Sets `build_standalone()` for CM3 builds (static linking, since ld.so won't find local libs)
- Maps ~200 package names to their local directories via `override("name", TOP & "/path")`
- Lines prefixed with `%` are comments (disabled overrides)
- Defines `SYSTEM_LIBS{"MPZ"}` for GMP linking

### m3makefile Conventions

Each package has `src/m3makefile` (Quake language) that declares:
- `import("pkg")` — package dependencies
- `Module("Foo")` — compiles `Foo.i3` + `Foo.m3`
- `Interface("Foo")` — interface only (`.i3`)
- `Sequence("Foo", "Foo")` — generic sequence instantiation
- `Table("Key", "Key", "Value")` — generic table instantiation
- `library("name")` / `program("name")` — what to produce
- `SchemeStubs("Foo")` / `Smodule("Foo")` — mscheme integration (generates Scheme bindings)
- `c_source("foo")` — C source files

## Modula-3 Source Conventions

- `.i3` files — interfaces (like header files)
- `.m3` files — implementations (modules)
- `.ig` / `.mg` files — generic interfaces/modules (templates)
- Source lives in `<package>/src/`; build artifacts go to `<package>/<TARGET>/` (e.g., `AMD64_LINUX/`, `ARM64_DARWIN/`)
- Module names use PascalCase (e.g., `CspExpression`, `DynamicInt`)

## Key Subsystems

**CSP** (`csp/`): The most actively developed area. A CSP compiler and simulator:
- `cspgrammar/` — AST library (expressions, statements, types, declarations)
- `cspsimlib/` — simulation runtime (channels, scheduling, compiled processes)
- `src/` — `cspc` program: the CSP compiler driver, heavily integrated with mscheme (Scheme bindings for the AST and runtime). Uses `SchemeStubs` to expose M3 types to Scheme and `Smodule` for Scheme-callable modules.
- `doc/` — LaTeX documentation for the CSP language and cspbuild system

**SPICE** (`spice/`): Circuit simulation tools — `spicelib`, `spiceflat`, `ctlib`, `tracelib`, `spicecompress`, `spicetiming`, `techc`, `schemagraph`, `genopt`, etc.

**mscheme**: A Scheme interpreter embedded in Modula-3 (lives in the CM3 tree at `~/cm3-git/m3-scheme/`). The `sstubgen` tool generates Scheme stubs from M3 interfaces, enabling Scheme scripts to manipulate M3 objects. CSP uses this extensively.

## CM3 Compiler

The CM3 checkout at `~/cm3-git/` contains:
- `m3-sys/cm3/` — compiler driver (interprets Quake build scripts)
- `m3-sys/m3front/` — front end
- `m3-libs/m3core/`, `m3-libs/libm3/` — core runtime and standard library
- `m3-scheme/` — mscheme (Scheme interpreter for M3)
- Build scripts in `scripts/` (e.g., `do-cm3-std.sh`)

To rebuild CM3 itself: `cd ~/cm3-git/cm3 && scripts/concierge.py full-upgrade --backend c all`

## Platform Notes

- Primary target: `AMD64_LINUX` (Linux x86-64)
- ARM64_DARWIN (Apple Silicon macOS) is supported — see `BUILDING_DARWIN_2026_03_02.md` for detailed setup (requires Homebrew deps, config patches for C compiler and X11 libs)
- The GCC backend is needed on AMD64_LINUX for full functionality; ARM64_DARWIN uses the C backend
