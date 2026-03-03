#!/bin/sh
# CSP parser test suite
# Usage: sh run_tests.sh

CSPFE=../ARM64_DARWIN/cspfe
PASS=0
FAIL=0
TOTAL=0

run_test() {
    name="$1"
    file="$2"
    expect_ok="$3"  # "ok" or "fail"
    TOTAL=$((TOTAL + 1))
    result=$($CSPFE "$file" 2>&1)
    if echo "$result" | grep -q "syntax ok"; then
        got="ok"
    else
        got="fail"
    fi
    if [ "$got" = "$expect_ok" ]; then
        printf "  PASS  %s\n" "$name"
        PASS=$((PASS + 1))
    else
        printf "  FAIL  %s  (expected %s, got: %s)\n" "$name" "$expect_ok" "$result"
        FAIL=$((FAIL + 1))
    fi
}

# Create temp dir for test files
TDIR=$(mktemp -d)
trap "rm -rf $TDIR" EXIT

# --- Basic statements ---

cat > "$TDIR/skip.csp" << 'EOF'
skip
EOF

cat > "$TDIR/skip_semi.csp" << 'EOF'
skip;
EOF

cat > "$TDIR/bare_ident.csp" << 'EOF'
x
EOF

cat > "$TDIR/assign.csp" << 'EOF'
x = 1
EOF

cat > "$TDIR/hello.csp" << 'EOF'
print("hello, world!")
EOF

cat > "$TDIR/error_kw.csp" << 'EOF'
error
EOF

# --- Declarations ---

cat > "$TDIR/decl_types.csp" << 'EOF'
int x;
int(8) y;
sint(16) z;
bool flag;
boolean done;
string s
EOF

cat > "$TDIR/decl_init.csp" << 'EOF'
int x = 42;
int y = 0xff;
int z = 0b1010;
int w = 4_abc
EOF

cat > "$TDIR/decl_direction.csp" << 'EOF'
function foo(int +x; int -y; int +-z) =
  ( skip );
skip
EOF

# --- Compound assignments ---

cat > "$TDIR/compound.csp" << 'EOF'
int x;
x += 1;
x -= 2;
x *= 3;
x /= 4;
x %= 5;
x &= 0xff;
x |= 0x100;
x ^= 0xaa;
x <<= 2;
x >>= 1
EOF

# --- Inc/Dec ---

cat > "$TDIR/incdec.csp" << 'EOF'
int x;
x++;
x--
EOF

# --- Channel ops ---

cat > "$TDIR/channel.csp" << 'EOF'
int x;
R!x;
L?x;
R!(x + 1)
EOF

cat > "$TDIR/bool_assign.csp" << 'EOF'
bool flag;
flag+;
flag-
EOF

# --- Expressions ---

cat > "$TDIR/expr.csp" << 'EOF'
int x;
x = 1 + 2 * 3;
x = (1 + 2) * 3;
x = ~x;
x = -x;
x = 2 ** 8;
x = a || b && c;
x = a | b ^ c & d;
x = a == b;
x = a != b;
x = a < b;
x = a > b;
x = a <= b;
x = a >= b;
x = a << 2;
x = a >> 1
EOF

# --- Lvalue suffixes ---

cat > "$TDIR/lvalue.csp" << 'EOF'
int x;
x = a[0];
x = a[1, 2];
x = a{7};
x = a{7:0};
x = f();
x = f(1);
x = f(1, 2);
x = a.field;
x = a.0;
x = a::member
EOF

# --- Selection (guards) ---

cat > "$TDIR/det_guard.csp" << 'EOF'
[ true -> skip
[] false -> skip
]
EOF

cat > "$TDIR/det_guard_else.csp" << 'EOF'
[ x > 0 -> x--
[] else -> skip
]
EOF

cat > "$TDIR/nondet_guard.csp" << 'EOF'
[
 #L[0] -> L[0]?x
 :
 #L[1] -> L[1]?x
]
EOF

cat > "$TDIR/wait_expr.csp" << 'EOF'
[ done ]
EOF

# --- Repetition ---

cat > "$TDIR/rep_guard.csp" << 'EOF'
*[ x != 0 ->
   x--
]
EOF

cat > "$TDIR/rep_infinite.csp" << 'EOF'
*[ L?x; R!x ]
EOF

# --- Loop statements ---

cat > "$TDIR/loop_angle.csp" << 'EOF'
int x;
< i : 0..7 : x += i >
EOF

cat > "$TDIR/loop_semi.csp" << 'EOF'
int x;
<; i : 0..7 : x += i >
EOF

cat > "$TDIR/loop_comma.csp" << 'EOF'
int x;
<, i : 0..7 : R[i]!x >
EOF

