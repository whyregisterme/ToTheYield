Scriptname SNDuel_Main extends Quest
{SkyrimNet Duels: a formal duel with real weapons, fought until one side yields or goes down.

 Nobody dies. The opponent is put in the Opponent alias, which is flagged Essential, so at zero
 health they kneel in bleedout. The player is made essential for the duration: at zero health the
 player drops, and the opponent stops attacking (both verified by hand in game, 2026-10-23). This
 script then ends combat, gives whoever went down enough health to stand, puts every flag back the
 way it was, and tells SkyrimNet how the duel ended.

 SkyrimNet calls BeginDuel and YieldDuel (layer actions/BeginDuel.yaml and YieldDuel.yaml).

 StorageUtil keys. The layer's YAML and prompt read the same strings with papyrus_util, so rename
 one here and you must rename it there too:
     SNDuel_Active             int, global (None)   1 while a duel is being fought
     SNDuel_Opponent           int, on the NPC      1 while that NPC is the opponent
     SNDuel_Status             string, global       one line about the duel, for spectators' prompts
     SNDuel_SetPlayerEssential int, global          1 while the player is essential because of us

 Stuck? From the console: stopquest SNDuel_Quest, then startquest SNDuel_Quest. OnInit runs again
 and Reset puts everything back. If you are still immortal after that: setessential 7 0}

ReferenceAlias Property OpponentAlias Auto
{The Opponent alias. Flagged Essential and Optional in the plugin: filling it is what protects the NPC.}

SNDuel_PlayerAlias Property PlayerAliasScript Auto
{The PlayerAlias, which notices outside attackers while a duel runs and calls OnGameLoad.}

