MODULE MicdelGrainGrowth;

IMPORT MicdelThermo, MicdelPrecipitate, Math;

PROCEDURE ZenerLimit(READONLY par : Params;
                     READONLY pops : MicdelPrecipitate.Populations) : LONGREAL =
  VAR
    fv := MicdelPrecipitate.ZenerFraction(pops);
    rz := MicdelPrecipitate.ZenerRadius(pops);
  BEGIN
    IF fv <= 0.0d0 OR rz <= 0.0d0 THEN RETURN 1.0d0 END;
    RETURN par.alpha * rz / fv
  END ZenerLimit;

PROCEDURE GrowthRate(READONLY par : Params;
                     D, T : LONGREAL;
                     READONLY pops : MicdelPrecipitate.Populations) : LONGREAL =
  VAR
    k := par.k0 * Math.exp(-par.Qgg / (MicdelThermo.R * T));
    dLim := ZenerLimit(par, pops);
    dDdt : LONGREAL;
  BEGIN
    IF D <= 0.0d0 THEN RETURN 0.0d0 END;
    IF D >= dLim THEN RETURN 0.0d0 END;
    dDdt := k / (par.m * Math.pow(D, par.m - 1.0d0));
    RETURN dDdt
  END GrowthRate;

PROCEDURE Step(READONLY par : Params;
               VAR D : LONGREAL;
               T : LONGREAL;
               READONLY pops : MicdelPrecipitate.Populations;
               dt : LONGREAL) =
  VAR
    dDdt := GrowthRate(par, D, T, pops);
    dLim := ZenerLimit(par, pops);
    newD : LONGREAL;
  BEGIN
    newD := D + dDdt * dt;
    IF newD > dLim THEN newD := dLim END;
    IF newD > D THEN D := newD END
  END Step;

BEGIN
END MicdelGrainGrowth.
