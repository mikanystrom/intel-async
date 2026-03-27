(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Main;
IMPORT Scheme;
IMPORT Debug;
IMPORT ParseParams;
IMPORT Stdio;
IMPORT TextSeq;
IMPORT SchemeReadLine;
IMPORT SchemeStubs;
IMPORT SchemeM3;
IMPORT ReadLine;
IMPORT Pathname;

(* Force compiled Scheme modules to be linked and registered *)
IMPORT PhotopicCompiled; <*NOWARN*>

PROCEDURE DoIt() =
  BEGIN
  END DoIt;

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
  pp       := NEW(ParseParams.T).init(Stdio.stderr);
  doScheme := FALSE;
  extra    := NEW(TextSeq.T).init();
BEGIN
  TRY
    doScheme := pp.keywordPresent("-scm");
    IF doScheme THEN
      WHILE pp.keywordPresent("-scmfile") DO
        extra.addhi(pp.getNext())
      END
    END;
    (* we dont check args for extraneous here *)
  EXCEPT
    ParseParams.Error => Debug.Error("Can't parse command line")
  END;

  IF doScheme THEN
    SchemeStubs.RegisterStubs();
    TRY
      WITH scm = NEW(SchemeM3.T).init(GetPaths(extra)^) DO
        SchemeReadLine.MainLoop(NEW(ReadLine.Default).init(), scm)
      END
    EXCEPT
      Scheme.E(err) => Debug.Error("Caught Scheme.E : " & err)
    END
  ELSE
    DoIt()
  END

END Main.
