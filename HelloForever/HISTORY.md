# HelloForever version history

Precise per-version account derived from the shipped sources (and the tagged
commits in this repository). Client target throughout: **WoW Forever**
build **1.60.1** / TOC **16001**. SavedVariables file: `HelloForever.lua`
(`## SavedVariables: HelloForeverDB`).

## Forever platform limits (all versions)

These are client facts, not HelloForever bugs:

- Addons **never** receive `COMBAT_LOG_EVENT_UNFILTERED` on Forever.
- Many combat-related API values are **secret** while in combat
  (`issecretvalue` / `issecrettable`); readable after combat / restriction lift.
- Details on Forever only skins Blizzard's `C_DamageMeter` UI; its own
  `addSegment` path is disabled (`do return end`), so Details' saved segments
  are empty shells. HelloForever therefore reads `C_DamageMeter` directly
  from v0.3.0 onward.

---

## v0.1.0 — learning stub

**What it does**

- Slash `/hello`: prints player level and zone.
- Small draggable XP/hour frame; session XP tracking on `PLAYER_XP_UPDATE`.
- Resets the XP session counter from the frame / reset path.
- Persists frame position in `HelloForeverDB.pos`.

**Events:** `ADDON_LOADED`, `PLAYER_LOGIN`, `PLAYER_XP_UPDATE`.

**SavedVariables schema:** `{ pos = { point, relativePoint, x, y } }` (plus
runtime XP session state held in memory).

**Limitations**

- No character snapshot, no timeline, no fight data, no combat-log helpers.
- Teaching / UI experiment only.

**Why next version:** Need offline analysis of character state over time, not
just an on-screen XP counter.

---

## v0.2.0 — snapshot + timeline + combatlog toggle

**What it does**

- Keeps the XP/hour UI.
- Per-character store under `HelloForeverDB.characters["Name-Realm"]`.
- Full **snapshot** collectors: stats (incl. `UnitArmor`), equipped gear,
  talents, skills, reputations, quests, money, XP, zone, time played.
- **Timeline** with idle dedupe + delta encoding + periodic keyframes
  (fields: zone, subzone, level, xp, money; cap 2000 entries).
- Settings: `HelloForeverDB.settings.combatLog = "off"|"on"|"auto"` with
  `/hello combatlog …`.
- Slash: `/hello`, `/hello snap`, `/hello reset`, `/hello combatlog …`.

**Events added:** `PLAYER_ENTERING_WORLD`, `PLAYER_LOGOUT`, `PLAYER_LEVEL_UP`,
`ZONE_CHANGED_NEW_AREA`, `TIME_PLAYED_MSG`.

**SavedVariables schema (additions)**

```text
HelloForeverDB = {
  pos, settings = { combatLog },
  characters = {
    ["Name-Realm"] = {
      snapshot = { t, reason, name, realm, class, level, xp, xpMax, money,
                   zone, subzone, stats, equipped, talents, skills,
                   reputations, quests, timePlayed, ... },
      timeline = { {t,last,n,k?,zone?,subzone?,level?,xp?,money?}, ... },
      _tlCount, ...
    }
  }
}
```

**Limitations / known issues**

- Talent collector still assumed classic `GetTalentInfo` / tabs — weak on Forever.
- No `/hello debug` to see which API branch ran.
- No money/equipment live patches (only full snaps / timeline ticks).
- Bag contents are **not** snapshotted (equipped slots only).
- Armour via `UnitArmor` may read **0** on some characters / timings
  (**partially observed; root cause unverified**).
- `/combatlog` behaviour on Forever is **unverified** (no evidence this host
  wrote `WoWCombatLog.txt` during development).

**Why next version:** Need richer collectors, live money/gear patches, and a
debug surface for which Forever APIs actually return data.

---

## v0.2.1 — richer collectors + `/hello debug` + live patches

**What it does (delta from 0.2.0)**

- Multi-branch collectors with `lastApiUsed` tracing (talents / skills /
  reputations / quests try modern `C_*` APIs then classic fallbacks).
