(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE CspIntrinsics;
FROM CspScheduler IMPORT GetTime;
IMPORT CspCompiledProcess AS Process;
FROM CspCompiledProcess IMPORT Frame;
FROM Fmt IMPORT Unsigned, F, Int;
IMPORT Mpz;
IMPORT CspIntrinsicsP AS P;

IMPORT CspString;
IMPORT NativeInt;
IMPORT DynamicInt;

IMPORT Debug;
IMPORT Random;
IMPORT Word;
IMPORT Wr;
IMPORT Stdio;
IMPORT Thread;
IMPORT Rd, FileRd, OSError, Text;

<*FATAL Thread.Alerted*>

PROCEDURE DefaultPut(<*UNUSED*>self : Putter; str : CspString.T) =
  BEGIN
    Wr.PutText(Stdio.stdout, str);
    Wr.Flush(Stdio.stdout)
  END DefaultPut;

VAR putstring : Putter := NEW(Putter, put := DefaultPut);
    
PROCEDURE print(frame : Process.Frame; str : CspString.T) : BOOLEAN =
  BEGIN
    putstring.put(F("%s: %s: %s\n",
                    Unsigned(GetTime(), base := 10),
                    frame.name,
                    str));
    RETURN TRUE
  END print;

PROCEDURE GetPutter() : Putter = BEGIN RETURN putstring END GetPutter;

PROCEDURE SetPutter(putter : Putter) = BEGIN putstring := putter END SetPutter;
  
PROCEDURE string_native(<*UNUSED*>frame  : Frame;
                        num              : NativeInt.T;
                        base             : INTEGER) : TEXT =
  BEGIN
    RETURN Int(num, base := base)
  END string_native;

PROCEDURE string_dynamic(<*UNUSED*>frame : Frame;
                         num             : DynamicInt.T;
                         base            : INTEGER) : TEXT =
  BEGIN
    RETURN Mpz.FormatBased(num, base)
  END string_dynamic;

PROCEDURE walltime(<*UNUSED*>frame : Frame) : NativeInt.T =
  BEGIN
    RETURN P.GetNanoclock()
  END walltime;

PROCEDURE simtime(<*UNUSED*>frame : Frame) : NativeInt.T =
  BEGIN RETURN GetTime() END simtime;

PROCEDURE assert(x : BOOLEAN; text : TEXT) : NativeInt.T =
  BEGIN
    IF NOT x THEN
      Debug.Error("Assertion failed : " & text)
    END;
    RETURN 0
  END assert;

PROCEDURE random_native(bits : NativeInt.T) : NativeInt.T =
  VAR
    x := rand.integer();
  BEGIN
    IF bits = BITSIZE(Word.T) - 1 THEN
      RETURN Word.And(x, NativeInt.Max)
    ELSE
      WITH mask = Word.Shift(1, bits) - 1 DO
        RETURN Word.And(x, mask)
      END
    END
  END random_native;

PROCEDURE random_dynamic(x : DynamicInt.T; bits : NativeInt.T) : DynamicInt.T =
  BEGIN
    Mpz.set_ui(x, 0);
    WHILE bits # 0 DO
      WITH b = MIN(BITSIZE(Word.T) - 1, bits) DO
        Mpz.LeftShift(x, x, b);
        Mpz.add_ui(x, x, random_native(b));
        DEC(bits, b)
      END
    END;
    RETURN x
  END random_dynamic;

PROCEDURE ParseHexLine(line : TEXT; VAR val : INTEGER) : BOOLEAN =
  VAR
    len := Text.Length(line);
    pos : INTEGER := 0;
    ch  : CHAR;
    digit : INTEGER;
    result : INTEGER := 0;
    found : BOOLEAN := FALSE;
  BEGIN
    (* skip leading whitespace *)
    WHILE pos < len DO
      ch := Text.GetChar(line, pos);
      IF ch # ' ' AND ch # '\t' THEN EXIT END;
      INC(pos)
    END;
    (* empty or comment *)
    IF pos >= len THEN RETURN FALSE END;
    IF pos + 1 < len
       AND Text.GetChar(line, pos) = '/'
       AND Text.GetChar(line, pos + 1) = '/' THEN
      RETURN FALSE
    END;
    (* skip optional 0x prefix *)
    IF pos + 1 < len
       AND Text.GetChar(line, pos) = '0'
       AND (Text.GetChar(line, pos + 1) = 'x'
            OR Text.GetChar(line, pos + 1) = 'X') THEN
      INC(pos, 2)
    END;
    (* parse hex digits *)
    WHILE pos < len DO
      ch := Text.GetChar(line, pos);
      IF ch >= '0' AND ch <= '9' THEN
        digit := ORD(ch) - ORD('0')
      ELSIF ch >= 'a' AND ch <= 'f' THEN
        digit := ORD(ch) - ORD('a') + 10
      ELSIF ch >= 'A' AND ch <= 'F' THEN
        digit := ORD(ch) - ORD('A') + 10
      ELSE
        EXIT
      END;
      result := Word.Or(Word.Shift(result, 4), digit);
      found := TRUE;
      INC(pos)
    END;
    val := result;
    RETURN found
  END ParseHexLine;

PROCEDURE readHexInts(<*UNUSED*>frame : Frame;
                      path            : TEXT;
                      maxN            : INTEGER) : IntArray =
  VAR
    rd     : Rd.T;
    result : IntArray;
    count  : INTEGER := 0;
    line   : TEXT;
    val    : INTEGER;
  BEGIN
    result := NEW(IntArray, maxN);
    TRY
      rd := FileRd.Open(path);
    EXCEPT
    | OSError.E =>
      Debug.Error("readHexInts: cannot open " & path);
      RETURN NEW(IntArray, 0)
    END;
    TRY
      WHILE count < maxN DO
        line := Rd.GetLine(rd);
        IF ParseHexLine(line, val) THEN
          result^[count] := val;
          INC(count)
        END
      END
    EXCEPT
    | Rd.EndOfFile => (* normal end of file *)
    ELSE
      (* Rd.Failure or unexpected error *)
    END;
    TRY Rd.Close(rd) EXCEPT ELSE END;
    WITH trimmed = NEW(IntArray, count) DO
      FOR i := 0 TO count - 1 DO trimmed^[i] := result^[i] END;
      RETURN trimmed
    END
  END readHexInts;

VAR
  rand := NEW(Random.Default).init(TRUE);
BEGIN END CspIntrinsics.
