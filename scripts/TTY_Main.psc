Scriptname TTY_Main extends Quest
{To the Yield: a formal duel with real weapons, fought until one side yields or goes down.

 Nobody dies. The opponent is put in the Opponent alias, which is flagged Essential, so at zero
 health they kneel in bleedout. The player is made essential for the duration: at zero health the
 player drops, and the opponent stops attacking (both verified by hand in game, 2026-10-23). This
 script then ends combat, gives whoever went down enough health to stand, puts every flag back the
 way it was, and tells SkyrimNet how the duel ended.

 SkyrimNet calls BeginDuel and YieldDuel (layer actions/BeginDuel.yaml and YieldDuel.yaml).

 StorageUtil keys. The layer's YAML and prompt read the same strings with papyrus_util, so rename
 one here and you must rename it there too:
     TTY_Active             int, global (None)   1 while a duel is being fought
     TTY_Opponent           int, on the NPC      1 while that NPC is the opponent
     TTY_Status             string, global       one line about the duel, for spectators' prompts
     TTY_SetPlayerEssential int, global          1 while the player is essential because of us
     TTY_RankNpc            form, global         the NPC whose relationship rank a duel lowered
     TTY_RankNpcToPlayer    int, global          that NPC's rank toward the player before the duel
     TTY_RankPlayerToNpc    int, global          the player's rank toward that NPC before the duel

 Stuck? From the console: stopquest TTY_Quest, then startquest TTY_Quest. OnInit runs again
 and Reset puts everything back. If you are still immortal after that: setessential 7 0}

ReferenceAlias Property OpponentAlias Auto
{The Opponent alias. Flagged Essential and Optional in the plugin: filling it is what protects the NPC.}

TTY_PlayerAlias Property PlayerAliasScript Auto
{The PlayerAlias, which notices outside attackers while a duel runs and calls OnGameLoad.}

Message Property ConfirmMsg Auto
{"You've been offered a duel..." with Fight / Refuse / Refuse silently. The box names nobody: an <Alias=Opponent>
 tag printed "[...]" in game even with the alias filled, so a notification names the opponent just before it.}

