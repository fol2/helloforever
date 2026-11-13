# helloforever

Open-source **WoW Forever** addons by James To.

Client: World of Warcraft Forever build **1.60.1** (TOC **16001**).

| Folder | Status | What it does |
|--------|--------|--------------|
| [`HelloForever/`](HelloForever/) | **v0.8.1** (tags v0.1.0 → v0.5.0) | XP panel and fight history window, character snapshot / timeline, plus lossless fight capture from Blizzard's `C_DamageMeter` (all meter types, sources, spells, death recaps). Reads when combat ends so chain pulls are not missed. |
| [`HelloLink/`](HelloLink/) | **v0.1.0** | The live-state strip: one row of coloured squares, 2 pixels high, along the top of the game, which a program outside reads from the screen (the character's live state, no reload). `/hlink strip off` hides it. Format and reader: [`docs/STRIP.md`](docs/STRIP.md). Built, not yet accepted in the game. |
| [`HelloAim/`](HelloAim/) | **Proposal only** — see [`HelloAim/PLAN.md`](HelloAim/PLAN.md) | Planned fixed strip of secure action buttons with a non-clickable highlight overlay. Will read Matty7500Hunter / MHP-Hunter-Helper's recommendation and highlight which button to press. **No code shipped yet.** |

Version-by-version HelloForever detail: [`HelloForever/HISTORY.md`](HelloForever/HISTORY.md).

## Install (HelloForever)

1. Clone this repository (or download a release / tag).
2. Copy `HelloForever/` into `World of Warcraft/_forever_/Interface/AddOns/`.
3. Restart the client or `/reload`.
4. Enable **HelloForever** on the character select screen.

## What you see in game (v0.8.1)

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

## HelloForever slash commands (v0.8.1)

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
| `/hello purge <days>` | Drop stored fights older than `<days>` days (under 7 days needs `force`, as those may not be exported yet) |
| `/hello combatlog on\|off\|auto` | Combat-log helper toggle |
| `/hello debug` | API / fight-log debug lines |
| `/hello selftest` | Which client events and APIs the addon found on this client, and which snapshot sections it could read. Run it after playing a few minutes on a new client build; the result is also saved to SavedVariables |

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
| 0.6.0 | Version/schema envelope on every export; unique fight IDs; per-section freshness; quest states; hunter pet; fight context + profession events |
| 0.7.0 | What a pull cost and used, on every fight: XP, health, mana and pet health before and after, the target's name / level / classification, cast counts for the player and the pet, and the names of the spells in the record |
| **0.7.1** | Fix: fights the client still lists after a meter reset (every login) are no longer filed a second time |
| **0.8.0** | Opt-in `/hello afkreload`: reload the UI once when you go AFK, so the saved data reaches the disk |
| **0.8.1** | Removed `/hello afkreload`: the client refuses a reload without a key press, so it could not work |

Git tags `v0.1.0` … `v0.4.0` mark each addon source tree for reviewers (`git diff v0.3.0 v0.4.0 -- HelloForever`).

### Design notes — fight capture

Forever does not deliver CLEU to addons, and Details' segment writer is disabled.
HelloForever reads `C_DamageMeter` / `C_DeathRecap` after combat when values are
not secret, stores per-day compressed buckets, and expects an **external**
offline pipeline (not in this public repo) to export SavedVariables.

Several capture behaviours are still **unverified in-game** (encoding round-trip,
session survival across `/reload`, chain-pull splitting, pets as sources, death
recap fields, Details resets), and the UI has only been exercised against the
mock client in `tests/`. See HISTORY.md.

### Layout (v0.8.1)

| File | Role |
|------|------|
| `Core.lua` | Guarded API calls, secret-value scrubbing, timers, SavedVariables root, one event frame, debounce / after-combat queues |
| `Snapshot.lua` | Snapshot collectors, per-section freshness, hunter pet, fight context blobs, profession events, MH observe, timeline, session counters |
| `Fights.lua` | Fight log v4 (reader, storage, trim, reports); stamps pre-pull context hashes on each fight |
| `UI.lua` | XP panel, tooltip, menu, fight history window, addon compartment hooks |
| `Commands.lua` | `/hello` |

Export schema (envelope, fight ID, snapshot sections) is documented in
[`docs/SCHEMA.md`](docs/SCHEMA.md). `schemaVersion` 6 is additive on the fight-log
encoding (`FL_VERSION` stays 4) but changes fight keys and the quests object.

## HelloAim (proposal)

See [`HelloAim/PLAN.md`](HelloAim/PLAN.md). Agreed direction: strip just above
the action bar; keyboard with Bindings.xml labels (fallback to the action-bar
key of the same spell); hide MH's suggestion icon while active; no automation —
every cast is a player key press. **Status: proposal (revision 4), not
implemented.** Revision 3 found that Matty7500Hunter already glows the
action-bar button to press, so the next step is a trial of MH alone before any
HelloAim code is written; open decisions are listed in the plan.

## Tests

```bash
lua5.1 tests/fights_harness_v4.lua      # loads the files listed in the TOC against a mock client
lua5.1 tests/id_freshness.lua           # fight ID, envelope, freshness, quest classify
luacheck HelloForever tests             # lint (.luacheckrc)
# optional: python3 tests/verify_lossless.py tests/v4_truth.json /path/to/exported/fights
```

`python3 tools/package.py` checks that the TOC version, `VERSION_FALLBACK`,
`SOURCE_REVISION` and the changelog agree, runs the tests and builds
`dist/HelloForever-<version>.zip` with SHA-256 sums (`--check` for the checks alone).
Work that still needs the game client or more GitHub access is listed in [`plan/`](plan/).

The harness also writes the SavedVariables file a client would save (second
argument, default `tests/HelloForever_v4_SV.lua`, git-ignored). The offline pipeline keeps
a copy as its contract fixture, so regenerate that copy when the export changes.

The harness covers the fight log (instant read, secrets, chain pulls, resets, recycled
ids, length corrections, failed reads, late updates, trim), the snapshot / timeline paths and the UI. Widgets are strict
mocks: a method that does not exist on that widget type fails the run. Fixtures use fake
names (`FakeHunter` / `TestRealm`).

## Terms of Use note

Assistive UI only. These projects do **not** automate gameplay, send keystrokes,
or cast without player input. Third-party bots / input injectors violate
Blizzard's Terms of Use — do not combine them with these addons.

## License

MIT — see [LICENSE](LICENSE).
