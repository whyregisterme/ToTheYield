# To the Yield

A SkyrimNet add-on for formal duels: real weapons, fought until one side yields or goes down.
Nobody dies.

Talk an NPC into a duel, or let one challenge you. NPCs can also challenge each other while you
watch. Each side fights with whatever they're carrying. When it ends, SkyrimNet hears how it went, so
the duelists (and anyone watching) remember who won.

## Requirements

- SkyrimNet **0.28.0 (beta 28) or newer**
- PapyrusUtil SE (SkyrimNet already needs it)
- powerofthree's Papyrus Extender
- Optional: Spell Perk Item Distributor (SPID), for bystander protection (see below). Without it
  everything else works; bystanders just aren't shielded from stray blows.
- Optional: **Magelight UI 1.3.0 or newer** (SeverActions installs it too). With it, the
  confirmations appear on a proper page that names who is involved; without it, as message boxes.
- Optional: **SeverActions 4.6.0 or newer**, for its Duel API. With it you can duel your own
  companions, and NPCs of the same side (two of your followers, two guards of one hold) can duel each
  other. Without it those are refused, and everything else works the same.

## Install

Download `ToTheYield-<version>.zip` from [Releases](../../releases) and install it with your mod
manager (Vortex or MO2). Enable `ToTheYield.esp`. It's ESL-flagged, so it takes no load-order slot.

Updating: replace the old version rather than installing alongside it.

**Game versions:** tested on 1.6.1170. There is no DLL, so the mod itself doesn't depend on the game
version; it runs wherever SkyrimNet, PapyrusUtil and Papyrus Extender do. The plugin uses header
version 1.70, so it loads on SE 1.5.97 as well as AE, without needing BEES.

## Playing

- **Starting a duel.** Ask an NPC to duel, or an NPC may challenge you. You're asked to confirm, on
  the Magelight page if you have it, else in a box:
  - **Fight** starts the duel.
  - **Refuse** declines, and the NPC hears that you turned them down.
  - **Refuse silently** declines without telling the NPC (Escape does the same on the page).
- **No confirmation, no duel.** The confirmation is the only sign a duel has really started and that
  you're both protected. If an NPC agrees but nothing asks you, the duel didn't start: don't attack
  them, ask again.
- **Yielding.** Sheathe your weapon for about 4 seconds. The NPC can also concede on their own.
- **Nobody dies.** Your opponent kneels when beaten. You drop at zero health and they stop attacking.
  Afterwards, whoever went down gets back up with some health.
- **A duel also ends** if you walk away, never draw your weapon, someone outside the duel attacks
  either of you, or 3 minutes pass. Your followers are kept out of it. If your opponent is the one
  who leaves (through a door, say), the duel is simply called off.
- **Friends can duel you; followers need SeverActions or dismissing.** A current follower won't fight
  you on their own (their follower status stops it). With SeverActions 4.6.0 or newer, its Duel API
  frees them for the duel and gives them back to you afterwards, still following. Without it, dismiss
  them, then duel. If an opponent still won't actually fight
  (stays out of combat for about 4 seconds), the duel is called off instead of dragging on.
- You can't duel while either of you is already in combat or on horseback, against someone hostile to you, or with a child. Your opponent has to be close by.

### NPC against NPC

- **Challenges.** An NPC may challenge someone nearby to a duel. The challenged NPC accepts or
  declines in their own words. An unanswered challenge lapses after a minute.
- **You decide.** When a challenge is accepted, you're asked first:
  - **Allow** lets the duel go ahead.
  - **Stop it** calls it off, and the two hear that you stopped it.
  - **Stop it silently** calls it off without telling them (Escape does the same on the page).
- **The fight.** Same rules as yours: nobody dies, the loser kneels and yields, and either duelist
  can concede. It ends in a draw after 3 minutes, and is called off if the two drift far apart,
  never really fight, or someone else joins in.
