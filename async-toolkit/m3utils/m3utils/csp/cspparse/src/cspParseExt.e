%source csp.t csp.y
%import cspLexExt cspParse
%module {
IMPORT Text, Fmt;

CONST
  SK_ASSIGN = 1; SK_PASSIGN = 2; SK_MASSIGN = 3;
  SK_TASSIGN = 4; SK_DASSIGN = 5; SK_RASSIGN = 6;
  SK_AASSIGN = 7; SK_OASSIGN = 8; SK_XASSIGN = 9;
  SK_LSASSIGN = 10; SK_RSASSIGN = 11;
  SK_INC = 12; SK_DEC = 13;
  SK_SEND = 14; SK_RECV = 15;
  SK_BSET = 16; SK_BCLR = 17;
  SK_EXPR = 18;

VAR
  curType   : TEXT := "";
  curConst  : TEXT := "#f";
  funcList  : TEXT := "";
  structList: TEXT := "";

PROCEDURE MakeStmt(lv : TEXT; kind : INTEGER; rhs : TEXT) : TEXT =
  BEGIN
    CASE kind OF
    | SK_ASSIGN     => RETURN "(assign " & lv & " " & rhs & ")"
    | SK_PASSIGN    => RETURN "(assign-operate + " & lv & " " & rhs & ")"
    | SK_MASSIGN    => RETURN "(assign-operate - " & lv & " " & rhs & ")"
    | SK_TASSIGN    => RETURN "(assign-operate * " & lv & " " & rhs & ")"
    | SK_DASSIGN    => RETURN "(assign-operate / " & lv & " " & rhs & ")"
    | SK_RASSIGN    => RETURN "(assign-operate % " & lv & " " & rhs & ")"
    | SK_AASSIGN    => RETURN "(assign-operate & " & lv & " " & rhs & ")"
    | SK_OASSIGN    => RETURN "(assign-operate | " & lv & " " & rhs & ")"
    | SK_XASSIGN    => RETURN "(assign-operate ^ " & lv & " " & rhs & ")"
    | SK_LSASSIGN   => RETURN "(assign-operate << " & lv & " " & rhs & ")"
    | SK_RSASSIGN   => RETURN "(assign-operate >> " & lv & " " & rhs & ")"
    | SK_INC        => RETURN "(assign-operate + " & lv & " 10_1)"
    | SK_DEC        => RETURN "(assign-operate - " & lv & " 10_1)"
    | SK_SEND       => RETURN "(send " & lv & " " & rhs & ")"
    | SK_RECV       => RETURN "(recv " & lv & " " & rhs & ")"
    | SK_BSET       => RETURN "(assign " & lv & " #t)"
    | SK_BCLR       => RETURN "(assign " & lv & " #f)"
    | SK_EXPR       => RETURN "(eval " & lv & ")"
    ELSE <* ASSERT FALSE *>
    END
  END MakeStmt;

PROCEDURE IntLit(src : TEXT) : TEXT =
  VAR len := Text.Length(src);
  BEGIN
    IF len = 0 THEN RETURN "10_0" END;
    (* Check for 0x or 0X prefix *)
    IF len >= 2 AND Text.GetChar(src, 0) = '0' AND
       (Text.GetChar(src, 1) = 'x' OR Text.GetChar(src, 1) = 'X') THEN
      VAR rest := StripUnderscores(Text.Sub(src, 2));
      BEGIN
        RETURN "16_" & ToUpper(rest)
      END
    END;
    (* Check for 0b or 0B prefix *)
    IF len >= 2 AND Text.GetChar(src, 0) = '0' AND
       (Text.GetChar(src, 1) = 'b' OR Text.GetChar(src, 1) = 'B') THEN
      VAR rest := StripUnderscores(Text.Sub(src, 2));
          dec  := BinToDec(rest);
      BEGIN
        RETURN "10_" & dec
      END
    END;
    (* Check for radix notation: digits followed by _ *)
    FOR i := 0 TO len - 1 DO
      IF Text.GetChar(src, i) = '_' AND i > 0 THEN
        (* Already in radix notation, pass through unchanged *)
        RETURN src
      END;
      IF NOT (Text.GetChar(src, i) >= '0' AND Text.GetChar(src, i) <= '9') THEN
        EXIT
      END
    END;
    (* Plain decimal *)
    RETURN "10_" & StripUnderscores(src)
  END IntLit;

PROCEDURE StripUnderscores(s : TEXT) : TEXT =
  VAR r := ""; len := Text.Length(s); c : CHAR;
  BEGIN
    FOR i := 0 TO len - 1 DO
      c := Text.GetChar(s, i);
      IF c # '_' THEN r := r & Text.FromChar(c) END
    END;
    RETURN r
  END StripUnderscores;

PROCEDURE ToUpper(s : TEXT) : TEXT =
  VAR r := ""; len := Text.Length(s); c : CHAR;
  BEGIN
    FOR i := 0 TO len - 1 DO
      c := Text.GetChar(s, i);
      IF c >= 'a' AND c <= 'f' THEN
        c := VAL(ORD(c) - ORD('a') + ORD('A'), CHAR)
      END;
      r := r & Text.FromChar(c)
    END;
    RETURN r
  END ToUpper;

PROCEDURE BinToDec(bin : TEXT) : TEXT =
  VAR val := 0; len := Text.Length(bin); c : CHAR;
  BEGIN
    FOR i := 0 TO len - 1 DO
      c := Text.GetChar(bin, i);
      IF c = '1' THEN val := val * 2 + 1
      ELSIF c = '0' THEN val := val * 2
      END
    END;
    RETURN Fmt.Int(val)
  END BinToDec;

PROCEDURE WrapSeq(inner : TEXT; cnt : INTEGER) : TEXT =
  BEGIN
    IF cnt > 1 THEN
      RETURN "(sequence " & inner & ")"
    ELSE
      RETURN inner
    END
  END WrapSeq;

PROCEDURE Seq(a, b : TEXT) : TEXT =
  BEGIN
    IF Text.Empty(a) THEN RETURN b
    ELSIF Text.Empty(b) THEN RETURN a
    ELSE RETURN a & " " & b
    END
  END Seq;

PROCEDURE ReplacePrefix(s, old, new : TEXT) : TEXT =
  VAR olen := Text.Length(old);
  BEGIN
    IF Text.Length(s) >= olen AND Text.Equal(Text.Sub(s, 0, olen), old) THEN
      RETURN new & Text.Sub(s, olen)
    END;
    RETURN s
  END ReplacePrefix;
}
%interface {
}
%public {
  scmResult : TEXT;
  scmBody   : TEXT;
}

