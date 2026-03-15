(* Copyright (c) 2026 Mika Nystrom. *)
(* SPDX-License-Identifier: Apache-2.0 *)

(* MDDPrivate -- internal representation of MDD nodes.

   Reveals MDD.T as a branded object so that Node and Terminal
   can be declared as subtypes. *)

INTERFACE MDDPrivate;
IMPORT MDD;

REVEAL MDD.T = BRANDED "MDD.T" OBJECT END;

TYPE
  Node = MDD.T OBJECT
    level    : INTEGER;
    children : REF ARRAY OF MDD.T;
    tag      : CARDINAL;
  END;

  Terminal = Node OBJECT
    value : BOOLEAN;
  END;

PROCEDURE GetTag() : CARDINAL;

END MDDPrivate.