- **Same side.** Two members of the same group (two guards of the same hold, two of your followers)
  won't fight each other on their own. With SeverActions 4.6.0 or newer its Duel API stages the
  fight, and your followers can issue challenges too; without it, that pair is refused and followers
  don't challenge.
- **One duel at a time.** While any duel is on, yours or theirs, no other can start.

### Duel records

- **Everyone's record is kept**, in your duels and in NPC duels: wins, losses and draws, and head to
  head. Beating someone or making them yield is a win; walking away forfeits, so it counts as a loss;
  running out of time is a draw. Duels that are interrupted or called off don't count.
- **Turning a challenge down aloud** is remembered by the challenger. Refusing silently never is.
- **NPCs know only their own record**: how they've done overall, and against whoever they're talking
  to. Someone who has never fought a duel hears nothing about anyone's.
- **Duel Record**, a lesser power you're given, shows your record and a row for each opponent (on the
  Magelight page, or in a box without it). When someone you've fought before challenges you again,
  their offer shows your record against them.
- Records start with 0.5.0; duels fought on earlier versions aren't counted.

### Bystanders (needs SPID)

While any duel is fought, NPCs within about 8 m of you who aren't in it turn ghost: blows pass
through them, so a wild swing in a crowded hall doesn't hurt the Jarl or count as an assault. They
turn solid again when the duel ends. An NPC who was already a ghost stays one.

## Console levers

- `set TTY_UseMagelight to 0`: always the message boxes, even with Magelight installed (say, on a
  controller). Set it back to `1` and load a save to bring the page back.
- `set TTY_UseBrawlFaction to 0`: keeps you and your opponent out of the vanilla brawl faction. Default
  1. Without it, your opponent's friends (fellow guards, the Companions) join in on their side.
- If a duel ever gets stuck: `stopquest TTY_Quest`, then `startquest TTY_Quest`. If you're
  still unkillable afterwards: `setessential 7 0`.
- A stuck NPC duel: `stopquest TTY_NpcDuelQuest`, then `startquest TTY_NpcDuelQuest`.
- Bystanders still ghosts after a duel: `set TTY_BystanderGuard to 0`.

## How it works

| Path | What |
|---|---|
| `scripts/TTY_Main.psc` | The duel: start, watch, end, clean up. Its header lists the StorageUtil keys |
| `scripts/TTY_PlayerAlias.psc` | Cleanup after a reload; outside attackers on the player |
| `scripts/TTY_OpponentAlias.psc` | Opponent went down, or was hit by an outsider |
| `scripts/TTY_NpcDuel.psc` | NPC against NPC: challenge, accept, the fight, the end. Its header lists its StorageUtil keys |
| `scripts/TTY_NpcDuelistAlias.psc`, `TTY_NpcPlayerAlias.psc` | A duelist went down or was hit; cleanup after a reload |
| `scripts/TTY_BystanderGhostEffect.psc` | Turns a nearby bystander ghost for the length of a duel |
| `scripts/TTY_Records.psc` | Duel records: every result and spoken refusal, kept on the actors. Its header lists the keys |
| `scripts/TTY_RecordPowerEffect.psc` | The Duel Record power |
| `scripts/TTY_SA.psc` | Whether SeverActions' Duel API is there; names no SeverActions script, so it loads without it |
| `scripts/TTY_SABridge.psc` | Every SeverActions call, made only after `TTY_SA` says it's there. SeverActions' scripts are compiled against, never shipped |
| `scripts/TTY_UI.psc` | Every Magelight UI call, behind a check that Magelight is installed, new enough and ready |
| `magelight/ToTheYield/` | The Magelight page: both confirmations and the record, in Windows' own fonts (nothing bundled) |
| `imports/` | Magelight's Papyrus header, compiled against and never shipped (Magelight installs its own) |
| `ToTheYield_DISTR.ini` | SPID gives every NPC the (conditional) bystander ability |
| `spriggit/ToTheYield/` | The plugin as Spriggit JSON: two quests (one per duel kind, Essential aliases), two confirm boxes, the bystander ability, the Duel Record power, a faction, a keyword, three globals |
| `layer/whyregister.to-the-yield/` | The SkyrimNet layer: `BeginDuel`, `YieldDuel`, `ChallengeDuel`, `AcceptDuel`, `DeclineDuel` and `YieldNpcDuel` actions, a prompt that only renders while a duel is on, and one with the speaker's own record (nothing for someone without one) |

