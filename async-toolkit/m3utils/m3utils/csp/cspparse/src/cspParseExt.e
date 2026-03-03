%source csp.t csp.y
%import cspLexExt cspParse

program:
  x  { (* Phase 1: syntax check only *) }

top_list:
  empty  { }
  func   { }
  struct { }

function_decl:
  typed   { }
  untyped { }

structure_decl:
  x  { }

opt_seq_stmt:
  yes   { }
  empty { }

sequential_statement:
  single { }
  cons   { }
  trail  { }

sequential_part:
  var { }
  par { }

parallel_statement:
  single { }
  cons   { }

var_statement:
  x  { }

statement:
  paren      { }
  sel        { }
  rep        { }
  lp         { }
  hash       { }
  error      { }
  skip       { }
  lval       { }

stmt_suffix:
  assign     { }
  passign    { }
  massign    { }
  tassign    { }
  dassign    { }
  rassign    { }
  aassign    { }
  oassign    { }
  xassign    { }
  lsassign   { }
  rsassign   { }
  inc        { }
  dec        { }
  send       { }
  recv       { }
  bset       { }
  bclr       { }
  expr_stmt  { }

hash_start:
  sel          { }
  peek_assign  { }
  peek_stmt    { }
  probe_stmt   { }

selection_statement:
  guard { }
  wait  { }

repetition_statement:
  guard    { }
  infinite { }

loop_statement:
  langl { }
  sloop { }
  bloop { }
  cloop { }

guard_commands:
  determ    { }
  nondeterm { }

det_guard_commands:
  noelse   { }
  withelse { }

det_guard_noelse_commands:
  single { }
  cons   { }

det_guard_command:
  simple     { }
  loop       { }
  loop_paren { }

det_guard_inner:
  single { }
  cons   { }

det_guard_body:
  simple     { }
  loop       { }
  loop_paren { }

non_det_guard_commands:
  simple { }
  linked { }

non_det_guard_simple:
  single { }
  cons   { }

non_det_guard_command:
  simple     { }
  loop       { }
  loop_paren { }

non_det_guard_inner:
  single { }
  cons   { }

non_det_guard_body:
  simple     { }
  loop       { }
  loop_paren { }

non_det_guard_linked:
  x  { }

linked_guard_list:
  single { }
  cons   { }

linked_guard_command:
  simple     { }
  loop       { }
  loop_paren { }

linked_guard_inner:
  single { }
  cons   { }

linked_guard_body:
  simple     { }
  loop       { }
  loop_paren { }

guard_command_simple:
  x  { }

guard_else_command:
  x  { }

linkage_specifier:
  x  { }

linkage_terms:
  single { }
  cons   { }

linkage_term:
  expr { }
  loop { }

linkage_term_or_paren:
  bare  { }
  paren { }

opt_tilde:
  yes { }
  no  { }

linkage_expr:
  base    { }
  dot_id  { }
  dot_int { }
  array   { }

expression:
  x  { }

cond_or_expr:
  single { }
  or     { }

cond_and_expr:
  single { }
  and    { }

or_expr:
  single { }
  or     { }

xor_expr:
  single { }
  xor    { }

and_expr:
  single { }
  and    { }

eq_expr:
  single { }
  eq     { }
  neq    { }

rel_expr:
  single { }
  lt     { }
  gt     { }
  leq    { }
  geq    { }

shift_expr:
  single { }
  lshift { }
  rshift { }

add_expr:
  single { }
  add    { }
  sub    { }

mul_expr:
  single { }
  mul    { }
  div    { }
  rem    { }

unary_expr:
  single { }
  uminus { }
  utilde { }

exp_expr:
  single { }
  exp    { }

primary_expression:
  integer    { }
  true       { }
  false      { }
  string_lit { }
  paren      { }
  recv_expr  { }
  peek_expr  { }
  probe_expr { }
  lvalue     { }
  loop_expr  { }

loop_expression:
  ploop { }
  mloop { }
  aloop { }
  oloop { }
  xloop { }

lvalue:
  ident    { }
  string   { }
  array    { }
  bitrange { }
  call     { }
  dot_id   { }
  dot_int  { }
  member   { }

expression_list:
  single { }
  cons   { }

opt_expression_list:
  yes   { }
  empty { }

opt_colon_expr:
  yes   { }
  empty { }

opt_expression:
  yes   { }
  empty { }

opt_lvalue:
  yes   { }
  empty { }

range:
  range { }
  count { }

declaration_list:
  single { }
  cons   { }
  trail  { }

opt_decl_list:
  yes   { }
  empty { }

declaration:
  x  { }

type:
  int         { }
  sint        { }
  boolean     { }
  bool        { }
  string      { }

opt_const:
  yes { }
  no  { }

opt_paren_expr:
  yes   { }
  empty { }

declarator_list:
  single { }
  cons   { }

declarator:
  x  { }

opt_direction:
  out      { }
  in       { }
  inout_pm { }
  inout_mp { }
  none     { }

opt_array_dims:
  bracket { }
  empty   { }

range_list:
  single { }
  cons   { }

opt_initializer:
  yes   { }
  empty { }
