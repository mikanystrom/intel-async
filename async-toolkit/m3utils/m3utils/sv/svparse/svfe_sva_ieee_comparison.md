# svfe SVA Grammar vs IEEE 1800-2017 Annex A

Systematic comparison of the svfe parser's SVA grammar against the formal
grammar in IEEE Std 1800-2017, Annex A, Section A.2.10 (Assertion
declarations), pages 1151-1154.

## Methodology

The IEEE grammar defines SVA through several interconnected nonterminals:
`property_spec`, `property_expr`, `sequence_expr`, `property_declaration`,
`sequence_declaration`, and supporting productions for repetition, delay,
and match items.  The svfe grammar implements these as a precedence tower
of nonterminals descending from `property_expr` through `seq_base_expr`,
with precedence/associativity declarations resolving ambiguities that the
IEEE grammar leaves implicit.

## Coverage: What We Implement Correctly

### Property-level operators

| IEEE production | svfe nonterminal | Alternatives |
|---|---|---|
| `[clocking_event] [disable iff (...)] property_expr` | `property_expr` | `bare`, `clocked`, `clocked_disable` |
| `not property_expr` | `prop_not_expr` | `not` |
| `property_expr or property_expr` | `prop_or_expr` | `or` |
| `property_expr and property_expr` | `prop_and_expr` | `and` |
| `property_expr iff property_expr` | `prop_iff_expr` | `iff` |
| `property_expr implies property_expr` | `prop_implies_kw_expr` | `implies_kw` |
| `property_expr until property_expr` | `prop_until_expr` | `until` |
| `property_expr s_until property_expr` | `prop_until_expr` | `s_until` |
| `property_expr until_with property_expr` | `prop_until_expr` | `until_with` |
| `property_expr s_until_with property_expr` | `prop_until_expr` | `s_until_with` |
| `(property_expr)` | `prop_unary_expr` | `paren` |

### Implication and followed-by

| IEEE production | svfe nonterminal | Alternatives |
|---|---|---|
| `sequence_expr \|-> property_expr` | `prop_impl_expr` | `implies` |
| `sequence_expr \|=> property_expr` | `prop_impl_expr` | `nimplies` |
| `sequence_expr #-# property_expr` | `prop_impl_expr` | `fimplies` |
| `sequence_expr #=# property_expr` | `prop_impl_expr` | `fnimplies` |

### Temporal operators (unary prefix)

| IEEE production | svfe nonterminal | Alternatives |
|---|---|---|
| `nexttime property_expr` | `prop_temporal_expr` | `nexttime` |
| `nexttime [N] property_expr` | `prop_temporal_expr` | `nexttime_n` |
| `s_nexttime property_expr` | `prop_temporal_expr` | `s_nexttime` |
| `s_nexttime [N] property_expr` | `prop_temporal_expr` | `s_nexttime_n` |
| `always property_expr` | `prop_temporal_expr` | `always_prop` |
| `always [lo:hi] property_expr` | `prop_temporal_expr` | `always_range` |
| `s_always [lo:hi] property_expr` | `prop_temporal_expr` | `s_always_range` |
| `eventually [lo:hi] property_expr` | `prop_temporal_expr` | `eventually_range` |
| `s_eventually property_expr` | `prop_temporal_expr` | `s_eventually_prop` |
| `s_eventually [lo:hi] property_expr` | `prop_temporal_expr` | `s_eventually_range` |

### Abort properties

| IEEE production | svfe nonterminal | Alternatives |
|---|---|---|
| `accept_on (expr) property_expr` | `prop_temporal_expr` | `accept_on` |
| `reject_on (expr) property_expr` | `prop_temporal_expr` | `reject_on` |
| `sync_accept_on (expr) property_expr` | `prop_temporal_expr` | `sync_accept_on` |
| `sync_reject_on (expr) property_expr` | `prop_temporal_expr` | `sync_reject_on` |

### Control flow in properties

| IEEE production | svfe nonterminal | Alternatives |
|---|---|---|
| `if (expr) prop [else prop]` | `prop_temporal_expr` | `if_prop` |
| `case (expr) items endcase` | `prop_temporal_expr` | `case_prop` |

### Sequence wrappers

| IEEE production | svfe nonterminal | Alternatives |
|---|---|---|
| `strong(sequence_expr)` | `prop_unary_expr` | `strong` |
| `weak(sequence_expr)` | `prop_unary_expr` | `weak` |
| `first_match(sequence_expr)` | `prop_unary_expr` | `first_match` |

### Sequence-level operators

