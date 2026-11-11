Scriptname TTY_Main extends Quest
{To the Yield: a formal duel with weapons and magic, fought until one side yields or goes down.

 Nobody dies. The opponent is put in the Opponent alias, which is flagged Essential, so at zero
 health they kneel in bleedout. The player is made essential for the duration: at zero health the
 player drops, and the opponent stops attacking (both verified by hand in game, 2026-10-23). This
 script then ends combat, gives whoever went down enough health to stand, puts every flag back the
 way it was, and tells SkyrimNet how the duel ended.

 When the opponent yields (goes down, or concedes in words) the player answers: accept, keep fighting
 (they get up and it goes on), or fight to the death. Only that last one lets anybody die: it clears the
 alias and the player's flag, and is never offered for an NPC who was essential before the duel.

 SkyrimNet calls BeginDuel and YieldDuel (layer actions/BeginDuel.yaml and YieldDuel.yaml).
 The player confirms the duel on a Magelight UI page when Magelight is installed (TTY_UI), else in
 ConfirmMsg; set TTY_UseMagelight to 0 for the box always.

 StorageUtil keys. The layer's YAML and prompt read the same strings with papyrus_util, so rename
 one here and you must rename it there too:
     TTY_Active             int, global (None)   1 while a duel is being fought
     TTY_Asking             int, global          1 while the player's duel offer waits for an answer
     TTY_Opponent           int, on the NPC      1 while that NPC is the opponent
     TTY_Status             string, global       one line about the duel, for spectators' prompts
     TTY_SetPlayerEssential int, global          1 while the player is essential because of us
     TTY_RankNpc            form, global         the NPC whose relationship rank a duel lowered
     TTY_RankNpcToPlayer    int, global          that NPC's rank toward the player before the duel
     TTY_RankPlayerToNpc    int, global          the player's rank toward that NPC before the duel
     TTY_BraveNpc           form, global         the NPC whose Confidence a duel raised
     TTY_NpcConfidence      float, global        that NPC's base Confidence before the duel
     TTY_YieldRefused       int, global          how many of the opponent's offered yields the player refused
     TTY_ToTheDeath         int, global          1 once the player made it a duel to the death
     TTY_LawlessNpc         form, global         the NPC a sanctioned duel to the death took out of their crime faction
     TTY_NpcCrimeFaction    form, global         that crime faction

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
{TTY_UseBrawlFaction, default 1: both fighters join the vanilla brawl faction, which keeps the
 opponent's friends out of it. At 0 (as shipped up to 0.3.1) fellow guards piled on the player; tested
 live 2026-10-26, two of the opponent's fellow guards stayed out and sword hits kept full damage.
 Console: set TTY_UseBrawlFaction to 0 to turn it off.}

GlobalVariable Property BystanderGuard Auto
{TTY_BystanderGuard: 1 while a duel is fought. TTY_BystanderGhostAbility (given to NPCs by SPID,
 ToTheYield_DISTR.ini) turns bystanders near the player ghost while it is 1, so stray blows pass
 through them. Without SPID nothing reads it.}

Faction Property DuelistFaction Auto
{TTY_DuelistFaction: the duelists, whom the ghost ability leaves alone.}

Spell Property RecordPower Auto
{TTY_RecordPower, the Duel Record lesser power. Given to the player on every load (SetupUI).}

GlobalVariable Property UseMagelight Auto
{TTY_UseMagelight, default 1. 0 = always the message box, even with Magelight UI installed. Console:
 set TTY_UseMagelight to 0. Turning it back on takes effect at the next load.}

Message Property YieldMsg Auto
{"Your opponent yields." with I accept your yield / Keep fighting / Until one of us is dead.}

Message Property YieldMercyMsg Auto
{YieldMsg without the duel to the death, for an opponent who can't be killed or one already in it:
 I accept your yield / Keep fighting.}

Message Property DeathConfirmMsg Auto
{"A duel to the death..." with Back / To the death. Back comes first, so Enter is the safe answer.}

GlobalVariable Property SanctionedDeath Auto
{TTY_SanctionedDeath, default 0: killing an opponent in a duel to the death is murder (tested live
 2026-11-10: a Dawnstar guard's death cost 1000 bounty; the brawl faction covers blows, not a kill). At 1
 the opponent leaves their crime faction for the rest of the duel, so no hold's law counts the kill.
 Console: set TTY_SanctionedDeath to 1.}

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
float Property SAStartSeconds = 15.0 AutoReadOnly        ; SeverActions' companion duel must start within this
float Property YieldAgainSeconds = 15.0 AutoReadOnly     ; after a refused yield, before a spoken one counts again
int Property StandUpSeconds = 30 AutoReadOnly            ; a refused opponent has this long to get back up

Actor opponent = None
bool brawlFactionUsed = false
float startTime = 0.0
float sheathedSince = 0.0
bool playerHasDrawn = false
float lastRekick = 0.0
float disengagedSince = 0.0
float playerStartX = 0.0   ; where each stood when the duel started, to tell who walked away
float playerStartY = 0.0
float npcStartX = 0.0
float npcStartY = 0.0
int uiView = 0             ; the Magelight page this session, 0 = message boxes
int saHandle = 0           ; SeverActions' duel (a companion duel, TTY_SA), 0 = To the Yield's own
bool saStarted = false     ; SeverActions has freed the companion and started the fight
float saStartedAt = 0.0
bool uiShowing = false     ; the offer, or the record, is up on the page
bool recordShowing = false ; it is the record (the Duel Record power), not an offer
bool yieldShowing = false  ; it is the opponent's yield, waiting on the player's answer
bool npcKillable = false   ; the opponent was not essential before the duel made them so
bool toTheDeath = false    ; the player refused a yield and chose a duel to the death
string yieldHow = ""       ; "downed" or "conceded": how the opponent yielded
bool yieldPending = false  ; the yield is still waiting on the player's answer
float yieldAt = 0.0        ; when, so the time spent answering is not duel time
float yieldAgainAt = 0.0   ; before this, a spoken yield is the refused one again and is ignored

; States: "" (no duel), "Asking" (the offer is up), "Fighting", "Yielding" (the opponent yielded and the
; player is answering, or the opponent is getting back up), "Ending" (cleaning up; no new duel can start).

Event OnInit()
    Reset()
    SetupUI()
EndEvent

; Magelight forgets mods, views and listeners between sessions, and mod event registrations last one
; load, so this runs on every load.
Function SetupUI()
    uiView = 0
    uiShowing = false
    recordShowing = false
    yieldShowing = false
    ; The Duel Record power works with or without Magelight (a message box then).
    Actor player = Game.GetPlayer()
    if RecordPower && !player.HasSpell(RecordPower)
        player.AddSpell(RecordPower, false)
    endif
    ; SeverActions' Duel API, for companions (TTY_SA). Events last one load, like Magelight's.
    TTY_SA.Refresh()
    RegisterForModEvent("SeverActions_DuelStarted", "OnSADuelStarted")
    RegisterForModEvent("SeverActions_DuelEnded", "OnSADuelEnded")
    if !UseMagelight || UseMagelight.GetValue() <= 0
        return
    endif
    uiView = TTY_UI.Setup("ttyDuelChoice")
    if uiView
        RegisterForModEvent("Magelight_JS_ttyDuelChoice", "OnUiChoice")
        RegisterForModEvent("Magelight_UIModeExited", "OnUiExited")
        RegisterForModEvent("Magelight_ViewLoadFailed", "OnUiFailed")
    endif
EndFunction

bool Function UiReady()
    return uiView != 0 && !uiShowing && UseMagelight && UseMagelight.GetValue() > 0
EndFunction

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

    ; Before the alias makes them essential: an NPC a quest keeps alive stays out of a duel to the death.
    npcKillable = !akSpeaker.IsEssential()
    if !npcKillable
        ; Seen live 2026-11-10: a generic Nord (base not essential, in no alias afterwards) was essential
        ; here. Name whatever holds them, so the log can say which mod protects them.
        string held = ""
        Alias[] aliases = PO3_SKSEFunctions.GetRefAliases(akSpeaker)
        int i = 0
        while aliases && i < aliases.Length
            if aliases[i]
                held += " " + PO3_SKSEFunctions.GetFormEditorID(aliases[i].GetOwningQuest()) + "." + aliases[i].GetName()
            endif
            i += 1
        endwhile
        Debug.Trace("[TTY] " + akSpeaker.GetDisplayName() + " is essential before the duel (base " \
            + akSpeaker.GetActorBase().IsEssential() + ", aliases:" + held + "): no duel to the death")
    endif
    OpponentAlias.ForceRefTo(akSpeaker)
    ; Asking holds off any other duel until the player answers, which on the page comes later (OnUiChoice).
    GoToState("Asking")
    StorageUtil.SetIntValue(None, "TTY_Asking", 1)
    if UiReady()
        uiShowing = true
        string json = "{\"name\":\"" + JsonEscape(akSpeaker.GetDisplayName()) + "\"" \
            + ",\"rec\":\"" + JsonEscape(TTY_Records.VsPlayerLine(akSpeaker)) + "\"}"
        if TTY_UI.Open(uiView, "ttyOffer", json)
            return
        endif
        uiShowing = false
    endif
    AskWithBox()
EndFunction

Function AskWithBox()
    Actor npc = OpponentAlias.GetActorReference()
    if npc
        ; The box can't name anyone, so the notification just before it does.
        Debug.Notification(npc.GetDisplayName() + " offers you a duel")
    endif
    ; Buttons, in ConfirmMsg's order: 0 Fight, 1 Refuse, 2 Refuse silently (SeverActions' convention).
    Decide(ConfirmMsg.Show())
EndFunction

; The player's answer, from the box or the page: 0 Fight, 1 Refuse, 2 Refuse silently.
Function Decide(int aiChoice)
    if GetState() != "Asking"
        return
    endif
    GoToState("")
    StorageUtil.UnsetIntValue(None, "TTY_Asking")
    Actor akSpeaker = OpponentAlias.GetActorReference()
    if !akSpeaker
        return
    endif
    if aiChoice != 0
        OpponentAlias.Clear()
        ; Either way, the NPC cannot ask again straight away.
        SkyrimNetApi.SetActionCooldown("BeginDuel", CooldownSeconds)
        if aiChoice == 1
            ; Narrated, so the NPC reacts to being turned down.
            Actor player = Game.GetPlayer()
            SkyrimNetApi.DirectNarration("*" + player.GetDisplayName() + " refuses to duel " + akSpeaker.GetDisplayName() + ".*", akSpeaker, player)
            TTY_Records.Refusal(akSpeaker, player)
        else
            ; Silent: nothing recorded, nothing said.
            Debug.Trace("[TTY] Player silently refused a duel with " + akSpeaker.GetDisplayName())
        endif
        return
    endif

    ; The game was paused while the player chose, but check again in case something changed around it.
    string reason = CannotDuelReason(akSpeaker)
    if reason != ""
        OpponentAlias.Clear()
        Debug.Notification("No duel: " + reason + ".")
        return
    endif
    saHandle = 0
    saStarted = false
    if IsFollower(akSpeaker) && TTY_SA.Available()
        ; A companion: SeverActions frees them to fight and keeps its guards off the pair. It must
        ; free them before anyone starts the fight, so StartFight leaves that to it.
        saHandle = TTY_SABridge.Begin(Game.GetPlayer(), akSpeaker, MaxDuelSeconds + 60.0)
        if saHandle <= 0
            saHandle = 0
            OpponentAlias.Clear()
            Debug.Notification("No duel: SeverActions couldn't start it.")
            return
        endif
    endif
    StartFight(akSpeaker)
EndFunction

; ---------------------------------------------------------------------------------------------
; Magelight page events. Every mod, and TTY_NpcDuel, hears every Magelight event: each checks the view
; and whether this script's card is the one up. Functions, not Events: Caprica refuses new event names
; on a non-native script, and in a Skyrim .pex an event is only a function; SKSE calls it by name.
; ---------------------------------------------------------------------------------------------

; The offer's buttons: "fight", "refuse", "quiet". The yield's: "accept", "keep", "death" (the page asks
; "to the death?" itself and only sends "death" once the player confirms).
Function OnUiChoice(string asEventName, string asChoice, float afView, Form akSender)
    if uiView == 0 || afView as int != uiView || !uiShowing
        return
    endif
    uiShowing = false
    TTY_UI.Close(uiView)
    if recordShowing
        ; The record card's only button is Close.
        recordShowing = false
        return
    endif
    if yieldShowing
        yieldShowing = false
        if asChoice == "keep"
            AnswerYield(1)
        elseif asChoice == "death"
            ConfirmDeath(true)
        else
            AnswerYield(0)
        endif
        return
    endif
    if asChoice == "fight"
        Decide(0)
    elseif asChoice == "refuse"
        Decide(1)
    else
        Decide(2)
    endif
EndFunction

; Escape or the host's toggle key closed the page: the offer is refused silently.
; TTY_UI.Close raises this too, after uiShowing is already cleared, so that one is ignored.
Function OnUiExited(string asEventName, string asModId, float afView, Form akSender)
    if uiView == 0 || afView as int != uiView || !uiShowing
        return
    endif
    uiShowing = false
    TTY_UI.Close(uiView)
    if recordShowing
        recordShowing = false
        return
    endif
    if yieldShowing
        ; The yield is accepted: the one answer that can't hurt anyone.
        yieldShowing = false
        AnswerYield(0)
        return
    endif
    Decide(2)
EndFunction

; The page couldn't load: the box for the rest of the session, and for the offer if one was up.
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
        if recordShowing
            recordShowing = false
            Debug.MessageBox(TTY_Records.PlayerText())
        elseif yieldShowing
            yieldShowing = false
            AskYieldWithBox()
        elseif GetState() == "Asking"
            AskWithBox()
        endif
    endif
EndFunction

; SeverActions_DuelStarted / _DuelEnded (DUEL_API.md). Functions, not Events, as for Magelight. Only
; the handle tells duels apart: every mod's duels send these.
Function OnSADuelStarted(string asEventName, string asWhy, float afHandle, Form akSender)
    if saHandle > 0 && afHandle as int == saHandle
        saStarted = true
        saStartedAt = Utility.GetCurrentRealTime()
        Actor npc = opponent
        if npc
            npc.StartCombat(Game.GetPlayer())
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

; TTY_RecordPowerEffect: the Duel Record power. Not mid-duel or while a duel offer is up.
Function ShowRecord()
    if GetState() != "" || StorageUtil.GetIntValue(None, "TTY_NpcAsking", 0) == 1
        Debug.Notification("Your duel record can wait until this is settled.")
        return
    endif
    if UiReady()
        uiShowing = true
        recordShowing = true
        if TTY_UI.Open(uiView, "ttyRecord", TTY_Records.PlayerJson())
            return
        endif
        uiShowing = false
        recordShowing = false
    endif
    Debug.MessageBox(TTY_Records.PlayerText())
EndFunction

; YieldDuel.yaml: the opponent concedes in words. Only does anything while Fighting.
Function YieldDuel(Actor akSpeaker)
EndFunction

; ---------------------------------------------------------------------------------------------
; Called by the alias scripts. They do nothing outside a fight; State Fighting overrides them.
; ---------------------------------------------------------------------------------------------

Function OnOpponentDown()
EndFunction

Function OfferYield(string asHow)
EndFunction

Function OnOutsideAttack(Actor akAttacker)
EndFunction

Function EndDuel(Actor akWinner, Actor akLoser, string asHow)
EndFunction

; TTY_PlayerAlias.OnPlayerLoadGame.
Function OnGameLoad()
    SetupUI()
    ; Saved with an offer up (the page is gone now): the offer lapses, as if refused silently.
    if GetState() == "Asking"
        OpponentAlias.Clear()
        GoToState("")
    endif
    StorageUtil.UnsetIntValue(None, "TTY_Asking")
    ; GetCurrentRealTime restarts with every game launch, so a duel saved mid-fight restarts its clock.
    startTime = Utility.GetCurrentRealTime()
    yieldAt = startTime
    sheathedSince = 0.0
    if GetState() == "Yielding" && saHandle > 0
        saHandle = 0
        saStarted = false
        EndDuel(None, None, "reloaded")
    elseif GetState() == "Yielding" && yieldPending
        ; Saved with the yield unanswered: ask again. (Saved while they were getting up, RefuseYield's
        ; wait carries on by itself.)
        ShowYield()
    elseif GetState() == "Fighting" && saHandle > 0
        ; SeverActions ends every duel a loaded save carries, and the companion is back with their
        ; framework: this one cannot go on. Not a result.
        saHandle = 0
        saStarted = false
        EndDuel(None, None, "reloaded")
    elseif GetState() == "Fighting"
        RegisterForSingleUpdate(TickSeconds)
    elseif GetState() == ""
        ; A crash or a quit mid-duel never reaches FinishDuel. Undo what it would have undone.
        RestorePlayerEssential()
        GuardOff(None, None)
        RestoreRanks()
        RestoreConfidence()
        RestoreCrimeFaction()
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
    elseif StorageUtil.GetIntValue(None, "TTY_NpcAsking", 0) == 1
        return "another duel is waiting on your answer"
    elseif !akNpc || akNpc == player || akNpc.IsDead()
        return "no opponent"
    elseif akNpc.IsChild()
        return "not with a child"
    elseif IsFollower(akNpc) && !TTY_SA.Available()
        ; With SeverActions' Duel API a companion can duel (Decide); without it they won't fight you.
        return akNpc.GetDisplayName() + " is your companion. Dismiss them first to duel"
    elseif akNpc.IsInCombat() || player.IsInCombat()
        return "someone is already fighting"
    elseif akNpc.IsOnMount() || player.IsOnMount()
        return "dismount first"
    elseif akNpc.IsHostileToActor(player)
        return akNpc.GetDisplayName() + " is hostile"
    elseif Elsewhere(akNpc)
        return akNpc.GetDisplayName() + " has gone elsewhere"
    elseif akNpc.GetDistance(player) > MaxStartDistance
        return akNpc.GetDisplayName() + " is too far away"
    endif
    return ""
EndFunction

; akNpc has gone where the duel can't follow: unloaded, or through a door into another interior or
; out of one. Two exterior cells side by side are the same open ground, so distance decides those.
bool Function Elsewhere(Actor akNpc)
    Actor player = Game.GetPlayer()
    if !akNpc.Is3DLoaded()
        return true
    endif
    Cell a = akNpc.GetParentCell()
    Cell b = player.GetParentCell()
    if !a || !b
        return true
    endif
    return a != b && (a.IsInterior() || b.IsInterior())
EndFunction

; How far akActor has moved (on the ground plane) from (afX, afY).
float Function Strayed(Actor akActor, float afX, float afY)
    float dx = akActor.GetPositionX() - afX
    float dy = akActor.GetPositionY() - afY
    return Math.Sqrt(dx * dx + dy * dy)
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
    playerStartX = player.GetPositionX()
    playerStartY = player.GetPositionY()
    npcStartX = akNpc.GetPositionX()
    npcStartY = akNpc.GetPositionY()

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
    ; With SeverActions (a companion), it frees them, sets their courage and adds the brawl faction
    ; itself, and restores only what it changed: doing it here too would undo the wrong values.
    ; Tested live 2026-10-27: a companion at rank 3 fought once SeverActions freed her.
    bool sa = saHandle > 0
    if !sa
        LowerRanks(akNpc)
        Embolden(akNpc)
    endif

    brawlFactionUsed = !sa && BrawlFaction && UseBrawlFaction && UseBrawlFaction.GetValue() > 0
    if brawlFactionUsed
        akNpc.AddToFaction(BrawlFaction)
        player.AddToFaction(BrawlFaction)
    endif

    GuardOn(akNpc, None)

    string names = akNpc.GetDisplayName() + " and " + player.GetDisplayName()
    toTheDeath = false
    yieldPending = false
    yieldAgainAt = 0.0
    StorageUtil.SetIntValue(None, "TTY_Active", 1)
    StorageUtil.SetIntValue(akNpc, "TTY_Opponent", 1)
    ; Facts, not values: "formal", "nobody is meant to die" and the like had NPCs judge whatever the
    ; duel turned into (seen live 2026-11-10). What the fight means is left to their own profiles.
    StorageUtil.SetStringValue(None, "TTY_Status", names + " are fighting a duel with weapons and magic, until someone goes down, or offers a yield and the other accepts it.")
    StorageUtil.UnsetIntValue(None, "TTY_YieldRefused")
    StorageUtil.UnsetIntValue(None, "TTY_ToTheDeath")
    ; 'custom' rejects a plain string (SkyrimNet logs "Invalid value for field 'data'"). persistent_generic
    ; takes JSON with a "line" field, the form other mods' events pass validation with, and is kept as a memory.
    SkyrimNetApi.RegisterEvent("persistent_generic", "{\"line\":\"" + JsonEscape(names + " began a duel with weapons and magic.") + "\"}", akNpc, player)

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
        ; SeverActions starts a companion's fight itself, once they are free (OnSADuelStarted).
        if !sa
            akNpc.StartCombat(player)
        endif
        RegisterForSingleUpdate(TickSeconds)
    endif
EndFunction

State Fighting
    Event OnUpdate()
        Actor player = Game.GetPlayer()
        float now = Utility.GetCurrentRealTime()

        if opponent && opponent.IsDead() && toTheDeath
            EndDuel(player, opponent, "killed")
            return
        elseif !opponent || opponent.IsDead()
            EndDuel(None, None, "broken")
            return
        elseif opponent.IsBleedingOut() && !toTheDeath
            ; To the death, kneeling is no yield: the brawl faction still drops a beaten fighter into
            ; bleedout, and asking again each time left no way to finish them (seen live 2026-11-10).
            ; Only a spoken concession is still asked about.
            OfferYield("downed")
            return
        elseif player.IsBleedingOut() || player.GetActorValue("Health") <= 1.0
            ; An essential player does not play the bleedout kneel: they drop at zero health.
            EndDuel(opponent, player, "downed")
            return
        elseif Elsewhere(opponent)
            ; Through a door or unloaded (seen live 2026-10-26: an NPC agreed, then walked out through
            ; a door). Not the player's forfeit, and not a result either.
            EndDuel(None, None, "opponent_left")
            return
        elseif opponent.GetDistance(player) > WalkAwayDistance
            ; Whoever strayed further from where they stood at the start is the one who left.
            if Strayed(opponent, npcStartX, npcStartY) > Strayed(player, playerStartX, playerStartY)
                EndDuel(None, None, "opponent_left")
            else
                EndDuel(opponent, player, "walked_away")
            endif
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
        ; A companion's fight starts when SeverActions says so: until then, hands off.
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
        if now - engageFrom > LeadInSeconds + 0.5
            ; Kneeling to the death is out of the fight but not refusing it.
            if (opponent.IsInCombat() && opponent.GetCombatTarget() == player) || opponent.IsBleedingOut()
                disengagedSince = 0.0
            else
                if disengagedSince == 0.0
                    disengagedSince = now
                elseif now - disengagedSince >= EngageGraceSeconds
                    EndDuel(None, None, "would_not_fight")
                    return
                endif
                if now - lastRekick >= RekickSeconds && !opponent.IsDead()
                    lastRekick = now
                    opponent.StartCombat(player)
                endif
            endif
        endif
        KeepFollowersOut(opponent)
        RegisterForSingleUpdate(TickSeconds)
    EndEvent

    Function YieldDuel(Actor akSpeaker)
        if akSpeaker && akSpeaker == opponent && Utility.GetCurrentRealTime() >= yieldAgainAt
            OfferYield("conceded")
        endif
    EndFunction

    Function OnOpponentDown()
        OfferYield("downed")
    EndFunction

    ; The opponent yields: the fight stops until the player answers (ShowYield, then AnswerYield).
    Function OfferYield(string asHow)
        GoToState("Yielding")
        UnregisterForUpdate()
        yieldHow = asHow
        yieldAt = Utility.GetCurrentRealTime()
        yieldPending = true
        ShowYield()
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

; The fight is paused on the opponent's yield. Anyone outside the duel joining in still calls it off.
State Yielding
    Function OnOutsideAttack(Actor akAttacker)
        if akAttacker && akAttacker != opponent && akAttacker != Game.GetPlayer() && !akAttacker.IsPlayerTeammate()
            yieldPending = false
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

; ---------------------------------------------------------------------------------------------
; The opponent's yield, and the player's answer
; ---------------------------------------------------------------------------------------------

; A duel to the death is offered only for an opponent who can die: not one a quest keeps alive
; (npcKillable), and not a companion, whom SeverActions keeps essential for the whole duel.
bool Function CanDuelToDeath()
    return npcKillable && !toTheDeath && saHandle <= 0
EndFunction

; Asks the player, on the page or in a box. The game is paused either way.
Function ShowYield()
    Actor npc = opponent
    if !npc
        yieldPending = false
        EndDuel(None, None, "broken")
        return
    endif
    if UiReady()
        string name = npc.GetDisplayName()
        string note = ""
        if toTheDeath
            note = "This is a duel to the death. Accept, and it ends here."
        elseif saHandle > 0
            note = "A companion can't be killed in a duel."
        elseif !npcKillable
            note = name + " can't be killed: the world still needs them."
        endif
        ; 1 or 0, never true/false: Papyrus keeps one string table that ignores case, so a "true" can come
        ; back as another script's "True", which JSON.parse rejects (seen live 2026-11-10: the whole card
        ; lost its data and the death button with it).
        string death = "0"
        if CanDuelToDeath()
            death = "1"
        endif
        string murder = "1"
        if SanctionedDeath && SanctionedDeath.GetValue() > 0
            murder = "0"
        endif
        uiShowing = true
        yieldShowing = true
        string json = "{\"name\":\"" + JsonEscape(name) + "\",\"how\":\"" + yieldHow + "\",\"death\":" + death \
            + ",\"murder\":" + murder + ",\"note\":\"" + JsonEscape(note) + "\"}"
        if TTY_UI.Open(uiView, "ttyYield", json)
            return
        endif
        uiShowing = false
        yieldShowing = false
    endif
    AskYieldWithBox()
