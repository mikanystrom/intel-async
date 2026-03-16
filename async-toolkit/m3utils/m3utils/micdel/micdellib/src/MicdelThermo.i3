(* Thermodynamic data for microalloy precipitate species.
   Solubility products, diffusion coefficients, interfacial energies.
   Data from the Lagneborg-Hutchinson-Siwecki-Zajac monograph. *)

INTERFACE MicdelThermo;

TYPE
  Phase = {Austenite, Ferrite};

  Element = {C, N, V, Nb, Ti, Mn, Si, CN};

  SolProd = RECORD
    A, B : LONGREAL;  (* log10([M][X]) = -A/T + B, wt%, T in Kelvin *)
  END;

  SpeciesId = {VN, VC, VCN, NbC, NbCN, TiN, TiC};

  SpeciesData = RECORD
    name : TEXT;
    metal : Element;
    interstitial : Element;
    sp : ARRAY Phase OF SolProd;
    gamma : LONGREAL;        (* precipitate/matrix interfacial energy, J/m^2 *)
    Vm : LONGREAL;           (* molar volume of precipitate, m^3/mol *)
    D0 : ARRAY Phase OF LONGREAL;  (* pre-exp diffusivity of controlling solute, m^2/s *)
    Qd : ARRAY Phase OF LONGREAL;  (* activation energy for diffusion, J/mol *)
  END;

CONST
  R   = 8.314462d0;      (* J/(mol*K) *)
  KB  = 1.380649d-23;    (* J/K *)
  Nav = 6.02214076d23;   (* 1/mol *)

PROCEDURE Solubility(READONLY sp : SolProd; T : LONGREAL) : LONGREAL;
PROCEDURE Diffusivity(READONLY sd : SpeciesData;
                      phase : Phase; T : LONGREAL) : LONGREAL;
PROCEDURE DrivingForce(READONLY sd : SpeciesData; phase : Phase;
                       T, cMetal, cInterstitial : LONGREAL) : LONGREAL;

VAR DefaultSpecies : ARRAY SpeciesId OF SpeciesData;

END MicdelThermo.
