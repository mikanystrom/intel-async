(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

(* Main.m3 -- svsynth: mscheme with BDD primitives for logic synthesis *)
(*
   svsynth is an extended mscheme interpreter that includes BDD
   (Binary Decision Diagram) primitives for logic synthesis.  It
   loads the sv/src/ Scheme libraries and provides BDD operations
   that can be called from Scheme to build, manipulate, and optimize
   Boolean functions extracted from SystemVerilog ASTs.

   Usage:
     svsynth [file.scm ...]

   The interpreter starts with BDD primitives pre-loaded, then
   processes any files given on the command line, and enters an
   interactive REPL.
*)

MODULE Main;
IMPORT SchemeM3, Scheme, Pathname, Csighandler;
IMPORT Debug, Wr, AL;
IMPORT SchemeNavigatorEnvironment, SchemeEnvironment;
IMPORT ParseParams, Stdio;
IMPORT BDDPrims;

TYPE
  Interrupter = Scheme.Interrupter OBJECT
  OVERRIDES
    interrupt := Interrupt;
  END;

PROCEDURE Interrupt(<*UNUSED*>i : Interrupter) : BOOLEAN =
  BEGIN
    IF Csighandler.have_signal() = 1 THEN
      Csighandler.clear_signal();
      RETURN TRUE
    ELSE
      RETURN FALSE
    END
  END Interrupt;

VAR
  env : SchemeEnvironment.T := NEW(SchemeNavigatorEnvironment.T).initEmpty();
BEGIN
  Csighandler.install_int_handler();

  TRY
    WITH pp = NEW(ParseParams.T).init(Stdio.stderr) DO
      pp.skipParsed();

      WITH arr = NEW(REF ARRAY OF Pathname.T,
                      1 + NUMBER(pp.arg^) - pp.next) DO
        arr[0] := "require";
        FOR i := 1 TO LAST(arr^) DO arr[i] := pp.getNext() END;
        pp.finish();

        TRY
          (* Get the default primitives and extend with BDD ops *)
          WITH prims = BDDPrims.Install(SchemeM3.GetPrims()) DO
            WITH scm = NEW(SchemeM3.T).init(arr^, globalEnv := env) DO
              scm.setPrimitives(prims);
              scm.readEvalWriteLoop(NEW(Interrupter))
            END
          END
        EXCEPT
          Scheme.E(err) =>
          Debug.Error("Couldn't initialize interpreter: " & err)
        |
          Wr.Failure(err) =>
          Debug.Error("Wr.Failure: " & AL.Format(err))
        END
      END
    END
  EXCEPT
    ParseParams.Error => Debug.Error("check usage, ParseParams error")
  END;

END Main.