Faction Property BrawlFaction Auto
{Skyrim.esm DGIntimidateFaction (0x04CFA6), the faction vanilla brawls use. Only used while
 UseBrawlFaction is 1. SeverActions' brawl manager watches the same faction.}

GlobalVariable Property UseBrawlFaction Auto
{TTY_UseBrawlFaction, default 0. 1 also puts both fighters in the vanilla brawl faction, which may
 keep guards and bystanders out of it. Console: set TTY_UseBrawlFaction to 1}

GlobalVariable Property BystanderGuard Auto
{TTY_BystanderGuard: 1 while a duel is fought. TTY_BystanderGhostAbility (given to NPCs by SPID,
 ToTheYield_DISTR.ini) turns bystanders near the player ghost while it is 1, so stray blows pass
 through them. Without SPID nothing reads it.}

Faction Property DuelistFaction Auto
{TTY_DuelistFaction: the duelists, whom the ghost ability leaves alone.}

; Tuning. Times are real seconds.
float Property TickSeconds = 0.25 AutoReadOnly
float Property LeadInSeconds = 1.5 AutoReadOnly          ; "the duel begins" to the first blow
float Property MaxDuelSeconds = 180.0 AutoReadOnly       ; after this it is called a draw
float Property DrawGraceSeconds = 15.0 AutoReadOnly      ; the player has this long to draw
float Property SheatheYieldSeconds = 4.0 AutoReadOnly    ; weapon away this long = the player yields
float Property MaxStartDistance = 1500.0 AutoReadOnly    ; game units, about 21 m
float Property WalkAwayDistance = 3000.0 AutoReadOnly
float Property RecoverHealthFraction = 0.3 AutoReadOnly  ; of base health, for whoever went down
int Property CooldownSeconds = 120 AutoReadOnly          ; before BeginDuel is offered again
float Property RekickSeconds = 1.0 AutoReadOnly          ; between StartCombat retries
float Property EngageGraceSeconds = 4.0 AutoReadOnly     ; opponent out of the fight this long = called off

Actor opponent = None
bool brawlFactionUsed = false
float startTime = 0.0
float sheathedSince = 0.0
bool playerHasDrawn = false
float lastRekick = 0.0
float disengagedSince = 0.0

; States: "" (no duel), "Fighting", "Ending" (cleaning up; no new duel can start).

Event OnInit()
    Reset()
EndEvent

; ---------------------------------------------------------------------------------------------
; SkyrimNet actions
; ---------------------------------------------------------------------------------------------

; BeginDuel.yaml: the speaker and the player agreed to a duel. The player still confirms in a
; message box, because the LLM chose this action and can misread a conversation.
Function BeginDuel(Actor akSpeaker)
    ; Unfilled properties would otherwise surface as "Cannot call X() on a None object" spam.
    if !OpponentAlias || !ConfirmMsg || !PlayerAliasScript
        Debug.Trace("[TTY] TTY_Quest properties are not filled; is ToTheYield.esp enabled?", 2)
        return
    endif
    string reason = CannotDuelReason(akSpeaker)
    if reason != ""
        Debug.Notification("No duel: " + reason + ".")
        return
    endif

    Debug.Notification(akSpeaker.GetDisplayName() + " offers you a duel")
    ; Buttons, in ConfirmMsg's order: 0 Fight, 1 Refuse, 2 Refuse silently (SeverActions' convention).
    OpponentAlias.ForceRefTo(akSpeaker)
    int choice = ConfirmMsg.Show()
    if choice != 0
        OpponentAlias.Clear()
        ; Either way, the NPC cannot ask again straight away.
        SkyrimNetApi.SetActionCooldown("BeginDuel", CooldownSeconds)
        if choice == 1
            ; Narrated, so the NPC reacts to being turned down.
            Actor player = Game.GetPlayer()
            SkyrimNetApi.DirectNarration("*" + player.GetDisplayName() + " refuses to duel " + akSpeaker.GetDisplayName() + ".*", akSpeaker, player)
        else
            ; Silent: nothing recorded, nothing said.
            Debug.Trace("[TTY] Player silently refused a duel with " + akSpeaker.GetDisplayName())
        endif
        return
    endif

    ; The box paused the game, but check again in case something changed around it.
    reason = CannotDuelReason(akSpeaker)
    if reason != ""
        OpponentAlias.Clear()
        Debug.Notification("No duel: " + reason + ".")
        return
    endif
    StartFight(akSpeaker)
EndFunction

; YieldDuel.yaml: the opponent concedes in words. Only does anything while Fighting.
Function YieldDuel(Actor akSpeaker)
EndFunction

; ---------------------------------------------------------------------------------------------
; Called by the alias scripts. They do nothing outside a fight; State Fighting overrides them.
; ---------------------------------------------------------------------------------------------

Function OnOpponentDown()
EndFunction

Function OnOutsideAttack(Actor akAttacker)
EndFunction

Function EndDuel(Actor akWinner, Actor akLoser, string asHow)
EndFunction

; TTY_PlayerAlias.OnPlayerLoadGame.
Function OnGameLoad()
    ; GetCurrentRealTime restarts with every game launch, so a duel saved mid-fight restarts its clock.
    startTime = Utility.GetCurrentRealTime()
    sheathedSince = 0.0
    if GetState() == "Fighting"
        RegisterForSingleUpdate(TickSeconds)
    elseif GetState() == ""
        ; A crash or a quit mid-duel never reaches FinishDuel. Undo what it would have undone.
        RestorePlayerEssential()
        GuardOff(None, None)
        RestoreRanks()
    endif
EndFunction

; ---------------------------------------------------------------------------------------------
; The fight
; ---------------------------------------------------------------------------------------------

