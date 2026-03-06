%source sv.t sv.y
%import svLexExt svParse
%module {
IMPORT Text;

PROCEDURE Seq(a, b : TEXT) : TEXT =
  BEGIN
    IF Text.Empty(a) THEN RETURN b
    ELSIF Text.Empty(b) THEN RETURN a
    ELSE RETURN a & " " & b
    END
  END Seq;

PROCEDURE Wrap(tag, body : TEXT) : TEXT =
  BEGIN
    RETURN "(" & tag & " " & body & ")"
  END Wrap;

PROCEDURE Wrap2(tag, a, b : TEXT) : TEXT =
  BEGIN
    RETURN "(" & tag & " " & a & " " & b & ")"
  END Wrap2;
}
%interface {
}
%public {
  scmResult : TEXT;
}

source_text: { val : TEXT; cnt : INTEGER; }
  x  { self.scmResult := $1; $$.val := $1 }

description_list: { val : TEXT; cnt : INTEGER; }
  empty  { $$.val := "" }
  cons   { $$.val := Seq($1, $2) }

description: { val : TEXT; cnt : INTEGER; }
  module     { $$.val := $1 }
  package    { $$.val := $1 }
  interface  { $$.val := $1 }
  typedef    { $$.val := $1 }
  import     { $$.val := $1 }
  param      { $$.val := $1 }
  localparam { $$.val := $1 }
  null       { $$.val := "" }

package_declaration: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := "(package " & $1 & " " & $2 & " " & $3 & ")" }

package_body: { val : TEXT; cnt : INTEGER; }
  empty  { $$.val := "" }
  cons   { $$.val := Seq($1, $2) }

package_item: { val : TEXT; cnt : INTEGER; }
  param      { $$.val := $1 }
  localparam { $$.val := $1 }
  typedef    { $$.val := $1 }
  function   { $$.val := $1 }
  task       { $$.val := $1 }
  import     { $$.val := $1 }

import_declaration: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := "(import " & $1 & ")" }

import_items: { val : TEXT; cnt : INTEGER; }
  single   { $$.val := $1 }
  cons     { $$.val := $1 & " " & $2 }

import_item: { val : TEXT; cnt : INTEGER; }
  specific  { $$.val := $1 & "::" & $2 }
  wildcard  { $$.val := $1 & "::*" }

dpi_export_declaration: { val : TEXT; cnt : INTEGER; }
  function      { $$.val := "(dpi-export " & $1 & " function " & $2 & ")" }
  task          { $$.val := "(dpi-export " & $1 & " task " & $2 & ")" }
  function_cid  { $$.val := "(dpi-export " & $1 & " function " & $3 & " :c-name " & $2 & ")" }
  task_cid      { $$.val := "(dpi-export " & $1 & " task " & $3 & " :c-name " & $2 & ")" }

module_declaration: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := "(module " & $1 & " " & $2 & $3 & " " & $4 & " " & $5 & ")" }

opt_module_imports: { val : TEXT; cnt : INTEGER; }
  empty  { $$.val := "" }
  cons   { $$.val := Seq($1, $2) }

opt_param_port_list: { val : TEXT; cnt : INTEGER; }
  yes         { $$.val := "(parameters " & $1 & ")" }
  empty_hash  { $$.val := "(parameters)" }
  empty       { $$.val := "()" }

param_port_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  cons    { $$.val := $1 & " " & $2 }

param_port_decl: { val : TEXT; cnt : INTEGER; }
  param_typed      { $$.val := "(parameter " & $1 & " " & $2 & " " & $3 & ")" }
  param_typed_dims { $$.val := "(parameter " & $1 & " " & $2 & " " & $3 & " " & $4 & ")" }
  param_bare       { $$.val := "(parameter " & $1 & $2 & ")" }
  param_range      { $$.val := "(parameter " & $1 & " " & $2 & " " & $3 & " " & $4 & ")" }
  localparam_typed { $$.val := "(localparam " & $1 & " " & $2 & " " & $3 & ")" }
  localparam_typed_dims { $$.val := "(localparam " & $1 & " " & $2 & " " & $3 & " " & $4 & ")" }
  localparam_bare  { $$.val := "(localparam " & $1 & $2 & ")" }
  localparam_range { $$.val := "(localparam " & $1 & " " & $2 & " " & $3 & " " & $4 & ")" }
  bare_typed       { $$.val := "(parameter " & $1 & " " & $2 & " " & $3 & ")" }
  bare_typed_dims  { $$.val := "(parameter " & $1 & " " & $2 & " " & $3 & " " & $4 & ")" }
  bare_range       { $$.val := "(parameter " & $1 & " " & $2 & " " & $3 & " " & $4 & ")" }
  bare_bare        { $$.val := "(parameter " & $1 & $2 & ")" }
  param_type       { $$.val := "(parameter-type " & $1 & " " & $2 & ")" }

