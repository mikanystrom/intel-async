%start source_text

source_text:
  x                         description_list

description_list:
  empty
  cons                      description_list description

description:
  module                    module_declaration
  package                   package_declaration
  interface                 interface_declaration
  typedef                   typedef_declaration ';'
  import                    import_declaration ';'
  param                     parameter_declaration ';'
  localparam                localparam_declaration ';'
  directive                 T_DIRECTIVE
  null                      ';'


package_declaration:
  x                         T_PACKAGE T_IDENT ';' package_body T_ENDPACKAGE opt_end_label

package_body:
  empty
  cons                      package_body package_item

package_item:
  param                     parameter_declaration ';'
  localparam                localparam_declaration ';'
  typedef                   typedef_declaration ';'
  function                  function_declaration
  task                      task_declaration
  import                    import_declaration ';'
  directive                 T_DIRECTIVE


import_declaration:
  x                         T_IMPORT import_items

import_items:
  single                    import_item
  cons                      import_items ',' import_item

import_item:
  specific                  T_IDENT T_SCOPE T_IDENT
  wildcard                  T_IDENT T_SCOPE '*'


module_declaration:
  x                         T_MODULE T_IDENT opt_module_imports opt_param_port_list opt_port_list ';' module_body T_ENDMODULE opt_end_label

opt_module_imports:
  empty
  cons                      opt_module_imports import_declaration ';'

opt_param_port_list:
  yes                       '#' '(' param_port_list ')'
  empty_hash                '#' '(' ')'
  empty

param_port_list:
  single                    param_port_decl
  cons                      param_port_list ',' param_port_decl

param_port_decl:
  param_typed               T_PARAMETER data_type T_IDENT '=' expression
  param_bare                T_PARAMETER T_IDENT param_ident_rest
  param_range               T_PARAMETER opt_signing packed_dim_list T_IDENT '=' expression
  localparam_typed          T_LOCALPARAM data_type T_IDENT '=' expression
  localparam_bare           T_LOCALPARAM T_IDENT param_ident_rest
  localparam_range          T_LOCALPARAM opt_signing packed_dim_list T_IDENT '=' expression
  bare_typed                data_type T_IDENT '=' expression
  bare_range                opt_signing packed_dim_list T_IDENT '=' expression
  bare_bare                 T_IDENT param_ident_rest
  param_type                T_PARAMETER T_TYPE T_IDENT '=' data_type_or_implicit

param_ident_rest:
  scoped                    T_SCOPE T_IDENT T_IDENT '=' expression
  user_typed                T_IDENT '=' expression
  plain                     '=' expression

opt_port_list:
  yes                       '(' port_list ')'
  empty_parens              '(' ')'
  empty

port_list:
  single                    port_decl
  cons                      port_list ',' port_decl

port_decl:
  wire                      port_direction T_WIRE opt_signing opt_packed_dims port_ident
  reg                       port_direction T_REG opt_signing opt_packed_dims port_ident
  logic                     port_direction T_LOGIC opt_signing opt_packed_dims port_ident
  integer                   port_direction T_INTEGER port_ident
  int                       port_direction T_INT opt_signing port_ident
  user_typed                port_direction T_IDENT T_IDENT opt_unpacked_dims
  dir_only                  port_direction T_IDENT dir_only_rest
  implicit_dims             port_direction packed_dim_list port_ident
  scoped_typed              port_direction T_IDENT T_SCOPE T_IDENT T_IDENT opt_unpacked_dims
  scoped_only               T_IDENT T_SCOPE T_IDENT T_IDENT opt_unpacked_dims
  user_typed_bare           T_IDENT T_IDENT opt_unpacked_dims
  interface_port            T_IDENT '.' T_IDENT T_IDENT opt_unpacked_dims
  dotnamed                  '.' T_IDENT '(' opt_expression ')'
  dotstar                   T_DOTSTAR
  ident_only                T_IDENT

dir_only_rest:
  bare
  dims                      unpacked_dim_list
  dims_ident                unpacked_dim_list port_ident
  assign                    '=' expression