# --- Hash (probe/peek) ---

cat > "$TDIR/hash_select.csp" << 'EOF'
#[ done -> R!result ]
EOF

cat > "$TDIR/hash_probe.csp" << 'EOF'
int x;
x = #L
EOF

# --- Functions ---

cat > "$TDIR/func_typed.csp" << 'EOF'
function even(int -n) : bool =
  ( even = ((n & 1) == 0) );

function odd(int -n) : bool =
  ( odd = ~even(n) );

skip
EOF

cat > "$TDIR/func_untyped.csp" << 'EOF'
function doWork(int -x; int -y) =
  ( print(x + y) );

doWork(1, 2)
EOF

# --- Structures ---

cat > "$TDIR/struct.csp" << 'EOF'
structure point =
  (
   int x;
   int y;
   );

skip
EOF

# --- Complex: P0/P1 from simple.cast ---

cat > "$TDIR/p0.csp" << 'EOF'
int x;
*[ R!x; x++ ]
EOF

cat > "$TDIR/p1.csp" << 'EOF'
*[ L?x ; print(x) ]
EOF

# --- Complex: Collatz worker (simplified) ---

cat > "$TDIR/worker.csp" << 'EOF'
function even(int -n) : bool =
  ( even = ((n & 1) == 0) );

function odd(int -n) : bool =
  ( odd = ~even(n) );

bool assert_inrange=false;

int i;
int steps  = 0;
int maxlen = 0;
int id;

STRT?id;
print ("id = " + id);

*[
  int idx = i * 4 + id;
  int num = 2 * idx + 1;
  int len = 0;
  int snum = num;
  int newval;

  *[ num != 1 ->
     [  odd(num)  -> newval = 3 * num + 1
     [] even(num) -> newval = num / 2
     ];
     num = newval;

     #[ assert_inrange -> assert(num == newval, "overflow!") ];

     len++
   ]
  ;
  assert(num == 1);
  steps += len;

  [  len > maxlen ->
     maxlen = len;
     steps = 0
  [] else -> skip
  ];

  i++
]
EOF

# --- Complex: SMERGE with nondet guards ---

cat > "$TDIR/smerge.csp" << 'EOF'
int x;

*[
  int y = x;
  [
   #L[0] -> L[0]?x
   :
   #L[1] -> L[1]?x
   ];
  R!x
]
EOF

# --- Complex: Manager with hash-selection ---

cat > "$TDIR/manager.csp" << 'EOF'
int ops;
int bigiter=0;
int outstanding;
int lastprint = 0;
int printstep = 10;

int start = walltime();

*[ STATUS?x;

   bool doprint = false;

   #[ tok ->
     outstanding--;
     #[ outstanding == 0 ->
        print("phase complete");
        outstanding = 4 ; bigiter++
      ];
   ];

   ops += 1;

   int now       = walltime();
   int runtime   = now - start;
   int runtime_s = runtime / 1000000000 + 1;

   doprint |= (now > (lastprint + printstep * 1000000000));

   #[ doprint ->
      print("total steps = " + ops);
      lastprint = now
   ]

 ]
EOF

# --- Startsplit with exponent ---

cat > "$TDIR/startsplit.csp" << 'EOF'
*[ L?i; R[0]!i, R[1]!(i + 2**level) ]
EOF

# --- Parallel composition ---

cat > "$TDIR/parallel.csp" << 'EOF'
A!1, B!2, C!3
EOF

# --- Sequential with trailing semicolons ---

cat > "$TDIR/trailing.csp" << 'EOF'
x = 1;
y = 2;
z = 3;
EOF

# --- Nested parens ---

cat > "$TDIR/nested_paren.csp" << 'EOF'
(x = 1; y = 2)
EOF

# ================================================================
# Tests from CSP Reference Manual (csp.tex)
# ================================================================

# --- Euclid's algorithm (Chapter 3, Example Programs) ---

cat > "$TDIR/euclid.csp" << 'EOF'
x = A;
y = B;

*[  x > y -> x = x - y
 [] x < y -> y = y - x
 ];

print ("gcd(" + A + "," + B + ") = " + x)
EOF

# --- Four-phase handshaking (Chapter 3, nodes example) ---
# Uses wait expressions [cond], boolean assign shorthands, resetNodes

cat > "$TDIR/fourphase_s.csp" << 'EOF'
function resetNodes() = (ro-);

*[ [ri]; ro+; [~ri]; ro- ]
EOF

cat > "$TDIR/fourphase_t.csp" << 'EOF'
function resetNodes() = (lo-);
*[ lo+; [li]; print(li); lo-; [~li]; print(li) ]
EOF

