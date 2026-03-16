MODULE MicdelPrecipitate;

IMPORT MicdelThermo, MicdelAlloy, Math, Fmt;

CONST
  Pi = 3.14159265358979323846d0;
  FourThirdsPi = 4.0d0 / 3.0d0 * Pi;

PROCEDURE InitPopulations() : Populations =
  VAR p : Populations;
  BEGIN
    FOR s := FIRST(MicdelThermo.SpeciesId) TO LAST(MicdelThermo.SpeciesId) DO
      p[s] := Population { species := s, Nv := 0.0d0, r := 0.0d0, fv := 0.0d0 }
    END;
    RETURN p
  END InitPopulations;

PROCEDURE NucleationRate(READONLY sd : MicdelThermo.SpeciesData;
                         phase : MicdelThermo.Phase;
                         T, cMetal, cInterstitial,
                         rho_disl : LONGREAL) : LONGREAL =
  VAR
    dgv := MicdelThermo.DrivingForce(sd, phase, T, cMetal, cInterstitial);
    dgStar, n0, z, betaStar, diff, j : LONGREAL;
  BEGIN
    IF dgv <= 0.0d0 THEN RETURN 0.0d0 END;

    dgStar := 16.0d0 * Pi * sd.gamma * sd.gamma * sd.gamma
              / (3.0d0 * dgv * dgv);

    n0 := 1.0d28 + rho_disl * 1.0d10;

    z := sd.Vm / (2.0d0 * Pi * sd.gamma)
         * Math.sqrt(dgv / (MicdelThermo.Nav * MicdelThermo.KB * T));

    diff := MicdelThermo.Diffusivity(sd, phase, T);
    VAR rStar := 2.0d0 * sd.gamma / dgv;
    BEGIN
      betaStar := 4.0d0 * Pi * rStar * rStar * diff * cMetal * 0.01d0
                  / (sd.Vm * sd.Vm / (MicdelThermo.Nav * MicdelThermo.Nav))
    END;

    j := n0 * z * betaStar * Math.exp(-dgStar / (MicdelThermo.KB * T));

    IF j > 1.0d30 THEN j := 1.0d30 END;
    IF j < 0.0d0 THEN j := 0.0d0 END;
    RETURN j
  END NucleationRate;

PROCEDURE CriticalRadius(READONLY sd : MicdelThermo.SpeciesData;
                         phase : MicdelThermo.Phase;
                         T, cMetal, cInterstitial : LONGREAL) : LONGREAL =
  VAR dgv := MicdelThermo.DrivingForce(sd, phase, T, cMetal, cInterstitial);
  BEGIN
    IF dgv <= 0.0d0 THEN RETURN 1.0d0 END;
    RETURN 2.0d0 * sd.gamma / dgv
  END CriticalRadius;

PROCEDURE GrowthRate(READONLY sd : MicdelThermo.SpeciesData;
                     phase : MicdelThermo.Phase;
                     T, cMetal, cInterstitial, r : LONGREAL) : LONGREAL =
  VAR
    diff := MicdelThermo.Diffusivity(sd, phase, T);
    ks := MicdelThermo.Solubility(sd.sp[phase], T);
    c0, ci, cp, gibThomson, drdt : LONGREAL;
  BEGIN
    IF r <= 0.0d0 THEN RETURN 0.0d0 END;
    c0 := cMetal;
    gibThomson := Math.exp(2.0d0 * sd.gamma * sd.Vm
                           / (r * MicdelThermo.R * T));
    IF cInterstitial > 0.0d0 THEN
      ci := ks * gibThomson / cInterstitial
    ELSE
      ci := c0
    END;
    cp := 1.0d0;
    IF c0 <= ci THEN RETURN 0.0d0 END;
    drdt := diff / r * (c0 - ci) / (cp - ci);
    RETURN drdt
  END GrowthRate;

PROCEDURE CoarsenRate(READONLY sd : MicdelThermo.SpeciesData;
                      phase : MicdelThermo.Phase;
                      T, cInterface, r : LONGREAL) : LONGREAL =
  VAR
    diff := MicdelThermo.Diffusivity(sd, phase, T);
    dr3dt, drdt : LONGREAL;
  BEGIN
    IF r <= 0.0d0 THEN RETURN 0.0d0 END;
    dr3dt := 8.0d0 * sd.gamma * diff * cInterface * sd.Vm
             / (9.0d0 * MicdelThermo.R * T);
    drdt := dr3dt / (3.0d0 * r * r);
    RETURN drdt
  END CoarsenRate;

PROCEDURE ZenerRadius(READONLY pops : Populations) : LONGREAL =
  VAR
    sumFvR := 0.0d0;
    sumFv := 0.0d0;
  BEGIN
    FOR s := FIRST(MicdelThermo.SpeciesId) TO LAST(MicdelThermo.SpeciesId) DO
      IF pops[s].fv > 0.0d0 AND pops[s].r > 0.0d0 THEN
        sumFvR := sumFvR + pops[s].fv * pops[s].r;
        sumFv := sumFv + pops[s].fv
      END
    END;
    IF sumFv > 0.0d0 THEN
      RETURN sumFvR / sumFv
    ELSE
      RETURN 0.0d0
    END
  END ZenerRadius;

PROCEDURE ZenerFraction(READONLY pops : Populations) : LONGREAL =
  VAR sumFv := 0.0d0;
  BEGIN
    FOR s := FIRST(MicdelThermo.SpeciesId) TO LAST(MicdelThermo.SpeciesId) DO
      sumFv := sumFv + pops[s].fv
    END;
    RETURN sumFv
  END ZenerFraction;

