/* shapes_c.h — C bridge for the toy::Shape C++ hierarchy
 *
 * Design decisions demonstrated here:
 *
 * 1. OBJECT LIFETIME: Opaque handles (void*).  The C side owns objects
 *    created by toy_*_new(); the caller must call toy_*_free().
 *    The M3 side wraps these in traced REF objects that call _free()
 *    from a weak-ref cleaner, giving GC-triggered destruction.
 *
 * 2. TYPE FIDELITY: We preserve the class hierarchy through a "kind"
 *    enum and type-specific constructors, but the handle type is
 *    uniform (toy_shape_t).  Virtual dispatch happens on the C++ side.
 *
 * 3. DATA SHARING: Strings are copied (caller must free).
 *    Numeric values are returned by value.
 *    The filter() result is a caller-owned array of borrowed handles.
 *
 * 4. CALLBACKS: toy_shapelist_foreach takes a C function pointer + a
 *    void* context.  The M3 side passes a closure environment as the
 *    context and a trampoline as the function pointer.
 *
 * 5. EXCEPTIONS: All functions that might throw return an error code
 *    or NULL, with a thread-local error message retrievable via
 *    toy_last_error().
 */

#ifndef SHAPES_C_H
#define SHAPES_C_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* --- Opaque handles --- */

typedef void *toy_shape_t;
typedef void *toy_shapelist_t;

/* --- Error handling --- */

const char *toy_last_error(void);

/* --- Shape constructors --- */

toy_shape_t toy_circle_new(double cx, double cy, double r);
toy_shape_t toy_rectangle_new(double cx, double cy, double w, double h);

/* --- Shape methods (virtual dispatch on the C++ side) --- */

void   toy_shape_free(toy_shape_t s);
double toy_shape_cx(toy_shape_t s);
double toy_shape_cy(toy_shape_t s);
void   toy_shape_move(toy_shape_t s, double dx, double dy);
double toy_shape_area(toy_shape_t s);
double toy_shape_perimeter(toy_shape_t s);
int    toy_shape_contains(toy_shape_t s, double px, double py);

/* Returns a malloc'd string; caller must free(). */
char  *toy_shape_name(toy_shape_t s);

/* --- ShapeList --- */

toy_shapelist_t toy_shapelist_new(void);
void            toy_shapelist_free(toy_shapelist_t sl);

/* Transfers ownership of s to the list. Do NOT free s after this. */
void            toy_shapelist_add(toy_shapelist_t sl, toy_shape_t s);

size_t          toy_shapelist_size(toy_shapelist_t sl);

/* Borrowed handle — do NOT free the returned shape. */
toy_shape_t     toy_shapelist_get(toy_shapelist_t sl, size_t i);

double          toy_shapelist_total_area(toy_shapelist_t sl);

/* --- Callbacks --- */

/* Visitor: called for each shape.  ctx is passed through from the caller. */
typedef void (*toy_visitor_fn)(toy_shape_t s, size_t index, void *ctx);
void toy_shapelist_foreach(toy_shapelist_t sl, toy_visitor_fn fn, void *ctx);

/* Predicate: return non-zero to include the shape. */
typedef int (*toy_predicate_fn)(toy_shape_t s, void *ctx);

/* Returns a malloc'd array of borrowed shape handles, with *out_n
 * set to the count.  Caller must free() the array but NOT the shapes. */
toy_shape_t *toy_shapelist_filter(toy_shapelist_t sl,
                                  toy_predicate_fn fn, void *ctx,
                                  size_t *out_n);

#ifdef __cplusplus
}
#endif

#endif /* SHAPES_C_H */
