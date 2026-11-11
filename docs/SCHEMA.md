# HelloForever export schema

Canonical contract for the offline pipeline (`fol2/wow-data`) and for this
addon. **schemaVersion 6** ships with addon **0.6.0**.

Client: WoW Forever 1.60.1 / TOC 16001. Fight-log *encoding* is still
`fightLog.v = 4` (`FL_VERSION`: JSON → Deflate → Base64). `schemaVersion` is
the *data* envelope and field meanings.

This repository is public: examples use fake names (`FakeHunter` / `TestRealm`)
only.

---

## Export envelope (every snapshot, fight, gap, and the SV root)

Required fields, set by `ns.ExportMeta`:

| Field | Type | Source |
|-------|------|--------|
| `addonVersion` | string | TOC `## Version` (fallback `ns.VERSION_FALLBACK`, must equal the TOC at release) |
| `sourceRevision` | string | `ns.SOURCE_REVISION` — constant bumped at each release (may equal `addonVersion`) |
| `schemaVersion` | number | `ns.SCHEMA_VERSION` — **6** for this document |
| `gameBuild` | string | `select(2, GetBuildInfo())` (the client build, e.g. `"70862"`) |
| `client` | table | `{ version, build, date, toc }` from `GetBuildInfo` (all four returns) |
| `installId` | string | 8 lowercase hex chars, unique per SavedVariables file / machine |

`HelloForeverDB` carries the same envelope at the root so a pipeline that only
reads the file header still sees the version.

Pattern for `installId`: `^[0-9a-f]{8}$`.

---

## schemaVersion history

| schemaVersion | Addon | Notes |
|---------------|-------|--------|
| (none / implicit 4–5) | 0.4.0–0.5.0 | `addonVersion` + `client` on snapshots; fight key `{unix}-{sid}` optionally `-{n}` |
| **6** | **0.6.0** | Envelope above on every export. Fight ID format below. Per-section freshness. Quest states. Hunter pet. Fight context hashes. Profession events. MH observe. |

Importers **must** branch on `schemaVersion` (and still accept records that
only have `addonVersion`, as 0.5.0 files do).

---

## Fight ID

Field: `key` on each fight / gap record (also `fightLog.index` keys and
`fightSummary[].key`).

### Current format (`schemaVersion` ≥ 6, all newly written keys)

```
hf1-<installId>-<unixStart>-<sessionId>-<seq>
```

| Part | Meaning |
|------|---------|
| `hf1` | Format version. Not a suffix on the old two-part id. |
| `installId` | 8 lowercase hex chars from `HelloForeverDB.installId` (one random id per SavedVariables file, so two Macs / two WTF folders never collide) |
| `unixStart` | Fight start, unix seconds (`record.start`) |
| `sessionId` | `C_DamageMeter` session id (`record.sid`) |
| `seq` | Collision counter, **always present**, starting at `1`. A second fight that would share the other three fields gets `2`, `3`, … |

**PCRE (new keys only):**

```
^hf1-[0-9a-f]{8}-\d+-\d+-\d+$
```

Examples (fake data):

```
hf1-a1b2c3d4-1794211200-1-1
hf1-a1b2c3d4-1794211200-1-2
```

`seq` is a required fifth field, not an optional dash-suffix on
`{unix}-{sid}`. That old suffix form (`1794211200-1-2`) is what the
wow-data importer previously rejected.

Addon constant: `ns.FIGHT_KEY_PCRE` is the combined importer pattern below.

### Legacy keys (already stored by 0.4.0 / 0.5.0 — never rewritten)

```
<unixStart>-<sessionId>          e.g. 1794211200-1
<unixStart>-<sessionId>-<n>      e.g. 1794211200-1-2   (old collision suffix)
```

**PCRE (legacy only):**

```
^\d+-\d+(?:-\d+)?$
```

### Combined importer pattern (accept both)

```
^(?:hf1-[0-9a-f]{8}-\d+-\d+-\d+|\d+-\d+(?:-\d+)?)$
```

Lua: `ns.ParseFightKey(key)` returns:

```text
{ format = "hf1"|"legacy"|"legacy_suffix",
  installId? = "<8 hex>",   -- hf1 only
  start = number, sid = number, seq = number }
```

