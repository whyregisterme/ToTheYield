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
 shows the player NpcConfirmMsg first: Allow / Stop it / Stop it silently.

 StorageUtil keys. The layer's YAML and prompt read the same strings with papyrus_util:
     TTY_NpcDuelActive   int, global (None)   1 while an NPC duel is being fought
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

; Tuning. Times are real seconds.
float Property TickSeconds = 0.5 AutoReadOnly
float Property LeadInSeconds = 1.0 AutoReadOnly
float Property MaxDuelSeconds = 180.0 AutoReadOnly       ; after this it is called a draw
float Property MaxStartDistance = 1500.0 AutoReadOnly    ; between the duelists, about 21 m
float Property SeparatedDistance = 3000.0 AutoReadOnly
float Property RecoverHealthFraction = 0.3 AutoReadOnly
float Property RekickSeconds = 1.0 AutoReadOnly
float Property EngageGraceSeconds = 4.0 AutoReadOnly
float Property ChallengeSeconds = 60.0 AutoReadOnly       ; an unanswered challenge lapses after this
int Property CooldownSeconds = 120 AutoReadOnly          ; before ChallengeDuel is offered again

Actor duelA = None
Actor duelB = None
bool aJoinedBrawl = false
bool bJoinedBrawl = false
float startTime = 0.0
float lastRekick = 0.0
float disengagedSince = 0.0
float challengeTime = 0.0

; States: "" (no duel), "Fighting", "Ending".

Event OnInit()
    Reset()
EndEvent

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
    SkyrimNetApi.RegisterEvent("persistent_generic", "{\"line\":\"" + JsonEscape(akChallenger.GetDisplayName() + " challenged " + akTarget.GetDisplayName() + " to a duel to the yield, with real weapons.") + "\"}", akChallenger, akTarget)
    RegisterForSingleUpdate(ChallengeSeconds + 1.0)
EndFunction

; AcceptDuel.yaml: the challenged speaker says yes. The player still gets the last word.
Function AcceptDuel(Actor akAccepter)
    Actor challenger = StorageUtil.GetFormValue(None, "TTY_NpcChallenger") as Actor
    if !akAccepter || !challenger || StorageUtil.GetIntValue(akAccepter, "TTY_NpcChallenged", 0) != 1
        Debug.Trace("[TTY] AcceptDuel: no challenge is waiting on this speaker")
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

    Debug.Notification(challenger.GetDisplayName() + " and " + akAccepter.GetDisplayName() + " are about to duel")
    ; Buttons, in NpcConfirmMsg's order: 0 Allow, 1 Stop it, 2 Stop it silently.
    DuelistA.ForceRefTo(challenger)
    DuelistB.ForceRefTo(akAccepter)
    int choice = NpcConfirmMsg.Show()
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
    ; The box paused the game: check again in case something changed around it.
    reason = CannotDuelReason(challenger, akAccepter)
    if reason != ""
        DuelistA.Clear()
        DuelistB.Clear()
        Debug.Notification("No duel: " + reason + ".")
        return
    endif
    StartDuel(challenger, akAccepter)
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
    endif
EndFunction