program: { val : TEXT; cnt : INTEGER; }
  x  {
    self.scmBody := $2;
    self.scmResult := "(" & funcList & ") (" & structList & ") () () () " &
      WrapSeq($2, $2.cnt);
    $$.val := self.scmResult;
    funcList := "";
    structList := ""
  }

top_list: { val : TEXT; cnt : INTEGER; }
  empty  { $$.val := "" }
  func   { $$.val := $1; $$.cnt := $1.cnt }
  struct { $$.val := $1; $$.cnt := $1.cnt }

function_decl: { val : TEXT; cnt : INTEGER; }
  typed   {
    VAR f := "(function " & $1 & " " & $2 & " " & $3;
    BEGIN
      funcList := Seq(funcList, f & " (sequence " & $4 & "))");
      $$.val := ""
    END
  }
  untyped {
    VAR f := "(function " & $1 & " " & $2 & " ()";
    BEGIN
      funcList := Seq(funcList, f & " (sequence " & $3 & "))");
      $$.val := ""
    END
  }

structure_decl: { val : TEXT; cnt : INTEGER; }
  x  {
    structList := Seq(structList, "(structure-decl " & $1 & " (" & $2 & "))");
    $$.val := ""
  }

opt_seq_stmt: { val : TEXT; cnt : INTEGER; }
  yes   { $$.val := $1; $$.cnt := $1.cnt }
  empty { $$.val := "skip"; $$.cnt := 1 }

sequential_statement: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1; $$.cnt := $1.cnt }
  cons   { $$.val := $1 & " " & $2; $$.cnt := $1.cnt + $2.cnt }
  trail  { $$.val := $1; $$.cnt := $1.cnt }

sequential_part: { val : TEXT; cnt : INTEGER; }
  var { $$.val := $1; $$.cnt := $1.cnt }
  par {
    IF $1.cnt > 1 THEN
      $$.val := "(parallel " & $1 & ")"; $$.cnt := 1
    ELSE
      $$.val := $1; $$.cnt := 1
    END
  }