param_ident_rest: { val : TEXT; cnt : INTEGER; }
  scoped      { $$.val := "::" & $1 & " " & $2 & " " & $3 }
  user_typed  { $$.val := " " & $1 & " " & $2 }
  plain       { $$.val := " () " & $1 }

opt_port_list: { val : TEXT; cnt : INTEGER; }
  yes           { $$.val := "(ports " & $1 & ")" }
  empty_parens  { $$.val := "(ports)" }
  empty         { $$.val := "()" }

port_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  cons    { $$.val := $1 & " " & $2 }

port_decl: { val : TEXT; cnt : INTEGER; }
  wire        { $$.val := "(port " & $1 & " wire " & $2 & " " & $3 & " " & $4 & ")" }
  reg         { $$.val := "(port " & $1 & " reg " & $2 & " " & $3 & " " & $4 & ")" }
  logic       { $$.val := "(port " & $1 & " logic " & $2 & " " & $3 & " " & $4 & ")" }
  integer     { $$.val := "(port " & $1 & " integer " & $2 & ")" }
  int         { $$.val := "(port " & $1 & " int " & $2 & " " & $3 & ")" }
  bit         { $$.val := "(port " & $1 & " bit " & $2 & " " & $3 & " " & $4 & ")" }
  byte        { $$.val := "(port " & $1 & " byte " & $2 & ")" }
  shortint    { $$.val := "(port " & $1 & " shortint " & $2 & ")" }
  longint     { $$.val := "(port " & $1 & " longint " & $2 & ")" }
  string_dir  { $$.val := "(port " & $1 & " string " & $2 & ")" }
  user_typed  { $$.val := "(port " & $1 & " " & $2 & " (id " & $3 & " " & $4 & "))" }
  dir_only    { $$.val := "(port " & $1 & " " & $2 & $3 & ")" }
  implicit_dims { $$.val := "(port " & $1 & " logic " & $2 & " " & $3 & ")" }
  signed_dims   { $$.val := "(port " & $1 & " signed " & $2 & " " & $3 & ")" }
  unsigned_dims { $$.val := "(port " & $1 & " unsigned " & $2 & " " & $3 & ")" }
  scoped_typed { $$.val := "(port " & $1 & " " & $2 & "::" & $3 & " (id " & $4 & " " & $5 & "))" }
  scoped_typed_dims { $$.val := "(port " & $1 & " " & $2 & "::" & $3 & " " & $4 & " (id " & $5 & " " & $6 & "))" }
  scoped_only  { $$.val := "(port " & $1 & "::" & $2 & " (id " & $3 & " " & $4 & "))" }
  scoped_only_dims { $$.val := "(port " & $1 & "::" & $2 & " " & $3 & " (id " & $4 & " " & $5 & "))" }

  user_typed_bare { $$.val := "(port " & $1 & " (id " & $2 & " " & $3 & "))" }
  interface_port { $$.val := "(port-if " & $1 & "." & $2 & " (id " & $3 & " " & $4 & "))" }
  wire_bare   { $$.val := "(port wire (id " & $1 & " " & $2 & "))" }
  bare_logic  { $$.val := "(port logic " & $1 & " " & $2 & " " & $3 & ")" }
  bare_int    { $$.val := "(port int " & $1 & " " & $2 & ")" }
  bare_integer { $$.val := "(port integer " & $1 & ")" }
  bare_bit    { $$.val := "(port bit " & $1 & " " & $2 & " " & $3 & ")" }
  bare_string { $$.val := "(port string " & $1 & ")" }
  dotnamed    { $$.val := "(port-named " & $1 & " " & $2 & ")" }
  dotstar     { $$.val := "(port-dotstar)" }
  ident_only  { $$.val := "(port-ident " & $1 & ")" }

dir_only_rest: { val : TEXT; cnt : INTEGER; }
  bare        { $$.val := " (id )" }
  dims        { $$.val := " (id  " & $1 & ")" }
  dims_ident  { $$.val := " " & $1 & " " & $2 }
  assign      { $$.val := " (id  " & $1 & ")" }

port_direction: { val : TEXT; cnt : INTEGER; }
  input   { $$.val := "input" }
  output  { $$.val := "output" }
  inout   { $$.val := "inout" }

port_ident: { val : TEXT; cnt : INTEGER; }
  simple  { $$.val := "(id " & $1 & " " & $2 & ")" }
  assign  { $$.val := "(id " & $1 & " " & $2 & " " & $3 & ")" }

opt_net_type: { val : TEXT; cnt : INTEGER; }
  wire   { $$.val := "wire" }
  reg    { $$.val := "reg" }
  logic  { $$.val := "logic" }
  empty  { $$.val := "" }

opt_signing: { val : TEXT; cnt : INTEGER; }
  signed    { $$.val := "signed" }
  unsigned  { $$.val := "unsigned" }
  empty     { $$.val := "" }

opt_packed_dims: { val : TEXT; cnt : INTEGER; }
  yes    { $$.val := $1 }
  empty  { $$.val := "" }

packed_dim_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  cons    { $$.val := $1 & " " & $2 }

