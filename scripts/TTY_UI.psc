Scriptname TTY_UI Hidden
{Every Magelight UI call To the Yield makes. Magelight is optional: when it is missing, too old or
 not ready, Available() is false, nothing below calls it, and TTY_Main and TTY_NpcDuel fall back to
 message boxes. Kept apart so neither of them names Magelight at all.

 The page is Data/Magelight/ToTheYield/views/prompt/index.html, created hidden at startup by that
 folder's manifest.json. Both quests share it, each with its own listener, so a button answer only
 reaches the script that asked. Magelight keeps nothing in the save, so Setup() runs on every load.}

string Function ModId() Global
    return "ToTheYield"
EndFunction

; 1.3.0: the oldest host this was tested on.
bool Function Available() Global
    if SKSE.GetPluginVersion("Magelight") <= 0
        return false
    endif
    return Magelight.GetVersion() >= 10300 && Magelight.IsReady()
EndFunction

; The page's view id, or 0 when there is no usable page this session. asListener is the page function
; this script's answers come back through (Magelight_JS_<asListener>). RegisterMod is idempotent, so
; both quests calling it is fine.
int Function Setup(string asListener) Global
    if !Available()
        return 0
    endif
    if !Magelight.RegisterMod(ModId(), "To the Yield")
        Debug.Trace("[TTY] Magelight refused the mod: " + Magelight.GetLastError(ModId()))
        return 0
    endif
    int view = Magelight.FindView(ModId(), "prompt")
    if view == 0
        Debug.Trace("[TTY] Magelight has no prompt view; is the Magelight/ToTheYield folder installed?")
        return 0
    endif
    Magelight.RegisterListener(view, asListener)
    return view
EndFunction

; Hands the page its content, shows it and takes the cursor with the game paused. False when the
; cursor is taken: the caller uses a message box instead. Checked before touching the page, because
; the page is shared: the other quest's card may be the one up, and Call would draw over it.
bool Function Open(int aiView, string asFunction, string asJson) Global
    if Magelight.IsUIModeActive()
        Debug.Trace("[TTY] Magelight UI mode is held (view " + Magelight.GetUIModeView() + "): message box instead")
        return false
    endif
    Magelight.Call(aiView, asFunction, asJson)
    Magelight.ShowView(aiView, true)
    if !Magelight.RequestUIMode(aiView, true)
        Debug.Trace("[TTY] Magelight UI mode refused: " + Magelight.GetLastError(ModId()))
        Magelight.ShowView(aiView, false)
        return false
    endif
    return true
EndFunction

Function Close(int aiView) Global
    Magelight.ReleaseUIMode(ModId())
    Magelight.ShowView(aiView, false)
EndFunction