- `/hello debug` prints `_apiUsed` so a screenshot shows which branch worked.
- `PLAYER_MONEY` / `PLAYER_EQUIPMENT_CHANGED` → throttled `PatchMoney` /
  `PatchEquipped` without a full snapshot.
- Snapshot validity guard: money==0 AND xp==0 AND xpMax==0 treated as
  invalid (logout wipe / not-yet-ready reads).
- Logout touch + refresh of live fields.

**Events added:** `PLAYER_MONEY`, `PLAYER_EQUIPMENT_CHANGED`.

**Limitations**

- Forever still has **no** classic talent tabs; Branch A (`C_Traits`) was
  incomplete until 0.2.2.
- Same armour / bags / combatlog caveats as 0.2.0.

**Why next version:** Talent snapshots on Forever were empty / wrong without
the Camelot trait-tree walk.

---

## v0.2.2 — Forever Camelot talent / trait tree

**What it does (delta from 0.2.1)**

- Rewrote `collectTalents` for Forever:
  - Config via `C_SpecializationInfo.GetCombatConfigIDForSpecGroup`,
  - Tree / groups via `C_Traits` (`Enum.TraitConfigType.CamelotCombat`),
  - Compact snapshot: tabs (trait groups) + purchased nodes only.
- Kept classic `GetTalentTabInfo` path as Branch B for other flavours.

**Limitations**

- Still no stamp of which addon build produced a SavedVariables file.
- Fight damage still unavailable (Details empty; no CLEU).

**Why next version:** The addon should write its **own version** (and client
build) into the save so offline review does not need a debug screenshot.

---

## v0.2.3 — `addonVersion` + client build stamps

**What it does (delta from 0.2.2)**

- `getAddonVersion()` from TOC metadata (fallback string).
- `getClientInfo()` from `GetBuildInfo` → `{ version, build, date, toc }`.
- `stampVersions(snap)` on every snapshot; also
  `HelloForeverDB.addonVersion` at load.

**Limitations**

- Still no per-fight damage / healing capture.
- Stamps appear in SV only after the next in-game `/reload` with 0.2.3 loaded.

**Why next version:** Need fight metrics. Details cannot provide them on
Forever; Blizzard's `C_DamageMeter` can, after combat when values are not secret.

---

## v0.3.0 — first fights module (`C_DamageMeter`)

**What it does**

- New fights module reading Blizzard meter APIs after combat:
  - `C_DamageMeter.GetAvailableCombatSessions`
  - `GetCombatSessionFromID` / `GetCombatSessionSourceFromID`
  - Respects `issecretvalue` / restriction; wait loop inspired by Details'
    secret-drop wait (no work while in combat).
- Stores compact per-fight records (player damage, duration, DPS, top spells,
  pet damage heuristic, death flag) under `characters[key].fights` (cap 200)
  with duplicate / grow-in-place handling for chained sessions.
- Slash: `/hello fights`.
- Events: `PLAYER_REGEN_ENABLED`, `PLAYER_REGEN_DISABLED` (plus existing).

**SavedVariables additions**

```text
characters[key].fights = {
  { t, name, dur, dmg, dps, spells = {...}, petDmg?, died?, deaths?,
    approx?, mapID?, spellsCut?, ... }, ...
}
-- plus small rolled-up day summaries when trimmed
```

**Limitations / known issues**

- Only a **summary** per fight (not all meter types / all sources / all spells).
- Post-combat delay (wait-for-secret) could miss back-to-back pulls if a new
  fight starts before the previous read finishes.
- Hard cap 200 detailed fights — oldest drop without an external export ack.
- Death recaps not captured.
- Interaction with Details' meter resets → possible gaps (**unverified in
  long sessions**).

**Why next version:** Need **lossless** fight detail, **instant** capture at
combat end, and safe handling of chain pulls / export when full.

---

## v0.4.0 — lossless fight log

**What it does**

