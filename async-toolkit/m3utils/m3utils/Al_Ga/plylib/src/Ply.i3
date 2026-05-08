(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE Ply;

IMPORT Rd;

(* Binary PLY mesh reader.

   Reads binary_little_endian PLY files with vertex properties of
   type float or uchar, and triangular faces.  Only float properties
   are stored; uchar properties (e.g. RGB color) are skipped during
   read.  Float properties are stored in a flat array indexed by
   their float-only index (0-based, skipping uchars).

   Faces are stored as a contiguous array of integer triples. *)

EXCEPTION
  ParseError(TEXT);

TYPE
  PropKind = {Float, Uchar};

  (* A single named vertex property as declared in the header. *)
  Property = RECORD
    name      : TEXT;
    kind      : PropKind;
    floatIdx  : INTEGER;   (* index into float array, or -1 for uchar *)
  END;

  Header = RECORD
    nVertices    : CARDINAL;
    nFaces       : CARDINAL;
    nFloatProps  : CARDINAL;           (* number of float properties *)
    nAllProps    : CARDINAL;           (* total properties including uchar *)
    properties   : REF ARRAY OF Property;  (* all properties in order *)
  END;

  (* Flat vertex data: nVertices * nFloatProps floats, row-major.
     vertex i, float property j at vertexData[i * nFloatProps + j]. *)
  Vertices = REF ARRAY OF REAL;

  (* Triangle indices: nFaces * 3 integers. *)
  Faces = REF ARRAY OF INTEGER;

  T = RECORD
    header   : Header;
    vertices : Vertices;
    faces    : Faces;
  END;

(* ---- Reading ---- *)

PROCEDURE ReadHeader(rd: Rd.T): Header RAISES {ParseError, Rd.Failure};
PROCEDURE ReadData(rd: Rd.T; READONLY h: Header): T
    RAISES {ParseError, Rd.Failure};
PROCEDURE Read(rd: Rd.T): T RAISES {ParseError, Rd.Failure};
PROCEDURE ReadFile(path: TEXT): T RAISES {ParseError, Rd.Failure};

(* ---- Property lookup ---- *)

PROCEDURE FindProperty(READONLY h: Header; name: TEXT): INTEGER;
  (* Return the float index for the named property, or -1 if not
     found or if the property is not a float. *)

(* ---- Vertex accessors ---- *)

PROCEDURE GetVertex(READONLY m: T; i: CARDINAL;
                    VAR x, y, z: REAL);
  (* Extract position.  Assumes "x","y","z" are the first three
     float properties (standard PLY convention). *)

PROCEDURE GetVertexN(READONLY m: T; i: CARDINAL;
                     px, py, pz: CARDINAL;
                     VAR x, y, z: REAL);
  (* Extract three float-indexed properties from vertex i. *)

END Ply.
