Scriptname TTY_RecordPowerEffect extends ActiveMagicEffect
{TTY_RecordPowerEffect, on the Duel Record lesser power: shows the player's duel record, on the
 Magelight page when there is one, else in a message box. TTY_Main hands the power out on every load.}

TTY_Main Property MainQuest Auto
{TTY_Quest.}

Event OnEffectStart(Actor akTarget, Actor akCaster)
    if MainQuest
        MainQuest.ShowRecord()
    endif
EndEvent
