/* Compatibility shims for macOS which lacks some old POSIX math functions */
#include <math.h>

#ifdef __APPLE__
double drem(double x, double y) { return remainder(x, y); }
double gamma(double x) { return tgamma(x); }
#endif
