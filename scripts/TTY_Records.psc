Scriptname TTY_Records Hidden
{Duel records: who has fought whom, and how it went. TTY_Main and TTY_NpcDuel report every ending
 and every spoken refusal here; the layer prompt 0681_whyregister_duel_record reads the counts back.

 Only what an NPC is part of ever reaches that NPC's prompt: their own record, and their record
 against whoever they are talking to. Everything is in the SKSE co-save (StorageUtil), on the actors.

 How endings count: a winner and a loser (downed, yielded, conceded, or walked away, which forfeits)
 is a win and a loss. "time" and "separated" are draws. Anything else (interrupted, never drew,
 would not fight, broken) is not a result and is not recorded.

 StorageUtil keys. The prompt reads the same strings with papyrus_util, so rename one here and you
 must rename it there too:
     TTY_RecW, TTY_RecL, TTY_RecD      int, on any duelist   their own wins, losses, draws
     TTY_VsPlayerW, L, D               int, on the NPC       their wins, losses, draws against the player
     TTY_RefusedByPlayer               int, on the NPC       times the player turned their challenge down aloud
     TTY_VsW|<name>, L|, D|            int, on an NPC        against another NPC, by that NPC's name
     TTY_RefusedBy|<name>              int, on an NPC        times that NPC declined their challenge
     TTY_RecFoes                       form list, on player  everyone the player has a result or a refusal with
 NPC-against-NPC counts are keyed by display name because the prompt only knows the other actor by
 name (decnpc(responseTarget.UUID).name, the same string GetDisplayName gives).}

; A duel ended. akA and akB are the two duelists, akWinner is one of them or None.
Function Result(Actor akA, Actor akB, Actor akWinner, string asHow) Global
    if !akA || !akB || akA == akB
        return
    endif
    if akWinner && (akWinner == akA || akWinner == akB)
        Actor loser = akB
        if akWinner == akB
            loser = akA
        endif
        Count(akWinner, loser, "W")
        Count(loser, akWinner, "L")
        Debug.Trace("[TTY] Record: " + akWinner.GetDisplayName() + " beat " + loser.GetDisplayName() + " (" + asHow + ")")
    elseif asHow == "time" || asHow == "separated"
        Count(akA, akB, "D")
        Count(akB, akA, "D")
        Debug.Trace("[TTY] Record: " + akA.GetDisplayName() + " and " + akB.GetDisplayName() + " drew (" + asHow + ")")
    endif
EndFunction

; akRefuser turned akChallenger's challenge down out loud. Silent refusals are never recorded.
Function Refusal(Actor akChallenger, Actor akRefuser) Global
    if !akChallenger || !akRefuser || akChallenger == akRefuser
        return
    endif
    Actor player = Game.GetPlayer()
    if akRefuser == player
        StorageUtil.AdjustIntValue(akChallenger, "TTY_RefusedByPlayer", 1)
        StorageUtil.FormListAdd(player, "TTY_RecFoes", akChallenger, false)
    elseif akChallenger != player
        StorageUtil.AdjustIntValue(akChallenger, "TTY_RefusedBy|" + akRefuser.GetDisplayName(), 1)
    endif
EndFunction

; One line of akActor's tally, against akOther. asWhat: "W", "L" or "D".
Function Count(Actor akActor, Actor akOther, string asWhat) Global
    Actor player = Game.GetPlayer()
    StorageUtil.AdjustIntValue(akActor, "TTY_Rec" + asWhat, 1)
    if akActor == player
        StorageUtil.FormListAdd(player, "TTY_RecFoes", akOther, false)
    elseif akOther == player
        StorageUtil.AdjustIntValue(akActor, "TTY_VsPlayer" + asWhat, 1)
    else
        StorageUtil.AdjustIntValue(akActor, "TTY_Vs" + asWhat + "|" + akOther.GetDisplayName(), 1)
    endif
EndFunction

; ---------------------------------------------------------------------------------------------
; The player's side, for the Duel Record power and the duel offer card. Everything here is from the
; player's point of view: an NPC's losses against the player are the player's wins.
; ---------------------------------------------------------------------------------------------

