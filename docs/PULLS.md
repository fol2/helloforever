# The record of each pull (format 1)

`hellolink watch --pulls DIR` appends one JSON line for each pull to `DIR/<YYYY-MM-DD>.jsonl`, by
the local date of the pull's start (#361). `hellolink replay RECORD --pulls DIR` builds the same
lines from a `--record` file. The reader builds the line from what it reads on the strip
(`docs/STRIP.md`): the fast block and the level squares of each frame, object 10 (the character)
and object 24 (the units). The addons save nothing for it.

The files hold the character's state. Keep them out of this repository.

## When a pull starts and ends

- A pull starts at the first frame whose state flags have the in-combat bit (128), and ends at
  the first frame whose flags do not. A frame whose state group is unknown neither starts nor ends
  a pull.
- `t0` and `t1` are Unix seconds, two decimals: the reader's clock when it read those frames.
  Under `replay`, the run's times are set by the first frame's `clock` (the client's `time()`
  modulo 65536), so they are within one second of the client's time.
- To join a line to a HelloForever fight record (`docs/SCHEMA.md`, the `pull` block): the line
  whose `t0` is within 2 s of `pull.t0` (whole seconds, `PLAYER_REGEN_DISABLED`).
- `t1` is `null` when the end was not seen: the reader stopped, or read no frame for 120 s.
- With no reader running there is no line. The fight record and the client's combat log stay.

## The line

```json
{"v": 1, "reader": "<build>", "char": "<GUID>", "t0": 1794516378.42, "t1": 1794516401.9,
 "samples": [[dt, map, x, y, facing, flags, hp, pw, petHp, tgtHp, thrP, thrPet, cast], ...],
 "units": [{"i": 1, "id": 740, "g": null, "lvl": 35, "cls": "normal", "seen": 5, "last": 15,
            "dead": 15, "thr": [[5, 3], [15, 2]], "thrPet": [], "tgt": [[5, "player"], [15, "pet"]]}],
 "near": [[5, 1], [15, 0]], "gaps": [[9, 35]], "gclash": false}
```

Every `dt` is tenths of a second from `t0`, a whole number. `null` is unknown, never 0. A reader
of this format ignores keys it does not know.

- `v`: 1, this format.
- `reader`: the build that wrote the line (`hellolink built-from`).
- `char`: object 10's `guid`, `Player-<server id>-<hex>`; `null` until the reader got object 10.
- `samples`: at most 5 a second, from the frames (16 to 27 a second):
  - `map`, `x`, `y`, `facing`: the fast block's position group. `x` and `y` are the map
    fraction times 65535; `facing` is 0 to 255, 0 north, counter-clockwise.
  - `flags`: the fast block's state flags (in combat 128, dead 64, mounted 32, indoors 512,
    swimming 1024, flying 2048, and the rest of `docs/STRIP.md`, section 5).
  - `hp`, `pw`, `petHp`, `tgtHp`: the level squares, per cent, 0 to 100 (steps of 1/127):
    the player's health and power, the pet's health, the target's health.
  - `thrP`, `thrPet`: the fast block's threat group: the player's and the pet's threat on the
    target, per cent; 0 for a unit not on the target's list.
  - `cast`: the spell the player casts or channels (the cast group), else `null`. Instant spells
    are not here: take them from the combat log.
  - Speed is not given (the client keeps `GetUnitSpeed` secret in combat): work it out from the
    positions.
- `units`: each hostile nameplate (it can be attacked) seen in combat during the pull, in the
  order first seen. Object 24 comes about twice a second, so these times are that fine.
  - `i`: its index in this pull, from 1.
  - `id`: the creature's npc id (`null` for a player or a player's pet).
  - `g`: a 16-bit check over the unit's GUID, when HelloLink sends it (a later version); `null`
    before that.
  - `lvl`, `cls`: its level (-1 for a hidden one) and classification when first seen.
  - `seen`, `last`: when it was first and last seen; `dead`: when it was first seen dead, or
    `null`.
  - `thr`: `[dt, situation]` at each change, `UnitThreatSituation("player", unit)`, 0 to 3.
  - `thrPet`: the same for the pet, when HelloLink sends it; `[]` before that.
  - `tgt`: `[dt, target]` at each change: `"player"`, `"pet"`, `"other"`, or `null` for none.
  - No health: the client keeps every unit's health secret. Take a creature's health from the
    combat log's advanced fields.
- `near`: `[dt, n]` at each change: hostile nameplates not dead and not in combat (a risk of a
  further pull).
- `gaps`: `[dt0, dt1]` for each stretch of more than 1.5 s with no frame inside the pull.
- `gclash`: `true` when two nameplates of the pull could not be told apart surely: the same
  creature with no `g` (the reader then tells them apart by their place in the client's list,
  which can change), or the same `g`. Units of such a pull may be mixed up.

## Size

About 300 bytes a second in combat: about 10 KB for a 30-second pull.

## Changes to this format

A new key may come in any version. A change to the meaning of a key makes `v` 2.