; YieldNpcDuel.yaml: a duelist concedes in words. Only does anything while Fighting.
Function YieldNpcDuel(Actor akSpeaker)
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
    GoToState("Fighting")
    duelA = akA
    duelB = akB
    DuelistA.ForceRefTo(akA)
    DuelistB.ForceRefTo(akB)

    aJoinedBrawl = !akA.IsInFaction(BrawlFaction)
    if aJoinedBrawl
        akA.AddToFaction(BrawlFaction)
    endif
    bJoinedBrawl = !akB.IsInFaction(BrawlFaction)
    if bJoinedBrawl
        akB.AddToFaction(BrawlFaction)
    endif

    GuardOn(akA, akB)
    Embolden(akA)
    Embolden(akB)

    string a = akA.GetDisplayName()
    string b = akB.GetDisplayName()
    StorageUtil.SetIntValue(None, "TTY_NpcDuelActive", 1)
    StorageUtil.SetStringValue(None, "TTY_NpcStatus", a + " and " + b + " are fighting a formal duel with real weapons, to the yield. Nobody is meant to die.")
    StorageUtil.SetIntValue(akA, "TTY_NpcDuelist", 1)
    StorageUtil.SetIntValue(akB, "TTY_NpcDuelist", 1)
    StorageUtil.SetStringValue(akA, "TTY_NpcDuelFoe", b)
    StorageUtil.SetStringValue(akB, "TTY_NpcDuelFoe", a)
    SkyrimNetApi.RegisterEvent("persistent_generic", "{\"line\":\"" + JsonEscape(a + " and " + b + " began a duel to the yield, with real weapons.") + "\"}", akA, akB)

    startTime = Utility.GetCurrentRealTime()
    lastRekick = startTime
    disengagedSince = 0.0
    akA.DrawWeapon()
    akB.DrawWeapon()
    Utility.Wait(LeadInSeconds)
    ; Either can be deleted during the wait; OnUpdate then ends it.
    if GetState() == "Fighting" && akA && akB
        akA.StartCombat(akB)
        akB.StartCombat(akA)
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
    elseif !akA || !akB || akA == akB || akA == player || akB == player
        return "needs two NPCs"
    elseif akA.IsDead() || akB.IsDead()
        return "a duelist is dead"
    elseif akA.IsChild() || akB.IsChild()
        return "not with a child"
    elseif akA.IsInCombat() || akB.IsInCombat()
        return "someone is already fighting"
    elseif akA.GetFactionReaction(akB) >= 2
        ; Ally or friend: the same group. They will not fight (tested).
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
    ; GetCurrentRealTime restarts with every game launch, so a duel saved mid-fight restarts its clock.
    startTime = Utility.GetCurrentRealTime()
    lastRekick = startTime
    disengagedSince = 0.0
    if GetState() == "Fighting"
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
        if !duelA || !duelB || duelA.IsDead() || duelB.IsDead()
            EndDuel(None, None, "broken")
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

        ; Keep each on the other. A pair that stays out of it is not going to fight: call it off.
        bool aOn = duelA.IsInCombat() && duelA.GetCombatTarget() == duelB
        bool bOn = duelB.IsInCombat() && duelB.GetCombatTarget() == duelA
        if aOn && bOn
            disengagedSince = 0.0
        elseif now - startTime > LeadInSeconds + 0.5
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

    Function YieldNpcDuel(Actor akSpeaker)
        if akSpeaker && akSpeaker == duelA
            EndDuel(duelB, duelA, "conceded")
        elseif akSpeaker && akSpeaker == duelB
            EndDuel(duelA, duelB, "conceded")
        endif
    EndFunction

    Function OnDuelistDown(Actor akDown)
        if akDown == duelA
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

State Ending
EndState

Function FinishDuel(Actor akWinner, Actor akLoser, string asHow)
    Actor a = duelA
    Actor b = duelB
    ; 1. Stop the fight, and again after each wait below (TTY_Main found once was not enough).
    StopBoth(a, b)
    LeaveBrawl(a, b)
    GuardOff(a, b)
    StorageUtil.UnsetIntValue(None, "TTY_NpcDuelActive")
    StorageUtil.UnsetStringValue(None, "TTY_NpcStatus")
    ClearDuelistKeys(a)
    ClearDuelistKeys(b)

    ; 2. Tell SkyrimNet. A concession needs no narration: YieldNpcDuel.yaml's eventString already
    ;    recorded it, and the duelist said it out loud.
    SkyrimNetApi.SetActionCooldown("ChallengeDuel", CooldownSeconds)
    if asHow != "conceded"
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
    UnregisterForUpdate()
    Actor a = None
    Actor b = None
    if DuelistA
        a = DuelistA.GetActorReference()
    endif
    if DuelistB
        b = DuelistB.GetActorReference()
    endif
    StopBoth(a, b)
    if BrawlFaction
        LeaveBrawl(a, b)
    endif
    ClearDuelistKeys(a)
    ClearDuelistKeys(b)
    GuardOff(a, b)
    if DuelistA
        DuelistA.Clear()
    endif
    if DuelistB
        DuelistB.Clear()
    endif
    StorageUtil.UnsetIntValue(None, "TTY_NpcDuelActive")
    StorageUtil.UnsetStringValue(None, "TTY_NpcStatus")
    ClearChallenge()
    RestoreAllConfidence()
    duelA = None
    duelB = None
    GoToState("")
EndFunction