port_direction:
  input                     T_INPUT
  output                    T_OUTPUT
  inout                     T_INOUT

port_ident:
  simple                    T_IDENT opt_unpacked_dims
  assign                    T_IDENT opt_unpacked_dims '=' expression

opt_net_type:
  wire                      T_WIRE
  reg                       T_REG
  logic                     T_LOGIC
  empty

opt_signing:
  signed                    T_SIGNED
  unsigned                  T_UNSIGNED
  empty

opt_packed_dims:
  yes                       packed_dim_list
  empty

packed_dim_list:
  single                    packed_dim
  cons                      packed_dim_list packed_dim

packed_dim:
  range                     '[' expression ':' expression ']'

opt_unpacked_dims:
  yes                       unpacked_dim_list
  empty

unpacked_dim_list:
  single                    unpacked_dim
  cons                      unpacked_dim_list unpacked_dim

unpacked_dim:
  range                     '[' expression ':' expression ']'
  size                      '[' expression ']'


module_body:
  empty
  cons                      module_body module_item

module_item:
  port_dir_decl             port_direction_declaration ';'
  net_decl                  net_declaration ';'
  param_decl                parameter_declaration ';'
  localparam_decl           localparam_declaration ';'
  assign_stmt               continuous_assign ';'
  always_block              always_construct
  initial_block             T_INITIAL statement
  generate_block            generate_region
  genvar_decl               T_GENVAR genvar_id_list ';'
  ident_item                T_IDENT ident_item_tail
  typedef_item              typedef_declaration ';'
  import_item               import_declaration ';'
  function_item             function_declaration
  task_item                 task_declaration
  directive                 T_DIRECTIVE
  attribute                 T_ATTRIBUTE module_item
  if_gen                    T_IF '(' expression ')' generate_block opt_gen_else
  for_gen                   T_FOR '(' genvar_init ';' expression ';' genvar_step ')' generate_block
  begin_block               T_BEGIN opt_block_name generate_body T_END opt_end_name

ident_item_tail:
  inst_hash                 '#' '(' arg_list ')' inst_list ';'
  inst_hash_empty           '#' '(' ')' inst_list ';'
  inst_or_decl              T_IDENT ident_after_two ';'

ident_after_two:
  inst_ports                opt_unpacked_dims '(' opt_connection_list ')'
  decl_more                 opt_unpacked_dims
  decl_more_list            opt_unpacked_dims ',' ident_decl_list


port_direction_declaration:
  wire                      port_direction T_WIRE opt_signing opt_packed_dims ident_decl_list
  reg                       port_direction T_REG opt_signing opt_packed_dims ident_decl_list
  logic                     port_direction T_LOGIC opt_signing opt_packed_dims ident_decl_list
  integer                   port_direction T_INTEGER ident_decl_list
  bare                      port_direction opt_signing opt_packed_dims ident_decl_list
  user_type                 port_direction T_IDENT ident_decl_list

net_declaration:
  typed                     data_type ident_decl_list
  wire_signed               T_WIRE T_SIGNED opt_packed_dims ident_decl_list
  wire_unsigned             T_WIRE T_UNSIGNED opt_packed_dims ident_decl_list
  wire_range                T_WIRE packed_dim_list ident_decl_list
  wire_ident                T_WIRE T_IDENT wire_ident_rest
  genvar                    T_GENVAR genvar_id_list
  user_type                 T_IDENT ident_decl_list
  user_type_dims            T_IDENT packed_dim_list ident_decl_list

wire_ident_rest:
  user_type                 ident_decl_list
  assign                    '=' expression
  dims                      unpacked_dim_list
  dims_assign               unpacked_dim_list '=' expression
  dims_list                 unpacked_dim_list ',' ident_decl_list
  list                      ',' ident_decl_list
  bare

data_type:
  logic                     T_LOGIC opt_signing opt_packed_dims
  reg                       T_REG opt_signing opt_packed_dims
  integer                   T_INTEGER
  bit                       T_BIT opt_signing opt_packed_dims
  byte                      T_BYTE opt_signing
  shortint                  T_SHORTINT opt_signing
  int                       T_INT opt_signing
  longint                   T_LONGINT opt_signing
  string                    T_STRING
  void                      T_VOID
  enum                      enum_type
  struct                    struct_type
  scoped                    T_IDENT T_SCOPE T_IDENT