| IEEE production | svfe nonterminal | Alternatives |
|---|---|---|
| `sequence_expr and sequence_expr` | `prop_and_expr` | `and` (merged with property and) |
| `sequence_expr intersect sequence_expr` | `prop_and_expr` | `intersect` |
| `sequence_expr or sequence_expr` | `prop_or_expr` | `or` (merged with property or) |
| `expr throughout sequence_expr` | `seq_throughout_expr` | `throughout` |
| `sequence_expr within sequence_expr` | `seq_within_expr` | `within` |

Note: IEEE has separate `sequence_expr and/or` and `property_expr and/or`.
We merge them at the property precedence level.  The output is identical;
the distinction is semantic, not syntactic.

### Cycle delays

| IEEE production | svfe nonterminal | Alternatives |
|---|---|---|
| `seq ##N seq` | `seq_concat_expr` | `delay` |
| `seq ##[lo:hi] seq` | `seq_concat_expr` | `delay_range` |
| `seq ##[*] seq` | `seq_concat_expr` | `delay_star` |
| `seq ##[+] seq` | `seq_concat_expr` | `delay_plus` |
| `##N seq` (initial) | `seq_concat_expr` | `init_delay` |
| `##[lo:hi] seq` (initial) | `seq_concat_expr` | `init_delay_range` |
| `##[*] seq` (initial) | `seq_concat_expr` | `init_delay_star` |
| `##[+] seq` (initial) | `seq_concat_expr` | `init_delay_plus` |

### Boolean abbreviations (repetition)

| IEEE production | svfe nonterminal | Alternatives |
|---|---|---|
| `expr [*N]` | `seq_base_expr` | `rep_star_range` |
| `expr [*lo:hi]` | `seq_base_expr` | `rep_star_range2` |
| `expr [*]` | `seq_base_expr` | `rep_star` |
| `expr [+]` | `seq_base_expr` | `rep_plus` |
| `expr [->N]` | `seq_base_expr` | `rep_goto` |
| `expr [->lo:hi]` | `seq_base_expr` | `rep_goto_range` |
| `expr [=N]` | `seq_base_expr` | `rep_nonconsec` |
| `expr [=lo:hi]` | `seq_base_expr` | `rep_nonconsec_range` |

### Assertion statements

| IEEE production | svfe location | Status |
|---|---|---|
| `assert property (prop_spec) action_block` | `statement`, `module_item` | Implemented |
| `assume property (prop_spec) action_block` | `statement`, `module_item` | Implemented |
| `cover property (prop_spec) stmt_or_null` | `statement`, `module_item` | Implemented |
| `cover sequence (...) stmt_or_null` | `statement`, `module_item` | Implemented |
| `restrict property (prop_spec) ;` | `statement`, `module_item` | Implemented |
| `expect (prop_spec) action_block` | `statement` | Implemented |
| `[label :] concurrent_assertion` | `statement`, `module_item` | Implemented |

### Declarations

| IEEE production | svfe location | Status |
|---|---|---|
| `property ... endproperty` | `module_item` | Implemented |
| `sequence ... endsequence` | `module_item` | Implemented |

## Gaps: What We Do Not Implement

### Gap A: Inline clocking events (LALR limitation)

**IEEE grammar:**
```
property_expr ::= ... | clocking_event property_expr
sequence_expr ::= ... | clocking_event sequence_expr
```

**Example:**
```sv
@(posedge clk) a ##1 @(posedge clk2) b
```

**Status:** Cannot implement.  The `@(event)` syntax is shared with
`always @(...)` and `event_ctrl_stmt`.  After the `sensitivity`
nonterminal reduces, LALR merges all contexts into one state.  Three
grammar placements were tried (see `svfe_sva_gaps_response.md` Gap 10);
all produce either reduce/reduce or shift/reduce conflicts that break
existing constructs.

### Gap B: Assertion variable declarations

**IEEE grammar:**
```
assertion_variable_declaration ::= var_data_type list_of_variable_decl_assignments ;

property_declaration ::=
    property identifier [(...)] ;
        { assertion_variable_declaration }
        property_spec [;]
    endproperty [: identifier]

sequence_declaration ::=
    sequence identifier [(...)] ;
        { assertion_variable_declaration }
        sequence_expr [;]
    endsequence [: identifier]
```

**Example:**
```sv
property p;
    int x;
    (valid, x = data) |-> ##5 (out == x);
endproperty
```

**Status:** Not implemented.  Two sub-parts:

- *Variable declarations* (`int x;` before the body): Feasible.  Keyword
  tokens (`int`, `logic`, etc.) are distinct from property expression
  start tokens, so no LALR conflict.

