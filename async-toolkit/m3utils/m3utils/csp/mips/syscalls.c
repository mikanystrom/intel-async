/* syscalls.c — C wrappers for MiniMIPS simulator syscalls */

void print_int(int n) {
    register int a0 asm("a0") = n;
    register int v0 asm("v0") = 1;
    asm volatile("syscall" : : "r"(v0), "r"(a0));
}

void halt(void) {
    register int v0 asm("v0") = 10;
    asm volatile("syscall" : : "r"(v0));
    __builtin_unreachable();
}