; Why akNpc cannot duel right now, or "" if they can.
string Function CannotDuelReason(Actor akNpc)
    Actor player = Game.GetPlayer()
    if GetState() != "" || StorageUtil.GetIntValue(None, "TTY_NpcDuelActive", 0) == 1
        ; One duel of any kind at a time (TTY_NpcDuel runs the NPC-against-NPC ones).
        return "a duel is already under way"
    elseif !akNpc || akNpc == player || akNpc.IsDead()
        return "no opponent"
    elseif akNpc.IsChild()
        return "not with a child"
    elseif IsFollower(akNpc)
        return akNpc.GetDisplayName() + " is your companion. Dismiss them first to duel"
    elseif akNpc.IsInCombat() || player.IsInCombat()
        return "someone is already fighting"
    elseif akNpc.IsOnMount() || player.IsOnMount()
        return "dismount first"
    elseif akNpc.IsHostileToActor(player)
        return akNpc.GetDisplayName() + " is hostile"
    elseif akNpc.GetDistance(player) > MaxStartDistance
        return akNpc.GetDisplayName() + " is too far away"
    endif
    return ""
EndFunction

; A current follower cannot be dueled. Tested live on a SeverActions companion, 2026-10-23: the
; follower factions keep them from fighting the player whatever their rank, and SeverActions'
; friendly-fire guard stops the fight when the brawl faction overrides that. Clearing the teammate
; flag also sets off its follower tracker. Dismissed, the same NPC duels fine.
bool Function IsFollower(Actor akNpc)
    if akNpc.IsPlayerTeammate()
        return true
    endif
    Faction currentFollower = Game.GetFormFromFile(0x0005C84E, "Skyrim.esm") as Faction
    return currentFollower && akNpc.IsInFaction(currentFollower)
EndFunction

Function StartFight(Actor akNpc)
    Actor player = Game.GetPlayer()
    opponent = akNpc
    GoToState("Fighting")

    ; Protect the player. Whether we did it is kept in the co-save, so a reload or a quest restart
    ; can always undo it (OnGameLoad, Reset), and a player who was already essential stays so.
    ActorBase playerBase = player.GetActorBase()
    if !playerBase.IsEssential()
        playerBase.SetEssential(true)
        StorageUtil.SetIntValue(None, "TTY_SetPlayerEssential", 1)
    endif

    ; Someone who likes the player drops a StartCombat against them at once. Tested live on a
    ; dismissed follower (rank 3), 2026-10-23: with both ranks set to 0 they fought every sample of
    ; two 10 s runs; at rank 3 they never did. Neutral NPCs (guards) are at 0 already.
    LowerRanks(akNpc)

    brawlFactionUsed = BrawlFaction && UseBrawlFaction && UseBrawlFaction.GetValue() > 0
    if brawlFactionUsed
        akNpc.AddToFaction(BrawlFaction)
        player.AddToFaction(BrawlFaction)
    endif

    GuardOn(akNpc, None)

    string names = akNpc.GetDisplayName() + " and " + player.GetDisplayName()
    StorageUtil.SetIntValue(None, "TTY_Active", 1)
    StorageUtil.SetIntValue(akNpc, "TTY_Opponent", 1)
    StorageUtil.SetStringValue(None, "TTY_Status", names + " are fighting a formal duel with real weapons, to the yield. Nobody is meant to die.")
    ; 'custom' rejects a plain string (SkyrimNet logs "Invalid value for field 'data'"). persistent_generic
    ; takes JSON with a "line" field, the form other mods' events pass validation with, and is kept as a memory.
    SkyrimNetApi.RegisterEvent("persistent_generic", "{\"line\":\"" + JsonEscape(names + " began a duel to the yield, with real weapons.") + "\"}", akNpc, player)

    PlayerAliasScript.WatchDuel(akNpc)
    Debug.Notification("Duel with " + akNpc.GetDisplayName() + ". Sheathe your weapon to yield.")

    startTime = Utility.GetCurrentRealTime()
    sheathedSince = 0.0
    lastRekick = startTime
    disengagedSince = 0.0
    playerHasDrawn = player.IsWeaponDrawn()
    akNpc.DrawWeapon()
    Utility.Wait(LeadInSeconds)
    ; The NPC can be deleted during the wait (a despawning leveled actor); OnUpdate then ends it.
    if GetState() == "Fighting" && akNpc
        akNpc.StartCombat(player)
        RegisterForSingleUpdate(TickSeconds)
    endif
