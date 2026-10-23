# SkyrimNet Duels

A SkyrimNet add-on for formal duels: real weapons, fought until one side yields or goes down.
Nobody dies.

Talk an NPC into a duel, or let one challenge you. Each side fights with whatever they're carrying.
When it ends, SkyrimNet hears how it went, so the NPC (and anyone watching) remembers who won.

## Requirements

- SkyrimNet **0.28.0 (beta 28) or newer**
- PapyrusUtil SE (SkyrimNet already needs it)
- powerofthree's Papyrus Extender

## Install

Download `SkyrimNetDuels-<version>.zip` from [Releases](../../releases) and install it with your mod
manager (Vortex or MO2). Enable `SkyrimNetDuels.esp`. It's ESL-flagged, so it takes no load-order slot.

Updating: replace the old version rather than installing alongside it.

## Playing

- **Starting a duel.** Ask an NPC to duel, or an NPC may challenge you. A box asks you to confirm:
  - **Fight** starts the duel.
  - **Refuse** declines, and the NPC hears that you turned them down.
  - **Refuse silently** declines without telling the NPC.
- **Yielding.** Sheathe your weapon for about 4 seconds. The NPC can also concede on their own.
- **Nobody dies.** Your opponent kneels when beaten. You drop at zero health and they stop attacking.
  Afterwards, whoever went down gets back up with some health.
- **A duel also ends** if you walk away, never draw your weapon, someone outside the duel attacks
  either of you, or 3 minutes pass. Your followers are kept out of it.
- You can't duel while either of you is already in combat or on horseback, against someone hostile to you, or with a child. Your opponent has to be close by.

## Console levers

- `set SNDuel_UseBrawlFaction to 1`: also puts both fighters in the vanilla brawl faction, in case
  guards or bystanders keep joining in. Default 0, because other mods' brawls use the same faction.
- If a duel ever gets stuck: `stopquest SNDuel_Quest`, then `startquest SNDuel_Quest`. If you're
  still unkillable afterwards: `setessential 7 0`.

## How it works

| Path | What |
|---|---|
| `scripts/SNDuel_Main.psc` | The duel: start, watch, end, clean up. Its header lists the StorageUtil keys |
| `scripts/SNDuel_PlayerAlias.psc` | Cleanup after a reload; outside attackers on the player |
| `scripts/SNDuel_OpponentAlias.psc` | Opponent went down, or was hit by an outsider |
| `spriggit/SkyrimNetDuels/` | The plugin as Spriggit JSON: a quest (Player and Essential Opponent aliases), the confirm box, one global |
| `layer/whyregister.skyrimnet-duels/` | The SkyrimNet layer: `BeginDuel` and `YieldDuel` actions, and a prompt that only renders mid-duel |

- Protection: the NPC sits in an Essential quest alias, so they go into bleedout instead of dying.
  The player is set essential only for the duel. The vanilla brawl faction alone does **not** stop
  weapon damage.
- Afterwards, combat is stopped three times over 4 seconds (once wasn't enough in testing), flags are
  restored, and SkyrimNet gets a narration of the outcome.

## Building

`build.sh` (Git Bash on Windows) compiles the scripts with Caprica, builds the `.esp` from the
Spriggit source, round-trips it back to JSON to catch dropped fields, and zips the result into
`dist/`. It expects to sit two folders below a tools folder inside the game directory
(`<Skyrim>/Tools/projects/SkyrimNetDuels`), with Caprica and Spriggit in that tools folder, Python 3
on PATH, and the game's Papyrus sources (vanilla, SKSE, PapyrusUtil, Papyrus Extender, SkyrimNet)
installed. It only reads the game folder.

## Credits

- SkyrimNet by the SkyrimNet team
- PapyrusUtil by exiledviking; Papyrus Extender by powerofthree
