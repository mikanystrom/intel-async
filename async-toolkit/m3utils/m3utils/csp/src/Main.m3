(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Main;

(* look at die cost of chopping Tofino Creek in two *)

IMPORT Fmt;
IMPORT ParseParams;
IMPORT Stdio;
IMPORT SchemeM3;
IMPORT SchemeStubs;
IMPORT ReadLine, SchemeReadLine;
IMPORT Debug;
IMPORT Scheme;
IMPORT Pathname;
IMPORT Thread;
IMPORT TextSeq;
IMPORT TextRd, SchemeInputPort;

(* Force compiled Scheme modules to be linked and registered *)
IMPORT CspcCompiled; <*NOWARN*>
<*FATAL Thread.Alerted*>

PROCEDURE GetPaths(extras : TextSeq.T) : REF ARRAY OF Pathname.T = 
  CONST
    fixed = ARRAY OF Pathname.T { "require", "m3" };
  VAR
    res := NEW(REF ARRAY OF Pathname.T, NUMBER(fixed) + extras.size());
  BEGIN
    FOR i := 0 TO NUMBER(fixed) - 1 DO
      res[i] := fixed[i]
    END;
    FOR i := NUMBER(fixed) TO extras.size() + NUMBER(fixed) - 1 DO
      res[i] := extras.remlo()
    END;
    RETURN res
  END GetPaths;
  
VAR
  pp := NEW(ParseParams.T).init(Stdio.stderr);
  doScheme := FALSE;
  evalExpr : TEXT := NIL;
  extra := NEW(TextSeq.T).init();

BEGIN
  TRY
    doScheme := pp.keywordPresent("-scm");
    IF pp.keywordPresent("-e") THEN
      evalExpr := pp.getNext()
    END;
    pp.skipParsed();
    WITH n = NUMBER(pp.arg^) - pp.next DO
      FOR i := 0 TO n - 1 DO
        extra.addhi(pp.getNext())
      END
    END;
    pp.finish()
  EXCEPT
    ParseParams.Error => Debug.Error("Can't parse command line")
  END;

  IF doScheme OR evalExpr # NIL THEN
    SchemeStubs.RegisterStubs();
    TRY
      WITH scm = NEW(SchemeM3.T).init(GetPaths(extra)^) DO
        IF evalExpr # NIL THEN
          EVAL scm.loadPort(NEW(SchemeInputPort.T).init(NEW(TextRd.T).init(evalExpr)))
        END;
        IF doScheme THEN
          SchemeReadLine.MainLoop(NEW(ReadLine.Default).init(), scm)
        END
      END
    EXCEPT
      Scheme.E(err) => Debug.Error("Caught Scheme.E : " & err)
    END
  END
END Main.