# Diagnostic: break four-phase T into smaller pieces
cat > "$TDIR/fourphase_t1.csp" << 'EOF'
*[ lo+ ]
EOF

cat > "$TDIR/fourphase_t2.csp" << 'EOF'
*[ lo+; [li] ]
EOF

cat > "$TDIR/fourphase_t3.csp" << 'EOF'
*[ lo+; [li]; print(li) ]
EOF

cat > "$TDIR/fourphase_t4.csp" << 'EOF'
*[ lo+; [li]; print(li); lo- ]
EOF

cat > "$TDIR/fourphase_t5.csp" << 'EOF'
*[ lo+; [li]; print(li); lo-; [~li] ]
EOF

cat > "$TDIR/fourphase_t6.csp" << 'EOF'
*[ lo+; [li]; print(li); lo-; [~li]; print(li) ]
EOF

# --- Dijkstra's mutual exclusion (Chapter 3, complex example) ---

cat > "$TDIR/dijkstra.csp" << 'EOF'
function resetNodes() = (b[i]+, c[i]+, k+, busy-);

bool Li0 = true;
bool Li1 = false;

*[ Li0 -> b[i] = false;
   Li0-, Li1+

 [] Li1 ->
   wait(random(4));
   print ("Li1 k=" + k);

  [ b2i(k) != i ->
    c[i] = true;
    #[ b[b2i(k)] -> k = i && i ]
  [] else ->
     c[i] = false;
     bool fail = false;
    <;j:N: #[ j != i & ~c[j] -> fail = true]> ;

    #[ ~fail ->
       print ("enter critical section " + i);
       assert(~busy);
       busy+;
       wait(random(4));
       busy-;
       print ("leave critical section " + i);
       c[i] = true; b[i] = true;
       print ("enter non-critical section " + i);
       wait(random(4));
       print ("leave non-critical section " + i);
       Li0+, Li1-
     ]
    ]
  ]
EOF

# --- String concatenation (sec 1.4.6, sec 2.7.1) ---

cat > "$TDIR/string_concat.csp" << 'EOF'
string s;
s = "The answer is " + (4 * 10 + 2);
s = "hello" + " " + "world";
s = "x = " + x;
print("result: " + s)
EOF

# --- Array declarations (sec 2.1.5) ---

cat > "$TDIR/array_decl.csp" << 'EOF'
int a[0..2];
int b[3];
int c[0..2, 0..5];
int d[3][6];
int e[0..3, 0..3, 0..3];
int f[4][4][4];
skip
EOF

# --- Array declarations in functions ---
# Note: data[] with empty brackets uses T_BOX token, not '[' ']'.
# Grammar requires range_list inside brackets. Use explicit dim for now.

cat > "$TDIR/array_func.csp" << 'EOF'
function sumArray(int -n; int -data[0..9]) : int =
  (
   int total = 0;
   <; i : n : total += data[i] >;
   sumArray = total
  );

int x[10];
y = sumArray(10, x)
EOF

# --- Structure field access via :: (sec 2.5.3) ---

cat > "$TDIR/struct_access.csp" << 'EOF'
structure point =
  (
   int x;
   int y;
   );

structure line =
  (
   int start;
   int finish;
   );

skip
EOF

# Note: struct_type variables can't be declared yet (Phase 1 limitation),
# but :: access on bare identifiers works.

cat > "$TDIR/struct_member.csp" << 'EOF'
s::field = 42;
s::nested::deep = 1;
x = s::a + s::b;
s::arr[0] = s::arr[1]
EOF

# --- Bit access (sec 2.5.2) ---

cat > "$TDIR/bit_access.csp" << 'EOF'
int x = 0xff;
int y;
y = x{7:0};
y = x{3};
y = x{15:8};
x{7:0} = 0xab;
x{0} = 1
EOF

# --- Receive expression (sec 2.7.2) ---

cat > "$TDIR/recv_expr.csp" << 'EOF'
v = IPort?;
C!(A? * B?);
x = (L? + R?) / 2
EOF

# --- Peek expression (sec 2.7.3) ---

cat > "$TDIR/peek_expr.csp" << 'EOF'
x = #IPort?;
y = #A? + #B?
EOF

# --- Pack/unpack (sec 2.8.1, 2.8.2) ---

cat > "$TDIR/pack_unpack.csp" << 'EOF'
structure s =
  (
   int(8) a[4];
   int(8) b;
   );

int p = pack(ss);
unpack(tt, p);
print("packed = " + hex(p))
EOF

# --- Simple if #[...] (sec 2.4.3.2) ---

cat > "$TDIR/simple_if.csp" << 'EOF'
#[ x > 0 -> print("positive") ];
#[ x > 0 -> print("pos")
[] x < 0 -> print("neg")
];
#[ flag -> x = 1 ]
EOF

