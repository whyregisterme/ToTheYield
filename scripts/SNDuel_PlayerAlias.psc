Scriptname SNDuel_PlayerAlias extends ReferenceAlias
{On the PlayerAlias of SNDuel_Quest. After every load it lets SNDuel_Main undo a duel's flags, and
 while a duel runs it notices anyone outside the duel attacking the player.}

Actor duelOpponent = None

Event OnPlayerLoadGame()
    ; The cast is None if SNDuel_Main failed to load; check it rather than log an error per load.
    SNDuel_Main main = GetOwningQuest() as SNDuel_Main
    if main
        main.OnGameLoad()
    endif
EndEvent

Function WatchDuel(Actor akOpponent)
    duelOpponent = akOpponent
    GoToState("Watching")
EndFunction

Function StopWatching()
    duelOpponent = None
    GoToState("")
EndFunction

; OnHit fires for every hit the player takes, so it is only handled while a duel runs.
State Watching
    Event OnHit(ObjectReference akAggressor, Form akSource, Projectile akProjectile, bool abPowerAttack, bool abSneakAttack, bool abBashAttack, bool abHitBlocked)
        ; Traps and hazards hit with a non-actor aggressor, or none: the cast gives None for those.
        Actor attacker = akAggressor as Actor
        if !attacker || attacker == duelOpponent || attacker == GetActorReference()
            return
        endif
        SNDuel_Main main = GetOwningQuest() as SNDuel_Main
        if main
            main.OnOutsideAttack(attacker)
        endif
    EndEvent
EndState
