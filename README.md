# helloforever

Open-source **WoW Forever** addons by James To.

Client: World of Warcraft Forever build **1.60.1** (TOC **16001**).

| Folder | Status | What it does |
|--------|--------|--------------|
| [`HelloForever/`](HelloForever/) | **v0.4.0** (tagged history v0.1.0 → v0.4.0) | Character snapshot / timeline, plus lossless fight capture from Blizzard's `C_DamageMeter` (all meter types, sources, spells, death recaps). Reads when combat ends so chain pulls are not missed. |
| [`HelloAim/`](HelloAim/) | **Proposal only** — see [`HelloAim/PLAN.md`](HelloAim/PLAN.md) | Planned fixed strip of secure action buttons with a non-clickable highlight overlay. Will read Matty7500Hunter / MHP-Hunter-Helper's recommendation and highlight which button to press. **No code shipped yet.** |

Version-by-version HelloForever detail: [`HelloForever/HISTORY.md`](HelloForever/HISTORY.md).

## Install (HelloForever)

1. Clone this repository (or download a release / tag).
2. Copy `HelloForever/` into `World of Warcraft/_forever_/Interface/AddOns/`.
3. Restart the client or `/reload`.
4. Enable **HelloForever** on the character select screen.

## HelloForever slash commands (v0.4.0)

| Command | Effect |
|---------|--------|
| `/hello` | Status / help |
| `/hello snap` | Force a character snapshot |
| `/hello debug` | API / fight-log debug line |
| `/hello fights` | Summarise stored fights |
| `/hello fights read` | Re-read current sessions if available |
| `/hello export` | Fight-log size / budget / trim stats |
| `/hello combatlog on\|off\|auto` | Combat-log helper toggle |

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

Git tags `v0.1.0` … `v0.4.0` mark each addon source tree for reviewers (`git diff v0.3.0 v0.4.0 -- HelloForever`).

### Design notes — fight capture

Forever does not deliver CLEU to addons, and Details' segment writer is disabled.
HelloForever reads `C_DamageMeter` / `C_DeathRecap` after combat when values are
not secret, stores per-day compressed buckets, and expects an **external**
offline pipeline (not in this public repo) to export SavedVariables.

Several v0.4.0 behaviours are still **unverified in-game** (encoding round-trip,
session survival across `/reload`, chain-pull splitting, pets as sources, death
recap fields, Details resets). See HISTORY.md.

## HelloAim (proposal)

See [`HelloAim/PLAN.md`](HelloAim/PLAN.md). Agreed direction: strip just above
the action bar; keyboard with Bindings.xml labels (fallback to the action-bar
key of the same spell); hide MH's suggestion icon while active; no automation —
every cast is a player key press. **Status: proposal, not implemented, for
expert review.**

## Tests

```bash
lua5.1 tests/fights_harness_v4.lua
# optional: python3 tests/verify_lossless.py tests/v4_truth.json /path/to/exported/fights
```

Fixtures use fake names (`FakeHunter` / `TestRealm`).

## Terms of Use note

Assistive UI only. These projects do **not** automate gameplay, send keystrokes,
or cast without player input. Third-party bots / input injectors violate
Blizzard's Terms of Use — do not combine them with these addons.

## License

MIT — see [LICENSE](LICENSE).