packed_dim: { val : TEXT; cnt : INTEGER; }
  range  { $$.val := "[" & $1 & ":" & $2 & "]" }

opt_unpacked_dims: { val : TEXT; cnt : INTEGER; }
  yes    { $$.val := $1 }
  empty  { $$.val := "" }

unpacked_dim_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  cons    { $$.val := $1 & " " & $2 }

unpacked_dim: { val : TEXT; cnt : INTEGER; }
  range  { $$.val := "[" & $1 & ":" & $2 & "]" }
  size   { $$.val := "[" & $1 & "]" }

module_body: { val : TEXT; cnt : INTEGER; }
  empty  { $$.val := "" }
  cons   { $$.val := Seq($1, $2) }

module_item: { val : TEXT; cnt : INTEGER; }
  port_dir_decl   { $$.val := $1 }
  net_decl        { $$.val := $1 }
  param_decl      { $$.val := $1 }
  localparam_decl { $$.val := $1 }
  assign_stmt     { $$.val := $1 }
  always_block    { $$.val := $1 }
  initial_block   { $$.val := Wrap("initial", $1) }
  final_block     { $$.val := Wrap("final", $1) }
  generate_block  { $$.val := $1 }
  genvar_decl     { $$.val := "(genvar " & $1 & ")" }
  ident_item      { $$.val := "(ident-item " & $1 & " " & $2 & ")" }
  typedef_item    { $$.val := $1 }
  import_item     { $$.val := $1 }
  function_item   { $$.val := $1 }
  task_item       { $$.val := $1 }
  attribute       { $$.val := $2 }
  dpi_export      { $$.val := $1 }
  if_gen          { $$.val := "(if-generate " & $1 & " " & $2 & " " & $3 & ")" }
  for_gen         { $$.val := "(for-generate " & $1 & " " & $2 & " " & $3 & " " & $4 & ")" }
  case_item       { $$.val := "(" & $1 & " " & $2 & " " & $3 & ")" }
  begin_block     { $$.val := "(begin " & $1 & " " & $2 & " " & $3 & ")" }

ident_item_tail: { val : TEXT; cnt : INTEGER; }
  inst_hash        { $$.val := "(instance (params " & $1 & ") " & $2 & ")" }
  inst_hash_empty  { $$.val := "(instance (params) " & $1 & ")" }
  inst_or_decl     { $$.val := $1 & " " & $2 }

ident_after_two: { val : TEXT; cnt : INTEGER; }
  inst_ports      { $$.val := $1 & " (" & $2 & ")" }
  decl_more       { $$.val := $1 }
  decl_more_list  { $$.val := $1 & " " & $2 }

port_direction_declaration: { val : TEXT; cnt : INTEGER; }
  wire       { $$.val := "(decl " & $1 & " wire " & $2 & " " & $3 & " " & $4 & ")" }
  reg        { $$.val := "(decl " & $1 & " reg " & $2 & " " & $3 & " " & $4 & ")" }
  logic      { $$.val := "(decl " & $1 & " logic " & $2 & " " & $3 & " " & $4 & ")" }
  integer    { $$.val := "(decl " & $1 & " integer " & $2 & ")" }
  bare       { $$.val := "(decl " & $1 & " " & $2 & " " & $3 & " " & $4 & ")" }
  user_type  { $$.val := "(decl " & $1 & " " & $2 & " " & $3 & ")" }

net_declaration: { val : TEXT; cnt : INTEGER; }
  typed          { $$.val := Wrap2("decl", $1, $2) }
  wire_signed    { $$.val := "(decl wire signed " & $1 & " " & $2 & ")" }
  wire_unsigned  { $$.val := "(decl wire unsigned " & $1 & " " & $2 & ")" }
  wire_range     { $$.val := "(decl wire " & $1 & " " & $2 & ")" }
  wire_ident     { $$.val := "(decl wire " & $1 & " " & $2 & ")" }
  genvar         { $$.val := "(genvar " & $1 & ")" }
  user_type      { $$.val := "(decl " & $1 & " " & $2 & ")" }
  user_type_dims { $$.val := "(decl " & $1 & " " & $2 & " " & $3 & ")" }

wire_ident_rest: { val : TEXT; cnt : INTEGER; }
  user_type    { $$.val := $1 }
  assign       { $$.val := "(id  " & $1 & ")" }
  dims         { $$.val := "(id  " & $1 & ")" }
  dims_assign  { $$.val := "(id  " & $1 & " " & $2 & ")" }
  dims_list    { $$.val := "(id  " & $1 & ") " & $2 }
  list         { $$.val := "(id ) " & $1 }
  bare         { $$.val := "(id )" }

