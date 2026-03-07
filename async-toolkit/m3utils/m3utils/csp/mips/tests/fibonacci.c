/* fibonacci.c — Print first 10 Fibonacci numbers */
void print_int(int n);
void halt(void);

int main(void) {
    int a = 0, b = 1;
    for (int i = 0; i < 10; i++) {
        print_int(b);
        int t = a + b;
        a = b;
        b = t;
    }
    return 0;
}
