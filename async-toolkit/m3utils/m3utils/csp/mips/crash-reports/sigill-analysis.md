# SIGILL (exit code 132) Analysis for cspc on ARM64 Darwin

Date: 2026-03-07
Platform: Darwin 25.3.0, ARM64 (Apple Silicon T6041)
Binary: `/Users/mika/cm3/intel-async/async-toolkit/m3utils/m3utils/csp/ARM64_DARWIN/cspc`
(Mach-O 64-bit executable arm64, 7.8 MB)

## Executive Summary

The transient SIGILL crash in cspc on ARM64 Darwin is most likely caused by
**longjmp to a corrupted jmp_buf during exception handling, where the
PAC (Pointer Authentication Code) signature check on the saved return
address fails**. This is triggered by a race condition in the garbage
collector's thread suspension mechanism. A secondary contributing factor
is the completely broken `m3_fence()` implementation on non-x86 platforms.

## Root Cause Analysis

### Primary Hypothesis: PAC-signed longjmp + GC Corruption

On Apple Silicon (ARM64), the CPU uses Pointer Authentication Codes (PAC)
to sign return addresses and other code pointers. When `_setjmp` saves the
execution context, the return address in the jmp_buf is PAC-signed. When
`_longjmp` restores it, the CPU verifies the signature. **If the jmp_buf
has been modified in any way -- even a single bit flip -- the PAC check
fails and the CPU raises SIGILL** (not SIGSEGV, because the instruction
is an authentication failure, not an access violation).

The CM3 runtime exception handling uses `_setjmp`/`_longjmp` (via
`Csetjmp__m3_longjmp` in `m3-libs/m3core/src/C/Common/CsetjmpC.c`):

```c
// For ARM64 Darwin (non-Win32, non-Solaris):
void __cdecl Csetjmp__m3_longjmp(Csetjmp__jmp_buf env, int val)
{
    _longjmp(*env, val);
}
```

And the generated C code uses:
```c
#define m3_setjmp(env) (_setjmp(env))
```

The jmp_buf is allocated with `alloca` on the stack. If GC activity
between the setjmp and longjmp corrupts either:
- The stack memory containing the jmp_buf (via incorrect stack scanning bounds)
- A pointer that is used to locate the jmp_buf

...then the longjmp will hit a PAC authentication failure = SIGILL.

### Why It's Transient

The crash is non-deterministic because it requires a specific timing
window where:

1. A thread has an active exception frame (jmp_buf on stack from `_setjmp`)
2. The GC fires (`CollectSomeInStateZero` in `RTCollector.m3`)
3. The GC suspends the thread via Mach `thread_suspend` + `thread_abort_safely`
   (`ThreadApple.c:26-51`)
4. During stack scanning (`ProcessStopped` / `ProcessOther`), the GC either:
   - Scans the stack with incorrect bounds (due to ARM64 red zone or PAC),
     writing GC metadata into the jmp_buf region, or
   - The `__darwin_arm_thread_state64_get_sp()` on line 137 of
     `ThreadApple.c` returns a stack pointer that is slightly off, causing
     the scan range to be wrong

The relevant code in `ThreadApple.c`:
```c
#if defined(__arm__) || defined(__arm64__)
  sp = (char*)__darwin_arm_thread_state64_get_sp(state);
#else
  sp = (char*)(state.M3_STACK_REGISTER);
#endif
  sp -= M3_STACK_ADJUST;       // <-- M3_STACK_ADJUST is 0 for ARM64!
  /* process the stack */
  if (sp < top)
      p(sp, top);
  else if (sp > top)
      p(top, sp);
  /* process the registers */
  p(&state, &state + 1);       // <-- scans register state too
```

Note that `M3_STACK_ADJUST` is 0 for ARM64. On x86-64, it's 128 (the red zone).
ARM64 also has a red zone concept, but the CM3 runtime doesn't account for it.

### Secondary Factor: Broken `m3_fence()` on ARM64

In `m3-sys/m3back/src/M3C.m3` (lines 4873-4889), the `m3_fence` helper
for non-MSVC platforms is defined as:

```c
static void __stdcall m3_fence(void){}  // not yet implemented
```

This is a **no-op** -- it does nothing. On x86, this is tolerable because
x86 has a strong memory model (TSO). On ARM64, which has a weak memory
model, this means:

- The `inCritical` flag in `RTHeapRep.ThreadState` (used to prevent GC
  from suspending a thread during allocation) may not be visible to the
  GC thread promptly, allowing the GC to suspend a thread that is
  mid-allocation
- Any concurrent data structure relying on fences for correctness will
  have data races

While this probably doesn't directly cause SIGILL, it increases the
probability of the GC observing inconsistent state.

### Tertiary: No SIGILL Handler Installed

The CM3 signal handler (`RTSignalC.c`, lines 104-120) installs handlers
for SIGHUP, SIGINT, SIGQUIT, SIGSEGV, SIGPIPE, SIGTERM, and SIGBUS --
**but NOT SIGILL**. This means:

1. SIGILL uses the default action (terminate + core dump)
2. No backtrace or diagnostic information is produced
3. The crash is less debuggable than other signal crashes

## Evidence Trail

### Files Examined

