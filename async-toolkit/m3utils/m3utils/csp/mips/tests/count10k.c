/* count10k.c — Count to 10,000, print final value.
 * Performance benchmark: measures simulator throughput.
 * Uses volatile to prevent the compiler from optimizing away the loop.
 */
void print_int(int n);

int main(void) {
    volatile int i = 0;
    while (i < 10000) {
        i = i + 1;
    }
    print_int(i);
    return 0;
}
