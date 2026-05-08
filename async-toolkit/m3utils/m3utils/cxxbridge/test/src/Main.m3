(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Main;

IMPORT ToyShapes, Fmt, Stdio, Wr, Thread;

<*FATAL Wr.Failure, Thread.Alerted, ToyShapes.Error*>

PROCEDURE Put(t: TEXT) =
  BEGIN Wr.PutText(Stdio.stdout, t); END Put;

(* A visitor closure that prints each shape *)
TYPE
  PrintVisitor = ToyShapes.VisitorClosure OBJECT OVERRIDES
    visit := PrintVisit;
  END;

PROCEDURE PrintVisit(<*UNUSED*> self: PrintVisitor;
                     s: ToyShapes.Shape; index: CARDINAL) =
  BEGIN
    Put("  [" & Fmt.Int(index) & "] "
          & ToyShapes.Name(s)
          & " at (" & Fmt.LongReal(ToyShapes.Cx(s), prec := 2)
          & ", " & Fmt.LongReal(ToyShapes.Cy(s), prec := 2)
          & ")  area=" & Fmt.LongReal(ToyShapes.Area(s), prec := 4)
          & "\n");
  END PrintVisit;

(* A predicate closure that selects shapes containing a point *)
TYPE
  ContainsPred = ToyShapes.PredicateClosure OBJECT
    px, py: LONGREAL;
  OVERRIDES
    test := ContainsTest;
  END;

PROCEDURE ContainsTest(self: ContainsPred;
                       s: ToyShapes.Shape): BOOLEAN =
  BEGIN
    RETURN ToyShapes.Contains(s, self.px, self.py);
  END ContainsTest;

PROCEDURE Run() =
  VAR
    c1 := ToyShapes.NewCircle(0.0d0, 0.0d0, 5.0d0);
    c2 := ToyShapes.NewCircle(10.0d0, 0.0d0, 3.0d0);
    r1 := ToyShapes.NewRectangle(5.0d0, 5.0d0, 4.0d0, 6.0d0);
    r2 := ToyShapes.NewRectangle(-3.0d0, -3.0d0, 10.0d0, 2.0d0);
    sl := ToyShapes.NewShapeList();
  BEGIN
    Put("=== Individual shapes ===\n");
    Put("c1: " & ToyShapes.Name(c1)
          & "  area=" & Fmt.LongReal(ToyShapes.Area(c1), prec := 4)
          & "  perim=" & Fmt.LongReal(ToyShapes.Perimeter(c1), prec := 4)
          & "\n");
    Put("r1: " & ToyShapes.Name(r1)
          & "  area=" & Fmt.LongReal(ToyShapes.Area(r1), prec := 4)
          & "\n");

    Put("\n=== Move c1 by (1, 2) ===\n");
    ToyShapes.Move(c1, 1.0d0, 2.0d0);
    Put("c1 now at (" & Fmt.LongReal(ToyShapes.Cx(c1), prec := 2)
          & ", " & Fmt.LongReal(ToyShapes.Cy(c1), prec := 2) & ")\n");

    Put("\n=== Build a list ===\n");
    ToyShapes.Add(sl, c1);
    ToyShapes.Add(sl, c2);
    ToyShapes.Add(sl, r1);
    ToyShapes.Add(sl, r2);
    Put("list size: " & Fmt.Int(ToyShapes.Size(sl)) & "\n");
    Put("total area: " & Fmt.LongReal(ToyShapes.TotalArea(sl), prec := 4) & "\n");

    Put("\n=== ForEach (visitor callback) ===\n");
    ToyShapes.ForEach(sl, NEW(PrintVisitor));

    Put("\n=== Filter: shapes containing (1, 0) ===\n");
    VAR
      pred := NEW(ContainsPred, px := 1.0d0, py := 0.0d0);
      hits := ToyShapes.Filter(sl, pred);
    BEGIN
      Put("found " & Fmt.Int(NUMBER(hits^)) & " shapes:\n");
      FOR i := 0 TO LAST(hits^) DO
        Put("  " & ToyShapes.Name(hits[i])
              & " at (" & Fmt.LongReal(ToyShapes.Cx(hits[i]), prec := 2)
              & ", " & Fmt.LongReal(ToyShapes.Cy(hits[i]), prec := 2)
              & ")\n");
      END;
    END;

    Put("\n=== Filter: shapes containing (20, 20) ===\n");
    VAR
      pred := NEW(ContainsPred, px := 20.0d0, py := 20.0d0);
      hits := ToyShapes.Filter(sl, pred);
    BEGIN
      Put("found " & Fmt.Int(NUMBER(hits^)) & " shapes (expected 0)\n");
    END;

    Put("\ndone.\n");
  END Run;

BEGIN
  Run();
END Main.