enum_type:
  x                         T_ENUM opt_enum_base_type '{' enum_name_list '}'

opt_enum_base_type:
  yes                       data_type_or_implicit
  empty

data_type_or_implicit:
  logic                     T_LOGIC opt_signing opt_packed_dims
  bit                       T_BIT opt_signing opt_packed_dims
  reg                       T_REG opt_signing opt_packed_dims
  int                       T_INT opt_signing
  integer                   T_INTEGER

enum_name_list:
  single                    enum_name_decl
  cons                      enum_name_list ',' enum_name_decl

enum_name_decl:
  plain                     T_IDENT
  ranged                    T_IDENT '[' expression ']'
  assigned                  T_IDENT '=' expression
  ranged_assigned           T_IDENT '[' expression ']' '=' expression

struct_type:
  packed                    T_STRUCT T_PACKED opt_signing '{' struct_member_list '}'
  unpacked                  T_STRUCT '{' struct_member_list '}'

struct_member_list:
  single                    struct_member
  cons                      struct_member_list struct_member

struct_member:
  typed                     data_type_or_implicit ident_decl_list ';'
  user_type                 T_IDENT ident_decl_list ';'

typedef_declaration:
  data                      T_TYPEDEF data_type T_IDENT opt_unpacked_dims
  enum                      T_TYPEDEF enum_type T_IDENT
  struct                    T_TYPEDEF struct_type T_IDENT
  alias                     T_TYPEDEF T_IDENT T_IDENT

ident_decl_list:
  single                    ident_decl
  cons                      ident_decl_list ',' ident_decl

ident_decl:
  plain                     T_IDENT opt_unpacked_dims
  init                      T_IDENT opt_unpacked_dims '=' expression

genvar_id_list:
  single                    T_IDENT
  cons                      genvar_id_list ',' T_IDENT

parameter_declaration:
  typed                     T_PARAMETER data_type ident_decl_list
  range                     T_PARAMETER opt_signing packed_dim_list ident_decl_list
  ident_start               T_PARAMETER T_IDENT decl_ident_rest

localparam_declaration:
  typed                     T_LOCALPARAM data_type ident_decl_list
  range                     T_LOCALPARAM opt_signing packed_dim_list ident_decl_list
  ident_start               T_LOCALPARAM T_IDENT decl_ident_rest

decl_ident_rest:
  user_typed                T_IDENT opt_unpacked_dims '=' expression
  scoped                    T_SCOPE T_IDENT ident_decl_list
  assign                    '=' expression
  dims_assign               unpacked_dim_list '=' expression
  bare


continuous_assign:
  x                         T_ASSIGN assign_list

assign_list:
  single                    assign_one
  cons                      assign_list ',' assign_one

assign_one:
  x                         lvalue '=' expression


always_construct:
  always                    T_ALWAYS sensitivity statement
  comb                      T_ALWAYS_COMB statement
  ff                        T_ALWAYS_FF sensitivity statement
  latch                     T_ALWAYS_LATCH sensitivity statement

sensitivity:
  list                      '@' '(' sensitivity_list ')'
  star                      '@' '(' '*' ')'
  at_star                   '@' '*'

sensitivity_list:
  single                    sensitivity_item
  or                        sensitivity_list T_OR sensitivity_item
  comma                     sensitivity_list ',' sensitivity_item

sensitivity_item:
  posedge                   T_POSEDGE expression
  negedge                   T_NEGEDGE expression
  expr                      expression