# --- Composition precedence (sec 2.4.5, 2.4.6) ---

cat > "$TDIR/comp_prec.csp" << 'EOF'
S0; S1, S2; S3
EOF

cat > "$TDIR/comp_paren.csp" << 'EOF'
(S0; S1), (S2; S3)
EOF

cat > "$TDIR/comp_complex.csp" << 'EOF'
(a = 1; b = 2; c = 3), (d = 4; e = 5), f = 6;
g = 7
EOF

# --- Comments (sec 2.2) ---

cat > "$TDIR/comments.csp" << 'EOF'
/* This is a block comment */
x = 1; /* inline comment */
// This is a line comment
y = 2; // trailing comment
/* Multi-line
   comment */
z = 3
EOF

# --- Empty string and escape sequences (sec 2.6.1.3) ---

cat > "$TDIR/string_escapes.csp" << 'EOF'
string s;
s = "";
s = "hello\nworld";
s = "tab\there";
s = "quote\"inside";
s = "back\\slash"
EOF

# --- Multiple declarators same type (sec 2.3) ---

cat > "$TDIR/multi_decl.csp" << 'EOF'
int x, y, z;
int a = 1, b = 2, c = 3;
bool p, q = true;
string name, label
EOF

# --- Const declarations (sec 2.1.1 context) ---

cat > "$TDIR/const_decl.csp" << 'EOF'
const int WIDTH = 32;
const int HEIGHT = 64;
const bool DEBUG = true;
const string MSG = "hello";
skip
EOF

# --- Nested function calls ---

cat > "$TDIR/nested_calls.csp" << 'EOF'
x = f(g(x), h(y, z));
x = max(min(a, b), min(c, d));
print("val = " + abs(x - y))
EOF

# --- Loop expressions (sec 2.6.3) ---

cat > "$TDIR/loop_expr.csp" << 'EOF'
int x;
x = <+ i : 0..7 : a[i] >;
x = <* i : 1..5 : i >;
x = <& i : 0..3 : mask[i] >;
x = <| i : 0..3 : flag[i] >;
x = <^ i : 0..7 : data[i] >
EOF

# --- Function with value-result (sec 2.3, example from manual) ---

cat > "$TDIR/func_value_result.csp" << 'EOF'
function F(int +x = 12, -y) : int = ( x = x * y; F = x + y );
q = 2;
z = F(q, 3)
EOF

# --- Function with no params ---

cat > "$TDIR/func_no_params.csp" << 'EOF'
function doNothing() = ( skip );
function getZero() : int = ( getZero = 0 );
doNothing();
x = getZero()
EOF

# --- Multiple functions with various signatures ---
# Note: 3 function decls then body. Previously failed—test each combo.

cat > "$TDIR/func_multi.csp" << 'EOF'
function add(int -a, -b) : int = ( add = a + b );
function swap(int +-a, +-b) = ( int t = a; a = b; b = t );

int p = 1, q = 2;
r = add(p, q);
swap(p, q)
EOF

cat > "$TDIR/func_three.csp" << 'EOF'
function f1() = ( skip );
function f2() = ( skip );
function f3() = ( skip );

f1(); f2(); f3()
EOF

# --- resetNodes function (sec 2.8.7) ---

cat > "$TDIR/reset_nodes.csp" << 'EOF'
function resetNodes() = (ro-, lo-);

*[ skip ]
EOF

# --- Wait shorthand [G] (sec 2.4.3.1) ---

cat > "$TDIR/wait_shorthand.csp" << 'EOF'
[done];
[x > 0];
[~busy];
[#A || #B]
EOF

# --- Guard loop (boxloop) inside deterministic guards ---

cat > "$TDIR/boxloop_guard.csp" << 'EOF'
[
  <[] i : 0..3 : #L[i] -> L[i]?x >
]
EOF

# --- Nondet guard loop (clloop) ---

cat > "$TDIR/clloop_guard.csp" << 'EOF'
[
  <: i : 0..3 : #L[i] -> L[i]?x >
]
EOF

# --- Repetition with else ---

cat > "$TDIR/rep_else.csp" << 'EOF'
*[ x > 0 -> x--
[] else -> skip
]
EOF

# --- Chained struct access ---

cat > "$TDIR/chained_struct.csp" << 'EOF'
s::tok = true;
s::id = id;
s::l::length = len;
s::l::num = num;
s::ops = steps;
x = s::l::length + s::l::num
EOF

# --- Hex with underscores (sec 2.6.1.1) ---

cat > "$TDIR/hex_underscore.csp" << 'EOF'
int x;
x = 0x_ff;
x = 0xff_00;
x = 0b_1010;
x = 0b1010_0101;
x = 1_000_000
EOF

# --- Radix literal (sec 2.6.1.1) ---

cat > "$TDIR/radix_literal.csp" << 'EOF'
int x;
x = 16_ff;
x = 2_1010;
x = 8_77;
x = 21_20
EOF

# --- Right-associative exponentiation (sec 2.6.2) ---

cat > "$TDIR/exp_assoc.csp" << 'EOF'
x = 2 ** 3 ** 2;
x = (2 ** 3) ** 2;
x = 2 ** (3 ** 2)
EOF

# --- Complex expression precedence ---

cat > "$TDIR/expr_prec.csp" << 'EOF'
x = a + b * c ** 2;
x = (a + b) * c;
x = ~a & b | c ^ d;
x = a << 2 + 1;
x = a == b && c != d || e < f;
x = -x ** 2
EOF

# --- Multiple hash-ifs nested ---

cat > "$TDIR/nested_hash.csp" << 'EOF'
#[ cond1 ->
   x = 1;
   #[ cond2 ->
      y = 2;
      #[ cond3 -> z = 3 ]
   ]
]
EOF