EndFunction

Function AskYieldWithBox()
    Actor npc = opponent
    if npc
        ; The box can't name anyone, so the notification just before it does.
        Debug.Notification(npc.GetDisplayName() + " offers a yield")
    endif
    ; Buttons, in this order in both boxes: 0 I accept your yield, 1 Keep fighting, 2 Until one of us is dead.
    if CanDuelToDeath()
        AnswerYield(YieldMsg.Show())
    else
        AnswerYield(YieldMercyMsg.Show())
    endif
EndFunction

; 0 accept, 1 keep fighting, 2 to the death (the box path: asks to confirm first).
Function AnswerYield(int aiChoice)
    if GetState() != "Yielding" || !yieldPending
        return
    endif
    if aiChoice == 1
        RefuseYield(false)
    elseif aiChoice == 2 && CanDuelToDeath()
        ; Buttons: 0 Back, 1 To the death.
        if DeathConfirmMsg.Show() == 1
            ConfirmDeath(true)
        else
            AskYieldWithBox()
        endif
    else
        yieldPending = false
        EndDuel(Game.GetPlayer(), opponent, yieldHow)
    endif
EndFunction

Function ConfirmDeath(bool abSure)
    if GetState() != "Yielding" || !yieldPending
        return
    endif
    if abSure && CanDuelToDeath()
        RefuseYield(true)
    else
        yieldPending = false
        EndDuel(Game.GetPlayer(), opponent, yieldHow)
    endif