parallel_statement: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1; $$.cnt := 1 }
  cons   { $$.val := $1 & " " & $2; $$.cnt := $1.cnt + 1 }

var_statement: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := $1; $$.cnt := $1.cnt }

statement: { val : TEXT; cnt : INTEGER; }
  paren      { $$.val := "(sequence " & $1 & ")"; $$.cnt := 1 }
  sel        { $$.val := $1; $$.cnt := 1 }
  rep        { $$.val := $1; $$.cnt := 1 }
  lp         { $$.val := $1; $$.cnt := 1 }
  hash       { $$.val := $1; $$.cnt := 1 }
  error      { $$.val := "(error)"; $$.cnt := 1 }
  skip       { $$.val := "skip"; $$.cnt := 1 }
  lval       { $$.val := MakeStmt($1, $2.cnt, $2); $$.cnt := 1 }

stmt_suffix: { val : TEXT; cnt : INTEGER; }
  assign     { $$.val := $1; $$.cnt := SK_ASSIGN }
  passign    { $$.val := $1; $$.cnt := SK_PASSIGN }
  massign    { $$.val := $1; $$.cnt := SK_MASSIGN }
  tassign    { $$.val := $1; $$.cnt := SK_TASSIGN }
  dassign    { $$.val := $1; $$.cnt := SK_DASSIGN }
  rassign    { $$.val := $1; $$.cnt := SK_RASSIGN }
  aassign    { $$.val := $1; $$.cnt := SK_AASSIGN }
  oassign    { $$.val := $1; $$.cnt := SK_OASSIGN }
  xassign    { $$.val := $1; $$.cnt := SK_XASSIGN }
  lsassign   { $$.val := $1; $$.cnt := SK_LSASSIGN }
  rsassign   { $$.val := $1; $$.cnt := SK_RSASSIGN }
  inc        { $$.val := ""; $$.cnt := SK_INC }
  dec        { $$.val := ""; $$.cnt := SK_DEC }
  send       { $$.val := $1; $$.cnt := SK_SEND }
  recv       { $$.val := $1; $$.cnt := SK_RECV }
  bset       { $$.val := ""; $$.cnt := SK_BSET }
  bclr       { $$.val := ""; $$.cnt := SK_BCLR }
  expr_stmt  { $$.val := ""; $$.cnt := SK_EXPR }

hash_start: { val : TEXT; cnt : INTEGER; }
  sel          { $$.val := "(if " & $1 & ")" }
  peek_assign  { $$.val := "(assign " & $2 & " (peek " & $1 & "))" }
  peek_stmt    { $$.val := "(eval (peek " & $1 & "))" }
  probe_stmt   { $$.val := "(eval (probe " & $1 & "))" }

selection_statement: { val : TEXT; cnt : INTEGER; }
  guard { $$.val := "(" & $1 & ")" }
  wait  { $$.val := "(if (" & $1 & " (sequence skip)))" }

repetition_statement: { val : TEXT; cnt : INTEGER; }
  guard    {
    $$.val := "(" & ReplacePrefix($1, "if ", "do ") & ")";
    $$.val := ReplacePrefix($$.val, "(if ", "(do ");
    $$.val := ReplacePrefix($$.val, "(nondet-if ", "(nondet-do ")
  }
  infinite { $$.val := "(do (#t (sequence " & $1 & ")))" }

loop_statement: { val : TEXT; cnt : INTEGER; }
  langl { $$.val := "(sequential-loop " & $1 & " " & $2 & " (sequence " & $3 & "))" }
  sloop { $$.val := "(sequential-loop " & $1 & " " & $2 & " (sequence " & $3 & "))" }
  bloop { $$.val := "(parallel-loop " & $1 & " " & $2 & " (sequence " & $3 & "))" }
  cloop { $$.val := "(parallel-loop " & $1 & " " & $2 & " (sequence " & $3 & "))" }

guard_commands: { val : TEXT; cnt : INTEGER; }
  determ    { $$.val := "if " & $1 }
  nondeterm { $$.val := "nondet-if " & $1 }

