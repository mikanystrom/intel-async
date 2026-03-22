%start source_text

source_text:
  x                         description_list

description_list:
  empty
  cons                      description_list description

mark:
  empty

description:
  module                    mark module_declaration
  package                   mark package_declaration
  interface                 mark interface_declaration
  typedef                   mark typedef_declaration ';'
  import                    mark import_declaration ';'
  dpi_export                mark dpi_export_declaration ';'
  dpi_import                mark dpi_import_declaration ';'
  timeunit                  mark timeunit_declaration
  param                     mark parameter_declaration ';'
  localparam                mark localparam_declaration ';'
  null                      mark ';'


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
  dpi_export                dpi_export_declaration ';'
  dpi_import                dpi_import_declaration ';'
  extern_item               extern_declaration ';'
  timeunit_item             timeunit_declaration


import_declaration:
  x                         T_IMPORT import_items

import_items:
  single                    import_item
  cons                      import_items ',' import_item

import_item:
  specific                  T_IDENT T_SCOPE T_IDENT
  wildcard                  T_IDENT T_SCOPE '*'

dpi_export_declaration:
  function                  T_EXPORT T_STRLIT T_FUNCTION T_IDENT
  task                      T_EXPORT T_STRLIT T_TASK T_IDENT
  function_cid              T_EXPORT T_STRLIT T_IDENT '=' T_FUNCTION T_IDENT
  task_cid                  T_EXPORT T_STRLIT T_IDENT '=' T_TASK T_IDENT

dpi_import_declaration:
  function                  T_IMPORT T_STRLIT opt_dpi_property T_FUNCTION opt_data_type_or_void T_IDENT opt_port_list
  function_user             T_IMPORT T_STRLIT opt_dpi_property T_FUNCTION T_IDENT T_IDENT opt_port_list
  function_bare             T_IMPORT T_STRLIT opt_dpi_property T_FUNCTION T_IDENT opt_port_list
  task                      T_IMPORT T_STRLIT opt_dpi_property T_TASK T_IDENT opt_port_list
  function_cid              T_IMPORT T_STRLIT opt_dpi_property T_IDENT '=' T_FUNCTION opt_data_type_or_void T_IDENT opt_port_list
  function_cid_user         T_IMPORT T_STRLIT opt_dpi_property T_IDENT '=' T_FUNCTION T_IDENT T_IDENT opt_port_list
  function_cid_bare         T_IMPORT T_STRLIT opt_dpi_property T_IDENT '=' T_FUNCTION T_IDENT opt_port_list
  task_cid                  T_IMPORT T_STRLIT opt_dpi_property T_IDENT '=' T_TASK T_IDENT opt_port_list

opt_dpi_property:
  pure                      T_PURE
  context                   T_CONTEXT
  empty


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
  param_typed_dims          T_PARAMETER data_type T_IDENT unpacked_dim_list '=' expression
  param_bare                T_PARAMETER T_IDENT param_ident_rest
  param_range               T_PARAMETER opt_signing packed_dim_list T_IDENT '=' expression
  localparam_typed          T_LOCALPARAM data_type T_IDENT '=' expression
  localparam_typed_dims     T_LOCALPARAM data_type T_IDENT unpacked_dim_list '=' expression
  localparam_bare           T_LOCALPARAM T_IDENT param_ident_rest
  localparam_range          T_LOCALPARAM opt_signing packed_dim_list T_IDENT '=' expression
  bare_typed                data_type T_IDENT '=' expression
  bare_typed_dims           data_type T_IDENT unpacked_dim_list '=' expression
  bare_range                opt_signing packed_dim_list T_IDENT '=' expression
  bare_bare                 T_IDENT param_ident_rest
  param_type                T_PARAMETER T_TYPE T_IDENT '=' data_type
  param_type_user           T_PARAMETER T_TYPE T_IDENT '=' T_IDENT
  param_type_bare           T_PARAMETER T_TYPE T_IDENT
  localparam_type           T_LOCALPARAM T_TYPE T_IDENT '=' data_type
  localparam_type_user      T_LOCALPARAM T_TYPE T_IDENT '=' T_IDENT
  bare_type                 T_TYPE T_IDENT '=' data_type
  bare_type_user            T_TYPE T_IDENT '=' T_IDENT

