(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Main;
IMPORT Params, FileRd, Rd, Wr, Thread, OSError, Text, Pathname;
IMPORT cspTok, cspLexExt, cspParseExt;
FROM Stdio IMPORT stdout, stderr;
<* FATAL Wr.Failure, Thread.Alerted *>

PROCEDURE CellName(fname : TEXT) : TEXT =
  VAR base := Pathname.Last(fname);
      dot  := Text.FindChar(base, '.');
  BEGIN
    IF dot >= 0 THEN base := Text.Sub(base, 0, dot) END;
    RETURN base
  END CellName;

VAR
  lexer  := NEW(cspLexExt.T);
  parser := NEW(cspParseExt.T);
  rd     : Rd.T;
  fname  : TEXT;
  doLex  : BOOLEAN := FALSE;
  doScm  : BOOLEAN := FALSE;
  cellName : TEXT := NIL;
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
        IF i < Params.Count THEN cellName := Params.Get(i) END;
      ELSE
        fname := arg;
      END;
    END;
    INC(i);
  END;
  IF fname = NIL THEN
    Wr.PutText(stderr, "usage: cspfe [--lex] [--scm] [--name CELLNAME] <file.csp>\n");
    Wr.Flush(stderr);
  ELSE
    IF cellName = NIL THEN cellName := CellName(fname) END;
    TRY
      rd := FileRd.Open(fname);
      EVAL lexer.setRd(rd);
      IF doLex THEN
        cspTok.Test(lexer);
      ELSE
        parser.setLex(lexer).parse().discard();
        IF doScm THEN
          Wr.PutText(stdout, "(\"" & cellName & "\"\n");
          Wr.PutText(stdout, "  (csp\n");
          Wr.PutText(stdout, "    " & parser.scmResult & ")\n");
          Wr.PutText(stdout, "  (cellinfo \"" & cellName & "\" \"" &
            cellName & "\" () ()))\n");
          Wr.Flush(stdout);
        ELSE
          Wr.PutText(stdout, fname & ": syntax ok\n");
          Wr.Flush(stdout);
        END;
      END;
    EXCEPT
    | OSError.E =>
        Wr.PutText(stderr, "cspfe: cannot open " & fname & "\n");
        Wr.Flush(stderr);
    END;
  END;
END Main.
