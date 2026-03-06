(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE CspIntrinsics;
IMPORT CspString;
FROM CspCompiledProcess IMPORT Frame;
IMPORT NativeInt, DynamicInt;

PROCEDURE print(frame : Frame; str : CspString.T) : BOOLEAN;

PROCEDURE string_native(frame  : Frame;
                        num    : NativeInt.T;
                        base   : INTEGER) : TEXT;

PROCEDURE string_dynamic(frame : Frame;
                         num   : DynamicInt.T;
                         base  : INTEGER) : TEXT;

PROCEDURE walltime(frame : Frame) : NativeInt.T;

PROCEDURE simtime(frame : Frame) : NativeInt.T;

PROCEDURE assert(x : BOOLEAN; text : TEXT) : NativeInt.T;

PROCEDURE random_native(bits : NativeInt.T) : NativeInt.T;

PROCEDURE random_dynamic(x : DynamicInt.T; bits : NativeInt.T) : DynamicInt.T;

CONST random_wide = random_dynamic;

TYPE IntArray = REF ARRAY OF INTEGER;

PROCEDURE readHexInts(frame : Frame; path : TEXT; maxN : INTEGER) : IntArray;

TYPE
  Putter = OBJECT
  METHODS
    put(str : CspString.T);
  END;
  
PROCEDURE GetPutter() : Putter;
  
PROCEDURE SetPutter(putter : Putter);
  
END CspIntrinsics.