PROCEDURE MaxVolumeFraction(cMetal, cInter : LONGREAL;
                            READONLY sd : MicdelThermo.SpeciesData) : LONGREAL =
  (* Maximum precipitate volume fraction from stoichiometry.
     fv_max ~ (cMetal/100) * (rho_Fe / rho_ppt) * (M_ppt / M_metal)
     Approximate: fv_max ~ cMetal * 0.02 for typical MX precipitates
     where cMetal is in wt%.  Use the lesser of metal and interstitial. *)
  VAR
    fMetal := cMetal * 0.02d0;   (* approx max fv from metal solute *)
    fInter := cInter * 0.02d0;   (* approx max fv from interstitial *)
  BEGIN
    EVAL sd;  (* proportionality is similar across species *)
    RETURN MIN(fMetal, fInter)
  END MaxVolumeFraction;

PROCEDURE Step(VAR pop : Population;
               READONLY sd : MicdelThermo.SpeciesData;
               phase : MicdelThermo.Phase;
               T, rho_disl : LONGREAL;
               VAR solute : MicdelAlloy.T;
               dt : LONGREAL) =
  VAR
    cMetal := MicdelAlloy.GetElement(solute, sd.metal);
    cInter := MicdelAlloy.GetElement(solute, sd.interstitial);
    jnuc, rCrit, drGrow, drCoarsen, dr : LONGREAL;
    dNv, newNv, newR, newFv : LONGREAL;
    dfv, fvMax : LONGREAL;
    cMetalNew, cInterNew : LONGREAL;
  BEGIN
    IF cMetal <= 0.0d0 OR cInter <= 0.0d0 THEN RETURN END;

    (* Maximum possible volume fraction from available solute *)
    fvMax := MaxVolumeFraction(cMetal, cInter, sd);
    IF pop.fv >= fvMax THEN RETURN END;  (* equilibrium reached *)

    jnuc := NucleationRate(sd, phase, T, cMetal, cInter, rho_disl);
    rCrit := CriticalRadius(sd, phase, T, cMetal, cInter);
    dNv := jnuc * dt;

    IF pop.r > 0.0d0 THEN
      drGrow := GrowthRate(sd, phase, T, cMetal, cInter, pop.r)
    ELSE
      drGrow := 0.0d0
    END;

    IF pop.Nv > 0.0d0 AND pop.r > rCrit * 2.0d0 THEN
      VAR ks := MicdelThermo.Solubility(sd.sp[phase], T);
          ci : LONGREAL;
      BEGIN
        IF cInter > 0.0d0 THEN ci := ks / cInter ELSE ci := 0.0d0 END;
        drCoarsen := CoarsenRate(sd, phase, T, ci, pop.r)
      END
    ELSE
      drCoarsen := 0.0d0
    END;

    dr := (drGrow + drCoarsen) * dt;

    newNv := pop.Nv + dNv;
    IF newNv > 0.0d0 THEN
      IF pop.Nv > 0.0d0 THEN
        newR := (pop.Nv * (pop.r + dr) + dNv * rCrit) / newNv
      ELSE
        newR := rCrit
      END
    ELSE
      newR := 0.0d0
    END;

    IF newR < 0.0d0 THEN newR := 0.0d0 END;
    newFv := FourThirdsPi * newR * newR * newR * newNv;

    (* Cap volume fraction at stoichiometric limit *)
    IF newFv > fvMax THEN
      newFv := fvMax;
      (* Adjust Nv to be consistent with capped fv and current r *)
      IF newR > 0.0d0 THEN
        newNv := newFv / (FourThirdsPi * newR * newR * newR)
      END
    END;

    (* Solute depletion proportional to volume fraction increase.
       dfv of precipitate consumes proportional solute.
       For MX: fv ~ cM * Vm_ppt * rho_Fe / (M_ppt * 100)
       => dcM ~ dfv / 0.02, but cap at available solute. *)
    dfv := newFv - pop.fv;
    IF dfv > 0.0d0 THEN
      cMetalNew := cMetal - dfv / 0.02d0;
      IF cMetalNew < 0.0d0 THEN cMetalNew := 0.0d0 END;
      MicdelAlloy.SetElement(solute, sd.metal, cMetalNew);

      IF sd.interstitial # MicdelThermo.Element.CN THEN
        cInterNew := cInter - dfv / 0.02d0;
        IF cInterNew < 0.0d0 THEN cInterNew := 0.0d0 END;
        MicdelAlloy.SetElement(solute, sd.interstitial, cInterNew)
      ELSE
        VAR cC := MicdelAlloy.GetElement(solute, MicdelThermo.Element.C);
            cN := MicdelAlloy.GetElement(solute, MicdelThermo.Element.N);
            depl := dfv / 0.02d0;
        BEGIN
          cC := cC - depl * 0.5d0;
          cN := cN - depl * 0.5d0;
          IF cC < 0.0d0 THEN cC := 0.0d0 END;
          IF cN < 0.0d0 THEN cN := 0.0d0 END;
          MicdelAlloy.SetElement(solute, MicdelThermo.Element.C, cC);
          MicdelAlloy.SetElement(solute, MicdelThermo.Element.N, cN)
        END
      END
    END;

    pop.Nv := newNv;
    pop.r := newR;
    pop.fv := newFv
  END Step;

PROCEDURE FormatPop(READONLY pop : Population) : TEXT =
  BEGIN
    RETURN MicdelThermo.DefaultSpecies[pop.species].name
       & ": Nv=" & Fmt.LongReal(pop.Nv, Fmt.Style.Sci, 3)
       & " r=" & Fmt.LongReal(pop.r * 1.0d9, Fmt.Style.Fix, 1) & "nm"
       & " fv=" & Fmt.LongReal(pop.fv, Fmt.Style.Sci, 3)
  END FormatPop;

BEGIN
END MicdelPrecipitate.
