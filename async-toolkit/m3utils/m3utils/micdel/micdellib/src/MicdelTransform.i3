(* Gamma-to-alpha (austenite-to-ferrite) transformation.
   Ae3 calculation, ferrite grain size prediction,
   intragranular nucleation refinement from V(C,N). *)

INTERFACE MicdelTransform;

IMPORT MicdelAlloy, MicdelPrecipitate;

TYPE
  Params = RECORD
    Ae3_base : LONGREAL;
    kC  : LONGREAL;
    kMn : LONGREAL;
    kSi : LONGREAL;
    kNi : LONGREAL;
    kCr : LONGREAL;
    f_factor : LONGREAL;
    nCCT : LONGREAL;
  END;

CONST
  Default = Params {
    Ae3_base := 1183.0d0 + 273.15d0,
    kC  := -203.0d0,
    kMn := -30.0d0,
    kSi := 44.7d0,
    kNi := -15.2d0,
    kCr := -11.0d0,
    f_factor := 0.8d0,
    nCCT := 1.5d0
  };

PROCEDURE Ae3(READONLY par : Params; READONLY comp : MicdelAlloy.T) : LONGREAL;

PROCEDURE FerriteFraction(READONLY par : Params;
                          T, coolingRate : LONGREAL;
                          READONLY comp : MicdelAlloy.T) : LONGREAL;

PROCEDURE FerriteGrainSize(D_gamma : LONGREAL;
                           coolingRate : LONGREAL;
                           READONLY pops : MicdelPrecipitate.Populations;
                           READONLY comp : MicdelAlloy.T) : LONGREAL;

PROCEDURE IntragranularRefinement(
              READONLY pops : MicdelPrecipitate.Populations) : LONGREAL;

END MicdelTransform.
