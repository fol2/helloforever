# Changelog

See also [`HelloForever/HISTORY.md`](HelloForever/HISTORY.md) for API / schema detail.

## HelloForever 0.14.0 — 2026-11-15

**New: the assistant's `target` card** (`docs/specs/115.md`, section 5, #136)

- Out of combat, target a creature you have fought at least 3 times at your level: the bar
  shows what those fights usually were. `Defias Thug: usual 15 s, taken 340, died 2 of 8`.
  Prio 2 when one of them was a death. In English or Cantonese.
- The card goes when the target goes, or is not a creature. It does not change in a fight;
  a target picked in a fight gets its card when the fight ends.
- Saved data does not change.

## HelloForever 0.13.1 and HelloLink 0.2.1 — 2026-11-15

- HelloLink: the live-state strip's state flags gain bit 8192, a chat input is open (#131), so a
  program that types into the game can refuse while one is open. The client's active chat edit
  box tells it (seen in the game); when the client cannot say, the whole state group is
  unknown. `docs/STRIP.md`, section 5.
- HelloForever: the assistant's window says what HelloLink says also while the assistant is
  off; it said `HelloLink is not loaded` (seen in the game check of 15 Nov 2026).
- The game check of the assistant's steps 1 and 2 is recorded in `plan/05-assistant-link.md`,
  sections 10 and 11.

## HelloForever 0.13.0 and HelloLink 0.2.0 — 2026-11-15

