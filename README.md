# helloforever

Open-source **WoW Forever** addons by James To.

Client: World of Warcraft Forever build **1.60.1** (TOC **16001**).

| Folder | Status | What it does |
|--------|--------|--------------|
| [`HelloForever/`](HelloForever/) | **v0.19.0** (tags v0.1.0 → v0.5.0) | XP panel and fight history window, character snapshot / timeline, plus lossless fight capture from Blizzard's `C_DamageMeter` (all meter types, sources, spells, death recaps). Reads when combat ends so chain pulls are not missed. Keeps the usual fight against each enemy at your level and compares each new fight with it. The assistant (off by default): a bar of advice cards, and a window with every setting. |
| [`HelloLink/`](HelloLink/) | **v1.19.0** | The live-state strip: one row of coloured squares, 1 pixel high in format 3 (the default since 1.1.0; format 2 since 1.0.0 is 1 pixel too, format 1 is 2 pixels), along the top of the game, which a program outside reads from the screen (the character's live state, no reload). `/hlink strip off` hides it; `/hlink settings` (or the game's AddOns options) has every strip setting without typing. Format and reader: [`docs/STRIP.md`](docs/STRIP.md). Read in the game on 13 Nov 2026 ([results](plan/05-assistant-link.md)). |
| [`HelloAim/`](HelloAim/) | **Proposal only** — see [`HelloAim/PLAN.md`](HelloAim/PLAN.md) | Planned fixed strip of secure action buttons with a non-clickable highlight overlay. Will read Matty7500Hunter / MHP-Hunter-Helper's recommendation and highlight which button to press. **No code shipped yet.** |

Version-by-version HelloForever detail: [`HelloForever/HISTORY.md`](HelloForever/HISTORY.md).

## Install (HelloForever)

1. Clone this repository (or download a release / tag).
2. Copy `HelloForever/` into `World of Warcraft/_forever_/Interface/AddOns/`.
3. Restart the client or `/reload`.
4. Enable **HelloForever** on the character select screen.

## What you see in game (v0.19.0)

- **XP panel** — level, XP bar with the rested stretch behind it, XP/hour, time to the
  next level and the last fight (name, length, DPS). At the level cap it shows gold/hour
  and session time instead. Hover for session totals (XP, gold, fights, best fight,
  fight-log size). Drag to move, left-click for the fight history, right-click for the
  menu (lock, scale, chat announcements, combat-log mode, snapshot, reset, Settings).
- **Settings window** (`/hello settings`, the panel's menu, or the game's AddOns options) —
  every setting and action below without typing: the panel, the fight line, the baseline line
  and emptying it, the combat log file, the fight log's budget, dropping old fights, the
  assistant. Emptying and dropping ask for a second click.
- **Fight history window** (`/hello ui`) — the newest 50 fights; click one for its
  breakdown (top damage spells incl. pet, healing, damage taken by attacker, death recap),
  decoded on demand from the stored record.
- **Addon compartment entry** on clients that have the compartment button: left-click
  opens the fight history, right-click shows / hides the panel.
- **The fight baseline** (`/hello baseline on`, off by default) — after a fight against
  one enemy, one chat line: this fight against the usual fight with that enemy at your
  level (length, damage per second, damage taken, deaths). With HelloLink installed, the
  same numbers go on the live-state strip for a program on your computer.
