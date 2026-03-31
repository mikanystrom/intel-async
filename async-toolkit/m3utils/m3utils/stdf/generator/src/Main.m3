(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

(* $Id: Main.m3,v 1.2 2009/11/08 22:05:28 mika Exp $ *)

(*
  Copyright (c) 2008, Generation Capital Ltd.  All rights reserved.

  Author: Mika Nystrom <mika@alum.mit.edu>
*)


MODULE Main;
IMPORT Pathname, Params, Scheme, Debug, OSError, ReadLineError, NetObj;
IMPORT AL, IP, ReadLine;
FROM SchemeReadLine IMPORT MainLoop;
IMPORT Thread;
IMPORT SchemeM3;
IMPORT SchemeNavigatorEnvironment;
IMPORT SchemeStubs;

<*FATAL Thread.Alerted*>

BEGIN

  SchemeStubs.RegisterStubs();

  (* First arg is TARGET platform, rest are init files *)
  WITH target = Params.Get(1),
       initArr = ARRAY [0..0] OF Pathname.T { "require" } DO
    TRY
      WITH scm = NEW(SchemeM3.T).init(initArr,
                                      globalEnv :=
                                NEW(SchemeNavigatorEnvironment.T).initEmpty()) DO
        EVAL scm.loadEvalText(
          "(define deriv-dir \"../" & target & "/\")");
        FOR i := 2 TO Params.Count-1 DO
          EVAL scm.loadEvalText("(load \"" & Params.Get(i) & "\")")
        END;
        MainLoop(NEW(ReadLine.Default).init(), scm)
      END
    EXCEPT
      Scheme.E(err) => Debug.Error("Caught Scheme.E : " & err)
    |
      IP.Error(err) => Debug.Error("Caught IP.Error : " & AL.Format(err))
    |
      OSError.E(err) => 
        Debug.Error("Caught NetObj.Error : " & AL.Format(err))
    |
      ReadLineError.E(err) => 
        Debug.Error("Caught ReadLineError.E : " & AL.Format(err))
    |
      NetObj.Error(err) => Debug.Error("Caught NetObj.Error : " & 
                                        AL.Format(err))
    END
  END
END Main.

