(* Static recrystallization kinetics for austenite.
   JMAK model with solute drag retardation from Nb, V. *)

INTERFACE MicdelRecryst;

IMPORT MicdelAlloy;

TYPE
  Params = RECORD
    A    : LONGREAL;
    p    : LONGREAL;   (* strain exponent *)
    q    : LONGREAL;   (* strain rate exponent *)
    s    : LONGREAL;   (* grain size exponent *)
    Qrex : LONGREAL;   (* activation energy, J/mol *)
    n    : LONGREAL;   (* Avrami exponent *)
  END;

CONST
  Default = Params {
    A    := 2.5d-19,
    p    := 4.0d0,
    q    := 1.0d0,
    s    := 2.0d0,
    Qrex := 230000.0d0,
    n    := 1.0d0
  };

PROCEDURE T50(READONLY par : Params;
              eps, epsRate, D0, T : LONGREAL;
              READONLY solute : MicdelAlloy.T) : LONGREAL;

PROCEDURE SoluteDragFactor(READONLY solute : MicdelAlloy.T) : LONGREAL;

PROCEDURE Fraction(READONLY par : Params;
                   t, t50 : LONGREAL) : LONGREAL;

PROCEDURE RexGrainSize(D0, eps : LONGREAL) : LONGREAL;

END MicdelRecryst.