data_type: { val : TEXT; cnt : INTEGER; }
  logic     { $$.val := "(logic " & $1 & " " & $2 & ")" }
  reg       { $$.val := "(reg " & $1 & " " & $2 & ")" }
  integer   { $$.val := "(integer)" }
  real      { $$.val := "(real)" }
  time      { $$.val := "(time)" }
  bit       { $$.val := "(bit " & $1 & " " & $2 & ")" }
  byte      { $$.val := "(byte " & $1 & ")" }
  shortint  { $$.val := "(shortint " & $1 & ")" }
  int       { $$.val := "(int " & $1 & ")" }
  longint   { $$.val := "(longint " & $1 & ")" }
  string    { $$.val := "string" }
  void      { $$.val := "void" }
  enum      { $$.val := $1 }
  struct    { $$.val := $1 }
  scoped    { $$.val := "(" & $1 & "::" & $2 & ")" }

enum_type: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := "(enum " & $1 & " " & $2 & ")" }

opt_enum_base_type: { val : TEXT; cnt : INTEGER; }
  yes        { $$.val := $1 }
  user_type  { $$.val := $1 }
  empty      { $$.val := "()" }

data_type_or_implicit: { val : TEXT; cnt : INTEGER; }
  logic    { $$.val := "(logic " & $1 & " " & $2 & ")" }
  bit      { $$.val := "(bit " & $1 & " " & $2 & ")" }
  reg      { $$.val := "(reg " & $1 & " " & $2 & ")" }
  int      { $$.val := "(int " & $1 & ")" }
  integer  { $$.val := "integer" }

enum_name_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  cons    { $$.val := $1 & " " & $2 }

enum_name_decl: { val : TEXT; cnt : INTEGER; }
  plain            { $$.val := $1 }
  ranged           { $$.val := $1 & "[" & $2 & "]" }
  assigned         { $$.val := "(" & $1 & " " & $2 & ")" }
  ranged_assigned  { $$.val := "(" & $1 & "[" & $2 & "] " & $3 & ")" }

struct_type: { val : TEXT; cnt : INTEGER; }
  packed    { $$.val := "(struct packed " & $1 & " " & $2 & ")" }
  unpacked  { $$.val := "(struct " & $1 & ")" }

struct_member_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  cons    { $$.val := $1 & " " & $2 }

struct_member: { val : TEXT; cnt : INTEGER; }
  typed      { $$.val := Wrap2("member", $1, $2) }
  user_type  { $$.val := "(member " & $1 & " " & $2 & ")" }

typedef_declaration: { val : TEXT; cnt : INTEGER; }
  data    { $$.val := "(typedef " & $1 & " " & $2 & " " & $3 & ")" }
  enum    { $$.val := "(typedef " & $1 & " " & $2 & ")" }
  struct  { $$.val := "(typedef " & $1 & " " & $2 & ")" }
  alias   { $$.val := "(typedef " & $1 & " " & $2 & ")" }

ident_decl_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  cons    { $$.val := $1 & " " & $2 }

ident_decl: { val : TEXT; cnt : INTEGER; }
  plain  { $$.val := "(id " & $1 & " " & $2 & ")" }
  init   { $$.val := "(id " & $1 & " " & $2 & " " & $3 & ")" }

genvar_id_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  cons    { $$.val := $1 & " " & $2 }

parameter_declaration: { val : TEXT; cnt : INTEGER; }
  typed        { $$.val := "(parameter " & $1 & " " & $2 & ")" }
  range        { $$.val := "(parameter " & $1 & " " & $2 & " " & $3 & ")" }
  ident_start  { $$.val := "(parameter " & $1 & " " & $2 & ")" }

localparam_declaration: { val : TEXT; cnt : INTEGER; }
  typed        { $$.val := "(localparam " & $1 & " " & $2 & ")" }
  range        { $$.val := "(localparam " & $1 & " " & $2 & " " & $3 & ")" }
  ident_start  { $$.val := "(localparam " & $1 & " " & $2 & ")" }

decl_ident_rest: { val : TEXT; cnt : INTEGER; }
  user_typed   { $$.val := " (id " & $1 & " " & $2 & " " & $3 & ")" }
  scoped       { $$.val := "::" & $1 & " " & $2 }
  assign       { $$.val := " () " & $1 }
  dims_assign  { $$.val := " " & $1 & " " & $2 }
  bare         { $$.val := "" }

continuous_assign: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := "(assign " & $1 & ")" }

assign_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  cons    { $$.val := $1 & " " & $2 }

assign_one: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := Wrap2("=", $1, $2) }

always_construct: { val : TEXT; cnt : INTEGER; }
  always  { $$.val := "(always " & $1 & " " & $2 & ")" }
  comb    { $$.val := "(always_comb " & $1 & ")" }
  ff      { $$.val := "(always_ff " & $1 & " " & $2 & ")" }
  latch       { $$.val := "(always_latch " & $1 & " " & $2 & ")" }
  latch_nosens { $$.val := "(always_latch " & $1 & ")" }

sensitivity: { val : TEXT; cnt : INTEGER; }
  list     { $$.val := "(sens " & $1 & ")" }
  star     { $$.val := "(sens *)" }
  at_star  { $$.val := "(sens *)" }