; "Your duels with Farkas: 2 won, 1 lost." or "" when the player has no result with akNpc.
string Function VsPlayerLine(Actor akNpc) Global
    if !akNpc
        return ""
    endif
    int w = StorageUtil.GetIntValue(akNpc, "TTY_VsPlayerL", 0)
    int l = StorageUtil.GetIntValue(akNpc, "TTY_VsPlayerW", 0)
    int d = StorageUtil.GetIntValue(akNpc, "TTY_VsPlayerD", 0)
    if w + l + d == 0
        return ""
    endif
    return "Your duels with " + akNpc.GetDisplayName() + ": " + Tally(w, l, d) + "."
EndFunction

string Function Tally(int aiW, int aiL, int aiD) Global
    string s = aiW + " won, " + aiL + " lost"
    if aiD > 0
        s += ", " + aiD + " drawn"
    endif
    return s
EndFunction

; Everyone the player has a result or a refusal with, at most aiMax of them, as live actors.
Actor[] Function Foes(int aiMax) Global
    Actor player = Game.GetPlayer()
    int n = StorageUtil.FormListCount(player, "TTY_RecFoes")
    Actor[] out = PapyrusUtil.ActorArray(0)
    int i = 0
    while i < n && out.Length < aiMax
        Actor a = StorageUtil.FormListGet(player, "TTY_RecFoes", i) as Actor
        ; A deleted actor (a despawned leveled NPC) comes back None: their row goes, the totals stay.
        if a
            out = PapyrusUtil.PushActor(out, a)
        endif
        i += 1
    endwhile
    return out
EndFunction

; The record page's data: {"name","w","l","d","foes":[{"name","w","l","d","r"}]}. r = challenges of
; theirs the player turned down aloud.
string Function PlayerJson() Global
    Actor player = Game.GetPlayer()
    string s = "{\"name\":\"" + Esc(player.GetDisplayName()) + "\"" \
        + ",\"w\":" + StorageUtil.GetIntValue(player, "TTY_RecW", 0) \
        + ",\"l\":" + StorageUtil.GetIntValue(player, "TTY_RecL", 0) \
        + ",\"d\":" + StorageUtil.GetIntValue(player, "TTY_RecD", 0) + ",\"foes\":["
    Actor[] foes = Foes(60)
    int i = 0
    while i < foes.Length
        Actor a = foes[i]
        if i > 0
            s += ","
        endif
        s += "{\"name\":\"" + Esc(a.GetDisplayName()) + "\"" \
            + ",\"w\":" + StorageUtil.GetIntValue(a, "TTY_VsPlayerL", 0) \
            + ",\"l\":" + StorageUtil.GetIntValue(a, "TTY_VsPlayerW", 0) \
            + ",\"d\":" + StorageUtil.GetIntValue(a, "TTY_VsPlayerD", 0) \
            + ",\"r\":" + StorageUtil.GetIntValue(a, "TTY_RefusedByPlayer", 0) + "}"
        i += 1
    endwhile
    return s + "]}"
EndFunction

; The same, as a message box's text, for when there is no Magelight page.
string Function PlayerText() Global
    Actor player = Game.GetPlayer()
    int w = StorageUtil.GetIntValue(player, "TTY_RecW", 0)
    int l = StorageUtil.GetIntValue(player, "TTY_RecL", 0)
    int d = StorageUtil.GetIntValue(player, "TTY_RecD", 0)
    if w + l + d == 0 && StorageUtil.FormListCount(player, "TTY_RecFoes") == 0
        return "You have not fought a duel to the yield yet."
    endif
    string s = "Duels to the yield: " + Tally(w, l, d) + "."
    Actor[] foes = Foes(12)
    int i = 0
    while i < foes.Length
        Actor a = foes[i]
        s += "\n" + a.GetDisplayName() + ": " + Tally(StorageUtil.GetIntValue(a, "TTY_VsPlayerL", 0), StorageUtil.GetIntValue(a, "TTY_VsPlayerW", 0), StorageUtil.GetIntValue(a, "TTY_VsPlayerD", 0))
        int r = StorageUtil.GetIntValue(a, "TTY_RefusedByPlayer", 0)
        if r > 0
            s += "; you turned them down " + r + "x"
        endif
        i += 1
    endwhile
    return s
EndFunction

string Function Esc(string asText) Global
    string out = ""
    int len = StringUtil.GetLength(asText)
    int i = 0
    while i < len
        string c = StringUtil.GetNthChar(asText, i)
        if c == "\"" || c == "\\"
            out += "\\"
        endif
        out += c
        i += 1
    endwhile
    return out
EndFunction
