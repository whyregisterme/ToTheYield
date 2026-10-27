Scriptname TTY_SABridge Hidden
{Every SeverActions call To the Yield makes, and nothing else: SeverActions' Duel API (v1,
 SeverActions 4.6.0, Data/SKSE/Plugins/SeverActions/API/DUEL_API.md).

 Without SeverActions this script cannot load, so nothing may call it before TTY_SA.Present() says
 SeverActions is there, and it is only ever called statically (TTY_SABridge.Begin(...)), never
 through a variable or property of its type. Compiled against SeverActionsNativeExt2.psc, whose
 .pex is never shipped.}

int Function ApiVersion() Global
    return SeverActionsNativeExt2.Duel_ApiVersion()
EndFunction

; The duel's handle, or 0 when SeverActions refused (its reason is in SeverActionsNative.log).
int Function Begin(Actor akA, Actor akB, float afMaxSeconds) Global
    if SeverActionsNativeExt2.Duel_ApiVersion() < 1
        return 0
    endif
    return SeverActionsNativeExt2.Duel_Begin(akA, akB, afMaxSeconds)
EndFunction

bool Function End(int aiHandle) Global
    return SeverActionsNativeExt2.Duel_End(aiHandle)
EndFunction