or `nil` if the string is not a fight id.

Gap records use the same `hf1-…` generator (`uniqueKey`). A record's `rev`
is a revision of the **same** key (same fight grown / corrected), not a new
id. A recycled session id that is a different fight gets a new key
(`rekeyOf` names the one it did not overwrite), still in `hf1-…` form.

Lua 5.1 does not have a CSPRNG; `installId` is a 32-bit hash of `time()`,
`GetTime()`, the profiler clock, two `math.random` draws and the address of a
fresh table. The shared RNG is never reseeded. Collision across independent
installs is the 32-bit birthday bound (about 2^16 installs for a 50% chance;
two Macs are fine).

A SavedVariables file that is synchronised between machines carries its
`installId` with it: the id names the file, not the hardware. Fights still
cannot collide, because the key also holds the start second and session id.

### Integrity rules for importers

- A stored record carries its own `key`; it must equal the key it is filed
  under in `fightLog.days[day].keys`. A mismatch means the two lists are out of
  step: do not export that record under either name.
- `start` and `sid` inside the key equal `record.start` / `record.sid`.
- Blob prefixes are `d1:` (Base64 of raw Deflate of JSON) and `j1:` (JSON
  text). Anything else is not a fight blob of this fight-log version.

---

## Snapshot freshness

Each section has `snapshot.freshness.<name> = { observedAt, status }`.
`status` is `ok` | `unavailable` | `stale`. `observedAt` is unix seconds of
the last **successful** read of that section. Patching gold does not bump
gear / quests / talents / pet.

