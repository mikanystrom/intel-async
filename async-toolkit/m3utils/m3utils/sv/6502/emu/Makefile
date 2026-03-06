CC = gcc
CFLAGS = -O2 -Wall

emu6502: emu6502.c fake6502.c
	$(CC) $(CFLAGS) -o $@ $^

clean:
	rm -f emu6502

.PHONY: clean