- Protection: the NPC sits in an Essential quest alias, so they go into bleedout instead of dying.
  The player is set essential only for the duel. The vanilla brawl faction alone does **not** stop
  weapon damage.
- Friends: someone who likes you drops out of any fight with you at once. For the duel, their
  relationship rank with you is set to 0 (tested live: they then fought every time), and put back
  afterwards. The original is kept in the save, so a reload or quest restart always restores it.
- Followers: the follower factions keep them from fighting you whatever their rank, and SeverActions'
  friendly-fire guard stops any fight with its companions. Dismissed, they duel like anyone else.
- SeverActions' Duel API (4.6.0+): used only for what To the Yield can't stage itself, a duel with
  your active companion and a duel between two NPCs of the same side. SeverActions frees a companion
  (teammate flag, follower frameworks), sets both duelists' courage and the brawl faction, keeps its
  friendly-fire guard and your other followers off the pair, and puts all of it back when the duel
  ends. To the Yield waits for SeverActions to say the fight is on, then runs the duel exactly as
  usual: the yield, the protection, the records. A save loaded mid-duel ends such a duel, unrecorded.
  Tested live: you against a companion, two Whiterun guards, and two of your followers, with a third
  follower staying out.
- Courage: many civilians are Cowardly and run from any fight. For the duel, each duelist's
  Confidence is raised to Foolhardy and put back afterwards (the original is kept in the save, like
  the relationship rank). Tested live: two cowardly Dawnstar locals then fought it out.
- Pile-ons: both duelists join the vanilla brawl faction, in your duels and NPC duels alike, which
  keeps their friends from piling in. Without it, a fellow guard joined within a second in testing,
  and up to 0.3.1 your own duels went without it: duel a guard and the other guards joined in. Tested
  live: two of the opponent's fellow guards stood by, and sword hits still did full damage.
- Bystanders: the ability's conditions (a duel is on, within 600 units of you, not a duelist) are
  checked by the engine, which switches the ghost flag on and off. No script watches swings. Same
  technique as "Brawling - No Hitting Bystanders" uses for vanilla brawls.
- The confirm boxes don't name anyone (name tags in message boxes showed up as "[...]" in game); a
  notification just before each box says who is involved. The Magelight page gets the names as text.
- The page falls back to the boxes whenever it can't be used: Magelight missing or older than 1.3.0,
  another mod holding the cursor, the page failing to load, or `TTY_UseMagelight` at 0. Both quests
  share the one page, each answering on its own listener, and only one confirmation is up at a time.
- Afterwards, combat is stopped three times over 4 seconds (once wasn't enough in testing), flags are
  restored, and SkyrimNet gets a narration of the outcome.

## Building

`build.sh` (Git Bash on Windows) compiles the scripts with Caprica, builds the `.esp` from the
Spriggit source, round-trips it back to JSON to catch dropped fields, and zips the result into
`dist/`. It expects to sit two folders below a tools folder inside the game directory
(`<Skyrim>/Tools/projects/ToTheYield`), with Caprica and Spriggit in that tools folder, Python 3
on PATH, and the game's Papyrus sources (vanilla, SKSE, PapyrusUtil, Papyrus Extender, SkyrimNet)
installed. It only reads the game folder.

## Credits

- SkyrimNet by the SkyrimNet team
- PapyrusUtil by exiledviking; Papyrus Extender by powerofthree
- Magelight UI by Severause (MIT); its Papyrus header is in `imports/` for building

## License

MIT. See [LICENSE](LICENSE).
