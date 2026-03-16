MODULE MicdelAlloy;

IMPORT MicdelThermo, Fmt;

PROCEDURE GetElement(READONLY a : T; e : MicdelThermo.Element) : LONGREAL =
  BEGIN
    CASE e OF
    | MicdelThermo.Element.C  => RETURN a.C
    | MicdelThermo.Element.N  => RETURN a.N
    | MicdelThermo.Element.V  => RETURN a.V
    | MicdelThermo.Element.Nb => RETURN a.Nb
    | MicdelThermo.Element.Ti => RETURN a.Ti
    | MicdelThermo.Element.Mn => RETURN a.Mn
    | MicdelThermo.Element.Si => RETURN a.Si
    | MicdelThermo.Element.CN => RETURN a.C + a.N
    END
  END GetElement;

PROCEDURE SetElement(VAR a : T; e : MicdelThermo.Element; v : LONGREAL) =
  BEGIN
    CASE e OF
    | MicdelThermo.Element.C  => a.C := v
    | MicdelThermo.Element.N  => a.N := v
    | MicdelThermo.Element.V  => a.V := v
    | MicdelThermo.Element.Nb => a.Nb := v
    | MicdelThermo.Element.Ti => a.Ti := v
    | MicdelThermo.Element.Mn => a.Mn := v
    | MicdelThermo.Element.Si => a.Si := v
    | MicdelThermo.Element.CN => (* no-op *)
    END
  END SetElement;

PROCEDURE Format(READONLY a : T) : TEXT =
  BEGIN
    RETURN "C=" & Fmt.LongReal(a.C, Fmt.Style.Fix, 4)
       & " N=" & Fmt.LongReal(a.N, Fmt.Style.Fix, 4)
       & " V=" & Fmt.LongReal(a.V, Fmt.Style.Fix, 4)
       & " Nb=" & Fmt.LongReal(a.Nb, Fmt.Style.Fix, 4)
       & " Ti=" & Fmt.LongReal(a.Ti, Fmt.Style.Fix, 4)
       & " Mn=" & Fmt.LongReal(a.Mn, Fmt.Style.Fix, 2)
       & " Si=" & Fmt.LongReal(a.Si, Fmt.Style.Fix, 2)
  END Format;

BEGIN
END MicdelAlloy.
