MODULE MicdelRecryst;

IMPORT MicdelThermo, MicdelAlloy, Math;

PROCEDURE T50(READONLY par : Params;
              eps, epsRate, D0, T : LONGREAL;
              READONLY solute : MicdelAlloy.T) : LONGREAL =
  (* D0 in meters internally, convert to um for the Sellars equation. *)
  VAR
    t : LONGREAL;
    drag := SoluteDragFactor(solute);
    d0um := D0 * 1.0d6;  (* m -> um *)
  BEGIN
    IF eps <= 0.0d0 OR epsRate <= 0.0d0 OR d0um <= 0.0d0 THEN
      RETURN 1.0d10
    END;
    t := par.A
         * Math.pow(eps, -par.p)
         * Math.pow(epsRate, -par.q)
         * Math.pow(d0um, par.s)
         * Math.exp(par.Qrex / (MicdelThermo.R * T))
         * drag;
    RETURN t
  END T50;

PROCEDURE SoluteDragFactor(READONLY solute : MicdelAlloy.T) : LONGREAL =
  VAR
    f := 1.0d0;
    nb := solute.Nb;
    v := solute.V;
  BEGIN
    IF nb > 0.0d0 THEN f := f * Math.exp(275000.0d0 * nb / 100.0d0) END;
    IF v > 0.0d0 THEN f := f * Math.exp(3000.0d0 * v / 100.0d0) END;
    RETURN f
  END SoluteDragFactor;

PROCEDURE Fraction(READONLY par : Params;
                   t, t50 : LONGREAL) : LONGREAL =
  BEGIN
    IF t50 <= 0.0d0 THEN RETURN 1.0d0 END;
    IF t <= 0.0d0 THEN RETURN 0.0d0 END;
    RETURN 1.0d0 - Math.exp(-0.693d0 * Math.pow(t / t50, par.n))
  END Fraction;

PROCEDURE RexGrainSize(D0, eps : LONGREAL) : LONGREAL =
  (* Sellars: D_rex(um) = 0.743 * D0(um)^0.67 * eps^-0.67
     Input/output in meters, convert internally. *)
  VAR d0um := D0 * 1.0d6;  (* m -> um *)
      dRexUm : LONGREAL;
  BEGIN
    IF d0um <= 0.0d0 OR eps <= 0.0d0 THEN RETURN D0 END;
    dRexUm := 0.743d0 * Math.pow(d0um, 0.67d0) * Math.pow(eps, -0.67d0);
    RETURN dRexUm * 1.0d-6  (* um -> m *)
  END RexGrainSize;

BEGIN
END MicdelRecryst.