statement:
  seq_block                 T_BEGIN opt_block_name statement_list T_END opt_end_name
  if_stmt                   T_IF '(' expression ')' statement opt_else
  case_stmt                 case_keyword '(' expression ')' case_item_list T_ENDCASE
  case_inside_stmt          case_keyword '(' expression ')' T_INSIDE case_item_list T_ENDCASE
  for_stmt                  T_FOR '(' for_init ';' expression ';' for_step ')' statement
  while_stmt                T_WHILE '(' expression ')' statement
  repeat_stmt               T_REPEAT '(' expression ')' statement
  forever_stmt              T_FOREVER statement
  assign_stmt               lvalue '=' expression ';'
  nb_assign_stmt            lvalue T_LEQ expression ';'
  force_assign              T_ASSIGN lvalue '=' expression ';'
  call_stmt                 subroutine_call ';'
  return_stmt               T_RETURN opt_expression ';'
  passign_stmt              lvalue T_PASSIGN expression ';'
  massign_stmt              lvalue T_MASSIGN expression ';'
  tassign_stmt              lvalue T_TASSIGN expression ';'
  dassign_stmt              lvalue T_DASSIGN expression ';'
  rassign_stmt              lvalue T_RASSIGN expression ';'
  aassign_stmt              lvalue T_AASSIGN expression ';'
  oassign_stmt              lvalue T_OASSIGN expression ';'
  xassign_stmt              lvalue T_XASSIGN expression ';'
  lsassign_stmt             lvalue T_LSASSIGN expression ';'
  rsassign_stmt             lvalue T_RSASSIGN expression ';'
  inc_stmt                  lvalue T_INC ';'
  dec_stmt                  lvalue T_DEC ';'
  preinc_stmt               T_INC lvalue ';'
  predec_stmt               T_DEC lvalue ';'
  assert_stmt               T_ASSERT '(' expression ')' opt_assert_else
  null_stmt                 ';'
  directive                 T_DIRECTIVE

opt_block_name:
  yes                       ':' T_IDENT
  empty

opt_end_name:
  yes                       ':' T_IDENT
  empty

opt_else:
  yes                       T_ELSE statement
  empty

opt_assert_else:
  yes                       T_ELSE statement
  bare                      ';'
  empty

case_keyword:
  case                      T_CASE
  casez                     T_CASEZ
  casex                     T_CASEX
  unique_case               T_UNIQUE T_CASE
  priority_case             T_PRIORITY T_CASE

case_item_list:
  single                    case_item
  cons                      case_item_list case_item

case_item:
  exprs                     case_expr_list ':' statement
  default_colon             T_DEFAULT ':' statement
  default_bare              T_DEFAULT statement

case_expr_list:
  single                    case_expr_item
  cons                      case_expr_list ',' case_expr_item

case_expr_item:
  expr                      expression
  range                     '[' expression ':' expression ']'

for_init:
  decl                      data_type_or_implicit T_IDENT '=' expression
  assign                    lvalue '=' expression

for_step:
  assign                    lvalue '=' expression
  inc                       lvalue T_INC
  dec                       lvalue T_DEC
  preinc                    T_INC lvalue
  predec                    T_DEC lvalue
  passign                   lvalue T_PASSIGN expression
  massign                   lvalue T_MASSIGN expression

statement_list:
  empty
  cons                      statement_list statement
  local_decl                statement_list net_declaration ';'
  auto_decl                 statement_list T_AUTOMATIC net_declaration ';'

subroutine_call:
  func                      hierarchical_id '(' opt_arg_list ')'
  system                    T_SYSIDENT opt_paren_args

opt_paren_args:
  yes                       '(' opt_arg_list ')'
  empty

opt_arg_list:
  yes                       arg_list
  empty

arg_list:
  single                    arg_item
  cons                      arg_list ',' arg_item

arg_item:
  expr                      expression
  named                     '.' T_IDENT '(' opt_expression ')'
  empty_arg


function_declaration:
  x                         T_FUNCTION opt_automatic opt_data_type_or_void T_IDENT opt_port_list ';' function_body T_ENDFUNCTION opt_end_label

opt_automatic:
  yes                       T_AUTOMATIC
  empty

opt_data_type_or_void:
  data                      data_type
  void                      T_VOID
  logic                     T_LOGIC opt_signing opt_packed_dims
  reg                       T_REG opt_signing opt_packed_dims
  integer                   T_INTEGER
  implicit_range            opt_signing opt_packed_dims
  empty

