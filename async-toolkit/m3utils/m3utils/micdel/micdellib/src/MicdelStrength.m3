MODULE MicdelStrength;

IMPORT MicdelAlloy, MicdelPrecipitate, MicdelThermo, Math;

CONST
  Sigma0 = 53.9d0;         (* lattice friction, MPa *)
  Ky     = 18.14d0;        (* Hall-Petch, MPa*mm^0.5 *)
  AlphaT = 0.33d0;
  Taylor_M = 3.06d0;
  G_ferrite = 81000.0d0;   (* shear modulus, MPa *)
  Burgers = 2.48d-10;      (* m *)
  Pi = 3.14159265358979323846d0;

PROCEDURE YieldStress(D_alpha : LONGREAL;
                      READONLY solute : MicdelAlloy.T;
                      READONLY pops : MicdelPrecipitate.Populations;
                      rho_disl : LONGREAL) : LONGREAL =
  BEGIN
    RETURN Sigma0
           + SolidSolution(solute)
           + HallPetch(D_alpha)
           + Orowan(pops)
           + DislocationStrength(rho_disl)
  END YieldStress;

PROCEDURE HallPetch(D_alpha : LONGREAL) : LONGREAL =
  VAR d_mm := D_alpha * 1000.0d0;
  BEGIN
    IF d_mm <= 0.0d0 THEN RETURN 0.0d0 END;
    RETURN Ky / Math.sqrt(d_mm)
  END HallPetch;

PROCEDURE SolidSolution(READONLY solute : MicdelAlloy.T) : LONGREAL =
  BEGIN
    RETURN 4570.0d0 * solute.C
         + 3750.0d0 * solute.N
         + 32.0d0   * solute.Mn
         + 84.0d0   * solute.Si
         + 11.0d0   * solute.Mo
  END SolidSolution;

PROCEDURE Orowan(READONLY pops : MicdelPrecipitate.Populations) : LONGREAL =
  VAR
    total := 0.0d0;
    fv, r, lambda, contrib : LONGREAL;
  BEGIN
    FOR s := FIRST(MicdelThermo.SpeciesId) TO LAST(MicdelThermo.SpeciesId) DO
      fv := pops[s].fv;
      r := pops[s].r;
      IF fv > 1.0d-10 AND r > 1.0d-10 THEN
        lambda := (Math.sqrt(2.0d0 * Pi / (3.0d0 * fv))
                   - Math.sqrt(8.0d0 / 3.0d0)) * r;
        IF lambda > 0.0d0 THEN
          contrib := 0.538d0 * G_ferrite * Burgers / lambda
                     * Math.log(r / Burgers);
          IF contrib > 0.0d0 THEN total := total + contrib END
        END
      END
    END;
    RETURN total
  END Orowan;

PROCEDURE DislocationStrength(rho_disl : LONGREAL) : LONGREAL =
  BEGIN
    IF rho_disl <= 0.0d0 THEN RETURN 0.0d0 END;
    RETURN AlphaT * Taylor_M * G_ferrite * Burgers * Math.sqrt(rho_disl)
           / 1.0d6
  END DislocationStrength;

BEGIN
END MicdelStrength.
