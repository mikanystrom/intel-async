MODULE MicdelSchedule;

IMPORT Rd, Wr, TextWr, MicdelAlloy, Fmt, Scan, Text, FloatMode, Lex,
       Thread;

<* FATAL Thread.Alerted, Wr.Failure *>

TYPE PassList = REF RECORD
  pass : Pass;
  next : PassList;
END;

PROCEDURE ParseSchedule(rd : Rd.T) : T RAISES {ParseError} =
  VAR
    sched : T;
    line : TEXT;
    passHead : PassList := NIL;
    passTail : PassList := NIL;
    nPasses := 0;
    gotComp := FALSE;
    gotReheat := FALSE;
    gotCooling := FALSE;
  BEGIN
    sched.comp := MicdelAlloy.Zero;
    sched.T_reheat := 1473.0d0;
    sched.D_gamma_0 := 50.0d-6;
    sched.cooling := Cooling {
      rate := 10.0d0, T_coil := 873.0d0,
      t_coil := 3600.0d0, coilRate := 0.01d0
    };

    TRY
      LOOP
        line := Rd.GetLine(rd);
        line := StripComment(line);
        IF Text.Length(line) = 0 THEN (* skip blank *)
        ELSIF StartsWith(line, "COMPOSITION") THEN
          ParseComposition(line, sched.comp);
          gotComp := TRUE
        ELSIF StartsWith(line, "REHEAT") THEN
          ParseReheat(line, sched.T_reheat, sched.D_gamma_0);
          gotReheat := TRUE
        ELSIF StartsWith(line, "PASS") THEN
          VAR p := ParsePass(line);
              node := NEW(PassList, pass := p, next := NIL);
          BEGIN
            IF passTail = NIL THEN
              passHead := node; passTail := node
            ELSE
              passTail.next := node; passTail := node
            END;
            INC(nPasses)
          END
        ELSIF StartsWith(line, "COOLING") THEN
          ParseCooling(line, sched.cooling);
          gotCooling := TRUE
        END
      END
    EXCEPT
    | Rd.EndOfFile => (* normal end of input *)
    | Rd.Failure => RAISE ParseError("I/O error reading schedule")
    | Thread.Alerted => RAISE ParseError("interrupted")
    END;

    IF NOT gotComp THEN RAISE ParseError("missing COMPOSITION line") END;
    IF NOT gotReheat THEN RAISE ParseError("missing REHEAT line") END;
    IF nPasses = 0 THEN RAISE ParseError("no PASS lines found") END;
    IF NOT gotCooling THEN RAISE ParseError("missing COOLING line") END;

    sched.nPasses := nPasses;
    sched.passes := NEW(REF ARRAY OF Pass, nPasses);
    VAR node := passHead; i := 0;
    BEGIN
      WHILE node # NIL DO
        sched.passes[i] := node.pass;
        node := node.next;
        INC(i)
      END
    END;

    RETURN sched
  END ParseSchedule;

PROCEDURE StripComment(line : TEXT) : TEXT =
  VAR len := Text.Length(line);
  BEGIN
    FOR i := 0 TO len - 1 DO
      IF Text.GetChar(line, i) = '#' THEN
        line := Text.Sub(line, 0, i);
        EXIT
      END
    END;
    RETURN Trim(line)
  END StripComment;

PROCEDURE Trim(t : TEXT) : TEXT =
  VAR
    len := Text.Length(t);
    start := 0;
    stop := len;
  BEGIN
    WHILE start < len AND Text.GetChar(t, start) = ' ' DO INC(start) END;
    WHILE stop > start AND Text.GetChar(t, stop - 1) = ' ' DO DEC(stop) END;
    RETURN Text.Sub(t, start, stop - start)
  END Trim;

PROCEDURE StartsWith(line, prefix : TEXT) : BOOLEAN =
  BEGIN
    RETURN Text.Length(line) >= Text.Length(prefix)
           AND Text.Equal(Text.Sub(line, 0, Text.Length(prefix)), prefix)
  END StartsWith;

PROCEDURE FindKV(line : TEXT; key : TEXT; VAR val : LONGREAL) : BOOLEAN =
  VAR
    kLen := Text.Length(key);
    len := Text.Length(line);
  BEGIN
    FOR i := 0 TO len - kLen - 1 DO
      IF Text.Equal(Text.Sub(line, i, kLen), key)
         AND i + kLen < len
         AND Text.GetChar(line, i + kLen) = '=' THEN
        VAR
          vStart := i + kLen + 1;
          vEnd := vStart;
        BEGIN
          WHILE vEnd < len
                AND Text.GetChar(line, vEnd) # ' '
                AND Text.GetChar(line, vEnd) # '\t' DO
            INC(vEnd)
          END;
          TRY
            val := Scan.LongReal(Text.Sub(line, vStart, vEnd - vStart));
            RETURN TRUE
          EXCEPT
          | FloatMode.Trap, Lex.Error => RETURN FALSE
          END
        END
      END
    END;
    RETURN FALSE
  END FindKV;

