CXX ?= c++
CXXFLAGS = -std=c++17 -O2 -fPIC

all: libtoyshapes.dylib libtoyshapes.a

libtoyshapes.dylib: shapes_c.o
	$(CXX) -shared -o $@ $<

libtoyshapes.a: shapes_c.o
	ar rcs $@ $<

shapes_c.o: shapes_c.cpp shapes_c.h shapes.hpp
	$(CXX) $(CXXFLAGS) -c -o $@ shapes_c.cpp

clean:
	rm -f *.o *.a *.dylib
