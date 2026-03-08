%left lvalue_primary_expression
%right lval_statement

%start program

program:
  x                        top_list opt_seq_stmt

top_list:
  empty
  func                     top_list function_decl
  struct                   top_list structure_decl

function_decl:
  typed                    T_FUNCTION T_IDENT '(' opt_decl_list ')' ':' type '=' statement ';'
  untyped                  T_FUNCTION T_IDENT '(' opt_decl_list ')' '=' statement ';'

structure_decl:
  x                        T_STRUCTURE T_IDENT '=' '(' declaration_list ')' ';'

opt_seq_stmt:
  yes                      sequential_statement
  empty

sequential_statement:
  single                   sequential_part
  cons                     sequential_statement ';' sequential_part
  trail                    sequential_statement ';'

sequential_part:
  var                      var_statement
  par                      parallel_statement

parallel_statement:
  single                   statement
  cons                     parallel_statement ',' statement

var_statement:
  x                        declaration

statement:
  paren                    '(' sequential_statement ')'
  sel                      selection_statement
  rep                      repetition_statement
  lp                       loop_statement
  hash                     '#' hash_start
  error                    T_ERROR
  skip                     T_SKIP
  lval                     lvalue stmt_suffix

stmt_suffix:
  assign                   '=' expression
  passign                  T_PASSIGN expression
  massign                  T_MASSIGN expression
  tassign                  T_TASSIGN expression
  dassign                  T_DASSIGN expression
  rassign                  T_RASSIGN expression
  aassign                  T_AASSIGN expression
  oassign                  T_OASSIGN expression
  xassign                  T_XASSIGN expression
  lsassign                 T_LSASSIGN expression
  rsassign                 T_RSASSIGN expression
  inc                      T_INC
  dec                      T_DEC
  send                     '!' opt_expression
  recv                     '?' opt_lvalue
  bset                     '+'
  bclr                     '-'
  expr_stmt

hash_start:
  sel                      '[' det_guard_noelse_commands ']'
  peek_assign              lvalue '?' lvalue
  peek_stmt                lvalue '?'
  probe_stmt               lvalue

selection_statement:
  guard                    '[' guard_commands ']'
  wait                     '[' expression ']'

repetition_statement:
  guard                    T_LOOP guard_commands ']'
  infinite                 T_LOOP sequential_statement ']'

loop_statement:
  langl                    '<' T_IDENT ':' range ':' sequential_statement '>'
  sloop                    T_SLOOP T_IDENT ':' range ':' sequential_statement '>'
  bloop                    T_BLOOP T_IDENT ':' range ':' sequential_statement '>'
  cloop                    T_CLOOP T_IDENT ':' range ':' sequential_statement '>'

guard_commands:
  determ                   det_guard_commands
  nondeterm                non_det_guard_commands

det_guard_commands:
  noelse                   det_guard_noelse_commands
  withelse                 det_guard_noelse_commands T_BOX guard_else_command

det_guard_noelse_commands:
  single                   det_guard_command
  cons                     det_guard_noelse_commands T_BOX det_guard_command

det_guard_command:
  simple                   guard_command_simple
  loop                     T_BOXLOOP T_IDENT ':' range ':' det_guard_body '>'
  loop_paren               T_BOXLOOP T_IDENT ':' range ':' '(' det_guard_inner ')' '>'

det_guard_inner:
  single                   det_guard_command
  cons                     det_guard_inner T_BOX det_guard_command

det_guard_body:
  simple                   guard_command_simple
  loop                     T_BOXLOOP T_IDENT ':' range ':' det_guard_body '>'
  loop_paren               T_BOXLOOP T_IDENT ':' range ':' '(' det_guard_inner ')' '>'

non_det_guard_commands:
  simple                   non_det_guard_simple
  linked                   non_det_guard_linked

non_det_guard_simple:
  single                   non_det_guard_command
  cons                     non_det_guard_simple ':' non_det_guard_command

non_det_guard_command:
  simple                   guard_command_simple
  loop                     T_CLLOOP T_IDENT ':' range ':' non_det_guard_body '>'
  loop_paren               T_CLLOOP T_IDENT ':' range ':' '(' non_det_guard_inner ')' '>'

non_det_guard_inner:
  single                   non_det_guard_command
  cons                     non_det_guard_inner ':' non_det_guard_command

non_det_guard_body:
  simple                   guard_command_simple
  loop                     T_CLLOOP T_IDENT ':' range ':' non_det_guard_body '>'
  loop_paren               T_CLLOOP T_IDENT ':' range ':' '(' non_det_guard_inner ')' '>'

non_det_guard_linked:
  x                        linked_guard_list ':' linkage_specifier

linked_guard_list:
  single                   linked_guard_command
  cons                     linked_guard_list ':' linked_guard_command

linked_guard_command:
  simple                   expression linkage_specifier T_ARROW sequential_statement
  loop                     T_CLLOOP T_IDENT ':' range ':' linked_guard_body '>'
  loop_paren               T_CLLOOP T_IDENT ':' range ':' '(' linked_guard_inner ')' '>'

linked_guard_inner:
  single                   linked_guard_command
  cons                     linked_guard_inner ':' linked_guard_command

