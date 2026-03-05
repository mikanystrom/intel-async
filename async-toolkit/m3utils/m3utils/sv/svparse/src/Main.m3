(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)

MODULE Main;
IMPORT Params, FileRd, Rd, Wr, Thread, OSError, Text, Pathname;
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

VAR
  lexer  := NEW(svLexExt.T);
  parser := NEW(svParseExt.T);
  rd     : Rd.T;
  fname  : TEXT := NIL;
  doLex  : BOOLEAN := FALSE;
  doScm  : BOOLEAN := FALSE;
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
      ELSIF Text.Equal(arg, "--name") THEN
        INC(i);
        IF i < Params.Count THEN modName := Params.Get(i) END;
      ELSE
        fname := arg;
      END;
    END;
    INC(i);
  END;
  IF fname = NIL THEN
    Wr.PutText(stderr, "usage: svfe [--lex] [--scm] [--name NAME] <file.sv>\n");
    Wr.Flush(stderr);
  ELSE
    IF modName = NIL THEN modName := BaseName(fname) END;
    TRY
      rd := FileRd.Open(fname);
      EVAL lexer.setRd(rd);
      IF doLex THEN
        svTok.Test(lexer);
      ELSE
        parser.setLex(lexer).parse().discard();
        IF doScm THEN
          Wr.PutText(stdout, parser.scmResult & "\n");
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
