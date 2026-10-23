Scriptname TTY_OpponentAlias extends ReferenceAlias
{On the Opponent alias of TTY_Quest. The alias's Essential flag is what keeps the NPC alive;
 this script reports when they go down and when someone outside the duel hits them.
 TTY_Main ignores both unless a duel is being fought.}

Event OnEnterBleedout()
    TTY_Main main = GetOwningQuest() as TTY_Main
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
    ; The cast is None if TTY_Main failed to load. Checked, so OnHit cannot spam the log.
    TTY_Main main = GetOwningQuest() as TTY_Main
    if main
        main.OnOutsideAttack(attacker)
    endif
EndEvent
