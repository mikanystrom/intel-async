# Building CM3 and m3utils on ARM64_DARWIN (Apple Silicon macOS)

Notes from 2026-03-02.

## Prerequisites

Install via Homebrew:

```sh
brew install ninja cmake gnu-sed expat mpfr
brew install --cask xquartz    # for X11/GUI packages
```

Homebrew on ARM64 installs to `/opt/homebrew/`. XQuartz installs to `/opt/X11/`.

## 1. Get the sources

```sh
mkdir ~/cm3 && cd ~/cm3
git clone https://github.com/modula3/cm3.git
```

## 2. Bootstrap the compiler

The bootstrap is C source code, so an AMD64\_LINUX bootstrap tarball works
fine -- it just gets compiled locally via CMake.

```sh
cd ~/cm3
mkdir bootstrap build
curl --location --silent \
  https://github.com/modula3/cm3/releases/download/d5.11.10/cm3-boot-AMD64_LINUX-d5.11.10.tar.xz \
  | tar Jxf - -C bootstrap --strip-components=1
cmake -S bootstrap -B build -G Ninja -DCMAKE_INSTALL_PREFIX=$PWD/install
cmake --build build && cmake --install build
export PATH="$PWD/install/bin:$PATH"
```

**Fix needed:** The bootstrap's `m3core.h` may be missing
`#include <stdint.h>`, causing `uint32_t` undefined errors on macOS. If
the cmake build fails with this, add `#include <stdint.h>` at the top of
`bootstrap/m3core.h` and retry. (This is fixed in newer bootstrap
tarballs.)

## 3. Fix the ARM64\_DARWIN config

The shipped config has two problems:

- `Darwin.common` sets `SYSTEM_CC = "g++ -x c++"` which breaks C code
  (void\* implicit conversion errors).
- Missing `-lXpm` and `-L/opt/homebrew/lib` for X11 linking.

Edit `~/cm3/install/bin/config/ARM64_DARWIN` (and the source copy at
`cm3/m3-sys/cminstall/src/config/ARM64_DARWIN`) to pre-define `SYSTEM_CC`
**before** `Darwin.common` is included. Pre-defining `SYSTEM_CC` causes
`configure_c_compiler()` in `Darwin.common` to return early, bypassing the
`g++ -x c++` default.

```
readonly TARGET = "ARM64_DARWIN"

readonly DarwinArch = "arm64"

% Use C compiler (not C++) so that C sources compile as C.
% Darwin.common's configure_c_compiler() uses g++ -x c++ which breaks
% standard C idioms like implicit void* conversion.
SYSTEM_CC = "/usr/bin/cc -g -fPIC -arch arm64 -Wall -Werror -Wno-return-type -Wno-missing-braces -Wno-deprecated-non-prototype -Wno-unused-but-set-variable -Wno-uninitialized -I/opt/homebrew/opt/expat/include -I/opt/homebrew/include"
SYSTEM_CC_LD = "/usr/bin/cc -g -fPIC -arch arm64 -Wall -Werror -Wno-return-type -Wno-missing-braces -Wno-deprecated-non-prototype"
SYSTEM_CC_ASM = "/usr/bin/cc -arch arm64"

include("ARM64.common")
include("Darwin.common")

M3_PARALLEL_BACK = 20

% Homebrew.
SYSTEM_LIBS{"ODBC"} = ["-L/opt/homebrew/lib", "-liodbc", "-liodbcinst"]
SYSTEM_LIBS{"X11"} = ["-L/opt/X11/lib", "-L/opt/homebrew/lib", "-lXft", "-lfontconfig", "-lXaw", "-lXmu", "-lXext", "-lXt", "-lSM", "-lICE", "-lXpm", "-lX11" ]
SYSTEM_LIBS{"OPENGL"} = [ "-Wl,-dylib_file," & LIBGL_DYLIB & ":" & LIBGL_DYLIB,
                          "-L/opt/X11/lib", "-lGLU", "-lGL", "-lXext" ]
SYSTEM_LIBS{"EXPAT"} = ["-L/opt/homebrew/opt/expat/lib", "-lexpat"]
SYSTEM_LIBS{"MPFR"} = ["-L/opt/homebrew/lib", "-lmpfr", "-lgmp"]

SYSTEM_LIBORDER = [
    "OPENGL",
    "X11",
    "TCP",
    "ODBC",
    "EXPAT",
    "MPFR",
    "FLEX-BISON",
    "LEX-YACC",
    "LIBC"
]
```

