Scriptname TTY_SA Hidden
{Whether SeverActions' Duel API can be used. Names no SeverActions type, so it loads with or without
 SeverActions; TTY_SABridge holds the calls themselves.

 With the API, To the Yield also duels what it otherwise refuses: the player against an active
 companion (TTY_Main), and two NPCs of the same side, such as two guards of one hold (TTY_NpcDuel).
 SeverActions frees a companion to fight, keeps its friendly-fire guard and the follower frameworks
 off the pair, and puts it all back afterwards. Every other duel keeps To the Yield's own path.

 StorageUtil key, read by the layer's BeginDuel.yaml:
     TTY_SADuels   int, global   1 when the API is usable this session (set on every load)}

bool Function Present() Global
    ; GetPluginVersion is -1 when SeverActionsNative.dll is not loaded.
    return SKSE.GetPluginVersion("SeverActionsNative") > 0 && Game.GetModByName("SeverActions.esp") != 255
EndFunction

bool Function Available() Global
    return Present() && TTY_SABridge.ApiVersion() >= 1
EndFunction

; On every load, so the layer's eligibility rules know (a companion is only offered BeginDuel then).
Function Refresh() Global
    if Available()
        StorageUtil.SetIntValue(None, "TTY_SADuels", 1)
    else
        StorageUtil.UnsetIntValue(None, "TTY_SADuels")
    endif
EndFunction
