Scriptname SNDuel_OpponentAlias extends ReferenceAlias
{On the Opponent alias of SNDuel_Quest. The alias's Essential flag is what keeps the NPC alive;
 this script reports when they go down and when someone outside the duel hits them.
 SNDuel_Main ignores both unless a duel is being fought.}

Event OnEnterBleedout()
    SNDuel_Main main = GetOwningQuest() as SNDuel_Main
    if main
        main.OnOpponentDown()
    endif
EndEvent

Event OnHit(ObjectReference akAggressor, Form akSource, Projectile akProjectile, bool abPowerAttack, bool abSneakAttack, bool abBashAttack, bool abHitBlocked)
    ; Traps and hazards hit with a non-actor aggressor, or none: the cast gives None for those.
    Actor attacker = akAggressor as Actor
    if !attacker || attacker == Game.GetPlayer()
        return
    endif
    ; The cast is None if SNDuel_Main failed to load. Checked, so OnHit cannot spam the log.
    SNDuel_Main main = GetOwningQuest() as SNDuel_Main
    if main
        main.OnOutsideAttack(attacker)
    endif
EndEvent
