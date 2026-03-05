(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

(* BDDPrims.i3 -- BDD primitives for mscheme *)

INTERFACE BDDPrims;
IMPORT SchemePrimitive;

PROCEDURE Install(prims : SchemePrimitive.ExtDefiner) : SchemePrimitive.ExtDefiner;
  (* Install BDD primitives into the given ExtDefiner.
     Primitives added:
       (bdd-true)              => BDD constant true
       (bdd-false)             => BDD constant false
       (bdd-var name)          => new BDD variable
       (bdd-not a)             => NOT a
       (bdd-and a b)           => a AND b
       (bdd-or  a b)           => a OR b
       (bdd-xor a b)           => a XOR b
       (bdd-implies a b)       => a => b
       (bdd-equiv a b)         => a <=> b
       (bdd-ite c t e)         => if c then t else e
       (bdd-restrict b v val)  => restrict v to val (0/1) in b
       (bdd-format b)          => string representation
       (bdd-size b)            => node count
       (bdd-equal? a b)        => boolean equality
  *)

END BDDPrims.