param_ident_rest:
  scoped                    T_SCOPE T_IDENT T_IDENT '=' expression
  user_typed                T_IDENT '=' expression
  user_typed_dims           T_IDENT unpacked_dim_list '=' expression
  plain                     '=' expression
  plain_dims                unpacked_dim_list '=' expression

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
  bit                       port_direction T_BIT opt_signing opt_packed_dims port_ident
  byte                      port_direction T_BYTE port_ident
  shortint                  port_direction T_SHORTINT port_ident
  longint                   port_direction T_LONGINT port_ident
  string_dir                port_direction T_STRING port_ident
  user_typed                port_direction T_IDENT T_IDENT opt_unpacked_dims
  dir_only                  port_direction T_IDENT dir_only_rest
  implicit_dims             port_direction packed_dim_list port_ident
  signed_dims               port_direction T_SIGNED packed_dim_list port_ident
  unsigned_dims             port_direction T_UNSIGNED packed_dim_list port_ident
  scoped_typed              port_direction T_IDENT T_SCOPE T_IDENT T_IDENT opt_unpacked_dims
  scoped_typed_dims         port_direction T_IDENT T_SCOPE T_IDENT packed_dim_list T_IDENT opt_unpacked_dims
  scoped_only               T_IDENT T_SCOPE T_IDENT T_IDENT opt_unpacked_dims
  scoped_only_dims          T_IDENT T_SCOPE T_IDENT packed_dim_list T_IDENT opt_unpacked_dims
  user_typed_bare           T_IDENT T_IDENT opt_unpacked_dims
  interface_port            T_IDENT '.' T_IDENT T_IDENT opt_unpacked_dims
  wire_bare                 T_WIRE T_IDENT opt_unpacked_dims
  bare_logic                T_LOGIC opt_signing opt_packed_dims port_ident
  bare_int                  T_INT opt_signing port_ident
  bare_integer              T_INTEGER port_ident
  bare_bit                  T_BIT opt_signing opt_packed_dims port_ident
  bare_string               T_STRING port_ident
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
  ref                       T_REF
  const_ref                 T_CONST T_REF

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
  port_dir_decl             mark port_direction_declaration ';'
  net_decl                  mark net_declaration ';'
  param_decl                mark parameter_declaration ';'
  localparam_decl           mark localparam_declaration ';'
  assign_stmt               mark continuous_assign ';'
  always_block              mark always_construct
  initial_block             mark T_INITIAL statement
  final_block               mark T_FINAL statement
  generate_block            mark generate_region
  genvar_decl               mark T_GENVAR genvar_id_list ';'
  ident_item                mark T_IDENT ident_item_tail
  typedef_item              mark typedef_declaration ';'
  import_item               mark import_declaration ';'
  function_item             mark function_declaration
  task_item                 mark task_declaration
  attribute                 mark T_ATTRIBUTE module_item
  dpi_export                mark dpi_export_declaration ';'
  dpi_import                mark dpi_import_declaration ';'
  extern_item               mark extern_declaration ';'
  timeunit_item             mark timeunit_declaration
  assert_mod                mark T_ASSERT T_PROPERTY '(' property_expr ')' opt_assert_else
  assume_mod                mark T_ASSUME T_PROPERTY '(' property_expr ')' opt_assert_else
  cover_mod                 mark T_COVER T_PROPERTY '(' property_expr ')' ';'
  assert_imm_mod            mark T_ASSERT '#' T_NUMBER '(' expression ')' opt_assert_else
  assert_final_mod          mark T_ASSERT T_FINAL '(' expression ')' opt_assert_else
  assume_imm_mod            mark T_ASSUME '#' T_NUMBER '(' expression ')' opt_assert_else
  assume_final_mod          mark T_ASSUME T_FINAL '(' expression ')' opt_assert_else
  cover_imm_mod             mark T_COVER '#' T_NUMBER '(' expression ')' ';'
  cover_final_mod           mark T_COVER T_FINAL '(' expression ')' ';'
  labeled_assert            mark T_IDENT ':' T_ASSERT T_PROPERTY '(' property_expr ')' opt_assert_else
  labeled_assume            mark T_IDENT ':' T_ASSUME T_PROPERTY '(' property_expr ')' opt_assert_else
  labeled_cover             mark T_IDENT ':' T_COVER T_PROPERTY '(' property_expr ')' ';'
  labeled_assert_imm        mark T_IDENT ':' T_ASSERT '#' T_NUMBER '(' expression ')' opt_assert_else
  labeled_assume_imm        mark T_IDENT ':' T_ASSUME '#' T_NUMBER '(' expression ')' opt_assert_else
  labeled_cover_imm         mark T_IDENT ':' T_COVER '#' T_NUMBER '(' expression ')' ';'
  if_gen                    mark T_IF '(' expression ')' generate_block opt_gen_else
  for_gen                   mark T_FOR '(' genvar_init ';' expression ';' genvar_step ')' generate_block
  case_item                 mark case_keyword '(' expression ')' case_item_list T_ENDCASE
  begin_block               mark T_BEGIN opt_block_name generate_body T_END opt_end_name
  annotation                T_ANNOTATION module_item
  translate_off             mark T_TRANSLATE_OFF translate_off_body T_TRANSLATE_ON

