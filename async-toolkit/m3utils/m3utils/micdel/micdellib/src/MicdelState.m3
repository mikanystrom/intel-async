MODULE MicdelState;

IMPORT MicdelAlloy, MicdelPrecipitate, MicdelRecryst, MicdelGrainGrowth,
       MicdelTransform, MicdelStrength, MicdelThermo, Fmt;

PROCEDURE Init(READONLY comp : MicdelAlloy.T;
               D_gamma_0 : LONGREAL;
               T_reheat : LONGREAL) : T =
  VAR st : T;
  BEGIN
    st.D_gamma := D_gamma_0;
    st.X_rex := 1.0d0;
    st.eps_ret := 0.0d0;
    st.rho_disl := 1.0d10;
    st.temp := T_reheat;
    st.solute := comp;
    st.precip := MicdelPrecipitate.InitPopulations();
    st.time := 0.0d0;
    st.D_alpha := 0.0d0;
    st.sigma_y := 0.0d0;
    st.transformed := FALSE;
    RETURN st
  END Init;

PROCEDURE ApplyDeformation(VAR st : T;
                           eps, epsRate : LONGREAL) =
  BEGIN
    st.eps_ret := st.eps_ret + eps;
    st.rho_disl := st.rho_disl + eps * epsRate * 1.0d13;
    IF st.rho_disl > 1.0d16 THEN st.rho_disl := 1.0d16 END;
    st.X_rex := 0.0d0
  END ApplyDeformation;

PROCEDURE EvolveInterpass(VAR st : T;
                          dt_total : LONGREAL;
                          coolingRate : LONGREAL;
                          dtStep : LONGREAL := 0.01d0) =
  VAR
    elapsed := 0.0d0;
    dt : LONGREAL;
    t50, xNew, dX : LONGREAL;
    dRex : LONGREAL;
  BEGIN
    WHILE elapsed < dt_total DO
      dt := MIN(dtStep, dt_total - elapsed);

      st.temp := st.temp - coolingRate * dt;

      IF st.X_rex < 1.0d0 AND st.eps_ret > 0.0d0 THEN
        t50 := MicdelRecryst.T50(MicdelRecryst.Default,
                                  st.eps_ret, 10.0d0,
                                  st.D_gamma, st.temp,
                                  st.solute);
        xNew := MicdelRecryst.Fraction(MicdelRecryst.Default,
                                        elapsed + dt, t50);
        IF xNew > st.X_rex THEN
          dX := xNew - st.X_rex;
          dRex := MicdelRecryst.RexGrainSize(st.D_gamma, st.eps_ret);
          IF xNew > 0.0d0 THEN
            st.D_gamma := xNew * dRex + (1.0d0 - xNew) * st.D_gamma
          END;
          st.rho_disl := st.rho_disl * (1.0d0 - dX * 0.9d0);
          IF st.rho_disl < 1.0d10 THEN st.rho_disl := 1.0d10 END;
          st.eps_ret := st.eps_ret * (1.0d0 - dX);
          st.X_rex := xNew
        END
      END;

      IF st.X_rex > 0.5d0 THEN
        MicdelGrainGrowth.Step(MicdelGrainGrowth.Default,
                               st.D_gamma, st.temp,
                               st.precip, dt)
      END;

      FOR s := FIRST(MicdelThermo.SpeciesId) TO LAST(MicdelThermo.SpeciesId) DO
        MicdelPrecipitate.Step(st.precip[s],
                               MicdelThermo.DefaultSpecies[s],
                               MicdelThermo.Phase.Austenite,
                               st.temp, st.rho_disl,
                               st.solute, dt)
      END;

      elapsed := elapsed + dt;
      st.time := st.time + dt
    END
  END EvolveInterpass;

PROCEDURE Transform(VAR st : T;
                    coolingRate : LONGREAL) =
  VAR
    ae3 := MicdelTransform.Ae3(MicdelTransform.Default, st.solute);
    tTransform : LONGREAL;
    dtCoil := 1.0d0;
  BEGIN
    IF st.temp > ae3 THEN
      tTransform := (st.temp - ae3) / MAX(coolingRate, 0.1d0);
      st.temp := ae3;
      st.time := st.time + tTransform
    END;

    st.D_alpha := MicdelTransform.FerriteGrainSize(
                    st.D_gamma, coolingRate,
                    st.precip, st.solute);

    (* Partition C to pearlite: ferrite solubility of C is ~0.02 wt% *)
    IF st.solute.C > 0.02d0 THEN
      st.solute.C := 0.02d0
    END;

    (* Reduce dislocation density after transformation *)
    st.rho_disl := 1.0d12;

    (* Coil cooling: V(C,N) precipitates in ferrite *)
    FOR i := 1 TO 3600 DO
      st.temp := st.temp - 0.01d0 * dtCoil;
      IF st.temp < 573.0d0 THEN EXIT END;

      FOR s := FIRST(MicdelThermo.SpeciesId) TO LAST(MicdelThermo.SpeciesId) DO
        MicdelPrecipitate.Step(st.precip[s],
                               MicdelThermo.DefaultSpecies[s],
                               MicdelThermo.Phase.Ferrite,
                               st.temp, st.rho_disl,
                               st.solute, dtCoil)
      END
    END;

    st.sigma_y := MicdelStrength.YieldStress(st.D_alpha, st.solute,
                                              st.precip, st.rho_disl);
    st.transformed := TRUE
  END Transform;

PROCEDURE Format(READONLY st : T) : TEXT =
  VAR t : TEXT;
  BEGIN
    t := Fmt.LongReal(st.temp - 273.15d0, Fmt.Style.Fix, 1)
       & "\t" & Fmt.LongReal(st.D_gamma * 1.0d6, Fmt.Style.Fix, 1)
       & "\t" & Fmt.LongReal(st.X_rex, Fmt.Style.Fix, 3)
       & "\t" & Fmt.LongReal(st.eps_ret, Fmt.Style.Fix, 3)
       & "\t" & Fmt.LongReal(st.rho_disl, Fmt.Style.Sci, 2)
       & "\t" & Fmt.LongReal(MicdelPrecipitate.ZenerFraction(st.precip),
                              Fmt.Style.Sci, 2);
    IF st.transformed THEN
      t := t & "\t" & Fmt.LongReal(st.D_alpha * 1.0d6, Fmt.Style.Fix, 1)
           & "\t" & Fmt.LongReal(st.sigma_y, Fmt.Style.Fix, 1)
    END;
    RETURN t
  END Format;

PROCEDURE FormatHeader() : TEXT =
  BEGIN
    RETURN "T(C)\tD_g(um)\tX_rex\teps_ret\trho\tfv_ppt\tD_a(um)\tsigma_y(MPa)"
  END FormatHeader;

BEGIN
END MicdelState.