Key points:

- `-Wno-deprecated-non-prototype`, `-Wno-unused-but-set-variable`,
  `-Wno-uninitialized` suppress warnings in legacy/f2c code that are
  errors under `-Werror`.
- `-I/opt/homebrew/include` and `-I/opt/homebrew/opt/expat/include` let C
  files find Homebrew headers.
- `-lXpm` added to X11 libs (missing in upstream).
- `-L/opt/homebrew/lib` added to X11 libs for Homebrew-installed libXpm.

## 4. Fix Darwin.common for empty libraries

macOS `libtool -static` fails when given no object files (happens with
generics-only packages like `simpletoken`). Edit
`~/cm3/install/bin/config/Darwin.common`, in the `make_lib` procedure,
after the `try_exec` line for `libtool -static`, add a fallback:

```
  ret_code = try_exec ("@" & SYSTEM_LIBTOOL, arch, "-static", "-o", lib_a, objects)
  if not equal(ret_code, 0)
    % Empty library (e.g. generics-only package): create valid archive with dummy object.
    ret_code = try_exec ("@/usr/bin/cc -c -x c /dev/null -o /tmp/_cm3_dummy.o && " & SYSTEM_LIBTOOL & " -static -o " & lib_a & " /tmp/_cm3_dummy.o")
  end
```

## 5. Build CM3

```sh
cd ~/cm3/cm3
scripts/concierge.py full-upgrade --backend c all
```

This builds everything including GUI packages with zero fatal errors.

**Note:** The GCC backend is not available -- the bundled GCC 4.7 doesn't
support AArch64. Use the C backend (`--backend c`), which is the default
and recommended option.

## 6. Building m3utils

Set PATH to include CM3, Homebrew, and GNU sed:

```sh
cd intel-async/async-toolkit/m3utils/m3utils
export PATH="$HOME/cm3/install/bin:/opt/homebrew/opt/gnu-sed/libexec/gnubin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/X11/bin"
make std       # builds standard targets
make intel     # builds Intel-specific targets (rdlparse, etc.)
```

Source fixes needed for m3utils (committed to `claude_edits` branch):

- **xmlParser.c**: Replace hardcoded `/usr/local/include/expat.h` with
  `#include <expat.h>` (include path provided via SYSTEM\_CC flags).
- **MpfrC.c**: Use `<stdlib.h>` instead of `<malloc.h>` on macOS
  (`malloc.h` does not exist on Darwin).
- **trstlp.c**: Mark unused f2c variable `iout` with
  `__attribute__((unused))`.
- **m3arch.sh**: Add ARM64\_DARWIN detection for arm64 Darwin.
- **mk\_inputs.sh**: Use `m3arch.sh` instead of hardcoded `AMD64_LINUX`
  for platform detection; use GNU sed (`gsed`) for `\U` uppercase which
  BSD sed does not support; use `cc -E -P -x c` instead of `cpp` because
  Apple's `cpp` wrapper cannot handle non-standard file extensions like
  `.ee`.
- **diesplit/compat.c**: Compatibility shims for `drem()` (use
  `remainder()`) and `gamma()` (use `tgamma()`) which are missing on
  macOS.
- **diesplit/m3makefile**: Link `compat.c` into the diesplit program.
- **diesplit/reports.scm**: Fix params format to include `n` (layer count)
  as third element, matching `report-yields-for-params` expectations.
- **diesplit/run.scm**: Work around `Polynomial.LaTeXFmt` nil dereference
  crash in `Mpfr.FormatInt` by redefining `decorate-yield` to skip LaTeX
  formatting.
- **diesplit/uncensor.sh**: Script to regenerate `.scm` files from
  `.CENSORED` versions with plausible dummy values for proprietary
  constants.

### Known non-critical build failures (make intel)

Three packages fail due to missing optional dependencies:

- **htmltable/cgidb**: Requires MySQL client library.
- **tcam/schmoozer**: Requires `newuoa` (separate build).
- **pg/pgtool**: Requires PostgreSQL client library.

These do not affect the rest of the build.