# --- Send without value (passive sync) ---

cat > "$TDIR/send_empty.csp" << 'EOF'
R!;
L?
EOF

# --- Boolean expressions in guards ---

cat > "$TDIR/bool_guard.csp" << 'EOF'
[ #A && #B -> A?a; B?b
[] #C -> C?c
];
[ ~done && count > 0 -> count-- ]
EOF

# --- Parallel bool assignment in function body ---

cat > "$TDIR/parallel_bool.csp" << 'EOF'
bool a, b, c;
a+, b-, c+;
a-, b+, c-
EOF

# --- Structure with initializers (sec 2.1.4) ---

cat > "$TDIR/struct_init.csp" << 'EOF'
structure config =
  (
   int(8) width = 32;
   int(8) height = 24;
   bool enabled = true;
   );

skip
EOF

# --- Structure with arrays (sec 2.8.1 pack example) ---

cat > "$TDIR/struct_array.csp" << 'EOF'
structure packet =
  (
   int(8) data[4];
   int(8) tag;
   );

skip
EOF

# --- Declaration inside guarded command scope ---

cat > "$TDIR/guard_scope.csp" << 'EOF'
*[ #L ->
   int x;
   L?x;
   int y = x * 2;
   R!y
]
EOF

# --- Complex lvalue chains ---

cat > "$TDIR/complex_lvalue.csp" << 'EOF'
a[i]::field = 1;
a::b[0] = 2;
f(x)::result = 3;
a[0][1]::data{7:0} = 0xff
EOF

# --- Collatz common (full from manual, ch 3) ---

cat > "$TDIR/collatz_common.csp" << 'EOF'
structure longest_so_far =
  (
   int num;
   int length;
   );

structure status =
  (
   bool     tok;
   sint(61) id;
   int(128) ops;
   );

function even(int -n) : bool = ( even = ((n & 1) == 0) );

function odd(int -n) : bool =  ( odd = ~even(n) );

skip
EOF

# --- SMERGE from manual (ch 3, nondet guards with probes) ---

cat > "$TDIR/smerge_manual.csp" << 'EOF'
function recv(int -which) =
  (
   L[which]?xs
  );

function checksend() =
  (
   #[ flag ->
      R!result; flag = false
    ]
  );

int xs;
bool flag = false;
int result;

*[
  [#L[0] -> recv(0)
  :#L[1] -> recv(1)
  ];
  checksend()
 ]
EOF

# --- Loop statement with complex body ---

cat > "$TDIR/loop_complex.csp" << 'EOF'
<; i : 0..3 :
  int x;
  A[i]?x;
  x = x * 2;
  B[i]!x
>
EOF

# --- Parallel loop ---

cat > "$TDIR/loop_parallel.csp" << 'EOF'
<, i : 0..7 : R[i]!data[i] >;
<, i : 0..3 :
  A[i]?x[i],
  B[i]!y[i]
>
EOF

# --- Nested loops ---

cat > "$TDIR/nested_loops.csp" << 'EOF'
<; i : 0..3 :
  <; j : 0..3 :
    a[i][j] = i * 4 + j
  >
>
EOF

# --- Multiple structures ---

cat > "$TDIR/multi_struct.csp" << 'EOF'
structure inner =
  (
   int(8) x;
   int(8) y;
   );

structure outer =
  (
   int(16) header;
   int(32) payload;
   bool valid;
   );

skip
EOF

# --- Function returning string ---

cat > "$TDIR/func_string.csp" << 'EOF'
function fmt(int -x; int -y) : string =
  ( fmt = "(" + x + "," + y + ")" );

