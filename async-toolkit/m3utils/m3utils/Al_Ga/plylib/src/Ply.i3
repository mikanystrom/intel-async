(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE Ply;

(* Binary PLY mesh reader.

   Reads binary_little_endian PLY files with vertex properties of
   type float or uchar, and triangular faces.  Only float properties
   are stored; uchar properties (e.g. RGB color) are skipped during
   read.  Float properties are stored in a flat array indexed by
   their float-only index (0-based, skipping uchars).

   Faces are stored as a contiguous array of integer triples.

   Reference: PLY format specification by Greg Turk, 1994.
   See also: Turk, G., "The PLY Polygon File Format",
   http://paulbourke.net/dataformats/ply/ *)

IMPORT Rd;

EXCEPTION
  ParseError(TEXT);

TYPE
  Format = {BinaryLittleEndian, Ascii};
  PropKind = {Float, Uchar};

  (* A single named vertex property as declared in the PLY header. *)
  Property = RECORD
    name      : TEXT;       (* property name from the header *)
    kind      : PropKind;   (* Float or Uchar *)
    floatIdx  : INTEGER;    (* index into the float array, or -1 for uchar *)
  END;

  Header = RECORD
    format       : Format;                    (* binary or ascii *)
    nVertices    : CARDINAL;                  (* vertex count *)
    nFaces       : CARDINAL;                  (* face count *)
    nFloatProps  : CARDINAL;                  (* float properties per vertex *)
    nAllProps    : CARDINAL;                  (* all properties per vertex *)
    properties   : REF ARRAY OF Property;     (* nAllProps elements *)
  END;

  (* Flat vertex data: nVertices * nFloatProps floats, row-major.

     Invariant: NUMBER(vertices^) = header.nVertices * header.nFloatProps.
     Vertex i, float property j is at vertices[i * nFloatProps + j]. *)
  Vertices = REF ARRAY OF REAL;

  (* Triangle indices: nFaces * 3 integers.

     Invariant: NUMBER(faces^) = header.nFaces * 3.
     Face i has vertex indices faces[3*i], faces[3*i+1], faces[3*i+2]. *)
  Faces = REF ARRAY OF INTEGER;

  T = RECORD
    header   : Header;
    vertices : Vertices;
    faces    : Faces;
  END;

(* ---- Reading ---- *)

PROCEDURE ReadHeader(rd: Rd.T): Header RAISES {ParseError, Rd.Failure};
  (* Requires: rd is positioned at the beginning of a PLY file.
     Ensures:  returns a valid Header; rd is positioned at the first
               byte of binary vertex data (immediately after "end_header").
     Raises:   ParseError if format is not binary_little_endian 1.0,
               or if vertex properties are not float or uchar. *)

PROCEDURE ReadData(rd: Rd.T; READONLY h: Header): T
    RAISES {ParseError, Rd.Failure};
  (* Requires: rd is positioned at the start of binary data, as left
               by ReadHeader; h describes the expected layout.
     Ensures:  returns T with h copied into the header field;
               vertices and faces arrays allocated and filled.
     Raises:   ParseError if a face has other than 3 vertices, or
               if the file ends prematurely. *)

PROCEDURE Read(rd: Rd.T): T RAISES {ParseError, Rd.Failure};
  (* Requires: rd is positioned at the beginning of a PLY file.
     Ensures:  equivalent to ReadData(rd, ReadHeader(rd)). *)

PROCEDURE ReadFile(path: TEXT): T RAISES {ParseError, Rd.Failure};
  (* Requires: path names a readable file.
     Ensures:  opens path, calls Read, closes the file.
     Raises:   ParseError if the file cannot be opened or is not
               a valid PLY file. *)

(* ---- Property lookup ---- *)

PROCEDURE FindProperty(READONLY h: Header; name: TEXT): INTEGER;
  (* Requires: h is a valid Header.
     Ensures:  returns the float index (>= 0) for the named property,
               or -1 if no float property with that name exists. *)

(* ---- Vertex accessors ---- *)

PROCEDURE GetVertex(READONLY m: T; i: CARDINAL;
                    VAR x, y, z: REAL);
  (* Requires: i < m.header.nVertices; the first three float
               properties are x, y, z (standard PLY convention).
     Modifies: x, y, z.
     Ensures:  x, y, z are set to the position of vertex i. *)

PROCEDURE GetVertexN(READONLY m: T; i: CARDINAL;
                     px, py, pz: CARDINAL;
                     VAR x, y, z: REAL);
  (* Requires: i < m.header.nVertices; px, py, pz < m.header.nFloatProps.
     Modifies: x, y, z.
     Ensures:  x, y, z are set to the float properties at the given
               indices for vertex i. *)

END Ply.
