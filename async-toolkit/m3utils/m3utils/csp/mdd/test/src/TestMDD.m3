(* TestMDD -- acceptance tests for the MDD library.

   Tests cover:
     1. Terminal nodes and basic identity
     2. Singleton construction and node structure
     3. Union, Intersection, Difference
     4. Quasi-reduced form (no level skipping)
     5. Hash-consing (canonical form)
     6. Event construction
     7. Saturation on a small example (2-process mutual exclusion)
     8. Saturation on a 3-process ring (dining philosophers N=3) *)

MODULE TestMDD EXPORTS Main;
IMPORT MDD, MDDEvent, MDDSaturation;
IMPORT IO, Fmt;

VAR nTests := 0;
    nPassed := 0;

PROCEDURE Check(name: TEXT; cond: BOOLEAN) =
  BEGIN
    INC(nTests);
    IF cond THEN
      INC(nPassed);
    ELSE
      IO.Put("FAIL: " & name & "\n");
    END;
  END Check;

(* ================================================================
   Test 1: Terminals
   ================================================================ *)

PROCEDURE TestTerminals() =
  BEGIN
    IO.Put("--- Test 1: Terminals ---\n");
    Check("Zero is empty", MDD.IsEmpty(MDD.Zero()));
    Check("One is not empty", NOT MDD.IsEmpty(MDD.One()));
    Check("Zero = Zero", MDD.Equal(MDD.Zero(), MDD.Zero()));
    Check("One = One", MDD.Equal(MDD.One(), MDD.One()));
    Check("Zero # One", NOT MDD.Equal(MDD.Zero(), MDD.One()));
    Check("Zero level = -1", MDD.NodeLevel(MDD.Zero()) = -1);
    Check("One level = -1", MDD.NodeLevel(MDD.One()) = -1);
  END TestTerminals;

(* ================================================================
   Test 2: Singleton and MakeNode
   ================================================================ *)

PROCEDURE TestSingleton() =
  VAR
    s1, s2, s3 : MDD.T;
    domains := ARRAY [0..1] OF CARDINAL { 3, 2 };
    vals1   := ARRAY [0..1] OF CARDINAL { 1, 0 };
    vals2   := ARRAY [0..1] OF CARDINAL { 2, 1 };
    vals3   := ARRAY [0..1] OF CARDINAL { 1, 0 };
  BEGIN
    IO.Put("--- Test 2: Singleton and MakeNode ---\n");
    MDD.SetLevels(2, domains);
    Check("NumLevels = 2", MDD.NumLevels() = 2);
    Check("Domain(0) = 3", MDD.Domain(0) = 3);
    Check("Domain(1) = 2", MDD.Domain(1) = 2);

    s1 := MDD.Singleton(vals1);
    s2 := MDD.Singleton(vals2);
    s3 := MDD.Singleton(vals3);

    Check("singleton not empty", NOT MDD.IsEmpty(s1));
    Check("singleton level = 1", MDD.NodeLevel(s1) = 1);
    Check("identical singletons are equal (canonical)",
          MDD.Equal(s1, s3));
    Check("different singletons are not equal",
          NOT MDD.Equal(s1, s2));
    Check("Size(s1) > 0", MDD.Size(s1) > 0);
  END TestSingleton;

(* ================================================================
   Test 3: Union, Intersection, Difference
   ================================================================ *)

