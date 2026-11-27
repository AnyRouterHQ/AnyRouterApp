---------------------------- MODULE LocalModelLifecycle ----------------------------
(***************************************************************************)
(* The local model lifecycle of AnyRouter: chats, warm-ups, unloads and    *)
(* deletes that share one generation gate and one set of loaded weights.   *)
(*                                                                         *)
(* One step of this model is one indivisible step of the Swift code: a     *)
(* method of an actor that runs without a suspension point, or the code    *)
(* between two awaits. The comment "CODE <file> :: <text>" above an action *)
(* names the line that step comes from. scripts/formal-conformance.py      *)
(* fails when that line is gone, so a change to the code cannot drift away *)
(* from this file unnoticed.                                               *)
(*                                                                         *)
(* The five FLAG constants are the design decisions the code makes. TRUE   *)
(* is what the code does now. FALSE is what it did before the bug that the *)
(* matching invariant found, so each can be switched back to show that the *)
(* invariant fails without it (formal/mutants).                            *)
(***************************************************************************)
EXTENDS Naturals, Sequences, FiniteSets, TLC

CONSTANTS
    ChatReqs,             \* chat streams that may start: one GGUFEngine or MLXEngine stream call each
    WarmReqs,             \* warm-ups that may start: one GGUFEngine.warm call each
    DeletableModels,      \* models the user may delete from the Hub, once each
    SharedResidency,      \* FLAG: both engines use one gate and one cache of loaded weights
    UnloadDropsLoad,      \* FLAG: an unload also clears the load in progress
    DeleteUnloadsFirst,   \* FLAG FALSE: LocalModelHub.delete removes the files, then unloads
    CheckCancelAfterGate, \* FLAG: a stream cancelled while it waited at the gate stops there
    ReleaseOnEveryPath    \* FLAG: the gate is released after success, error and cancel

Engines == {"gguf", "mlx"}
Models  == {"g1", "g2", "m1"}   \* g1 and g2 are GGUF files, m1 is an MLX snapshot
NONE    == "none"

ASSUME /\ ChatReqs \cap WarmReqs = {}
       /\ DeletableModels \subseteq Models
       /\ {SharedResidency, UnloadDropsLoad, DeleteUnloadsFirst,
           CheckCancelAfterGate, ReleaseOnEveryPath} \subseteq BOOLEAN

EngineOf(m) == IF m = "m1" THEN "mlx" ELSE "gguf"
Reqs == ChatReqs \cup WarmReqs

\* The gate and the cache that serve an engine. With SharedResidency both engines use the "gguf" ones.
Slot(e)  == IF SharedResidency THEN "gguf" ELSE e
SlotOf(m) == Slot(EngineOf(m))

VARIABLES
    pc,        \* stage of each request, see Stages
    rmodel,    \* the model a request was started for
    canceled,  \* the consumer of a chat stream has gone (Task.cancel through onTermination)
    qcancel,   \* history: the stream was cancelled while it waited at the gate
    busy,      \* GenerationGate.busy, per slot
    waitq,     \* GenerationGate.waiters, per slot, first in first out
    cur,       \* the cache's current model, per slot
    ld,        \* the cache's loading, per slot: the model a load in progress is for
    loadOk,    \* the file could be opened when the load started, per slot
    warned,    \* history: an unload ran and no load has started since, per slot
    installed, \* models whose files are on disk
    dp         \* progress of the delete of each deletable model: 0 not started, 1 first half, 2 done

vars == <<pc, rmodel, canceled, qcancel, busy, waitq, cur, ld, loadOk, warned, installed, dp>>

Stages == {"idle", "queued", "gated", "manifested", "loading", "running", "releasing", "done", "leaked"}
Holding == {"gated", "manifested", "loading", "running", "releasing"}

\* Where a failed stream goes. Without ReleaseOnEveryPath it never gives the gate back.
FailStage == IF ReleaseOnEveryPath THEN "releasing" ELSE "leaked"

TypeOK ==
    /\ pc \in [Reqs -> Stages]
    /\ rmodel \in [Reqs -> Models \cup {NONE}]
    /\ canceled \in [Reqs -> BOOLEAN]
    /\ qcancel \in [Reqs -> BOOLEAN]
    /\ busy \in [Engines -> BOOLEAN]
    /\ waitq \in [Engines -> Seq(Reqs)]
    /\ cur \in [Engines -> Models \cup {NONE}]
    /\ ld \in [Engines -> Models \cup {NONE}]
    /\ loadOk \in [Engines -> BOOLEAN]
    /\ warned \in [Engines -> BOOLEAN]
    /\ installed \subseteq Models
    /\ dp \in [DeletableModels -> 0..2]

