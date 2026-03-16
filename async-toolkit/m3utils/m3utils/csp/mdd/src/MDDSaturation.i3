(* Copyright (c) 2026 Mika Nystrom. *)
(* SPDX-License-Identifier: Apache-2.0 *)

(* MDDSaturation -- saturation-based reachability for MDDs.

   Implements the saturation algorithm of Ciardo, Marmorstein, and
   Siminiceanu (2001).  Exploits the asynchronous structure of CSP
   systems: each event (tau or sync) affects only a small number of
   MDD levels, so fixed-point iteration can be performed level-by-level
   rather than globally. *)

INTERFACE MDDSaturation;
IMPORT MDD, MDDEvent;

TYPE EventList = REF ARRAY OF MDDEvent.T;

(* Compute the reachable state set from initial by firing all events
   to a fixed point using the saturation algorithm. *)
PROCEDURE ComputeReachable(initial: MDD.T; events: EventList) : MDD.T;

(* Compute the set of states that have at least one successor
   under any event.  Used for deadlock detection:
   deadlocked = Difference(reached, HasSuccessor(events)). *)
PROCEDURE HasSuccessor(reached: MDD.T; events: EventList) : MDD.T;

(* Compute the set of deadlocked states directly by incremental
   subtraction.  Starts with reached and removes states that have
   a successor under each event.  Terminates early when the set
   becomes empty.  Much faster than HasSuccessor when few states
   are deadlocked. *)
PROCEDURE ComputeDeadlocked(reached: MDD.T; events: EventList) : MDD.T;

END MDDSaturation.
