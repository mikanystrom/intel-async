(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE LibertyParseMain;
IMPORT Rd;
IMPORT LibertyComponent;
IMPORT libertyLexStd;
IMPORT libertyParseStd;

PROCEDURE Parse(rd : Rd.T) : LibertyComponent.T  RAISES { Rd.Failure } =
  VAR
    lexer    := NEW(libertyLexStd.T);
    parser   := NEW(libertyParseStd.T);
  BEGIN
    EVAL lexer.setRd(rd);
    EVAL parser.setLex(lexer);
    
    EVAL parser.parse();

    WITH res = parser.val DO
      res.makeParentLinks();
    
      RETURN res
    END
  END Parse;


BEGIN END LibertyParseMain.
