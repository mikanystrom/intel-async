(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE LibertyParseMain;
IMPORT Rd;
IMPORT LibertyComponent;

PROCEDURE Parse(rd : Rd.T) : LibertyComponent.T RAISES { Rd.Failure };

END LibertyParseMain.
