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

## v0.6.0 — schema envelope, fight IDs, freshness, pet, fight context

**Version / export envelope**

- `## Version: 0.6.0` in the TOC; `ns.VERSION_FALLBACK`, `ns.SOURCE_REVISION`
  (`"0.6.0"`) and `ns.SCHEMA_VERSION` (6) live in `Core.lua` and **must** match
  at release. Runtime version still comes from `GetAddOnMetadata`.
- `ns.ExportMeta` stamps every snapshot, fight/gap record and the SV root with
  `addonVersion`, `sourceRevision`, `schemaVersion`, `gameBuild` (`GetBuildInfo`
  return 2) and `client` `{ version, build, date, toc }`.
- `HelloForeverDB.installId`: 8 lowercase hex chars, created once.

See [`docs/SCHEMA.md`](../docs/SCHEMA.md) for the canonical export schema.

**Fight IDs**

- Generator: `ns.MakeFightKey` → `hf1-<installId>-<unixStart>-<sid>-<seq>`.
- Parser: `ns.ParseFightKey` also accepts legacy `unix-sid` and `unix-sid-n`.
- Gap records use the same generator. Old keys already in `fightLog.index`
  are left as they are.

**Freshness / quests**

- `snapshot.freshness.<section> = { observedAt, status }`.
- `quests` is now `{ log, completed, abandoned }` (breaking vs 0.5.0 array;
  importers must branch on `schemaVersion`).
- Verified against warcraft.wiki.gg: Forever `C_QuestLog.GetInfo` has no
  `isComplete`; turn-in uses `IsQuestComplete` / objectives; history uses
  `C_QuestLog.IsQuestFlaggedCompleted` / `GetAllCompletedQuestIDs`.

**Hunter pet**

- `collectPet`: `kind` hunter / temporary / minion / none from `HasPetUI` +
  `UnitExists("pet")`. Abilities from `C_SpellBook.HasPetSpells` (Forever) or
  `HasPetSpells` (Classic); autocast from `GetPetActionInfo`. Happiness /
  training points / XP from the Classic globals; `"unknown"` if absent.
- Not used: `C_StableInfo`, `C_PetJournal` (not Classic-era).

**Fight context / professions / MH**

- `RememberContext` stores up to 40 hashed gear/talent/pet blobs; a patch
  re-hashes only the part that changed (`RememberContext("gear")`).
  `FightsCombatStart` copies the three ids (O(1), no snapshot APIs) and
  samples MH read-only (`IsAddOnLoaded` + `lastDecision` copy; no MH methods).
  `FightsSeen` hangs that stamp on the tracked session (`fightTrack.sessions[sid]
  .ctx` / `.mh`), so the record built later uses the stamp of its own pull.
- `PatchTalents` on `TRAIT_CONFIG_UPDATED` / `PLAYER_TALENT_UPDATE` /
  `CHARACTER_POINTS_CHANGED` keeps the talents hash current between snapshots.
- Events: `skill_up`, `profession_cast`, `profession_loot` on the existing
  `events` ring. Cast/loot handlers no-op in combat. Spell names are matched
  exactly against the skill lines (plus four gathering aliases).
- `SampleMH`: read-only globals / SV through `rawget`, under `pcall`; never
  calls MH methods or runs its metamethods.

**Self-test and save size**

- `ns.eventLog[event]`: `false` when `RegisterEvent` refused the event, else the
  number of times it fired. `/hello selftest` (Commands.lua) prints it with a
  list of API probes and the per-section freshness of a fresh snapshot, and
  stores the result in `HelloForeverDB.selftest`.
- `ns.ExportMeta(dest, slim)`: fight and gap records pass `slim` and carry no
  `client` table. `collectSkills` rows are `{ name, rank, max, id?, cat? }`.

**Quest bookkeeping**

- `collectQuests(prevQ, full)`: the turned-in history is copied on a full
  snapshot, when a quest leaves the log, or when a late completed flag is seen;
  otherwise the previous list is reused. `questWatch` holds the log of the last
  read; a quest missing from the log is `abandoned` only if `turnedIn(id)` is
  exactly `false`.

---

## v0.5.0 — UI, modules, cheaper capture, edge-case fixes

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

**Known limitations of the re-read rules (from review, left as they are)**

- After a relog, if combat starts before the first read (the 3 s catch-up) and the
  client sends no `DAMAGE_METER_CURRENT_SESSION_UPDATED` for the new fight, a fight on
  a reused id with the same name is taken for an update of the old session and can be
  stored over the earlier record. Same as v0.4.0.
- A session that left the list, came back, and then fails to read three times is filed
  a second time (tagged `rekeyOf`) with the error in it.
- A marker written by v0.4.0 has no fingerprint; if that very session left the list and
  came back unchanged it would be filed again. It needs the session to survive the
  client restart that installing the new files requires.
