(* Copyright (c) 2026 Mika Nystrom. *)
(* SPDX-License-Identifier: Apache-2.0 *)

(* MDD -- Multi-valued Decision Diagrams.

   An MDD is a directed acyclic graph where each internal node at level k
   has domain(k) children (one per value in the local state space).
   Terminals are Zero (empty set) and One (universal acceptance).

   Nodes are hash-consed (canonical): two MDDs represent the same set
   iff they are the same object (reference equality).

   The forest is quasi-reduced: every path from root to terminal visits
   every level exactly once, even if all children at a level are identical.
   This simplifies the saturation algorithm. *)

INTERFACE MDD;
IMPORT Word;

TYPE T <: REFANY;

CONST Brand = "MDD 0.1";

(* Terminal nodes *)
PROCEDURE One() : T;
PROCEDURE Zero() : T;

(* Forest setup -- call once before building any MDDs.
   n = number of levels, domains[k] = number of values at level k.
   Level 0 is bottom, level n-1 is top. *)
PROCEDURE SetLevels(n: CARDINAL; READONLY domains: ARRAY OF CARDINAL);
PROCEDURE NumLevels() : CARDINAL;
PROCEDURE Domain(level: CARDINAL) : CARDINAL;

(* Set operations *)
PROCEDURE Union(a, b: T) : T;
PROCEDURE Intersection(a, b: T) : T;
PROCEDURE Difference(a, b: T) : T;
PROCEDURE IsEmpty(a: T) : BOOLEAN;
PROCEDURE Equal(a, b: T) : BOOLEAN;

(* Node inspection *)
PROCEDURE NodeLevel(a: T) : INTEGER;
PROCEDURE NodeChild(a: T; i: CARDINAL) : T;

(* Construction *)
PROCEDURE MakeNode(level: CARDINAL;
                   READONLY children: ARRAY OF T) : T;
PROCEDURE Singleton(READONLY values: ARRAY OF CARDINAL) : T;

(* Statistics *)
PROCEDURE Size(a: T) : CARDINAL;
PROCEDURE NodeCount() : CARDINAL;
PROCEDURE Hash(a: T) : Word.T;
PROCEDURE ClearCaches();
PROCEDURE Format(a: T) : TEXT;

END MDD.
