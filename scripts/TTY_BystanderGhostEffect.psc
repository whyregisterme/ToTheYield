Scriptname TTY_BystanderGhostEffect extends ActiveMagicEffect
{TTY_BystanderGhostAbility's effect: a bystander near the player turns ghost while a duel is fought, so
 a stray blow passes through them instead of hurting them (or counting as assault). The engine turns it
 on and off from the ability's conditions (TTY_BystanderGuard is 1, within 600 units of the player,
 not in TTY_DuelistFaction, not the player); this only flips the flag.
 Same technique as "Brawling - No Hitting Bystanders", which does it for vanilla brawls.}

Keyword Property WasGhost Auto
{TTY_WasGhost: marks a bystander who was a ghost already, so we leave them one afterwards.}

Event OnEffectStart(Actor akTarget, Actor akCaster)
    if !akTarget
        return
    endif
    if akTarget.IsGhost()
        PO3_SKSEFunctions.AddKeywordToRef(akTarget, WasGhost)
    else
        akTarget.SetGhost(true)
    endif
EndEvent

Event OnEffectFinish(Actor akTarget, Actor akCaster)
    if !akTarget
        return
    endif
    if akTarget.HasKeyword(WasGhost)
        PO3_SKSEFunctions.RemoveKeywordFromRef(akTarget, WasGhost)
    else
        akTarget.SetGhost(false)
    endif
EndEvent
