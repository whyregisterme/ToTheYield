Scriptname TTY_NpcDuel extends Quest
{To the Yield, NPC against NPC: a formal duel between two NPCs, fought until one yields or goes down.
 Nobody dies. Separate from TTY_Main (the player's duels), so neither can disturb the other.

 Tested live on spawned NPCs, 2026-10-23, and built on what held:
   - Two NPCs from different groups (a guard and a hunter) stay in a StartCombat fight.
     Two members of the same group never fight, whatever their rank or extra factions: refused.
   - With both duelists in the vanilla brawl faction, a fellow guard watching stayed out for 15 s.
     Without it he joined within a second, and stopping him only had him rejoin (11 times in 15 s).
   - Each duelist sits in an Essential alias, as TTY_Main's opponent does: at zero health they
     kneel in bleedout instead of dying.

 SkyrimNet actions (layer actions/): ChallengeDuel (challenger names the target), AcceptDuel and
 DeclineDuel (the challenged NPC answers), YieldNpcDuel (a duelist concedes). An accepted challenge
 shows the player NpcConfirmMsg first: Allow / Stop it / Stop it silently, or the same on a Magelight UI
 page when Magelight is installed (TTY_UI; TTY_UseMagelight 0 = the box always).

 StorageUtil keys. The layer's YAML and prompt read the same strings with papyrus_util:
     TTY_NpcDuelActive   int, global (None)   1 while an NPC duel is being fought
     TTY_NpcAsking       int, global          1 while the player decides whether to allow one
     TTY_NpcChallenger   form, global         the NPC whose challenge is waiting for an answer
     TTY_NpcChallengeTarget form, global      the NPC that challenge waits on
     TTY_NpcChallengePending int, global      1 while a challenge waits (ChallengeDuel is hidden)
     TTY_NpcChallenged   int, on the target   1 while a challenge waits on that NPC's answer
     TTY_NpcChallengerName string, on target  who challenged them, for their prompt
     TTY_NpcStatus       string, global       one line about the duel, for spectators' prompts
     TTY_NpcDuelist      int, on each NPC     1 while that NPC is a duelist
     TTY_NpcDuelFoe      string, on each NPC  the other duelist's name, for the duelist's prompt
     TTY_NpcBrave        form list, global    the duelists whose Confidence a duel raised
     TTY_NpcConfidence   float, on each NPC   that duelist's base Confidence before the duel
     TTY_NpcYieldOffer   int, on the winner   1 while a yield offered to them waits on their answer
     TTY_NpcYieldFrom    string, on winner    who offered it, for their prompt
     TTY_NpcDeathOK      int, on the winner   1 when a fight to the death is one of their answers
     TTY_NpcRefused      int, on the loser    how many of their offered yields were refused
     TTY_NpcToTheDeath   int, global          1 once the player allowed a fight to the death

 A spoken yield is an offer (YieldNpcDuel): the winner answers with AcceptNpcYield, RefuseNpcYield (they
 fight on; a fall still ends it) or DeathNpcDuel, which the player allows or stops (NpcDeathMsg). Ria and
 Njada in simulation, 2026-11-10: with "refuse" meaning only death, a winner who wanted "get up" chose it
 anyway; with "fight on" offered, no winner chose death in ten takes. So both answers exist.

 Stuck? From the console: stopquest TTY_NpcDuelQuest, then startquest TTY_NpcDuelQuest.}

ReferenceAlias Property DuelistA Auto
{Alias 1, flagged Essential and Optional. Filling it is what protects the first duelist.}

ReferenceAlias Property DuelistB Auto
{Alias 2, flagged Essential and Optional.}

Faction Property BrawlFaction Auto
{Skyrim.esm DGIntimidateFaction (0x04CFA6). Keeps bystanders out of the fight.}

Message Property NpcConfirmMsg Auto
{"Two of them are about to fight a duel..." with Allow / Stop it / Stop it silently. The box names nobody
 (alias tags printed "[...]" in game), so a notification names the duelists just before it.}

GlobalVariable Property BystanderGuard Auto
{TTY_BystanderGuard: 1 while a duel is fought. TTY_BystanderGhostAbility (given to NPCs by SPID,
 ToTheYield_DISTR.ini) turns bystanders near the player ghost while it is 1, so stray blows pass
 through them. Without SPID nothing reads it.}

Faction Property DuelistFaction Auto
{TTY_DuelistFaction: the duelists, whom the ghost ability leaves alone.}

GlobalVariable Property UseMagelight Auto
{TTY_UseMagelight, shared with TTY_Main: 0 = always the message box. Takes effect at the next load.}

Message Property NpcDeathMsg Auto
{"One of them refuses the other's yield and wants a fight to the death." with Allow / Stop it /
 Stop it silently: the player decides, as for the duel itself.}

; Tuning. Times are real seconds.
float Property TickSeconds = 0.5 AutoReadOnly
float Property LeadInSeconds = 1.0 AutoReadOnly
float Property MaxDuelSeconds = 180.0 AutoReadOnly       ; after this it is called a draw
float Property MaxStartDistance = 1500.0 AutoReadOnly    ; between the duelists, about 21 m
float Property SeparatedDistance = 3000.0 AutoReadOnly
float Property RecoverHealthFraction = 0.3 AutoReadOnly
float Property RekickSeconds = 1.0 AutoReadOnly
float Property EngageGraceSeconds = 4.0 AutoReadOnly
float Property SAStartSeconds = 15.0 AutoReadOnly        ; SeverActions' same-side duel must start within this
float Property ChallengeSeconds = 60.0 AutoReadOnly       ; an unanswered challenge lapses after this
int Property CooldownSeconds = 120 AutoReadOnly          ; before ChallengeDuel is offered again
float Property AnswerSeconds = 30.0 AutoReadOnly         ; an offered yield the winner never answers stands
float Property YieldAgainSeconds = 15.0 AutoReadOnly     ; after "fight on", before a spoken yield counts again
float Property SparedSeconds = 10.0 AutoReadOnly         ; kneeling this long to the death, unfinished: spared

Actor duelA = None
Actor duelB = None
bool aJoinedBrawl = false
bool bJoinedBrawl = false
float startTime = 0.0
float lastRekick = 0.0
float disengagedSince = 0.0
float challengeTime = 0.0
int uiView = 0             ; the Magelight page this session, 0 = message boxes
int saHandle = 0           ; SeverActions' duel (a same-side pair, TTY_SA), 0 = To the Yield's own
bool saStarted = false     ; SeverActions has started the fight
float saStartedAt = 0.0
bool uiShowing = false     ; this script's card is up on the page
bool deathShowing = false  ; it is the "to the death?" card, not the duel offer
bool aKillable = false     ; neither was essential before the duel made them so: a death is possible
bool bKillable = false
bool toTheDeath = false    ; the player allowed a fight to the death
Actor yieldWinner = None   ; the duelist a yield was offered to, and who offered it
Actor yieldLoser = None
float offeredAt = 0.0
float yieldAgainAt = 0.0
float kneelSince = 0.0     ; to the death, when the kneeling one went down

; States: "" (no duel), "Asking" (the player decides), "Fighting", "Offered" (a yield waits on the
; winner's answer), "AskingDeath" (the player decides on a fight to the death), "Ending".

Event OnInit()
    Reset()
    SetupUI()
EndEvent

; Magelight forgets mods, views and listeners between sessions, and mod event registrations last one
; load, so this runs on every load. The page is TTY_Main's too: this script listens on its own name.
Function SetupUI()
    uiView = 0
    uiShowing = false
    deathShowing = false
    ; SeverActions' Duel API, for two NPCs of the same side (TTY_SA). Events last one load.
    RegisterForModEvent("SeverActions_DuelStarted", "OnSADuelStarted")
    RegisterForModEvent("SeverActions_DuelEnded", "OnSADuelEnded")
    if !UseMagelight || UseMagelight.GetValue() <= 0
        return
    endif
    uiView = TTY_UI.Setup("ttyNpcChoice")
    if uiView
        RegisterForModEvent("Magelight_JS_ttyNpcChoice", "OnUiChoice")
        RegisterForModEvent("Magelight_UIModeExited", "OnUiExited")
        RegisterForModEvent("Magelight_ViewLoadFailed", "OnUiFailed")
    endif
EndFunction

bool Function UiReady()
    return uiView != 0 && !uiShowing && UseMagelight && UseMagelight.GetValue() > 0
EndFunction

; Outside a fight the only update is the challenge expiry, registered by ChallengeDuel.
Event OnUpdate()
    if StorageUtil.GetFormValue(None, "TTY_NpcChallenger") && Utility.GetCurrentRealTime() - challengeTime >= ChallengeSeconds
        Debug.Trace("[TTY] NPC duel challenge lapsed unanswered")
        ClearChallenge()
    endif
EndEvent

; ---------------------------------------------------------------------------------------------
; SkyrimNet actions
; ---------------------------------------------------------------------------------------------

; ChallengeDuel.yaml: the speaker dares akTarget to a duel. Nothing starts until they accept.
Function ChallengeDuel(Actor akChallenger, Actor akTarget)
    if !akChallenger || !akTarget
        Debug.Trace("[TTY] ChallengeDuel: no challenger or no target")
        return
    endif
    Debug.Trace("[TTY] ChallengeDuel: " + akChallenger.GetDisplayName() + " -> " + akTarget.GetDisplayName())
    if akTarget == Game.GetPlayer()
        ; The player's own duels are BeginDuel (TTY_Main). Nothing to record here.
        return
    endif
    ; Tested live: the challenger, hearing their own challenge recorded, issued it again while the
    ; duel was starting. A repeat about a duel already waiting or under way is not news: drop it quietly.
    if StorageUtil.GetIntValue(None, "TTY_NpcChallengePending", 0) == 1 || GetState() != ""
        Debug.Trace("[TTY] ChallengeDuel ignored: a challenge or duel is already in hand")
        return
    endif
    string reason = CannotDuelReason(akChallenger, akTarget)
    if reason != ""
        Debug.Notification("No duel: " + reason + ".")
        return
    endif
    ; One challenge waits at a time: a new one replaces it.
    ClearChallenge()
    StorageUtil.SetFormValue(None, "TTY_NpcChallenger", akChallenger)
    StorageUtil.SetFormValue(None, "TTY_NpcChallengeTarget", akTarget)
    StorageUtil.SetIntValue(None, "TTY_NpcChallengePending", 1)
    StorageUtil.SetIntValue(akTarget, "TTY_NpcChallenged", 1)
    StorageUtil.SetStringValue(akTarget, "TTY_NpcChallengerName", akChallenger.GetDisplayName())
    challengeTime = Utility.GetCurrentRealTime()
    SkyrimNetApi.RegisterEvent("persistent_generic", "{\"line\":\"" + JsonEscape(akChallenger.GetDisplayName() + " challenged " + akTarget.GetDisplayName() + " to a duel with weapons and magic.") + "\"}", akChallenger, akTarget)
    RegisterForSingleUpdate(ChallengeSeconds + 1.0)
EndFunction

; AcceptDuel.yaml: the challenged speaker says yes. The player still gets the last word.
Function AcceptDuel(Actor akAccepter)
    Actor challenger = StorageUtil.GetFormValue(None, "TTY_NpcChallenger") as Actor
    if !akAccepter || !challenger || StorageUtil.GetIntValue(akAccepter, "TTY_NpcChallenged", 0) != 1
        string who = "nobody"
        string waits = "no one"
        Actor target = StorageUtil.GetFormValue(None, "TTY_NpcChallengeTarget") as Actor
        if akAccepter
            who = akAccepter.GetDisplayName() + " (" + akAccepter.GetFormID() + ")"
        endif
        if target
            waits = target.GetDisplayName() + " (" + target.GetFormID() + ")"
        endif
        Debug.Trace("[TTY] AcceptDuel: no challenge is waiting on this speaker: " + who + "; one waits on " + waits)
        return
    endif
    ClearChallenge()
    string reason = CannotDuelReason(challenger, akAccepter)
    if reason != ""
        Debug.Notification("No duel: " + reason + ".")
        return
    endif
    if !NpcConfirmMsg || !DuelistA || !DuelistB
        Debug.Trace("[TTY] TTY_NpcDuelQuest properties are not filled; is ToTheYield.esp enabled?", 2)
        return
    endif

    ; Before the aliases make them essential: anyone a quest keeps alive stays out of a fight to the death.
    aKillable = !challenger.IsEssential()
    bKillable = !akAccepter.IsEssential()
    DuelistA.ForceRefTo(challenger)
    DuelistB.ForceRefTo(akAccepter)
    ; Asking holds off any other duel until the player answers, which on the page comes later (OnUiChoice).
    GoToState("Asking")
    StorageUtil.SetIntValue(None, "TTY_NpcAsking", 1)
    if UiReady()
        uiShowing = true
        string json = "{\"a\":\"" + JsonEscape(challenger.GetDisplayName()) + "\"" \
            + ",\"b\":\"" + JsonEscape(akAccepter.GetDisplayName()) + "\"}"
        if TTY_UI.Open(uiView, "ttyNpcOffer", json)
            return
        endif
        uiShowing = false
    endif
    AskWithBox()
EndFunction

Function AskWithBox()
    Actor challenger = DuelistA.GetActorReference()
    Actor akAccepter = DuelistB.GetActorReference()
    if challenger && akAccepter
        ; The box can't name anyone, so the notification just before it does.
        Debug.Notification(challenger.GetDisplayName() + " and " + akAccepter.GetDisplayName() + " are about to duel")
    endif
    ; Buttons, in NpcConfirmMsg's order: 0 Allow, 1 Stop it, 2 Stop it silently.
    Decide(NpcConfirmMsg.Show())
EndFunction

; The player's answer, from the box or the page: 0 Allow, 1 Stop it, 2 Stop it silently.
Function Decide(int choice)
    if GetState() != "Asking"
        return
    endif
    GoToState("")
    StorageUtil.UnsetIntValue(None, "TTY_NpcAsking")
    Actor challenger = DuelistA.GetActorReference()
    Actor akAccepter = DuelistB.GetActorReference()
    if !challenger || !akAccepter
        DuelistA.Clear()
        DuelistB.Clear()
        return
    endif
    if choice != 0
        DuelistA.Clear()
        DuelistB.Clear()
        SkyrimNetApi.SetActionCooldown("ChallengeDuel", CooldownSeconds)
        if choice == 1
            ; Narrated, so the two react to being stopped.
            SkyrimNetApi.DirectNarration("*" + Game.GetPlayer().GetDisplayName() + " steps between " + challenger.GetDisplayName() + " and " + akAccepter.GetDisplayName() + " and forbids the duel.*", challenger, akAccepter)
        else
            Debug.Trace("[TTY] Player silently stopped an NPC duel")
        endif
        return
    endif
    ; The game was paused while the player chose: check again in case something changed around it.
    string reason = CannotDuelReason(challenger, akAccepter)
    if reason != ""
        DuelistA.Clear()
        DuelistB.Clear()
        Debug.Notification("No duel: " + reason + ".")
        return
    endif
    StartDuel(challenger, akAccepter)
EndFunction

; ---------------------------------------------------------------------------------------------
; Magelight page events. Every mod, and TTY_Main, hears every Magelight event: each checks the view
; and whether this script's card is the one up. Functions, not Events: Caprica refuses new event names
; on a non-native script, and in a Skyrim .pex an event is only a function; SKSE calls it by name.
; ---------------------------------------------------------------------------------------------

; The card's buttons: "allow", "stop", "quiet".
Function OnUiChoice(string asEventName, string asChoice, float afView, Form akSender)
    if uiView == 0 || afView as int != uiView || !uiShowing
        return
    endif
    uiShowing = false
    TTY_UI.Close(uiView)
    if deathShowing
        deathShowing = false
        if asChoice == "allow"
            DecideDeath(0)
        elseif asChoice == "stop"
            DecideDeath(1)
        else
            DecideDeath(2)
        endif
        return
    endif
    if asChoice == "allow"
        Decide(0)
    elseif asChoice == "stop"
        Decide(1)
    else
        Decide(2)
    endif
EndFunction

; Escape or the host's toggle key closed the page: the duel is stopped silently.
; TTY_UI.Close raises this too, after uiShowing is already cleared, so that one is ignored.
Function OnUiExited(string asEventName, string asModId, float afView, Form akSender)
    if uiView == 0 || afView as int != uiView || !uiShowing
        return
    endif
    uiShowing = false
    TTY_UI.Close(uiView)
    if deathShowing
        ; The yield stands, silently: the answer that can't kill anyone.
        deathShowing = false
        DecideDeath(2)
        return
    endif
    Decide(2)
EndFunction

; The page couldn't load: the box for the rest of the session, and for the card if one was up.
Function OnUiFailed(string asEventName, string asDetail, float afView, Form akSender)
    if uiView == 0 || afView as int != uiView
        return
    endif
    Debug.Trace("[TTY] Magelight page failed to load (" + asDetail + "): message boxes this session")
    bool wasShowing = uiShowing
    uiShowing = false
    uiView = 0
    if wasShowing
        TTY_UI.Close(afView as int)
        if deathShowing
            deathShowing = false
            AskDeathWithBox()
        elseif GetState() == "Asking"
            AskWithBox()
        endif
    endif
EndFunction

; SeverActions_DuelStarted / _DuelEnded (DUEL_API.md). TTY_Main hears the same events and keeps its
; own handle: only the handle tells duels apart.
Function OnSADuelStarted(string asEventName, string asWhy, float afHandle, Form akSender)
    if saHandle > 0 && afHandle as int == saHandle
        saStarted = true
        saStartedAt = Utility.GetCurrentRealTime()
        if duelA && duelB
            duelA.StartCombat(duelB)
            duelB.StartCombat(duelA)
        endif
    endif
EndFunction

; SeverActions ended it before we did ("ended" is our own Duel_End, which clears saHandle first).
Function OnSADuelEnded(string asEventName, string asWhy, float afHandle, Form akSender)
    if saHandle <= 0 || afHandle as int != saHandle
        return
    endif
    saHandle = 0
    saStarted = false
    if GetState() != "Fighting"
        return
    endif
    if asWhy == "calledoff"
        EndDuel(None, None, "interrupted")
    elseif asWhy == "expired"
        EndDuel(None, None, "time")
    elseif asWhy == "death"
        EndDuel(None, None, "broken")
    elseif asWhy == "load"
        EndDuel(None, None, "reloaded")
    endif
EndFunction

; DeclineDuel.yaml: the challenged speaker refuses.
Function DeclineDuel(Actor akDecliner)
    Actor challenger = StorageUtil.GetFormValue(None, "TTY_NpcChallenger") as Actor
    if !akDecliner || StorageUtil.GetIntValue(akDecliner, "TTY_NpcChallenged", 0) != 1
        return
    endif
    ClearChallenge()
    if challenger
        SkyrimNetApi.RegisterEvent("persistent_generic", "{\"line\":\"" + JsonEscape(akDecliner.GetDisplayName() + " declined " + challenger.GetDisplayName() + "'s challenge to a duel.") + "\"}", akDecliner, challenger)
        TTY_Records.Refusal(challenger, akDecliner)
    endif
EndFunction

; YieldNpcDuel.yaml: a duelist offers their yield. Only does anything while Fighting (OfferNpcYield).
Function YieldNpcDuel(Actor akSpeaker)
EndFunction

; The winner's answers to an offered yield (AcceptNpcYield / RefuseNpcYield / DeathNpcDuel.yaml). Only
; State Offered does anything with them.
Function AcceptNpcYield(Actor akSpeaker)
EndFunction

Function RefuseNpcYield(Actor akSpeaker)
EndFunction

Function DeathNpcDuel(Actor akSpeaker)
EndFunction

Function OfferNpcYield(Actor akWinner, Actor akLoser)
EndFunction

Function ClearChallenge()
    Actor target = StorageUtil.GetFormValue(None, "TTY_NpcChallengeTarget") as Actor
    if target
        StorageUtil.UnsetIntValue(target, "TTY_NpcChallenged")
        StorageUtil.UnsetStringValue(target, "TTY_NpcChallengerName")
    endif
    StorageUtil.UnsetFormValue(None, "TTY_NpcChallenger")
    StorageUtil.UnsetFormValue(None, "TTY_NpcChallengeTarget")
    StorageUtil.UnsetIntValue(None, "TTY_NpcChallengePending")
EndFunction

; Starts a duel between two NPCs. Returns "" on success, else why not. AcceptDuel calls it once the
; player allows the duel.
string Function StartDuel(Actor akA, Actor akB)
    if !DuelistA || !DuelistB || !BrawlFaction
        Debug.Trace("[TTY] TTY_NpcDuelQuest properties are not filled; is ToTheYield.esp enabled?", 2)
        return "not set up"
    endif
    string reason = CannotDuelReason(akA, akB)
    if reason != ""
        Debug.Trace("[TTY] No NPC duel: " + reason)
        return reason
    endif
    ; Two of the same side won't fight on their own: SeverActions stages it, and sets their courage
    ; and the brawl faction itself (restoring only what it changed), so those are left to it.
    saHandle = 0
    saStarted = false
    bool sa = akA.GetFactionReaction(akB) >= 2
    if sa
        saHandle = TTY_SABridge.Begin(akA, akB, MaxDuelSeconds + 60.0)
        if saHandle <= 0
            saHandle = 0
            DuelistA.Clear()
            DuelistB.Clear()
            Debug.Notification("No duel: SeverActions couldn't start it.")
            return "SeverActions refused"
        endif
    endif
    GoToState("Fighting")
    duelA = akA
    duelB = akB
    DuelistA.ForceRefTo(akA)
    DuelistB.ForceRefTo(akB)

    aJoinedBrawl = false
    bJoinedBrawl = false
    if !sa
        aJoinedBrawl = !akA.IsInFaction(BrawlFaction)
        if aJoinedBrawl
            akA.AddToFaction(BrawlFaction)
        endif
        bJoinedBrawl = !akB.IsInFaction(BrawlFaction)
        if bJoinedBrawl
            akB.AddToFaction(BrawlFaction)
        endif
    endif

    GuardOn(akA, akB)
    if !sa
        Embolden(akA)
        Embolden(akB)
    endif

    string a = akA.GetDisplayName()
    string b = akB.GetDisplayName()
    StorageUtil.SetIntValue(None, "TTY_NpcDuelActive", 1)
    StorageUtil.SetStringValue(None, "TTY_NpcStatus", a + " and " + b + " are fighting a duel with weapons and magic, until one of them yields or goes down.")
    StorageUtil.SetIntValue(akA, "TTY_NpcDuelist", 1)
    StorageUtil.SetIntValue(akB, "TTY_NpcDuelist", 1)
    StorageUtil.SetStringValue(akA, "TTY_NpcDuelFoe", b)
    StorageUtil.SetStringValue(akB, "TTY_NpcDuelFoe", a)
    SkyrimNetApi.RegisterEvent("persistent_generic", "{\"line\":\"" + JsonEscape(a + " and " + b + " began a duel with weapons and magic.") + "\"}", akA, akB)

    startTime = Utility.GetCurrentRealTime()
    lastRekick = startTime
    disengagedSince = 0.0
    akA.DrawWeapon()
    akB.DrawWeapon()
    Utility.Wait(LeadInSeconds)
    ; Either can be deleted during the wait; OnUpdate then ends it.
    if GetState() == "Fighting" && akA && akB
        ; SeverActions starts a same-side pair's fight itself (OnSADuelStarted).
        if !sa
            akA.StartCombat(akB)
            akB.StartCombat(akA)
        endif
        RegisterForSingleUpdate(TickSeconds)
    endif
    return ""
EndFunction

string Function CannotDuelReason(Actor akA, Actor akB)
    Actor player = Game.GetPlayer()
    if GetState() != ""
        return "an NPC duel is already under way"
    elseif StorageUtil.GetIntValue(None, "TTY_Active", 0) == 1
        ; One duel of any kind at a time: not while the player is fighting one (TTY_Main).
        return "a duel is already under way"
    elseif StorageUtil.GetIntValue(None, "TTY_Asking", 0) == 1
        return "another duel is waiting on your answer"
    elseif !akA || !akB || akA == akB || akA == player || akB == player
        return "needs two NPCs"
    elseif akA.IsDead() || akB.IsDead()
        return "a duelist is dead"
    elseif akA.IsChild() || akB.IsChild()
        return "not with a child"
    elseif akA.IsInCombat() || akB.IsInCombat()
        return "someone is already fighting"
    elseif akA.GetFactionReaction(akB) >= 2 && !TTY_SA.Available()
        ; Ally or friend: the same group. They will not fight (tested), unless SeverActions' Duel
        ; API stages it (StartDuel).
        return akA.GetDisplayName() + " and " + akB.GetDisplayName() + " are on the same side"
    elseif akA.GetDistance(akB) > MaxStartDistance
        return "too far apart"
    endif
    return ""
EndFunction

; From TTY_NpcDuelistAlias. They do nothing outside a fight; State Fighting overrides them.
Function OnDuelistDown(Actor akDown)
EndFunction

Function OnOutsideAttack(Actor akVictim, Actor akAttacker)
EndFunction

Function EndDuel(Actor akWinner, Actor akLoser, string asHow)
EndFunction

; From TTY_NpcPlayerAlias.OnPlayerLoadGame.
Function OnGameLoad()
    SetupUI()
    ; Saved while the player was deciding (the page is gone now): treated as stopped silently.
    if GetState() == "Asking"
        DuelistA.Clear()
        DuelistB.Clear()
        GoToState("")
    endif
    StorageUtil.UnsetIntValue(None, "TTY_NpcAsking")
    ; GetCurrentRealTime restarts with every game launch, so a duel saved mid-fight restarts its clock.
    startTime = Utility.GetCurrentRealTime()
    lastRekick = startTime
    disengagedSince = 0.0
    offeredAt = startTime
    if (GetState() == "Fighting" || GetState() == "Offered" || GetState() == "AskingDeath") && saHandle > 0
        ; SeverActions ends every duel a loaded save carries: this one cannot go on. Not a result.
        saHandle = 0
        saStarted = false
        EndDuel(None, None, "reloaded")
    elseif GetState() == "AskingDeath"
        ; Saved while the player decided (the page is gone now): the yield stands, silently.
        DecideDeath(2)
    elseif GetState() == "Fighting" || GetState() == "Offered"
        RegisterForSingleUpdate(TickSeconds)
    else
        ; The real-time clock restarted, so a waiting challenge can no longer lapse: drop it.
        ClearChallenge()
        GuardOff(None, None)
        ; A crash or a quit mid-duel never reaches FinishDuel.
        RestoreAllConfidence()
    endif
EndFunction

State Fighting
    Event OnUpdate()
        float now = Utility.GetCurrentRealTime()
        if toTheDeath && duelA && duelB && duelA.IsDead() != duelB.IsDead()
            if duelA.IsDead()
                EndDuel(duelB, duelA, "killed")
            else
                EndDuel(duelA, duelB, "killed")
            endif
            return
        elseif !duelA || !duelB || duelA.IsDead() || duelB.IsDead()
            EndDuel(None, None, "broken")
            return
        elseif toTheDeath && (duelA.IsBleedingOut() || duelB.IsBleedingOut())
            ; The brawl faction still drops a beaten fighter to their knees. The other may finish them;
            ; one who doesn't has spared them. Either way kneeling is not refusing to fight.
            if kneelSince == 0.0
                kneelSince = now
            elseif now - kneelSince >= SparedSeconds
                if duelA.IsBleedingOut()
                    EndDuel(duelB, duelA, "spared")
                else
                    EndDuel(duelA, duelB, "spared")
                endif
                return
            endif
            RegisterForSingleUpdate(TickSeconds)
            return
        elseif duelA.IsBleedingOut()
            EndDuel(duelB, duelA, "downed")
            return
        elseif duelB.IsBleedingOut()
            EndDuel(duelA, duelB, "downed")
            return
        elseif duelA.GetDistance(duelB) > SeparatedDistance
            EndDuel(None, None, "separated")
            return
        elseif now - startTime > MaxDuelSeconds
            EndDuel(None, None, "time")
            return
        endif
        kneelSince = 0.0

        ; Keep each on the other. A pair that stays out of it is not going to fight: call it off.
        bool aOn = duelA.IsInCombat() && duelA.GetCombatTarget() == duelB
        bool bOn = duelB.IsInCombat() && duelB.GetCombatTarget() == duelA
        ; A SeverActions fight starts when it says so: until then, hands off.
        float engageFrom = startTime
        if saHandle > 0
            engageFrom = saStartedAt
            if !saStarted
                engageFrom = now
                if now - startTime > SAStartSeconds
                    EndDuel(None, None, "would_not_fight")
                    return
                endif
            endif
        endif
        if aOn && bOn
            disengagedSince = 0.0
        elseif now - engageFrom > LeadInSeconds + 0.5
            if disengagedSince == 0.0
                disengagedSince = now
            elseif now - disengagedSince >= EngageGraceSeconds
                EndDuel(None, None, "would_not_fight")
                return
            endif
            if now - lastRekick >= RekickSeconds
                lastRekick = now
                if !aOn
                    duelA.StartCombat(duelB)
                endif
                if !bOn
                    duelB.StartCombat(duelA)
                endif
            endif
        endif
        RegisterForSingleUpdate(TickSeconds)
    EndEvent

    ; A spoken yield is an offer: the other duelist answers it (State Offered). Straight after "fight on"
    ; the same offer again is ignored.
    Function YieldNpcDuel(Actor akSpeaker)
        if Utility.GetCurrentRealTime() < yieldAgainAt
            return
        endif
        if akSpeaker && akSpeaker == duelA
            OfferNpcYield(duelB, duelA)
        elseif akSpeaker && akSpeaker == duelB
            OfferNpcYield(duelA, duelB)
        endif
    EndFunction

    Function OfferNpcYield(Actor akWinner, Actor akLoser)
        GoToState("Offered")
        UnregisterForUpdate()
        yieldWinner = akWinner
        yieldLoser = akLoser
        offeredAt = Utility.GetCurrentRealTime()
        ; The fight waits on the answer.
        StopBoth(duelA, duelB)
        StorageUtil.SetIntValue(akWinner, "TTY_NpcYieldOffer", 1)
        StorageUtil.SetStringValue(akWinner, "TTY_NpcYieldFrom", akLoser.GetDisplayName())
        if CanFightToDeath()
            StorageUtil.SetIntValue(akWinner, "TTY_NpcDeathOK", 1)
        endif
        RegisterForSingleUpdate(TickSeconds)
    EndFunction

    Function OnDuelistDown(Actor akDown)
        if toTheDeath
            return
        elseif akDown == duelA
            EndDuel(duelB, duelA, "downed")
        elseif akDown == duelB
            EndDuel(duelA, duelB, "downed")
        endif
    EndFunction

    ; Someone outside the duel hitting either duelist means it is no longer a duel.
    Function OnOutsideAttack(Actor akVictim, Actor akAttacker)
        if akAttacker && akAttacker != duelA && akAttacker != duelB
            EndDuel(None, None, "interrupted")
        endif
    EndFunction

    ; Every way a duel ends comes through here once: the state change stops a second caller.
    Function EndDuel(Actor akWinner, Actor akLoser, string asHow)
        GoToState("Ending")
        UnregisterForUpdate()
        FinishDuel(akWinner, akLoser, asHow)
    EndFunction
EndState

; A yield waits on the winner's answer. The fight is stopped meanwhile; a fall or anything that would end
; a duel still ends it, and no answer in AnswerSeconds lets the yield stand.
State Offered
    Event OnUpdate()
        float now = Utility.GetCurrentRealTime()
        if !duelA || !duelB || duelA.IsDead() || duelB.IsDead()
            EndDuel(None, None, "broken")
            return
        elseif duelA.IsBleedingOut() && !toTheDeath
            EndDuel(duelB, duelA, "downed")
            return
        elseif duelB.IsBleedingOut() && !toTheDeath
            EndDuel(duelA, duelB, "downed")
            return
        elseif duelA.GetDistance(duelB) > SeparatedDistance
            EndDuel(None, None, "separated")
            return
        elseif now - offeredAt > AnswerSeconds
            EndDuel(yieldWinner, yieldLoser, "stood")
            return
        endif
        StopBoth(duelA, duelB)
        RegisterForSingleUpdate(TickSeconds)
    EndEvent

    Function AcceptNpcYield(Actor akSpeaker)
        if akSpeaker && akSpeaker == yieldWinner
            EndDuel(yieldWinner, yieldLoser, "accepted")
        endif
    EndFunction

    Function RefuseNpcYield(Actor akSpeaker)
        if akSpeaker && akSpeaker == yieldWinner
            FightOn()
        endif
    EndFunction

    ; Asked for when it is not one of their answers (a quest keeps someone alive): fight on instead.
    Function DeathNpcDuel(Actor akSpeaker)
        if akSpeaker && akSpeaker == yieldWinner
            if CanFightToDeath()
                AskDeath()
            else
                FightOn()
            endif
        endif
    EndFunction

    Function OnDuelistDown(Actor akDown)
        if toTheDeath
            return
        elseif akDown == duelA
            EndDuel(duelB, duelA, "downed")
        elseif akDown == duelB
            EndDuel(duelA, duelB, "downed")
        endif
    EndFunction

    Function OnOutsideAttack(Actor akVictim, Actor akAttacker)
        if akAttacker && akAttacker != duelA && akAttacker != duelB
            EndDuel(None, None, "interrupted")
        endif
    EndFunction

    Function EndDuel(Actor akWinner, Actor akLoser, string asHow)
        GoToState("Ending")
        UnregisterForUpdate()
        FinishDuel(akWinner, akLoser, asHow)
    EndFunction
EndState

; The player decides on a fight to the death (the game is paused for the box or the page).
State AskingDeath
    Function OnOutsideAttack(Actor akVictim, Actor akAttacker)
        if akAttacker && akAttacker != duelA && akAttacker != duelB
            EndDuel(None, None, "interrupted")
        endif
    EndFunction

    Function EndDuel(Actor akWinner, Actor akLoser, string asHow)
        GoToState("Ending")
        UnregisterForUpdate()
        FinishDuel(akWinner, akLoser, asHow)
    EndFunction
EndState

State Ending
EndState

; Nothing differs while the player decides; the state itself keeps other duels out (CannotDuelReason).
State Asking
EndState

; ---------------------------------------------------------------------------------------------
; An offered yield and its answers
; ---------------------------------------------------------------------------------------------

; Neither was essential before the duel, and the duel is To the Yield's own: SeverActions keeps a
; same-side pair essential throughout.
bool Function CanFightToDeath()
    return aKillable && bKillable && !toTheDeath && saHandle <= 0
EndFunction

Function ClearOffer()
    if yieldWinner
        StorageUtil.UnsetIntValue(yieldWinner, "TTY_NpcYieldOffer")
        StorageUtil.UnsetStringValue(yieldWinner, "TTY_NpcYieldFrom")
        StorageUtil.UnsetIntValue(yieldWinner, "TTY_NpcDeathOK")
    endif
EndFunction

; The winner refused and makes them fight on. A fall still ends it.
Function FightOn()
    Actor w = yieldWinner
    Actor l = yieldLoser
    ClearOffer()
    if !w || !l
        EndDuel(None, None, "broken")
        return
    endif
    StorageUtil.SetIntValue(l, "TTY_NpcRefused", StorageUtil.GetIntValue(l, "TTY_NpcRefused", 0) + 1)
    string n = w.GetDisplayName()
    string m = l.GetDisplayName()
    if !toTheDeath
        StorageUtil.SetStringValue(None, "TTY_NpcStatus", m + " and " + n + " are fighting a duel with weapons and magic. " + m + " offered a yield and " + n + " refused it, so it goes on.")
    endif
    SkyrimNetApi.DirectNarration("*" + n + " won't accept " + m + "'s yield. The duel goes on.*", w, l)
    ResumeFight()
EndFunction

Function ResumeFight()
    float now = Utility.GetCurrentRealTime()
    ; The time spent on the yield is not duel time.
    startTime += now - offeredAt
    yieldAgainAt = now + YieldAgainSeconds
    SkyrimNetApi.SetActionCooldown("YieldNpcDuel", YieldAgainSeconds as int)
    disengagedSince = 0.0
    lastRekick = now
    kneelSince = 0.0
    GoToState("Fighting")
    if duelA && duelB
        duelA.StartCombat(duelB)
        duelB.StartCombat(duelA)
    endif
    RegisterForSingleUpdate(TickSeconds)
EndFunction

; The winner wants a fight to the death: the player allows it or stops it.
Function AskDeath()
    GoToState("AskingDeath")
    UnregisterForUpdate()
    if UiReady()
        uiShowing = true
        deathShowing = true
        string json = "{\"w\":\"" + JsonEscape(yieldWinner.GetDisplayName()) + "\"" \
            + ",\"l\":\"" + JsonEscape(yieldLoser.GetDisplayName()) + "\"}"
        if TTY_UI.Open(uiView, "ttyNpcDeath", json)
            return
        endif
        uiShowing = false
        deathShowing = false
    endif
    AskDeathWithBox()
EndFunction

Function AskDeathWithBox()
    if yieldWinner && yieldLoser
        ; The box can't name anyone, so the notification just before it does.
        Debug.Notification(yieldWinner.GetDisplayName() + " refuses " + yieldLoser.GetDisplayName() + "'s yield and wants a fight to the death")
    endif
    ; Buttons, in NpcDeathMsg's order: 0 Allow, 1 Stop it, 2 Stop it silently.
    DecideDeath(NpcDeathMsg.Show())
EndFunction

; 0 Allow: both lose their protection and it goes on. 1 Stop it: the player steps in and the yield
; stands. 2 Stop it silently: the yield stands, and the player is not mentioned.
Function DecideDeath(int aiChoice)
    if GetState() != "AskingDeath"
        return
    endif
    Actor w = yieldWinner
    Actor l = yieldLoser
    ClearOffer()
    if !w || !l || w.IsDead() || l.IsDead()
        EndDuel(None, None, "broken")
        return
    endif
    string n = w.GetDisplayName()
    string m = l.GetDisplayName()
    if aiChoice == 0
        toTheDeath = true
        StorageUtil.SetIntValue(None, "TTY_NpcToTheDeath", 1)
        StorageUtil.SetIntValue(l, "TTY_NpcRefused", StorageUtil.GetIntValue(l, "TTY_NpcRefused", 0) + 1)
        StorageUtil.SetStringValue(None, "TTY_NpcStatus", n + " and " + m + " are fighting to the death. " + n + " refused " + m + "'s yield.")
        SkyrimNetApi.DirectNarration("*" + n + " refuses " + m + "'s yield. The duel is to the death now.*", w, l)
        ; The aliases' essential flags are the only protection the duel added. duelA and duelB still
        ; name both, for the cleanup.
        DuelistA.Clear()
        DuelistB.Clear()
        ResumeFight()
    elseif aiChoice == 1
        SkyrimNetApi.DirectNarration("*" + Game.GetPlayer().GetDisplayName() + " steps in before it can go further. " + m + "'s yield stands, and " + n + " has won the duel.*", w, l)
        EndDuel(w, l, "stopped")
    else
        EndDuel(w, l, "stood")
    endif
EndFunction

Function FinishDuel(Actor akWinner, Actor akLoser, string asHow)
    Actor a = duelA
    Actor b = duelB
    TTY_Records.Result(a, b, akWinner, asHow)
    if saHandle > 0
        int h = saHandle
        saHandle = 0
        saStarted = false
        TTY_SABridge.End(h)
    endif
    ; 1. Stop the fight, and again after each wait below (TTY_Main found once was not enough).
    StopBoth(a, b)
    LeaveBrawl(a, b)
    GuardOff(a, b)
    StorageUtil.UnsetIntValue(None, "TTY_NpcDuelActive")
    StorageUtil.UnsetStringValue(None, "TTY_NpcStatus")
    ClearDuelistKeys(a)
    ClearDuelistKeys(b)

    ClearOffer()
    yieldWinner = None
    yieldLoser = None
    toTheDeath = false
    kneelSince = 0.0
    yieldAgainAt = 0.0
    StorageUtil.UnsetIntValue(None, "TTY_NpcToTheDeath")
    ClearRefused(a)
    ClearRefused(b)

    ; 2. Tell SkyrimNet. An accepted yield needs no narration: AcceptNpcYield.yaml's eventString
    ;    already recorded it, and the winner said it out loud. "stopped" was narrated as the player
    ;    stepped in (DecideDeath).
    SkyrimNetApi.SetActionCooldown("ChallengeDuel", CooldownSeconds)
    if asHow != "accepted" && asHow != "stopped"
        SkyrimNetApi.DirectNarration(Outcome(a, b, akWinner, akLoser, asHow), a, b)
    endif

    ; 3. Whoever went down gets enough health back to stand up.
    Utility.Wait(1.0)
    StopBoth(a, b)
    RecoverIfDown(a)
    RecoverIfDown(b)

    ; 4. Release the aliases (the protection) once both are back on their feet.
    Utility.Wait(3.0)
    StopBoth(a, b)
    int waited = 0
    while ((a && a.IsBleedingOut()) || (b && b.IsBleedingOut())) && waited < 10
        Utility.Wait(1.0)
        waited += 1
    endwhile
    ; Back to their own courage only now: put back earlier, a coward still in combat runs.
    RestoreConfidence(a)
    RestoreConfidence(b)
    DuelistA.Clear()
    DuelistB.Clear()
    duelA = None
    duelB = None
    GoToState("")
EndFunction

Function StopBoth(Actor a, Actor b)
    if a
        a.StopCombat()
    endif
    if b
        b.StopCombat()
    endif
EndFunction

Function LeaveBrawl(Actor a, Actor b)
    if a && aJoinedBrawl
        a.RemoveFromFaction(BrawlFaction)
    endif
    if b && bJoinedBrawl
        b.RemoveFromFaction(BrawlFaction)
    endif
    aJoinedBrawl = false
    bJoinedBrawl = false
EndFunction

Function ClearRefused(Actor akNpc)
    if akNpc
        StorageUtil.UnsetIntValue(akNpc, "TTY_NpcRefused")
    endif
EndFunction

Function ClearDuelistKeys(Actor akNpc)
    if akNpc
        StorageUtil.UnsetIntValue(akNpc, "TTY_NpcDuelist")
        StorageUtil.UnsetStringValue(akNpc, "TTY_NpcDuelFoe")
    endif
EndFunction

; Many civilians are Cowardly (Confidence 0) and run from any fight, a duel included: tested live
; 2026-10-25, Captain Wayfinder and Ravam Verethi both fled. Foolhardy (4) never flees. Confidence is
; saved with the game, so each original goes in the co-save.
Function Embolden(Actor akNpc)
    if akNpc && StorageUtil.FormListFind(None, "TTY_NpcBrave", akNpc) < 0
        StorageUtil.SetFloatValue(akNpc, "TTY_NpcConfidence", akNpc.GetBaseActorValue("Confidence"))
        StorageUtil.FormListAdd(None, "TTY_NpcBrave", akNpc, false)
        akNpc.SetActorValue("Confidence", 4.0)
    endif
EndFunction

Function RestoreConfidence(Actor akNpc)
    if akNpc && StorageUtil.FormListFind(None, "TTY_NpcBrave", akNpc) >= 0
        akNpc.SetActorValue("Confidence", StorageUtil.GetFloatValue(akNpc, "TTY_NpcConfidence", 0.0))
        StorageUtil.UnsetFloatValue(akNpc, "TTY_NpcConfidence")
        StorageUtil.FormListRemove(None, "TTY_NpcBrave", akNpc, true)
    endif
EndFunction

Function RestoreAllConfidence()
    int i = StorageUtil.FormListCount(None, "TTY_NpcBrave")
    while i > 0
        i -= 1
        RestoreConfidence(StorageUtil.FormListGet(None, "TTY_NpcBrave", i) as Actor)
    endwhile
    StorageUtil.FormListClear(None, "TTY_NpcBrave")
EndFunction

Function RecoverIfDown(Actor akNpc)
    if akNpc && !akNpc.IsDead() && akNpc.IsBleedingOut()
        akNpc.RestoreActorValue("Health", akNpc.GetBaseActorValue("Health") * RecoverHealthFraction)
    endif
EndFunction

; Display names go into a JSON string, so quotes and backslashes in them must be escaped.
string Function JsonEscape(string asText)
    string out = ""
    int len = StringUtil.GetLength(asText)
    int i = 0
    while i < len
        string c = StringUtil.GetNthChar(asText, i)
        if c == "\"" || c == "\\"
            out += "\\"
        endif
        out += c
        i += 1
    endwhile
    return out
EndFunction

; The narration SkyrimNet gets when the duel ends. Asterisks mark it as narration, not speech.
string Function Outcome(Actor a, Actor b, Actor akWinner, Actor akLoser, string asHow)
    string na = "one duelist"
    string nb = "the other"
    if a
        na = a.GetDisplayName()
    endif
    if b
        nb = b.GetDisplayName()
    endif
    if asHow == "downed" && akWinner && akLoser
        return "*" + akLoser.GetDisplayName() + " goes down and yields. " + akWinner.GetDisplayName() + " has won the duel.*"
    elseif asHow == "stood" && akWinner && akLoser
        return "*" + akLoser.GetDisplayName() + "'s yield stands. " + akWinner.GetDisplayName() + " has won the duel.*"
    elseif asHow == "killed" && akWinner && akLoser
        return "*" + akLoser.GetDisplayName() + " dies by " + akWinner.GetDisplayName() + "'s hand. The duel to the death is over.*"
    elseif asHow == "spared" && akWinner && akLoser
        return "*" + akLoser.GetDisplayName() + " is down, and " + akWinner.GetDisplayName() + " does not finish it. " + akWinner.GetDisplayName() + " has won the duel.*"
    elseif asHow == "time"
        return "*Neither " + na + " nor " + nb + " can finish it. The duel ends in a draw.*"
    elseif asHow == "separated"
        return "*" + na + " and " + nb + " break apart, and the duel is left unfinished.*"
    elseif asHow == "would_not_fight"
        return "*" + na + " and " + nb + " never really cross blades, and the duel is called off.*"
    elseif asHow == "interrupted"
        return "*Someone else joins the fight, and the duel between " + na + " and " + nb + " is called off.*"
    endif
    return "*The duel between " + na + " and " + nb + " is over.*"
EndFunction

; The ghost ability's switch (see BystanderGuard). Duelists are marked so they stay solid.
Function GuardOn(Actor akA, Actor akB)
    if !BystanderGuard || !DuelistFaction
        return
    endif
    if akA
        akA.AddToFaction(DuelistFaction)
    endif
    if akB
        akB.AddToFaction(DuelistFaction)
    endif
    BystanderGuard.SetValue(1)
EndFunction

Function GuardOff(Actor akA, Actor akB)
    if BystanderGuard
        BystanderGuard.SetValue(0)
    endif
    if DuelistFaction
        if akA
            akA.RemoveFromFaction(DuelistFaction)
        endif
        if akB
            akB.RemoveFromFaction(DuelistFaction)
        endif
    endif
EndFunction

; Puts everything back, from any state. Runs on first start and when the quest is restarted.
Function Reset()
    if saHandle > 0
        int h = saHandle
        saHandle = 0
        TTY_SABridge.End(h)
    endif
    saStarted = false
    UnregisterForUpdate()
    Actor a = None
    Actor b = None
    if DuelistA
        a = DuelistA.GetActorReference()
    endif
    if DuelistB
        b = DuelistB.GetActorReference()
    endif
    ; A fight to the death has already released the aliases.
    if !a
        a = duelA
    endif
    if !b
        b = duelB
    endif
    StopBoth(a, b)
    if BrawlFaction
        LeaveBrawl(a, b)
    endif
    ClearDuelistKeys(a)
    ClearDuelistKeys(b)
    ClearRefused(a)
    ClearRefused(b)
    ClearOffer()
    yieldWinner = None
    yieldLoser = None
    toTheDeath = false
    deathShowing = false
    kneelSince = 0.0
    StorageUtil.UnsetIntValue(None, "TTY_NpcToTheDeath")
    GuardOff(a, b)
    if DuelistA
        DuelistA.Clear()
    endif
    if DuelistB
        DuelistB.Clear()
    endif
    StorageUtil.UnsetIntValue(None, "TTY_NpcDuelActive")
    StorageUtil.UnsetIntValue(None, "TTY_NpcAsking")
    StorageUtil.UnsetStringValue(None, "TTY_NpcStatus")
    ClearChallenge()
    RestoreAllConfidence()
    duelA = None
    duelB = None
    GoToState("")
EndFunction