PROCEDURE TestSetOps() =
  VAR
    s1, s2, u, inter, diff : MDD.T;
    domains := ARRAY [0..1] OF CARDINAL { 3, 2 };
    vals1   := ARRAY [0..1] OF CARDINAL { 0, 0 };
    vals2   := ARRAY [0..1] OF CARDINAL { 1, 1 };
  BEGIN
    IO.Put("--- Test 3: Union, Intersection, Difference ---\n");
    MDD.SetLevels(2, domains);

    s1 := MDD.Singleton(vals1);  (* state (0,0) *)
    s2 := MDD.Singleton(vals2);  (* state (1,1) *)

    (* Union *)
    u := MDD.Union(s1, s2);
    Check("Union(s1,s2) not empty", NOT MDD.IsEmpty(u));
    Check("Union(s1,Zero) = s1", MDD.Equal(MDD.Union(s1, MDD.Zero()), s1));
    Check("Union(Zero,s2) = s2", MDD.Equal(MDD.Union(MDD.Zero(), s2), s2));
    Check("Union(s1,s1) = s1", MDD.Equal(MDD.Union(s1, s1), s1));
    Check("Union is commutative", MDD.Equal(MDD.Union(s1, s2),
                                             MDD.Union(s2, s1)));

    (* Intersection *)
    inter := MDD.Intersection(s1, s2);
    Check("Intersection of disjoint is empty", MDD.IsEmpty(inter));
    Check("Intersection(s1,s1) = s1",
          MDD.Equal(MDD.Intersection(s1, s1), s1));
    Check("Intersection(u,s1) = s1",
          MDD.Equal(MDD.Intersection(u, s1), s1));

    (* Difference *)
    diff := MDD.Difference(u, s1);
    Check("Difference(u,s1) = s2", MDD.Equal(diff, s2));
    Check("Difference(s1,s1) = Zero",
          MDD.IsEmpty(MDD.Difference(s1, s1)));
    Check("Difference(s1,Zero) = s1",
          MDD.Equal(MDD.Difference(s1, MDD.Zero()), s1));
  END TestSetOps;

(* ================================================================
   Test 4: Quasi-reduced form
   ================================================================ *)

PROCEDURE TestQuasiReduced() =
  VAR
    s : MDD.T;
    domains := ARRAY [0..2] OF CARDINAL { 2, 2, 2 };
    vals    := ARRAY [0..2] OF CARDINAL { 0, 0, 0 };
  BEGIN
    IO.Put("--- Test 4: Quasi-reduced form ---\n");
    MDD.SetLevels(3, domains);

    s := MDD.Singleton(vals);
    (* Every level must be present: root at level 2, then 1, then 0 *)
    Check("root at level 2", MDD.NodeLevel(s) = 2);
    Check("child at level 1",
          MDD.NodeLevel(MDD.NodeChild(s, 0)) = 1);
    Check("grandchild at level 0",
          MDD.NodeLevel(MDD.NodeChild(MDD.NodeChild(s, 0), 0)) = 0);
    Check("leaf is One",
          MDD.Equal(MDD.NodeChild(
                     MDD.NodeChild(MDD.NodeChild(s, 0), 0), 0),
                    MDD.One()));
    Check("non-taken child is Zero",
          MDD.Equal(MDD.NodeChild(s, 1), MDD.Zero()));
  END TestQuasiReduced;

(* ================================================================
   Test 5: Hash-consing
   ================================================================ *)

PROCEDURE TestCanonical() =
  VAR
    s1, s2, u1, u2 : MDD.T;
    domains := ARRAY [0..1] OF CARDINAL { 3, 2 };
    v1 := ARRAY [0..1] OF CARDINAL { 0, 0 };
    v2 := ARRAY [0..1] OF CARDINAL { 1, 1 };
  BEGIN
    IO.Put("--- Test 5: Hash-consing (canonical form) ---\n");
    MDD.SetLevels(2, domains);

    s1 := MDD.Singleton(v1);
    s2 := MDD.Singleton(v2);
    u1 := MDD.Union(s1, s2);
    u2 := MDD.Union(s1, s2);
    Check("Union same args -> same object", MDD.Equal(u1, u2));

    (* Build same set from scratch *)
    VAR
      u3 := MDD.Union(MDD.Singleton(v2), MDD.Singleton(v1));
    BEGIN
      Check("Union built in different order -> same MDD",
            MDD.Equal(u1, u3));
    END;
  END TestCanonical;

