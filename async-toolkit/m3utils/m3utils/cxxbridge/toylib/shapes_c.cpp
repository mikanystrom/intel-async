// shapes_c.cpp — C bridge implementation

#include "shapes_c.h"
#include "shapes.hpp"

#include <cstring>
#include <cstdlib>

using namespace toy;

// Thread-local error message
static thread_local char error_buf[256] = "";

static void set_error(const char *msg) {
    strncpy(error_buf, msg, sizeof(error_buf) - 1);
    error_buf[sizeof(error_buf) - 1] = '\0';
}

static void clear_error() { error_buf[0] = '\0'; }

extern "C" {

const char *toy_last_error(void) {
    return error_buf;
}

// --- Shape constructors ---

toy_shape_t toy_circle_new(double cx, double cy, double r) {
    clear_error();
    try {
        return static_cast<toy_shape_t>(new Circle(cx, cy, r));
    } catch (const std::exception &e) {
        set_error(e.what());
        return NULL;
    } catch (...) {
        set_error("unknown C++ exception");
        return NULL;
    }
}

toy_shape_t toy_rectangle_new(double cx, double cy, double w, double h) {
    clear_error();
    try {
        return static_cast<toy_shape_t>(new Rectangle(cx, cy, w, h));
    } catch (const std::exception &e) {
        set_error(e.what());
        return NULL;
    } catch (...) {
        set_error("unknown C++ exception");
        return NULL;
    }
}

// --- Shape methods ---

void toy_shape_free(toy_shape_t s) {
    delete static_cast<Shape*>(s);
}

double toy_shape_cx(toy_shape_t s) {
    return static_cast<Shape*>(s)->cx();
}

double toy_shape_cy(toy_shape_t s) {
    return static_cast<Shape*>(s)->cy();
}

void toy_shape_move(toy_shape_t s, double dx, double dy) {
    static_cast<Shape*>(s)->move(dx, dy);
}

double toy_shape_area(toy_shape_t s) {
    return static_cast<Shape*>(s)->area();
}

double toy_shape_perimeter(toy_shape_t s) {
    return static_cast<Shape*>(s)->perimeter();
}

int toy_shape_contains(toy_shape_t s, double px, double py) {
    return static_cast<Shape*>(s)->contains(px, py) ? 1 : 0;
}

char *toy_shape_name(toy_shape_t s) {
    std::string n = static_cast<Shape*>(s)->name();
    char *r = (char*)malloc(n.size() + 1);
    if (r) strcpy(r, n.c_str());
    return r;
}

// --- ShapeList ---

toy_shapelist_t toy_shapelist_new(void) {
    clear_error();
    try {
        return static_cast<toy_shapelist_t>(new ShapeList());
    } catch (...) {
        set_error("failed to create ShapeList");
        return NULL;
    }
}

void toy_shapelist_free(toy_shapelist_t sl) {
    delete static_cast<ShapeList*>(sl);
}

void toy_shapelist_add(toy_shapelist_t sl, toy_shape_t s) {
    static_cast<ShapeList*>(sl)->add(static_cast<Shape*>(s));
}

size_t toy_shapelist_size(toy_shapelist_t sl) {
    return static_cast<ShapeList*>(sl)->size();
}

toy_shape_t toy_shapelist_get(toy_shapelist_t sl, size_t i) {
    return static_cast<toy_shape_t>(static_cast<ShapeList*>(sl)->get(i));
}

double toy_shapelist_total_area(toy_shapelist_t sl) {
    return static_cast<ShapeList*>(sl)->totalArea();
}

// --- Callbacks ---

// The C bridge wraps the C function pointer + context into a
// std::function for the C++ side.

void toy_shapelist_foreach(toy_shapelist_t sl,
                           toy_visitor_fn fn, void *ctx) {
    static_cast<ShapeList*>(sl)->forEach(
        [fn, ctx](Shape *s, size_t i) {
            fn(static_cast<toy_shape_t>(s), i, ctx);
        });
}

toy_shape_t *toy_shapelist_filter(toy_shapelist_t sl,
                                  toy_predicate_fn fn, void *ctx,
                                  size_t *out_n) {
    auto result = static_cast<ShapeList*>(sl)->filter(
        [fn, ctx](const Shape *s) -> bool {
            return fn(const_cast<toy_shape_t>(
                static_cast<const void*>(s)), ctx) != 0;
        });

    *out_n = result.size();
    if (result.empty()) return NULL;

    toy_shape_t *arr = (toy_shape_t*)malloc(result.size() * sizeof(toy_shape_t));
    for (size_t i = 0; i < result.size(); ++i)
        arr[i] = static_cast<toy_shape_t>(result[i]);
    return arr;
}

} // extern "C"