det_guard_commands: { val : TEXT; cnt : INTEGER; }
  noelse   { $$.val := $1 }
  withelse { $$.val := $1 & " " & $2 }

det_guard_noelse_commands: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  cons   { $$.val := $1 & " " & $2 }

det_guard_command: { val : TEXT; cnt : INTEGER; }
  simple     { $$.val := $1 }
  loop       { $$.val := "(parallel-loop " & $1 & " " & $2 & " " & $3 & ")" }
  loop_paren { $$.val := "(parallel-loop " & $1 & " " & $2 & " " & $3 & ")" }

det_guard_inner: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  cons   { $$.val := $1 & " " & $2 }

det_guard_body: { val : TEXT; cnt : INTEGER; }
  simple     { $$.val := $1 }
  loop       { $$.val := "(parallel-loop " & $1 & " " & $2 & " " & $3 & ")" }
  loop_paren { $$.val := "(parallel-loop " & $1 & " " & $2 & " " & $3 & ")" }

non_det_guard_commands: { val : TEXT; cnt : INTEGER; }
  simple { $$.val := $1 }
  linked { $$.val := $1 }

non_det_guard_simple: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  cons   { $$.val := $1 & " " & $2 }

non_det_guard_command: { val : TEXT; cnt : INTEGER; }
  simple     { $$.val := $1 }
  loop       { $$.val := "(parallel-loop " & $1 & " " & $2 & " " & $3 & ")" }
  loop_paren { $$.val := "(parallel-loop " & $1 & " " & $2 & " " & $3 & ")" }

non_det_guard_inner: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  cons   { $$.val := $1 & " " & $2 }

non_det_guard_body: { val : TEXT; cnt : INTEGER; }
  simple     { $$.val := $1 }
  loop       { $$.val := "(parallel-loop " & $1 & " " & $2 & " " & $3 & ")" }
  loop_paren { $$.val := "(parallel-loop " & $1 & " " & $2 & " " & $3 & ")" }

non_det_guard_linked: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := $1 }

linked_guard_list: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  cons   { $$.val := $1 & " " & $2 }

linked_guard_command: { val : TEXT; cnt : INTEGER; }
  simple     { $$.val := "(" & $1 & " (sequence " & $3 & "))" }
  loop       { $$.val := "(parallel-loop " & $1 & " " & $2 & " " & $3 & ")" }
  loop_paren { $$.val := "(parallel-loop " & $1 & " " & $2 & " " & $3 & ")" }

linked_guard_inner: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  cons   { $$.val := $1 & " " & $2 }

linked_guard_body: { val : TEXT; cnt : INTEGER; }
  simple     { $$.val := "(" & $1 & " (sequence " & $3 & "))" }
  loop       { $$.val := "(parallel-loop " & $1 & " " & $2 & " " & $3 & ")" }
  loop_paren { $$.val := "(parallel-loop " & $1 & " " & $2 & " " & $3 & ")" }

guard_command_simple: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := "(" & $1 & " (sequence " & $2 & "))" }

guard_else_command: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := "(else (sequence " & $1 & "))" }

linkage_specifier: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := "(@" & $1 & ")" }

linkage_terms: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  cons   { $$.val := $1 & " " & $2 }

linkage_term: { val : TEXT; cnt : INTEGER; }
  expr { $$.val := $2 }
  loop { $$.val := "(parallel-loop " & $1 & " " & $2 & " " & $3 & ")" }

linkage_term_or_paren: { val : TEXT; cnt : INTEGER; }
  bare  { $$.val := $1 }
  paren { $$.val := $1 }

opt_tilde: { val : TEXT; cnt : INTEGER; }
  yes { $$.val := "~" }
  no  { $$.val := "" }

linkage_expr: { val : TEXT; cnt : INTEGER; }
  base    { $$.val := "(id " & $1 & ")" }
  dot_id  { $$.val := "(member-access " & $1 & " " & $2 & ")" }
  dot_int { $$.val := "(member-access " & $1 & " " & IntLit($2) & ")" }
  array   { $$.val := "(array-access " & $1 & " " & $2 & ")" }

expression: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := $1 }

cond_or_expr: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  or     { $$.val := "(|| " & $1 & " " & $2 & ")" }

cond_and_expr: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  and    { $$.val := "(&& " & $1 & " " & $2 & ")" }

