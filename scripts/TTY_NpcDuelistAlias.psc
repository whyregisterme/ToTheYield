Scriptname TTY_NpcDuelistAlias extends ReferenceAlias
{On the DuelistA and DuelistB aliases of TTY_NpcDuelQuest. The alias's Essential flag is what keeps
 the duelist alive; this script reports when they go down and when someone outside the duel hits
 them. TTY_NpcDuel ignores both unless a duel is being fought.}

Event OnEnterBleedout()
    TTY_NpcDuel main = GetOwningQuest() as TTY_NpcDuel
    if main
        main.OnDuelistDown(GetActorReference())
    endif
EndEvent

Event OnHit(ObjectReference akAggressor, Form akSource, Projectile akProjectile, bool abPowerAttack, bool abSneakAttack, bool abBashAttack, bool abHitBlocked)
    ; Traps and hazards hit with a non-actor aggressor, or none: the cast gives None for those.
    Actor attacker = akAggressor as Actor
    if !attacker
        return
    endif
    ; The cast is None if TTY_NpcDuel failed to load. Checked, so OnHit cannot spam the log.
    TTY_NpcDuel main = GetOwningQuest() as TTY_NpcDuel
    if main
        main.OnOutsideAttack(GetActorReference(), attacker)
    endif
EndEvent
