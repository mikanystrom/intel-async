(* MICDEL hot-rolling microstructure evolution model.
   Pass-by-pass simulation: reads a schedule file, tracks austenite
   grain size, recrystallization, precipitation, and predicts final
   ferrite grain size and yield stress. *)

MODULE Main;

IMPORT Params, Wr, Stdio, FileRd, Rd, Fmt, Text, Thread,
       Scan, FloatMode, Lex, OSError, MicdelAlloy,
       MicdelState, MicdelSchedule, MicdelStrength,
       MicdelPrecipitate, MicdelThermo;

<* FATAL Thread.Alerted, Wr.Failure *>

PROCEDURE Usage() =
  BEGIN
    Wr.PutText(Stdio.stderr,
      "Usage: micdeltool -schedule <file> [-dt <step>]\n" &
      "  -schedule <file>  : roll schedule input file\n" &
      "  -dt <step>        : time step for interpass evolution (default 0.01 s)\n")
  END Usage;

PROCEDURE ScanLR(t : TEXT) : LONGREAL =
  BEGIN
    TRY
      RETURN Scan.LongReal(t)
    EXCEPT
    | FloatMode.Trap, Lex.Error =>
      Wr.PutText(Stdio.stderr, "Bad number: " & t & "\n");
      RETURN 0.01d0
    END
  END ScanLR;

PROCEDURE Run() RAISES {MicdelSchedule.ParseError} =
  VAR
    schedFile : TEXT := NIL;
    dtStep := 0.01d0;
    rd : Rd.T;
    sched : MicdelSchedule.T;
    state : MicdelState.T;
    nArgs := Params.Count;
    i := 1;
    arg : TEXT;
  BEGIN
    WHILE i < nArgs DO
      arg := Params.Get(i);
      IF Text.Equal(arg, "-schedule") AND i + 1 < nArgs THEN
        INC(i);
        schedFile := Params.Get(i)
      ELSIF Text.Equal(arg, "-dt") AND i + 1 < nArgs THEN
        INC(i);
        dtStep := ScanLR(Params.Get(i))
      ELSIF Text.Equal(arg, "-help") OR Text.Equal(arg, "-h") THEN
        Usage();
        RETURN
      ELSE
        Wr.PutText(Stdio.stderr, "Unknown argument: " & arg & "\n");
        Usage();
        RETURN
      END;
      INC(i)
    END;

    IF schedFile = NIL THEN
      Usage();
      RETURN
    END;

    TRY
      rd := FileRd.Open(schedFile)
    EXCEPT
    | OSError.E =>
      Wr.PutText(Stdio.stderr, "Cannot open: " & schedFile & "\n");
      RETURN
    END;
    sched := MicdelSchedule.ParseSchedule(rd);
    TRY Rd.Close(rd) EXCEPT Rd.Failure => END;

    Wr.PutText(Stdio.stdout, "# MICDEL Hot-Rolling Microstructure Model\n");
    Wr.PutText(Stdio.stdout, "# Schedule: " & schedFile & "\n");
    Wr.PutText(Stdio.stdout, "# " & MicdelSchedule.FormatSchedule(sched));
    Wr.PutText(Stdio.stdout, "#\n");

    state := MicdelState.Init(sched.comp, sched.D_gamma_0, sched.T_reheat);

    Wr.PutText(Stdio.stdout, "# Pass\t" & MicdelState.FormatHeader() & "\n");

    FOR p := 0 TO sched.nPasses - 1 DO
      VAR pass := sched.passes[p];
      BEGIN
        state.temp := pass.T_entry;
        MicdelState.ApplyDeformation(state, pass.strain, pass.strainRate);
        MicdelState.EvolveInterpass(state, pass.t_interpass,
                                    pass.coolingRate, dtStep);
        Wr.PutText(Stdio.stdout, Fmt.Int(p + 1) & "\t"
                   & MicdelState.Format(state) & "\n")
      END
    END;

    MicdelState.Transform(state, sched.cooling.rate);

    Wr.PutText(Stdio.stdout, "#\n");
    Wr.PutText(Stdio.stdout, "# === Final Results ===\n");
    Wr.PutText(Stdio.stdout, "# Ferrite grain size: "
               & Fmt.LongReal(state.D_alpha * 1.0d6, Fmt.Style.Fix, 1)
               & " um\n");
    Wr.PutText(Stdio.stdout, "# Yield stress:       "
               & Fmt.LongReal(state.sigma_y, Fmt.Style.Fix, 1)
               & " MPa\n");

    Wr.PutText(Stdio.stdout, "#   sigma_0 (friction):   53.9 MPa\n");
    Wr.PutText(Stdio.stdout, "#   sigma_ss (sol.soln.): "
               & Fmt.LongReal(MicdelStrength.SolidSolution(state.solute),
                               Fmt.Style.Fix, 1) & " MPa\n");
    Wr.PutText(Stdio.stdout, "#   sigma_HP (Hall-Petch): "
               & Fmt.LongReal(MicdelStrength.HallPetch(state.D_alpha),
                               Fmt.Style.Fix, 1) & " MPa\n");
    Wr.PutText(Stdio.stdout, "#   sigma_Or (Orowan):    "
               & Fmt.LongReal(MicdelStrength.Orowan(state.precip),
                               Fmt.Style.Fix, 1) & " MPa\n");
    Wr.PutText(Stdio.stdout, "#   sigma_d (disloc.):    "
               & Fmt.LongReal(MicdelStrength.DislocationStrength(state.rho_disl),
                               Fmt.Style.Fix, 1) & " MPa\n");

    Wr.PutText(Stdio.stdout, "#\n# === Precipitate Populations ===\n");
    FOR s := FIRST(MicdelThermo.SpeciesId) TO LAST(MicdelThermo.SpeciesId) DO
      IF state.precip[s].Nv > 0.0d0 THEN
        Wr.PutText(Stdio.stdout, "#   "
                   & MicdelPrecipitate.FormatPop(state.precip[s]) & "\n")
      END
    END;

    Wr.PutText(Stdio.stdout, "#\n# Solute remaining: "
               & MicdelAlloy.Format(state.solute) & "\n");

    Wr.Flush(Stdio.stdout)
  END Run;

BEGIN
  TRY
    Run()
  EXCEPT
  | MicdelSchedule.ParseError(msg) =>
    Wr.PutText(Stdio.stderr, "Parse error: " & msg & "\n")
  END
END Main.