- **The assistant** (off by default; `/hello assist` opens its window) — a bar under the
  panel shows one card at a time, a line of advice that says what it stands on. The `fight`
  card compares a fight with your usual fight against that enemy; the `target` card shows,
  before a fight, what your fights against the creature you target usually were; the `gold`
  card, after each hour of play, what that hour brought against your usual hour; the `ammo`
  card, when your bags hold fewer than 200 of the ammunition you have on; the `bags` card,
  when 2 bag slots or fewer are free. Hover for the detail,
  right-click to send a card away, left-click for the window. The window has a control for
  every setting: on or off, English or Cantonese, cards from the companion, the muted
  subjects, and a sample card. With HelloLink, a program on your computer can add cards,
  and `/hello ask session` (or the window's button) asks it.

## HelloForever slash commands (v0.19.0)

| Command | Effect |
|---------|--------|
| `/hello` | Status and the command list |
| `/hello ui` | Fight history window |
| `/hello settings` | Settings window: every setting below, without typing |
| `/hello show` / `hide` / `toggle` | XP panel on / off |
| `/hello lock` / `unlock` | Pin the panel / allow dragging |
| `/hello scale <0.5-2.5>` | Panel size |
| `/hello resetpos` | Put the panel back at the top of the screen |
| `/hello reset` | Restart the session counters (XP/hour, gold, fights) |
| `/hello snap` | Force a character snapshot (queued until combat ends) |
| `/hello fights [n]` | Summarise the last `n` stored fights (default 5) |
| `/hello fights read` | Re-read current sessions if available |
| `/hello levels [n]` | Level-up log: when each level was reached and how long it took |
| `/hello announce on\|off` | One chat line per captured fight (off by default) |
| `/hello baseline on\|off\|reset` | After a fight against one enemy, one chat line: this fight against the usual fight with that enemy at your level (off by default); `reset` forgets the kept fights |
| `/hello assist` | The assistant's window |
| `/hello assist on\|off` | The assistant on or off (off by default) |
| `/hello assist list` / `test` | The current cards in chat / a sample card for 30 s |
| `/hello assist lang <code>` | The language of the cards: `en` (default) or `yue` |
| `/hello assist mute <key>` / `unmute <key>` | Keep a subject away for good, or take it back |
| `/hello assist outside on\|off` | Take cards from the companion or not |
| `/hello ask <topic>` | Ask the companion (the topic: `session`) |
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
| **0.9.0** | Keeps the last 10 fights against each enemy at your level (the fight baseline) |
| **0.10.0** | `/hello baseline on`: one chat line per fight, against the usual fight |
| **0.11.0** | The baseline goes on HelloLink's live-state strip (object 12) |
| **0.12.0** | The assistant, step 1: the bar, its window, the `fight` card, in English and Cantonese |
| **0.13.0** | The assistant, step 2: cards from outside through HelloLink 0.2.0, `/hello ask`, strip object 13 |
| **0.13.1** | The assistant's state line while it is off |
| **0.19.0** | Each character's record holds its GUID, so two characters with one first name stay apart |
| **0.18.4** | A character's history goes on in one record when the client gives no realm |
| **0.18.3** | The assistant: a subject taken back from mute shows its standing card at once |
| **0.18.2** | Saved data: a skill line that cannot be read in full is not written with a maximum of 0 |
| **0.18.1** | Saved data: an unknown bag count, bag size, XP or level is not written as a number |
| **0.18.0** | A settings window: every setting without typing |
| **0.17.0** | The assistant's `bags` card |
| **0.16.0** | The assistant's `ammo` card |
| **0.15.0** | The assistant's `gold` card |
| **0.14.0** | The assistant's `target` card |

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

### Layout (v0.19.0)

| File | Role |
|------|------|
| `Core.lua` | Guarded API calls, secret-value scrubbing, timers, SavedVariables root, one event frame, debounce / after-combat queues |
| `Snapshot.lua` | Snapshot collectors, per-section freshness, hunter pet, fight context blobs, profession events, MH observe, timeline, session counters |
| `Fights.lua` | Fight log v4 (reader, storage, trim, reports); stamps pre-pull context hashes on each fight; the fight baseline |
| `UI.lua` | XP panel, tooltip, menu, fight history window, addon compartment hooks |
| `Assistant.lua` | The assistant: cards, the bar, its window, the languages (`docs/specs/115.md`) |
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

The full list of tests, with what a healthy run prints, is in
[`docs/code-standards.md`](docs/code-standards.md) (Commands). The main ones:

```bash
lua5.1 tests/fights_harness_v4.lua      # loads the files listed in the TOC against a mock client
lua5.1 tests/id_freshness.lua           # fight ID, envelope, freshness, quest classify
luacheck HelloForever HelloLink tests   # lint (.luacheckrc)
sh tests/run_all.sh                     # every CI step at once; run it before each push
```

`reader/target/release/hellolink package` (build it with `cargo build --release --locked` in `reader/`) checks that the TOC version, `VERSION_FALLBACK`,
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

## Debugging in the game

- Type `/console scriptErrors 1` once. A Lua error then shows in a pop-up with its file, line and message.
- A change to the content of a `.lua` file that is already installed needs only `/reload`. A new file or a `.toc` change needs a full client restart. How to install each kind of change: `docs/code-standards.md`, "This machine".
- API: <https://warcraft.wiki.gg/wiki/World_of_Warcraft_API>. Events: <https://warcraft.wiki.gg/wiki/Events>.
- An installed addon to read as an example: `Mac-ever` (small and easy to read).

## Terms of Use note

Assistive UI only. These projects do **not** automate gameplay, send keystrokes,
or cast without player input. Third-party bots / input injectors violate
Blizzard's Terms of Use — do not combine them with these addons.

## License

MIT — see [LICENSE](LICENSE).