**New: cards from outside the game, and a question** (step 2 of `docs/specs/115.md`, #127)

- A program on your computer (the companion, step 3) can put cards on the assistant's bar:
  `tools/hellolink.py write <AddOns> --assist <json>` writes a set of cards into the slot
  files; HelloLink 0.2.0 checks the set strictly and takes it only for this UI session and
  when it was written a moment ago; HelloForever shows its cards beside its own. Every `|` of
  a text from outside is doubled, so it draws no colour, icon or link.
- `/hello ask <topic>`, or the topic's button in the assistant's window, asks the companion.
  The bar says `asked: session` until the answer comes, or `no answer: is the companion
  running?` after 30 s. The one topic is `session` (the companion is step 3).
- The window's state line: the slots left and when the last set came, or that the strip is
  off. The setting `Take cards from the companion` now does what it says.
- HelloLink looks at a slot also for the assistant, while the assistant is on: at the fixed
  times at any depth, when a rest starts, at a level up, and 3, 8 and 20 s after a question.
  Never in combat; with 20 slots left only after a question.
- The live-state strip gains object 13, `assist`: what the game took from the companion and
  the last question (`docs/STRIP.md`). With thirteen objects an object is stale after 46.8 s
  (it was 43.2 s). `null` while the assistant is off.
- The slot file says `slots`, and a write of a part keeps the others: a reader's request no
  longer replaces a text.
- Saved data does not change.

## HelloForever 0.12.0 — 2026-11-15

**New: the assistant** (step 1 of `docs/specs/115.md`, #125). Off by default.

- Turn it on in its window (`/hello assist`, the panel's right-click menu, the button in the
  fight window, or the game's settings page) or with `/hello assist on`.
- A bar under the XP panel shows one card at a time: a line of advice that says what it
  stands on. Hover for the detail, who made it and its age; right-click to send it away;
  left-click for the window.
- The first card, `fight`: after a fight against one enemy, this fight against the usual
  fight with that enemy at your level. `Defias Thug: 12 s, usual 15 s · taken 210, usual 340`.
  It stays 120 s or until the next fight.
- The window lists the cards and has a control for every setting: on or off, the language
  (English or Cantonese), cards from the companion, the muted subjects, and a sample card.
  The commands are a second way: `/hello assist on|off|list|test|lang <code>|mute <key>|unmute <key>|outside on|off`.
- Nothing on the bar changes in a fight. A rule that fails three times is off for the session,
  and the fight is saved as before.
- Saved data: `settings.assist`, `assistOutside`, `assistLang`, `assistMuted`, and
  `characters[key].assist` (how often each card was shown and sent away) (`docs/SCHEMA.md`).
  Fight records do not change.

## HelloForever 0.11.0 and HelloLink — 2026-11-15

**New: the fight baseline on the live-state strip** (step 3 of the fight baseline, #109)

- HelloLink's strip carries object 12, `baseline`: after a counted fight, this fight's
  length, damage per second, damage taken and death against the usual fight with that enemy
  at your level, for a program on your computer (`docs/STRIP.md`, section 6). A later
  revision of that fight sends it again. `null` before the first counted fight after a login
  or reload, and after `/hello baseline reset`.
- HelloForever 0.11.0 hands the numbers to HelloLink in a plain table that is not saved.
  Without HelloForever the object is `null` and the strip runs as before.
- For a reader: with twelve objects an object is stale after 43.2 s without a whole copy (it
  was 39.6 s). Nothing else in the format changed.
- Saved data does not change.

## HelloForever 0.10.0 — 2026-11-15

**New: after a fight, how it went against the usual fight** (step 2 of the fight baseline, #104)

- Type `/hello baseline on`. After a fight against one enemy, one chat line compares this
  fight with the earlier fights against that enemy at your level:
  `Defias Thug (lvl 14): 12 s, usual 15 s · 38 dps, usual 31 · taken 210, usual 340 (8 fights)`.
- The usual value is the median of up to 10 earlier fights. A number gets its usual value
  only when at least 3 earlier fights know it. Before that the line says
  `first fights, 2 so far`. A death adds `DIED (usual: 0 of 8 died)`.
- No line for a fight against two or more enemies, or for a later revision of a fight.
- `/hello baseline off` turns the line off (off is the default). `/hello baseline reset`
  forgets the kept fights; fights that started before the reset are not kept again.
- Saved data: the setting `settings.baseline`, and `baselineResetAt` after a reset
  (`docs/SCHEMA.md`). Fight records do not change.

## HelloForever 0.9.0 — 2026-11-14

**New: the addon keeps the usual fights against each enemy** (step 1 of a fight baseline, #99)

- After a fight against one enemy, the addon keeps its length, damage per second, damage
  taken and death under that enemy and your level at the pull. It keeps the last 10 fights
  of each enemy and level, for at most 200 of them. Fights against two or more enemies, and
  fights where your level changed in the pull, are not kept.
- Nothing is shown yet. The next release compares a fight with the usual one, in one chat
  line that you turn on (`docs/specs/93.md`).
- Saved data: `characters[key].baseline` (`docs/SCHEMA.md`, "Fight baseline"). Fight records
  do not change.

## HelloLink: the live-state strip grows — 2026-11-14

**New on the strip: where the guide's arrow points, and the rested XP** (format 1, objects 7 and 8)

- Object 7, `waypoint`: the map and place that the arrow of RestedXP Guides points at, with
  the step's number and text, or `null`. Object 8, `rest`: the rested XP. `docs/STRIP.md`, section 6.
- For a reader: there are more objects now, so an object is stale after 28.8 s without a
  whole copy (it was 21.6 s), and after 32.4 s since object 9. A reader with the old time may call an object stale too early
  when many objects are large. Nothing else in the format changed.
- Object 7 also names the guide (`guide`). Object 9, `route` (#64): the journey that Shortest
  Path Forever has planned, as its public interface gives it: the goal, the time left and
  the legs (what to do, by what means, how many seconds). A leg has no place. With nine
  objects an object is stale after 32.4 s.
- Object 10, `who` (#68): the character's name and realm, so that a reader can tell which
  character's saved files belong to the one in the game. With ten objects an object is
  stale after 36 s.
- Object 11, `steps` (#74): the three steps of the guide after the current one, each with
  its number, text and place. With eleven objects an object is stale after 39.6 s.
- Object 12, `baseline` (#109): see HelloForever 0.11.0 above. With twelve objects an object
  is stale after 43.2 s.
- A guide text over its limit (object 7: 600 bytes; object 11: 400 bytes a step) is cut and
  ends with `…` (#78). It was `null` before. The cut is not inside a character, a texture
  code or a colour code.
- Object 2, `target`, has two more keys (#82): `id`, the creature's id, and `reaction`, the
  target's reaction to the player (1 to 3 hostile, 4 neutral, 5 to 8 friendly).
- Removed (#45): format 0, the text strip that `/hlink send` drew, and its reader
  (`hellolink_strip.py read`); `/hlink reloadtest`; the probes `squares`, `secrets`, `bars`,
  `curves` and `probe --rate`. `/hlink send` gives the question to the strip (object 1) only.
  `/hlink probe depth` stays.
- Object 3, `place`, says whether the player is in an instance, and which (#91):
  `instance`, `instanceType`, `instanceMap`, `instanceName`.
- The fast block's state flags say indoors (512), swimming (1024) and flying (2048) (#101).
  The client gives no height: `UnitPosition`'s z was 0 on 15 Nov 2026.
- The reader streams only (#103): it waits 15 s for a capture's first frame (4.5 to 10 s
  were seen under load) and tries a failed stream again after 2 to 30 s, saying `waiting`;
  it no longer falls back to `screencapture` while it has a capture program.
- The addon's version stays 0.1.0: `Strip.lua` and `HelloLink.lua` changed, no file was
  added or removed.
- The reader (#80): `waiting` is its first event, said at the start; `--remember <file>`
  keeps the row's place for the next start.

## HelloForever 0.8.1 — 2026-11-12

**Removed: the reload when AFK** (`/hello afkreload`, new in 0.8.0)

- Seen in the game on 12 Nov 2026: Forever refuses `ReloadUI` when it is not called from a
  key press or a click ("Interface action failed because of an AddOn"). The feature
  printed its warning and then nothing happened. It is gone; `/hello afkreload` now says so.
- Your data is still written at `/reload`, logout and exit, as before 0.8.0.
- The setting `afkReload` and the key `afkReloadAt` are no longer read or written. A file
  that has them keeps them; they mean nothing.

## HelloForever 0.8.0 — 2026-11-12

**New: save the data when you go AFK** (`/hello afkreload on|off`, off by default)

- The client writes the addon's data to disk only at `/reload`, logout and exit. An addon
  cannot write a file, and `/hello snap` only changes memory. So data collected before a
  long AFK stayed in the game until you came back.
- With the setting on, the addon reloads the UI once when you go AFK: after a 5 s warning in
  chat (move and it is cancelled), never in combat, and at most once in 10 minutes.
- Not yet seen in the game: that this client fires `PLAYER_FLAGS_CHANGED` for AFK and lets an
  addon reload without a key press. If either is not so, nothing happens and nothing breaks
  (`plan/01-in-game-verification.md`, section 9).

## HelloForever 0.7.1 — 2026-11-12

**Fix: fights were filed again at every login**

- The client announces a meter reset when it starts and still lists the fights of the last
  session, with the same ids. The addon threw its "already read" markers away on that
  reset, so it read all of them again and stored each as a new fight with an estimated
  start time. Seen in real data: about 30 copies at each login, and at least 98 copies
  among 724 collected fight files. The fault is in 0.5.0 and 0.6.0 as well.
- The markers are now kept across a reset (and across a restart of the session numbering)
  and marked as having left the list. A session that is listed afterwards is read and
  compared: the same content stores nothing, a session that grew is a new revision, other
  content is another fight under its own key. A marker whose session never returns is
  forgotten after an hour, as before.
- "The same content" is now proven, not assumed: the marker keeps a fingerprint of the whole
  meter content (everything but the rates, in any row order). Another fight on the same id with the same
  name, length and totals is stored under its own key. A marker written before 0.7.1 has no
  fingerprint, so **the first login after the update files the last session once more**;
  after that, never again.
- A reset also lets a session that had stopped changing be read again, and a marker whose
  session is gone expires after the hour by a timer, not only at the next read.
- Copies already stored are not removed. The offline pipeline's report counts a fight once.

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
