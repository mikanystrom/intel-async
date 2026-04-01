(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)

MODULE Main;
IMPORT Params, FileRd, Rd, Wr, Thread, OSError, Text, Pathname, Env, FmtTime, Time;
IMPORT svTok, svLexExt, svParseExt;
FROM Stdio IMPORT stdout, stderr;
<* FATAL Wr.Failure, Thread.Alerted *>

PROCEDURE BaseName(fname : TEXT) : TEXT =
  VAR base := Pathname.Last(fname);
      dot  := Text.FindChar(base, '.');
  BEGIN
    IF dot >= 0 THEN base := Text.Sub(base, 0, dot) END;
    RETURN base
  END BaseName;

PROCEDURE CommandLine(): TEXT =
  VAR res: TEXT := "";
  BEGIN
    FOR i := 0 TO Params.Count - 1 DO
      IF i > 0 THEN res := res & " " END;
      res := res & Params.Get(i);
    END;
    RETURN res;
  END CommandLine;

PROCEDURE EmitScmHeader(wr: Wr.T) =
  VAR cwd := Env.Get("PWD");
  BEGIN
    Wr.PutText(wr, ";; Command: " & CommandLine() & "\n");
    IF cwd # NIL THEN Wr.PutText(wr, ";; CWD: " & cwd & "\n") END;
    Wr.PutText(wr, ";; Date: " & FmtTime.Long(Time.Now()) & "\n");
    Wr.PutText(wr, "\n");
  END EmitScmHeader;

PROCEDURE PrettyPrintScm(wr: Wr.T; s: TEXT) =
  (* Pretty-print an S-expression with indentation.
     Rule: a nested '(' after a space gets its own indented line.
     Respects quoted strings — does not reformat inside "...". *)
  VAR
    len   := Text.Length(s);
    depth := 0;
    c     : CHAR;
    prev  : CHAR := ' ';
    inStr := FALSE;
  BEGIN
    FOR i := 0 TO len - 1 DO
      c := Text.GetChar(s, i);
      IF inStr THEN
        Wr.PutChar(wr, c);
        IF c = '"' AND prev # '\\' THEN inStr := FALSE END;
      ELSIF c = '"' THEN
        Wr.PutChar(wr, c);
        inStr := TRUE;
      ELSIF c = '(' THEN
        IF depth > 0 AND prev = ' ' THEN
          Wr.PutChar(wr, '\n');
          FOR j := 1 TO depth DO Wr.PutText(wr, "  ") END;
        END;
        Wr.PutChar(wr, '(');
        INC(depth);
      ELSIF c = ')' THEN
        Wr.PutChar(wr, ')');
        IF depth > 0 THEN DEC(depth) END;
      ELSE
        Wr.PutChar(wr, c);
      END;
      prev := c;
    END;
    Wr.PutChar(wr, '\n');
  END PrettyPrintScm;

PROCEDURE Help() =
  BEGIN
    Wr.PutText(stderr, "svfe -- SystemVerilog frontend (parser)\n");
    Wr.PutText(stderr, "Usage: svfe [--help] [--scm] [--lex] [--no-lines] [--name NAME] <file.sv>\n\n");
    Wr.PutText(stderr, "  --scm        Emit S-expression parse tree to stdout\n");
    Wr.PutText(stderr, "  --lex        Emit lexer token stream (debugging)\n");
    Wr.PutText(stderr, "  --no-lines   Suppress (@ N ...) line number wrappers\n");
    Wr.PutText(stderr, "  --name NAME  Set module name for error messages\n\n");
    Wr.PutText(stderr, "With no flags, checks syntax and prints 'filename: syntax ok'.\n");
    Wr.PutText(stderr, "See sv/doc/svfe-manual.md for full documentation.\n");
    Wr.Flush(stderr);
  END Help;

VAR
  lexer  := NEW(svLexExt.T);
  parser := NEW(svParseExt.T);
  rd     : Rd.T;
  fname  : TEXT := NIL;
  doLex  : BOOLEAN := FALSE;
  doScm  : BOOLEAN := FALSE;
  doHelp : BOOLEAN := FALSE;
  modName : TEXT := NIL;
  i : INTEGER;
BEGIN
  i := 1;
  WHILE i < Params.Count DO
    VAR arg := Params.Get(i);
    BEGIN
      IF Text.Equal(arg, "--lex") THEN
        doLex := TRUE;
      ELSIF Text.Equal(arg, "--scm") THEN
        doScm := TRUE;
      ELSIF Text.Equal(arg, "--no-lines") THEN
        parser.noLines := TRUE;
      ELSIF Text.Equal(arg, "--name") THEN
        INC(i);
        IF i < Params.Count THEN modName := Params.Get(i) END;
      ELSIF Text.Equal(arg, "--help") OR Text.Equal(arg, "-h") THEN
        doHelp := TRUE;
      ELSE
        fname := arg;
      END;
    END;
    INC(i);
  END;
  IF doHelp THEN
    Help();
  ELSIF fname = NIL THEN
    Wr.PutText(stderr, "usage: svfe [--help] [--scm] [--lex] [--no-lines] [--name NAME] <file.sv>\n");
    Wr.Flush(stderr);
  ELSE
    IF modName = NIL THEN modName := BaseName(fname) END;
    TRY
      rd := FileRd.Open(fname);
      lexer.curFile := fname;
      EVAL lexer.setRd(rd);
      parser.lexer := lexer;
      IF doLex THEN
        svTok.Test(lexer);
      ELSE
        parser.setLex(lexer).parse().discard();
        IF doScm THEN
          EmitScmHeader(stdout);
          PrettyPrintScm(stdout, parser.scmResult);
          Wr.Flush(stdout);
        ELSE
          Wr.PutText(stdout, fname & ": syntax ok\n");
          Wr.Flush(stdout);
        END;
      END;
    EXCEPT
    | OSError.E =>
        Wr.PutText(stderr, "svfe: cannot open " & fname & "\n");
        Wr.Flush(stderr);
    END;
  END;
END Main.