function_body:
  empty
  cons                      function_body function_body_item

function_body_item:
  decl                      port_direction_declaration ';'
  net_decl                  net_declaration ';'
  param_decl                parameter_declaration ';'
  localparam_decl           localparam_declaration ';'
  stmt                      statement
  directive                 T_DIRECTIVE

task_declaration:
  x                         T_TASK opt_automatic T_IDENT opt_port_list ';' task_body T_ENDTASK opt_end_label

task_body:
  empty
  cons                      task_body task_body_item

task_body_item:
  decl                      port_direction_declaration ';'
  net_decl                  net_declaration ';'
  stmt                      statement
  directive                 T_DIRECTIVE

opt_end_label:
  yes                       ':' T_IDENT
  empty


interface_declaration:
  x                         T_INTERFACE T_IDENT opt_param_port_list opt_port_list ';' interface_body T_ENDINTERFACE opt_end_label

interface_body:
  empty
  cons                      interface_body interface_item

interface_item:
  net_decl                  net_declaration ';'
  param_decl                parameter_declaration ';'
  localparam_decl           localparam_declaration ';'
  modport                   modport_declaration ';'
  typedef_item              typedef_declaration ';'
  function_item             function_declaration
  task_item                 task_declaration
  directive                 T_DIRECTIVE

modport_declaration:
  x                         T_MODPORT T_IDENT '(' modport_port_list ')'

modport_port_list:
  single                    modport_port_item
  cons                      modport_port_list ',' modport_port_item

modport_port_item:
  input                     T_INPUT T_IDENT
  output                    T_OUTPUT T_IDENT
  inout                     T_INOUT T_IDENT
  ident                     T_IDENT


generate_region:
  x                         T_GENERATE generate_body T_ENDGENERATE

generate_body:
  empty
  cons                      generate_body generate_item

generate_item:
  module_item               module_item
  if_gen                    T_IF '(' expression ')' generate_block opt_gen_else
  for_gen                   T_FOR '(' genvar_init ';' expression ';' genvar_step ')' generate_block
  begin_gen                 T_BEGIN opt_block_name generate_body T_END opt_end_name

opt_gen_else:
  yes                       T_ELSE generate_block
  empty

generate_block:
  single                    generate_item
  block                     T_BEGIN opt_block_name generate_body T_END opt_end_name

genvar_init:
  decl                      T_GENVAR T_IDENT '=' expression
  assign                    T_IDENT '=' expression

genvar_step:
  assign                    T_IDENT '=' expression
  inc                       T_IDENT T_INC
  dec                       T_IDENT T_DEC
  preinc                    T_INC T_IDENT
  predec                    T_DEC T_IDENT
  passign                   T_IDENT T_PASSIGN expression


module_instantiation:
  x                         T_IDENT opt_param_actuals inst_list

opt_param_actuals:
  yes                       '#' '(' arg_list ')'
  empty_hash                '#' '(' ')'
  empty

inst_list:
  single                    inst_one
  cons                      inst_list ',' inst_one

inst_one:
  x                         T_IDENT opt_unpacked_dims '(' opt_connection_list ')'

opt_connection_list:
  yes                       connection_list
  empty

connection_list:
  single                    connection
  cons                      connection_list ',' connection

connection:
  named                     '.' T_IDENT '(' opt_expression ')'
  implicit_named            '.' T_IDENT
  dotstar                   T_DOTSTAR
  positional                expression


expression:
  x                         cond_expr

cond_expr:
  single                    lor_expr
  ternary                   lor_expr '?' expression ':' expression

lor_expr:
  single                    land_expr
  lor                       lor_expr T_LOR land_expr

land_expr:
  single                    bor_expr
  land                      land_expr T_LAND bor_expr

bor_expr:
  single                    bxor_expr
  bor                       bor_expr '|' bxor_expr

bxor_expr:
  single                    band_expr
  bxor                      bxor_expr '^' band_expr
  bxnor                     bxor_expr T_XNOR band_expr

