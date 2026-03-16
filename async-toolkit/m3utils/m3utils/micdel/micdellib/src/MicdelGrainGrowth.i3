(* Grain growth kinetics with Zener drag from precipitates. *)

INTERFACE MicdelGrainGrowth;

IMPORT MicdelPrecipitate;

TYPE
  Params = RECORD
    m     : LONGREAL;   (* grain growth exponent, typically 2-4 *)
    k0    : LONGREAL;   (* pre-exponential, m^m/s *)
    Qgg   : LONGREAL;   (* activation energy, J/mol *)
    alpha : LONGREAL;   (* Zener constant *)
  END;

CONST
  Default = Params {
    m     := 2.0d0,
    k0    := 4.1d-3,
    Qgg   := 200000.0d0,
    alpha := 0.05d0
  };

PROCEDURE ZenerLimit(READONLY par : Params;
                     READONLY pops : MicdelPrecipitate.Populations) : LONGREAL;

PROCEDURE GrowthRate(READONLY par : Params;
                     D, T : LONGREAL;
                     READONLY pops : MicdelPrecipitate.Populations) : LONGREAL;

PROCEDURE Step(READONLY par : Params;
               VAR D : LONGREAL;
               T : LONGREAL;
               READONLY pops : MicdelPrecipitate.Populations;
               dt : LONGREAL);

END MicdelGrainGrowth.