- Sessions cooling off after a failed re-read share one retry timer; a second one may
  wait for the next trigger. Its good record is kept meanwhile.

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

## v0.7.0 — what a pull cost and used

- `Fights.lua`: one pull-stats table per pull (`PLAYER_REGEN_DISABLED` to
  `PLAYER_REGEN_ENABLED`), shared by every session that starts in it, the same way as the
  context stamp. `vitals()` reads `UnitXP`, `UnitXPMax`, `UnitLevel`, `UnitHealth(Max)`,
  `UnitPower(Max)` for the player and `UnitHealth(Max)` for the pet at both events.
  `targetNow()` reads the target at the first. `UNIT_SPELLCAST_SUCCEEDED` (player and pet)
  increments a counter; out of combat the last 8 player casts are remembered so that a cast
  within 3 s before combat is counted as the opener.
- The read marker of a stored fight keeps the block, so a later revision read after the
  tracked session was forgotten still has it.
- `record.spellNames` is filled when the record is read, through `ns.SpellName`.
- Format: [`../docs/SCHEMA.md`](../docs/SCHEMA.md), "Pull stats".

**Untested in the game (0.7.0):**

- Whether `UnitHealth`, `UnitPower` and `UnitLevel("target")` return plain numbers at
  `PLAYER_REGEN_DISABLED` and `PLAYER_REGEN_ENABLED`. If they are secret, those fields are
  absent and nothing else changes.
- Whether the XP of the kill has arrived by `PLAYER_REGEN_ENABLED`. If it arrives later,
  `stop.xp` is short by that kill and the next pull's `start.xp` shows it.
- Whether Auto Shot and pet abilities fire `UNIT_SPELLCAST_SUCCEEDED` on this client.
- Whether the mob that was pulled is still the target when combat starts (a pet pull or a
  mob that attacks first gives another target, or none).

## v0.7.1 — a reset no longer makes read fights look new

- `Fights.lua`: `markDoneGone` replaces the two places that emptied `fightTrack.done`
  (`FightsMeterReset`, and the "ids went backwards" branch of `plan`). Markers get `gone`
  and so take the existing "left the list and came back" path: re-read, compare by
  signature, store only what differs.
- `fingerprint(rec)` (a djb2 hash over the whole meter content in canonical order, rates left
  out) is stored on the read marker as `fp`. On the "came back" path a record is "nothing
  new" only when its fingerprint equals the marker's; without one it is stored under its own
  key. `markDoneGone` also clears `stale` and schedules `expireDone`.
- `tests/fights_harness_more.lua` splices extra sections (16f to 16h) into the harness, which
  holds the fix's failing test and stays as committed.
- The mock client used to empty its session list together with `DAMAGE_METER_RESET`. The
  real client does not: harness section 16e models a reset with the list intact.

**Untested in the game (0.7.1):** which of the two branches fires at login was not
observed directly (`fightTrack.resets` was 8, which points at the reset event). Both now
keep the markers. The check is in `plan/01-in-game-verification.md`, section 2.

## v0.8.0 — opt-in reload when AFK (did not work; removed in 0.8.1)

- New setting `afkReload` (`/hello afkreload on|off`, default off). On `PLAYER_FLAGS_CHANGED`
  for `"player"` with `UnitIsAFK("player")` true, the addon prints a warning, waits 5 s, checks
  again that the player is AFK and out of combat, and calls `ReloadUI` (or `C_UI.Reload`)
  inside `pcall`. The reload makes the client write SavedVariables; the usual `PLAYER_LOGOUT`
  snapshot runs first.
- At most one reload in 600 s (`HelloForeverDB.afkReloadAt`, Unix time of the last one), so
  a client that reports AFK again after loading cannot loop.

**SavedVariables additions**

```text
HelloForeverDB.settings += { afkReload }
HelloForeverDB.afkReloadAt = <unix time>      -- absent until the first AFK reload
```

**Untested in the game (0.8.0):** whether this client fires `PLAYER_FLAGS_CHANGED` for AFK
and whether it lets an addon reload from a timer (no key press). Harness section 29b
assumes both. The check is in `plan/01-in-game-verification.md`, section 9.

## v0.8.1 — the reload when AFK is removed (current)

- Forever refuses `ReloadUI` outside a hardware event: the call from the `C_Timer` callback
  raised "Interface action failed because of an AddOn" and `pcall` returned without an error
  (seen with `/hlink reloadtest`, 12 Nov 2026). The 0.8.0 handler, the `afkReload` default
  and the help line are deleted. `/hello afkreload` prints why.
- `HelloForeverDB.settings.afkReload` and `HelloForeverDB.afkReloadAt` are legacy keys: not
  read, not written, not removed from a file that has them.