- Fight log v4 (`FL_VERSION = 4`):
  - All meter types, all sources, all spells; death recaps via `C_DeathRecap`.
  - Read the **same frame** combat ends when readable; else ≤10 s poll at 0.25 s.
  - Chain-pull safe: session grow → re-read with `rev`; vanished unread → gap record.
  - Work spread across frames (`FL_CALLS_PER_STEP`) to limit hitches.
  - Per-day compressed buckets via `C_EncodingUtil` (JSON → Deflate → Base64),
    ~3 MB/character budget, never trim days newer than `FL_KEEP_DAYS` (7).
  - Compact `fightSummary` ring (~50) for `/hello fights` without decoding all days.
- Slash: `/hello fights [read]`, `/hello export`.
- Also listens for meter events when present:
  `DAMAGE_METER_COMBAT_SESSION_UPDATED`,
  `DAMAGE_METER_CURRENT_SESSION_UPDATED`,
  `DAMAGE_METER_RESET`,
  `ADDON_RESTRICTION_STATE_CHANGED`.

**SavedVariables additions (conceptual)**

```text
characters[key].fightLog = {
  v = 4,
  days = { ["YYYY-MM-DD"] = { enc = "<base64 deflate>", n = N, bytes = B }, ... },
  index = { [fightKey] = day, ... },
  trimmedDays, ...
}
characters[key].fightTrack = { sessions, done, maxDone, resets }
characters[key].fightSummary = { {key,name,dur,dmg,...}, ... }
```

**Unverified in-game (as of publish — needs a real combat + export pass)**

- `C_EncodingUtil` round-trip on real SavedVariables after `/reload`.
- Whether meter sessions survive `/reload` and logout.
- How chain pulls split into sessions on this build.
- Whether pets appear as separate `combatSources`.
- Exact death-recap field shapes returned by Forever.
- Whether Details-initiated `DAMAGE_METER_RESET` causes gaps in practice.
- That 0.2.3 stamps remain present alongside the fight log after mixed play.

**Still open from earlier versions**

- Armour reading 0 on some characters.
- Characters that never logged in this session may have zeroed snapshot fields.
- `/combatlog` usefulness on Forever.

**Why next version:** The capture brief was met, but the addon was one 1,900-line file
with a bare XP box, did avoidable work on hot paths, and had several edge cases that
could lose or duplicate data.

---

## v0.5.0 — UI, modules, cheaper capture, edge-case fixes (current)

**Platform note.** Forever is the modern (12.x) UI architecture under game type
`camelot` (community documentation reports `WOW_PROJECT_ID` 18): secret values, no
combat log for addons, `C_Traits` talents. Per the 12.x secret-value rules, tainted code
may store and pass a secret but arithmetic, comparison, indexing, using it as a key, or
testing a secret boolean throws. API signatures were checked against Blizzard's
generated documentation on the `forever` branch of Gethe/wow-ui-source.

**Structure**

- Split into `Core.lua`, `Snapshot.lua`, `Fights.lua`, `UI.lua`, `Commands.lua`
  (load order in the TOC). One event frame with a handler table replaces the
  `if / elseif` chain; the UI is isolated so a widget failure cannot stop capture.

**What changed in behaviour**

- *Secrets:* every guarded API call drops secret returns, so collectors cannot do
  arithmetic on one. Snapshot work requested in combat (periodic refresh, level-up,
  `/hello snap`) runs about 2 s after combat ends.
- *Bursts:* `PLAYER_MONEY`, `PLAYER_EQUIPMENT_CHANGED` and `ZONE_CHANGED_NEW_AREA`
  keep the leading read and add one trailing read at the end of the 10 s window.
- *Validity guard:* `xp == 0 and xpMax == 0` with money is accepted when the client
  reports a level-capped character; all-zero is still the logout wipe.
- *Time played:* snapshots and the logout touch store the login value plus elapsed
  time instead of the login value.
- *Combat log:* mode `off` leaves logging alone at login and logout; `/hello combatlog
  off` still switches it off.
- *Timeline:* trimming cuts forward to the next keyframe. Lists are trimmed in batches.

**Fight log (record format v4 unchanged)**

