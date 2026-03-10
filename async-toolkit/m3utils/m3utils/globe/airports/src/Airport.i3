(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE Airport;

IMPORT GeoCoord;

(* Airport identifier to geographic coordinate lookup.
   Supports ICAO (4-letter), IATA (3-letter), and other identifiers.
   Contains a built-in database of world airports (OurAirports open data).
   A single T object is shared across all identifiers for the same airport. *)

TYPE
  T = OBJECT
    icao : TEXT;              (* ICAO code, e.g. "EGLL" *)
    iata : TEXT;              (* IATA code, e.g. "LHR" *)
    name : TEXT;              (* Airport name *)
    loc  : GeoCoord.LatLon;  (* Location in radians *)
  END;

PROCEDURE Lookup(code : TEXT) : T;
  (* Look up an airport by any identifier (case-insensitive).
     Returns NIL if not found. *)

PROCEDURE Count() : CARDINAL;
  (* Number of unique airports in the database *)

CONST Brand = "Airport";

END Airport.
