# Changelog

See also [`HelloForever/HISTORY.md`](HelloForever/HISTORY.md) for API / schema detail.

## HelloForever 0.7.0 — 2026-11-12

**What a pull cost and used** (`record.pull`, new on every fight)

The damage meter gives totals only. Each fight record now also has:

- **Before and after:** XP, level, health, mana and pet health when combat started and
  when it ended. XP per fight and the cost of a fight no longer need a guess.
- **Target:** the name, level, classification and creature type of the target when combat
  started.
- **Cast counts:** per spell, for the player and for the pet, from
  `UNIT_SPELLCAST_SUCCEEDED`. A cast that landed up to 3 seconds before combat counts as the
  opener (`lead`). At most 40 different spells a pull; the rest are counted in `castsDropped`.
- **Spell names** (`record.spellNames`): id to name for the casts and for the player's
  damage and damage-taken rows, so a report needs no spell database.

A value the client keeps secret is left out, never guessed. The in-combat handler only
writes into a table. A different fight found on a reused session id gets the latest pull's
block marked `approx`, never the earlier fight's. Additive: `schemaVersion` stays 6.

Only run against the mock client. `plan/01-in-game-verification.md` lists what the game
must confirm (are health, mana and the target's level readable at the two combat events;
has the kill's XP arrived by then; does Auto Shot fire the cast event).

## HelloForever 0.6.0 — 2026-11-11

**Version alignment**

- TOC, `VERSION_FALLBACK`, README and docs all report **0.6.0** (the v0.5.0
  fallback could previously lag the TOC, so a metadata miss stamped `0.4.0`
  while the game showed `0.5.0`).
- Every export (SavedVariables root, character snapshot, fight record, gap
  record) carries `addonVersion`, `sourceRevision`, `schemaVersion` (6),
  `gameBuild` (the build string from `GetBuildInfo`) and `client`
  `{ version, build, date, toc }`.
- A per-install `installId` (8 hex chars) is generated once per SavedVariables
  file so later fight IDs can be unique across machines.

See [`docs/SCHEMA.md`](docs/SCHEMA.md).

**Fight IDs**

- New keys: `hf1-<installId>-<unixStart>-<sessionId>-<seq>` (PCRE
  `^hf1-[0-9a-f]{8}-\d+-\d+-\d+$`). Unique across two machines via `installId`.
- `seq` is always present so uniqueness is not an optional suffix on
  `{unix}-{sid}` (the form the wow-data importer previously rejected).
- Existing `{unix}-{sid}` and `{unix}-{sid}-{n}` keys are never rewritten;
  `ns.ParseFightKey` accepts all three. Combined importer PCRE is in SCHEMA.md.

**Freshness and quests**

- Each snapshot section has its own `observedAt` + `status` (`ok` /
  `unavailable` / `stale`). Money/gear patches no longer make talents or
  quests look fresh.
- Quest log states: `accepted`, `in_progress`, `ready`, `failed`, `completed`
  (history), `abandoned`, `unknown`. `C_QuestLog.GetInfo` has no `isComplete`
  on Forever; that missing field is no longer treated as false.
- Bags (backpack + equipped bags, occupied slots only) as their own section.

**Hunter pet**

- Permanent hunter pet: name, family, level, abilities with ranks, Growl
  autocast, happiness, training points, XP. Temporary summons (`UnitExists`
  without `HasPetUI`) are stored as `kind = "temporary"`, not mixed with the
  stable pet. Missing API values are `"unknown"`, never guessed. Classic-era
  APIs only (`HasPetUI`, `GetPetHappiness`, `GetPetTrainingPoints`,
  `GetPetActionInfo`, `HasPetSpells` / `C_SpellBook.HasPetSpells`).

**Fight context, professions, Matty Hunter**

- Each fight references pre-pull gear/talent/pet hashes (`contextBlobs`), not
  a full copy. Context ids are an O(1) copy at combat start (no snapshot APIs).
- Profession events: skill-ups, OOC gathering/fishing/craft casts and the
  following loot/tradeskill line.
- Read-only observe of Matty7500Hunter `lastDecision` / scores when the
  global exists. MH is never modified. If it is not loaded or not readable,
  the fight record says why.

**Self-test, smaller saves, release packaging**

- `/hello selftest` lists the client events the addon asked for that this
  client does not know or has not fired yet, the APIs it did not find, and the
  snapshot sections that could not be read. The result is also saved
  (`HelloForeverDB.selftest`). Run it after playing a few minutes on a new
  client build.
- Smaller SavedVariables: fight records no longer repeat the client table
  (`gameBuild` stays; the rest is on the root), and skill rows keep `id` and
  `cat` instead of the whole 16-field API table (`_raw`).
- `tools/package.py` checks that the TOC version, `VERSION_FALLBACK`,
  `SOURCE_REVISION` and this changelog agree, runs the tests and builds a zip
  with SHA-256 sums.
- `plan/` lists what still needs the game client or more GitHub access:
  in-game verification, the CI workflow, release tags, the Matty Hunter contract.

**Review fixes before release**

- Quests: `abandoned` is recorded only when the client says the quest was not
  turned in, and an entry goes away again if the quest returns to the log or
  its completed flag arrives late. Finished objectives are counted instead of
  summing kill counts, so `10/10` plus an unfinished objective is no longer
  `ready`. The turned-in history (thousands of ids) is copied on a full
  snapshot or when a quest leaves the log, not on every `QUEST_LOG_UPDATE`;
  `completedTotal` shows when the list was capped (cap raised to 4000).
- Fight context is stamped per session, so a fight read late (chain pull,
  secret values, `/reload`) keeps the gear / talents / pet it was pulled with.
  Talent changes now refresh the talents hash between snapshots.
- Profession casts match skill names exactly. A substring match filed class
  spells such as Arcane Shot under the `Arcane` skill line.
- Matty Hunter is read with `rawget` under `pcall`: its metamethods never run
  and a surprise in its tables cannot break the combat-start handler. The
  "not installed" stamp on each fight is two fields instead of a paragraph.
- `installId` no longer reseeds the RNG other addons share, and no longer
  needs `math.randomseed` to exist.
- Freshness: a section that was never read has no `observedAt`; logout and
  time-played values carried over from an earlier read are `stale`, not `ok`.
- Skill-up chat lines parse through the client's `SKILL_RANK_UP` format, and
  the same rank is not logged twice.
- Bags refresh on `BAG_UPDATE_DELAYED` where the client has it.
- A later revision of a fight keeps the start its key was made with. After
  the session list had been empty for a moment, 0.5.0 re-estimated the start,
  so the key and the record disagreed.
- A repeatable quest (never flagged completed by the client) handed in this
  session is recognised from `QUEST_TURNED_IN` and not listed as abandoned.
- A session the meter announces just before `PLAYER_REGEN_DISABLED` gets that
  pull's Matty Hunter sample, and a different fight found on a recycled session
  id gets the latest pull's context (marked `approx`) instead of inheriting the
  earlier fight's.

## HelloForever 0.5.0 — 2026-11-09

**New**

- XP panel redesign: XP bar with rested overlay, XP/hour, time to level, last fight;
  gold/hour at the level cap; tooltip with session totals; lock, scale, hide; right-click menu.
- Fight history window (`/hello ui`): newest 50 fights with a per-fight breakdown.
- Session counters (XP, gold, fights, best fight, deaths) and a level-up log (`/hello levels`).
- Optional one-line chat announcement per fight (`/hello announce on`).
- `/hello budget <MB>`, `/hello purge <days>` (inside the 7-day keep window it asks for
  `force`), `/hello fights <n>`, `/hello help`.
- Addon compartment entry and addon-list icon.

**Fixed**

- Equipment, money and zone changes arriving within 10 s of the previous one were
  dropped; a second gear swap could stay out of the snapshot until relog.
- A fight reusing a session id (same name) could overwrite or be skipped as the earlier
  fight; it now gets its own record when the player's own totals went down. A session
  that merely got shorter is treated as a correction of the same fight.
- A session list that was empty for a moment made every fight look new when it came back.
- After a relog that restarted numbering at the same id, a fight against the same mob
  could be skipped or stored over the previous login's record.
- A re-read in which one meter type failed replaced the good record with the error.
- Fight data that arrived after the instant post-combat read was never picked up
  unless the session also got longer.
- A secret death-recap flag threw instead of waiting; an unexpected reader error stalled
  the queue until the next fight.
- Level-capped characters (XP 0 / 0) were treated as a logout wipe: no snapshots or
  timeline entries.
- Snapshot work could run in combat and store blanked (secret) stats.
- Combat-log mode `off` no longer switches off logging started elsewhere at every login.
- Timeline trim could leave delta entries with no keyframe before them.
- `fightTrack.done` and the trimmed-day receipts grew without bound.

**Cheaper**

- Per-value secret checks no longer go through `pcall`; the character key and addon
  version are resolved once instead of on every access; fight-log size is tracked
  incrementally; repeated in-combat meter events for the same session return immediately.
- The panel only ticks while shown and only rewrites text that changed.
- Fight records are deflated with the size-optimised level.

SavedVariables stay compatible with 0.4.0 (additive fields only).

## HelloForever 0.4.0 — 2026-11-09

- Lossless fight log from `C_DamageMeter` + `C_DeathRecap`.
- Instant post-combat read; chain-pull / gap handling; compressed day buckets.
- Slash: `/hello fights [read]`, `/hello export`.

## HelloForever 0.3.0

- First fights module (per-fight summaries from `C_DamageMeter`).

## HelloForever 0.2.3

- Stamp `addonVersion` + client build into DB and snapshots.

## HelloForever 0.2.2

- Forever Camelot talent / trait-tree collector.

## HelloForever 0.2.1

- Multi-branch collectors, `/hello debug`, live money/gear patches.

## HelloForever 0.2.0

- Character snapshot + delta timeline + combatlog setting.

## HelloForever 0.1.0

- `/hello` + XP/hour learning stub.

## HelloAim

- Proposal only (`HelloAim/PLAN.md`). Not implemented.
- Plan revision 2: reviewed against the 1.60.1 UI source; open decisions, in-game
  checks and the Matty7500Hunter contract checklist added.
- Plan revision 3: Matty7500Hunter v.41 source read locally. MH already glows the
  action-bar button to press, so the plan now starts with a trial of MH alone
  (phase v0.0, no code); MH contract filled in; follow log proposed for HelloForever.
- Plan revision 4: MH is now v.42 and has run on this client; the phase v0.0 trial
  is under way. The MH names HelloForever 0.6.0 reads are confirmed in the MH source
  (`docs/SCHEMA.md`); the in-game confirmation is in `plan/04-matty-hunter-contract.md`.
