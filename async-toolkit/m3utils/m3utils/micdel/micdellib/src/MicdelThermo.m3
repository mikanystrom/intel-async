MODULE MicdelThermo;

IMPORT Math;

PROCEDURE Solubility(READONLY sp : SolProd; T : LONGREAL) : LONGREAL =
  BEGIN
    RETURN Math.pow(10.0d0, -sp.A / T + sp.B)
  END Solubility;

PROCEDURE Diffusivity(READONLY sd : SpeciesData;
                      phase : Phase; T : LONGREAL) : LONGREAL =
  BEGIN
    RETURN sd.D0[phase] * Math.exp(-sd.Qd[phase] / (R * T))
  END Diffusivity;

PROCEDURE DrivingForce(READONLY sd : SpeciesData; phase : Phase;
                       T, cMetal, cInterstitial : LONGREAL) : LONGREAL =
  VAR
    ks := Solubility(sd.sp[phase], T);
    ss := cMetal * cInterstitial;
  BEGIN
    IF ss <= ks THEN RETURN 0.0d0 END;
    RETURN R * T / sd.Vm * Math.log(ss / ks)
  END DrivingForce;

BEGIN
  DefaultSpecies[SpeciesId.VN] := SpeciesData {
    name := "VN", metal := Element.V, interstitial := Element.N,
    sp := ARRAY Phase OF SolProd {
      SolProd { A := 7840.0d0, B := 3.02d0 },
      SolProd { A := 8330.0d0, B := 3.90d0 }
    },
    gamma := 0.5d0, Vm := 10.29d-6,
    D0 := ARRAY Phase OF LONGREAL { 3.7d-5,  1.0d-4 },
    Qd := ARRAY Phase OF LONGREAL { 186000.0d0, 146000.0d0 }
  };

  DefaultSpecies[SpeciesId.VC] := SpeciesData {
    name := "VC", metal := Element.V, interstitial := Element.C,
    sp := ARRAY Phase OF SolProd {
      SolProd { A := 6560.0d0, B := 4.45d0 },
      SolProd { A := 7050.0d0, B := 4.29d0 }
    },
    gamma := 0.5d0, Vm := 10.86d-6,
    D0 := ARRAY Phase OF LONGREAL { 3.7d-5,  1.0d-4 },
    Qd := ARRAY Phase OF LONGREAL { 186000.0d0, 146000.0d0 }
  };

  DefaultSpecies[SpeciesId.VCN] := SpeciesData {
    name := "V(C,N)", metal := Element.V, interstitial := Element.CN,
    sp := ARRAY Phase OF SolProd {
      SolProd { A := 7700.0d0, B := 3.30d0 },
      SolProd { A := 8100.0d0, B := 3.80d0 }
    },
    gamma := 0.5d0, Vm := 10.5d-6,
    D0 := ARRAY Phase OF LONGREAL { 3.7d-5,  1.0d-4 },
    Qd := ARRAY Phase OF LONGREAL { 186000.0d0, 146000.0d0 }
  };

  DefaultSpecies[SpeciesId.NbC] := SpeciesData {
    name := "NbC", metal := Element.Nb, interstitial := Element.C,
    sp := ARRAY Phase OF SolProd {
      SolProd { A := 6770.0d0, B := 2.26d0 },
      SolProd { A := 7500.0d0, B := 3.00d0 }
    },
    gamma := 0.5d0, Vm := 13.38d-6,
    D0 := ARRAY Phase OF LONGREAL { 8.3d-5,  5.0d-4 },
    Qd := ARRAY Phase OF LONGREAL { 266000.0d0, 220000.0d0 }
  };

  DefaultSpecies[SpeciesId.NbCN] := SpeciesData {
    name := "Nb(C,N)", metal := Element.Nb, interstitial := Element.CN,
    sp := ARRAY Phase OF SolProd {
      SolProd { A := 7500.0d0, B := 2.50d0 },
      SolProd { A := 8000.0d0, B := 3.20d0 }
    },
    gamma := 0.5d0, Vm := 13.0d-6,
    D0 := ARRAY Phase OF LONGREAL { 8.3d-5,  5.0d-4 },
    Qd := ARRAY Phase OF LONGREAL { 266000.0d0, 220000.0d0 }
  };

  DefaultSpecies[SpeciesId.TiN] := SpeciesData {
    name := "TiN", metal := Element.Ti, interstitial := Element.N,
    sp := ARRAY Phase OF SolProd {
      SolProd { A := 15790.0d0, B := 5.40d0 },
      SolProd { A := 15790.0d0, B := 5.40d0 }
    },
    gamma := 0.8d0, Vm := 11.63d-6,
    D0 := ARRAY Phase OF LONGREAL { 1.5d-5,  1.5d-5 },
    Qd := ARRAY Phase OF LONGREAL { 250000.0d0, 250000.0d0 }
  };

  DefaultSpecies[SpeciesId.TiC] := SpeciesData {
    name := "TiC", metal := Element.Ti, interstitial := Element.C,
    sp := ARRAY Phase OF SolProd {
      SolProd { A := 7000.0d0, B := 2.75d0 },
      SolProd { A := 7500.0d0, B := 3.10d0 }
    },
    gamma := 0.8d0, Vm := 12.18d-6,
    D0 := ARRAY Phase OF LONGREAL { 1.5d-5,  1.5d-5 },
    Qd := ARRAY Phase OF LONGREAL { 250000.0d0, 250000.0d0 }
  };
END MicdelThermo.
