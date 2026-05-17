(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

UNSAFE MODULE Ply;

IMPORT Rd, Text, TextRd, Lex, FloatMode, FileRd, Fmt, OSError, Thread;

<*FATAL Thread.Alerted*>

PROCEDURE ReadHeader(rd: Rd.T): Header RAISES {ParseError, Rd.Failure} =
  VAR
    line     : TEXT;
    h        : Header;
    props    : ARRAY [0..63] OF Property;
    nAll     : CARDINAL := 0;
    nFloat   : CARDINAL := 0;
    inVertex : BOOLEAN  := FALSE;
    inFace   : BOOLEAN  := FALSE;
  BEGIN
    TRY
      line := Rd.GetLine(rd);
      IF NOT Text.Equal(line, "ply") THEN
        RAISE ParseError("not a PLY file");
      END;

      line := Rd.GetLine(rd);
      IF Text.Equal(line, "format binary_little_endian 1.0") THEN
        h.format := Format.BinaryLittleEndian;
      ELSIF Text.Equal(line, "format ascii 1.0") THEN
        h.format := Format.Ascii;
      ELSE
        RAISE ParseError("unsupported format: " & line);
      END;

      LOOP
        line := Rd.GetLine(rd);
        IF Text.Equal(line, "end_header") THEN EXIT; END;

        IF TextStartsWith(line, "comment ") OR
           TextStartsWith(line, "obj_info ") THEN
          (* skip *)

        ELSIF TextStartsWith(line, "element vertex ") THEN
          h.nVertices := ScanCardinal(line, 15);
          inVertex := TRUE;
          inFace := FALSE;

        ELSIF TextStartsWith(line, "element face ") THEN
          h.nFaces := ScanCardinal(line, 13);
          inVertex := FALSE;
          inFace := TRUE;

        ELSIF TextStartsWith(line, "property ") THEN
          IF inVertex THEN
            IF TextStartsWith(line, "property float ") THEN
              VAR name := Text.Sub(line, 15); BEGIN
                props[nAll] := Property{name := name,
                                        kind := PropKind.Float,
                                        floatIdx := nFloat};
                INC(nAll);
                INC(nFloat);
              END;
            ELSIF TextStartsWith(line, "property uchar ") THEN
              VAR name := Text.Sub(line, 15); BEGIN
                props[nAll] := Property{name := name,
                                        kind := PropKind.Uchar,
                                        floatIdx := -1};
                INC(nAll);
              END;
            ELSE
              RAISE ParseError(
                "unsupported vertex property type: " & line);
            END;
          ELSIF inFace THEN
            IF NOT TextStartsWith(line, "property list uchar int") THEN
              RAISE ParseError("unsupported face property: " & line);
            END;
          END;
        END;
      END;

    EXCEPT
    | Rd.EndOfFile =>
        RAISE ParseError("unexpected end of file in header");
    END;

    h.nFloatProps := nFloat;
    h.nAllProps := nAll;
    h.properties := NEW(REF ARRAY OF Property, nAll);
    h.properties^ := SUBARRAY(props, 0, nAll);

    RETURN h;
  END ReadHeader;

PROCEDURE ReadData(rd: Rd.T; READONLY h: Header): T
    RAISES {ParseError, Rd.Failure} =
  VAR m: T;
  BEGIN
    m.header := h;
    m.vertices := NEW(Vertices, h.nVertices * h.nFloatProps);
    m.faces := NEW(Faces, h.nFaces * 3);

    IF h.format = Format.Ascii THEN
      ReadDataAscii(rd, h, m);
    ELSE
      ReadDataBinary(rd, h, m);
    END;
    RETURN m;
  END ReadData;

PROCEDURE ReadDataAscii(rd: Rd.T; READONLY h: Header; VAR m: T)
    RAISES {ParseError, Rd.Failure} =
  VAR
    line : TEXT;
    trd  : TextRd.T;
    floatPos : CARDINAL := 0;
    val  : REAL;
    n, idx : INTEGER;
  BEGIN
    TRY
      (* Read vertex data: one line per vertex, space-separated values *)
      FOR i := 0 TO h.nVertices - 1 DO
        line := Rd.GetLine(rd);
        trd := TextRd.New(line);
        FOR j := 0 TO h.nAllProps - 1 DO
          IF h.properties[j].kind = PropKind.Float THEN
            Lex.Skip(trd);
            val := Lex.Real(trd);
            m.vertices[floatPos] := val;
            INC(floatPos);
          ELSE
            (* uchar: read and discard *)
            Lex.Skip(trd);
            EVAL Lex.Int(trd);
          END;
        END;
      END;

      (* Read face data: "3 v0 v1 v2" per line *)
      FOR i := 0 TO h.nFaces - 1 DO
        line := Rd.GetLine(rd);
        trd := TextRd.New(line);
        Lex.Skip(trd);
        n := Lex.Int(trd);
        IF n # 3 THEN
          RAISE ParseError("face " & Fmt.Int(i) & " has " & Fmt.Int(n)
                             & " vertices (only triangles supported)");
        END;
        FOR j := 0 TO 2 DO
          Lex.Skip(trd);
          idx := Lex.Int(trd);
          m.faces[3 * i + j] := idx;
        END;
      END;

    EXCEPT
    | Rd.EndOfFile =>
        RAISE ParseError("unexpected end of file in ascii data");
    | Lex.Error, FloatMode.Trap =>
        RAISE ParseError("number parse error in ascii data");
    END;
  END ReadDataAscii;

PROCEDURE ReadDataBinary(rd: Rd.T; READONLY h: Header; VAR m: T)
    RAISES {ParseError, Rd.Failure} =
  VAR
    buf4      : ARRAY [0..3] OF CHAR;
    faceCount : CHAR;
  BEGIN
    TRY
      (* Read vertex data: nVertices rows of mixed properties *)
      VAR floatPos : CARDINAL := 0; BEGIN
        FOR i := 0 TO h.nVertices - 1 DO
          FOR j := 0 TO h.nAllProps - 1 DO
            IF h.properties[j].kind = PropKind.Float THEN
              ReadBytes4(rd, buf4);
              m.vertices[floatPos] := DecodeLEFloat(buf4);
              INC(floatPos);
            ELSE
              EVAL Rd.GetChar(rd);
            END;
          END;
        END;
      END;

      (* Read face data *)
      FOR i := 0 TO h.nFaces - 1 DO
        faceCount := Rd.GetChar(rd);
        VAR n := ORD(faceCount); BEGIN
          IF n # 3 THEN
            RAISE ParseError("face " & Fmt.Int(i) & " has " & Fmt.Int(n)
                               & " vertices (only triangles supported)");
          END;
        END;
        FOR j := 0 TO 2 DO
          ReadBytes4(rd, buf4);
          m.faces[3 * i + j] := DecodeLEInt32(buf4);
        END;
      END;

    EXCEPT
    | Rd.EndOfFile =>
        RAISE ParseError("unexpected end of file in binary data");
    END;
  END ReadDataBinary;

PROCEDURE Read(rd: Rd.T): T RAISES {ParseError, Rd.Failure} =
  VAR h: Header;
  BEGIN
    h := ReadHeader(rd);
    RETURN ReadData(rd, h);
  END Read;

PROCEDURE ReadFile(path: TEXT): T RAISES {ParseError, Rd.Failure} =
  VAR rd: Rd.T;
  BEGIN
    TRY
      rd := FileRd.Open(path);
    EXCEPT
    | OSError.E =>
        RAISE ParseError("cannot open file: " & path);
    END;
    TRY
      RETURN Read(rd);
    FINALLY
      Rd.Close(rd);
    END;
  END ReadFile;

PROCEDURE FindProperty(READONLY h: Header; name: TEXT): INTEGER =
  BEGIN
    FOR i := 0 TO h.nAllProps - 1 DO
      IF Text.Equal(h.properties[i].name, name) AND
         h.properties[i].kind = PropKind.Float THEN
        RETURN h.properties[i].floatIdx;
      END;
    END;
    RETURN -1;
  END FindProperty;

PROCEDURE GetVertex(READONLY m: T; i: CARDINAL;
                    VAR x, y, z: REAL) =
  VAR base := i * m.header.nFloatProps;
  BEGIN
    x := m.vertices[base + 0];
    y := m.vertices[base + 1];
    z := m.vertices[base + 2];
  END GetVertex;

PROCEDURE GetVertexN(READONLY m: T; i: CARDINAL;
                     px, py, pz: CARDINAL;
                     VAR x, y, z: REAL) =
  VAR base := i * m.header.nFloatProps;
  BEGIN
    x := m.vertices[base + px];
    y := m.vertices[base + py];
    z := m.vertices[base + pz];
  END GetVertexN;

(* ---- Internal helpers ---- *)

PROCEDURE TextStartsWith(t, prefix: TEXT): BOOLEAN =
  VAR len := Text.Length(prefix);
  BEGIN
    RETURN Text.Length(t) >= len AND
           Text.Equal(Text.Sub(t, 0, len), prefix);
  END TextStartsWith;

PROCEDURE ScanCardinal(line: TEXT; offset: CARDINAL): CARDINAL
    RAISES {ParseError} =
  VAR
    sub := Text.Sub(line, offset);
    rd  := TextRd.New(sub);
    val : CARDINAL;
  BEGIN
    TRY
      val := Lex.Int(rd);
    EXCEPT
    | Lex.Error, FloatMode.Trap =>
        RAISE ParseError("expected integer in: " & line);
    | Rd.Failure =>
        RAISE ParseError("read failure parsing: " & line);
    END;
    RETURN val;
  END ScanCardinal;

PROCEDURE ReadBytes4(rd: Rd.T; VAR buf: ARRAY [0..3] OF CHAR)
    RAISES {Rd.Failure, Rd.EndOfFile} =
  BEGIN
    FOR i := 0 TO 3 DO buf[i] := Rd.GetChar(rd); END;
  END ReadBytes4;

PROCEDURE DecodeLEFloat(READONLY buf: ARRAY [0..3] OF CHAR): REAL =
  VAR
    bits : Bits32;
    res  : REAL;
  BEGIN
    bits := ORD(buf[0])
         + ORD(buf[1]) * 256
         + ORD(buf[2]) * 65536
         + ORD(buf[3]) * 16777216;
    res := LOOPHOLE(bits, REAL);
    RETURN res;
  END DecodeLEFloat;

TYPE Bits32 = BITS 32 FOR [0 .. 16_FFFFFFFF];

PROCEDURE DecodeLEInt32(READONLY buf: ARRAY [0..3] OF CHAR): INTEGER =
  BEGIN
    RETURN ORD(buf[0])
         + ORD(buf[1]) * 256
         + ORD(buf[2]) * 65536
         + ORD(buf[3]) * 16777216;
  END DecodeLEInt32;

BEGIN
END Ply.
