/* collatz.c — Print Collatz sequence starting from 27 */
void print_int(int n);
void halt(void);

int main(void) {
    int n = 27;
    while (n != 1) {
        print_int(n);
        if (n & 1)
            n = 3 * n + 1;
        else
            n = n >> 1;
    }
    print_int(1);
    return 0;
}
