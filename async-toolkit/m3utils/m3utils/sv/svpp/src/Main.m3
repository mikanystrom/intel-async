MODULE Main;

(* SystemVerilog preprocessor.

   Handles `define (with parameters), `undef, `ifdef, `ifndef, `else,
   `elsif, `endif, `include, and macro expansion.  Outputs preprocessed
   SV to stdout with line counts preserved (directive lines become blank)
   so that parser error messages refer to correct line numbers.

   Usage: svpp [-I dir]... [-D NAME[=VALUE]]... file.sv
*)

IMPORT Rd, Wr, FileRd, Stdio, Text, TextList, Params,
       TextRefTbl, OSError, Pathname, FS, BoolSeq, Fmt, Env, FmtTime, Time;

<*FATAL ANY*>

(* ================================================================ *)
(* Macro representation                                             *)
(* ================================================================ *)

TYPE
  Macro = REF RECORD
    body    : TEXT;           (* expansion body *)
    params  : TextList.T;    (* NIL for simple macros *)
    defaults: TextList.T;    (* NIL or parallel list of defaults *)
  END;

VAR
  macros := NEW(TextRefTbl.Default).init(256);
  includeDirs: TextList.T := NIL;
  seenFiles := NEW(TextRefTbl.Default).init(64);

(* ================================================================ *)
(* Text utilities                                                   *)
(* ================================================================ *)

PROCEDURE IsIdentChar(c: CHAR): BOOLEAN =
  BEGIN
    RETURN (c >= 'a' AND c <= 'z') OR (c >= 'A' AND c <= 'Z')
        OR (c >= '0' AND c <= '9') OR c = '_';
  END IsIdentChar;

PROCEDURE IsSpace(c: CHAR): BOOLEAN =
  BEGIN
    RETURN c = ' ' OR c = '\t';
  END IsSpace;

PROCEDURE TrimLeft(t: TEXT): TEXT =
  VAR i := 0; len := Text.Length(t);
  BEGIN
    WHILE i < len AND IsSpace(Text.GetChar(t, i)) DO INC(i) END;
    RETURN Text.Sub(t, i);
  END TrimLeft;

PROCEDURE TrimRight(t: TEXT): TEXT =
  VAR i := Text.Length(t) - 1;
  BEGIN
    WHILE i >= 0 AND (IsSpace(Text.GetChar(t, i))
                      OR Text.GetChar(t, i) = '\n'
                      OR Text.GetChar(t, i) = '\r') DO
      DEC(i)
    END;
    RETURN Text.Sub(t, 0, i + 1);
  END TrimRight;

PROCEDURE Trim(t: TEXT): TEXT =
  BEGIN RETURN TrimLeft(TrimRight(t)) END Trim;

(* Read an identifier starting at position pos in t.
   Returns the identifier text (may be empty). *)
PROCEDURE ReadIdent(t: TEXT; pos: INTEGER): TEXT =
  VAR i := pos; len := Text.Length(t);
  BEGIN
    WHILE i < len AND IsIdentChar(Text.GetChar(t, i)) DO INC(i) END;
    RETURN Text.Sub(t, pos, i - pos);
  END ReadIdent;

(* Find character c in t starting at pos.  Returns index or -1. *)
PROCEDURE FindChar(t: TEXT; c: CHAR; pos: INTEGER := 0): INTEGER =
  VAR len := Text.Length(t);
  BEGIN
    FOR i := pos TO len - 1 DO
      IF Text.GetChar(t, i) = c THEN RETURN i END
    END;
    RETURN -1;
  END FindChar;

(* Find matching close paren.  pos points just after the '('.
   Returns index of ')' or -1. *)
PROCEDURE FindCloseParen(t: TEXT; pos: INTEGER): INTEGER =
  VAR depth := 1; len := Text.Length(t); c: CHAR;
  BEGIN
    FOR i := pos TO len - 1 DO
      c := Text.GetChar(t, i);
      IF    c = '(' THEN INC(depth)
      ELSIF c = ')' THEN
        DEC(depth);
        IF depth = 0 THEN RETURN i END
      END
    END;
    RETURN -1;
  END FindCloseParen;

