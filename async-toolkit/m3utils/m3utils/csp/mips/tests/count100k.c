void print_int(int n);
int main(void) {
    volatile int i = 0;
    while (i < 100000) {
        i = i + 1;
    }
    print_int(i);
    return 0;
}
