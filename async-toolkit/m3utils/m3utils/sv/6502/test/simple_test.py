#!/usr/bin/env python3
"""Generate a simple 6502 test program as a hex file for iverilog.

Tests: LDA imm, STA zp, LDX imm, INX, STX zp, ADC, CMP, BEQ/BNE,
       JMP, JSR/RTS.  Final result stored at $10.  If all tests pass,
       loops at the success address (0x0300).  On failure, loops at the
       failing test's address.
"""

mem = [0] * 65536

def emit(addr, *bytes_):
    for i, b in enumerate(bytes_):
        mem[addr + i] = b & 0xFF
    return addr + len(bytes_)

pc = 0x0200  # program start

# --- Test 1: LDA #$42, STA $10, LDA #$00, CMP $10 ---
# After: A=$00, mem[$10]=$42
t1 = pc
pc = emit(pc, 0xA9, 0x42)      # LDA #$42
pc = emit(pc, 0x85, 0x10)      # STA $10
pc = emit(pc, 0xA9, 0x00)      # LDA #$00
pc = emit(pc, 0xC5, 0x10)      # CMP $10  (should set flags: Z=0, C=0)
pc = emit(pc, 0xF0, 0xFE)      # BEQ *    (trap: should NOT be equal)
# fall through = pass

# --- Test 2: LDA $10, CMP #$42 ---
t2 = pc
pc = emit(pc, 0xA5, 0x10)      # LDA $10  (should get $42)
pc = emit(pc, 0xC9, 0x42)      # CMP #$42 (should set Z=1)
pc = emit(pc, 0xD0, 0xFE)      # BNE *    (trap: should be equal)
# fall through = pass

# --- Test 3: ADC ---
t3 = pc
pc = emit(pc, 0x18)            # CLC
pc = emit(pc, 0xA9, 0x13)      # LDA #$13
pc = emit(pc, 0x69, 0x25)      # ADC #$25  (should give $38)
pc = emit(pc, 0xC9, 0x38)      # CMP #$38
pc = emit(pc, 0xD0, 0xFE)      # BNE *    (trap)

# --- Test 4: LDX, INX, STX ---
t4 = pc
pc = emit(pc, 0xA2, 0x05)      # LDX #$05
pc = emit(pc, 0xE8)            # INX      (X=$06)
pc = emit(pc, 0xE8)            # INX      (X=$07)
pc = emit(pc, 0x86, 0x11)      # STX $11
pc = emit(pc, 0xA5, 0x11)      # LDA $11
pc = emit(pc, 0xC9, 0x07)      # CMP #$07
pc = emit(pc, 0xD0, 0xFE)      # BNE *    (trap)

# --- Test 5: JSR/RTS ---
t5 = pc
pc = emit(pc, 0xA9, 0x00)      # LDA #$00
# JSR to subroutine that sets A=$99
# JSR(3) + CMP(2) + BNE(2) + JMP(3) = 10 bytes after LDA
jsr_target = pc + 3 + 2 + 2 + 3  # skip past JSR + check code + JMP
pc = emit(pc, 0x20, jsr_target & 0xFF, (jsr_target >> 8) & 0xFF)  # JSR
# After RTS, should continue here with A=$99
pc = emit(pc, 0xC9, 0x99)      # CMP #$99
pc = emit(pc, 0xD0, 0xFE)      # BNE *    (trap)
pc = emit(pc, 0x4C, 0x00, 0x03)  # JMP $0300 (success!)

# Subroutine at jsr_target
assert pc == jsr_target, f"jsr_target mismatch: {pc:#x} != {jsr_target:#x}"
pc = emit(pc, 0xA9, 0x99)      # LDA #$99
pc = emit(pc, 0x60)            # RTS

# --- Success: loop at $0300 ---
emit(0x0300, 0x4C, 0x00, 0x03)  # JMP $0300 (infinite loop = success)

# --- Reset vector ---
mem[0xFFFC] = 0x00
mem[0xFFFD] = 0x02  # reset to $0200

# Write hex file
with open('sv/6502/test/simple_test.hex', 'w') as f:
    for b in mem:
        f.write(f'{b:02x}\n')

print(f"Generated simple_test.hex")
print(f"  Program: $0200-${pc-1:04x}")
print(f"  Success: $0300")
print(f"  Reset:   $0200")