- *Match-item assignments* (`(expr, x = e)`): Likely LALR conflict.
  After `( expr ,` the parser cannot distinguish a sequence match-item
  list from parenthesized expressions, function argument lists, or
  concatenations without unbounded lookahead.

### Gap C: `expression_or_dist`

**IEEE grammar:**
```
expression_or_dist ::= expression [ dist { dist_list } ]
```

Used in `property_expr` (`if`, `case`, abort clauses), `sequence_expr`
(base expression), and `cover sequence`.

**Status:** We use plain `expression` everywhere.  The `dist` clause is
part of the constraint/randomization subsystem (§18.5.4).  It is rarely
used in SVA and would require implementing the `dist` keyword, `dist_list`,
and weight syntax (`:/`, `:=`).  Low priority.

### Gap D: Named property/sequence instantiation with arguments

**IEEE grammar:**
```
property_instance ::=
    ps_or_hierarchical_property_identifier [ ( [ property_list_of_arguments ] ) ]

sequence_instance ::=
    ps_or_hierarchical_sequence_identifier [ ( [ sequence_list_of_arguments ] ) ]

property_list_of_arguments ::=
    [property_actual_arg] {, [property_actual_arg]}
    {, .identifier ([property_actual_arg])}
    | .identifier ([property_actual_arg])
    {, .identifier ([property_actual_arg])}
```

**Example:**
```sv
sequence s_handshake(req, ack);
    req ##[1:5] ack;
endsequence

property p;
    s_handshake(req, ack) |-> ##1 done;
endproperty
```

**Status:** Simple invocations (no arguments) parse correctly via the
`expression` pathway — a bare identifier is a valid expression.
Invocations with positional arguments (e.g., `s_handshake(req, ack)`)
also parse correctly as function calls via `expression`.  Named argument
binding (`.req(a)`) does not work because the expression grammar doesn't
include this syntax.  However, named argument binding in SVA is rare;
positional arguments are the norm.

### Gap E: `first_match` with match items

**IEEE grammar:**
```
first_match ( sequence_expr {, sequence_match_item} )
```

**Status:** Our `first_match` wraps a single `seq_within_expr` with no
match items.  Adding match items would require the same `(expr, ...)`
disambiguation as Gap B Part 2.

### Gap F: `checker` construct

**IEEE grammar:**
```
checker_declaration ::=
    checker checker_identifier [(...)] ;
        { ... }
    endchecker [: checker_identifier]
```

**Status:** Not implemented.  Large but mechanical — another module-like
container.  Low priority unless formal tools require it.

## Deliberate Simplifications

These are places where our grammar is intentionally looser than IEEE,
without loss of parse correctness:

1. **`expression` vs `constant_expression`** — IEEE distinguishes constant
   expressions (compile-time evaluable) in ranges and delay counts.  We
   use `expression` uniformly.  The distinction is semantic, enforced by
   downstream tools, not by the parser.

2. **`expression` vs `expression_or_dist`** — See Gap C above.  The
   `dist` clause is omitted as it belongs to the constraint subsystem.

3. **Merged `and`/`or`/`intersect`** — IEEE has these at both the
   `sequence_expr` and `property_expr` levels.  We merge them at the
   property level.  This is valid because `sequence_expr` is a subset
   of `property_expr`, and the output S-expression is identical.

4. **Port lists** — IEEE defines `property_port_list` and
   `sequence_port_list` with `local` modifier and direction keywords.
   We reuse the generic `opt_port_list` from module declarations.
   The difference is semantic (port direction/locality), not syntactic.

5. **`sequence_instance`** — IEEE has a distinct `sequence_instance`
   nonterminal with optional `sequence_abbrev` suffix.  We parse named
   sequences as expressions.  `seq_name [*3]` still works via
   `seq_base_expr` → `expression` + boolean abbreviation.

## Summary

| Category | Count |
|---|---|
| IEEE `property_expr` alternatives implemented | 28 of 30 |
| IEEE `sequence_expr` alternatives implemented | 8 of 11 |
| IEEE assertion statements implemented | 7 of 7 |
| IEEE declarations implemented | 2 of 3 (no `checker`) |
| Gaps confirmed as LALR limitations | 1 (inline clocking) |
| Gaps feasible but not yet implemented | 1 (assertion variable decls) |
| Gaps unlikely to be needed | 3 (dist, checker, first_match match items) |

The svfe SVA grammar covers the large majority of IEEE 1800-2017 §A.2.10.
The missing features are either LALR-incompatible (inline clocking events),
rarely used (dist, checker, named argument binding), or partially feasible
(assertion variable declarations).