translate_off_body:
  empty
  cons                      translate_off_body module_item

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
  real                      T_REAL
  time                      T_TIME
  bit                       T_BIT opt_signing opt_packed_dims
  byte                      T_BYTE opt_signing
  shortint                  T_SHORTINT opt_signing
  int                       T_INT opt_signing
  longint                   T_LONGINT opt_signing
  string                    T_STRING
  void                      T_VOID
  enum                      enum_type
  struct                    struct_type
  union                     union_type
  scoped                    T_IDENT T_SCOPE T_IDENT

enum_type:
  x                         T_ENUM opt_enum_base_type '{' enum_name_list '}'

opt_enum_base_type:
  yes                       data_type_or_implicit
  user_type                 T_IDENT
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

union_type:
  packed                    T_UNION T_PACKED opt_signing '{' struct_member_list '}'
  unpacked                  T_UNION '{' struct_member_list '}'
  tagged_packed             T_UNION T_TAGGED T_PACKED opt_signing '{' struct_member_list '}'
  tagged                    T_UNION T_TAGGED '{' struct_member_list '}'

struct_member_list:
  single                    struct_member
  cons                      struct_member_list struct_member

struct_member:
  typed                     data_type_or_implicit ident_decl_list ';'
  user_type                 T_IDENT ident_decl_list ';'
  void_member               T_VOID T_IDENT ';'
  struct_typed              struct_type ident_decl_list ';'
  union_typed               union_type ident_decl_list ';'
  enum_typed                enum_type ident_decl_list ';'

typedef_declaration:
  data                      T_TYPEDEF data_type T_IDENT opt_unpacked_dims
  enum                      T_TYPEDEF enum_type T_IDENT
  struct                    T_TYPEDEF struct_type T_IDENT
  union                     T_TYPEDEF union_type T_IDENT
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
  type_decl                 T_PARAMETER T_TYPE T_IDENT '=' data_type
  type_user                 T_PARAMETER T_TYPE T_IDENT '=' T_IDENT

localparam_declaration:
  typed                     T_LOCALPARAM data_type ident_decl_list
  range                     T_LOCALPARAM opt_signing packed_dim_list ident_decl_list
  ident_start               T_LOCALPARAM T_IDENT decl_ident_rest
  type_decl                 T_LOCALPARAM T_TYPE T_IDENT '=' data_type
  type_user                 T_LOCALPARAM T_TYPE T_IDENT '=' T_IDENT

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
  latch_nosens              T_ALWAYS_LATCH statement

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
  assert_deferred           T_ASSERT '#' T_NUMBER '(' expression ')' opt_assert_else
  assert_final              T_ASSERT T_FINAL '(' expression ')' opt_assert_else
  assert_property_stmt      T_ASSERT T_PROPERTY '(' property_expr ')' opt_assert_else
  assume_stmt               T_ASSUME '(' expression ')' opt_assert_else
  assume_deferred           T_ASSUME '#' T_NUMBER '(' expression ')' opt_assert_else
  assume_final              T_ASSUME T_FINAL '(' expression ')' opt_assert_else
  assume_property_stmt      T_ASSUME T_PROPERTY '(' property_expr ')' opt_assert_else
  cover_stmt                T_COVER '(' expression ')' ';'
  cover_deferred            T_COVER '#' T_NUMBER '(' expression ')' ';'
  cover_final               T_COVER T_FINAL '(' expression ')' ';'
  cover_property_stmt       T_COVER T_PROPERTY '(' property_expr ')' ';'
  delay_stmt                '#' expression statement
  event_ctrl_stmt           sensitivity statement
  foreach_stmt              T_FOREACH '(' hierarchical_id '[' foreach_var_list ']' ')' statement
  do_while_stmt             T_DO statement T_WHILE '(' expression ')' ';'
  release_stmt              T_RELEASE lvalue ';'
  force_stmt                T_FORCE lvalue '=' expression ';'
  void_cast                 T_VOID '\'' '(' expression ')' ';'
  null_stmt                 ';'

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

property_expr:
  expr                      expression
  clocked                   sensitivity expression
  clocked_disable           sensitivity T_IDENT T_IDENT '(' expression ')' expression