EndFunction

State Fighting
    Event OnUpdate()
        Actor player = Game.GetPlayer()
        float now = Utility.GetCurrentRealTime()

        if !opponent || opponent.IsDead()
            EndDuel(None, None, "broken")
            return
        elseif opponent.IsBleedingOut()
            EndDuel(player, opponent, "downed")
            return
        elseif player.IsBleedingOut() || player.GetActorValue("Health") <= 1.0
            ; An essential player does not play the bleedout kneel: they drop at zero health.
            EndDuel(opponent, player, "downed")
            return
        elseif opponent.GetDistance(player) > WalkAwayDistance
            EndDuel(opponent, player, "walked_away")
            return
        elseif now - startTime > MaxDuelSeconds
            EndDuel(None, None, "time")
            return
        endif

        ; Sheathing yields, but only once the player has drawn: the duel can start with weapons away.
        if player.IsWeaponDrawn()
            playerHasDrawn = true
            sheathedSince = 0.0
        elseif playerHasDrawn
            if sheathedSince == 0.0
                sheathedSince = now
            elseif now - sheathedSince >= SheatheYieldSeconds
                EndDuel(opponent, player, "player_yielded")
                return
            endif
        elseif now - startTime > DrawGraceSeconds
            EndDuel(None, None, "never_drew")
            return
        endif

        ; The engine can drop a scripted fight, or the opponent can turn on a follower: keep it on
        ; the player, once a second (SeverActions re-issues StartCombat for the same reason). An
        ; opponent who stays out of it is not going to fight: call the duel off rather than retry for
        ; three minutes (0.2.0 did, and a follower drew and sheathed about 70 times).
        if now - startTime > LeadInSeconds + 0.5
            if opponent.IsInCombat() && opponent.GetCombatTarget() == player
                disengagedSince = 0.0
            else
                if disengagedSince == 0.0
                    disengagedSince = now
                elseif now - disengagedSince >= EngageGraceSeconds
                    EndDuel(None, None, "would_not_fight")
                    return
                endif
                if now - lastRekick >= RekickSeconds
                    lastRekick = now
                    opponent.StartCombat(player)
                endif
            endif
        endif
        KeepFollowersOut(opponent)
        RegisterForSingleUpdate(TickSeconds)
    EndEvent

    Function YieldDuel(Actor akSpeaker)
        if akSpeaker && akSpeaker == opponent
            EndDuel(Game.GetPlayer(), opponent, "conceded")
        endif
    EndFunction

    Function OnOpponentDown()
        EndDuel(Game.GetPlayer(), opponent, "downed")
    EndFunction

    ; Followers are teammates and are only kept out (KeepFollowersOut). Anyone else hitting either
    ; fighter means this is no longer a duel.
    Function OnOutsideAttack(Actor akAttacker)
        if akAttacker && akAttacker != opponent && akAttacker != Game.GetPlayer() && !akAttacker.IsPlayerTeammate()
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
    Actor player = Game.GetPlayer()
    Actor npc = opponent
    ; After an outside attack the player may still be fighting someone else: leave that alone.
    bool calmPlayer = asHow != "interrupted"

    ; 1. Stop the fight. Again after each wait below: in testing the opponent picked the player
    ;    straight back up when combat was stopped only once.
    ; npc is None if the opponent was deleted mid-duel ("broken"): every use below checks it.
    StopTheFight(npc, calmPlayer)
    GuardOff(npc, None)
    if brawlFactionUsed
        if npc
            npc.RemoveFromFaction(BrawlFaction)
        endif
        player.RemoveFromFaction(BrawlFaction)
    endif
    ; Clear the duel keys now, not after the waits below: while TTY_Opponent is set, YieldDuel is
    ; still offered, and in testing the opponent answered the outcome narration by conceding again.
    ; The alias (the NPC's protection) stays filled until step 4.
    StorageUtil.UnsetIntValue(None, "TTY_Active")
    StorageUtil.UnsetStringValue(None, "TTY_Status")
    if npc
        StorageUtil.UnsetIntValue(npc, "TTY_Opponent")
    endif
    if PlayerAliasScript
        PlayerAliasScript.StopWatching()
    endif
    SkyrimNetApi.SetActionCooldown("BeginDuel", CooldownSeconds)

    ; 2. Tell SkyrimNet. DirectNarration is stored, and one NPC (usually the opponent) responds.
    ;    A concession needs no narration: YieldDuel.yaml's eventString already recorded it, and
    ;    the opponent said it out loud.
    if asHow != "conceded"
        SkyrimNetApi.DirectNarration(Outcome(npc, akWinner, akLoser, asHow), npc, player)
    endif

    ; 3. Whoever went down gets enough health back to stand up.
    Utility.Wait(1.0)
    StopTheFight(npc, calmPlayer)
    float playerBaseHealth = player.GetBaseActorValue("Health")
    if player.GetActorValue("Health") < playerBaseHealth * 0.1
        player.RestoreActorValue("Health", playerBaseHealth * RecoverHealthFraction)
    endif
    if npc && !npc.IsDead() && npc.IsBleedingOut()
        npc.RestoreActorValue("Health", npc.GetBaseActorValue("Health") * RecoverHealthFraction)
    endif

    ; 4. Put the flags back once both are on their feet. The NPC stays essential until it has
    ;    left bleedout, so a stray blow cannot kill it on the ground.
    Utility.Wait(3.0)
    StopTheFight(npc, calmPlayer)
    RestoreRanks()
    RestorePlayerEssential()
    int waited = 0
    while npc && npc.IsBleedingOut() && waited < 10
        Utility.Wait(1.0)
        waited += 1
    endwhile
    if OpponentAlias
        OpponentAlias.Clear()
    endif
    if npc
        StorageUtil.UnsetIntValue(npc, "TTY_Opponent")
    endif
    opponent = None
    brawlFactionUsed = false
    GoToState("")
EndFunction

Function StopTheFight(Actor akNpc, bool abCalmPlayer)
    if akNpc
        akNpc.StopCombat()
        akNpc.StopCombatAlarm()
        KeepFollowersOut(akNpc)
    endif
    if abCalmPlayer
        Game.GetPlayer().StopCombatAlarm()
    endif
EndFunction

; Stops any follower who has joined in against the opponent.
Function KeepFollowersOut(Actor akNpc)
    Actor[] followers = PO3_SKSEFunctions.GetPlayerFollowers()
    ; With no followers this is None, not an empty array: test the array itself before .Length.
    if !followers
        return
    endif
    int i = followers.Length
    while i > 0
        i -= 1
        Actor follower = followers[i]
        if follower && follower != akNpc && follower.IsInCombat() && follower.GetCombatTarget() == akNpc
            follower.StopCombat()
        endif
    endwhile
EndFunction

; The narration SkyrimNet gets when a duel ends. Asterisks mark it as narration, not speech.
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

string Function Outcome(Actor akNpc, Actor akWinner, Actor akLoser, string asHow)
    string p = Game.GetPlayer().GetDisplayName()
    string n = "their opponent"
    if akNpc
        n = akNpc.GetDisplayName()
    endif
    if asHow == "downed" && akWinner && akLoser
        return "*" + akLoser.GetDisplayName() + " goes down and yields. " + akWinner.GetDisplayName() + " has won the duel.*"
    elseif asHow == "player_yielded"
        return "*" + p + " sheathes their weapon and yields. " + n + " has won the duel.*"
    elseif asHow == "walked_away"
        return "*" + p + " walks away from the duel with " + n + ", forfeiting it.*"
    elseif asHow == "time"
        return "*Neither " + p + " nor " + n + " can finish it. The duel ends in a draw.*"
    elseif asHow == "never_drew"
        return "*" + p + " never draws a weapon, and the duel with " + n + " is called off.*"
    elseif asHow == "would_not_fight"
        return "*" + n + " won't raise a weapon against " + p + ", and the duel is called off.*"
    elseif asHow == "interrupted"
        return "*Someone else joins the fight, and the duel between " + p + " and " + n + " is called off.*"
    endif
    return "*The duel between " + p + " and " + n + " is over.*"
EndFunction

Function RestorePlayerEssential()
    if StorageUtil.GetIntValue(None, "TTY_SetPlayerEssential", 0) == 1
        Game.GetPlayer().GetActorBase().SetEssential(false)
        StorageUtil.UnsetIntValue(None, "TTY_SetPlayerEssential")
    endif
EndFunction

; Relationship ranks are saved with the game, so the originals go in the co-save: a reload, a
; crash or a quest restart can always put them back (OnGameLoad, Reset), like the essential flag.
Function LowerRanks(Actor akNpc)
    Actor player = Game.GetPlayer()
    int npcToPlayer = akNpc.GetRelationshipRank(player)
    int playerToNpc = player.GetRelationshipRank(akNpc)
    if npcToPlayer <= 0 && playerToNpc <= 0
        return
    endif
    StorageUtil.SetFormValue(None, "TTY_RankNpc", akNpc)
    StorageUtil.SetIntValue(None, "TTY_RankNpcToPlayer", npcToPlayer)
    StorageUtil.SetIntValue(None, "TTY_RankPlayerToNpc", playerToNpc)
    akNpc.SetRelationshipRank(player, 0)
    player.SetRelationshipRank(akNpc, 0)
EndFunction

Function RestoreRanks()
    Actor npc = StorageUtil.GetFormValue(None, "TTY_RankNpc") as Actor
    if npc
        Actor player = Game.GetPlayer()
        npc.SetRelationshipRank(player, StorageUtil.GetIntValue(None, "TTY_RankNpcToPlayer", 0))
        player.SetRelationshipRank(npc, StorageUtil.GetIntValue(None, "TTY_RankPlayerToNpc", 0))
    endif
    StorageUtil.UnsetFormValue(None, "TTY_RankNpc")
    StorageUtil.UnsetIntValue(None, "TTY_RankNpcToPlayer")
    StorageUtil.UnsetIntValue(None, "TTY_RankPlayerToNpc")
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
    if OpponentAlias
        Actor npc = OpponentAlias.GetActorReference()
        if npc
            npc.StopCombat()
            StorageUtil.UnsetIntValue(npc, "TTY_Opponent")
            GuardOff(npc, None)
            if brawlFactionUsed
                npc.RemoveFromFaction(BrawlFaction)
            endif
        endif
        OpponentAlias.Clear()
    endif
    if brawlFactionUsed
        Game.GetPlayer().RemoveFromFaction(BrawlFaction)
    endif
    if PlayerAliasScript
        PlayerAliasScript.StopWatching()
    endif
    StorageUtil.UnsetIntValue(None, "TTY_Active")
    StorageUtil.UnsetStringValue(None, "TTY_Status")
    GuardOff(None, None)
    RestorePlayerEssential()
    RestoreRanks()
    opponent = None
    brawlFactionUsed = false
    GoToState("")
EndFunction
