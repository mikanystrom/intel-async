/* link.ld — Linker script for MiniMIPS simulator
 *
 * Text at 0x0 (instruction memory), data at 0x10000 (data memory).
 * The simulator loads .text into imem[] and .data into dmem[].
 */
ENTRY(_start)

SECTIONS {
    . = 0x0;
    .text : {
        *(.text)
        *(.text.*)
    }

    . = 0x10000;
    .data : {
        *(.data)
        *(.rodata)
        *(.rodata.*)
        *(.sdata)
    }
    .bss : {
        *(.bss)
        *(.sbss)
    }

    /DISCARD/ : {
        *(.MIPS.abiflags)
        *(.reginfo)
        *(.pdr)
        *(.comment)
        *(.note.GNU-stack)
        *(.mdebug.abi32)
        *(.got)
    }
}