sensitivity_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  or      { $$.val := $1 & " " & $2 }
  comma   { $$.val := $1 & " " & $2 }

sensitivity_item: { val : TEXT; cnt : INTEGER; }
  posedge  { $$.val := "(posedge " & $1 & ")" }
  negedge  { $$.val := "(negedge " & $1 & ")" }
  expr     { $$.val := $1 }

statement: { val : TEXT; cnt : INTEGER; }
  seq_block      { $$.val := "(begin " & $1 & " " & $2 & " " & $3 & ")" }
  if_stmt        { $$.val := "(if " & $1 & " " & $2 & " " & $3 & ")" }
  case_stmt      { $$.val := "(" & $1 & " " & $2 & " " & $3 & ")" }
  case_inside_stmt { $$.val := "(" & $1 & "-inside " & $2 & " " & $3 & ")" }
  for_stmt       { $$.val := "(for " & $1 & " " & $2 & " " & $3 & " " & $4 & ")" }
  while_stmt     { $$.val := "(while " & $1 & " " & $2 & ")" }
  repeat_stmt    { $$.val := "(repeat " & $1 & " " & $2 & ")" }
  forever_stmt   { $$.val := "(forever " & $1 & ")" }
  assign_stmt    { $$.val := Wrap2("=", $1, $2) }
  nb_assign_stmt { $$.val := Wrap2("<=", $1, $2) }
  force_assign   { $$.val := Wrap2("assign", $1, $2) }
  call_stmt      { $$.val := $1 }
  return_stmt    { $$.val := "(return " & $1 & ")" }
  passign_stmt   { $$.val := "(+= " & $1 & " " & $2 & ")" }
  massign_stmt   { $$.val := "(-= " & $1 & " " & $2 & ")" }
  tassign_stmt   { $$.val := "(*= " & $1 & " " & $2 & ")" }
  dassign_stmt   { $$.val := "(/= " & $1 & " " & $2 & ")" }
  rassign_stmt   { $$.val := "(%= " & $1 & " " & $2 & ")" }
  aassign_stmt   { $$.val := "(&= " & $1 & " " & $2 & ")" }
  oassign_stmt   { $$.val := "(|= " & $1 & " " & $2 & ")" }
  xassign_stmt   { $$.val := "(^= " & $1 & " " & $2 & ")" }
  lsassign_stmt  { $$.val := "(<<= " & $1 & " " & $2 & ")" }
  rsassign_stmt  { $$.val := "(>>= " & $1 & " " & $2 & ")" }
  inc_stmt       { $$.val := "(++ " & $1 & ")" }
  dec_stmt       { $$.val := "(-- " & $1 & ")" }
  preinc_stmt    { $$.val := "(++ " & $1 & ")" }
  predec_stmt    { $$.val := "(-- " & $1 & ")" }
  assert_stmt    { $$.val := "(assert " & $1 & " " & $2 & ")" }
  delay_stmt     { $$.val := "(delay " & $1 & " " & $2 & ")" }
  event_ctrl_stmt { $$.val := "(event-ctrl " & $1 & " " & $2 & ")" }
  void_cast      { $$.val := Wrap("void-cast", $1) }
  null_stmt      { $$.val := "(null)" }

opt_block_name: { val : TEXT; cnt : INTEGER; }
  yes    { $$.val := $1 }
  empty  { $$.val := "" }

opt_end_name: { val : TEXT; cnt : INTEGER; }
  yes    { $$.val := "" }
  empty  { $$.val := "" }

opt_else: { val : TEXT; cnt : INTEGER; }
  yes    { $$.val := $1 }
  empty  { $$.val := "()" }

opt_assert_else: { val : TEXT; cnt : INTEGER; }
  yes    { $$.val := $1 }
  bare   { $$.val := "()" }

case_keyword: { val : TEXT; cnt : INTEGER; }
  case           { $$.val := "case" }
  casez          { $$.val := "casez" }
  casex          { $$.val := "casex" }
  unique_case    { $$.val := "unique-case" }
  unique_casez   { $$.val := "unique-casez" }
  unique_casex   { $$.val := "unique-casex" }
  priority_case  { $$.val := "priority-case" }
  priority_casez { $$.val := "priority-casez" }
  priority_casex { $$.val := "priority-casex" }

case_item_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  cons    { $$.val := $1 & " " & $2 }

case_item: { val : TEXT; cnt : INTEGER; }
  exprs         { $$.val := "(" & $1 & " " & $2 & ")" }
  default_colon { $$.val := "(default " & $1 & ")" }
  default_bare  { $$.val := "(default " & $1 & ")" }

case_expr_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  cons    { $$.val := $1 & " " & $2 }

case_expr_item: { val : TEXT; cnt : INTEGER; }
  expr    { $$.val := $1 }
  range   { $$.val := "[" & $1 & ":" & $2 & "]" }

for_init: { val : TEXT; cnt : INTEGER; }
  decl    { $$.val := "(decl " & $1 & " " & $2 & " " & $3 & ")" }
  assign  { $$.val := Wrap2("=", $1, $2) }