Init ==
    /\ pc = [r \in Reqs |-> "idle"]
    /\ rmodel = [r \in Reqs |-> NONE]
    /\ canceled = [r \in Reqs |-> FALSE]
    /\ qcancel = [r \in Reqs |-> FALSE]
    /\ busy = [e \in Engines |-> FALSE]
    /\ waitq = [e \in Engines |-> <<>>]
    /\ cur = [e \in Engines |-> NONE]
    /\ ld = [e \in Engines |-> NONE]
    /\ loadOk = [e \in Engines |-> FALSE]
    /\ warned = [e \in Engines |-> FALSE]
    /\ installed = Models
    /\ dp = [m \in DeletableModels |-> 0]

(***************************************************************************)
(* Chat stream: GGUFEngine.stream and MLXEngine.stream.                    *)
(***************************************************************************)

\* The stream takes its turn at the gate: GenerationGate.acquire runs at once or joins the queue.
\* CODE Engines/Local/GGUF/GGUFEngine.swift :: func stream( :: await residency.gate.acquire()
\* CODE Engines/Local/MLX/MLXEngine.swift :: func stream( :: await residency.gate.acquire()
\* CODE Engines/Local/LocalResidency.swift :: actor GenerationGate :: func acquire() async {
StartChat(r, m) ==
    /\ r \in ChatReqs
    /\ pc[r] = "idle"
    /\ rmodel' = [rmodel EXCEPT ![r] = m]
    /\ \/ /\ ~busy[SlotOf(m)]
          /\ busy' = [busy EXCEPT ![SlotOf(m)] = TRUE]
          /\ pc' = [pc EXCEPT ![r] = "gated"]
          /\ UNCHANGED waitq
       \/ /\ busy[SlotOf(m)]
          /\ waitq' = [waitq EXCEPT ![SlotOf(m)] = Append(@, r)]
          /\ pc' = [pc EXCEPT ![r] = "queued"]
          /\ UNCHANGED busy
    /\ UNCHANGED <<canceled, qcancel, cur, ld, loadOk, warned, installed, dp>>

\* The stream holds the gate. It checks for cancel (FLAG CheckCancelAfterGate), then reads the manifest.
\* CODE Engines/Local/GGUF/GGUFEngine.swift :: func stream( :: try Task.checkCancellation()
\* CODE Engines/Local/GGUF/GGUFEngine.swift :: func stream( :: storage.readManifest(entryID: model.id)
\* CODE Engines/Local/MLX/MLXEngine.swift :: func stream( :: try Task.checkCancellation()
\* CODE Engines/Local/MLX/MLXEngine.swift :: func stream( :: storage.isInstalled(entryID: model.id)
GateExit(r) ==
    /\ r \in ChatReqs
    /\ pc[r] = "gated"
    /\ \/ /\ CheckCancelAfterGate /\ canceled[r]
          /\ pc' = [pc EXCEPT ![r] = FailStage]
       \/ /\ ~(CheckCancelAfterGate /\ canceled[r])
          /\ rmodel[r] \in installed
          /\ pc' = [pc EXCEPT ![r] = "manifested"]
       \/ /\ ~(CheckCancelAfterGate /\ canceled[r])
          /\ rmodel[r] \notin installed
          /\ pc' = [pc EXCEPT ![r] = FailStage]
    /\ UNCHANGED <<rmodel, canceled, qcancel, busy, waitq, cur, ld, loadOk, warned, installed, dp>>

\* The generation ends: the stream finishes and the model reference goes away.
\* CODE Engines/Local/GGUF/GGUFEngine.swift :: func stream( :: continuation.finish()
\* CODE Engines/Local/MLX/MLXEngine.swift :: func stream( :: continuation.finish()
RunFinish(r) ==
    /\ pc[r] = "running"
    /\ pc' = [pc EXCEPT ![r] = "releasing"]
    /\ UNCHANGED <<rmodel, canceled, qcancel, busy, waitq, cur, ld, loadOk, warned, installed, dp>>

\* The consumer leaves. Task.cancel does not interrupt the wait at the gate or a load.
\* CODE Engines/Local/GGUF/GGUFEngine.swift :: func stream( :: continuation.onTermination = { _ in task.cancel() }
\* CODE Engines/Local/MLX/MLXEngine.swift :: func stream( :: continuation.onTermination = { _ in task.cancel() }
Cancel(r) ==
    /\ r \in ChatReqs
    /\ ~canceled[r]
    /\ pc[r] \in {"queued", "gated", "manifested", "loading", "running"}
    /\ canceled' = [canceled EXCEPT ![r] = TRUE]
    /\ qcancel' = [qcancel EXCEPT ![r] = (pc[r] = "queued")]
    /\ UNCHANGED <<pc, rmodel, busy, waitq, cur, ld, loadOk, warned, installed, dp>>

(***************************************************************************)
(* Warm-up: GGUFEngine.warm. It never waits for the gate.                  *)
(***************************************************************************)

\* The warm-up reads the manifest, then GenerationGate.tryAcquire takes the gate only when it is free.
\* CODE Engines/Local/GGUF/GGUFEngine.swift :: func warm( :: guard await residency.gate.tryAcquire() else { return }
\* CODE Engines/Local/LocalResidency.swift :: actor GenerationGate :: func tryAcquire() -> Bool {
StartWarm(r, m) ==
    /\ r \in WarmReqs
    /\ pc[r] = "idle"
    /\ EngineOf(m) = "gguf"
    /\ rmodel' = [rmodel EXCEPT ![r] = m]
    /\ \/ /\ m \notin installed
          /\ pc' = [pc EXCEPT ![r] = "done"]
          /\ UNCHANGED busy
       \/ /\ m \in installed
          /\ busy[SlotOf(m)]
          /\ pc' = [pc EXCEPT ![r] = "done"]
          /\ UNCHANGED busy
       \/ /\ m \in installed
          /\ ~busy[SlotOf(m)]
          /\ busy' = [busy EXCEPT ![SlotOf(m)] = TRUE]
          /\ pc' = [pc EXCEPT ![r] = "manifested"]
    /\ UNCHANGED <<waitq, canceled, qcancel, cur, ld, loadOk, warned, installed, dp>>

(***************************************************************************)
(* The cache of loaded weights: ResidentModels.weights.                    *)
(***************************************************************************)

\* A caller that holds the gate asks for the weights. A hit returns them. A miss frees the old weights
\* and starts a load. The actor runs this without a suspension point.
\* CODE Engines/Local/LocalResidency.swift :: func weights< :: if let current, current.key == key
\* CODE Engines/Local/LocalResidency.swift :: func weights< :: current = nil
\* CODE Engines/Local/LocalResidency.swift :: func weights< :: loading = (id, key, serial, task)
CacheRequest(r) ==
    /\ pc[r] = "manifested"
    /\ LET m == rmodel[r]
           s == SlotOf(m)
           after == IF r \in ChatReqs THEN "running" ELSE "releasing"
       IN \/ /\ cur[s] = m
             /\ pc' = [pc EXCEPT ![r] = after]
             /\ UNCHANGED <<cur, ld, loadOk, warned>>
          \/ /\ cur[s] # m
             /\ ld[s] = NONE
             /\ cur' = [cur EXCEPT ![s] = NONE]
             /\ ld' = [ld EXCEPT ![s] = m]
             /\ loadOk' = [loadOk EXCEPT ![s] = (m \in installed)]
             /\ warned' = [warned EXCEPT ![s] = FALSE]
             /\ pc' = [pc EXCEPT ![r] = "loading"]
    /\ UNCHANGED <<rmodel, canceled, qcancel, busy, waitq, installed, dp>>

\* The load finishes. The caller always gets the weights. The cache keeps them only when the load is
\* still the one in progress.
\* CODE Engines/Local/LocalResidency.swift :: func weights< :: if loading?.serial == serial {
LoadSucceed(r) ==
    /\ pc[r] = "loading"
    /\ LET m == rmodel[r]
           s == SlotOf(m)
           after == IF r \in ChatReqs THEN "running" ELSE "releasing"
       IN /\ loadOk[s]
          /\ pc' = [pc EXCEPT ![r] = after]
          /\ \/ /\ ld[s] = m
                /\ cur' = [cur EXCEPT ![s] = m]
                /\ ld' = [ld EXCEPT ![s] = NONE]
             \/ /\ ld[s] # m
                /\ UNCHANGED <<cur, ld>>
    /\ UNCHANGED <<rmodel, canceled, qcancel, busy, waitq, loadOk, warned, installed, dp>>

\* The load fails (file gone, model too big). The error goes to the caller.
\* CODE Engines/Local/LocalResidency.swift :: func weights< :: if loading?.serial == serial { loading = nil }
LoadFail(r) ==
    /\ pc[r] = "loading"
    /\ LET m == rmodel[r]
           s == SlotOf(m)
       IN /\ pc' = [pc EXCEPT ![r] = IF r \in ChatReqs THEN FailStage ELSE "releasing"]
          /\ ld' = IF ld[s] = m THEN [ld EXCEPT ![s] = NONE] ELSE ld
    /\ UNCHANGED <<rmodel, canceled, qcancel, busy, waitq, cur, loadOk, warned, installed, dp>>

(***************************************************************************)
(* Giving the gate back: GenerationGate.release.                           *)
(***************************************************************************)

\* The first waiter, if any, gets the gate without it ever being free.
\* CODE Engines/Local/GGUF/GGUFEngine.swift :: func stream( :: await residency.gate.release()
\* CODE Engines/Local/MLX/MLXEngine.swift :: func stream( :: await residency.gate.release()
\* CODE Engines/Local/LocalResidency.swift :: actor GenerationGate :: waiters.removeFirst().resume()
Release(r) ==
    /\ pc[r] = "releasing"
    /\ LET s == SlotOf(rmodel[r])
       IN \/ /\ waitq[s] = <<>>
             /\ busy' = [busy EXCEPT ![s] = FALSE]
             /\ pc' = [pc EXCEPT ![r] = "done"]
             /\ UNCHANGED waitq
          \/ /\ waitq[s] # <<>>
             /\ pc' = [pc EXCEPT ![r] = "done", ![Head(waitq[s])] = "gated"]
             /\ waitq' = [waitq EXCEPT ![s] = Tail(@)]
             /\ UNCHANGED busy
    /\ UNCHANGED <<rmodel, canceled, qcancel, cur, ld, loadOk, warned, installed, dp>>

(***************************************************************************)
(* Things that happen around the engines at any time.                      *)
(***************************************************************************)

\* A memory warning, the Unload button, or five minutes in the background. The cache drops the weights.
\* A running generation keeps its own reference. FLAG UnloadDropsLoad also drops the load in progress.
\* CODE Engines/Local/LocalResidency.swift :: func unload() { :: current = nil
\* CODE App/AppState.swift :: - :: didReceiveMemoryWarningNotification
\* CODE Features/Services/MemoryMonitor.swift :: func unload() async :: await unloadAll()
UnloadAll(e) ==
    /\ cur' = [cur EXCEPT ![Slot(e)] = NONE]
    /\ ld' = IF UnloadDropsLoad THEN [ld EXCEPT ![Slot(e)] = NONE] ELSE ld
    /\ warned' = [warned EXCEPT ![Slot(e)] = TRUE]
    /\ UNCHANGED <<pc, rmodel, canceled, qcancel, busy, waitq, loadOk, installed, dp>>

\* ResidentModels.unload(ifID:): the same, only for the model that was deleted.
\* CODE Engines/Local/LocalResidency.swift :: func unload(ifID id: String) { :: if current?.id == id { current = nil }
UnloadIfEffect(m) ==
    LET s == SlotOf(m)
    IN /\ cur' = IF cur[s] = m THEN [cur EXCEPT ![s] = NONE] ELSE cur
       /\ ld' = IF UnloadDropsLoad /\ ld[s] = m THEN [ld EXCEPT ![s] = NONE] ELSE ld

\* ModelDownloadManager.delete removes the files.
\* CODE Features/Services/LocalModelHub.swift :: func delete(modelID: String) async :: try downloads.delete(entry)
RemoveFilesEffect(m) == installed' = installed \ {m}

\* LocalModelHub.delete does two steps. FLAG DeleteUnloadsFirst says which goes first.
\* CODE Features/Services/LocalModelHub.swift :: func delete(modelID: String) async :: await unloadModel(modelID)
DeleteStep1(m) ==
    /\ dp[m] = 0
    /\ dp' = [dp EXCEPT ![m] = 1]
    /\ IF DeleteUnloadsFirst
          THEN (UnloadIfEffect(m) /\ UNCHANGED installed)
          ELSE (RemoveFilesEffect(m) /\ UNCHANGED <<cur, ld>>)
    /\ UNCHANGED <<pc, rmodel, canceled, qcancel, busy, waitq, loadOk, warned>>

DeleteStep2(m) ==
    /\ dp[m] = 1
    /\ dp' = [dp EXCEPT ![m] = 2]
    /\ IF DeleteUnloadsFirst
          THEN (RemoveFilesEffect(m) /\ UNCHANGED <<cur, ld>>)
          ELSE (UnloadIfEffect(m) /\ UNCHANGED installed)
    /\ UNCHANGED <<pc, rmodel, canceled, qcancel, busy, waitq, loadOk, warned>>

(***************************************************************************)
(* What each FLAG means in the code. scripts/formal-conformance.py checks   *)
(* the lines for the flags that formal/LocalModelLifecycle.cfg sets.        *)
(***************************************************************************)
\* WHEN SharedResidency=TRUE ABSENT Engines/Local/GGUF/GGUFEngine.swift :: GenerationGate()
\* WHEN SharedResidency=TRUE ABSENT Engines/Local/MLX/MLXEngine.swift :: GenerationGate()
\* WHEN SharedResidency=TRUE ABSENT Engines/Local/GGUF/GGUFEngine.swift :: ResidentModels(
\* WHEN SharedResidency=TRUE ABSENT Engines/Local/MLX/MLXEngine.swift :: ResidentModels(
\* WHEN SharedResidency=TRUE COUNT App/AppState.swift :: - :: LocalResidency( :: 1
\* WHEN SharedResidency=TRUE CODE App/AppState.swift :: - :: GGUFEngine(telemetry: telemetry, residency: residency, loadLog: diagnostics)
\* WHEN SharedResidency=TRUE CODE App/AppState.swift :: - :: MLXEngine(telemetry: telemetry, residency: residency)
\* WHEN UnloadDropsLoad=TRUE CODE Engines/Local/LocalResidency.swift :: func unload() { :: loading = nil
\* WHEN UnloadDropsLoad=TRUE CODE Engines/Local/LocalResidency.swift :: func unload(ifID id: String) { :: if loading?.id == id { loading = nil }
\* WHEN DeleteUnloadsFirst=FALSE ORDER Features/Services/LocalModelHub.swift :: func delete(modelID: String) async :: try downloads.delete(entry) >> await unloadModel(modelID)
\* WHEN CheckCancelAfterGate=TRUE ORDER Engines/Local/GGUF/GGUFEngine.swift :: func stream( :: await residency.gate.acquire() >> try Task.checkCancellation() >> storage.readManifest(entryID: model.id) >> loadWeights(
\* WHEN CheckCancelAfterGate=TRUE ORDER Engines/Local/MLX/MLXEngine.swift :: func stream( :: await residency.gate.acquire() >> try Task.checkCancellation() >> storage.isInstalled(entryID: model.id) >> residency.models.weights(
\* WHEN ReleaseOnEveryPath=TRUE ORDER Engines/Local/GGUF/GGUFEngine.swift :: func stream( :: } catch is CancellationError >> } catch { >> await residency.gate.release()
\* WHEN ReleaseOnEveryPath=TRUE ORDER Engines/Local/MLX/MLXEngine.swift :: func stream( :: } catch is CancellationError >> } catch { >> await residency.gate.release()
\* WHEN ReleaseOnEveryPath=TRUE COUNT Engines/Local/GGUF/GGUFEngine.swift :: func stream( :: await residency.gate.release() :: 1
\* WHEN ReleaseOnEveryPath=TRUE COUNT Engines/Local/MLX/MLXEngine.swift :: func stream( :: await residency.gate.release() :: 1
\* WHEN ReleaseOnEveryPath=TRUE ORDER Engines/Local/GGUF/GGUFEngine.swift :: func warm( :: guard await residency.gate.tryAcquire() >> try? await loadWeights( >> await residency.gate.release()

(***************************************************************************)
(* Who may touch the gate, the cache, a warm-up or an unload. A new caller  *)
(* is a new way for steps to interleave: add it to the model first.         *)
(***************************************************************************)
\* ONLY Engines/Local/GGUF/GGUFEngine.swift, Engines/Local/MLX/MLXEngine.swift, Engines/Local/LocalResidency.swift, App/AppState.swift :: \bresidency\.(gate|models)\b|\bResidentModels\b|\bGenerationGate\b|\bLocalResidency\b
\* ONLY App/AppState.swift :: \.warm\(model
\* ONLY App/AppState.swift, Features/Services/LocalModelHub.swift :: \b(gguf|mlx)\.unload\(|\bunloadModel\(
\* ONLY Features/Services/MemoryMonitor.swift :: \bunloadAll\(

Progress ==
    \/ (\E r \in ChatReqs, m \in Models : StartChat(r, m))
    \/ (\E r \in WarmReqs, m \in Models : StartWarm(r, m))
    \/ (\E r \in Reqs : \/ GateExit(r)
                        \/ CacheRequest(r)
                        \/ LoadSucceed(r)
                        \/ LoadFail(r)
                        \/ RunFinish(r)
                        \/ Release(r))

Environment ==
    \/ (\E r \in Reqs : Cancel(r))
    \/ (\E e \in Engines : UnloadAll(e))
    \/ (\E m \in DeletableModels : DeleteStep1(m) \/ DeleteStep2(m))

Next == Progress \/ Environment

Spec == Init /\ [][Next]_vars

\* For the liveness check only: every step the code takes on its own is taken in the end.
LiveSpec == Spec /\ WF_vars(Progress)

(***************************************************************************)
(* What must hold.                                                         *)
(***************************************************************************)

\* One thing at a time per gate: a load, a generation, or a warm-up. Never two.
OneHolderPerGate ==
    \A s \in Engines :
        Cardinality({r \in Reqs : pc[r] \in Holding /\ SlotOf(rmodel[r]) = s}) <= 1

\* The gate is busy exactly while some request holds it, and a request waits exactly while it is queued.
GateMatchesHolders ==
    /\ \A s \in Engines :
          busy[s] = (\E r \in Reqs : pc[r] \in Holding /\ SlotOf(rmodel[r]) = s)
    /\ \A r \in Reqs :
          (pc[r] = "queued") <=> (\E s \in Engines : \E i \in 1..Len(waitq[s]) : waitq[s][i] = r)

\* Nothing is stuck at the gate once every request is over.
NoGateLeak ==
    (\A r \in Reqs : pc[r] \in {"idle", "done"}) =>
        \A s \in Engines : ~busy[s] /\ waitq[s] = <<>>

\* Only one generation runs at a time, on either engine.
OneGenerationAtATime ==
    Cardinality({r \in ChatReqs : pc[r] = "running"}) <= 1

\* The weights of one local model are in memory at most: the fit check judges a model as if it were alone.
InMemory ==
    ({cur[s] : s \in Engines} \ {NONE}) \cup
    {rmodel[r] : r \in {x \in Reqs : pc[x] \in {"loading", "running"}}}
AtMostOneModelInMemory == Cardinality(InMemory) <= 1

\* The join path of the cache is never taken: every caller of the cache holds the gate.
LoadOwnedByHolder ==
    \A s \in Engines :
        ld[s] # NONE => \E r \in Reqs : pc[r] = "loading" /\ rmodel[r] = ld[s]

\* When a delete is over, the cache does not hold the deleted model.
DeletedModelNotResident ==
    \A m \in DeletableModels : dp[m] = 2 => \A s \in Engines : cur[s] # m

\* A stream cancelled while it waited at the gate never reads a manifest or starts a load.
CancelledInQueueNeverLoads ==
    \A r \in ChatReqs : qcancel[r] => pc[r] \notin {"manifested", "loading", "running"}

\* After an unload and with no request in flight, nothing is loaded, unless a load started after the unload.
UnloadHonoredWhenIdle ==
    (\A r \in Reqs : pc[r] \in {"idle", "done"}) =>
        \A s \in Engines : warned[s] => cur[s] = NONE

\* Every request ends.
EveryRequestEnds == <>(\A r \in Reqs : pc[r] = "done")

\* Symmetry for TLC: two chat requests are interchangeable.
ChatSym == Permutations(ChatReqs)

=============================================================================
