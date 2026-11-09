# helloforever

Open-source **WoW Forever** addons by James To.

Client: World of Warcraft Forever build **1.60.1** (TOC **16001**).

| Folder | Status | What it does |
|--------|--------|--------------|
| [`HelloForever/`](HelloForever/) | **v0.5.0** (tagged history v0.1.0 → v0.4.0) | XP panel and fight history window, character snapshot / timeline, plus lossless fight capture from Blizzard's `C_DamageMeter` (all meter types, sources, spells, death recaps). Reads when combat ends so chain pulls are not missed. |
| [`HelloAim/`](HelloAim/) | **Proposal only** — see [`HelloAim/PLAN.md`](HelloAim/PLAN.md) | Planned fixed strip of secure action buttons with a non-clickable highlight overlay. Will read Matty7500Hunter / MHP-Hunter-Helper's recommendation and highlight which button to press. **No code shipped yet.** |

Version-by-version HelloForever detail: [`HelloForever/HISTORY.md`](HelloForever/HISTORY.md).

## Install (HelloForever)

1. Clone this repository (or download a release / tag).
2. Copy `HelloForever/` into `World of Warcraft/_forever_/Interface/AddOns/`.
3. Restart the client or `/reload`.
4. Enable **HelloForever** on the character select screen.

## What you see in game (v0.5.0)

- **XP panel** — level, XP bar with the rested stretch behind it, XP/hour, time to the
  next level and the last fight (name, length, DPS). At the level cap it shows gold/hour
  and session time instead. Hover for session totals (XP, gold, fights, best fight,
  fight-log size). Drag to move, left-click for the fight history, right-click for the
  menu (lock, scale, chat announcements, combat-log mode, snapshot, reset).
- **Fight history window** (`/hello ui`) — the newest 50 fights; click one for its
  breakdown (top damage spells incl. pet, healing, damage taken by attacker, death recap),
  decoded on demand from the stored record.
- **Addon compartment entry** on clients that have the compartment button: left-click
  opens the fight history, right-click shows / hides the panel.

## HelloForever slash commands (v0.5.0)

| Command | Effect |
|---------|--------|
| `/hello` | Status and the command list |
| `/hello ui` | Fight history window |
| `/hello show` / `hide` | XP panel on / off |
| `/hello lock` / `unlock` | Pin the panel / allow dragging |
| `/hello scale <0.5-2.5>` | Panel size |
| `/hello resetpos` | Put the panel back at the top of the screen |
| `/hello reset` | Restart the session counters (XP/hour, gold, fights) |
| `/hello snap` | Force a character snapshot (queued until combat ends) |
| `/hello fights [n]` | Summarise the last `n` stored fights (default 5) |
| `/hello fights read` | Re-read current sessions if available |
| `/hello levels [n]` | Level-up log: when each level was reached and how long it took |
| `/hello announce on\|off` | One chat line per captured fight (off by default) |
| `/hello export` | Fight-log size / budget / trim stats |
| `/hello budget <MB>` | Fight-log size budget per character (1–20, default 3) |
| `/hello purge <days>` | Drop stored fights older than `<days>` days |
| `/hello combatlog on\|off\|auto` | Combat-log helper toggle |
| `/hello debug` | API / fight-log debug lines |

SavedVariables: `WTF/Account/<account>/SavedVariables/HelloForever.lua`.

### Version timeline (summary)

| Version | Focus |
|---------|--------|
| **0.1.0** | `/hello` + XP/hour frame |
| **0.2.0** | Per-character snapshot + delta timeline + combatlog setting |
| **0.2.1** | Multi-branch collectors, `/hello debug`, live money/gear patches |
| **0.2.2** | Forever Camelot `C_Traits` talent snapshot |
| **0.2.3** | Stamp `addonVersion` + client build into SV / snapshots |
| **0.3.0** | First `C_DamageMeter` fights module (summaries, cap 200) |
| **0.4.0** | Lossless fight log, instant post-combat read, compressed day buckets |
| **0.5.0** | New XP panel + fight history window, session stats, level log; split into modules; cheaper capture; data-loss and stale-snapshot fixes |

Git tags `v0.1.0` … `v0.4.0` mark each addon source tree for reviewers (`git diff v0.3.0 v0.4.0 -- HelloForever`).

### Design notes — fight capture

Forever does not deliver CLEU to addons, and Details' segment writer is disabled.
HelloForever reads `C_DamageMeter` / `C_DeathRecap` after combat when values are
not secret, stores per-day compressed buckets, and expects an **external**
offline pipeline (not in this public repo) to export SavedVariables.

Several capture behaviours are still **unverified in-game** (encoding round-trip,
session survival across `/reload`, chain-pull splitting, pets as sources, death
recap fields, Details resets), and the v0.5.0 UI has only been exercised against the
mock client in `tests/`. See HISTORY.md.

### Layout (v0.5.0)

| File | Role |
|------|------|
| `Core.lua` | Guarded API calls, secret-value scrubbing, timers, SavedVariables root, one event frame, debounce / after-combat queues |
| `Snapshot.lua` | Snapshot collectors, timeline, session counters, level log, combat-log helper |
| `Fights.lua` | Fight log v4 (reader, storage, trim, reports) |
| `UI.lua` | XP panel, tooltip, menu, fight history window, addon compartment hooks |
| `Commands.lua` | `/hello` |

The SavedVariables layout is unchanged from v0.4.0 apart from additive fields, so an
existing export pipeline keeps working.

## HelloAim (proposal)

See [`HelloAim/PLAN.md`](HelloAim/PLAN.md). Agreed direction: strip just above
the action bar; keyboard with Bindings.xml labels (fallback to the action-bar
key of the same spell); hide MH's suggestion icon while active; no automation —
every cast is a player key press. **Status: proposal, not implemented, for
expert review.**

## Tests

```bash
lua5.1 tests/fights_harness_v4.lua      # loads the files listed in the TOC against a mock client
luacheck HelloForever tests             # optional lint (.luacheckrc)
# optional: python3 tests/verify_lossless.py tests/v4_truth.json /path/to/exported/fights
```

The harness covers the fight log (instant read, secrets, chain pulls, resets, recycled
ids, late updates, trim), the snapshot / timeline paths and the UI. Widgets are strict
mocks: a method that does not exist on that widget type fails the run. Fixtures use fake
names (`FakeHunter` / `TestRealm`).

## Terms of Use note

Assistive UI only. These projects do **not** automate gameplay, send keystrokes,
or cast without player input. Third-party bots / input injectors violate
Blizzard's Terms of Use — do not combine them with these addons.

## License

MIT — see [LICENSE](LICENSE).