for_step: { val : TEXT; cnt : INTEGER; }
  assign   { $$.val := Wrap2("=", $1, $2) }
  inc      { $$.val := "(++ " & $1 & ")" }
  dec      { $$.val := "(-- " & $1 & ")" }
  preinc   { $$.val := "(++ " & $1 & ")" }
  predec   { $$.val := "(-- " & $1 & ")" }
  passign  { $$.val := "(+= " & $1 & " " & $2 & ")" }
  massign  { $$.val := "(-= " & $1 & " " & $2 & ")" }

statement_list: { val : TEXT; cnt : INTEGER; }
  empty      { $$.val := "" }
  cons       { $$.val := Seq($1, $2) }
  local_decl      { $$.val := Seq($1, $2) }
  auto_decl       { $$.val := Seq($1, $2) }
  static_decl     { $$.val := Seq($1, $2) }
  local_param     { $$.val := Seq($1, $2) }
  local_parameter { $$.val := Seq($1, $2) }

subroutine_call: { val : TEXT; cnt : INTEGER; }
  func    { $$.val := "(call " & $1 & " " & $2 & ")" }
  system  { $$.val := "(syscall " & $1 & " " & $2 & ")" }

opt_paren_args: { val : TEXT; cnt : INTEGER; }
  yes    { $$.val := $1 }
  empty  { $$.val := "" }

opt_arg_list: { val : TEXT; cnt : INTEGER; }
  yes    { $$.val := $1 }
  empty  { $$.val := "" }

arg_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  cons    { $$.val := $1 & " " & $2 }

arg_item: { val : TEXT; cnt : INTEGER; }
  expr       { $$.val := $1 }
  named      { $$.val := "(named " & $1 & " " & $2 & ")" }
  empty_arg  { $$.val := "()" }

function_declaration: { val : TEXT; cnt : INTEGER; }
  x          { $$.val := "(function " & $1 & " " & $2 & " " & $3 & " " & $4 & ")" }
  user_type  { $$.val := "(function " & $1 & " " & $2 & " " & $3 & " " & $4 & ")" }
  user_type_dims { $$.val := "(function " & $1 & " (" & $2 & " " & $3 & ") " & $4 & " " & $5 & ")" }
  bare       { $$.val := "(function " & $1 & " () " & $2 & " " & $3 & ")" }

opt_automatic: { val : TEXT; cnt : INTEGER; }
  yes    { $$.val := "automatic" }
  empty  { $$.val := "" }

opt_data_type_or_void: { val : TEXT; cnt : INTEGER; }
  data            { $$.val := $1 }
  void            { $$.val := "void" }
  logic           { $$.val := "logic " & $1 & " " & $2 }
  reg             { $$.val := "reg " & $1 & " " & $2 }
  integer         { $$.val := "integer" }
  implicit_dims   { $$.val := $1 & " " & $2 }

function_body: { val : TEXT; cnt : INTEGER; }
  empty  { $$.val := "" }
  cons   { $$.val := Seq($1, $2) }

function_body_item: { val : TEXT; cnt : INTEGER; }
  decl           { $$.val := $1 }
  net_decl       { $$.val := $1 }
  auto_decl      { $$.val := "(automatic " & $1 & ")" }
  param_decl     { $$.val := $1 }
  localparam_decl { $$.val := $1 }
  stmt           { $$.val := $1 }

task_declaration: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := "(task " & $1 & " " & $2 & " " & $3 & ")" }

task_body: { val : TEXT; cnt : INTEGER; }
  empty  { $$.val := "" }
  cons   { $$.val := Seq($1, $2) }

task_body_item: { val : TEXT; cnt : INTEGER; }
  decl      { $$.val := $1 }
  net_decl  { $$.val := $1 }
  stmt      { $$.val := $1 }

opt_end_label: { val : TEXT; cnt : INTEGER; }
  yes    { $$.val := "" }
  empty  { $$.val := "" }

interface_declaration: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := "(interface " & $1 & " " & $2 & " " & $3 & " " & $4 & ")" }

interface_body: { val : TEXT; cnt : INTEGER; }
  empty  { $$.val := "" }
  cons   { $$.val := Seq($1, $2) }

interface_item: { val : TEXT; cnt : INTEGER; }
  net_decl       { $$.val := $1 }
  param_decl     { $$.val := $1 }
  localparam_decl { $$.val := $1 }
  modport        { $$.val := $1 }
  typedef_item   { $$.val := $1 }
  function_item  { $$.val := $1 }
  task_item      { $$.val := $1 }

modport_declaration: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := "(modport " & $1 & " " & $2 & ")" }

modport_port_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  cons    { $$.val := Seq($1, $2) }

modport_port_item: { val : TEXT; cnt : INTEGER; }
  input   { $$.val := "(input " & $1 & ")" }
  output  { $$.val := "(output " & $1 & ")" }
  inout   { $$.val := "(inout " & $1 & ")" }
  ident   { $$.val := $1 }