- Re-read rules. A stored session is read again when its length changed by more than
  0.5 s (longer as before; shorter is new) or when `DAMAGE_METER_COMBAT_SESSION_UPDATED`
  named it after the read. The re-read is stored as the next `rev` only if its
  fingerprint or length changed; three empty re-reads stop the retries for that session.
- Recycled ids. A re-read is a different fight, stored under a new key (`rekeyOf` names
  the key it did not overwrite), when either
  - the **player's own** damage done, healing done or damage taken went *down*
    (session-wide totals are not used, since another source's row can go away, and a
    meter type that failed on this read is not compared), or
  - the id had left the client's session list and came back with other content
    (numbering restarted at a relog, including a restart at the very same id).
  A shorter length alone is a correction of the same fight. A different name is a
  different fight, as before. If the meter announced a new session
  (`DAMAGE_METER_CURRENT_SESSION_UPDATED`) the old marker is dropped at once and the new
  fight keeps its event-stamped start; otherwise `startApprox = true`.
- An empty session list no longer counts as "numbering restarted" on its own: the
  markers survive it, and every session that comes back is read once and compared
  (identical: nothing stored; different: a new fight).
- A re-read in which a meter type failed that the stored record has is not written over
  the good record. It is retried after 5 s, and stored as it is only on the third such
  read, so a type that keeps failing cannot hold the queue.
- A half-read record is dropped when combat starts again and planned afresh afterwards.
- Reader errors are retried on the next frame (three strikes per record, as before).
- `HasRecapEvents` returning a secret boolean now waits like any other secret.
- Deflate uses `Enum.CompressionLevel.OptimizeForSize`, falling back to the default
  level if the client rejects the argument. Blobs stay `d1:` / `j1:` / table.
- `fightLog.bytes` is kept by deltas; `fightTrack.done` entries are forgotten an hour
  after their session leaves the client list; `fightLog.trimmed` keeps the newest 120 days.
- Budget is `settings.budgetMB` (1–20, default 3); `/hello purge <days>` drops old days
  on request (receipt in `trimmed` with `how = "purge"`); under 7 days it needs `force`.

**UI**

- XP panel (`HelloForeverFrame`): see README. Position still in `HelloForeverDB.pos`.
- Fight history window (`HelloForeverFights`), built on first use; records are decoded
  only for the fight being viewed.
- Right-click menu via `MenuUtil.CreateContextMenu` when present.

**SavedVariables additions**

```text
HelloForeverDB.settings += { shown, locked, scale, announce, budgetMB }
characters[key].levels = { { level, t, played, took }, ... }        -- cap 100
characters[key].fightTrack.done[sid] += { sig, mono = { d?, h?, t? }, errs?, stale?, gone?, back?, bad?, badAt? }
characters[key].fightTrack.sessions[sid] += { dirty?, re? }
characters[key].fightLog.trimmed[day] += { how? }
characters[key].fightLog += { trimmedDropped? }
record += { rekeyOf? }
```

**Measured on the mock client** (same eight-fight scenario, `tests/`): `pcall` calls
11,977 → 567, `UnitName` calls 50 → 5; stored records identical to v0.4.0 field for
field apart from `addonVersion`.

**Unverified in-game (in addition to the v0.4.0 list)**

- Every widget call in `UI.lua` (checked only against strict mocks).
- `MenuUtil`, the addon compartment TOC hooks and `IconTexture` / `Category` on Forever.
- Whether `DAMAGE_METER_COMBAT_SESSION_UPDATED` fires for a session after combat ends
  (the late-update re-read depends on it; harmless if it never does).
- Whether the client ever revises a finished session's own-player totals downward, or
  changes a finished session while it is briefly missing from the list. If it does,
  that fight would be filed a second time under a new key (tagged `rekeyOf`).
- `Enum.CompressionLevel.OptimizeForSize`: there is a fallback if the call throws, none
  if the client silently ignores the level; its size / time effect on real records.
- `IsPlayerAtEffectiveMaxLevel` / `GetMaxLevelForPlayerExpansion` on Forever (if neither
  works, a capped character is rejected as in v0.4.0).
- Addon compartment callback signatures and `MenuUtil` radio / checkbox callbacks.