or_expr: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  or     { $$.val := "(| " & $1 & " " & $2 & ")" }

xor_expr: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  xor    { $$.val := "(^ " & $1 & " " & $2 & ")" }

and_expr: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  and    { $$.val := "(& " & $1 & " " & $2 & ")" }

eq_expr: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  eq     { $$.val := "(== " & $1 & " " & $2 & ")" }
  neq    { $$.val := "(!= " & $1 & " " & $2 & ")" }

rel_expr: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  lt     { $$.val := "(< " & $1 & " " & $2 & ")" }
  gt     { $$.val := "(> " & $1 & " " & $2 & ")" }
  leq    { $$.val := "(<= " & $1 & " " & $2 & ")" }
  geq    { $$.val := "(>= " & $1 & " " & $2 & ")" }

shift_expr: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  lshift { $$.val := "(<< " & $1 & " " & $2 & ")" }
  rshift { $$.val := "(>> " & $1 & " " & $2 & ")" }

add_expr: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  add    { $$.val := "(+ " & $1 & " " & $2 & ")" }
  sub    { $$.val := "(- " & $1 & " " & $2 & ")" }

mul_expr: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  mul    { $$.val := "(* " & $1 & " " & $2 & ")" }
  div    { $$.val := "(/ " & $1 & " " & $2 & ")" }
  rem    { $$.val := "(% " & $1 & " " & $2 & ")" }

unary_expr: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  uminus { $$.val := "(- " & $1 & ")" }
  utilde { $$.val := "(not " & $1 & ")" }

exp_expr: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  exp    { $$.val := "(** " & $1 & " " & $2 & ")" }

primary_expression: { val : TEXT; cnt : INTEGER; }
  integer    { $$.val := IntLit($1) }
  true       { $$.val := "#t" }
  false      { $$.val := "#f" }
  string_lit { $$.val := $1 }
  paren      { $$.val := $1 }
  recv_expr  { $$.val := "(recv-expression " & $1 & ")" }
  peek_expr  { $$.val := "(peek " & $1 & ")" }
  probe_expr { $$.val := "(probe " & $1 & ")" }
  lvalue     { $$.val := $1 }
  loop_expr  { $$.val := $1 }

loop_expression: { val : TEXT; cnt : INTEGER; }
  ploop { $$.val := "(loop-expression " & $1 & " " & $2 & " + " & $3 & ")" }
  mloop { $$.val := "(loop-expression " & $1 & " " & $2 & " * " & $3 & ")" }
  aloop { $$.val := "(loop-expression " & $1 & " " & $2 & " & " & $3 & ")" }
  oloop { $$.val := "(loop-expression " & $1 & " " & $2 & " | " & $3 & ")" }
  xloop { $$.val := "(loop-expression " & $1 & " " & $2 & " ^ " & $3 & ")" }

lvalue: { val : TEXT; cnt : INTEGER; }
  ident    { $$.val := "(id " & $1 & ")" }
  string   { $$.val := "(id string)" }
  array    {
    VAR lv := $1; el := $2; elcnt := $2.cnt; i := 0;
    BEGIN
      $$.val := lv;
      WHILE i < elcnt DO
        VAR idx : TEXT; rest := el; pos := 0;
        BEGIN
          WHILE pos < Text.Length(rest) DO
            IF Text.GetChar(rest, pos) = '\001' THEN
              idx := Text.Sub(rest, 0, pos);
              el := Text.Sub(rest, pos+1);
              EXIT
            END;
            INC(pos)
          END;
          IF pos >= Text.Length(rest) THEN idx := rest; el := "" END;
          $$.val := "(array-access " & $$.val & " " & idx & ")";
          INC(i)
        END
      END
    END }
  bitrange {
    IF Text.Empty($3) THEN
      $$.val := "(bits " & $1 & " () " & $2 & ")"
    ELSE
      $$.val := "(bits " & $1 & " " & $2 & " " & $3 & ")"
    END }
  call     {
    IF Text.Empty($2) THEN
      $$.val := "(apply " & $1 & ")"
    ELSE
      $$.val := "(apply " & $1 & " " & $2 & ")"
    END }
  dot_id   { $$.val := "(member-access " & $1 & " " & $2 & ")" }
  dot_int  { $$.val := "(member-access " & $1 & " " & IntLit($2) & ")" }
  member   { $$.val := "(structure-access " & $1 & " " & $2 & ")" }