EndFunction

; "Keep fighting", or a duel to the death: whoever is down gets up, and the fight goes on.
Function RefuseYield(bool abToDeath)
    yieldPending = false
    Actor player = Game.GetPlayer()
    Actor npc = opponent
    if !npc || npc.IsDead()
        EndDuel(None, None, "broken")
        return
    endif
    string p = player.GetDisplayName()
    string n = npc.GetDisplayName()
    ; The prompt (0680) reads these, so the opponent's own terms change with the fight.
    StorageUtil.SetIntValue(None, "TTY_YieldRefused", StorageUtil.GetIntValue(None, "TTY_YieldRefused", 0) + 1)
    if abToDeath
        toTheDeath = true
        StorageUtil.SetIntValue(None, "TTY_ToTheDeath", 1)
        StorageUtil.SetStringValue(None, "TTY_Status", n + " and " + p + " are fighting to the death. " + p + " refused " + n + "'s yield.")
        SkyrimNetApi.DirectNarration("*" + p + " refuses " + n + "'s yield. The duel is to the death now.*", npc, player)
    else
        ; Said to the opponent, who answers it: refused, and pushed back up to go on.
        StorageUtil.SetStringValue(None, "TTY_Status", n + " and " + p + " are fighting a duel with weapons and magic. " + n + " offered a yield and " + p + " refused it, so it goes on.")
        SkyrimNetApi.DirectNarration("*" + p + " won't accept " + n + "'s yield and pushes " + n + " to get back up and keep fighting. The duel goes on.*", npc, player)
    endif
    ; A spoken yield straight after this would only be the same one again.
    yieldAgainAt = Utility.GetCurrentRealTime() + YieldAgainSeconds
    SkyrimNetApi.SetActionCooldown("YieldDuel", YieldAgainSeconds as int)

    ; Down: back on their feet first, still protected, so nothing kills them on the ground. In combat
    ; an essential NPC stays down fEssentialDeathTime (20 s); out of it, fEssentialNonCombatDeathTime
    ; (0 s). Seen live 2026-11-10: a guard left in the fight was still kneeling after 10 s. So the fight
    ; stops while they rise, as FinishDuel does, and starts again below.
    if npc.IsBleedingOut()
        StopTheFight(npc, true)
        npc.RestoreActorValue("Health", npc.GetBaseActorValue("Health") * RecoverHealthFraction)
        int waited = 0
        while npc.IsBleedingOut() && waited < StandUpSeconds && GetState() == "Yielding"
            Utility.Wait(1.0)
            waited += 1
            if waited % 3 == 0
                StopTheFight(npc, true)
            endif
        endwhile
    endif
    if GetState() != "Yielding"
        ; Ended while they were getting up (an outside attack).
        return
    endif
    if npc.IsBleedingOut()
        ; Still down: they couldn't go on, so the yield stands.
        Debug.Trace("[TTY] " + n + " did not get back up after a refused yield: the yield stands")
        EndDuel(player, npc, yieldHow)
        return
    endif
    if abToDeath
        ; Only what this duel added comes off: the alias's essential flag and the player's. Opponent
        ; still holds the NPC, for the cleanup.
        OpponentAlias.Clear()
        RestorePlayerEssential()
        if SanctionedDeath && SanctionedDeath.GetValue() > 0
            Outlaw(npc)
        endif
    endif

    ; The time spent answering is not duel time.
    float now = Utility.GetCurrentRealTime()
    startTime += now - yieldAt
    disengagedSince = 0.0
    sheathedSince = 0.0
    lastRekick = now
    GoToState("Fighting")
    npc.StartCombat(player)
    RegisterForSingleUpdate(TickSeconds)