Message Property ConfirmMsg Auto
{"<Alias=Opponent> offers you a duel..." with Fight / Refuse / Refuse silently. Owned by this quest, which is what
 lets the <Alias=Opponent> tag resolve to the NPC's name.}

Faction Property BrawlFaction Auto
{Skyrim.esm DGIntimidateFaction (0x04CFA6). Only used while UseBrawlFaction is 1.}

GlobalVariable Property UseBrawlFaction Auto
{SNDuel_UseBrawlFaction, default 0. A test lever: 1 also puts both fighters in the vanilla brawl
 faction, which may keep guards and bystanders out of it. Off by default because SeverActions'
 brawls use the same faction. Console: set SNDuel_UseBrawlFaction to 1}

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

Actor opponent = None
bool opponentWasTeammate = false
bool brawlFactionUsed = false
float startTime = 0.0
float sheathedSince = 0.0
bool playerHasDrawn = false

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
        Debug.Trace("[SNDuel] SNDuel_Quest properties are not filled; is SkyrimNetDuels.esp enabled?", 2)
        return
    endif
    string reason = CannotDuelReason(akSpeaker)
    if reason != ""
        Debug.Notification("No duel: " + reason + ".")
        return
    endif

    ; Fill the alias before the box: the box names the opponent through <Alias=Opponent>.
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
            Debug.Trace("[SNDuel] Player silently refused a duel with " + akSpeaker.GetDisplayName())
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

; SNDuel_PlayerAlias.OnPlayerLoadGame.
Function OnGameLoad()
    ; GetCurrentRealTime restarts with every game launch, so a duel saved mid-fight restarts its clock.
    startTime = Utility.GetCurrentRealTime()
    sheathedSince = 0.0
    if GetState() == "Fighting"
        RegisterForSingleUpdate(TickSeconds)
    elseif GetState() == ""
        ; A crash or a quit mid-duel never reaches FinishDuel. Undo what it would have undone.
        RestorePlayerEssential()
    endif
EndFunction

; ---------------------------------------------------------------------------------------------
; The fight
; ---------------------------------------------------------------------------------------------

; Why akNpc cannot duel right now, or "" if they can.
string Function CannotDuelReason(Actor akNpc)
    Actor player = Game.GetPlayer()
    if GetState() != ""
        return "a duel is already under way"
    elseif !akNpc || akNpc == player || akNpc.IsDead()
        return "no opponent"
    elseif akNpc.IsChild()
        return "not with a child"
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

Function StartFight(Actor akNpc)
    Actor player = Game.GetPlayer()
    opponent = akNpc
    GoToState("Fighting")

    ; Protect the player. Whether we did it is kept in the co-save, so a reload or a quest restart
    ; can always undo it (OnGameLoad, Reset), and a player who was already essential stays so.
    ActorBase playerBase = player.GetActorBase()
    if !playerBase.IsEssential()
        playerBase.SetEssential(true)
        StorageUtil.SetIntValue(None, "SNDuel_SetPlayerEssential", 1)
    endif

    ; A follower will not fight the player while flagged a teammate.
    opponentWasTeammate = akNpc.IsPlayerTeammate()
    if opponentWasTeammate
        akNpc.SetPlayerTeammate(false)
    endif

    brawlFactionUsed = UseBrawlFaction && UseBrawlFaction.GetValue() > 0
    if brawlFactionUsed
        akNpc.AddToFaction(BrawlFaction)
        player.AddToFaction(BrawlFaction)
    endif

    string names = akNpc.GetDisplayName() + " and " + player.GetDisplayName()
    StorageUtil.SetIntValue(None, "SNDuel_Active", 1)
    StorageUtil.SetIntValue(akNpc, "SNDuel_Opponent", 1)
    StorageUtil.SetStringValue(None, "SNDuel_Status", names + " are fighting a formal duel with real weapons, to the yield. Nobody is meant to die.")
    ; 'custom' rejects a plain string (SkyrimNet logs "Invalid value for field 'data'"). persistent_generic
    ; takes JSON with a "line" field, the form other mods' events pass validation with, and is kept as a memory.
    SkyrimNetApi.RegisterEvent("persistent_generic", "{\"line\":\"" + JsonEscape(names + " began a duel to the yield, with real weapons.") + "\"}", akNpc, player)

    PlayerAliasScript.WatchDuel(akNpc)
    Debug.Notification("Duel with " + akNpc.GetDisplayName() + ". Sheathe your weapon to yield.")

    startTime = Utility.GetCurrentRealTime()
    sheathedSince = 0.0
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
        ; the player. (SeverActions re-issues StartCombat for the same reason.)
        if now - startTime > LeadInSeconds + 2.0
            if !opponent.IsInCombat() || opponent.GetCombatTarget() != player
                opponent.StartCombat(player)
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
    if brawlFactionUsed
        if npc
            npc.RemoveFromFaction(BrawlFaction)
        endif
        player.RemoveFromFaction(BrawlFaction)
    endif
    ; Clear the duel keys now, not after the waits below: while SNDuel_Opponent is set, YieldDuel is
    ; still offered, and in testing the opponent answered the outcome narration by conceding again.
    ; The alias (the NPC's protection) stays filled until step 4.
    StorageUtil.UnsetIntValue(None, "SNDuel_Active")
    StorageUtil.UnsetStringValue(None, "SNDuel_Status")
    if npc
        StorageUtil.UnsetIntValue(npc, "SNDuel_Opponent")
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
    if opponentWasTeammate && npc && !npc.IsDead()
        npc.SetPlayerTeammate(true)
    endif
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
        StorageUtil.UnsetIntValue(npc, "SNDuel_Opponent")
    endif
    opponent = None
    opponentWasTeammate = false
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
    elseif asHow == "interrupted"
        return "*Someone else joins the fight, and the duel between " + p + " and " + n + " is called off.*"
    endif
    return "*The duel between " + p + " and " + n + " is over.*"
EndFunction

Function RestorePlayerEssential()
    if StorageUtil.GetIntValue(None, "SNDuel_SetPlayerEssential", 0) == 1
        Game.GetPlayer().GetActorBase().SetEssential(false)
        StorageUtil.UnsetIntValue(None, "SNDuel_SetPlayerEssential")
    endif
EndFunction

; Puts everything back, from any state. Runs on first start and when the quest is restarted.
Function Reset()
    UnregisterForUpdate()
    if OpponentAlias
        Actor npc = OpponentAlias.GetActorReference()
        if npc
            npc.StopCombat()
            StorageUtil.UnsetIntValue(npc, "SNDuel_Opponent")
            if opponentWasTeammate
                npc.SetPlayerTeammate(true)
            endif
        endif
        OpponentAlias.Clear()
    endif
    if PlayerAliasScript
        PlayerAliasScript.StopWatching()
    endif
    StorageUtil.UnsetIntValue(None, "SNDuel_Active")
    StorageUtil.UnsetStringValue(None, "SNDuel_Status")
    RestorePlayerEssential()
    opponent = None
    opponentWasTeammate = false
    brawlFactionUsed = false
    GoToState("")
EndFunction