(* Strip a trailing // line comment, respecting string literals. *)
PROCEDURE StripLineComment(t: TEXT): TEXT =
  VAR
    len := Text.Length(t);
    inStr := FALSE;
    c: CHAR;
  BEGIN
    FOR i := 0 TO len - 1 DO
      c := Text.GetChar(t, i);
      IF c = '"' AND (i = 0 OR Text.GetChar(t, i - 1) # '\\') THEN
        inStr := NOT inStr;
      ELSIF NOT inStr AND c = '/' AND i + 1 < len
            AND Text.GetChar(t, i + 1) = '/' THEN
        RETURN TrimRight(Text.Sub(t, 0, i));
      END
    END;
    RETURN t;
  END StripLineComment;

PROCEDURE StartsWith(t, prefix: TEXT): BOOLEAN =
  BEGIN
    RETURN Text.Length(t) >= Text.Length(prefix)
       AND Text.Equal(Text.Sub(t, 0, Text.Length(prefix)), prefix);
  END StartsWith;

PROCEDURE EndsWith(t, suffix: TEXT): BOOLEAN =
  VAR tl := Text.Length(t); sl := Text.Length(suffix);
  BEGIN
    RETURN tl >= sl AND Text.Equal(Text.Sub(t, tl - sl, sl), suffix);
  END EndsWith;

(* Replace all occurrences of pattern in s with replacement. *)
PROCEDURE ReplaceAll(s, pattern, replacement: TEXT): TEXT =
  VAR
    plen := Text.Length(pattern);
    slen := Text.Length(s);
    result: TEXT := "";
    i := 0;
  BEGIN
    IF plen = 0 THEN RETURN s END;
    WHILE i <= slen - plen DO
      IF Text.Equal(Text.Sub(s, i, plen), pattern) THEN
        result := result & replacement;
        INC(i, plen);
      ELSE
        result := result & Text.Sub(s, i, 1);
        INC(i);
      END
    END;
    (* Append remaining characters *)
    IF i < slen THEN result := result & Text.Sub(s, i) END;
    RETURN result;
  END ReplaceAll;

(* Split a string by commas at paren depth 0. *)
PROCEDURE SplitArgs(s: TEXT): TextList.T =
  VAR
    len := Text.Length(s);
    depth := 0;
    start := 0;
    result: TextList.T := NIL;
    c: CHAR;
  BEGIN
    FOR i := 0 TO len - 1 DO
      c := Text.GetChar(s, i);
      IF    c = '(' THEN INC(depth)
      ELSIF c = ')' THEN DEC(depth)
      ELSIF c = ',' AND depth = 0 THEN
        result := TextList.Cons(Trim(Text.Sub(s, start, i - start)), result);
        start := i + 1;
      END
    END;
    result := TextList.Cons(Trim(Text.Sub(s, start)), result);
    RETURN TextList.ReverseD(result);
  END SplitArgs;

(* ================================================================ *)
(* File reading                                                     *)
(* ================================================================ *)

PROCEDURE ReadLine(rd: Rd.T): TEXT RAISES {Rd.EndOfFile} =
  VAR
    result: TEXT := "";
    c: CHAR;
  BEGIN
    TRY
      c := Rd.GetChar(rd);
    EXCEPT
      Rd.EndOfFile => RAISE Rd.EndOfFile;
    END;
    WHILE c # '\n' DO
      IF c # '\r' THEN result := result & Text.FromChar(c) END;
      TRY
        c := Rd.GetChar(rd);
      EXCEPT
        Rd.EndOfFile => RETURN result;
      END
    END;
    RETURN result;
  END ReadLine;

TYPE LineList = REF RECORD line: TEXT; next: LineList END;

PROCEDURE ReadAllLines(filename: TEXT): LineList =
  VAR
    rd: Rd.T;
    head: LineList := NIL;
    tail: LineList := NIL;
    node: LineList;
    line: TEXT;
  BEGIN
    TRY
      rd := FileRd.Open(filename);
    EXCEPT
      OSError.E =>
        Wr.PutText(Stdio.stderr, "svpp: cannot open '" & filename & "'\n");
        Wr.Flush(Stdio.stderr);
        RETURN NIL;
    END;
    TRY
      LOOP
        TRY line := ReadLine(rd) EXCEPT Rd.EndOfFile => EXIT END;
        node := NEW(LineList, line := line, next := NIL);
        IF head = NIL THEN head := node ELSE tail.next := node END;
        tail := node;
      END
    FINALLY
      Rd.Close(rd);
    END;
    RETURN head;
  END ReadAllLines;

(* ================================================================ *)
(* Macro operations                                                 *)
(* ================================================================ *)

PROCEDURE MacroSet(name: TEXT; m: Macro) =
  VAR dummy: REFANY;
  BEGIN
    IF macros.get(name, dummy) THEN EVAL macros.delete(name, dummy) END;
    EVAL macros.put(name, m);
  END MacroSet;

PROCEDURE MacroGet(name: TEXT): Macro =
  VAR ref: REFANY;
  BEGIN
    IF macros.get(name, ref) THEN RETURN ref END;
    RETURN NIL;
  END MacroGet;

PROCEDURE MacroDefined(name: TEXT): BOOLEAN =
  VAR ref: REFANY;
  BEGIN RETURN macros.get(name, ref) END MacroDefined;

PROCEDURE MacroUndef(name: TEXT) =
  VAR ref: REFANY;
  BEGIN EVAL macros.delete(name, ref) END MacroUndef;

(* ================================================================ *)
(* Parse `define                                                    *)
(* ================================================================ *)

PROCEDURE ParseDefine(rest: TEXT) =
  VAR
    name      : TEXT;
    afterName : INTEGER;
    close     : INTEGER;
    paramStr  : TEXT;
    rawParams : TextList.T;
    body      : TEXT;
    params    : TextList.T;
    defaults  : TextList.T;
    p         : TextList.T;
    param     : TEXT;
    eqPos     : INTEGER;
    m         : Macro;
  BEGIN
    rest := TrimLeft(rest);
    name := ReadIdent(rest, 0);
    afterName := Text.Length(name);
    IF Text.Length(name) = 0 THEN RETURN END;

    IF afterName < Text.Length(rest)
       AND Text.GetChar(rest, afterName) = '(' THEN
      (* Parameterized macro *)
      close := FindCloseParen(rest, afterName + 1);
      IF close < 0 THEN RETURN END;
      paramStr := Text.Sub(rest, afterName + 1, close - afterName - 1);
      rawParams := SplitArgs(paramStr);
      IF close + 1 < Text.Length(rest) THEN
        body := StripLineComment(TrimLeft(Text.Sub(rest, close + 1)))
      ELSE
        body := ""
      END;
      params := NIL; defaults := NIL;
      p := rawParams;
      WHILE p # NIL DO
        param := p.head;
        eqPos := FindChar(param, '=');
        IF eqPos >= 0 THEN
          params := TextList.Cons(Trim(Text.Sub(param, 0, eqPos)), params);
          defaults := TextList.Cons(
            Trim(Text.Sub(param, eqPos + 1)), defaults);
        ELSE
          params := TextList.Cons(Trim(param), params);
          defaults := TextList.Cons(NIL, defaults);
        END;
        p := p.tail;
      END;
      m := NEW(Macro, body := body,
               params := TextList.ReverseD(params),
               defaults := TextList.ReverseD(defaults));
      MacroSet(name, m);
    ELSE
      (* Simple macro *)
      IF afterName < Text.Length(rest) THEN
        body := StripLineComment(TrimLeft(Text.Sub(rest, afterName)))
      ELSE
        body := ""
      END;
      m := NEW(Macro, body := body, params := NIL, defaults := NIL);
      MacroSet(name, m);
    END
  END ParseDefine;

(* ================================================================ *)
(* Macro expansion                                                  *)
(* ================================================================ *)

(* Parse macro arguments at position pos in line.
   pos should point at '('.  Returns (args, endPos) or NIL. *)
TYPE ArgsResult = RECORD args: TextList.T; endPos: INTEGER END;

PROCEDURE ParseMacroArgs(line: TEXT; pos: INTEGER;
                         VAR result: ArgsResult): BOOLEAN =
  VAR close: INTEGER; argStr: TEXT;
  BEGIN
    IF pos >= Text.Length(line)
       OR Text.GetChar(line, pos) # '(' THEN
      RETURN FALSE
    END;
    close := FindCloseParen(line, pos + 1);
    IF close < 0 THEN RETURN FALSE END;
    argStr := Text.Sub(line, pos + 1, close - pos - 1);
    result.args := SplitArgs(argStr);
    result.endPos := close + 1;
    RETURN TRUE;
  END ParseMacroArgs;

(* Single pass of macro expansion. *)
PROCEDURE ExpandOnce(line: TEXT): TEXT =
  VAR
    len       := Text.Length(line);
    i         := 0;
    result    : TEXT := "";
    name      : TEXT;
    afterName : INTEGER;
    m         : Macro;
    ar        : ArgsResult;
    fullArgs  : TextList.T;
    body      : TEXT;
    pa        : TextList.T;
    da        : TextList.T;
    fa        : TextList.T;
    nParams   : INTEGER;
    nArgs     : INTEGER;
  BEGIN
    WHILE i < len DO
      IF Text.GetChar(line, i) = '`' THEN
        name := ReadIdent(line, i + 1);
        afterName := i + 1 + Text.Length(name);
        IF Text.Length(name) > 0 THEN
          m := MacroGet(name);
        ELSE
          m := NIL
        END;
        IF m = NIL THEN
          (* Not a known macro *)
          result := result & Text.Sub(line, i, 1);
          INC(i);
        ELSIF m.params # NIL THEN
          (* Parameterized macro *)
          IF ParseMacroArgs(line, afterName, ar) THEN
            (* Fill in defaults for missing args *)
            nParams := TextList.Length(m.params);
            nArgs := TextList.Length(ar.args);
            fullArgs := NIL;
            pa := m.params; da := m.defaults; fa := ar.args;
            FOR j := 0 TO nParams - 1 DO
              IF j < nArgs AND fa # NIL THEN
                fullArgs := TextList.Cons(fa.head, fullArgs);
                fa := fa.tail;
              ELSIF da # NIL AND da.head # NIL THEN
                fullArgs := TextList.Cons(da.head, fullArgs)
              END;
              IF da # NIL THEN da := da.tail END;
              IF pa # NIL THEN pa := pa.tail END;
            END;
            fullArgs := TextList.ReverseD(fullArgs);
            (* Substitute params in body *)
            body := m.body;
            pa := m.params; fa := fullArgs;
            WHILE pa # NIL AND fa # NIL DO
              body := ReplaceAll(body, pa.head, fa.head);
              pa := pa.tail; fa := fa.tail;
            END;
            (* Token pasting *)
            body := ReplaceAll(body, "``", "");
            result := result & body;
            i := ar.endPos;
          ELSE
            (* No args -- leave unexpanded *)
            result := result & "`" & name;
            i := afterName;
          END
        ELSE
          (* Simple macro *)
          result := result & m.body;
          i := afterName;
        END
      ELSE
        result := result & Text.Sub(line, i, 1);
        INC(i);
      END
    END;
    RETURN result;
  END ExpandOnce;

(* Process inline conditionals from macro expansion. *)
PROCEDURE ProcessInlineConds(text: TEXT): TEXT =
  VAR
    len       := Text.Length(text);
    i         := 0;
    result    : TEXT := "";
    name      : TEXT;
    cname     : TEXT;
    afterName : INTEGER;
    rest      : TEXT;
    stack     : BoolSeq.T := NEW(BoolSeq.T).init();
    active    : BOOLEAN;
  BEGIN
    WHILE i < len DO
      IF Text.GetChar(text, i) = '`'
         AND i + 1 < len AND IsIdentChar(Text.GetChar(text, i + 1)) THEN
        name := ReadIdent(text, i + 1);
        afterName := i + 1 + Text.Length(name);
        IF Text.Equal(name, "ifdef") OR Text.Equal(name, "ifndef")
           OR Text.Equal(name, "elsif") THEN
          rest := TrimLeft(Text.Sub(text, afterName));
          cname := ReadIdent(rest, 0);
          (* Advance past whitespace + name *)
          VAR skip := afterName; BEGIN
            WHILE skip < len AND IsSpace(Text.GetChar(text, skip)) DO
              INC(skip)
            END;
            skip := skip + Text.Length(cname);
            i := skip;
          END;
          IF Text.Equal(name, "ifdef") THEN
            stack.addhi(MacroDefined(cname))
          ELSIF Text.Equal(name, "ifndef") THEN
            stack.addhi(NOT MacroDefined(cname))
          ELSE (* elsif *)
            IF stack.size() > 0 THEN
              stack.put(stack.size() - 1, MacroDefined(cname))
            END
          END
        ELSIF Text.Equal(name, "else") THEN
          IF stack.size() > 0 THEN
            stack.put(stack.size() - 1, NOT stack.gethi())
          END;
          i := afterName;
        ELSIF Text.Equal(name, "endif") THEN
          IF stack.size() > 0 THEN EVAL stack.remhi() END;
          i := afterName;
        ELSE
          (* Not a conditional -- check if active *)
          active := TRUE;
          FOR j := 0 TO stack.size() - 1 DO
            IF NOT stack.get(j) THEN active := FALSE END
          END;
          IF active THEN result := result & "`" & name END;
          i := afterName;
        END
      ELSE
        active := TRUE;
        FOR j := 0 TO stack.size() - 1 DO
          IF NOT stack.get(j) THEN active := FALSE END
        END;
        IF active THEN
          result := result & Text.Sub(text, i, 1)
        END;
        INC(i);
      END
    END;
    RETURN result;
  END ProcessInlineConds;

(* Expand macros iteratively until fixed point. *)
PROCEDURE ExpandMacros(line: TEXT): TEXT =
  VAR
    expanded : TEXT;
    n        := 0;
  BEGIN
    LOOP
      expanded := ExpandOnce(line);
      IF Text.Equal(expanded, line) OR n >= 50 THEN EXIT END;
      line := expanded;
      INC(n);
    END;
    RETURN ProcessInlineConds(expanded);
  END ExpandMacros;

(* ================================================================ *)
(* Check for unclosed macro args (multi-line invocation)            *)
(* ================================================================ *)

PROCEDURE HasUnclosedMacroArgs(text: TEXT): BOOLEAN =
  VAR
    len       := Text.Length(text);
    i         := 0;
    name      : TEXT;
    afterName : INTEGER;
    m         : Macro;
    depth     : INTEGER;
    c         : CHAR;
  BEGIN
    WHILE i < len DO
      IF Text.GetChar(text, i) = '`' THEN
        name := ReadIdent(text, i + 1);
        afterName := i + 1 + Text.Length(name);
        IF Text.Length(name) > 0 THEN m := MacroGet(name) ELSE m := NIL END;
        IF m # NIL AND m.params # NIL THEN
          IF afterName < len AND Text.GetChar(text, afterName) = '(' THEN
            depth := 0;
            FOR j := afterName TO len - 1 DO
              c := Text.GetChar(text, j);
              IF c = '(' THEN INC(depth)
              ELSIF c = ')' THEN
                DEC(depth);
                IF depth = 0 THEN
                  (* Closed -- continue scanning *)
                  i := j + 1;
                  (* Use goto-like exit by setting afterName *)
                  afterName := -1;
                  EXIT
                END
              END
            END;
            IF afterName # -1 AND depth > 0 THEN RETURN TRUE END;
            IF afterName = -1 THEN (* continue from i already set *) ELSE
              i := afterName
            END
          ELSE
            i := afterName
          END
        ELSE
          i := afterName;
          IF i = 0 THEN INC(i) END;  (* avoid infinite loop *)
        END
      ELSE
        INC(i);
      END
    END;
    RETURN FALSE;
  END HasUnclosedMacroArgs;

(* ================================================================ *)
(* Include file search                                              *)
(* ================================================================ *)

PROCEDURE FindInclude(name, fileDir: TEXT): TEXT =
  VAR
    path: TEXT;
    dirs: TextList.T;
  BEGIN
    (* Try file's directory first *)
    path := Pathname.Join(fileDir, name, NIL);
    IF FileExists(path) THEN RETURN path END;
    (* Try include directories *)
    dirs := includeDirs;
    WHILE dirs # NIL DO
      path := Pathname.Join(dirs.head, name, NIL);
      IF FileExists(path) THEN RETURN path END;
      dirs := dirs.tail;
    END;
    RETURN NIL;
  END FindInclude;

PROCEDURE FileExists(path: TEXT): BOOLEAN =
  BEGIN
    TRY
      EVAL FS.Status(path);
      RETURN TRUE;
    EXCEPT
      OSError.E => RETURN FALSE;
    END
  END FileExists;

(* ================================================================ *)
(* Conditional stack                                                *)
(* ================================================================ *)

TYPE CondEntry = RECORD active, seenTrue: BOOLEAN END;

VAR
  condStack: REF ARRAY OF CondEntry := NEW(REF ARRAY OF CondEntry, 64);
  condSP: INTEGER := 0;

PROCEDURE CondPush(active, seenTrue: BOOLEAN) =
  BEGIN
    IF condSP < NUMBER(condStack^) THEN
      condStack[condSP].active := active;
      condStack[condSP].seenTrue := seenTrue;
      INC(condSP);
    END
  END CondPush;

PROCEDURE CondPop() =
  BEGIN IF condSP > 0 THEN DEC(condSP) END END CondPop;

PROCEDURE IsActive(): BOOLEAN =
  BEGIN
    FOR i := 0 TO condSP - 1 DO
      IF NOT condStack[i].active THEN RETURN FALSE END
    END;
    RETURN TRUE;
  END IsActive;

PROCEDURE ParentActive(): BOOLEAN =
  BEGIN
    FOR i := 0 TO condSP - 2 DO
      IF NOT condStack[i].active THEN RETURN FALSE END
    END;
    RETURN TRUE;
  END ParentActive;

(* ================================================================ *)
(* Output                                                           *)
(* ================================================================ *)

PROCEDURE EmitLine(t: TEXT) =
  BEGIN
    Wr.PutText(Stdio.stdout, t);
    Wr.PutChar(Stdio.stdout, '\n');
  END EmitLine;

PROCEDURE EmitBlank() =
  BEGIN Wr.PutChar(Stdio.stdout, '\n') END EmitBlank;

(* ================================================================ *)
(* Main preprocessor                                                *)
(* ================================================================ *)

PROCEDURE Preprocess(filename: TEXT; emit := TRUE) =
  VAR
    ref         : REFANY;
    fileDir     : TEXT;
    lines       : LineList;
    line        : TEXT;
    trimmed     : TEXT;
    dname       : TEXT;
    drest       : TEXT;
    fullRest    : TEXT;
    afterDir    : INTEGER;
    cur         : LineList;
    cname       : TEXT;
    active      : BOOLEAN;
    joined      : TEXT;
    expanded    : TEXT;
    isDirective : BOOLEAN;
    seenTrue    : BOOLEAN;
    q1          : INTEGER;
    q2          : INTEGER;
    incName     : TEXT;
    incPath     : TEXT;

  VAR srcLineNo : INTEGER := 0;

  PROCEDURE DoEmitLine(t: TEXT) =
    BEGIN IF emit THEN EmitLine(t) END END DoEmitLine;
  PROCEDURE DoEmitBlank() =
    BEGIN IF emit THEN EmitBlank() END END DoEmitBlank;
  PROCEDURE DoEmitLineDirective() =
    BEGIN
      IF emit THEN
        EmitLine("`line " & Fmt.Int(srcLineNo + 1)
                 & " \"" & filename & "\" 0")
      END
    END DoEmitLineDirective;

  BEGIN
    (* Guard against circular includes *)
    IF seenFiles.get(filename, ref) THEN RETURN END;
    EVAL seenFiles.put(filename, NIL);

    fileDir := Pathname.Prefix(filename);
    IF fileDir = NIL OR Text.Length(fileDir) = 0 THEN fileDir := "." END;

    lines := ReadAllLines(filename);
    IF lines = NIL THEN RETURN END;

    cur := lines;
    WHILE cur # NIL DO
      line := cur.line;
      cur := cur.next;
      INC(srcLineNo);
      trimmed := TrimLeft(line);

      (* Check for directive *)
      IF Text.Length(trimmed) > 0 AND Text.GetChar(trimmed, 0) = '`' THEN
        dname := ReadIdent(trimmed, 1);
        afterDir := 1 + Text.Length(dname);
        IF afterDir < Text.Length(trimmed) THEN
          drest := Text.Sub(trimmed, afterDir)
        ELSE
          drest := ""
        END;

        isDirective := TRUE;
        IF Text.Equal(dname, "define") THEN
          (* Join backslash continuations *)
          fullRest := drest;
          DoEmitBlank();
          WHILE EndsWith(TrimRight(fullRest), "\\") AND cur # NIL DO
            VAR tr := TrimRight(fullRest); BEGIN
              fullRest := Text.Sub(tr, 0, Text.Length(tr) - 1)
                          & " " & cur.line;
            END;
            cur := cur.next;
            INC(srcLineNo);
            DoEmitBlank();
          END;
          IF IsActive() THEN ParseDefine(Trim(fullRest)) END;

        ELSIF Text.Equal(dname, "undef") THEN
          IF IsActive() THEN MacroUndef(Trim(drest)) END;
          DoEmitBlank();

        ELSIF Text.Equal(dname, "ifdef") THEN
          cname := Trim(drest);
          active := IsActive() AND MacroDefined(cname);
          CondPush(active, active);
          DoEmitBlank();

        ELSIF Text.Equal(dname, "ifndef") THEN
          cname := Trim(drest);
          active := IsActive() AND NOT MacroDefined(cname);
          CondPush(active, active);
          DoEmitBlank();

        ELSIF Text.Equal(dname, "elsif") THEN
          IF condSP > 0 THEN
            seenTrue := condStack[condSP - 1].seenTrue;
            CondPop();
            cname := Trim(drest);
            active := ParentActive() AND NOT seenTrue
                      AND MacroDefined(cname);
            CondPush(active, seenTrue OR active);
          END;
          DoEmitBlank();

        ELSIF Text.Equal(dname, "else") THEN
          IF condSP > 0 THEN
            seenTrue := condStack[condSP - 1].seenTrue;
            CondPop();
            active := ParentActive() AND NOT seenTrue;
            CondPush(active, TRUE);
          END;
          DoEmitBlank();

        ELSIF Text.Equal(dname, "endif") THEN
          CondPop();
          DoEmitBlank();

        ELSIF Text.Equal(dname, "include") THEN
          IF IsActive() THEN
            q1 := FindChar(drest, '\"');
            IF q1 >= 0 THEN
              q2 := FindChar(drest, '\"', q1 + 1);
              IF q2 > q1 THEN
                incName := Text.Sub(drest, q1 + 1, q2 - q1 - 1);
                incPath := FindInclude(incName, fileDir);
                IF incPath # NIL THEN Preprocess(incPath, FALSE) END;
              END
            END
          END;
          DoEmitBlank();

        ELSIF Text.Equal(dname, "timescale")
           OR Text.Equal(dname, "resetall")
           OR Text.Equal(dname, "default_nettype")
           OR Text.Equal(dname, "celldefine")
           OR Text.Equal(dname, "endcelldefine") THEN
          DoEmitBlank();

        ELSE
          (* Unknown directive -- treat as macro line, fall through *)
          isDirective := FALSE
        END
      ELSE
        isDirective := FALSE
      END;

      IF NOT isDirective THEN
        (* Non-directive line or unknown backtick macro *)
        IF NOT IsActive() THEN
          DoEmitBlank()
        ELSE
          (* Join continuation lines for multi-line macro args *)
          joined := line;
          VAR srcLines: CARDINAL := 1; BEGIN
            WHILE HasUnclosedMacroArgs(joined) AND cur # NIL DO
              joined := joined & "\n" & cur.line;
              cur := cur.next;
              INC(srcLineNo);
              INC(srcLines);
            END;
            expanded := ExpandMacros(joined);
            (* Output expanded lines, padding to preserve line count *)
            VAR p: CARDINAL := 0; nl: INTEGER; outLines: CARDINAL := 0; BEGIN
              LOOP
                nl := FindChar(expanded, '\n', p);
                IF nl < 0 THEN
                  DoEmitLine(Text.Sub(expanded, p));
                  INC(outLines);
                  EXIT
                ELSE
                  DoEmitLine(Text.Sub(expanded, p, nl - p));
                  INC(outLines);
                  p := nl + 1;
                END
              END;
              IF outLines < srcLines THEN
                (* Pad with blanks to match source line count *)
                WHILE outLines < srcLines DO
                  DoEmitBlank();
                  INC(outLines);
                END
              ELSIF outLines > srcLines THEN
                (* Expansion grew: emit `line to resync *)
                DoEmitLineDirective()
              END
            END
          END
        END
      END
    END;

    Wr.Flush(Stdio.stdout);
  END Preprocess;

(* ================================================================ *)
(* Command-line parsing and main                                    *)
(* ================================================================ *)

VAR
  filename: TEXT := NIL;
  i: INTEGER;
  arg, name, value: TEXT;
  eqPos: INTEGER;
  m: Macro;

BEGIN
  i := 1;
  WHILE i < Params.Count DO
    arg := Params.Get(i);
    IF Text.Equal(arg, "-I") AND i + 1 < Params.Count THEN
      INC(i);
      includeDirs := TextList.Cons(Params.Get(i), includeDirs);
    ELSIF StartsWith(arg, "-I") THEN
      includeDirs := TextList.Cons(Text.Sub(arg, 2), includeDirs);
    ELSIF Text.Equal(arg, "-D") AND i + 1 < Params.Count THEN
      INC(i);
      arg := Params.Get(i);
      eqPos := FindChar(arg, '=');
      IF eqPos >= 0 THEN
        name := Text.Sub(arg, 0, eqPos);
        value := Text.Sub(arg, eqPos + 1);
      ELSE
        name := arg; value := "1";
      END;
      m := NEW(Macro, body := value, params := NIL, defaults := NIL);
      MacroSet(name, m);
    ELSIF StartsWith(arg, "-D") THEN
      arg := Text.Sub(arg, 2);
      eqPos := FindChar(arg, '=');
      IF eqPos >= 0 THEN
        name := Text.Sub(arg, 0, eqPos);
        value := Text.Sub(arg, eqPos + 1);
      ELSE
        name := arg; value := "1";
      END;
      m := NEW(Macro, body := value, params := NIL, defaults := NIL);
      MacroSet(name, m);
    ELSIF Text.Equal(arg, "--help") OR Text.Equal(arg, "-h") THEN
      Wr.PutText(Stdio.stderr, "svpp -- SystemVerilog preprocessor\n");
      Wr.PutText(Stdio.stderr, "Usage: svpp [--help] [-I dir]... [-D NAME[=VALUE]]... file.sv\n\n");
      Wr.PutText(Stdio.stderr, "  -I dir          Add include search directory\n");
      Wr.PutText(Stdio.stderr, "  -D NAME[=VALUE] Define a preprocessor macro\n\n");
      Wr.PutText(Stdio.stderr, "Preprocessed output is written to stdout.\n");
      Wr.PutText(Stdio.stderr, "See sv/doc/svfe-manual.md (Section 10) for full documentation.\n");
      Wr.Flush(Stdio.stderr);
      filename := "";  (* suppress "no file" usage message *)
    ELSIF Text.GetChar(arg, 0) = '-' THEN
      Wr.PutText(Stdio.stderr, "svpp: unknown option: " & arg & "\n");
      Wr.Flush(Stdio.stderr);
    ELSE
      filename := arg;
    END;
    INC(i);
  END;

  IF filename = NIL THEN
    Wr.PutText(Stdio.stderr, "Usage: svpp [--help] [-I dir]... [-D NAME[=VALUE]]... file.sv\n");
    Wr.Flush(Stdio.stderr);
  ELSIF Text.Length(filename) > 0 THEN
    (* Emit provenance comment and resync line numbers *)
    VAR cmd: TEXT := ""; cwd := Env.Get("PWD"); BEGIN
      FOR j := 0 TO Params.Count - 1 DO
        IF j > 0 THEN cmd := cmd & " " END;
        cmd := cmd & Params.Get(j);
      END;
      Wr.PutText(Stdio.stdout,
        "/* svpp: " & cmd & "  CWD: ");
      IF cwd # NIL THEN Wr.PutText(Stdio.stdout, cwd) END;
      Wr.PutText(Stdio.stdout,
        "  Date: " & FmtTime.Long(Time.Now()) & " */\n");
      (* Resync: tell downstream parser that next line is line 1 of the source *)
      Wr.PutText(Stdio.stdout,
        "`line 1 \"" & filename & "\" 0\n");
    END;
    (* Reverse include dirs to maintain command-line order *)
    includeDirs := TextList.ReverseD(includeDirs);
    Preprocess(filename);
  END
END Main.