generate_region: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := "(generate " & $1 & ")" }

generate_body: { val : TEXT; cnt : INTEGER; }
  empty  { $$.val := "" }
  cons   { $$.val := Seq($1, $2) }

generate_item: { val : TEXT; cnt : INTEGER; }
  module_item  { $$.val := $1 }
  if_gen       { $$.val := "(if-generate " & $1 & " " & $2 & " " & $3 & ")" }
  for_gen      { $$.val := "(for-generate " & $1 & " " & $2 & " " & $3 & " " & $4 & ")" }
  begin_gen    { $$.val := "(begin " & $1 & " " & $2 & " " & $3 & ")" }
  sys_call     { $$.val := $1 }

opt_gen_else: { val : TEXT; cnt : INTEGER; }
  yes    { $$.val := $1 }
  empty  { $$.val := "()" }

generate_block: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  block   { $$.val := "(begin " & $1 & " " & $2 & " " & $3 & ")" }

genvar_init: { val : TEXT; cnt : INTEGER; }
  decl    { $$.val := "(genvar " & $1 & " " & $2 & ")" }
  assign  { $$.val := Wrap2("=", "(id " & $1 & ")", $2) }

genvar_step: { val : TEXT; cnt : INTEGER; }
  assign   { $$.val := Wrap2("=", "(id " & $1 & ")", $2) }
  inc      { $$.val := "(++ (id " & $1 & "))" }
  dec      { $$.val := "(-- (id " & $1 & "))" }
  preinc   { $$.val := "(++ (id " & $1 & "))" }
  predec   { $$.val := "(-- (id " & $1 & "))" }
  passign  { $$.val := "(+= (id " & $1 & ") " & $2 & ")" }

module_instantiation: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := "(instance " & $1 & " " & $2 & " " & $3 & ")" }

opt_param_actuals: { val : TEXT; cnt : INTEGER; }
  yes         { $$.val := "(params " & $1 & ")" }
  empty_hash  { $$.val := "(params)" }
  empty       { $$.val := "()" }

inst_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  cons    { $$.val := $1 & " " & $2 }

inst_one: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := "(" & $1 & " " & $2 & " " & $3 & ")" }

opt_connection_list: { val : TEXT; cnt : INTEGER; }
  yes    { $$.val := $1 }
  empty  { $$.val := "" }

connection_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  cons    { $$.val := $1 & " " & $2 }

connection: { val : TEXT; cnt : INTEGER; }
  named          { $$.val := "(named " & $1 & " " & $2 & ")" }
  implicit_named { $$.val := "(named " & $1 & " (id " & $1 & "))" }
  dotstar        { $$.val := "(.*)" }
  positional     { $$.val := $1 }

expression: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := $1 }

cond_expr: { val : TEXT; cnt : INTEGER; }
  single   { $$.val := $1 }
  ternary  { $$.val := "(?: " & $1 & " " & $2 & " " & $3 & ")" }

lor_expr: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  lor     { $$.val := Wrap2("||", $1, $2) }

land_expr: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  land    { $$.val := Wrap2("&&", $1, $2) }

bor_expr: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  bor     { $$.val := Wrap2("|", $1, $2) }

bxor_expr: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  bxor    { $$.val := Wrap2("^", $1, $2) }
  bxnor   { $$.val := Wrap2("~^", $1, $2) }

band_expr: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  band    { $$.val := Wrap2("&", $1, $2) }

eq_expr: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  eq      { $$.val := Wrap2("==", $1, $2) }
  neq     { $$.val := Wrap2("!=", $1, $2) }
  ceq     { $$.val := Wrap2("===", $1, $2) }
  cne     { $$.val := Wrap2("!==", $1, $2) }
  weq     { $$.val := Wrap2("==?", $1, $2) }
  wne     { $$.val := Wrap2("!=?", $1, $2) }

rel_expr: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  lt      { $$.val := Wrap2("<", $1, $2) }
  gt      { $$.val := Wrap2(">", $1, $2) }
  leq     { $$.val := Wrap2("<=", $1, $2) }
  geq     { $$.val := Wrap2(">=", $1, $2) }
  inside  { $$.val := "(inside " & $1 & " " & $2 & ")" }

inside_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  cons    { $$.val := $1 & " " & $2 }

inside_item: { val : TEXT; cnt : INTEGER; }
  expr    { $$.val := $1 }
  range   { $$.val := "[" & $1 & ":" & $2 & "]" }

shift_expr: { val : TEXT; cnt : INTEGER; }
  single   { $$.val := $1 }
  lshift   { $$.val := Wrap2("<<", $1, $2) }
  rshift   { $$.val := Wrap2(">>", $1, $2) }
  alshift  { $$.val := Wrap2("<<<", $1, $2) }
  arshift  { $$.val := Wrap2(">>>", $1, $2) }

add_expr: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  add     { $$.val := Wrap2("+", $1, $2) }
  sub     { $$.val := Wrap2("-", $1, $2) }

