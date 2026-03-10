(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE ProjectionRep;

IMPORT Projection;

REVEAL
  Projection.T = Projection.Public BRANDED Projection.Brand & ".T" OBJECT END;

BEGIN
END ProjectionRep.