EndFunction

; Nothing differs while the offer is up; the state itself keeps other duels out (CannotDuelReason).
State Asking
EndState

Function FinishDuel(Actor akWinner, Actor akLoser, string asHow)
    Actor player = Game.GetPlayer()
    Actor npc = opponent
    TTY_Records.Result(player, npc, akWinner, asHow)
    ; SeverActions stops the fight and gives a companion back to their framework.
    if saHandle > 0
        int h = saHandle
        saHandle = 0
        saStarted = false
        TTY_SABridge.End(h)
    endif
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
    StorageUtil.UnsetIntValue(None, "TTY_YieldRefused")
    StorageUtil.UnsetIntValue(None, "TTY_ToTheDeath")
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
    RestoreConfidence()
    RestoreCrimeFaction()
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
    toTheDeath = false
    yieldPending = false
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
    if asHow == "killed"
        return "*" + n + " dies by " + p + "'s hand. The duel to the death is over.*"
    elseif asHow == "downed" && akWinner && akLoser
        return "*" + akLoser.GetDisplayName() + " goes down and yields. " + akWinner.GetDisplayName() + " has won the duel.*"
    elseif asHow == "player_yielded"
        return "*" + p + " sheathes their weapon and yields. " + n + " has won the duel.*"
    elseif asHow == "walked_away"
        return "*" + p + " walks away from the duel with " + n + ", forfeiting it.*"
    elseif asHow == "opponent_left"
        return "*" + n + " leaves before the duel with " + p + " is settled, and it is called off.*"
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

