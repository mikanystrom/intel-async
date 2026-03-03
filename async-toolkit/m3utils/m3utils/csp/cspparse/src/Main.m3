(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Main;
IMPORT Params, FileRd, Rd, Wr, Thread, OSError, Text;
IMPORT cspTok, cspLexExt, cspParseExt;
FROM Stdio IMPORT stdout, stderr;
<* FATAL Wr.Failure, Thread.Alerted *>

VAR
  lexer  := NEW(cspLexExt.T);
  parser := NEW(cspParseExt.T);
  rd     : Rd.T;
  fname  : TEXT;
  doLex  : BOOLEAN := FALSE;
BEGIN
  IF Params.Count < 2 THEN
    Wr.PutText(stderr, "usage: cspfe [--lex] <file.csp>\n");
    Wr.Flush(stderr);
  ELSE
    IF Params.Count >= 3 AND Text.Equal(Params.Get(1), "--lex") THEN
      doLex := TRUE;
      fname := Params.Get(2);
    ELSE
      fname := Params.Get(1);
    END;
    TRY
      rd := FileRd.Open(fname);
      EVAL lexer.setRd(rd);
      IF doLex THEN
        cspTok.Test(lexer);
      ELSE
        parser.setLex(lexer).parse().discard();
        Wr.PutText(stdout, fname & ": syntax ok\n");
        Wr.Flush(stdout);
      END;
    EXCEPT
    | OSError.E =>
        Wr.PutText(stderr, "cspfe: cannot open " & fname & "\n");
        Wr.Flush(stderr);
    END;
  END;
END Main.
