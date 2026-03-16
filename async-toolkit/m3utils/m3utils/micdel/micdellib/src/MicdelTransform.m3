MODULE MicdelTransform;

IMPORT MicdelAlloy, MicdelPrecipitate, MicdelThermo, Math;

PROCEDURE Ae3(READONLY par : Params; READONLY comp : MicdelAlloy.T) : LONGREAL =
  BEGIN
    RETURN par.Ae3_base
           + par.kC * Math.sqrt(MAX(comp.C, 0.0d0))
           + par.kMn * comp.Mn
           + par.kSi * comp.Si
           + par.kCr * comp.Cr
  END Ae3;

PROCEDURE FerriteFraction(READONLY par : Params;
                          T, coolingRate : LONGREAL;
                          READONLY comp : MicdelAlloy.T) : LONGREAL =
  VAR
    ae3 := Ae3(par, comp);
    ae1 := ae3 - 100.0d0;
    f : LONGREAL;
  BEGIN
    IF T >= ae3 THEN RETURN 0.0d0 END;
    IF T <= ae1 THEN RETURN par.f_factor END;
    f := par.f_factor * (ae3 - T) / (ae3 - ae1);
    IF coolingRate < 1.0d0 THEN
      f := f * 1.05d0
    END;
    IF f > 1.0d0 THEN f := 1.0d0 END;
    IF f < 0.0d0 THEN f := 0.0d0 END;
    RETURN f
  END FerriteFraction;

PROCEDURE FerriteGrainSize(D_gamma : LONGREAL;
                           coolingRate : LONGREAL;
                           READONLY pops : MicdelPrecipitate.Populations;
                           READONLY comp : MicdelAlloy.T) : LONGREAL =
  (* Sellars-Beynon model (adapted):
     D_alpha(um) = 3.75 + 0.18*D_gamma(um) + 0.29/sqrt(coolingRate)
     with Mn refinement correction and intragranular nucleation. *)
  VAR
    dgUm := D_gamma * 1.0d6;  (* m -> um *)
    dAlphaUm : LONGREAL;
    igr : LONGREAL;
  BEGIN
    dAlphaUm := 3.75d0 + 0.18d0 * dgUm
                + 0.29d0 / Math.sqrt(MAX(coolingRate, 0.1d0));

    (* Mn refinement: ~ -0.7 um per wt% Mn *)
    dAlphaUm := dAlphaUm - 0.7d0 * comp.Mn;

    igr := IntragranularRefinement(pops);
    dAlphaUm := dAlphaUm / igr;

    IF dAlphaUm < 1.0d0 THEN dAlphaUm := 1.0d0 END;
    IF dAlphaUm > dgUm THEN dAlphaUm := dgUm END;
    RETURN dAlphaUm * 1.0d-6  (* um -> m *)
  END FerriteGrainSize;

PROCEDURE IntragranularRefinement(
              READONLY pops : MicdelPrecipitate.Populations) : LONGREAL =
  VAR
    factor := 1.0d0;
    nv, r : LONGREAL;
  BEGIN
    nv := pops[MicdelThermo.SpeciesId.VN].Nv;
    r := pops[MicdelThermo.SpeciesId.VN].r;
    IF nv > 0.0d0 AND r > 0.0d0 THEN
      factor := factor + 1.0d-23 * nv * r
    END;

    nv := pops[MicdelThermo.SpeciesId.VCN].Nv;
    r := pops[MicdelThermo.SpeciesId.VCN].r;
    IF nv > 0.0d0 AND r > 0.0d0 THEN
      factor := factor + 1.0d-23 * nv * r
    END;

    RETURN factor
  END IntragranularRefinement;

BEGIN
END MicdelTransform.