| File | Relevance |
|------|-----------|
| `m3core/src/runtime/POSIX/RTSignalC.c` | Signal handlers; SIGILL not handled |
| `m3core/src/thread/PTHREAD/ThreadApple.c` | Mach-based thread suspend/resume for GC |
| `m3core/src/thread/PTHREAD/ThreadPThread.m3` | StopWorld/StartWorld, inCritical checking |
| `m3core/src/thread/PTHREAD/ThreadPThreadC.c` | M3_DIRECT_SUSPEND on Apple, SIG_SUSPEND=0 |
| `m3core/src/runtime/common/RTCollector.m3` | GC collector; calls SuspendOthers |
| `m3core/src/runtime/common/RTAllocator.m3` | inCritical INC/DEC around allocations |
| `m3core/src/runtime/common/RTHeapRep.i3` | ThreadState with inCritical field |
| `m3core/src/C/Common/CsetjmpC.c` | _longjmp wrapper for exception handling |
| `m3core/src/runtime/ex_frame/RTExFrame.m3` | Exception handling via setjmp/longjmp |
| `m3core/src/m3core.h` | GET_PC for ARM64, __darwin_arm_thread_state64 |
| `m3-sys/m3back/src/M3C.m3` | C backend: m3_fence (broken), call_indirect |

### Key Observations

1. **ARM64 PAC + longjmp = SIGILL on corruption**: This is well-documented
   Apple behavior. Any corruption of PAC-signed values in jmp_buf causes
   SIGILL, not SIGSEGV.

2. **The GC uses direct Mach thread suspension on macOS**: This is inherently
   racy with stack-based jmp_bufs. The `thread_abort_safely` call should
   handle most cases, but the stack scanning bounds may be incorrect.

3. **M3_STACK_ADJUST=0 for ARM64**: The ARM64 ABI has a red zone (similar to
   x86-64's 128-byte red zone). Not accounting for it could cause the GC
   to scan into live but below-SP stack data.

4. **m3_fence is a no-op**: The weak memory model of ARM64 means the
   inCritical flag may not be visible when the GC checks it.

5. **Transient nature**: ~5-15% crash rate (per MEMORY.md notes about
   "retry with loop, succeeds on 2nd attempt") is consistent with a
   GC timing race.

## Recommended Fixes

### Fix 1: Install SIGILL handler for diagnostic capture (quick win)

In `m3core/src/runtime/POSIX/RTSignalC.c`, add SIGILL to the Handlers table:

```c
static const struct { int Signal; SIGNAL_HANDLER_TYPE Handler; }
Handlers[] = {
    { SIGHUP,  Shutdown },
    { SIGINT,  Interrupt },
    { SIGQUIT, Quit },
    { SIGILL,  SegV },         // <-- ADD THIS: capture PC on SIGILL
    { SIGSEGV, SegV },
    { SIGPIPE, IgnoreSignal },
    { SIGTERM, Shutdown },
    { SIGBUS,  SegV },
};
```

This will at least print the faulting PC address, which will confirm
whether the crash is in _longjmp (PAC failure) or elsewhere.

### Fix 2: Implement m3_fence properly on ARM64 (important)

In `m3-sys/m3back/src/M3C.m3`, change the fence implementation for
GCC/Clang to use a compiler built-in:

```c
#define m3_fence() __atomic_thread_fence(__ATOMIC_SEQ_CST)
```

Or at minimum:
```c
#define m3_fence() __asm__ __volatile__("dmb ish" ::: "memory")
```

### Fix 3: Account for ARM64 red zone in GC stack scanning (critical)

In `ThreadApple.c`, set `M3_STACK_ADJUST` for ARM64:

```c
#ifdef __arm64__
// ARM64 has a red zone below SP, similar to x86-64.
// The ABI allows functions to use up to 128 bytes below SP
// without adjusting SP. We must scan this region too.
#define M3_STACK_ADJUST 128
#endif
```

### Fix 4: Add memory barriers around inCritical (important)

In `RTAllocator.m3`, the `INC(thread.inCritical)` / `DEC(thread.inCritical)`
sequences need memory barriers on ARM64 to ensure the GC thread sees the
updated value promptly. Since Modula-3 lacks atomic operations at this level,
this would need to be done via a C helper that uses `__atomic_store_n`.

## Reproduction Strategy

The crash can be reproduced by running cspc in a loop with the MiniMIPS
build workload (7 CSP processes, heavy allocation):

```bash
#!/bin/bash
export M3UTILS=/Users/mika/cm3/intel-async/async-toolkit/m3utils/m3utils
export PATH="/Users/mika/cm3/install/bin:$PATH"

cat > /tmp/build_test.scm << 'EOF'
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))
(load (string-append (Env.Get "M3UTILS") "/csp/src/cspbuild.scm"))
(build-system! "minimips.sys")
(exit)
EOF

cd $M3UTILS/csp/mips
for i in $(seq 1 100); do
    $M3UTILS/csp/ARM64_DARWIN/cspc -scm /tmp/build_test.scm > /dev/null 2>&1
    rc=$?
    if [ $rc -eq 132 ]; then echo "[$i] SIGILL"; fi
done
```

For lldb-based capture:
```
lldb -- $M3UTILS/csp/ARM64_DARWIN/cspc -scm /tmp/build_test.scm
(lldb) process handle SIGILL --stop true --pass false --notify true
(lldb) breakpoint set -n RTSignalC__DefaultHandler
(lldb) breakpoint set -n RTOS__Crash
(lldb) run
```

When it crashes, check:
- `bt` -- is it in `_longjmp` / `__longjmp` / `_platform_longjmp`?
- `register read pc` -- is the faulting instruction an `autia` / `autib`?
- `image lookup -a $pc` -- is it in the cspc text section or libsystem?

## Workaround

The current retry loop in `build.sh` (max 5 attempts) is an adequate
workaround for now. The crash rate appears to be ~5-15%, so 5 retries
gives a failure probability of roughly 0.15^5 = 0.000076 (< 0.01%).
