/*
 * emu6502.c -- 6502 emulator harness
 *
 * Uses fake6502 as the reference model.
 * Loads a binary image into a 64KB memory space,
 * sets reset vector, and runs until PC is stuck or
 * a cycle limit is reached.
 *
 * Usage: emu6502 [--cycles N] [--start ADDR] binary.bin
 *
 * The binary is loaded at address 0x0000 by default (filling
 * the full 64KB space), or at a specified offset.
 *
 * For the Klaus Dormann test suite:
 *   emu6502 --start 0x0400 6502_functional_test.bin
 *
 * The program detects completion when PC doesn't change
 * between instructions (tight loop = test done).
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

/* 64KB memory */
static uint8_t memory[65536];

/* Memory interface for fake6502 */
uint8_t read6502(uint16_t address) {
    return memory[address];
}

void write6502(uint16_t address, uint8_t value) {
    memory[address] = value;
}

/* Import fake6502 API */
extern void reset6502(void);
extern void step6502(void);
extern uint32_t clockticks6502;
extern uint32_t instructions;
extern uint16_t pc;
extern uint8_t sp, a, x, y, status;

static void usage(const char *prog) {
    fprintf(stderr, "Usage: %s [--cycles N] [--start ADDR] [--success ADDR] binary.bin\n", prog);
    fprintf(stderr, "\n");
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  --cycles N       Maximum cycles (default: 100000000)\n");
    fprintf(stderr, "  --start ADDR     Load address in hex (default: 0x0000)\n");
    fprintf(stderr, "  --success ADDR   Success address in hex (PC at this addr = pass)\n");
    fprintf(stderr, "  --reset ADDR     Reset vector value in hex (default: from 0xFFFC)\n");
    exit(1);
}

int main(int argc, char **argv) {
    uint32_t max_cycles = 100000000;
    uint16_t load_addr = 0x0000;
    uint16_t success_addr = 0;
    uint16_t reset_addr = 0;
    int has_success = 0;
    int has_reset = 0;
    const char *binfile = NULL;

    /* Parse arguments */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--cycles") == 0 && i+1 < argc) {
            max_cycles = strtoul(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "--start") == 0 && i+1 < argc) {
            load_addr = strtoul(argv[++i], NULL, 16);
        } else if (strcmp(argv[i], "--success") == 0 && i+1 < argc) {
            success_addr = strtoul(argv[++i], NULL, 16);
            has_success = 1;
        } else if (strcmp(argv[i], "--reset") == 0 && i+1 < argc) {
            reset_addr = strtoul(argv[++i], NULL, 16);
            has_reset = 1;
        } else if (argv[i][0] == '-') {
            usage(argv[0]);
        } else {
            binfile = argv[i];
        }
    }

    if (!binfile) usage(argv[0]);

    /* Initialize memory */
    memset(memory, 0, sizeof(memory));

    /* Load binary */
    FILE *f = fopen(binfile, "rb");
    if (!f) {
        fprintf(stderr, "ERROR: cannot open %s\n", binfile);
        return 1;
    }

    size_t max_load = 65536 - load_addr;
    size_t loaded = fread(&memory[load_addr], 1, max_load, f);
    fclose(f);

    printf("Loaded %zu bytes at 0x%04X\n", loaded, load_addr);

    /* Set reset vector if specified */
    if (has_reset) {
        memory[0xFFFC] = reset_addr & 0xFF;
        memory[0xFFFD] = (reset_addr >> 8) & 0xFF;
        printf("Reset vector: 0x%04X\n", reset_addr);
    }

    /* Reset CPU */
    reset6502();
    printf("PC after reset: 0x%04X\n", pc);
    printf("Running (max %u cycles)...\n", max_cycles);

    /* Execute */
    uint16_t prev_pc;
    int stuck_count = 0;
    int result = 0;

    while (clockticks6502 < max_cycles) {
        prev_pc = pc;
        step6502();

        /* Check for stuck PC (tight loop = test complete) */
        if (pc == prev_pc) {
            stuck_count++;
            if (stuck_count > 2) {
                printf("PC stuck at 0x%04X after %u instructions, %u cycles\n",
                       pc, instructions, clockticks6502);
                if (has_success) {
                    if (pc == success_addr) {
                        printf("PASS: reached success address 0x%04X\n", success_addr);
                        result = 0;
                    } else {
                        printf("FAIL: stuck at 0x%04X, expected 0x%04X\n", pc, success_addr);
                        result = 1;
                    }
                } else {
                    result = 0;
                }
                goto done;
            }
        } else {
            stuck_count = 0;
        }
    }

    printf("Cycle limit reached: %u instructions, %u cycles\n",
           instructions, clockticks6502);
    printf("Final PC: 0x%04X  A: 0x%02X  X: 0x%02X  Y: 0x%02X  SP: 0x%02X  P: 0x%02X\n",
           pc, a, x, y, sp, status);
    result = 1;

done:
    printf("Final state: A=0x%02X X=0x%02X Y=0x%02X SP=0x%02X P=0x%02X\n",
           a, x, y, sp, status);
    return result;
}
