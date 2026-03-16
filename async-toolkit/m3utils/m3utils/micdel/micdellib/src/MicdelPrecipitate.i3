(* Precipitate population kinetics: mean-radius model for each species.
   Tracks number density, mean radius, volume fraction.
   Nucleation, growth, coarsening, and solute depletion. *)

INTERFACE MicdelPrecipitate;

IMPORT MicdelThermo, MicdelAlloy;

TYPE
  Population = RECORD
    species : MicdelThermo.SpeciesId;
    Nv : LONGREAL;       (* number density, 1/m^3 *)
    r  : LONGREAL;       (* mean radius, m *)
    fv : LONGREAL;       (* volume fraction *)
  END;

  Populations = ARRAY MicdelThermo.SpeciesId OF Population;

PROCEDURE InitPopulations() : Populations;

PROCEDURE NucleationRate(READONLY sd : MicdelThermo.SpeciesData;
                         phase : MicdelThermo.Phase;
                         T, cMetal, cInterstitial,
                         rho_disl : LONGREAL) : LONGREAL;

PROCEDURE CriticalRadius(READONLY sd : MicdelThermo.SpeciesData;
                         phase : MicdelThermo.Phase;
                         T, cMetal, cInterstitial : LONGREAL) : LONGREAL;

PROCEDURE GrowthRate(READONLY sd : MicdelThermo.SpeciesData;
                     phase : MicdelThermo.Phase;
                     T, cMetal, cInterstitial, r : LONGREAL) : LONGREAL;

PROCEDURE CoarsenRate(READONLY sd : MicdelThermo.SpeciesData;
                      phase : MicdelThermo.Phase;
                      T, cInterface, r : LONGREAL) : LONGREAL;

PROCEDURE ZenerRadius(READONLY pops : Populations) : LONGREAL;
PROCEDURE ZenerFraction(READONLY pops : Populations) : LONGREAL;

PROCEDURE Step(VAR pop : Population;
               READONLY sd : MicdelThermo.SpeciesData;
               phase : MicdelThermo.Phase;
               T, rho_disl : LONGREAL;
               VAR solute : MicdelAlloy.T;
               dt : LONGREAL);

PROCEDURE FormatPop(READONLY pop : Population) : TEXT;

END MicdelPrecipitate.