print(fmt(3, 4))
EOF

# --- Assert (sec 2.8.3) ---

cat > "$TDIR/assert_test.csp" << 'EOF'
assert(x == 1);
assert(x > 0, "x must be positive");
assert(true)
EOF

# --- Min/max/abs/log2/choose (sec 2.8.8) ---

cat > "$TDIR/builtins.csp" << 'EOF'
x = min(a, b);
x = max(a, b);
x = abs(x - y);
x = log2(256);
x = log2(N);
x = choose(flag, a, b);
x = b2i(done)
EOF

# --- Timing functions (sec 2.8.6) ---

cat > "$TDIR/timing.csp" << 'EOF'
int start = walltime();
int t = simtime();
int now = time();
wait(1000);
int elapsed = walltime() - start
EOF

# --- Random (sec 2.8.5) ---

cat > "$TDIR/random_test.csp" << 'EOF'
int x;
x = random(8);
x = random(32);
wait(random(4))
EOF

# --- Deep nesting ---

cat > "$TDIR/deep_nesting.csp" << 'EOF'
*[
  [
    #A -> A?x;
    [  x > 0 ->
       *[ x > 0 ->
          R!x;
          x--
        ];
        print("done sending")
    [] else -> skip
    ]
  :
    #B -> B?y;
    #[ y == 0 -> print("zero") ];
    R!y
  ]
]
EOF

# --- Billion constant (from collatz manager) ---

cat > "$TDIR/big_const.csp" << 'EOF'
int Billion = 1000 ** 3;
int x = 0x440000000000000068000000000000007;
x++;
x--
EOF

# --- Multiple send/receive in parallel ---

cat > "$TDIR/parallel_comm.csp" << 'EOF'
R[0]!data[0], R[1]!data[1], R[2]!data[2];
L[0]?x[0], L[1]?x[1]
EOF

# --- readHexInts (sec 2.8.7) ---

cat > "$TDIR/file_io.csp" << 'EOF'
int data[1024];
int count = readHexInts("input.hex", 1024, data);
print("read " + count + " values")
EOF

# --- Complex guard with loop expressions ---

