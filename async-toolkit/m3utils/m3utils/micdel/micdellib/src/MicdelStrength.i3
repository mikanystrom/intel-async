(* Yield stress prediction: Hall-Petch, solid solution, Orowan,
   dislocation strengthening contributions. *)

INTERFACE MicdelStrength;

IMPORT MicdelAlloy, MicdelPrecipitate;

PROCEDURE YieldStress(D_alpha : LONGREAL;
                      READONLY solute : MicdelAlloy.T;
                      READONLY pops : MicdelPrecipitate.Populations;
                      rho_disl : LONGREAL) : LONGREAL;

PROCEDURE HallPetch(D_alpha : LONGREAL) : LONGREAL;
PROCEDURE SolidSolution(READONLY solute : MicdelAlloy.T) : LONGREAL;
PROCEDURE Orowan(READONLY pops : MicdelPrecipitate.Populations) : LONGREAL;
PROCEDURE DislocationStrength(rho_disl : LONGREAL) : LONGREAL;

END MicdelStrength.
