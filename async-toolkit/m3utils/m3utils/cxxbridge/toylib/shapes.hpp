// shapes.hpp — toy C++ class hierarchy for M3 binding experiments

#ifndef SHAPES_HPP
#define SHAPES_HPP

#include <cmath>
#include <vector>
#include <string>
#include <functional>

namespace toy {

// Base class with virtual methods
class Shape {
public:
    Shape(double x, double y) : cx_(x), cy_(y) {}
    virtual ~Shape() {}

    double cx() const { return cx_; }
    double cy() const { return cy_; }
    void move(double dx, double dy) { cx_ += dx; cy_ += dy; }

    virtual double area() const = 0;
    virtual double perimeter() const = 0;
    virtual std::string name() const = 0;

    // Does the point (px,py) lie inside the shape?
    virtual bool contains(double px, double py) const = 0;

private:
    double cx_, cy_;
};

class Circle : public Shape {
public:
    Circle(double x, double y, double r) : Shape(x, y), r_(r) {}
    double radius() const { return r_; }

    double area() const override { return M_PI * r_ * r_; }
    double perimeter() const override { return 2.0 * M_PI * r_; }
    std::string name() const override { return "Circle"; }
    bool contains(double px, double py) const override {
        double dx = px - cx(), dy = py - cy();
        return dx*dx + dy*dy <= r_*r_;
    }

private:
    double r_;
};

class Rectangle : public Shape {
public:
    Rectangle(double x, double y, double w, double h)
        : Shape(x, y), w_(w), h_(h) {}
    double width() const { return w_; }
    double height() const { return h_; }

    double area() const override { return w_ * h_; }
    double perimeter() const override { return 2.0 * (w_ + h_); }
    std::string name() const override { return "Rectangle"; }
    bool contains(double px, double py) const override {
        double dx = px - cx(), dy = py - cy();
        return std::abs(dx) <= w_/2.0 && std::abs(dy) <= h_/2.0;
    }

private:
    double w_, h_;
};

// A collection that demonstrates iteration and callbacks
class ShapeList {
public:
    ~ShapeList() {
        for (auto s : shapes_) delete s;
    }
    void add(Shape *s) { shapes_.push_back(s); }
    size_t size() const { return shapes_.size(); }
    Shape *get(size_t i) const { return shapes_[i]; }

    // Iterate with a callback — the interesting binding case
    using Visitor = std::function<void(Shape *s, size_t index)>;
    void forEach(Visitor v) const {
        for (size_t i = 0; i < shapes_.size(); ++i)
            v(shapes_[i], i);
    }

    // Filter: return shapes that satisfy a predicate
    using Predicate = std::function<bool(const Shape *s)>;
    std::vector<Shape*> filter(Predicate p) const {
        std::vector<Shape*> result;
        for (auto s : shapes_)
            if (p(s)) result.push_back(s);
        return result;
    }

    double totalArea() const {
        double sum = 0;
        for (auto s : shapes_) sum += s->area();
        return sum;
    }

private:
    std::vector<Shape*> shapes_;
};

} // namespace toy

#endif // SHAPES_HPP