cat > "$TDIR/guard_loop_expr.csp" << 'EOF'
[ (<& i : 0..3 : #L[i] >) -> skip
[] else -> error
]
EOF

# --- Operator |= in statement context ---

cat > "$TDIR/orassign_stmt.csp" << 'EOF'
bool doprint = false;
doprint |= (now > threshold);
doprint |= flag
EOF

# --- Sint declarations ---

cat > "$TDIR/sint_decl.csp" << 'EOF'
sint(8) x;
sint(16) y = -1;
sint(32) z;
x = -128;
y = 127;
z = x + y
EOF

# --- Direction combinations in function params ---

cat > "$TDIR/direction_combos.csp" << 'EOF'
function test(int -a; int +b; int +-c; int -+d) =
  (
   c = a + b;
   d = a - b
  );

int x = 1, y, z, w;
test(x, y, z, w)
EOF

# --- Empty function body ---

cat > "$TDIR/func_empty_body.csp" << 'EOF'
function noop() = ( skip );
noop()
EOF

# --- Error cases (should fail) ---

cat > "$TDIR/bad_syntax.csp" << 'EOF'
x = ;
EOF

cat > "$TDIR/bad_unclosed.csp" << 'EOF'
[ true -> skip
EOF

# Note: x = 1;; is actually valid: sequential_statement ';' (trail),
# then a new sequential_part starts. The second ; is trail again.
# CSP allows trailing semicolons.
cat > "$TDIR/double_semi.csp" << 'EOF'
x = 1;;y = 2
EOF

cat > "$TDIR/bad_missing_arrow.csp" << 'EOF'
[ true skip ]
EOF

cat > "$TDIR/bad_empty_prog.csp" << 'EOF'
EOF

cat > "$TDIR/bad_unmatched_paren.csp" << 'EOF'
(x = 1
EOF

cat > "$TDIR/bad_operator.csp" << 'EOF'
x = 1 +* 2
EOF

# ========================================
echo "CSP Parser Test Suite"
echo "========================================"

echo ""
echo "--- Basic statements ---"
run_test "bare skip"         "$TDIR/skip.csp"          ok
run_test "skip with semi"    "$TDIR/skip_semi.csp"     ok
run_test "bare identifier"   "$TDIR/bare_ident.csp"    ok
run_test "assignment"        "$TDIR/assign.csp"        ok
run_test "function call"     "$TDIR/hello.csp"         ok
run_test "error keyword"     "$TDIR/error_kw.csp"      ok

echo ""
echo "--- Declarations ---"
run_test "type declarations" "$TDIR/decl_types.csp"    ok
run_test "initializers"      "$TDIR/decl_init.csp"     ok
run_test "directions"        "$TDIR/decl_direction.csp" ok
run_test "multiple declarators" "$TDIR/multi_decl.csp" ok
run_test "const declarations" "$TDIR/const_decl.csp"   ok
run_test "sint declarations" "$TDIR/sint_decl.csp"     ok
run_test "array declarations" "$TDIR/array_decl.csp"   ok

echo ""
echo "--- Compound assignments ---"
run_test "compound assigns"  "$TDIR/compound.csp"      ok
run_test "or-assign stmt"    "$TDIR/orassign_stmt.csp" ok

echo ""
echo "--- Inc/Dec ---"
run_test "inc/dec"           "$TDIR/incdec.csp"        ok

echo ""
echo "--- Channel ops ---"
run_test "send/receive"      "$TDIR/channel.csp"       ok
run_test "bool assign"       "$TDIR/bool_assign.csp"   ok
run_test "send empty"        "$TDIR/send_empty.csp"    ok
run_test "parallel comm"     "$TDIR/parallel_comm.csp" ok

echo ""
echo "--- Expressions ---"
run_test "expressions"       "$TDIR/expr.csp"          ok
run_test "expr precedence"   "$TDIR/expr_prec.csp"     ok
run_test "exp associativity" "$TDIR/exp_assoc.csp"     ok
run_test "nested calls"      "$TDIR/nested_calls.csp"  ok

echo ""
echo "--- Lvalue suffixes ---"
run_test "lvalue suffixes"   "$TDIR/lvalue.csp"        ok
run_test "bit access"        "$TDIR/bit_access.csp"    ok
run_test "complex lvalue"    "$TDIR/complex_lvalue.csp" ok
run_test "struct member ::"  "$TDIR/struct_member.csp" ok
run_test "chained struct"    "$TDIR/chained_struct.csp" ok

echo ""
echo "--- Receive/Peek expressions ---"
run_test "receive expr"      "$TDIR/recv_expr.csp"     ok
run_test "peek expr"         "$TDIR/peek_expr.csp"     ok

echo ""
echo "--- Selection ---"
run_test "det guard"         "$TDIR/det_guard.csp"     ok
run_test "det guard else"    "$TDIR/det_guard_else.csp" ok
run_test "nondet guard"      "$TDIR/nondet_guard.csp"  ok
run_test "wait expression"   "$TDIR/wait_expr.csp"     ok
run_test "wait shorthand"    "$TDIR/wait_shorthand.csp" ok
run_test "bool guard exprs"  "$TDIR/bool_guard.csp"    ok
run_test "simple if #[]"     "$TDIR/simple_if.csp"     ok
run_test "boxloop in guard"  "$TDIR/boxloop_guard.csp" ok
run_test "clloop in guard"   "$TDIR/clloop_guard.csp"  ok
run_test "guard loop expr"   "$TDIR/guard_loop_expr.csp" ok

echo ""
echo "--- Repetition ---"
run_test "rep guard"         "$TDIR/rep_guard.csp"     ok
run_test "rep infinite"      "$TDIR/rep_infinite.csp"  ok
run_test "rep with else"     "$TDIR/rep_else.csp"      ok

echo ""
echo "--- Loop ---"
run_test "loop angle"        "$TDIR/loop_angle.csp"    ok
run_test "loop semi"         "$TDIR/loop_semi.csp"     ok
run_test "loop comma"        "$TDIR/loop_comma.csp"    ok
run_test "loop complex body" "$TDIR/loop_complex.csp"  ok
run_test "loop parallel"     "$TDIR/loop_parallel.csp" ok
run_test "nested loops"      "$TDIR/nested_loops.csp"  ok

echo ""
echo "--- Loop expressions ---"
run_test "loop expressions"  "$TDIR/loop_expr.csp"     ok

echo ""
echo "--- Hash ---"
run_test "hash select"       "$TDIR/hash_select.csp"   ok
run_test "hash probe"        "$TDIR/hash_probe.csp"    ok
run_test "nested hash-ifs"   "$TDIR/nested_hash.csp"   ok

echo ""
echo "--- Functions ---"
run_test "typed functions"   "$TDIR/func_typed.csp"    ok
run_test "untyped function"  "$TDIR/func_untyped.csp"  ok
run_test "value-result func" "$TDIR/func_value_result.csp" ok
run_test "no-param funcs"    "$TDIR/func_no_params.csp" ok
run_test "multi signatures"  "$TDIR/func_multi.csp"    ok
run_test "three functions"   "$TDIR/func_three.csp"    ok
run_test "func string return" "$TDIR/func_string.csp"  ok
run_test "empty body func"   "$TDIR/func_empty_body.csp" ok
run_test "resetNodes"        "$TDIR/reset_nodes.csp"   ok
run_test "array func param"  "$TDIR/array_func.csp"    ok
run_test "direction combos"  "$TDIR/direction_combos.csp" ok

echo ""
echo "--- Structures ---"
run_test "structure decl"    "$TDIR/struct.csp"        ok
run_test "struct access"     "$TDIR/struct_access.csp" ok
run_test "struct with init"  "$TDIR/struct_init.csp"   ok
run_test "struct with array" "$TDIR/struct_array.csp"  ok
run_test "multiple structs"  "$TDIR/multi_struct.csp"  ok
run_test "pack/unpack"       "$TDIR/pack_unpack.csp"   ok

echo ""
echo "--- Strings ---"
run_test "string concat"     "$TDIR/string_concat.csp" ok
run_test "string escapes"    "$TDIR/string_escapes.csp" ok

echo ""
echo "--- Literals ---"
run_test "hex underscore"    "$TDIR/hex_underscore.csp" ok
run_test "radix literals"    "$TDIR/radix_literal.csp" ok
run_test "big constants"     "$TDIR/big_const.csp"     ok

echo ""
echo "--- Comments ---"
run_test "comments"          "$TDIR/comments.csp"      ok

echo ""
echo "--- Built-in functions ---"
run_test "assert"            "$TDIR/assert_test.csp"   ok
run_test "min/max/abs/etc"   "$TDIR/builtins.csp"      ok
run_test "timing functions"  "$TDIR/timing.csp"        ok
run_test "random"            "$TDIR/random_test.csp"   ok
run_test "file I/O"          "$TDIR/file_io.csp"       ok

echo ""
echo "--- Complex programs ---"
run_test "P0 (send loop)"   "$TDIR/p0.csp"            ok
run_test "P1 (recv loop)"   "$TDIR/p1.csp"            ok
run_test "Euclid's algo"    "$TDIR/euclid.csp"        ok
run_test "worker (collatz)"  "$TDIR/worker.csp"        ok
run_test "smerge (nondet)"   "$TDIR/smerge.csp"        ok
run_test "manager (hash)"    "$TDIR/manager.csp"       ok
run_test "startsplit (exp)"  "$TDIR/startsplit.csp"    ok
run_test "four-phase S"      "$TDIR/fourphase_s.csp"   ok
run_test "four-phase T"      "$TDIR/fourphase_t.csp"   ok
run_test "4ph-t1 lo+"       "$TDIR/fourphase_t1.csp"  ok
run_test "4ph-t2 +wait"     "$TDIR/fourphase_t2.csp"  ok
run_test "4ph-t3 +print"    "$TDIR/fourphase_t3.csp"  ok
run_test "4ph-t4 +lo-"      "$TDIR/fourphase_t4.csp"  ok
run_test "4ph-t5 +wait2"    "$TDIR/fourphase_t5.csp"  ok
run_test "4ph-t6 full"      "$TDIR/fourphase_t6.csp"  ok
run_test "Dijkstra mutex"    "$TDIR/dijkstra.csp"      ok
run_test "smerge (manual)"   "$TDIR/smerge_manual.csp" ok
run_test "collatz common"    "$TDIR/collatz_common.csp" ok

echo ""
echo "--- Composition ---"
run_test "parallel"          "$TDIR/parallel.csp"      ok
run_test "trailing semi"     "$TDIR/trailing.csp"      ok
run_test "nested parens"     "$TDIR/nested_paren.csp"  ok
run_test "comp precedence"   "$TDIR/comp_prec.csp"     ok
run_test "comp with parens"  "$TDIR/comp_paren.csp"    ok
run_test "comp complex"      "$TDIR/comp_complex.csp"  ok
run_test "parallel bool"     "$TDIR/parallel_bool.csp" ok

echo ""
echo "--- Scope ---"
run_test "guard scope decl"  "$TDIR/guard_scope.csp"   ok
run_test "deep nesting"      "$TDIR/deep_nesting.csp"  ok

echo ""
echo "--- Error cases (expect fail) ---"
run_test "bad syntax"        "$TDIR/bad_syntax.csp"    fail
run_test "unclosed bracket"  "$TDIR/bad_unclosed.csp"  fail
run_test "double semicolon"  "$TDIR/double_semi.csp"   ok
run_test "missing arrow"     "$TDIR/bad_missing_arrow.csp" fail
run_test "empty program"     "$TDIR/bad_empty_prog.csp" ok
run_test "unmatched paren"   "$TDIR/bad_unmatched_paren.csp" fail
run_test "bad operator"      "$TDIR/bad_operator.csp"  fail

echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
