/* sort.c — Bubble sort 8 integers and print them */
void print_int(int n);
void halt(void);

int main(void) {
    int arr[] = {64, 34, 25, 12, 22, 11, 90, 1};
    int n = 8;

    /* Bubble sort */
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - i - 1; j++) {
            if (arr[j] > arr[j + 1]) {
                int t = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = t;
            }
        }
    }

    /* Print sorted array */
    for (int i = 0; i < n; i++) {
        print_int(arr[i]);
    }
    return 0;
}