; Many civilians are Cowardly (Confidence 0) and run from any fight, a duel included: tested live
; 2026-10-25, Captain Wayfinder and Ravam Verethi both fled. Foolhardy (4) never flees. Confidence is
; saved with the game, so the original goes in the co-save, as the ranks below do.
Function Embolden(Actor akNpc)
    StorageUtil.SetFormValue(None, "TTY_BraveNpc", akNpc)
    StorageUtil.SetFloatValue(None, "TTY_NpcConfidence", akNpc.GetBaseActorValue("Confidence"))
    akNpc.SetActorValue("Confidence", 4.0)
EndFunction

; A sanctioned duel to the death: a crime is reported to the victim's crime faction, so without one
; there is nobody to report the killing to. Kept in the co-save, as the ranks are.
Function Outlaw(Actor akNpc)
    Faction crime = akNpc.GetCrimeFaction()
    if !crime
        return
    endif
    StorageUtil.SetFormValue(None, "TTY_LawlessNpc", akNpc)
    StorageUtil.SetFormValue(None, "TTY_NpcCrimeFaction", crime)
    akNpc.SetCrimeFaction(None)
EndFunction

Function RestoreCrimeFaction()
    Actor npc = StorageUtil.GetFormValue(None, "TTY_LawlessNpc") as Actor
    Faction crime = StorageUtil.GetFormValue(None, "TTY_NpcCrimeFaction") as Faction
    if npc && crime
        npc.SetCrimeFaction(crime)
    endif
    StorageUtil.UnsetFormValue(None, "TTY_LawlessNpc")
    StorageUtil.UnsetFormValue(None, "TTY_NpcCrimeFaction")