PROCEDURE ParseComposition(line : TEXT; VAR comp : MicdelAlloy.T)
    RAISES {ParseError} =
  VAR v : LONGREAL;
  BEGIN
    IF FindKV(line, "C", v)  THEN comp.C := v END;
    IF FindKV(line, "N", v)  THEN comp.N := v END;
    IF FindKV(line, "V", v)  THEN comp.V := v END;
    IF FindKV(line, "Nb", v) THEN comp.Nb := v END;
    IF FindKV(line, "Ti", v) THEN comp.Ti := v END;
    IF FindKV(line, "Mn", v) THEN comp.Mn := v END;
    IF FindKV(line, "Si", v) THEN comp.Si := v END;
    IF FindKV(line, "Cr", v) THEN comp.Cr := v END;
    IF FindKV(line, "Mo", v) THEN comp.Mo := v END;
    IF FindKV(line, "P", v)  THEN comp.P := v END;
    IF FindKV(line, "S", v)  THEN comp.S := v END;
    IF comp.C <= 0.0d0 AND comp.N <= 0.0d0 THEN
      RAISE ParseError("COMPOSITION: need at least C or N > 0")
    END
  END ParseComposition;

PROCEDURE ParseReheat(line : TEXT; VAR T, D : LONGREAL)
    RAISES {ParseError} =
  VAR v : LONGREAL;
  BEGIN
    IF FindKV(line, "T", v) THEN T := v
    ELSE RAISE ParseError("REHEAT: missing T=") END;
    IF FindKV(line, "D_gamma", v) THEN D := v END
  END ParseReheat;

PROCEDURE ParsePass(line : TEXT) : Pass RAISES {ParseError} =
  VAR
    p : Pass;
    v : LONGREAL;
  BEGIN
    p.strain := 0.3d0;
    p.strainRate := 10.0d0;
    p.T_entry := 1373.0d0;
    p.t_interpass := 5.0d0;
    p.coolingRate := 2.0d0;

    IF FindKV(line, "eps", v)      THEN p.strain := v END;
    IF FindKV(line, "rate", v)     THEN p.strainRate := v END;
    IF FindKV(line, "T", v)        THEN p.T_entry := v END;
    IF FindKV(line, "t_inter", v)  THEN p.t_interpass := v END;
    IF FindKV(line, "cool", v)     THEN p.coolingRate := v END;

    IF p.strain <= 0.0d0 THEN
      RAISE ParseError("PASS: strain must be > 0")
    END;
    RETURN p
  END ParsePass;

PROCEDURE ParseCooling(line : TEXT; VAR c : Cooling)
    RAISES {ParseError} =
  VAR v : LONGREAL;
  BEGIN
    IF FindKV(line, "rate", v)     THEN c.rate := v
    ELSE RAISE ParseError("COOLING: missing rate=") END;
    IF FindKV(line, "T_coil", v)   THEN c.T_coil := v END;
    IF FindKV(line, "t_coil", v)   THEN c.t_coil := v END;
    IF FindKV(line, "coilRate", v) THEN c.coilRate := v END
  END ParseCooling;

PROCEDURE FormatSchedule(READONLY sched : T) : TEXT =
  VAR wr := TextWr.New();
  BEGIN
    Wr.PutText(wr, "COMPOSITION  " & MicdelAlloy.Format(sched.comp) & "\n");
    Wr.PutText(wr, "REHEAT  T=" & Fmt.LongReal(sched.T_reheat, Fmt.Style.Fix, 1)
               & "  D_gamma=" & Fmt.LongReal(sched.D_gamma_0, Fmt.Style.Sci, 2) & "\n");
    FOR i := 0 TO sched.nPasses - 1 DO
      VAR p := sched.passes[i];
      BEGIN
        Wr.PutText(wr, "PASS  eps=" & Fmt.LongReal(p.strain, Fmt.Style.Fix, 3)
                   & "  rate=" & Fmt.LongReal(p.strainRate, Fmt.Style.Fix, 1)
                   & "  T=" & Fmt.LongReal(p.T_entry, Fmt.Style.Fix, 1)
                   & "  t_inter=" & Fmt.LongReal(p.t_interpass, Fmt.Style.Fix, 1)
                   & "  cool=" & Fmt.LongReal(p.coolingRate, Fmt.Style.Fix, 1) & "\n")
      END
    END;
    Wr.PutText(wr, "COOLING  rate=" & Fmt.LongReal(sched.cooling.rate, Fmt.Style.Fix, 1)
               & "  T_coil=" & Fmt.LongReal(sched.cooling.T_coil, Fmt.Style.Fix, 1)
               & "  t_coil=" & Fmt.LongReal(sched.cooling.t_coil, Fmt.Style.Fix, 0)
               & "  coilRate=" & Fmt.LongReal(sched.cooling.coilRate, Fmt.Style.Fix, 3) & "\n");
    RETURN TextWr.ToText(wr)
  END FormatSchedule;

BEGIN
END MicdelSchedule.
