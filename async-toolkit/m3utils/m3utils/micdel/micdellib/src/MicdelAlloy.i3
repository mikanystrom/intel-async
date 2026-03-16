(* Steel composition representation and access by element. *)

INTERFACE MicdelAlloy;

IMPORT MicdelThermo;

TYPE
  T = RECORD
    C, N, V, Nb, Ti, Mn, Si, Cr, Mo, P, S : LONGREAL;  (* wt% *)
  END;

CONST
  Zero = T { C := 0.0d0, N := 0.0d0, V := 0.0d0, Nb := 0.0d0,
             Ti := 0.0d0, Mn := 0.0d0, Si := 0.0d0, Cr := 0.0d0,
             Mo := 0.0d0, P := 0.0d0, S := 0.0d0 };

PROCEDURE GetElement(READONLY a : T; e : MicdelThermo.Element) : LONGREAL;
PROCEDURE SetElement(VAR a : T; e : MicdelThermo.Element; v : LONGREAL);
PROCEDURE Format(READONLY a : T) : TEXT;

END MicdelAlloy.
