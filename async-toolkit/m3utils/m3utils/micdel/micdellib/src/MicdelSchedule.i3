(* Roll schedule definition and text-format parser. *)

INTERFACE MicdelSchedule;

IMPORT Rd, MicdelAlloy;

TYPE
  Pass = RECORD
    strain     : LONGREAL;
    strainRate : LONGREAL;   (* 1/s *)
    T_entry    : LONGREAL;   (* K *)
    t_interpass: LONGREAL;   (* s *)
    coolingRate: LONGREAL;   (* K/s during interpass *)
  END;

  Cooling = RECORD
    rate     : LONGREAL;   (* K/s on run-out table *)
    T_coil   : LONGREAL;   (* coiling temperature, K *)
    t_coil   : LONGREAL;   (* coil cooling time, s *)
    coilRate : LONGREAL;   (* K/s in coil *)
  END;

  T = RECORD
    comp      : MicdelAlloy.T;
    T_reheat  : LONGREAL;
    D_gamma_0 : LONGREAL;   (* initial austenite grain size, m *)
    nPasses   : CARDINAL;
    passes    : REF ARRAY OF Pass;
    cooling   : Cooling;
  END;

EXCEPTION ParseError(TEXT);

PROCEDURE ParseSchedule(rd : Rd.T) : T RAISES {ParseError};

PROCEDURE FormatSchedule(READONLY sched : T) : TEXT;

END MicdelSchedule.