mul_expr: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  mul     { $$.val := Wrap2("*", $1, $2) }
  div     { $$.val := Wrap2("/", $1, $2) }
  rem     { $$.val := Wrap2("%", $1, $2) }

unary_expr: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  uminus  { $$.val := "(- " & $1 & ")" }
  uplus   { $$.val := "(+ " & $1 & ")" }
  lnot    { $$.val := "(! " & $1 & ")" }
  bnot    { $$.val := "(~ " & $1 & ")" }
  rand    { $$.val := "(&-reduce " & $1 & ")" }
  rnand   { $$.val := "(~&-reduce " & $1 & ")" }
  ror     { $$.val := "(|-reduce " & $1 & ")" }
  rnor    { $$.val := "(~|-reduce " & $1 & ")" }
  rxor    { $$.val := "(^-reduce " & $1 & ")" }
  rxnor   { $$.val := "(~^-reduce " & $1 & ")" }

pow_expr: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  pow     { $$.val := Wrap2("**", $1, $2) }

postfix_expr: { val : TEXT; cnt : INTEGER; }
  single     { $$.val := $1 }
  index      { $$.val := "(index " & $1 & " " & $2 & ")" }
  range_sel  { $$.val := "(range " & $1 & " " & $2 & " " & $3 & ")" }
  psel       { $$.val := "(+: " & $1 & " " & $2 & " " & $3 & ")" }
  msel       { $$.val := "(-: " & $1 & " " & $2 & " " & $3 & ")" }
  member     { $$.val := "(field " & $1 & " " & $2 & ")" }
  call       { $$.val := "(call " & $1 & " " & $2 & ")" }
  cast           { $$.val := "(cast " & $1 & " " & $2 & ")" }
  type_cast      { $$.val := "(cast " & $1 & " " & $2 & ")" }

cast_type: { val : TEXT; cnt : INTEGER; }
  int        { $$.val := "int" }
  logic      { $$.val := "logic" }
  bit        { $$.val := "bit" }
  byte       { $$.val := "byte" }
  shortint   { $$.val := "shortint" }
  longint    { $$.val := "longint" }
  integer    { $$.val := "integer" }
  signed     { $$.val := "signed" }
  unsigned   { $$.val := "unsigned" }

primary_expr: { val : TEXT; cnt : INTEGER; }
  number        { $$.val := $1 }
  string        { $$.val := $1 }
  ident         { $$.val := $1 }
  sysident      { $$.val := "(sys " & $1 & ")" }
  paren         { $$.val := $1 }
  concat        { $$.val := "(concat " & $1 & ")" }
  replicate     { $$.val := "(replicate " & $1 & " " & $2 & ")" }
  empty_concat        { $$.val := "(concat)" }
  stream_left         { $$.val := "(stream-left " & $1 & " " & $2 & ")" }
  stream_right        { $$.val := "(stream-right " & $1 & " " & $2 & ")" }
  struct_lit          { $$.val := "(struct-lit " & $1 & ")" }
  struct_lit_default  { $$.val := "(struct-lit-default " & $1 & ")" }
  unsigned_kw         { $$.val := "unsigned" }
  signed_kw           { $$.val := "signed" }

stream_slice: { val : TEXT; cnt : INTEGER; }
  number  { $$.val := $1 }
  ident   { $$.val := $1 }
  empty   { $$.val := "()" }

assign_pattern_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  cons    { $$.val := $1 & " " & $2 }

assign_pattern_item: { val : TEXT; cnt : INTEGER; }
  named       { $$.val := $1 & ": " & $2 }
  default     { $$.val := "default: " & $1 }
  positional  { $$.val := $1 }

hierarchical_id: { val : TEXT; cnt : INTEGER; }
  simple  { $$.val := "(id " & $1 & ")" }
  scoped  { $$.val := "(:: " & $1 & " " & $2 & ")" }
  dotted  { $$.val := "(field " & $1 & " " & $2 & ")" }

expression_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  cons    { $$.val := $1 & " " & $2 }

opt_expression: { val : TEXT; cnt : INTEGER; }
  yes    { $$.val := $1 }
  empty  { $$.val := "()" }

lvalue: { val : TEXT; cnt : INTEGER; }
  ident      { $$.val := $1 }
  index      { $$.val := "(index " & $1 & " " & $2 & ")" }
  range_sel  { $$.val := "(range " & $1 & " " & $2 & " " & $3 & ")" }
  psel       { $$.val := "(+: " & $1 & " " & $2 & " " & $3 & ")" }
  msel       { $$.val := "(-: " & $1 & " " & $2 & " " & $3 & ")" }
  member     { $$.val := "(field " & $1 & " " & $2 & ")" }
  concat     { $$.val := "(concat " & $1 & ")" }

lvalue_list: { val : TEXT; cnt : INTEGER; }
  single  { $$.val := $1 }
  cons    { $$.val := $1 & " " & $2 }
