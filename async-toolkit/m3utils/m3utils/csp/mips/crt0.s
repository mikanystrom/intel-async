## crt0.s — MIPS startup code for MiniMIPS simulator
## Sets up stack pointer and calls main, then exits via SYSCALL 10.

    .set noreorder
    .text
    .globl _start
    .ent _start

_start:
    li      $sp, 0xFFFC         # stack at top of 64KB data memory
    jal     main
    nop                         # delay slot
    move    $a0, $v0            # main's return value
    li      $v0, 10             # syscall: exit
    syscall
    nop                         # (never reached)

    .end _start