case_keyword:
  case                      T_CASE
  casez                     T_CASEZ
  casex                     T_CASEX
  unique_case               T_UNIQUE T_CASE
  unique_casez              T_UNIQUE T_CASEZ
  unique_casex              T_UNIQUE T_CASEX
  priority_case             T_PRIORITY T_CASE
  priority_casez            T_PRIORITY T_CASEZ
  priority_casex            T_PRIORITY T_CASEX

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

foreach_var_list:
  single                    T_IDENT
  cons                      foreach_var_list ',' T_IDENT

statement_list:
  empty
  cons                      statement_list statement
  local_decl                statement_list net_declaration ';'
  auto_decl                 statement_list T_AUTOMATIC net_declaration ';'
  static_decl               statement_list T_STATIC net_declaration ';'
  const_decl                statement_list T_CONST net_declaration ';'
  local_param               statement_list localparam_declaration ';'
  local_parameter            statement_list parameter_declaration ';'

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
  user_type                 T_FUNCTION opt_automatic T_IDENT T_IDENT opt_port_list ';' function_body T_ENDFUNCTION opt_end_label
  user_type_dims            T_FUNCTION opt_automatic T_IDENT packed_dim_list T_IDENT opt_port_list ';' function_body T_ENDFUNCTION opt_end_label
  bare                      T_FUNCTION opt_automatic T_IDENT opt_port_list ';' function_body T_ENDFUNCTION opt_end_label

opt_automatic:
  yes                       T_AUTOMATIC
  empty

opt_data_type_or_void:
  data                      data_type
  void                      T_VOID
  logic                     T_LOGIC opt_signing opt_packed_dims
  reg                       T_REG opt_signing opt_packed_dims
  integer                   T_INTEGER
  implicit_dims             opt_signing packed_dim_list

function_body:
  empty
  cons                      function_body function_body_item

function_body_item:
  decl                      port_direction_declaration ';'
  net_decl                  net_declaration ';'
  auto_decl                 T_AUTOMATIC net_declaration ';'
  const_decl                T_CONST net_declaration ';'
  param_decl                parameter_declaration ';'
  localparam_decl           localparam_declaration ';'
  stmt                      statement

task_declaration:
  x                         T_TASK opt_automatic T_IDENT opt_port_list ';' task_body T_ENDTASK opt_end_label

task_body:
  empty
  cons                      task_body task_body_item

task_body_item:
  decl                      port_direction_declaration ';'
  net_decl                  net_declaration ';'
  stmt                      statement

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
  extern_item               extern_declaration ';'
  timeunit_item             timeunit_declaration

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
  sys_call                  subroutine_call ';'

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


extern_declaration:
  function                  T_EXTERN T_FUNCTION opt_automatic opt_data_type_or_void T_IDENT opt_port_list
  function_user             T_EXTERN T_FUNCTION opt_automatic T_IDENT T_IDENT opt_port_list
  function_bare             T_EXTERN T_FUNCTION opt_automatic T_IDENT opt_port_list
  task                      T_EXTERN T_TASK opt_automatic T_IDENT opt_port_list

timeunit_declaration:
  timeunit                  T_TIMEUNIT time_literal ';'
  timeunit_prec             T_TIMEUNIT time_literal '/' time_literal ';'
  timeprecision             T_TIMEPRECISION time_literal ';'

time_literal:
  x                         T_NUMBER T_IDENT


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
  type_cast                 cast_type '\'' '(' expression ')'

cast_type:
  int                       T_INT
  logic                     T_LOGIC
  bit                       T_BIT
  byte                      T_BYTE
  shortint                  T_SHORTINT
  longint                   T_LONGINT
  integer                   T_INTEGER
  signed                    T_SIGNED
  unsigned                  T_UNSIGNED

primary_expr:
  number                    T_NUMBER
  string                    T_STRLIT
  ident                     hierarchical_id
  sysident                  T_SYSIDENT
  paren                     '(' expression ')'
  concat                    '{' expression_list '}'
  replicate                 '{' expression '{' expression_list '}' '}'
  empty_concat              '{' '}'
  stream_left               '{' T_LSHIFT stream_slice '{' expression_list '}' '}'
  stream_right              '{' T_RSHIFT stream_slice '{' expression_list '}' '}'
  struct_lit                '\'' '{' assign_pattern_list '}'
  struct_lit_default        '\'' '{' T_DEFAULT ':' expression '}'
  unsigned_kw               T_UNSIGNED
  signed_kw                 T_SIGNED

stream_slice:
  number                    T_NUMBER
  ident                     T_IDENT
  empty

assign_pattern_list:
  single                    assign_pattern_item
  cons                      assign_pattern_list ',' assign_pattern_item

assign_pattern_item:
  named                     T_IDENT ':' expression
  default                   T_DEFAULT ':' expression
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
