(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE CspType;
IMPORT CspSyntax;
IMPORT CspRange;
IMPORT CspDirection;
IMPORT CspInterval;
IMPORT Mpz;

TYPE
  T <: Public;

  Public = CspSyntax.T;

  PubArray = T OBJECT
    range      : CspRange.T;
    elemntType : T;
  END;

  Array <: PubArray;

  MayBeConst = T OBJECT
    isConst : BOOLEAN;
  END;
  
  Boolean <: MayBeConst;

  ChannelStructure <: T; (* see CspTypePublic.i3 *)

  PubChannel = T OBJECT
    numValues : Mpz.T;
    dir       : CspDirection.T;
  END;

  Channel <: PubChannel;

  Integer <: MayBeConst; (* see CspTypePublic.i3 *)

  PubNode = T OBJECT
    arrayed   : BOOLEAN;
    width     : [1..LAST(CARDINAL)];
    direction : CspDirection.T;
  END;

  Node <: PubNode;

  String <: MayBeConst;
  
  PubStructure = MayBeConst OBJECT
    (* this is an INSTANCE of a structure *)
    name    : TEXT;
  END;

  Structure <: PubStructure;
  
CONST Brand = "CspType";

END CspType.