EndFunction

Function RestoreConfidence()
    Actor npc = StorageUtil.GetFormValue(None, "TTY_BraveNpc") as Actor
    if npc
        npc.SetActorValue("Confidence", StorageUtil.GetFloatValue(None, "TTY_NpcConfidence", 0.0))
    endif
    StorageUtil.UnsetFormValue(None, "TTY_BraveNpc")
    StorageUtil.UnsetFloatValue(None, "TTY_NpcConfidence")
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
    if saHandle > 0
        ; Only reached with SeverActions present: saHandle is never set without it.
        int h = saHandle
        saHandle = 0
        TTY_SABridge.End(h)
    endif
    saStarted = false
    if OpponentAlias
        ; A duel to the death has already cleared the alias: opponent still names the NPC.
        Actor npc = OpponentAlias.GetActorReference()
        if !npc
            npc = opponent
        endif
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
    StorageUtil.UnsetIntValue(None, "TTY_Asking")
    StorageUtil.UnsetStringValue(None, "TTY_Status")
    StorageUtil.UnsetIntValue(None, "TTY_YieldRefused")
    StorageUtil.UnsetIntValue(None, "TTY_ToTheDeath")
    GuardOff(None, None)
    RestorePlayerEssential()
    RestoreRanks()
    RestoreConfidence()
    RestoreCrimeFaction()
    opponent = None
    brawlFactionUsed = false
    toTheDeath = false
    yieldPending = false
    yieldShowing = false
    GoToState("")
EndFunction
