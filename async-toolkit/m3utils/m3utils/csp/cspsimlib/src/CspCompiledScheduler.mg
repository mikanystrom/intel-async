(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

GENERIC MODULE CspCompiledScheduler(CspDebug);
IMPORT CspCompiledProcess AS Process;
IMPORT Word;
FROM Fmt IMPORT Int, F, Bool;
IMPORT Debug; FROM Debug IMPORT UnNil;
IMPORT CspClosureSeq AS ClosureSeq;
IMPORT CspChannel;
IMPORT Random;
IMPORT Thread;
IMPORT CspScheduler;
IMPORT CardSeq;
IMPORT Wx;
IMPORT CspSim;
IMPORT CspWorker;
IMPORT TextCardTbl;
IMPORT CspRemoteChannel;
IMPORT CspPortObject;

CONST doDebug = CspDebug.DebugSchedule;

TYPE
  LocalId = [0..1023];

  Set = SET OF LocalId;
  
  T = CspScheduler.T OBJECT

    (* we should probably consider promoting many of the fields to the
       CspScheduler interface (or adding another private one) so that
       everyone can see them and not have to take the overhead of a 
       NARROW() check so much below *)
    
    id           : CARDINAL;

    active, next : REF ARRAY OF Process.Closure;
    (* this is double-buffered.
       
       The "active" closures are the ones we are running on this iteration;
       the "next" closures are the ones we are scheduling for the next iteration
    *)
    
    ap, np       : CARDINAL;
    running      : Process.Closure;

    (* parallel scheduler fields 
       
       we add these to EVERY scheduler so we don't need to stick a bunch
       of extra tests in the Send/Recv/etc. 
    *)

    
    mu           : MUTEX;
    c            : Thread.Condition;
    
    commOutbox   : REF ARRAY OF ClosureSeq.T;
    waitOutbox   : REF ARRAY OF ClosureSeq.T;
    (* written by "from" scheduler, read by each "to" scheduler, according
       to their ids 

       XXX REMOVE XXX
    *)

    (* 
       The following are written by the end that updates.

       They are indexed by the target scheduler, so the target 
       can read the contents without contention.
    *)
    rdirty       : REF ARRAY OF REF ARRAY OF CspChannel.T;
    nrp          : REF ARRAY OF CARDINAL;
    wdirty       : REF ARRAY OF REF ARRAY OF CspChannel.T;
    nwp          : REF ARRAY OF CARDINAL;

    thePhase     : Phase;
    idle         : Set; (* used to do partial phases *)

    time         : Word.T;
  END;

VAR AllSchedulers : Set;
    
PROCEDURE ReadDirty(targ : CspChannel.T; cl : Process.Closure) =
  VAR
    t   : T := cl.fr.affinity;
    tgt : T := targ.writer.affinity; (* target (other) scheduler *)
    tgtId   := tgt.id;               (* target scheduler's id *)
  BEGIN
    IF doDebug THEN
      Debug.Out("ReadDirty target : " & targ.nm)
    END;
    IF t.nrp[tgtId] > LAST(t.rdirty[tgtId]^) THEN
      WITH new = NEW(REF ARRAY OF CspChannel.T, NUMBER(t.rdirty[tgtId]^) * 2) DO
        SUBARRAY(new^, 0, NUMBER(t.rdirty[tgtId]^)) := t.rdirty[tgtId]^;
        t.rdirty[tgtId] := new
      END;
    END;
    t.rdirty[tgtId][t.nrp[tgtId]] := targ;
    INC(t.nrp[tgtId])
  END ReadDirty;
  
PROCEDURE WriteDirty(surr : CspChannel.T; cl : Process.Closure) =
  VAR
    t   : T := cl.fr.affinity;
    tgt : T := surr.writer.affinity; (* target (other) scheduler *)
    tgtId   := tgt.id;               (* target scheduler's id *)
  BEGIN
    IF doDebug THEN
      Debug.Out("WriteDirty surrogate : " & UnNil(surr.nm))
    END;
    IF t.nwp[tgtId] > LAST(t.wdirty[tgtId]^) THEN
      WITH new = NEW(REF ARRAY OF CspChannel.T, NUMBER(t.wdirty[tgtId]^) * 2) DO
        SUBARRAY(new^, 0, NUMBER(t.wdirty[tgtId]^)) := t.wdirty[tgtId]^;
        t.wdirty[tgtId] := new
      END;
    END;
    t.wdirty[tgtId][t.nwp[tgtId]] := surr;
    INC(t.nwp[tgtId])
  END WriteDirty;

PROCEDURE ScheduleComm(from, toSchedule : Process.Closure) =
  VAR
    fromScheduler : T := from.fr.affinity;
  BEGIN
    IF fromScheduler = toSchedule.fr.affinity THEN
      (* the source and target are in the same scheduler, we can 
         schedule them same as if they were local *)
      Schedule(toSchedule)
      (*
    ELSE
      (* if the target block is running under another scheduler,
         we do not schedule it directly.  Instead, we put it in the 
         appropriate outbox to handle at the end of the
         timestep *)
      VAR
        toScheduler   : T := toSchedule.fr.affinity;
      BEGIN
        fromScheduler.commOutbox[toScheduler.id].addhi(toSchedule)
        END
        *)
    END
  END ScheduleComm;
  
PROCEDURE ScheduleWait(from, toSchedule : Process.Closure) =
  VAR
    fromScheduler : T := from.fr.affinity;
  BEGIN
    IF fromScheduler = toSchedule.fr.affinity THEN
      (* the source and target are in the same scheduler, we can 
         schedule them same as if they were local *)
      IF toSchedule.waiting THEN
        toSchedule.waiting := FALSE;
        Schedule(toSchedule)
      END
      (*
    ELSE
      (* if the target block is running under another scheduler,
         we do not schedule it directly.  Instead, we put it in the 
         appropriate outbox to handle at the end of the
         timestep *)
      VAR
        toScheduler   : T := toSchedule.fr.affinity;
      BEGIN
        fromScheduler.waitOutbox[toScheduler.id].addhi(toSchedule)
        END
        *)
    END
  END ScheduleWait;
  
PROCEDURE Schedule(closure : Process.Closure) =
  VAR
    t : T := closure.fr.affinity;
  BEGIN
    <*ASSERT closure # NIL*>

    IF doDebug THEN
      Debug.Out(F("scheduling %s : %s [%s] to run at %s",
                  Int(closure.frameId), closure.name, closure.fr.typeName,
                  Int(t.time)));
      IF t.running = NIL THEN
        Debug.Out(F("NIL : NIL scheduling %s : %s [%s] to run",
                  Int(closure.frameId), closure.name, closure.fr.typeName))
      ELSE
        Debug.Out(F("%s : %s scheduling %s : %s [%s] to run",
                    Int(t.running.frameId), t.running.name,
                    Int(closure.frameId), closure.name, closure.fr.typeName))
      END
    END;

    <*ASSERT t # NIL*>

    IF closure.scheduled = t.time THEN
      IF doDebug THEN
        Debug.Out(F("%s : %s already scheduled at %s",
                    Int(closure.frameId), closure.name, Int(t.time)))
      END;
      RETURN 
    END;
    
    IF t.np > LAST(t.next^) THEN
      WITH new = NEW(REF ARRAY OF Process.Closure, NUMBER(t.next^) * 2) DO
        SUBARRAY(new^, 0, NUMBER(t.next^)) := t.next^;
        t.next := new
      END
    END;
    t.next[t.np]      := closure;
    closure.scheduled := t.time;
    INC(t.np);

    IF doDebug THEN
      Debug.Out(F("Schedule : np = %s", Int(t.np)))
    END
  END Schedule;

PROCEDURE ScheduleFork(READONLY closures : ARRAY OF Process.Closure) : CARDINAL =
  BEGIN
    FOR i := FIRST(closures) TO LAST(closures) DO
      Schedule(closures[i])
    END;
    RETURN NUMBER(closures)
  END ScheduleFork;

PROCEDURE GetTime() : Word.T =
  BEGIN RETURN masterTime END GetTime;

VAR masterTime : Word.T := 0;
VAR eagerMode := FALSE;

PROCEDURE Run1(t : T) =
  BEGIN
    (* run *)
    t.time := masterTime;

    LOOP
      IF doDebug THEN
        Debug.Out(F("=====  @ %s Scheduling loop %s: np = %s",
                    Int(t.time),
                    Int(t.id), Int(t.np)))
      END;

      IF t.np = 0 THEN
        RETURN
      END;

      IF eagerMode THEN
        WHILE t.np = 1 DO
          VAR cl := t.next[0]; BEGIN
            t.np := 0;
            INC(masterTime);
            t.time := masterTime;
            cl.run();
          END
        END;
        IF t.np = 0 THEN RETURN END;
      END;

      VAR
        temp := t.active;
      BEGIN
        t.active := t.next;
        t.ap     := t.np;
        t.next   := temp;
        t.np     := 0;
      END;

      (* note that the time switches here, BEFORE we run *)
      INC(masterTime);
      t.time := masterTime;

      FOR i := 0 TO t.ap - 1 DO
        WITH cl      = t.active[i] DO
          <*ASSERT cl # NIL*>
          IF doDebug THEN
            Debug.Out(F("Scheduler switch to %s : %s",
                        Int(cl.frameId), cl.name));
            t.running := cl
          END;
          cl.run();
          IF doDebug THEN
            Debug.Out(F("Scheduler switch from %s : %s",
                        Int(cl.frameId), cl.name));
            t.running := NIL
          END;
          (*IF NOT success THEN Schedule(cl) END*)
        END
      END
    END
  END Run1;

VAR theScheduler : T;
    (* when running a single scheduler *)

PROCEDURE ConfigureRemoteChannels(READONLY sarr : ARRAY OF T;
                                  worker        : CspWorker.T) =

  PROCEDURE GetChannel() : CspChannel.T =
    VAR
      po : CspPortObject.T;
    BEGIN
      WITH hadIt = cTbl.get(k, po) DO
        <*ASSERT hadIt*>
        RETURN po
      END
    END GetChannel;
    
  VAR
    cTbl  := CspSim.GetPortTbl();
    cdTbl := worker.getChannelData();
    iter  := cdTbl.iterate();
    myWid := worker.getId();
    k  : TEXT;
    cd : CspRemoteChannel.T;
  BEGIN
    WHILE iter.next(k, cd) DO
      Debug.Out(F("Worker %s : configuring remote channel %s (%s) wrs=%s rds=%s",
                  Int(myWid),
                  cd.nm, Int(cd.id),
                  Int(cd.wrs),
                  Int(cd.rds)));
      WITH wwid = worker.gid2wid(cd.wrs),
           rwid = worker.gid2wid(cd.rds) DO
        IF    wwid = myWid AND rwid # myWid THEN
          (* remote is read, I am write *)
          WITH chan = GetChannel() DO
            chan.reader := NewReaderFrame(cd, rwid)
          END
        ELSIF rwid = myWid AND wwid # myWid THEN
          (* remote is write, I am read *)
          WITH chan = GetChannel() DO
            chan.writer := NewWriterFrame(cd, wwid)
          END
        END
      END
    END
  END ConfigureRemoteChannels;

TYPE
  RemoteFrame = Process.Frame OBJECT
    tgts   : CARDINAL; (* global id of tgt scheduler *)
    tgtw   : CARDINAL; (* worker id of tgt *)
  END;
    
PROCEDURE NewReaderFrame(cd : CspRemoteChannel.T;
                         rwid : CARDINAL) : Process.Frame =
  VAR
    res := NEW(RemoteFrame, id := cd.rdid, tgts := cd.wrs, tgtw := rwid);
  BEGIN
    res.dummy := NEW(Process.Closure,
                     name    := "**REMOTE-READER-DUMMY**",
                     frameId := cd.rdid,
                     fr      := res);
    RETURN res
  END NewReaderFrame;
  
PROCEDURE NewWriterFrame(cd : CspRemoteChannel.T;
                         wwid : CARDINAL) : Process.Frame =
  VAR
    res := NEW(RemoteFrame, id := cd.wrid, tgts := cd.rds, tgtw := wwid);
  BEGIN
    res.dummy := NEW(Process.Closure,
                     name    := "**REMOTE-WRITER-DUMMY**",
                     frameId := cd.wrid,
                     fr      := res);
    RETURN res
  END NewWriterFrame;
  
PROCEDURE Run(mt : CARDINAL; greedy, nondet, eager : BOOLEAN; worker : CspWorker.T) =
  BEGIN
    eagerMode := eager;

    IF worker # NIL AND mt = 0 THEN
      mt := 1
    END;

    IF mt = 0 THEN
      theScheduler := NEW(T,
                          id     := 0,
                          active := NEW(REF ARRAY OF Process.Closure, 1),
                          next   := NEW(REF ARRAY OF Process.Closure, 1),
                          np     := 0);

      (* mark the affinity of each process *)
      MapRandomly(ARRAY OF T { theScheduler });
      StartProcesses();
      Run1(theScheduler)
    ELSIF worker # NIL THEN
      Debug.Out("Scheduler.Run : worker wait");
      worker.awaitInitialization();
      Thread.Pause(2.0d0);
      Debug.Out("Scheduler.Run : worker run");
      
      schedulers := NEW(REF ARRAY OF T, mt);

      CreateMulti(schedulers^);

      WITH map = worker.getProcMap() DO
        MapPerMap(schedulers^, map)
      END;

      ConfigureRemoteChannels(schedulers^, worker);
      
      Debug.Out("Scheduler.Run : starting processes");
      StartProcesses();

      RunNondet(schedulers^, greedy);
      Debug.Out("Scheduler.Run : DONE");

      LOOP
        (* here we should do some work *)
        Thread.Pause(1.0d0)
      END
    ELSE
      schedulers := NEW(REF ARRAY OF T, mt);
      CreateMulti(schedulers^);
      MapRoundRobin(schedulers^);
      StartProcesses();
      IF nondet THEN
        RunNondet(schedulers^, greedy)
      ELSE
        RunMulti (schedulers^, greedy)
      END
    END
  END Run;

PROCEDURE StartProcesses() =
  (* start each process *)
  VAR
    k : TEXT;
    v : Process.Frame;
    iter := CspSim.GetProcTbl().iterate();
  BEGIN
    WHILE iter.next(k, v) DO
      v.start()
    END
  END StartProcesses;

PROCEDURE MapRandomly(READONLY sarr : ARRAY OF T) =
  VAR
    rand := NEW(Random.Default).init(TRUE);
    k : TEXT;
    v : Process.Frame;
    iter := CspSim.GetProcTbl().iterate();
  BEGIN
    WHILE iter.next(k, v) DO
      WITH q = rand.integer(FIRST(sarr), LAST(sarr)) DO
        v.affinity := sarr[q]
      END
    END
  END MapRandomly;

PROCEDURE MapRoundRobin(READONLY sarr : ARRAY OF T) =
  VAR
    q := 0;
    seq := CspSim.GetProcSeq();
  BEGIN
    FOR i := 0 TO seq.size() - 1 DO
      WITH v = seq.get(i) DO
        v.affinity := sarr[q];
        q := (q + 1) MOD NUMBER(sarr)
      END
    END
  END MapRoundRobin;
    
PROCEDURE MapPerMap(READONLY sarr : ARRAY OF T; map : TextCardTbl.T) =
  VAR
    seq := CspSim.GetProcSeq();
    sid : CARDINAL;
  BEGIN
    FOR i := 0 TO seq.size() - 1 DO
      WITH v     = seq.get(i),
           hadIt = map.get(v.name, sid) DO
        <*ASSERT hadIt*>
        IF doDebug THEN
          Debug.Out(F("MapPerMap : mapping %s -> %s", v.name, Int(sid)))
        END;
        v.affinity := sarr[sid]
      END
    END
  END MapPerMap;
    
(**********************************************************************)

VAR schedulers : REF ARRAY OF T := NIL;
    (* when running parallel schedulers *)

PROCEDURE AcquireLocks(READONLY schedulers : ARRAY OF T;
                       READONLY set        : Set ) =
  BEGIN
    FOR i := FIRST(schedulers) TO LAST(schedulers) DO
      IF i IN set THEN
        Thread.Acquire(schedulers[i].mu)
      END
    END
  END AcquireLocks;

PROCEDURE ReleaseLocks(READONLY schedulers : ARRAY OF T;
                       READONLY set        : Set ) =
  BEGIN
    FOR i := FIRST(schedulers) TO LAST(schedulers) DO
      IF i IN set THEN
        Thread.Release(schedulers[i].mu)
      END
    END
  END ReleaseLocks;

PROCEDURE SignalThreads(READONLY schedulers : ARRAY OF T;
                        READONLY set : Set               ) =
  BEGIN
    FOR i := FIRST(schedulers) TO LAST(schedulers) DO
      IF i IN set THEN
        Thread.Signal(schedulers[i].c)
      END
    END
  END SignalThreads;

PROCEDURE SetPhase(READONLY schedulers : ARRAY OF T;
                            phase      : Phase;
                   READONLY set        : Set) =
  (* scheduler[].mu m/b locked *)
  VAR
    n := 0;
  BEGIN
    <*ASSERT phase # Phase.Idle*>
    IF doDebug THEN
      Debug.Out(F("SetPhase(%s)", PhaseNames[phase]))
    END;
    FOR i := FIRST(schedulers) TO LAST(schedulers) DO
      IF i IN set THEN
        <*ASSERT schedulers[i].thePhase = Phase.Idle*>
        schedulers[i].thePhase := phase;
        INC(n)
      END
    END
  END SetPhase;

(**********************************************************************)  
    
TYPE
  Phase = {
  Idle,
  GetOtherBlocks,
  SwapActiveBlocks, (* this could be combined with UpdateSurrogates *)
  UpdateSurrogates,
  RunActiveBlocks,
  
  GetOtherBlocksPartial,
  SwapActiveBlocksPartial, 
  UpdateSurrogatesPartial
  };

CONST
  PhaseNames = ARRAY Phase OF TEXT {
  "Idle",
  "GetOtherBlocks",
  "SwapActiveBlocks", 
  "UpdateSurrogates",
  "RunActiveBlocks",

  "GetOtherBlocksPartial",
  "SwapActiveBlocksPartial", 
  "UpdateSurrogatesPartial"

  };

PROCEDURE GetIdle(VAR      idle       : Set) =
  (* wait until at least one scheduler is idle, and add all idle schedulers
     to idle set, draining the idleQ *)
  BEGIN
    LOCK mu DO
      IF idleQ.size() = 0 THEN
        Thread.Wait(mu, c)
      END;

      (* at least one is idle, report it *)
      
      WHILE idleQ.size() # 0 DO
        WITH idler = idleQ.remlo() DO
          <*ASSERT NOT idler IN idle*>
          idle := idle + Set { idler };
          IF doDebug THEN
            Debug.Out("GetIdle : " & Int(idler))
          END
        END
      END
    END
  END GetIdle;
  
PROCEDURE AwaitIdle(READONLY subset     : Set) =
  VAR
    idleSet    :=  Set {};
    notForMe := NEW(CardSeq.T).init();
  BEGIN
    IF doDebug THEN
      Debug.Out(F("AwaitIdle( %s)", FmtSet(subset)))
    END;
    
    LOCK mu DO
      LOOP
        WHILE idleQ.size() # 0 DO
          WITH idler = idleQ.remlo() DO
            IF idler IN subset THEN
              idleSet := idleSet + Set { idler };
            ELSE
              notForMe.addhi(idler)
            END;
            IF doDebug THEN
              Debug.Out("Went idle : " & Int(idler))
            END
          END
        END;

        IF doDebug THEN
          Debug.Out("AwaitIdle : idle set = " & FmtSet(idleSet))
        END;
        
        IF idleSet = subset THEN
          IF doDebug THEN
            Debug.Out("ALL IDLE.")
          END;
          idleQ := notForMe;
          RETURN 
        ELSE    
          Thread.Wait(mu, c)
        END
      END
    END
  END AwaitIdle;

PROCEDURE ReportIdle(myId : LocalId) =
  BEGIN
    LOCK mu DO
      idleQ.addhi(myId);
    END;
    Thread.Signal(c)
  END ReportIdle;

VAR mu    := NEW(MUTEX);
VAR c     := NEW(Thread.Condition);    
VAR idleQ := NEW(CardSeq.T).init();
  
PROCEDURE RunMulti(READONLY schedulers : ARRAY OF T; greedy : BOOLEAN) =

  PROCEDURE NothingPending() : BOOLEAN =
    BEGIN
      (* something is pending if it is in the local queue of a scheduler
         or if it is in the outbox of a scheduler *)
      FOR i := FIRST(schedulers) TO LAST(schedulers) DO
        WITH s = schedulers[i] DO
          IF s.np # 0 THEN RETURN FALSE END;
          FOR j := FIRST(schedulers) TO LAST(schedulers) DO
            IF s.commOutbox[j].size() # 0 THEN RETURN FALSE END;
            IF s.waitOutbox[j].size() # 0 THEN RETURN FALSE END;
            IF s.nrp[j] # 0 THEN RETURN FALSE END;
            IF s.nwp[j] # 0 THEN RETURN FALSE END
          END
        END
      END;
      RETURN TRUE
    END NothingPending;
  
  PROCEDURE CountPendingStuff() : CARDINAL =
    VAR
      res : CARDINAL := 0;
    BEGIN
      (* something is pending if it is in the local queue of a scheduler
         or if it is in the outbox of a scheduler *)
      FOR i := FIRST(schedulers) TO LAST(schedulers) DO
        WITH s = schedulers[i] DO
          res := res + s.np;
          
          FOR j := FIRST(schedulers) TO LAST(schedulers) DO
            res := res + s.commOutbox[j].size();
            res := res + s.waitOutbox[j].size()
          END
        END
      END;
      RETURN res
    END CountPendingStuff;
  
  PROCEDURE RunPhase(phase : Phase) =
    BEGIN
      IF doDebug THEN
        Debug.Out(F("RunMulti.RunPhase(%s)", PhaseNames[phase]))
      END;

      FOR i := FIRST(schedulers) TO LAST(schedulers) DO
        <*ASSERT schedulers[i].thePhase = Phase.Idle*>
      END;

      AcquireLocks(schedulers, AllSchedulers);

      TRY
        SetPhase(schedulers, phase, AllSchedulers)
      FINALLY
        ReleaseLocks(schedulers, AllSchedulers)
      END;
      SignalThreads(schedulers, AllSchedulers);
      AwaitIdle(AllSchedulers)
    END RunPhase;

  PROCEDURE UpdateTime() =
    BEGIN
      (* ensure time advances for everybody *)
      FOR i := FIRST(schedulers) TO LAST(schedulers) DO
        masterTime := MAX(masterTime, schedulers[i].time)
      END;
      
      INC(masterTime);
    END UpdateTime;
    
  VAR
    cls   := NEW(REF ARRAY OF SchedClosure, NUMBER(schedulers));
    thrds := NEW(REF ARRAY OF Thread.T    , NUMBER(schedulers));
    iter  := 0;
  BEGIN
    FOR i := FIRST(cls^) TO LAST(cls^) DO
      cls[i]   := NEW(SchedClosure, t := schedulers[i], greedy := greedy);
      thrds[i] := Thread.Fork(cls[i])
    END;

    LOOP
      IF doDebug THEN
        Debug.Out(F("=====  @ %s Master scheduling loop : np = %s, iter = %s",
                    Int(masterTime),
                    Int(CountPendingStuff()),
                    Int(iter)
                   )
                 )
      END;

      IF NothingPending() THEN
        Debug.Out("RunMulti : nothing pending---done at " & Int(masterTime));
        RETURN
      END;

      (* at the end of every Phase, all the schedulers are idle *)
      
      UpdateTime();

      RunPhase(Phase.GetOtherBlocks);

(*      UpdateTime();  *)
      
      RunPhase(Phase.SwapActiveBlocks);

      RunPhase(Phase.UpdateSurrogates);

      UpdateTime();

      RunPhase(Phase.RunActiveBlocks);
    END
  END RunMulti;

TYPE
  SchedClosure = Thread.Closure OBJECT
    t      : T;
    greedy : BOOLEAN;
  OVERRIDES
    apply := Apply;
  END;

CONST InitPhase = Phase.Idle;
      
PROCEDURE Apply(cl : SchedClosure) : REFANY =

  PROCEDURE DoSwapActiveBlocks() =
    VAR
      temp := t.active;
    BEGIN
      t.active := t.next;
      t.ap     := t.np;
      t.next   := temp;
      t.np     := 0;
    END DoSwapActiveBlocks;

  PROCEDURE GetOtherBlocksFrom(r : LocalId) =
    BEGIN
      WITH box = schedulers[r].commOutbox[myId] DO
        FOR i := 0 TO box.size() - 1 DO
          WITH myCl = box.get(i) DO
            Schedule(myCl)
          END
        END
      END;
      WITH box = schedulers[r].waitOutbox[myId] DO
        FOR i := 0 TO box.size() - 1 DO
          WITH myCl = box.get(i) DO
            IF myCl.waiting THEN
              myCl.waiting := FALSE; (* in case there are multiple wakers *)
              Schedule(myCl)
            END
          END
        END
      END
    END GetOtherBlocksFrom;
    
  PROCEDURE UpdateSurrogatesFrom(i : LocalId) =
    BEGIN
      WITH other = NARROW(schedulers[i],T) DO
        FOR w := 0 TO other.nwp[myId] - 1 DO
          WITH surrogate = other.wdirty[myId][w] DO
            surrogate.writeSurrogate()
          END
        END;
        FOR r := 0 TO other.nrp[myId] - 1 DO
          WITH target = other.rdirty[myId][r] DO
            target.readSurrogate()
          END
        END
      END
    END UpdateSurrogatesFrom;
    
  PROCEDURE ClearOutboxesTo(i : CARDINAL) =
    BEGIN
      EVAL t.commOutbox[i].init();
      EVAL t.waitOutbox[i].init()
    END ClearOutboxesTo;
    
  VAR
    t        := cl.t;
    myId     := t.id;
  BEGIN
    IF doDebug THEN
      Debug.Out(F("Starting scheduler %s", Int(myId)))
    END;
    
    LOOP
      (* this is a single scheduler *)

      IF doDebug THEN
        Debug.Out(F("Scheduler(%s) : idle",
                    Int(myId)))
      END;

      (* wait for command from central *)
      LOCK t.mu DO
        WHILE t.thePhase = Phase.Idle DO
          Thread.Wait(t.mu, t.c)
        END
      END;

      IF doDebug THEN
        Debug.Out(F("Scheduler(%s) : phase %s",
                    Int(myId),
                    PhaseNames[t.thePhase]))
      END;

      CASE t.thePhase OF
        Phase.Idle =>
        <*ASSERT FALSE*>
      |
        Phase.GetOtherBlocks =>
        <*ASSERT masterTime > t.time*>
        t.time := masterTime;
        
        FOR r := FIRST(schedulers^) TO LAST(schedulers^) DO
          GetOtherBlocksFrom(r)
        END
      |
        Phase.GetOtherBlocksPartial =>
        <*ASSERT masterTime > t.time*>
        t.time := masterTime;
        
        FOR r := FIRST(schedulers^) TO LAST(schedulers^) DO
          IF r IN t.idle THEN
            GetOtherBlocksFrom(r)
          END
        END
      |
        Phase.SwapActiveBlocks =>
        
        (* clear out the schedulers we just copied in GetOtherBlocks *)
        FOR i := FIRST(schedulers^) TO LAST(schedulers^) DO
          ClearOutboxesTo(i)
        END;

        DoSwapActiveBlocks()
      |
        Phase.SwapActiveBlocksPartial =>
        
        (* clear out the schedulers we just copied in GetOtherBlocks *)
        FOR i := FIRST(schedulers^) TO LAST(schedulers^) DO
          IF i IN t.idle THEN
            ClearOutboxesTo(i)
          END
        END;

        DoSwapActiveBlocks()
      |
        Phase.UpdateSurrogates =>
        (* 
           Update the channels with surrogate writes. 

           This needs to be done on the reader side (obv.)
        *)
        FOR i := FIRST(schedulers^) TO LAST(schedulers^) DO
          UpdateSurrogatesFrom(i)
        END;
      |
        Phase.UpdateSurrogatesPartial =>
        FOR i := FIRST(schedulers^) TO LAST(schedulers^) DO
          IF i IN t.idle THEN
            UpdateSurrogatesFrom(i)
          END
        END;
      |
        Phase.RunActiveBlocks =>
        VAR
          cycles := 0;
        BEGIN
          IF doDebug THEN
            Debug.Out(F("Scheduler %s : starting RunActiveBlocks", Int(myId)))
          END;
        
        <*ASSERT masterTime > t.time*>
        t.time := masterTime;

        (* first zero all the read/write channel stuff *)
        FOR i := FIRST(schedulers^) TO LAST(schedulers^) DO
          t.nrp[i] := 0;
          t.nwp[i] := 0
        END;

        (* now run the user code *)
        LOOP
          FOR i := 0 TO t.ap - 1 DO
            WITH cl      = t.active[i] DO
              <*ASSERT cl # NIL*>
              <*ASSERT cl.fr.affinity = t*>

              IF doDebug THEN
                Debug.Out(F("Apply %s : Scheduler switch to %s : %s",
                            Int(myId), Int(cl.frameId), cl.name));
                t.running := cl
              END;
              cl.run();
              IF doDebug THEN
                Debug.Out(F("Apply %s : Scheduler switch from %s : %s",
                            Int(myId), Int(cl.frameId), cl.name));
                t.running := NIL
              END;
              (*IF NOT success THEN Schedule(cl) END*)
            END(*WITH*)
          END(*FOR*);

          INC(cycles);
          
          IF doDebug THEN
            Debug.Out(F("Apply %s : cl.greedy=%s t.np=%s",
                        Int(myId), Bool(cl.greedy), Int(t.np)))
          END;
          
          IF cl.greedy AND t.np # 0 THEN
            (* just keep running till we are out of things to do *)
            INC(t.time);
            DoSwapActiveBlocks()
          ELSE
            EXIT
          END

        END(*LOOP*);

        IF doDebug THEN
          Debug.Out(F("Scheduler %s : RunActiveBlocks complete, cycles %s", Int(myId), Int(cycles)))
        END;
      END
        
      END;

      LOCK t.mu DO
        t.thePhase := Phase.Idle
      END;
      ReportIdle(myId);
      (* local time will have updated *)
      Thread.Signal(t.c)
    END
  END Apply;

PROCEDURE FmtSet(READONLY set : Set) : TEXT =
  VAR
    wx := Wx.New();
  BEGIN
    FOR i := FIRST(LocalId) TO LAST(LocalId) DO
      IF i IN set THEN
        Wx.PutText(wx, Int(i));
        Wx.PutChar(wx, ' ')
      END
    END;
    RETURN Wx.ToText(wx)
  END FmtSet;
  
PROCEDURE CreateMulti(VAR sarr : ARRAY OF T) =
  (* create n schedulers *)

  PROCEDURE NewChanArray() : REF ARRAY OF REF ARRAY OF CspChannel.T =
    VAR
      res := NEW(REF ARRAY OF REF ARRAY OF CspChannel.T, n);
    BEGIN
      FOR i := FIRST(res^) TO LAST(res^) DO
        res[i] := NEW(REF ARRAY OF CspChannel.T, 1)
      END;
      RETURN res
    END NewChanArray;

  PROCEDURE NewCardArray() : REF ARRAY OF CARDINAL =
    VAR
      res := NEW(REF ARRAY OF CARDINAL, n);
    BEGIN
      FOR i := FIRST(res^) TO LAST(res^) DO
        res[i] := 0
      END;
      RETURN res
    END NewCardArray;

  VAR
    n := NUMBER(sarr);
  BEGIN
    IF doDebug THEN
      Debug.Out(F("Creating %s schedulers", Int(n)))
    END;
    
    AllSchedulers := Set { };
    
    FOR i := FIRST(sarr) TO LAST(sarr) DO
      AllSchedulers := AllSchedulers + Set { i };
      
      WITH new = NEW(T,
                     id       := i,
                     active   := NEW(REF ARRAY OF Process.Closure, 1),
                     next     := NEW(REF ARRAY OF Process.Closure, 1),
                     np       := 0,

                     mu       := NEW(MUTEX),
                     c        := NEW(Thread.Condition),
                     
                     rdirty   := NewChanArray(),
                     nrp      := NewCardArray(),
        
                     wdirty   := NewChanArray(),
                     nwp      := NewCardArray(),

                     idle     := AllSchedulers,
                     
                     thePhase := InitPhase
                     ) DO
        sarr[i] := new;

        new.commOutbox := NEW(REF ARRAY OF ClosureSeq.T, n + 1);
        new.waitOutbox := NEW(REF ARRAY OF ClosureSeq.T, n + 1);

        FOR j := 0 TO n + 1 - 1  DO
          new.commOutbox[j] := NEW(ClosureSeq.T).init();
          new.waitOutbox[j] := NEW(ClosureSeq.T).init()
        END;
      END(*WITH*)      
    END(*FOR*);

    IF doDebug THEN
      Debug.Out("AllSchedulers = " & FmtSet(AllSchedulers))
    END
  END CreateMulti;
  
PROCEDURE RunNondet(READONLY schedulers : ARRAY OF T; greedy : BOOLEAN) =

  PROCEDURE Pend(what : TEXT; i, j : [ -1..LAST(CARDINAL) ] ) =
    BEGIN
      Debug.Out(F("Pending : scheduler[%s] : %s[%s]",
                  Int(i), what, Int(j)))
    END Pend;
    
  PROCEDURE NothingPending() : BOOLEAN =
    BEGIN
      (* 
         something is pending if it is in the local queue of a scheduler
         or if it is in the outbox of a scheduler 

         or if a process is running
      *)

      IF idle # AllSchedulers THEN Pend("idle # AllSchedulers", -1, -1); RETURN FALSE END;

      FOR i := FIRST(schedulers) TO LAST(schedulers) DO
        <*ASSERT i IN idle*>
        WITH s = schedulers[i] DO
          IF s.np # 0 THEN Pend("np",i,-1); RETURN FALSE END;

          FOR j := FIRST(schedulers) TO LAST(schedulers) DO
            IF s.commOutbox[j].size() # 0 THEN Pend("commOutbox",i,j); RETURN FALSE END;
            IF s.waitOutbox[j].size() # 0 THEN Pend("waitOutbox",i,j); RETURN FALSE END;
            IF s.nrp[j] # 0 THEN Pend("nrp",i,j); RETURN FALSE END;
            IF s.nwp[j] # 0 THEN Pend("nwp",i,j); RETURN FALSE END
          END
        END
      END;
      RETURN TRUE
    END NothingPending;
  
  PROCEDURE CountPendingStuff() : CARDINAL =
    (* just for debugging, doesn't lock anything, can touch running
       schedulers *)
    VAR
      res : CARDINAL := 0;
    BEGIN
      (* something is pending if it is in the local queue of a scheduler
         or if it is in the outbox of a scheduler *)
      FOR i := FIRST(schedulers) TO LAST(schedulers) DO
        WITH s = schedulers[i] DO
          res := res + s.np;
          
          FOR j := FIRST(schedulers) TO LAST(schedulers) DO
            res := res + s.commOutbox[j].size();
            res := res + s.waitOutbox[j].size()
          END
        END
      END;
      RETURN res
    END CountPendingStuff;
  
  PROCEDURE RunPhase(phase : Phase) =
    BEGIN
      IF doDebug THEN
        Debug.Out(F("RunMulti.RunPhase(%s)", PhaseNames[phase]))
      END;

      FOR i := FIRST(schedulers) TO LAST(schedulers) DO
        IF i IN idle THEN
          <*ASSERT schedulers[i].thePhase = Phase.Idle*>
        END
      END;

      AcquireLocks(schedulers, idle);

      TRY
        SetPhase(schedulers, phase, idle)
      FINALLY
        ReleaseLocks(schedulers, idle)
      END;
      SignalThreads(schedulers, idle);
      AwaitIdle(idle)
    END RunPhase;

  PROCEDURE StartActivePhase() =
    BEGIN
      IF doDebug THEN
        Debug.Out(F("RunMulti.StartActivePhase"))
      END;

      FOR i := FIRST(schedulers) TO LAST(schedulers) DO
        IF i IN idle THEN
          <*ASSERT schedulers[i].thePhase = Phase.Idle*>
        END
      END;

      AcquireLocks(schedulers, idle);

      TRY
        SetPhase(schedulers, Phase.RunActiveBlocks, idle)
      FINALLY
        ReleaseLocks(schedulers, idle)
      END;
      SignalThreads(schedulers, idle);

      idle := Set {};
      
    END StartActivePhase;

  PROCEDURE UpdateTime() =
    BEGIN
      (* ensure time advances for everybody *)
      FOR i := FIRST(schedulers) TO LAST(schedulers) DO
        IF i IN idle THEN
          masterTime := MAX(masterTime, schedulers[i].time)
        END
      END;
      
      INC(masterTime);
    END UpdateTime;

  PROCEDURE UpdateIdle() =
    BEGIN
      (* ensure all the idle schedulers know with whom they can communicate *)
      FOR i := FIRST(schedulers) TO LAST(schedulers) DO
        IF i IN idle THEN
          schedulers[i].idle := idle
        END
      END
    END UpdateIdle;
    
  VAR
    idle  := Set {};
    (* this is the set of schedulers idle at the beginning of the loop *)
    
    cls   := NEW(REF ARRAY OF SchedClosure, NUMBER(schedulers));
    thrds := NEW(REF ARRAY OF Thread.T    , NUMBER(schedulers));

    iter  := 0;
  BEGIN
    FOR i := FIRST(cls^) TO LAST(cls^) DO
      cls[i]   := NEW(SchedClosure, t := schedulers[i], greedy := greedy);
      thrds[i] := Thread.Fork(cls[i]);
      idle     := idle + Set { i } (* all are idle *)
    END;

    LOOP
      IF doDebug THEN
        Debug.Out(F("=====  @ %s Master scheduling loop : np = %s , iter = %s",
                    Int(masterTime),
                    Int(CountPendingStuff()),
                    Int(iter)
                   )
                 )
      END;

      IF NothingPending() THEN
        Debug.Out("RunMulti : nothing pending---done at " & Int(masterTime));
        RETURN
      END;

      (* at the end of every Phase, all the schedulers are idle *)
      
      UpdateTime();

      UpdateIdle();
      
      RunPhase(Phase.GetOtherBlocksPartial);

      RunPhase(Phase.SwapActiveBlocksPartial);

      RunPhase(Phase.UpdateSurrogatesPartial);

      UpdateTime();

      StartActivePhase();

      INC(iter);

      GetIdle(idle);

      IF doDebug THEN
        Debug.Out("After GetIdle : idle schedulers : " & FmtSet(idle))
      END

    END
  END RunNondet;

BEGIN
  CspScheduler.GetTime := GetTime;
END CspCompiledScheduler.
