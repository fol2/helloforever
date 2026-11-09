# Changelog

See also [`HelloForever/HISTORY.md`](HelloForever/HISTORY.md) for API / schema detail.

## HelloForever 0.5.0 — 2026-11-09

**New**

- XP panel redesign: XP bar with rested overlay, XP/hour, time to level, last fight;
  gold/hour at the level cap; tooltip with session totals; lock, scale, hide; right-click menu.
- Fight history window (`/hello ui`): newest 50 fights with a per-fight breakdown.
- Session counters (XP, gold, fights, best fight, deaths) and a level-up log (`/hello levels`).
- Optional one-line chat announcement per fight (`/hello announce on`).
- `/hello budget <MB>`, `/hello purge <days>`, `/hello fights <n>`, `/hello help`.
- Addon compartment entry and addon-list icon.

**Fixed**

- Equipment, money and zone changes arriving within 10 s of the previous one were
  dropped; a second gear swap could stay out of the snapshot until relog.
- A fight reusing a session id (same name) could overwrite or be skipped as the earlier
  fight; it now gets its own record.
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
