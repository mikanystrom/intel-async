(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Main;

IMPORT Ply, Fmt, Stdio, Wr, Rd, Params, Process, Thread;

<*FATAL Wr.Failure, Rd.Failure, Ply.ParseError, Thread.Alerted*>

PROCEDURE Run() =
  VAR
    path : TEXT;
    m    : Ply.T;
    x, y, z : REAL;
  BEGIN
    IF Params.Count < 2 THEN
      Wr.PutText(Stdio.stderr, "usage: plytest <file.ply>\n");
      Process.Exit(1);
    END;

    path := Params.Get(1);
    m := Ply.ReadFile(path);

    Wr.PutText(Stdio.stdout, "vertices:   " & Fmt.Int(m.header.nVertices) & "\n");
    Wr.PutText(Stdio.stdout, "faces:      " & Fmt.Int(m.header.nFaces) & "\n");
    Wr.PutText(Stdio.stdout, "properties: " & Fmt.Int(m.header.nAllProps)
                 & " (" & Fmt.Int(m.header.nFloatProps) & " float)\n");

    FOR i := 0 TO m.header.nAllProps - 1 DO
      Wr.PutText(Stdio.stdout, "  [" & Fmt.Int(i) & "] "
                   & m.header.properties[i].name & "\n");
    END;

    (* Print first 5 vertices *)
    VAR n := MIN(5, m.header.nVertices); BEGIN
      Wr.PutText(Stdio.stdout, "\nfirst " & Fmt.Int(n) & " vertices:\n");
      FOR i := 0 TO n - 1 DO
        Ply.GetVertex(m, i, x, y, z);
        Wr.PutText(Stdio.stdout,
          "  " & Fmt.Real(x, prec := 6)
          & "  " & Fmt.Real(y, prec := 6)
          & "  " & Fmt.Real(z, prec := 6) & "\n");
      END;
    END;

    (* Print first 5 faces *)
    VAR n := MIN(5, m.header.nFaces); BEGIN
      Wr.PutText(Stdio.stdout, "\nfirst " & Fmt.Int(n) & " faces:\n");
      FOR i := 0 TO n - 1 DO
        Wr.PutText(Stdio.stdout,
          "  " & Fmt.Int(m.faces[3*i])
          & "  " & Fmt.Int(m.faces[3*i + 1])
          & "  " & Fmt.Int(m.faces[3*i + 2]) & "\n");
      END;
    END;
  END Run;

BEGIN
  Run();
END Main.
