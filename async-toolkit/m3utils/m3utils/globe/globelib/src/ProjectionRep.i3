(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE ProjectionRep;

IMPORT Projection;

(* Reveals the representation of Projection.T for subtypes to use. *)

REVEAL Projection.T <: Projection.Public;

END ProjectionRep.