band_expr:
  single                    eq_expr
  band                      band_expr '&' eq_expr

eq_expr:
  single                    rel_expr
  eq                        eq_expr T_EQ rel_expr
  neq                       eq_expr T_NEQ rel_expr
  ceq                       eq_expr T_CEQ rel_expr
  cne                       eq_expr T_CNE rel_expr
  weq                       eq_expr T_WEQ rel_expr
  wne                       eq_expr T_WNE rel_expr

rel_expr:
  single                    shift_expr
  lt                        rel_expr '<' shift_expr
  gt                        rel_expr '>' shift_expr
  leq                       rel_expr T_LEQ shift_expr
  geq                       rel_expr T_GEQ shift_expr
  inside                    shift_expr T_INSIDE '{' inside_list '}'

inside_list:
  single                    inside_item
  cons                      inside_list ',' inside_item

inside_item:
  expr                      expression
  range                     '[' expression ':' expression ']'

shift_expr:
  single                    add_expr
  lshift                    shift_expr T_LSHIFT add_expr
  rshift                    shift_expr T_RSHIFT add_expr
  alshift                   shift_expr T_ALSHIFT add_expr
  arshift                   shift_expr T_ARSHIFT add_expr

add_expr:
  single                    mul_expr
  add                       add_expr '+' mul_expr
  sub                       add_expr '-' mul_expr

mul_expr:
  single                    unary_expr
  mul                       mul_expr '*' unary_expr
  div                       mul_expr '/' unary_expr
  rem                       mul_expr '%' unary_expr

unary_expr:
  single                    pow_expr
  uminus                    '-' unary_expr
  uplus                     '+' unary_expr
  lnot                      '!' unary_expr
  bnot                      '~' unary_expr
  rand                      '&' unary_expr
  rnand                     T_NAND unary_expr
  ror                       '|' unary_expr
  rnor                      T_NOR unary_expr
  rxor                      '^' unary_expr
  rxnor                     T_XNOR unary_expr

pow_expr:
  single                    postfix_expr
  pow                       postfix_expr T_POW unary_expr

postfix_expr:
  single                    primary_expr
  index                     postfix_expr '[' expression ']'
  range_sel                 postfix_expr '[' expression ':' expression ']'
  psel                      postfix_expr '[' expression T_PSEL expression ']'
  msel                      postfix_expr '[' expression T_MSEL expression ']'
  member                    postfix_expr '.' T_IDENT
  call                      postfix_expr '(' opt_arg_list ')'
  cast                      postfix_expr '\'' '(' expression ')'

primary_expr:
  number                    T_NUMBER
  string                    T_STRLIT
  ident                     hierarchical_id
  sysident                  T_SYSIDENT
  paren                     '(' expression ')'
  concat                    '{' expression_list '}'
  replicate                 '{' expression '{' expression_list '}' '}'
  empty_concat              '{' '}'
  struct_lit                '\'' '{' assign_pattern_list '}'
  struct_lit_default        '\'' '{' T_DEFAULT ':' expression '}'
  unsigned_kw               T_UNSIGNED
  signed_kw                 T_SIGNED

assign_pattern_list:
  single                    assign_pattern_item
  cons                      assign_pattern_list ',' assign_pattern_item

assign_pattern_item:
  named                     T_IDENT ':' expression
  positional                expression

hierarchical_id:
  simple                    T_IDENT
  scoped                    T_IDENT T_SCOPE T_IDENT
  dotted                    hierarchical_id '.' T_IDENT

expression_list:
  single                    expression
  cons                      expression_list ',' expression

opt_expression:
  yes                       expression
  empty

lvalue:
  ident                     hierarchical_id
  index                     lvalue '[' expression ']'
  range_sel                 lvalue '[' expression ':' expression ']'
  psel                      lvalue '[' expression T_PSEL expression ']'
  msel                      lvalue '[' expression T_MSEL expression ']'
  member                    lvalue '.' T_IDENT
  concat                    '{' lvalue_list '}'

lvalue_list:
  single                    lvalue
  cons                      lvalue_list ',' lvalue