(* ================================================================
   Test 6: Event construction
   ================================================================ *)

PROCEDURE TestEvents() =
  VAR
    e : MDDEvent.T;
    m : MDDEvent.Matrix;
    entries := ARRAY [0..1] OF MDDEvent.Entry {
                 MDDEvent.Entry { 0, 1 },
                 MDDEvent.Entry { 1, 0 } };
  BEGIN
    IO.Put("--- Test 6: Event construction ---\n");
    e := MDDEvent.NewTauEvent(0, NEW(MDDEvent.Matrix, 2));
    NARROW(MDDEvent.GetMatrix(e, 0), MDDEvent.Matrix)^
      := entries;
    Check("tau top = 0", MDDEvent.TopLevel(e) = 0);
    Check("tau bot = 0", MDDEvent.BotLevel(e) = 0);
    Check("tau not identity at level 0",
          NOT MDDEvent.IsIdentity(e, 0));
    Check("tau identity at level 1",
          MDDEvent.IsIdentity(e, 1));

    m := MDDEvent.GetMatrix(e, 0);
    Check("matrix not nil at level 0", m # NIL);
    Check("matrix nil at level 1", MDDEvent.GetMatrix(e, 1) = NIL);

    (* Sync event *)
    VAR
      topEntries := NEW(MDDEvent.Matrix, 1);
      botEntries := NEW(MDDEvent.Matrix, 1);
      se : MDDEvent.T;
    BEGIN
      topEntries[0] := MDDEvent.Entry { 0, 1 };
      botEntries[0] := MDDEvent.Entry { 0, 1 };
      se := MDDEvent.NewSyncEvent(2, 0, topEntries, botEntries);
      Check("sync top = 2", MDDEvent.TopLevel(se) = 2);
      Check("sync bot = 0", MDDEvent.BotLevel(se) = 0);
      Check("sync identity at level 1", MDDEvent.IsIdentity(se, 1));
      Check("sync not identity at level 2",
            NOT MDDEvent.IsIdentity(se, 2));
      Check("sync not identity at level 0",
            NOT MDDEvent.IsIdentity(se, 0));
    END;
  END TestEvents;

(* ================================================================
   Test 7: Saturation on 2-state mutual exclusion
   ================================================================ *)

(* Two processes, each with 2 states: idle(0), critical(1).
   Tau: idle -> critical for each process.
   Tau: critical -> idle for each process.
   No synchronisation.
   Reachable set should be all 4 states: {(0,0),(0,1),(1,0),(1,1)}.
   No deadlock (every state can transition). *)

PROCEDURE TestSaturationMutex() =
  VAR
    domains := ARRAY [0..1] OF CARDINAL { 2, 2 };
    init := ARRAY [0..1] OF CARDINAL { 0, 0 };
    events : MDDSaturation.EventList;
    reached, hasSucc, deadlocked : MDD.T;

    (* Process 0 (level 0): idle<->critical *)
    m0 := NEW(MDDEvent.Matrix, 2);
    (* Process 1 (level 1): idle<->critical *)
    m1 := NEW(MDDEvent.Matrix, 2);
  BEGIN
    IO.Put("--- Test 7: Saturation (2-state mutex) ---\n");
    MDD.SetLevels(2, domains);

    m0[0] := MDDEvent.Entry { 0, 1 };
    m0[1] := MDDEvent.Entry { 1, 0 };
    m1[0] := MDDEvent.Entry { 0, 1 };
    m1[1] := MDDEvent.Entry { 1, 0 };

    events := NEW(MDDSaturation.EventList, 2);
    events[0] := MDDEvent.NewTauEvent(0, m0);
    events[1] := MDDEvent.NewTauEvent(1, m1);

    VAR initial := MDD.Singleton(init);
    BEGIN
      reached := MDDSaturation.ComputeReachable(initial, events);
      IO.Put("  reached MDD size: " & Fmt.Int(MDD.Size(reached)) & "\n");

      (* All 4 states should be reachable *)
      VAR
        s00 := MDD.Singleton(ARRAY [0..1] OF CARDINAL { 0, 0 });
        s01 := MDD.Singleton(ARRAY [0..1] OF CARDINAL { 0, 1 });
        s10 := MDD.Singleton(ARRAY [0..1] OF CARDINAL { 1, 0 });
        s11 := MDD.Singleton(ARRAY [0..1] OF CARDINAL { 1, 1 });
        all4 := MDD.Union(MDD.Union(s00, s01), MDD.Union(s10, s11));
      BEGIN
        Check("reached = all 4 states", MDD.Equal(reached, all4));
      END;

      (* Deadlock check *)
      hasSucc := MDDSaturation.HasSuccessor(reached, events);
      deadlocked := MDD.Difference(reached, hasSucc);
      Check("no deadlock in mutex", MDD.IsEmpty(deadlocked));
    END;
  END TestSaturationMutex;

(* ================================================================
   Test 8: Saturation on dining philosophers N=2
   ================================================================ *)

(* 4 processes: phil0, fork0, phil1, fork1 (levels 0..3)
   Philosopher states: thinking(0), hungry(1), eating(2)
   Fork states: free(0), taken(1)

   Sync events (channels):
     phil_i picks up left fork:   phil_i: 0->1, fork_i: 0->1
     phil_i picks up right fork:  phil_i: 1->2, fork_{(i+1)%2}: 0->1
     phil_i puts down left fork:  phil_i: 2->0, fork_i: 1->0
     phil_i puts down right fork: phil_i: 2->0, fork_{(i+1)%2}: 1->0

   For deterministic dining (both forks acquired together):
     phil_i: thinking(0)->eating(2), fork_i: 0->1, fork_{(i+1)%2}: 0->1

   This should deadlock: both can go to hungry=1 simultaneously. *)

PROCEDURE TestSaturationDining2() =
  VAR
    (* Level ordering: fork0=0, phil0=1, fork1=2, phil1=3 *)
    domains := ARRAY [0..3] OF CARDINAL { 2, 3, 2, 3 };
    init    := ARRAY [0..3] OF CARDINAL { 0, 0, 0, 0 };
    events  : MDDSaturation.EventList;
    reached, hasSucc, deadlocked : MDD.T;
    nEvents := 0;
    eventList : ARRAY [0..9] OF MDDEvent.T; (* more than enough *)
  BEGIN
    IO.Put("--- Test 8: Saturation (dining N=2) ---\n");
    MDD.SetLevels(4, domains);

    (* Phil 0 (level 1) picks up fork 0 (level 0): think->hungry *)
    VAR
      pm := NEW(MDDEvent.Matrix, 1);
      fm := NEW(MDDEvent.Matrix, 1);
    BEGIN
      pm[0] := MDDEvent.Entry { 0, 1 };  (* thinking -> hungry *)
      fm[0] := MDDEvent.Entry { 0, 1 };  (* free -> taken *)
      eventList[nEvents] := MDDEvent.NewSyncEvent(1, 0, pm, fm);
      INC(nEvents);
    END;

    (* Phil 0 (level 1) picks up fork 1 (level 2): hungry->eating
       top=2, bot=1 *)
    VAR
      fm := NEW(MDDEvent.Matrix, 1);
      pm := NEW(MDDEvent.Matrix, 1);
    BEGIN
      fm[0] := MDDEvent.Entry { 0, 1 };  (* free -> taken *)
      pm[0] := MDDEvent.Entry { 1, 2 };  (* hungry -> eating *)
      eventList[nEvents] := MDDEvent.NewSyncEvent(2, 1, fm, pm);
      INC(nEvents);
    END;

    (* Phil 0 (level 1) puts down fork 0 (level 0): eating->thinking *)
    VAR
      pm := NEW(MDDEvent.Matrix, 1);
      fm := NEW(MDDEvent.Matrix, 1);
    BEGIN
      pm[0] := MDDEvent.Entry { 2, 0 };  (* eating -> thinking *)
      fm[0] := MDDEvent.Entry { 1, 0 };  (* taken -> free *)
      eventList[nEvents] := MDDEvent.NewSyncEvent(1, 0, pm, fm);
      INC(nEvents);
    END;

    (* Phil 0 (level 1) puts down fork 1 (level 2): eating->thinking
       top=2, bot=1 *)
    VAR
      fm := NEW(MDDEvent.Matrix, 1);
      pm := NEW(MDDEvent.Matrix, 1);
    BEGIN
      fm[0] := MDDEvent.Entry { 1, 0 };  (* taken -> free *)
      pm[0] := MDDEvent.Entry { 2, 0 };  (* eating -> thinking *)
      eventList[nEvents] := MDDEvent.NewSyncEvent(2, 1, fm, pm);
      INC(nEvents);
    END;

    (* Phil 1 (level 3) picks up fork 1 (level 2): think->hungry *)
    VAR
      pm := NEW(MDDEvent.Matrix, 1);
      fm := NEW(MDDEvent.Matrix, 1);
    BEGIN
      pm[0] := MDDEvent.Entry { 0, 1 };
      fm[0] := MDDEvent.Entry { 0, 1 };
      eventList[nEvents] := MDDEvent.NewSyncEvent(3, 2, pm, fm);
      INC(nEvents);
    END;

    (* Phil 1 (level 3) picks up fork 0 (level 0): hungry->eating
       top=3, bot=0 *)
    VAR
      pm := NEW(MDDEvent.Matrix, 1);
      fm := NEW(MDDEvent.Matrix, 1);
    BEGIN
      pm[0] := MDDEvent.Entry { 1, 2 };
      fm[0] := MDDEvent.Entry { 0, 1 };
      eventList[nEvents] := MDDEvent.NewSyncEvent(3, 0, pm, fm);
      INC(nEvents);
    END;

    (* Phil 1 (level 3) puts down fork 1 (level 2): eating->thinking *)
    VAR
      pm := NEW(MDDEvent.Matrix, 1);
      fm := NEW(MDDEvent.Matrix, 1);
    BEGIN
      pm[0] := MDDEvent.Entry { 2, 0 };
      fm[0] := MDDEvent.Entry { 1, 0 };
      eventList[nEvents] := MDDEvent.NewSyncEvent(3, 2, pm, fm);
      INC(nEvents);
    END;

    (* Phil 1 (level 3) puts down fork 0 (level 0): eating->thinking
       top=3, bot=0 *)
    VAR
      pm := NEW(MDDEvent.Matrix, 1);
      fm := NEW(MDDEvent.Matrix, 1);
    BEGIN
      pm[0] := MDDEvent.Entry { 2, 0 };
      fm[0] := MDDEvent.Entry { 1, 0 };
      eventList[nEvents] := MDDEvent.NewSyncEvent(3, 0, pm, fm);
      INC(nEvents);
    END;

    events := NEW(MDDSaturation.EventList, nEvents);
    FOR i := 0 TO nEvents - 1 DO events[i] := eventList[i] END;

    VAR initial := MDD.Singleton(init);
    BEGIN
      reached := MDDSaturation.ComputeReachable(initial, events);
      IO.Put("  reached MDD size: " & Fmt.Int(MDD.Size(reached)) & "\n");
      IO.Put("  node count: " & Fmt.Int(MDD.NodeCount()) & "\n");

      (* Deadlock check *)
      hasSucc := MDDSaturation.HasSuccessor(reached, events);
      deadlocked := MDD.Difference(reached, hasSucc);
      IO.Put("  deadlocked MDD size: " & Fmt.Int(MDD.Size(deadlocked)) & "\n");

      Check("dining N=2 has deadlock", NOT MDD.IsEmpty(deadlocked));

      (* The deadlock state is both hungry, both forks taken:
         fork0=taken(1), phil0=hungry(1), fork1=taken(1), phil1=hungry(1) *)
      VAR
        deadState := MDD.Singleton(
                       ARRAY [0..3] OF CARDINAL { 1, 1, 1, 1 });
      BEGIN
        Check("deadlock state is (1,1,1,1)",
              NOT MDD.IsEmpty(MDD.Intersection(deadlocked, deadState)));
      END;
    END;
  END TestSaturationDining2;

(* ================================================================
   Test 9: Deadlock-free system
   ================================================================ *)

(* Simple producer-consumer: producer(2 states) -> consumer(2 states)
   Sync: producer send, consumer recv.
   No deadlock: alternating send/recv. *)

PROCEDURE TestSaturationProdCons() =
  VAR
    (* Level 0: consumer, Level 1: producer *)
    domains := ARRAY [0..1] OF CARDINAL { 2, 2 };
    init    := ARRAY [0..1] OF CARDINAL { 0, 0 };
    events  : MDDSaturation.EventList;
    reached, hasSucc, deadlocked : MDD.T;

    (* Sync: producer(1) state 0->1, consumer(0) state 0->1 *)
    topM1 := NEW(MDDEvent.Matrix, 1);
    botM1 := NEW(MDDEvent.Matrix, 1);
    (* Sync: producer(1) state 1->0, consumer(0) state 1->0 *)
    topM2 := NEW(MDDEvent.Matrix, 1);
    botM2 := NEW(MDDEvent.Matrix, 1);
  BEGIN
    IO.Put("--- Test 9: Saturation (producer-consumer) ---\n");
    MDD.SetLevels(2, domains);

    topM1[0] := MDDEvent.Entry { 0, 1 };
    botM1[0] := MDDEvent.Entry { 0, 1 };
    topM2[0] := MDDEvent.Entry { 1, 0 };
    botM2[0] := MDDEvent.Entry { 1, 0 };

    events := NEW(MDDSaturation.EventList, 2);
    events[0] := MDDEvent.NewSyncEvent(1, 0, topM1, botM1);
    events[1] := MDDEvent.NewSyncEvent(1, 0, topM2, botM2);

    VAR initial := MDD.Singleton(init);
    BEGIN
      reached := MDDSaturation.ComputeReachable(initial, events);
      IO.Put("  reached MDD size: " & Fmt.Int(MDD.Size(reached)) & "\n");

      (* Reachable: (0,0) and (1,1) only *)
      VAR
        s00 := MDD.Singleton(ARRAY [0..1] OF CARDINAL { 0, 0 });
        s11 := MDD.Singleton(ARRAY [0..1] OF CARDINAL { 1, 1 });
        expected := MDD.Union(s00, s11);
      BEGIN
        Check("prodcons reached = {(0,0),(1,1)}",
              MDD.Equal(reached, expected));
      END;

      hasSucc := MDDSaturation.HasSuccessor(reached, events);
      deadlocked := MDD.Difference(reached, hasSucc);
      Check("prodcons no deadlock", MDD.IsEmpty(deadlocked));
    END;
  END TestSaturationProdCons;

(* ================================================================ *)

BEGIN
  TestTerminals();
  TestSingleton();
  TestSetOps();
  TestQuasiReduced();
  TestCanonical();
  TestEvents();
  TestSaturationMutex();
  TestSaturationProdCons();
  TestSaturationDining2();

  IO.Put("\n" & Fmt.Int(nPassed) & "/" & Fmt.Int(nTests) & " tests passed.\n");
  IF nPassed # nTests THEN
    IO.Put("*** FAILURES ***\n");
  END;
END TestMDD.
