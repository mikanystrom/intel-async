(* Combined microstructure state for the MICDEL pass-by-pass model.
   Couples recrystallization, grain growth, precipitation, and
   gamma-to-alpha transformation. *)

INTERFACE MicdelState;

IMPORT MicdelAlloy, MicdelPrecipitate;

TYPE
  T = RECORD
    D_gamma  : LONGREAL;   (* austenite grain diameter, m *)
    X_rex    : LONGREAL;   (* recrystallized fraction, 0-1 *)
    eps_ret  : LONGREAL;   (* retained strain *)
    rho_disl : LONGREAL;   (* dislocation density, 1/m^2 *)
    temp     : LONGREAL;   (* temperature, K *)
    solute   : MicdelAlloy.T;
    precip   : MicdelPrecipitate.Populations;
    time     : LONGREAL;   (* elapsed time, s *)

    D_alpha     : LONGREAL;   (* ferrite grain size, m *)
    sigma_y     : LONGREAL;   (* predicted yield stress, MPa *)
    transformed : BOOLEAN;
  END;

PROCEDURE Init(READONLY comp : MicdelAlloy.T;
               D_gamma_0 : LONGREAL;
               T_reheat : LONGREAL) : T;

PROCEDURE ApplyDeformation(VAR st : T;
                           eps, epsRate : LONGREAL);

PROCEDURE EvolveInterpass(VAR st : T;
                          dt_total : LONGREAL;
                          coolingRate : LONGREAL;
                          dtStep : LONGREAL := 0.01d0);

PROCEDURE Transform(VAR st : T;
                    coolingRate : LONGREAL);

PROCEDURE Format(READONLY st : T) : TEXT;
PROCEDURE FormatHeader() : TEXT;

END MicdelState.