linked_guard_body:
  simple                   expression linkage_specifier T_ARROW sequential_statement
  loop                     T_CLLOOP T_IDENT ':' range ':' linked_guard_body '>'
  loop_paren               T_CLLOOP T_IDENT ':' range ':' '(' linked_guard_inner ')' '>'

guard_command_simple:
  x                        expression T_ARROW sequential_statement

guard_else_command:
  x                        T_ELSE T_ARROW sequential_statement

linkage_specifier:
  x                        '@' '(' linkage_terms ')'

linkage_terms:
  single                   linkage_term
  cons                     linkage_terms ',' linkage_term

linkage_term:
  expr                     opt_tilde linkage_expr
  loop                     T_CLOOP T_IDENT ':' range ':' linkage_term_or_paren '>'

linkage_term_or_paren:
  bare                     linkage_term
  paren                    '(' linkage_term ')'

opt_tilde:
  yes                      '~'
  no

linkage_expr:
  base                     T_IDENT
  dot_id                   linkage_expr '.' T_IDENT
  dot_int                  linkage_expr '.' T_INTEGER
  array                    linkage_expr '[' expression_list ']'

expression:
  x                        cond_or_expr

cond_or_expr:
  single                   cond_and_expr
  or                       cond_or_expr T_PIPE2 cond_and_expr

cond_and_expr:
  single                   or_expr
  and                      cond_and_expr T_AMP2 or_expr

or_expr:
  single                   xor_expr
  or                       or_expr '|' xor_expr

xor_expr:
  single                   and_expr
  xor                      xor_expr '^' and_expr

and_expr:
  single                   eq_expr
  and                      and_expr '&' eq_expr

eq_expr:
  single                   rel_expr
  eq                       eq_expr T_EQ rel_expr
  neq                      eq_expr T_NEQ rel_expr

rel_expr:
  single                   shift_expr
  lt                       rel_expr '<' shift_expr
  gt                       rel_expr '>' shift_expr
  leq                      rel_expr T_LEQ shift_expr
  geq                      rel_expr T_GEQ shift_expr

shift_expr:
  single                   add_expr
  lshift                   shift_expr T_LSHIFT add_expr
  rshift                   shift_expr T_RSHIFT add_expr

add_expr:
  single                   mul_expr
  add                      add_expr '+' mul_expr
  sub                      add_expr '-' mul_expr

mul_expr:
  single                   unary_expr
  mul                      mul_expr '*' unary_expr
  div                      mul_expr '/' unary_expr
  rem                      mul_expr '%' unary_expr

unary_expr:
  single                   exp_expr
  uminus                   '-' unary_expr
  utilde                   '~' unary_expr

exp_expr:
  single                   primary_expression
  exp                      primary_expression T_EXP unary_expr

primary_expression:
  integer                  T_INTEGER
  true                     T_TRUE
  false                    T_FALSE
  string_lit               T_STRING_LIT
  paren                    '(' expression ')'
  recv_expr                lvalue '?'
  peek_expr                '#' lvalue '?'
  probe_expr               '#' lvalue
  lvalue                   lvalue
  loop_expr                loop_expression

loop_expression:
  ploop                    T_PLOOP T_IDENT ':' range ':' expression '>'
  mloop                    T_MLOOP T_IDENT ':' range ':' expression '>'
  aloop                    T_ALOOP T_IDENT ':' range ':' expression '>'
  oloop                    T_OLOOP T_IDENT ':' range ':' expression '>'
  xloop                    T_XLOOP T_IDENT ':' range ':' expression '>'

lvalue:
  ident                    T_IDENT
  string                   T_STRING
  array                    lvalue '[' expression_list ']'
  bitrange                 lvalue '{' expression opt_colon_expr '}'
  call                     lvalue '(' opt_expression_list ')'
  dot_id                   lvalue '.' T_IDENT
  dot_int                  lvalue '.' T_INTEGER
  member                   lvalue T_COLON2 T_IDENT

expression_list:
  single                   expression
  cons                     expression_list ',' expression

opt_expression_list:
  yes                      expression_list
  empty

opt_colon_expr:
  yes                      ':' expression
  empty

opt_expression:
  yes                      expression
  empty

opt_lvalue:
  yes                      lvalue
  empty

range:
  range                    expression T_DOTDOT expression
  count                    expression

declaration_list:
  single                   declaration
  cons                     declaration_list ';' declaration
  trail                    declaration_list ';'

opt_decl_list:
  yes                      declaration_list
  empty

declaration:
  x                        type declarator_list

type:
  int                      opt_const T_INT opt_paren_expr
  sint                     opt_const T_SINT '(' expression ')'
  boolean                  opt_const T_BOOLEAN
  bool                     opt_const T_BOOL
  string                   opt_const T_STRING
  struct_ref               T_IDENT

opt_const:
  yes                      T_CONST
  no

opt_paren_expr:
  yes                      '(' expression ')'
  empty

declarator_list:
  single                   declarator
  cons                     declarator_list ',' declarator

declarator:
  x                        opt_direction T_IDENT opt_array_dims opt_initializer

opt_direction:
  out                      '+'
  in                       '-'
  inout_pm                 '+' '-'
  inout_mp                 '-' '+'
  none

opt_array_dims:
  bracket                  opt_array_dims '[' range_list ']'
  empty

range_list:
  single                   range
  cons                     range_list ',' range

opt_initializer:
  yes                      '=' expression
  empty