expression_list: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1; $$.cnt := 1 }
  cons   { $$.val := $1 & "\001" & $2; $$.cnt := $1.cnt + 1 }

opt_expression_list: { val : TEXT; cnt : INTEGER; }
  yes   { $$.val := $1 }
  empty { $$.val := "" }

opt_colon_expr: { val : TEXT; cnt : INTEGER; }
  yes   { $$.val := $1 }
  empty { $$.val := "" }

opt_expression: { val : TEXT; cnt : INTEGER; }
  yes   { $$.val := $1 }
  empty { $$.val := "()" }

opt_lvalue: { val : TEXT; cnt : INTEGER; }
  yes   { $$.val := $1 }
  empty { $$.val := "()" }

range: { val : TEXT; cnt : INTEGER; }
  range { $$.val := "(range " & $1 & " " & $2 & ")" }
  count { $$.val := "(range 10_0 (- " & $1 & " 10_1))" }

declaration_list: { val : TEXT; cnt : INTEGER; }
  single { $$.val := "(" & $1 & ")"; $$.cnt := 1 }
  cons   { $$.val := $1 & " (" & $2 & ")"; $$.cnt := $1.cnt + 1 }
  trail  { $$.val := $1; $$.cnt := $1.cnt }

opt_decl_list: { val : TEXT; cnt : INTEGER; }
  yes   { $$.val := "(" & $1 & ")"; $$.cnt := $1.cnt }
  empty { $$.val := "()"; $$.cnt := 0 }

declaration: { val : TEXT; cnt : INTEGER; }
  x  { $$.val := $2; $$.cnt := $2.cnt }

type: { val : TEXT; cnt : INTEGER; }
  int     {
    curConst := $1;
    IF Text.Empty($2) THEN
      curType := "(integer " & curConst & " #f () ())"
    ELSE
      curType := "(integer " & curConst & " #f " & $2 & " ())"
    END;
    $$.val := curType
  }
  sint    {
    curConst := $1;
    curType := "(integer " & curConst & " #t " & $2 & " ())";
    $$.val := curType
  }
  boolean {
    curConst := $1;
    curType := "(boolean " & curConst & ")";
    $$.val := curType
  }
  bool    {
    curConst := $1;
    curType := "(boolean " & curConst & ")";
    $$.val := curType
  }
  string  {
    curConst := $1;
    curType := "(string " & curConst & ")";
    $$.val := curType
  }

opt_const: { val : TEXT; cnt : INTEGER; }
  yes { $$.val := "#t" }
  no  { $$.val := "#f" }

opt_paren_expr: { val : TEXT; cnt : INTEGER; }
  yes   { $$.val := $1 }
  empty { $$.val := "" }

declarator_list: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1; $$.cnt := $1.cnt }
  cons   { $$.val := $1 & " " & $2; $$.cnt := $1.cnt + $2.cnt }

declarator: { val : TEXT; cnt : INTEGER; }
  x  {
    VAR name := $2;
        dir  := $1;
        init := $4;
        decl : TEXT;
    BEGIN
      IF Text.Empty(dir) THEN dir := "none" END;
      decl := "(var1 (decl1 (id " & name & ") " & curType & " " & dir & "))";
      IF NOT Text.Empty(init) THEN
        $$.val := decl & " (assign (id " & name & ") " & init & ")";
        $$.cnt := 2
      ELSE
        $$.val := decl;
        $$.cnt := 1
      END
    END
  }

opt_direction: { val : TEXT; cnt : INTEGER; }
  out      { $$.val := "out" }
  in       { $$.val := "in" }
  inout_pm { $$.val := "inout" }
  inout_mp { $$.val := "inout" }
  none     { $$.val := "" }

opt_array_dims: { val : TEXT; cnt : INTEGER; }
  bracket { $$.val := Seq($1, $2) }
  empty   { $$.val := "" }

range_list: { val : TEXT; cnt : INTEGER; }
  single { $$.val := $1 }
  cons   { $$.val := $1 & " " & $2 }

opt_initializer: { val : TEXT; cnt : INTEGER; }
  yes   { $$.val := $1 }
  empty { $$.val := "" }
