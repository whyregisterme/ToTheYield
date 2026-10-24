Scriptname TTY_NpcPlayerAlias extends ReferenceAlias
{On the PlayerAlias of TTY_NpcDuelQuest. Quest scripts get no load event, so this passes it on.}

Event OnPlayerLoadGame()
    TTY_NpcDuel main = GetOwningQuest() as TTY_NpcDuel
    if main
        main.OnGameLoad()
    endif
EndEvent