- `ok`: read just now.
- `stale`: the value is carried over from an earlier read; `observedAt` is
  that earlier time (for a section carried over from a pre-0.6.0 snapshot, the
  old snapshot's `t`).
- `unavailable`: the client has no API for it, or it was never read. A section
  that was never read has **no** `observedAt`.

| Section | Snapshot fields | Notes |
|---------|-----------------|--------|
| `level` | `level`, `xp`, `xpMax`, `rested` | |
| `gold` | `money` | `PLAYER_MONEY` → `PatchMoney` |
| `gear` | `equipped` | slot name → item link |
| `bags` | `bags` | occupied slots `{ bag, slot, id, count, link }`; bags 0–NUM_BAG_SLOTS; not bank. Refreshed on `BAG_UPDATE_DELAYED` (`BAG_UPDATE` where that event does not exist) |
| `stats` | `stats` | |
| `talents` | `talents` | re-read on `TRAIT_CONFIG_UPDATED` / `PLAYER_TALENT_UPDATE` / `CHARACTER_POINTS_CHANGED` as well as on full snapshots |
| `professions` | `skills` | |
| `reputation` | `reputations` | |
| `quests` | `quests` | object, see below (was an array in 0.5.0) |
| `pet` | `pet` | hunter pet; `unavailable` until collected |
| `zone` | `zone`, `subzone` | |
| `timePlayed` | `timePlayed` | `ok` only once `TIME_PLAYED_MSG` has arrived this session; values kept from the previous snapshot are `stale` |

`snapshot.t` is the last write to **any** section (UI / logout). Importers
must use `freshness.*.observedAt`, not `t`, to decide if a section is current.

---

## Quests (`schemaVersion` 6)

`C_QuestLog.GetInfo` on Forever 1.60.1 **does not include `isComplete`**
(warcraft.wiki.gg). v0.5.0 treated the missing field as `complete = false`.
v0.6.0 never guesses that.

```text
quests = {
  log = {
    { id, title, level, state, objectives = { { text, type, finished, have?, need? } } },
    ...
  },
  completed = { questID, ... } | nil,   -- turned-in history, ascending; nil = no history API
  completedTotal = number | nil,        -- ids the client reported; > #completed when capped (4000)
  abandoned = { { id, title, observedAt }, ... },  -- cap 40
}
```

`have` / `need` come from `numFulfilled` / `numRequired`, or from the `3/8` in
the objective text when the API gives no counts.

The 0.5.0 shape, which importers still meet in older files, is a plain array
of `{ questID, title, level, complete }`. On Forever `complete` was always
`false` there (the missing `isComplete` field), so a 0.5.0 `complete = false`
says nothing: the quest is in the log, state `unknown`.

`state` (string):

| Value | Meaning | How it is decided |
|-------|---------|-------------------|
| `accepted` | In the log, no objective progress | objectives exist, none finished and none moved; or `isComplete == false` |
| `in_progress` | In the log, some progress | an objective is finished or has `have > 0`, but not all are finished |
| `ready` | In the log, ready to turn in | `IsQuestComplete` / `C_QuestLog.IsComplete` true, or `GetQuestLogTitle` isComplete `1`, or all objectives finished |
| `failed` | In the log, failed | isComplete `-1` |
| `completed` | Turned in (history, not in log) | `C_QuestLog.IsQuestFlaggedCompleted` / `GetAllCompletedQuestIDs` / `GetQuestsCompleted` |
| `abandoned` | Was in the log at the last read, is not now, and the client says it was **not** turned in | `questWatch` diff + `IsQuestFlaggedCompleted` / history list |
| `unknown` | In the log but complete flag and objectives are missing | **not guessed** |

Objectives are counted as finished / not finished. Kill counts are never
summed across objectives (`10/10` boars plus an unfinished "speak with X" is
`in_progress`, not `ready`).

`abandoned` rules:

- An entry is written only when the client answers "not completed" for that
  quest id. A quest with no id, or a client with no history API, is left out
  rather than guessed.
- An entry is removed again when the quest is back in the log or later shows
  up as turned in (the completed flag can arrive after the quest has left the
  log). The list therefore means "left the log without a turn-in and has not
  come back", newest last.

- A repeatable quest is never flagged completed by the client. A quest id seen
  in `QUEST_TURNED_IN` this session counts as turned in, so handing one in is
  not recorded as an abandon. (If that event does not exist on the client, a
  repeatable turn-in is still listed as abandoned.)

The turned-in history is copied on a full snapshot and whenever a quest leaves
the log, not on every `QUEST_LOG_UPDATE`.

`GetQuestsCompleted` is Classic-era (1.13.2). Forever documents
`C_QuestLog.GetAllCompletedQuestIDs` and `C_QuestLog.IsQuestFlaggedCompleted`.
`C_QuestLog.IsComplete` is **not** listed for Forever; `IsQuestComplete` is
Classic-era. Both are tried; if neither exists, progress comes from
`GetQuestLogLeaderBoard` / `C_QuestLog.GetQuestObjectives`.

---

## Hunter pet

`snapshot.pet`. Only Classic-era APIs (and Forever's documented replacements
of those APIs: `C_SpellBook.HasPetSpells` for `HasPetSpells`).
**Not used:** `C_PetJournal`, `C_StableInfo` (not Classic-era).

```text
pet = {
  kind = "hunter" | "temporary" | "minion" | "none",
  name, family, familyId, level,          -- or "unknown"
  happiness, happinessDamagePct, loyaltyRate,  -- GetPetHappiness; or "unknown"
  training = { total, spent } | "unknown",     -- GetPetTrainingPoints
  xp = { curr, next } | "unknown",             -- GetPetExperience
  hasUI, isHunterPet,                          -- HasPetUI
  abilities = { { name, rank, spellID, autocast, slot, sub? } },
  icon,
}
```

| `kind` | Rule (not guessed) |
|--------|-------------------|
| `hunter` | `HasPetUI()` second return is true (permanent hunter pet) |
| `minion` | pet UI present, not a hunter pet (e.g. warlock) |
| `temporary` | `UnitExists("pet")` and no pet UI (e.g. Summon Hawk) |
| `none` | no pet |
| section `unavailable` | `HasPetUI` and `UnitExists` both missing |

`rank` and `autocast` are `"unknown"` when the spellbook / `GetPetActionInfo`
does not provide them. Growl autocast comes from `GetPetActionInfo` (Forever
+ Classic).

---

## Fight context (pre-pull gear / talents / pet)

Fights do **not** copy full gear. They store hashes captured at
`PLAYER_REGEN_DISABLED` (table copies of ids only; no snapshot APIs in combat):

```text
record.context = { gear = "g-<8 hex>", talents = "t-<8 hex>", pet = "p-<8 hex>", approx? }
characters[key].contextBlobs[id] = { kind, t, data }   -- cap 40, LRU
characters[key].contextIds = { gear, talents, pet }    -- latest
characters[key].fightTrack.sessions[sid].ctx / .mh     -- the stamp of a session not read yet
```

`data` is the compact snapshot (equipped slots, purchased talent nodes, pet
summary). Two fights with the same gear share one blob. If a blob was trimmed,
the fight still has the hash. A hash is 32-bit djb2 with a `g-` / `t-` / `p-`
prefix: an identifier, not a checksum to trust across characters.

The stamp is kept per session, taken when the session is first seen (the pull
that starts it). A fight that is read late (a chain pull, a read blocked by
secret values, a `/reload` before the read) therefore still carries the
context it was pulled with, not the latest one.

A session the meter announces just before `PLAYER_REGEN_DISABLED` takes the
hashes of that moment, and the MH sample of the pull that follows.

`context.approx = true` (and `mh.approx = true`) in two cases only:

- the addon never saw the session start (a catch-up read): the hashes and the
  MH sample are those at read time;
- the record is a different fight found on a recycled session id that the
  client never announced (`rekeyOf` is set and `startApprox` is true): it gets
  the stamp of the latest pull, which is most likely its own.

---

## Profession events

Appended to `characters[key].events` (existing cap 500):

| `kind` | When | Fields |
|--------|------|--------|
| `skill_up` | `CHAT_MSG_SKILL` or `SKILL_LINES_CHANGED` rank diff (the same rank is logged once) | `skill`, `rank`, `from?` (or `raw` if the chat line matched neither the client's `SKILL_RANK_UP` format nor the English text) |
| `profession_cast` | `UNIT_SPELLCAST_SUCCEEDED` by the player, **out of combat**, whose spell name **equals** a skill line the character has (`Fishing`, `Mining`, `Skinning`) or is one of `Herb Gathering` → `Herbalism`, `Smelting` → `Mining`, `Disenchant` → `Enchanting`, `Pick Lock` → `Lockpicking` | `skill`, `spellID`, `spell` |
| `profession_loot` | `CHAT_MSG_LOOT` / `CHAT_MSG_TRADESKILLS` within 3 s of a profession cast, **out of combat** | `skill`, `item`, `spellID` |

In-combat `UNIT_SPELLCAST_SUCCEEDED` / loot are ignored (Auto Shot would
otherwise flood). Spell names are matched exactly, never as substrings: the
skill list also holds class lines (`Arcane`, `Fire`, `Beast Mastery`), and a
substring match would log every `Arcane Shot`. Crafts whose spell is named
after the item made are not recognised as profession casts.

---

## Matty Hunter (MH) observe

HelloForever **never writes** to Matty7500Hunter / MHP-Hunter-Helper.

At combat start (and on catch-up read) it samples, if present:

- Addon loaded: `Matty7500Hunter`, `MHP-Hunter-Helper`, `Matty7500HunterClassic`, `Matty7500HunterForever`
- Globals: `Matty7500Hunter`, `MHPHunterHelper`, `MHP_Hunter_Helper` — **reads** `lastDecision` / `lastScores` / `scores` with `rawget` (so MH's metamethods never run) when they are tables of strings (clipped to 200 bytes on a character boundary), finite numbers and booleans (max 20 keys, two levels). Secret values are skipped. **Does not call** MH functions.
- SV globals: `Matty7500HunterDB`, `MHPHunterHelperDB`, `Matty7500Hunter_lastDecision`

```text
record.mh = {
  status = "ok" | "unknown" | "unavailable",
  observedAt, addon?, version?, global?, decision?, scores?, sv?, note?, approx?
}
```

If MH is not installed, the record is just `{ status = "unavailable",
observedAt }`: it is stored on every fight, so it carries no note. That status
means none of the addon names above was loaded and none of the globals or
SavedVariables tables existed. The addon's source is All Rights Reserved on
CurseForge; `lastDecision` is the contract hypothesised in HelloAim/PLAN.md
and is **unverified in game**. If MH is loaded but exposes no readable table,
or the read fails, `status = "unknown"` with a `note` and HelloForever does
not guess scores. `approx = true` marks a sample taken when the fight was
read rather than at the pull.
