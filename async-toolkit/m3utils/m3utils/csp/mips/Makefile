# Makefile — Build MIPS programs for MiniMIPS simulator
#
# Usage:
#   make tests/fibonacci.hex    # compile fibonacci.c -> hex
#   make run-fibonacci          # compile + run on simulator
#   make all                    # compile all test programs
#
# Prerequisites: brew install llvm lld

LLVM     := /opt/homebrew/opt/llvm/bin
CC       := $(LLVM)/clang
LD       := /opt/homebrew/opt/lld/bin/ld.lld
OBJCOPY  := $(LLVM)/llvm-objcopy
OBJDUMP  := $(LLVM)/llvm-objdump

CFLAGS   := -target mipsel-unknown-elf -mcpu=mips1 -msoft-float \
            -ffreestanding -nostdlib -O1 -fno-builtin
LDFLAGS  := -T link.ld --oformat elf

MIPSDIR  := $(dir $(lastword $(MAKEFILE_LIST)))
PYTHON   := python3

# Test programs
TESTS    := fibonacci collatz sort count10k

all: $(patsubst %,tests/%.hex,$(TESTS))

# Compile C to object
tests/%.o: tests/%.c syscalls.c
	$(CC) $(CFLAGS) -c $< -o $@

tests/syscalls.o: syscalls.c
	$(CC) $(CFLAGS) -c $< -o $@

tests/crt0.o: crt0.s
	$(CC) $(CFLAGS) -c $< -o $@

# Link
tests/%.elf: tests/crt0.o tests/%.o tests/syscalls.o
	$(LD) $(LDFLAGS) $^ -o $@

# Convert ELF to hex (text + data)
tests/%.hex: tests/%.elf
	$(PYTHON) mips2hex.py $< --text $@ --data tests/$*_data.hex

# Disassemble (for debugging)
tests/%.dis: tests/%.elf
	$(OBJDUMP) -d $< > $@

# Run on simulator (requires sim binary in build/ARM64_DARWIN/)
run-%: tests/%.hex
	cp $< program.hex
	cp tests/$*_data.hex data.hex
	./build/ARM64_DARWIN/sim

# Clean generated files
clean:
	rm -f tests/*.o tests/*.elf tests/*.dis
	rm -f tests/fibonacci.hex tests/collatz.hex tests/sort.hex
	rm -f tests/*_data.hex
	rm -f program.hex data.hex

.PHONY: all clean run-%
