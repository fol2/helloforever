# The live-state strip: a reader's reference (format 1)

HelloLink draws one row of coloured squares along the top of the game. The row carries the
character's live state. Any program may read it from the screen; this page is what such a
program needs. Why the format is as it is, is in `docs/specs/29.md`. The addon side is
`HelloLink/Strip.lua`; a reference reader is `reader/hellolink/src/strip1.rs` (no I/O) with
`hellolink watch` (`reader/README.md`).

**Status: format 1, read in the game on 13 Nov 2026; the format stands.** A reader followed
it through 34 minutes of play: 18 615 frames, every one with a good check, a new one each
0.106 s (median), at six bits a square except for 12 s (118 frames) switched to three
bits by hand; the reader never asked to fall back. `plan/05-assistant-link.md` (section 5)
has the results and what is still open. A
change to the format changes this page and the vectors in `tests/vectors/` in the same pull
request.

The strip only shows what the addon may read, or what the client colours itself. A reader
only looks. Nothing here presses a key, casts or moves.

## 1. Find the row

Squares are `S` physical pixels on a side: 2 by default, 3 or 4 by setting. The row is `S`
pixels high and starts at the game's top-left corner by default; the player can move it.

1. Look for the **finder**: eight squares whose colours are the digits `4 2 1 7 0 6 3 5`
   (red, green, blue, white, black, yellow, cyan, magenta). A digit is
   `4*red + 2*green + blue`, each channel fully on or off; read a channel as on above half.
2. Take the square's width from the row, not only from the finder: eight squares give it to
   a sixth of a pixel, and the row is hundreds of squares long. The frame check (section 3)
   is the judge. The reference reader lines up the colour changes along the row.
3. Refuse a row whose squares are under 2 pixels in your capture. Format 2
   (`docs/specs/213.md`) draws squares of exactly 1 pixel: read those only when the depth
   square says format 2 (the digit 6 or 3).
4. Once found, capture only the row's rectangle. Look again when captures stop decoding.
5. On macOS with ScreenCaptureKit (measured 13 Nov 2026):
   - One stream a display at a time. A second stream on a display stops the first one
     ("application connection being interrupted"), and sometimes gets no frame itself. Two
     readers of one display cannot run side by side; streams on different displays can.
   - A stream gives its first frame at once on an idle machine, also of a display where
     nothing moves. Under load it does not: on 15 Nov 2026, with the machine busy (load
     about 11), the first frame came after 4.5 to 10 s. Never wait without a limit either:
     once, 40 minutes into a reader's run, the capture service (`replayd`) gave no frame to
     any program on any display until it was restarted; the cause is not known. The
     reference reader waits 15 s for a first frame, then tries the stream again after a pause
     of 2, 4, 8 and 16 s, then every 30 s, and says `waiting` with the reason meanwhile. It
     never falls back to `screencapture` while it has a capture program (#103; owner, 15 Nov
     2026: "i always wanted streaming not capturing"): a fall-back of whole-display
     screenshots added load and lost the row again and again under load.
   - Seen on 15 Nov 2026, with the capture service (`replayd`) running for 1 day 16 h: first
     frames took 4 to 11 s, and another tool's screenshots failed. After `killall replayd`
     (macOS starts it again at once), 5 of 6 first frames came in 1.06 to 2.03 s, and 1 of 6
     gave none in 40 s. What made the starts slow is not known. A restart is cheap to try;
     in that run the reference reader took its stream again by itself. After three failed
     starts in a row the reference reader says so on stderr, once a run (#113).
   - Stop your stream before your program leaves, and ask a capture process to stop (SIGTERM)
     before you kill it. This is good manners towards the service, not a proven cure.

A capture can show the row at another scale than the game drew it; in the game the squares
were seen exact to the pixel at a scale of 1.

## 2. The row, in squares from its left edge

| From | Squares | Part |
|---|---|---|
| 0 | 8 | finder |
| 8 | 12 | level squares: four values, three squares each (section 4) |
| 20 | 1 | depth: the digit 4 or 2 |
| 21 | 6 | session: the frame's session number as six two-level digits (18 bits, the top two 0, most significant first) |
| 27 | 64 | palette, only at depth 4 |
| 27, or 91 at depth 4 | to the frame's end | the frame (section 3); black after it |

**Depth 2**: a frame square is a digit, 3 bits.

**Depth 4**: a frame square is one of 64 colours, 6 bits. Colour `i` (0 to 63) has red level
`floor(i / 16)`, green level `floor(i / 4) modulo 4`, blue level `i modulo 4`; a level `k` is
the channel at `k / 3` of full. The palette shows the 64 colours in order. **Read the palette
first** and name each frame square by the palette colour nearest to it (the smallest sum of
squared differences of red, green and blue). Do not compare against fixed levels: a display
moves them (sent 51, 102, 153 came back 38, 90, 146 on one) and lets blue add green.

**Bytes from squares**: the squares' bits, each square most significant bit first, make one
string; cut it into bytes. The last square is filled with 0 bits; ignore them. `01 00 2A` is
the colours 0, 16, 0, 42 at depth 4 and the digits 0, 0, 2, 0, 0, 0, 5, 2 at depth 2. The
same rule holds at 9 bits a square (format 3, section 8): `01 00 2A` is the squares 2, 0, 336
(the bits `000000010 000000000 101010000`, the last three of them fill).

## 3. The frame

Numbers are unsigned, big-endian.

| Bytes | Field | Meaning |
|---|---|---|
| 1 | version | 1. Refuse another. |
| 2 | session | 1 to 65535: one more at every UI load. When it changes, forget every object and partial object. It must equal the session squares of the row. |
| 1 | dwell | How long a chunk stays on the row, in hundredths of a second, 5 to 100. |
| 2 | seq | One more, wrapping, each time the frame's bytes change. |
| 1 | fastLen | Bytes of the fast block: 58 in version 1. Skip bytes you do not know at its end. |
| fastLen | fast block | Section 5. |
| 6 | object part | objectId (1), objectVersion (2), chunkIndex (1), chunkCount (1), chunkLen (1). objectId 0: no object, all six bytes 0 and no chunk. Otherwise `1 ≤ chunkCount ≤ 12`, `chunkIndex < chunkCount`, `1 ≤ chunkLen ≤ 255`; refuse a frame that breaks one. |
| chunkLen | chunk | Section 6. |
| 2 | check | Over every byte before it. |

**The check**: two sums, both from 0. For each byte `b`: `s1 = (s1 + b) modulo 255`, then
`s2 = (s2 + s1) modulo 255`. The two bytes are `s1`, then `s2`. The bytes of `abcde` give
`F0 C8`.

Report nothing from a frame whose finder, version, lengths or check is wrong, whose session
is 0 or differs from the row's session squares, or whose dwell is outside 5 to 100. The `seq`
goes up at least once a second while the game runs (the clock field changes): after 3 s
without a new one, what you hold is stale, and the row may have moved (to another display,
or away): look for it again. A capture of a place the row left never changes, so only time
tells.

## 4. The level squares

Four values the client keeps secret from addons, each as three squares the client colours
itself: player health, player power, target health, pet health, in that order.

`level = 16 * square1 + 2 * square2 + (1 if square3 is yellow, 0 if it is green)`, from 0 to
127, and the value is `round(100 * level / 127)` per cent. Square 3 is yellow (digit 6) or
green (digit 2); anything else means unknown: no such unit, or the client did not colour it.

The level squares are not in the frame and change without a new `seq`. Read them from the
same capture as the frame. They carry no check.

## 5. The fast block (58 bytes)

First `known`, 2 bytes: one bit a group, group 1 in the most significant bit. A group whose
bit is 0 is **unknown** (not read, secret, or not there) and its bytes are 0: do not read
them as zeros.

| # | Group | Fields, in order | Bytes |
|---|---|---|---|
| 1 | clock | the client's time in seconds, modulo 65536 (2) | 2 |
| 2 | health | maximum health (3) | 3 |
| 3 | power | maximum power (3), power type (1) | 4 |
| 4 | level | level (1), XP (3), XP for the level (3) | 7 |
| 5 | state | flags (2): in combat 128, dead or ghost 64, mounted 32, resting 16, AFK 8, casting or channelling 4, has target 2, has pet 1, loot window open 256, indoors 512, swimming 1024, flying 2048 (#101), on a flight path 4096 (HelloLink 2.1.0: `UnitOnTaxi("player")`; 0 from a client without it), a chat input open 8192 (#131: the client's active chat edit box; the whole group is unknown when the client cannot say). Indoors, swimming and flying are hints about where the player is, not a level: the client gives no height, and two floors indoors look the same. `flying` is `IsFlying()`: true on a flying mount; it was false on a flight path (15 Nov 2026), which is what 4096 tells. | 2 |
| 6 | cast | spell id (3), tenths of a second left, rounded up, 255 = more than 25.4 s (1). Unknown when not casting. | 4 |
| 7 | target | level (1; 255 = hidden), flags (1): hostile 128, dead 64, elite 32, rare 16, tapped by another 8, a player 4, its target is the player 2, its target is the player's pet 1; name hash (2): the check of section 3 over the name's UTF-8 bytes | 4 |
| 8 | pet | maximum health (3) | 3 |
| 9 | position | map id (2), x (2), y (2): the map fraction times 65535, rounded; facing (1): radians / 2π × 256, rounded | 7 |
| 10 | purse | money in copper (4), free bag slots (1) | 5 |
| 11 | hand | main-hand item id (3; 0 = empty), seconds left of its temporary enchant, rounded up (2; 0 = none) | 5 |
| 12 | loot | items-received counter (1), the last item's id (3), its quantity (1) | 5 |
| 13 | uiError | the client's number of the last UI error message (2), error counter (1) | 3 |
| 14 | threat | the player's threat on the target (1), the pet's (1): per cent, 0 to 100. 0 for a unit not on the target's list. | 2 |

Conversions the addon makes:

- A number too large for its field is the field's largest value, except `facing`.
- `x`, `y`: `floor(fraction × 65535 + 0.5)`, the fraction being the client's map position, 0
  to 1.
- `facing`: `floor(radians / 2π × 256 + 0.5) modulo 256`, so a facing just under a full turn
  is 0, not 255. 0 is north and the number grows as the character turns left
  (counter-clockwise), so 64 is west: measured in the game on 13 Nov 2026 (2 facing north,
  59 after a quarter turn to the left).
- target `level`: 255 is a level the client hides. (A target whose level could not be read
  makes the whole target group unknown; 0 is not used.)
- `threat`: the client's scaled per cent for that unit on the target, rounded to the nearest
  whole number, at most 100; 0 for a unit that is not on the target's list. The group is
  unknown with no target, or when either value cannot be read.
- The two counters (loot, uiError) go up by one, wrapping, for each event: the difference
  between two readings, modulo 256, is how many happened in between.

## 6. Objects

Larger data comes one chunk a frame. The addon sends whole objects one after the other in
the order of their ids, then starts again; nothing jumps the queue. An object is at most 12
chunks.

**Versions.** `objectVersion` starts at a random number when the UI loads and goes up by one,
wrapping from 65535 to 0, each time the object's content changes: at most once a second for
one object (quests: once in 2 s). The name `(session, objectId, objectVersion)` therefore
does not come back while a reader can still hold a piece of it.
Besides its own events, the addon reads every object again every 30 s, in case the client
sent no event; not object 1 (the question) and not object 19 (completed quests: login and
turn-in only).

**Joining.** Build an object only from chunks seen one after the other: index 0, 1, ...,
all with the same session, objectId, objectVersion and chunkCount.

- A frame whose whole object part and chunk equal the chunk you accepted last is that chunk
  again: ignore it.
- Drop the partial object when a frame's object part is anything else than that or the next
  chunk, and when `5 × dwell` pass after a chunk without the next.

The joined bytes: `format` (1 byte), the content, then the check of section 3 over both.

| format | Content |
|---|---|
| 0 | UTF-8 text |
| 1 | Deflate of UTF-8 text (try a raw stream, then one with a zlib header) |
| 2 | format 3 only: the object's binary form (`docs/specs/232.md`, part E); a reader gives its JSON |
| 3 | format 3 only: format 2's binary form, deflated (try a raw stream, then one with a zlib header) |
| 254 | none: the object is too large to send. Drop your copy. |
| 255 | none: the addon cannot read the object now. Drop your copy. |

An object you have not seen whole for `3 × 23 × 12 × dwell` (82.8 s at the default) is stale:
three rounds of the twenty-three objects, each as large as it may be. (Six objects and 21.6 s until 14 Nov 2026, #62; eight and 28.8 s until #64; nine and 32.4 s until #68; ten and 36 s until #74; eleven and 39.6 s until #109; twelve and 43.2 s until #127; thirteen and 46.8 s until #138; sixteen and 57.6 s until #141; seventeen and 61.2 s until #180; eighteen and 64.8 s until #191.)
The last chunk of an object you hold, seen again, counts as seeing it whole: with one
one-chunk object in the queue the row shows nothing else.

| Id | Object | Text |
|---|---|---|
| 1 | question | Plain text the player typed (`/hlink send`). Sent in two rounds, then gone. Act once for each `(session, objectVersion)` that differs from the last one you acted on. |
| 2 | target | `{"name": "Wetlands Crocolisk", "type": "Beast", "class": "normal", "level": 23, "id": 1984, "reaction": 4}`, or `null` with no target. `type` may be `null`. `class`: `normal`, `elite`, `rare`, `rareelite`, `worldboss`, `trivial`, `minus`. `level` -1 = hidden. `id` is the creature's id, for a creature or a vehicle, a whole number of at most 9 digits; `null` for a player, a pet, another thing, a GUID of another shape, or when the client keeps it secret. `reaction` is the client's reaction of the target to the player: 1 to 3 hostile, 4 neutral, 5 to 8 friendly; `null` when the client gives none or keeps it secret. A hostile reaction does not say that the creature attacks first. |
| 3 | place | `{"map": 1437, "zone": "Wetlands", "sub": "Black Channel Marsh", "instance": false, "instanceType": "none", "instanceMap": 0, "instanceName": "Eastern Kingdoms"}`; `sub` may be `""`. `instance` is true in a dungeon, raid, battleground or other instance. `instanceType` is the client's word: `none`, `party`, `raid`, `pvp`, `arena`, `scenario`. `instanceMap` is the instance's map id (outside an instance, the continent's: 0 for the Eastern Kingdoms); `instanceName` its name (outside, the continent's). Each of the four is `null` when the client gives none or keeps it secret. Inside an instance the fast block's position may be unknown. |
| 4 | bags | `{"free": 12, "items": [[2318, 16], [4234, 3]]}`: item id and how many the bags hold, by id. The items are those of bags 0 to 5; `free` is the free slots of bags 0 to 4, as `bagFree` of the fast block. A change of the ammunition's count alone (a shot), or a slot freed because a stack of ammunition ran out, does not make a new version: those two are as of the last other change of the bags. |
| 5 | quests | `[{"id": 290, "title": "...", "state": "accepted", "objectives": [{"text": "...", "have": 0, "need": 9, "done": false}]}]`, by id. `state`: `accepted`, `in_progress`, `ready`, `failed`, `unknown`. `have` and `need` are `null` for an objective without a count. |
| 6 | skills | `[{"id": 165, "name": "Leatherworking", "rank": 75, "max": 150}]`, by id. |
| 7 | waypoint | `{"source": "RXPGuides", "guide": "29-32 Duskwood", "map": 1434, "x": 21823, "y": 7799, "title": null, "step": 109, "text": "   Kill \|cFFFF5722Young Stranglethorn Tigers\|r\n6/10 Young Stranglethorn Tiger slain"}`, or `null`: where a guide addon's arrow points. `map`, `x`, `y` are as the fast block's position has them. `guide` is the name of the guide that is followed; `title` is the place's title or the step's arrow text; `step` is the step's number in the guide; `text` is the step's text. Each of the four is `null` when the addon holds none. The texts are as the addon holds them: with the client's colour codes (`\|c...\|r`), texture codes (`\|T...\|t`) and line breaks; a `guide` or `title` that is not UTF-8 or is over 200 bytes is `null`. A `text` that is not UTF-8 is `null`; a `text` over 600 bytes is cut and ends with `…`, the whole within 600 bytes. The cut is at a character's border and outside a texture code and the ten characters of a colour code; a cut text can lack its closing `\|r`. `source` names the addon; RestedXP Guides is the only one read. The whole object is `null` with no such addon, or when its arrow holds no place. It does not say whether the arrow is shown. It follows the arrow, and a count in the text, within about a second. |
| 8 | rest | `{"rested": 12345}`: the rested XP, 0 for none. Format 255 when the client's value is no amount. |
| 9 | route | `{"source": "ShortestPathForever", "owner": "RestedXP", "goal": {"map": 1415, "x": 31934, "y": 34315, "title": "RestedXP"}, "seconds": 40, "index": 1, "guided": true, "legCount": 1, "legs": [{"mode": "walk", "seconds": 40, "text": "Walk to RestedXP"}]}`, or `null`: the journey that a route addon has planned. `goal` is where it ends: `map`, and `x`, `y` as the fast block's position has them, on that map, which can be a continent's; `title` as the addon names it. `seconds` is the time left, `legs` the legs from the one under way on, each with `mode` (the addon's word: `walk`, `flight`, ...), `seconds` and `text` (what to do). `index` is the number of the leg under way in the whole plan, `guided` whether the addon guides now, `owner` who asked for the journey. `legCount` is how many legs are left, or `null` when there are more than 200; `legs` has the first 20 of them. Seconds are cut to whole seconds. A value that is no amount, no word or no UTF-8 text of a fit length (120 bytes for a leg's `text`) is `null`. A leg has no place: the addon's interface gives none. `source` names the addon; Shortest Path Forever is the only one asked, through its public interface, which only reads. `null`: no such addon, no journey, or a plan that is not ready. While a journey goes on the time left changes, so the object comes anew about every two seconds. |
| 10 | who | `{"name": "FakeHunter", "realm": "Test Realm", "class": "HUNTER", "race": "NightElf", "fullName": "FakeHunter Family", "fullNameSource": "loot", "guid": "Player-1-0000ABCD", "realmSaved": "Test Realm", "talents": {"spent": 30, "unspent": 0, "tabs": [{"name": "Beast Mastery", "points": 21}, {"name": "Marksmanship", "points": 0}, {"name": "Survival", "points": 9}], "nodes": [[19552, 5, 5], [19577, 1, 1], [19583, 3, 5], [19590, 2, 2], [19596, 1, 1], [19598, 5, 5], [19616, 5, 5], [19621, 5, 5], [1223755, 2, 2], [1293241, 1, 1]]}}`: `talents` (HelloLink 2.2.0): the talent points spent and unspent, and each tab's points in the client's order (`C_SpecializationInfo`'s combat config and `C_Traits`' groups, as HelloForever reads them on this client; a tab with nothing spent is 0), read again at the talent events; `null` when a read fails or is secret, or (2.2.1) when the tabs' points do not add up to `spent`. `nodes` (HelloLink 2.4.0, for a gear score that weighs a node's own effect): the bought talent nodes, each `[spell, rank, most]` (the node's spell id, its rank bought, its most ranks), by spell id (`C_Traits.GetTreeNodes` and `GetNodeInfo`, an entry's definition for the spell, its override when it has one, as HelloForever's snapshot reads them); read again only after a talent event (a spec switch included) or a change of the config or the tabs' points (object 10 is built at least every 30 s); `null` when a read fails or is secret (no fall-back to another entry or spell then), when the ranks do not add up to `spent`, or for more than 80 nodes, while the tabs stay; a `null` is read again at the next build. the character in the game, by the name and the realm that the client gives (`UnitName("player")`, `GetRealmName()`). `name` has no family name. `name`, a hyphen and `realm` is the key of that character in HelloForever's saved data (`characters`, `docs/SCHEMA.md`) for a record keyed by name; see below for the realm `""` and the GUID. They are not the names of the client's own folders of saved files (seen 14 Nov 2026: a number and the name with its family name). `realm` is `""` when the client's `GetRealmName` answers `""` (a realm that is `nil`, secret or not read still makes the object format 255): this client has done so since 20 Nov 2026 (`GetRealmName`, `GetNormalizedRealmName` and `GetPlayerInfoByGUID` all give `""`; seen 22 Nov), and HelloLink then keys the character `Name-` (HelloLink 1.16.0; before it, object 10 was format 255). HelloForever 0.18.4 then keeps the one realm it saved before for that name, so its key can be `Name-<realm>` while `realm` here is `""`. From HelloForever 0.19.0 match a HelloForever record by its `guid` (object 10's `guid` below) (`docs/SCHEMA.md`, Character key), not by its key: two characters with one first name have one `name` and `realm` here, and one of their records is keyed by its GUID. A record with no `guid` yet is matched by `name`, unconfirmed. Format 255 when the client gives no name. `class` and `race` are the client's file names (the second values of `UnitClass` and `UnitRace`; #138), `null` when the client gives none. A failed or secret read of either makes the object format 255. `fullName` (HelloLink 0.8.1) is the name with the family name, as the player's own loot message gave it (`HelloLinkDB.fullNames`, section 11, under this character's GUID; sent only while its first word is `name`), and `fullNameSource` is `"loot"`; both are `null` until this character has looted once with HelloLink 0.8.1 or later. No client getter is read for it yet: the probe's `fullName` line decides that (a later release). `guid` (HelloLink 1.18.0) is `UnitGUID("player")`, `Player-<server id>-<hex>`: the character's identity, the key of `seen`, `looks` and `fullNames` (section 11) and the `guid` of its HelloForever record (0.19.0). `null` while the client gives no GUID of that form, or keeps it secret. `realmSaved` (HelloLink 1.19.0) is the realm HelloForever saved for this character before the client stopped giving one: the realm part of the key `"<name>-<realm>"` of the HelloForever record whose `guid` is this one (HelloForever 0.19.0), whatever the name in the key (a renamed character keeps its old record). `null` when HelloForever is not loaded, has no such record, or its key has no realm part (the split `"<name>-"` record, or a record keyed by the GUID). `realm` stays the client's own answer; a reader that needs a realm takes `realm` when it is not `""`, else `realmSaved`. `spells` (HelloLink 2.6.0, spec 232 part D item 5) follows `talents`: each spellbook line in the client's order, `[name, [[spell id, type, passive], ...]]` (the type as `C_SpellBook.GetSpellBookItemInfo` gives it, 1 a spell; the spell id `null` when the item has none). `null` when a read fails, raises or is secret; left out (no `spells` key) when object 10 with it would not fit the row's 12 chunks: object 10 then goes as it was before 2.6.0, so the rest always arrives. Read again after `SPELLS_CHANGED`, `LEARNED_SPELL_IN_SKILL_LINE` or `LEARNED_SPELL_IN_TAB`, and at the next build after a null. The professions and their ranks are object 6's. The getters are those HelloLink 2.5.1's probe saw answer in the game (`plan/05`). |
| 11 | steps | `{"source": "RXPGuides", "guide": "29-32 Duskwood", "steps": [{"step": 109, "text": "Go to the camp", "map": 1434, "x": 21823, "y": 7799, "tags": ["accept", "goto"], "quests": [33], "done": false, "lines": [{"map": 1434, "loop": false, "pts": [20316, 8519, 21823, 7799]}]}, ...], "orphans": [], "targets": {"target": ["Defias Thug"], "mobs": [], "scan": [], "rares": []}}`, or `null`: the current step of the guide and at most four after it, in the guide's order (HelloLink 0.8.0; before, the three after the current step); `[]` past the last step. The current step is the one RXP keeps for the guide (`RXPCData.guideProgress[<guide key>].step`); only when it keeps none, object 7's `step` (the arrow can point at the corpse, a waypoint with no step). `text` is as object 7's `text`, with a limit of 400 bytes: a longer text is cut in the same way and ends with `…`. `text` is `null` when the step has no text or the text is not UTF-8. `map`, `x`, `y` are the step's first place, as object 7 has them, or `null` for a step without a place among its first 20 elements. `tags` are the guide's words for what the step's first 20 elements do (`accept`, `turnin`, `goto`, ...; a word of letters, digits and `_`, at most 40 bytes), each once, in order; `quests` are the quest ids those elements name (an element's `questId`, and the list `questIds` of an `isOnQuest` or `isQuestTurnedIn` element), each once, in order, at most 200. `done` is true when the guide marks the step completed. `elements` (HelloLink 0.8.1) are the step's first 20 elements in order, each as `[tag, questId]`: `tag` as in `tags` or `null` (no tag, not a plain word, or secret), `questId` the element's quest id or `null`; an element with a list `questIds` gives one pair for each id of the list (one pair with `null` when the list is empty; a secret id in the list is a pair with `null`, and the list goes on). Repeats stay. At most 40 pairs a step (`quests` keeps its 200). Example: `"elements": [["accept", 33], ["goto", null], ["isQuestTurnedIn", 34], ["isQuestTurnedIn", 36]]`. `orphans` is RXP's own list of quests that no guide step names, as RXP keeps it (`orphanedList`, a table keyed by quest id; the ids sorted, at most 200; read only: the function that makes the list is never called, because it writes the list anew), `[]` when RXP holds none (seen 18 Nov 2026: none). `targets` are the names RXP's targeting looks for now, four lists of at most 20 names each (each name as a `text`, limit 60 bytes), `null` when RXP has no targeting or its answer cannot be read. `null` for the object: no guide addon, or no current step. `lines` (HelloLink 2.3.0, the current step only): its `.line` and `.loop` elements of RestedXP (a patrol path), at most 2, each at most 24 points taken evenly with the first and the last, in the 0..65535 units of the step's place, on the map `map` (a dashed part's negative points as their absolute values); `loop` is true when RestedXP draws the last point back to the first (`connectPoints`). The steps after it have no `lines`. When the object with its lines would not fit its chunks, it goes without them (`"lines": []`), not as format 254. |
| 12 | baseline | `{"fight": "hf1-0000abcd-1794516378-12-1", "rev": 1, "counted": true, "id": 1984, "level": 14, "name": "Defias Thug", "dur": [12, 15, 8], "dps": [38, 31, 8], "taken": [210, 340, 8], "died": [false, 0, 8]}`, or `{"fight": "...", "rev": 2, "counted": false}`, or `null`: the last counted fight against one enemy and how it went against the usual fight with that enemy at that player level (HelloForever, `docs/specs/93.md`, section 4). `fight` is the fight's key and `rev` its revision: two fights with the same numbers are two versions. `id` is the creature's id, `level` the player's level at the pull, `name` the enemy's name (`null` when it is not UTF-8 or is over 200 bytes). Each of `dur` (seconds), `dps` and `taken` is `[this fight, usual, how many earlier fights know it]`: `usual` is the median of those earlier fights (at most 10), `null` under 3. `died` is `[this fight, how many of the earlier fights died, how many know it]`, the count `null` under 3. A value this fight does not know is `null`. Numbers are rounded to whole numbers. Sent after a counted new fight; sent again for each revision of that fight, as `counted: false` (with no other keys) when the fight no longer counts. `null` before the first counted fight of the session (a reload, or no HelloForever), and after `/hello baseline reset`. |
| 13 | assist | `{"on": true, "lang": "en", "seq": 12, "re": 3, "ask": {"n": 4, "topic": "session", "t": 1794516375}, "left": 163, "taken": 1, "refused": 0, "shown": "bags"}`, or `null`: the acknowledgement of the assistant's way in (`docs/specs/115.md`, section 6). `seq` and `re` are those of the last set of cards the game took in this session, `null` before the first. `ask` is the player's last question (`n` counts from 1 in a UI session, `t` is when it was asked), `null` before the first. `left` is the session's slots not yet used, `null` before the first look. `taken` and `refused` count the cards of the last set. `shown` is the key of the card on the assistant's bar (`out:<id>` for a card from outside), or `null`. `lang` is the language the player chose for the cards. `null` for the object when HelloForever's assistant is off or HelloForever is not there. |
| 14 | gear | `{"slots": {"16": {"item": 2504, "enchant": 1887, "suffix": -9, "dur": [50, 60]}, ...}}`: the equipped gear, slots 1 to 19 (the client's inventory slots), an empty slot left out (#138). `enchant` and `suffix` are fields 2 and 7 of the item's link (`item:itemID:enchantID:gem1:...:gem4:suffixID:...`, warcraft.wiki.gg, ItemLink): the permanent enchant and the random suffix, `null` when the field is empty. A negative suffix is one of ItemRandomSuffix, a positive one of ItemRandomProperties. `dur` is `[current, max]`, `null` for an item without durability. Slot `"0"` is the ammunition, `{"item": 3030, "count": 2783}` (HelloLink 0.8.0; `GetInventoryItemID` and `GetInventoryItemCount` for slot 0), left out when the slot is empty (this client gives 0 for an empty slot 0: left out too, since HelloLink 1.16.0). A shot takes one from `count` and makes no new version: `count` is as of the last other change of the gear (as object 4's ammunition). Sent when the gear or its durability changes. When a call fails or answers a secret the object cannot be read (format 255). |
| 15 | bagslots | `{"bags": [{"bag": 0, "size": 16, "family": 0, "slots": [[1, 2318, 16], [4, 4234, 3]]}, ...]}`: the bags slot by slot (#138): the keyring (-1), the backpack (0), bags 1 to 4 and the reagent bag (5), this client's indices (its UI source, `BagIndexConstants`, 1.60.1). Each slot `[slot, item id, count]`; an empty slot and a container of no slots left out. `family` (HelloLink 0.8.0) is what the container may hold: the second value of `C_Container.GetContainerNumFreeSlots`, 0 for any item (seen 18 Nov 2026: 1 for a quiver); a family the client does not give or keeps secret makes the object format 255. Object 16's tabs have no `family`. A change of the ammunition's count alone (a shot) makes no new version, as in object 4; a stack shot empty does, since its slot is then free (seen about once in 200 shots, 16 Nov 2026). |
| 16 | bank | `{"tabs": [{"bag": 6, "size": 98, "slots": [[1, 9999, 5]]}, ...]}`, or `null`: the bank's purchased tabs, the character's then the account's (`C_Bank.FetchPurchasedBankTabIDs`), each as a container of object 15, while the bank is open (#138). `null` while it is closed: the last bank seen is not kept. A bank too large for one object is sent as format 254 (too large); object 15 still goes. When one tab list or one tab cannot be read, the whole object is format 255, never the tabs that could be read. |
| 17 | trainer | `{"npc": 1700, "pet": false, "skill": "Skinning", "step": 3, "filter": {"available": true, "unavailable": true, "used": false}, "services": [["Skinning", "Journeyman", "available", 10, ["Skinning", 50], 500], ...]}`, or `null`: the trainer window while it is open (#141), read as the client's own trainer UI reads it (`Blizzard_TrainerUI`, 1.60.1). `npc` is the trainer's creature id (from `UnitGUID("npc")`, as in object 2), `null` for one that is no creature. `pet` is true at a pet trainer (`C_Trainer.GetTrainerType()` is `Enum.TrainerType.Pet`): its costs are pet training points, not copper. `skill` is the profession the window trains (`GetTrainerServiceSkillLine`); `null` for a trainer that is not a profession trainer, and also when the filter hides every service, so the profession is not known. `step` is the index in `services` of the stage the trainer teaches (`GetTrainerServiceStepIndex`: the service the client shows apart, Journeyman, Expert and so on), `null` when there is none, and when the client's index is not in `services` (seen once, most likely after a service was bought, #160). `filter` is the window's own filter (`GetTrainerServiceTypeFilter`): the client lists only the services of the states that are on, and the addon does not change it, so a list with a filter off is partial. Each service is `[name, rank, state, level, skill, cost]` in the client's order: the rank text (`null` when empty), the state (`"available"`, `"unavailable"`, `"used"`), the required level, the required skill as `[name, rank]` (`null` for none), the cost (copper, or pet training points when `pet` is true). `null` while no trainer window is open: the last trainer seen is not kept. A failed or secret read, or a name the client does not have yet, makes the object format 255 (a name that comes later sends it again); a list too large for one object is format 254. |
| 18 | hearth | `{"bind": "Gadgetzan", "item": 6948, "readyAt": 1794516378}`, or `null` when the bags hold no hearthstone (#180). `bind` is where it is bound (`GetBindLocation()`), `null` when the client gives none, or a name that is not UTF-8 or is over 200 bytes. `item` is the hearthstone's item id. `readyAt` is when it is ready, in Unix seconds: the clock of the fast block's `clock` group (the client's `time()`); 0 when it is ready now. Count down with your own clock: `readyAt` minus now, at least 0. `readyAt` is worked out once for each cooldown start, with the end the client tells at that moment: it stays the same while a cooldown runs, and the countdown itself makes no new version. A bind, a use, the end of a cooldown, a hearthstone that comes or goes, and a change between format 255 and a readable object do. A whole second either way is possible. A new cooldown start with a duration of 1.5 s or less is the global cooldown and counts as ready; a duration told later for a start already known changes nothing, even 1.5 s: that cooldown ends at the end taken at its start. A count or cooldown that the client does not give, fails or keeps secret makes the object format 255; a bind it does not give is `null` in a readable object. **Not seen in the game (18 Nov 2026)**: whether this client answers these calls, or keeps them secret (`plan/05-assistant-link.md`, section 22). |
| 19 | done | `{"ids": [7, 33, 783]}`: the quests this character has completed, by id (`C_QuestLog.GetAllCompletedQuestIDs`; seen 18 Nov 2026: 480 ids in 21 ms). HelloLink 0.8.0. Read only at a login or a reload (`PLAYER_ENTERING_WORLD` with its `isInitialLogin` or `isReloadingUi` true; not at the loading screen of an instance) and when a quest is turned in (`QUEST_TURNED_IN`), never on a timer: the object stays as it was between them, and does not come round before the login's event. It takes several chunks; a very long list can be too large (format 254). A failed or secret read, an id that is no whole number, or a client without the function: format 255. |
| 20 | corpse | `{"map": 1437, "x": 32768, "y": 16384}`, or `null` when the client gives no corpse (the player is alive): where the corpse lies on the player's map (`C_DeathInfo.GetCorpseMapPosition` for `C_Map.GetBestMapForUnit("player")`), `x`, `y` as the fast block's position. HelloLink 0.8.0. Read again at a death, a release, a return to life, a login and a new zone. A failed or secret read, a place out of the map, or a client without the function: format 255. **Not seen while dead (18 Nov 2026)**: only the alive answer (none) was seen. |
| 21 | rep | `[{"id": 72, "name": "Stormwind", "standing": 6, "value": 3200, "min": 3000, "max": 9000, "watched": true, "header": false}, ...]`: the reputations in the client's order, headers included (`C_Reputation.GetFactionDataByIndex`, 1 to `GetNumFactions()`). HelloLink 0.8.0. `id` is `factionID`, `standing` the reaction (1 hated to 8 exalted), `value` the current standing, `min` and `max` the thresholds of this standing and the next, `watched` whether it is the watched reputation, `header` whether the line is a header. A field the client does not give is `null` (a header has no id). Read at each loading screen and on `UPDATE_FACTION`, at most once in 2 s, also when a read changes nothing. A failed or secret read, or a client without these functions: format 255. |
| 22 | ah | `{"source": "Auctionator", "prices": [[2318, 95, 2], [4234, null, null]]}`, or `null` without Auctionator: the price the auction addon Auctionator last scanned for each of the character's items: a price of the listings it saw, not a sale (its API README: "the last scanned price"). HelloLink 0.8.0. The items are those of the bags (0 to 5), of the bank while it is open, and of the worn gear (slots 0 to 19), each once, by id. Each is `[item id, last scanned price in copper, age in days of that scan]`; `null` when Auctionator has no price or its call fails or answers a secret. Asked through Auctionator's public interface (`Auctionator.API.v1`); HelloLink asks once to be told when Auctionator's prices change, and reads them again then, at a change of the bags, the bank (its slots or tabs too) or the gear. It is read at most once in 2 s, also when a read changes nothing. A failed or secret read of the items: format 255. |
| 23 | pet | `{"xp": [1200, 5600]}`, or `null` without a pet (`HasPetUI()` false): the pet's experience, current and needed (`GetPetExperience`). HelloLink 0.8.0. The pet's happiness is not sent: this client has no `GetPetHappiness` (seen 18 Nov 2026). Read on `UNIT_PET`, `UNIT_PET_EXPERIENCE` and `PET_UI_UPDATE`. A failed or secret read, or a client without `HasPetUI`: format 255. |
| 28 | window | `{"merchant": {"npc": 3518, "items": [[159, 23, 5, null, false]]}, "loot": [[2, null, null, 1], [1, 2589, 2, 1]], "quest": {"page": "detail", "id": 332, "title": "Wine Shop Advert", "xp": 130, "money": 0, "rewards": 1, "choices": 0}}`, or `null` while none of the three windows is open (HelloLink 2.5.0, spec 232, part D item 4). Each key is `null` while its window is closed. `merchant`: the creature id (`null` for a merchant that is no creature, or when the client does not give it) and each item `[item id, price in copper, stack, available, extended cost]`: the id `null` while the client has no link for it yet, available `null` for no limit. `loot`: each slot `[type, id, quantity, quality]`, type 0 (seen in play as `[0, null, null, null]`; its id is `null`, the rest as the client gives it), 1 an item, 2 money (its amount is only text in this client: id and quantity `null`), 3 a currency (its id the currency's). `quest`: the quest window, its `page` "detail" (a quest offered, `QUEST_DETAIL`), "progress" (`QUEST_PROGRESS`) or "complete" (its rewards, `QUEST_COMPLETE`), the quest's id, title (`null` when not UTF-8 or over 200 bytes), the XP and copper it rewards, and how many reward items and choices it has. Sent at the window's events (`MERCHANT_SHOW`, `MERCHANT_UPDATE`, `GET_ITEM_INFO_RECEIVED` while a merchant is open, `MERCHANT_CLOSED`, `LOOT_OPENED`, `LOOT_SLOT_CHANGED`, `LOOT_SLOT_CLEARED`, `LOOT_CLOSED`, `QUEST_DETAIL`, `QUEST_PROGRESS`, `QUEST_COMPLETE`, `QUEST_FINISHED`). The getters are those the 1.15.0 probe saw answer in the game (`plan/05`). |

JSON keys are exactly those shown; ignore keys you do not know. "Nothing there" is content
(`null`, `[]`), not a missing object.

## 7. When six bits do not hold

The addon cannot see the screen. With its depth setting on `auto` (the default) it starts
each UI session at depth 4 and falls back to depth 2 when a reader asks. With the setting on
`2` or `4` the player fixed the depth: the addon keeps it and looks at no request, so a
reader must not wait for a fall-back that the depth square never shows. A reader that finds
depth 4 unreadable asks by writing a field into the slot files that carry text into the
game (`hellolink write <AddOns> --strip-session <n>`):

```lua
HelloLink_Inbox = { seq = 1794516378971, text = "", slots = 200, strip = { session = 4711, depth = 2 } }
```

`session` is the number from the row's session squares, which are two-level and readable
when no six-bit frame is. `depth = 2` asks for 3 bits a square, and every HelloLink reads it.
Strip format 3 (`docs/specs/232.md`, part C) steps down by bits, one step at a time: 9 to 6,
6 to 3. A request for 6 bits names them, `strip = { session = 4711, bits = 6 }`; a request
for 3 bits is still written `depth = 2`. The reference reader asks for one step fewer bits
than the row has (its `ask` event carries `bits`), and so writes `depth = 2` for every row of
6 bits, in formats 1, 2 and 3. The addon takes `bits` (6 or 3) or `depth = 2` only when it is
fewer bits than the strip has now; a request never makes it step up. In `.parts.json`,
`hellolink write` keeps the session as `strip` and, for more than 3 bits, the bits as
`stripBits`. Ask when, over your last 200 frames at depth 4, more than 2 in 100
failed the check (count every frame as failed if you never read one), or when the two
nearest palette colours came back less than 12 apart (the largest of the three channel
differences, 0 to 255). The addon looks at a slot 30 s, 1, 2 and 5 minutes after the UI
loaded and every 10 minutes after that, and acts only on a request that names its own
session. Leave the request in every slot while the row shows that session (a later write of
a text must carry it over; `hellolink write` does). Each look uses one of the session's
slots (200 as installed); when they are used up the addon stops looking and keeps its depth.
Until the depth square shows 2, drop the frames that fail.

The slot file has three parts, each with one writer: the text (`seq`, `text`), this request
(`strip`) and the assistant's cards (`assist`, `docs/specs/115.md`, section 6). `slots` is
how many slots there are. A write through `hellolink write` replaces its own part and
carries the others over; a write of `strip` or `assist` keeps the top `seq` and `text`. With
HelloForever's assistant on, the addon also looks at the moments and after a question that
section 6 of that spec names, at any depth; never in combat; and with 20 slots left only
after a question.

## 8. Later versions

Version 1 only grows: bytes at the end of the fast block, `known` bits, object ids, JSON
keys. Ignore what you do not know. Version 2 is `docs/specs/213.md`: its row has the digit
6 or 3 in the depth square, and the reference reader reads both. Format 2 was the default in
HelloLink 1.0.0 (0.9.0 and 0.10.0 drew it after `/hlink strip format 2`). Version 3 is
`docs/specs/232.md`: the digit 5 or 7 in the depth square, then the layout square (below,
"Format 3 with lanes"); format 3 is the default since
HelloLink 1.1.0, and the only format HelloLink draws since 2.0.0 (the owner, 22 Nov 2026: formats 1
and 2 are legacy). The reader still reads all three, for the records of earlier play. A change of the layout, the finder, the bit order, a
frame field or the meaning of an existing field is a new version, announced in
`CHANGELOG.md`.

### Format 3 with the computed palette (the digit 1)

`docs/specs/232.md`, part C, "The computed palette", and section 6 are the contract. The
reference reader reads these rows. The addon draws them only behind two switches, off by
default, until the hour on the capture stream passes (part C, "Measure first", steps 3 and 4). A
row with the digit 1 in the depth square has no drawn palette. It carries a ramp, and a reader
builds every colour from the ramp.

**The addon's switches** (format 3 only; both saved in `HelloLinkDB`, both shown in the reply to any
`/hlink strip <setting>` and in the settings window; `/hlink strip` alone shows the usage):

- `/hlink strip ramp on|off`: a row at 6 bits has the ramp (4 levels) in place of the drawn
  palette. Off, the row is the drawn palette (digit 5). `ramp off` also sets the bits back to 6.
- `/hlink strip bits 9|6`: with 9, a session starts at 9 bits, a ramp of 8 levels. 9 needs the
  ramp on: with the ramp off the addon refuses it in chat and keeps 6. It also needs depth
  `auto`: a fixed depth 4 keeps 6 bits.

A change of either switch starts the row at the top the settings allow. The addon draws level `k`
of `L` at `0.29 + k × 0.71 / (L − 1)` of full: 0.29, 0.526667, 0.763333 and 1 at 4 levels
(captured as 74, 134, 195, 255 on a screen that keeps the values). The floor 0.29 is the
addon's; a reader takes the levels from the ramp. The frame's bytes are the same whatever the
palette. At 9 bits the frame's bytes are packed 9 bits a square, by the rule of section 2.

**The steps down.** A 9-bit row steps to the 6-bit ramp row at `bits = 6`, and to 3 bits at
`bits = 3` or `depth = 2`; a 6-bit ramp row steps to 3 bits. The session stays at each step, so
a reader asks once for each step: the reference reader asks again when the row's bits change
in the same session (9, then 6), and starts its count of 200 frames again at the step.

| From | Squares | Part |
|---|---|---|
| 0 to 27 | 28 | as format 3 with the digit 5: finder, level triples, the digit 1, the layout square, the session |
| 28 | 1 | levels: the digit `L - 1`, 3 (4 levels a channel, 6 bits a square) or 7 (8 levels, 9 bits). Refuse another |
| 29 | `3 × (L - 1) + 1` (10 or 22) | the ramp |
| 39 or 51 | 2 + 3 × `more` | `more` and the further level triples, as format 2 |
| then | to the frame's end | the frame (format 3); black after it |

**The formula.** Code `i` (0 to L³ − 1) has red level `floor(i / L²)`, green level
`floor(i / L) modulo L`, blue level `i modulo L`. A frame square is one code, `log2(L³)` bits,
in the order of "Bytes from squares" (section 2).

**The ramp's order.** Code 0; then the codes L², 2L², …, (L − 1)L² (red rising, green and blue
at level 0); then L, 2L, …, (L − 1)L (green); then 1, 2, …, L − 1 (blue). At 4 levels: the codes
0, 16, 32, 48, 4, 8, 12, 1, 2, 3. `v[c][0]` is channel `c` of the first square; `v[c][k]` is
channel `c` of the square that drives channel `c` at level `k`.

**Do not assume black is level 0, and do not assume the drawn values.** The addon draws the
lowest level above black and chooses the levels. Take every level from the ramp of the same
capture.

**Naming.** Name a frame square channel by channel: the level `k` whose `v[c][k]` is nearest to
the square's channel `c`; of two equally near, the lower. The code is
`(red × L + green) × L + blue`. The reference reader keeps three tables of 256 entries and
builds them again when the ramp as read changes.

**`gap` and `leak`**, in capture units (0 to 255). `gap` is the smallest `v[c][k] − v[c][k − 1]`
over the three channels. `leak` is the largest distance, over the ramp's squares, of a channel
that the square does not drive from that channel's `v[c][0]`. When a channel does not rise
strictly (`gap` 0 or less), the row has no frame: `why` is `ramp`.

**Failed frames.** A frame counts as failed when its check fails, when its ramp does not rise, or
when `gap − 2 × leak` is under 12. Use a frame whose check holds, also when it counts as failed.
Ask for fewer bits (9 to 6, 6 to 3) when more than 2 in 100 of the last 200 frames of a ramp row
failed. A row with a drawn palette keeps the rule of section 7 (ask at once when `apart` is
under 12). The reference reader's `ask` event has `bits`, the bits it asks for (one step fewer than the
row's: 6 for a 9-bit row, 3 for a 6-bit row). The count of the last 200 frames starts again when a
session changes between a drawn palette and a ramp, or when the row's bits change (a step); it asks once
for each step of a session; its `state` event and its `rows` lines have `gap` and `leak`; its `depth` is `L` (4 or
8).

The hand-written rows are `tests/vectors/ramp3.json`: rows as captured colours with the game
around them, each with its codes, `gap`, `leak` and the frame's bytes.
`reader/hellolink/tests/ramp3.rs` reads them with the reference reader.

### Format 3 with lanes (the layout square)

`docs/specs/232.md`, part C, "Lanes", and section 6 are the contract. The reference reader reads
these rows. The addon draws them only behind a switch, off by default, until lanes have their
measure on the stream and their hour (spec 232, section 11).

**The layout square** is square 21 of a format 3 row, after the depth square: the digit
`lanes − 1`, 0 to 3. Refuse a row whose layout square is 4 to 7. A row with the digit 0 has one
lane, as before.

**The lanes.** A lane is a screen line of squares. Lane 1 is the row's own line. Lane `k` is
`k − 1` squares under it, and starts under the frame's first square: the same column, the same
square size. The fixed head (finder, level triples, depth, layout, session, levels square, palette
or ramp, `more` and its triples) is in lane 1 only. The palette and the ramp of lane 1 serve every
lane. The frame's squares run along lane 1 to the game's right edge, then along lane 2 from its
start, then lane 3, and so on. The bits in the squares and the order of the bytes are those of
section 2, "Bytes from squares", as if the lanes were one line: lane 2 goes on where lane 1
stops, in the middle of a byte when the bits fall so. Black follows the frame's last square, in
whatever lane it ends.

**A lane's length.** Lane 1 holds the frame's squares from its first to the game's right edge.
Each lane under it holds as many. A reader takes the game's right edge from the capture's right
edge: the reference reader takes `round((width − x0) / w) − first` squares a lane, where `width`
is the capture's width, `x0` the row's left edge, `w` the square's side and `first` the frame's
first square. The addon takes the game's width from `GetPhysicalScreenSize`. **ACCEPTED
limit**: so the capture's right edge must be the game's right edge (the game full screen, as the
owner plays it). A game in a window is not tested. A frame that fits lane 1 does not depend on
this.

**The addon's switch** (format 3 only; saved in `HelloLinkDB`; shown in the reply to any
`/hlink strip <setting>` and in the settings window):

- `/hlink strip lanes 1|2|3|4`: the lanes, 1 by default. More than one lane needs format 3 and
  squares of 1 pixel: otherwise the addon refuses it in chat and keeps the lanes. At another
  size or format the setting is kept and the row has one lane.

More lanes are more room, not more squares painted: the chunk stays at most 128 bytes (the paint
budget, spec 232, section 4 B), so at the full width of a display a frame fits lane 1 and the lanes
under it stay empty. The lanes fill only when the row is narrow (a game window, or the row placed
far to the right). Before a chunk, a row keeps room for the rest of the frame at its longest
(`HEAD3`, 213 bytes in format 3 with 27 objects, 216 with 28 since HelloLink 2.5.0); when its place, size and lanes leave no byte for a chunk, no
object reaches a reader, and the addon says so while the strip is on (since HelloLink 1.25.0): in
the reply to any `/hlink strip <setting>` and in the settings window. Seen on 22 Nov 2026 on a 2560-pixel display:
at `/hlink strip at 2400 0` and 6 bits, 4 lanes held no frame at all; at `2300 0` they held a
chunk of 128 bytes. The reference reader's capture stream covers 4 lanes for a row of 1-pixel
squares. Its `rows` lines have `lanes` for a row of more than one lane, and its record has
`lanes` when they change (section 10).

The hand-written rows are `tests/vectors/lanes3.json`: a row of 2 lanes at 3 bits and a row of 4
lanes at 6 bits with the ramp, whose bytes cross the lanes' boundaries, as captured colours with
the game before, after and under them, and the layout squares a reader refuses.
`reader/hellolink/tests/lanes3.rs` reads them with the reference reader.

## 9. Test vectors

`tests/vectors/strip1.json` has one state, the frame's bytes (`frame`, 139 bytes), its
squares at both depths, the object it carries, and what the level squares read. Two images
are that row as the addon draws it at 2 pixels a square, from the image's top-left corner:
`tests/vectors/strip1_depth4.bmp` and `tests/vectors/strip1_depth2.bmp`. A reader is right
when it gets the state, the session 4711, the seq 9, the object and the levels 76, 83, 12
and unknown from each image. `reader/hellolink/tests/vectors.rs` does that with the reference reader.
`tests/make_vectors.py` made the files; #195 step 3c deleted it, and the files stay.

`objects` in the same file has eight more frames of that state, each with one whole object
in one chunk: a waypoint, a waypoint of `null`, the rested XP, a route, a route of `null`,
the character, the next steps and a fight baseline (ids 7, 7, 8, 9, 9, 10, 11, 12). For each:
`text`, `bytes` (the joined object: format, text, check) and `frame`. A reader is right when
it joins each frame to the id and the text.

## 10. The reference reader's local API

One display takes one capture stream (section 1), so two readers cannot run side by side.
A second program on the same computer asks the one reader instead:

    reader/target/release/hellolink watch --serve 8787

A program that keeps the reader running for play starts it from an installed copy, never
from a git checkout, where a checkout or a branch switch would change the code it runs next:

    reader/target/release/hellolink install-reader
    ~/Library/Application\ Support/HelloLink/reader/hellolink watch --serve 8787

`install-reader` copies the program (`hellolink`, which is also the assistant program,
`docs/specs/115.md`, section 7), the capture tool's source and a `VERSION` file (the commit)
into that folder (`--to <dir>` for another). It refuses, and changes nothing but the lock file
beside the folder, when the program was not built from the commit, when the folder holds
anything but a whole earlier install, or when the reader or the assistant program runs from
the folder (each holds that lock while it runs). The earlier install is kept beside the new
one as `reader-previous-<n>`. After a merge that changes them, when nobody plays: stop both,
build (`cargo build --release --locked` in `reader/`), install, start them again. The
assistant program runs beside the reader:

    ~/Library/Application\ Support/HelloLink/reader/hellolink assist --addons <AddOns> --reader http://127.0.0.1:8787

With `--record <file>` the reader also appends a record of every capture to that file, for
measurement offline (#178): how many bytes another format would need, how often a frame was
lost, how the palette moved. The first line of each run is `{"record": 1, "started": <Unix
time>, "colour": "srgb"}` (`colour`: the capture stream's colour space, below; a record
written before 22 Nov 2026 has no `colour` and is in sRGB); then comes one JSON line a capture:

| Key | When | Value |
|---|---|---|
| `t` | always | seconds since the run's first capture, to the millisecond |
| `frame` | the frame's bytes changed | the frame's bytes (section 3), hex |
| `depth` | the depth changed | 4 or 2; 8 for a ramp row of 8 levels (section 8) |
| `levels` | the level squares changed | the four per cent values of section 4, `null` for unknown |
| `palette` | the palette as read changed | 64 `[red, green, blue]`, 0 to 255 |
| `ramp` | the ramp as read changed (a row with the digit 1, section 8, in place of `palette`) | 10 or 22 `[red, green, blue]`, 0 to 255 |
| `lanes` | the lanes changed (format 3, section 8, "Lanes"); not written while they stay 1 | 1 to 4 |
| `why` | the capture gave no frame | the reason |
| `bad` | bytes were read, but no frame passed | the bytes as read, hex: the whole failed frame, or as much as was read when the frame ran off the image |

`depth`, `levels`, `palette` and `ramp` are written also on a capture whose frame failed. A
`palette` forgets the last `ramp` and a `ramp` the last `palette`, so a switch between them is
always written; a replay takes `gap` and `leak` from the last `ramp`. A row cut
short before its frame begins (in its palette) is no row to the reader, and `no row` here. A capture
with no change is `{"t": ...}` alone. The captures with which the reader looks for the row
(at the start, when it looks again, and each display's image in the slow fall-back) are recorded too: one line each, `why` `no row` when
the row was not on it. The stream gives a capture when its rectangle changes; the rectangle runs
from the row to the display's right edge, so a change of the game beside the row also gives a
line. An estimate, not measured: with ten new frames a second (the default dwell) and a frame
of about 330 bytes, a record grows about 25 MB an hour. The record holds the character's state: the
place, the money, the bags, the name in object 10. It stays on this computer; never commit one.

To read a record back, `reader/target/release/hellolink replay <file>` feeds it through the
same Watcher as `watch` (section 8) and prints each event that `watch --json` said, one JSON
line each, with the capture's `t` added. Each run's header comes out as `{"kind": "record",
"started": ..., "colour": ...}` (`colour` as in the header, `"srgb"` when it has none), and a
new Watcher starts with it. A line with only `t` is the last good
frame again. The record holds no picture, so the replay knows only what it holds: the
session is the frame's, a capture with no frame keeps the last depth and levels (but a row of
squares too small to read, which has no depth live either, so it is no failed frame), and at
depth 4 the palette gives how far apart its colours are (the `ask` of section 8). Not in a
record, so not replayed: which captures were the search's (the reader feeds them to no
Watcher; a replay does, which can add a `relocate` and an earlier `state` when the reader
starts or looks again), time passing with no capture, and the reader's `waiting` line.

With a row of format 2 (`docs/specs/213.md`) the events gain fields. A `state` has `format`
(2), `more` (the further level triples, per cent or `null`) and `keyAge` (seconds since its
keyframe first came). A `stale` comes 1.5 s after the keyframe, not 3 s after the last
`seq`. A delta whose keyframe is not held says no `state`. An `object` has `session`. An
object of format 253 ("secret now") has `"secret": true` on its event, and `/state` keeps the
last copy with `stale` and `secret` true, until a version that can be read. A `bad-object` (`id`, `version`, `why`) says that an
object came whole but could not be read. A record (`--record`) has `more` when it changes.
With `--names FILE` the reader keeps the names of object 25 (`"kind:id": [name, hash]`) in
FILE across runs, puts a name over the one held when its hash changes, and gives them in
`/state` as `names` (only when it holds any).

No picture while the game is not running (#348; the owner, 24 Nov 2026: "if game is not on don't
bother to read the screen. it's privacy issue"). The reader asks whether the game's own program
runs (below; at most 2 s for each command) before each search; again before a search reads the
displays (a game that quits closes its window seconds before its process ends) and before each
capture of a display; before a row found or a remembered place is streamed; before each turn of
the slow fall-back; and every 2 s while a stream runs. While the game does not run, it takes no
picture of any display or window: no list, no look, no stream, no `screencapture`. A stream is
left at its first turn after the next check (a turn comes at least every 0.5 s; the check waits at
most 2 s for each command), so usually 2 to 3 s after the game's end and at most about 5 s. It
says `waiting` with the `why` "the game is not running" (once a minute, as every `waiting`) and
asks again every 2 s. A check that fails (`pgrep` or `lsof` exits with an error, or gives no answer
in time) counts as not running, and its `why` says so: "the game is not running (its process
could not be checked: ...)". The check: `/usr/bin/pgrep '^World of Warcra'` lists the
candidates by name (macOS compares the executable's name, kept to 15 or 16 characters, and the
base name of `argv[0]`), and the game runs when one of them has the game's executable as the kernel
knows it: the first program text `/usr/sbin/lsof -a -p <pid> -d txt -Fn` lists (on Linux,
`/proc/<pid>/exe`) ends in `/World of Warcraft.app/Contents/MacOS/World of Warcraft`. Not the
command line (`pgrep -f`): a shell whose arguments name the game's path matches `-f`, and on 24 Nov
2026 at 11:33 the reader of #349 took a capture with the game closed. Not the name alone: the
game's launcher, `World of Warcraft Launcher`, has the same 15 characters, and a process can set
its own `argv[0]` (review of #351). The tests give the command-line pattern of a stand-in process
in `HELLOLINK_GAME_PROCESS` (an empty one is not taken).

The capture takes the game's own window (the application "Wow") since 23 Nov 2026, not a
rectangle of a display, so that another window over the game does not hide the row (the owner's
decision of that day; `docs/owner-decisions.md`). The search lists the game's window first
(`strip_capture --window Wow list`: one line, index 0, the window's size in pixels) and looks for
the row in it; the stream then takes the same window (`--window Wow stream 0 ...`), the rectangle
from the window's top-left corner. When the game has no window, or its capture gives no frame (a
minimised window), the search looks at the displays as before. A window whose frames show no row
(most likely a loading screen, as at a `/reload`) is no row for that search: the reader waits and
looks at the window again, five searches in a row, then once at the displays, so that a
window that never shows the row cannot hold it from a display that does (seen 23 Nov 2026: at two
`/reload`s it turned to a display, which then showed the row, and stayed there; the window's frames
were not recorded). A place in
the window has the display -1, in the reader and in the file of `--remember`, so that a restart
streams the window again. A remembered place is taken at the start only when it is of the source
the search reads first: with the window first, a display's place (kept when the window showed no
row) is not taken, and the start looks at the window again (seen 23 Nov 2026: the first start after
the install streamed a remembered display). `watch --display` takes the displays only (a remembered
-1 is not taken then). The tool picks the
largest window of "Wow" at each call (ACCEPTED limit, review of #316: the game has one main
window; a stream that no longer shows the row sends the reader to search again). When
the search finds the row on a display, not in the window, the reader says so on its error output
("the row is read from display N, not from the game's window"). A remembered place in the window
is not used with `--colour display`. Also ACCEPTED (review of #316, round 2): a Ctrl-C while the
window is listed lets the display list notice it; the hand-over of a found -1 to the stream is tested through the stream's
command and a remembered -1, not a stubbed search. A window is taken in
sRGB only: with `--colour display` the reader looks at the displays. Not seen yet: the window read
while it is covered, on another Space or minimised (`plan/05`, the window-capture box).

The capture stream gives its pixels in sRGB by default. With `--colour display` the reader
asks it for the display's own colour space instead (`docs/specs/232.md`, part C, "Deeper
colour"). It is for diagnosis: the computed palette fails there (the channels mix, `leak` 44 on
22 Nov 2026), so the hour of 9 bits runs on the default sRGB stream. Then the
capture tool gets `--colour display` before its command, for the look and for the stream, so
that a run's captures are all in one colour space, and the record's first line has
`"colour": "display"`. With `--colour display` `watch` takes no screenshots in place of the
stream: when the stream cannot run, it stops with an error. Each display has its own colour space:
keep the game on one display for a diagnostic run (the record does not mark a move to another display). The tool then names no colour space for ScreenCaptureKit, which gives
the display's own (seen on 22 Nov 2026 on this Mac: every frame carries the colour space of
`CGDisplayCopyColorSpace`; a display's colour space has no name, so it cannot be named). The
tool checks each frame: a frame in another colour space ends the stream (exit 2, "the frame is
not in the display's colour space"), and the reader starts it again. The Rust tests check the
option, the tool's arguments and the record. The tool's own part needs a screen, so CI does
not test it; on 22 Nov 2026 one frame of each was taken on this Mac: the two differed, the
display frame passed the check, and a tool that expected sRGB in its place ended with exit 2.

With a row of format 3 (`docs/specs/232.md`, section 6) and HelloLink 1.5.0, the frame's event ring gives `ring` events, each once, in order: `{"kind": "ring", "what": "loot", "item": 2589, "quantity": 3}`; `"what": "error"` with `error` (the UI error's number); `"money"` with `change` (copper, less than 0 for money lost); `"xp"` with `xp` (gained); `"level"` with `level` (the new level); `"death"`. When more events came in a gap than the ring keeps (8, of the last 10 s), `{"kind": "ring-lost", "count": 5}` comes first. The events that came before the reader read its first frame of a UI load are not said. `/state` does not keep them.

To measure how many colours a square can carry on a display (#213, step 4), draw the rows of
`/hlink probe depth <2 to 8 levels a channel> [1 to 8 pixels a square] [1 to 4 lines] [0 to 90 floor
per cent]` in the game, take a screenshot (`screencapture -x -t bmp <file>`), and read it with `hellolink depth
<file>...`. It prints one JSON line an image: `levels`, `px`, `wrong` (pattern squares named
wrong, of `of`: 240 for one line, else 256 a line), `apart` (the nearest two palette colours as
they came back), `bits` (a square), `lines` and `wrongByLine` (the wrong squares of each screen
line the pattern is on, from its first). With more than one line the pattern starts a line of its
own: the rest of the palette's line is not drawn, so a reader skips it. `/hlink probe lanes` is `depth 4 1 4`: rows of 1-pixel
squares one under the other, as format 3's lanes would be (`docs/specs/232.md`, part C). The
lines are in the first levels digit: `floor(levels / 8) + 2 * (lines - 1)`. With a floor `f`
(`docs/specs/232.md`, part C, "The computed palette"), the probe draws level `k` of the palette
and the pattern at `lo + k × (1 − lo) / (L − 1)` of full, `lo` = `f` / 100 (no floor: 0); the client
makes the bytes from that fraction (the tests round it to the nearest). The rows do not carry the floor, and the reader does
not need it: it names each pattern square by the nearest palette colour as drawn. A screenshot is not the capture stream: the two can give a colour back differently.

The same line also reads the image by a ramp, as a reader of the computed palette would
(`docs/specs/232.md`, part C, "The computed palette"). The ramp is the palette squares at its
codes: 0; L², 2L², …; L, 2L, …; 1, 2, …, L − 1 (L is `levels`). A `gap` of 0 or less means a channel's ramp does not rise: a reader of the strip refuses such a frame
(`why`: `ramp`), but this tool still prints `rampWrong`, as a diagnosis. `rampWrong` is the pattern squares
named wrong when each square is named channel by channel against the ramp (of two equally near
levels, the lower). `gap` and `leak` are those of the spec's "The reader", step 4. `floors` has an
object for each floor from 1 to L − 2: `floor`, `levels` (the floor to L − 1), and over only
the pattern squares and palette squares whose three levels are all in `levels`: `pattern` (how
many pattern squares), `wrong` (by the nearest drawn palette colour of those levels),
`rampWrong`, `gap` and `leak`. Of a floor's ramp, the other two channels are at the floor, not at
0. With `--levels 2,4,6,7` (rising, two at least), `given` is the same object for those levels,
without `floor`. `given` is `null` without `--levels`, or when the image does not draw one of
the levels.

The reader says `{"kind": "waiting", "why": "looking for the row"}` as soon as it starts, so
both requests answer at once; the first state comes when the row is found, which takes
seconds. With `--remember <file>` the reader keeps the row's display and rectangle in that
file (five whole numbers, no picture; the display -1 is the game's window) and tries that place
first at the next start, without a look at every display, when it is of the source the search
reads first (above). A place that shows no row, or gives no stream, is looked for again.

| Request | Answer |
|---|---|
| `GET http://127.0.0.1:8787/state` | The present, as one JSON object (below). |
| `GET http://127.0.0.1:8787/events` | Server-sent events: a line `data: <JSON>` and an empty line for each. The first is the present, `{"kind": "snapshot", ...}` with the keys of `/state`. Then comes every event after it, the JSON that `watch --json` prints. Nothing is missed between the two. A line that starts with `:` is a sign of life, sent after 15 s without an event. |

`/state`:

    {"state": {"kind": "state", "session": 4711, "seq": 9, "depth": 4, "fast": {...}, "levels": {...}},
     "levels": {"health": 76, ...},
     "objects": {"4": {"format": 1, "text": "{\"free\": 12, ...}", "stale": false}},
     "condition": "live",
     "age": 0.12}

- `state` is the last state read, or `null` before the first. `age` is how many seconds ago
  it was read. `levels` is the last reading of the level squares (section 4).
- `objects` has the last of each object by its id (section 6): `format` and `text` as the
  reader's `object` event gives them, and `stale` as its `stale-object` and `fresh-object`
  events say. `text` is the object's own JSON, as text. The objects are dropped when a state
  of another session comes.
- `condition`: `live` after a state; `stale`, `lost` or `waiting` after the reader's event of
  that name. The last state stays in the answer: judge it by `condition` and `age`.

A program that follows the state listens to `/events` only: the snapshot it gets first and
the events after it leave no gap, so it has no need of `/state`. `/state` is for a program
that asks now and then. A client that is 1000 events behind is dropped. So is one that does
not take what is sent to it for 10 s, or takes more than 10 s to send its request. In both
cases listen again.

The API only reads. It listens on 127.0.0.1, sends no CORS header, and answers 403 to a
request whose `Host` is not `127.0.0.1` or `localhost` with its own port: a web page in a
browser cannot read it. Another program of the same user on the same computer can. It keeps
nothing on disk. It is HTTP and not a WebSocket because the data goes one way, and a
WebSocket is open to any web page unless the server checks where the page came from.

## 11. Saved data, not on the strip: the character's looks

One thing HelloLink gives is not on the strip and not in the API of section 10: the
character's own appearance choices (skin, face, hair and what else the race has). The client
gives them only at a barber, so HelloLink takes them there and keeps them in its saved
variables (HelloLink 0.6.0, #168). A program reads them from the saved file
`WTF/Account/<account>/SavedVariables/HelloLink.lua`, in the global table `HelloLinkDB`. The
client writes that file at a logout and at a `/reload`, not before.

```lua
HelloLinkDB.looks = {
    ["Player-1-0000ABCD"] = {                 -- the GUID (1.18.0); "<name>-<realm>" before it, or with no GUID
        at = 1794516378,                     -- the client's time() when the record was taken; nil if unreadable
        race = "NightElf",                   -- the race's file name, the second value of UnitRace; nil if unreadable
        sex = 3,                             -- UnitSex("player"): 2 male, 3 female; nil if unreadable
        models = { [3] = 124, [9] = false }, -- [category id] = the category's chrModelID, or false when it has none
        choices = { [501] = 7002 },          -- [option id] = the id of the option's current choice
    },
}
```

- From HelloLink 1.18.0 the key is the character's GUID (`UnitGUID("player")`, object 10's
  `guid`; spec 276), as for `fullNames`: look a character up by its GUID first. Only while the
  client gives no GUID is the key the name and realm, as before.
- Before 1.18.0 the key was `UnitName("player")`, `-`, `GetRealmName()`: the name and the realm of
  object 10. Such a record stays until the next barber writes the GUID's. It was the key of
  HelloForever's saved data, except while the client gives `""` for the realm
  (since 20 Nov 2026): the key here is then `<name>-`, and HelloForever 0.18.4 can keep
  `<name>-<realm>` (`docs/SCHEMA.md`, Character key). So one character can have a
  `<name>-<realm>` record from before 20 Nov 2026 and a `<name>-` record from after it: take
  the one with the later `at`. The key has no family name: two characters with one first name on
  one realm share it, and a join by name cannot tell them apart: an answer from an old key is not
  confirmed.
- All ids are numbers, as `C_BarberShop.GetAvailableCustomizations()` gives them: a category's
  `id` and `chrModelID`, an option's `id`, and the `id` of `choices[currentChoiceIndex]`.
  `choices` holds the options of every category in one table.
- An option with no current choice, or with a field that is missing or of another type, is
  not in `choices`. So an option that is absent is unknown, not "the first choice".
- The record is taken when the barber's window opens (`BARBER_SHOP_OPEN`) and when a new
  appearance is applied (`BARBER_SHOP_APPEARANCE_APPLIED`). It replaces the character's older
  record whole. When the client answers nothing, or the answer holds no current choice, or
  the name or the realm cannot be read, nothing is written and the older record stays.
- `HelloLinkDB.looks` is absent until the first record. A character that never sat in a
  barber's chair with HelloLink 0.6.0 or later has no entry.
- The client writes a table whose keys are 1, 2, 3... without the keys (`{ 124, 125 }`); a
  reader must take both forms.
- The other keys of `HelloLinkDB` (`on`, `x`, `y`, `size`, `depth`, `dwell`, `session`) are
  the strip's own settings and may change without notice. Only `looks`, `probe`, `probeWindows`
  and `seen` are for a reader.
- `HelloLinkDB.probe` (HelloLink 0.7.1, #185) holds the last 8 runs of `/hlink probe api`,
  newest first: `{ at = <Unix second or nil>, why = "login" | "command" | "TAXIMAP_OPENED" |
  "MERCHANT_SHOW" | "target" | "combat" | "raid", map = <text>, level = <text>, results = {
  "<probe> [<ms> ms] <answer>", ... } }`. A login or command run has every probe; a flight
  master's map runs the taxi probe only, a merchant the two repair probes. The format-2 probes
  (HelloLink 0.8.2, #213: the `unit ...`, `nameplates`, `auras ...`, `cooldowns`, `action bar`,
  `group`, `hunter` and `timers` lines) run alone once in a UI session at each of: the first
  target (`target`), a second into the first fight (`combat`), the first raid (`raid`). The
  `addon cost` line runs only at login and on the command (HelloLink 0.8.3; it took 55.5 to 77.6 ms in 0.8.2's
  event runs, 87.2 ms at a 0.8.3 login).
  An answer is text for a person: `<secret>` for a value the client keeps secret, `absent` for a
  function that is not there, `ERROR` for a call that failed; the format-2 lines give the error's text after it (`ERROR <text>`, since 0.8.3). Its form may change in any version; it is the ground for HelloLink 0.8.0 and for
  format 2 (#213), not an interface.
- `HelloLinkDB.probeWindows` (HelloLink 1.15.0, #232, part D): the newest answer of each window's
  probe line, by its name: `{ ["window merchant"] = { at = <Unix second or nil>, why = <the event>,
  map = <text>, result = "<probe> [<ms> ms] <answer>" }, ... }`, for `window merchant`
  (`MERCHANT_SHOW`), `window loot` (`LOOT_OPENED`), `window quest` (`QUEST_DETAIL`, `QUEST_PROGRESS`,
  `QUEST_COMPLETE`; and `QUEST_GREETING` and `GOSSIP_SHOW` once each, which can come with no quest, so a
  quest window after them still samples) and `window trade skill` (`TRADE_SKILL_SHOW`; its recipes from
  `GetFilteredRecipeIDs` or `GetAllRecipeIDs`). Each runs once a UI session, when its window first opens; it never takes
  one of `probe`'s 8 runs. The same lines, and `spellbook`, are also in every login and command
  run of `probe`. Answers as in `probe`. Since HelloLink 2.5.1 also `window trade skill list`: the
  trade skill line again at the first `TRADE_SKILL_LIST_UPDATE` after a profession window opened,
  as the window fills its recipe list then (at `TRADE_SKILL_SHOW` both lists were empty, 23 Nov 2026).
  The same release adds to every login and command run `professions` (`GetProfessions`, then
  `GetProfessionInfo` for each index it gives) and two getters to `spellbook`
  (`C_SpellBook.GetSpellBookSkillLineInfo`, `C_SpellBook.GetSpellBookItemInfo`): what object 29
  (the spellbook and professions, spec 232 part D item 5) needs to know first.

- `HelloLinkDB.eventsAtLogout` (HelloLink 2.2.1): `{ at = <time()>, seen = "<name>=<count> ... | ..." }`, the
  API probe's event counts of the whole UI session (the quest log's and the talents' events among
  them), written at the logout or a `/reload`, as the "events seen" line of `/hlink probe api`. A count of 0 is an event
  this client knows that did not come in the session; `refused`, one it would not register; `at` is left
  out when the clock cannot be read, and `seen` is `"ERROR"` when the counts cannot be written.
- `HelloLinkDB.eventsSessions` (HelloLink 2.6.1): the same counts for the last 6 UI sessions, newest first:
  `{ { from = <time() when the UI loaded>, at = <time() at the logout or /reload>, seen = "..." }, ... }`. A
  `/reload` ends a session too, so `eventsAtLogout` alone held only the last one: on 23 Nov 2026 a 2.5-minute session
  after a reload replaced the counts of three hours of play. `from` and `at` give each session's length; either is left out when the clock could not be read then, so a reader takes a rate only from an entry with both and `at > from`. A list in the saved data that is not as written (an entry that is no table, a gap) is cut at that point.
- `HelloLinkDB.frames` (HelloLink 1.0.0, formats 2 and 3): `{ at = <last slot>, t = {...}, seq =
  {...} }`, a ring of the last 512 frames drawn in this UI session (`session`; a /reload starts it
  afresh): when each went up by the client's `GetTime()`, and its seq. It is set against a reader's record to tell a frame that was up too short from one
  no capture got (#213). `HelloLinkDB.format` (3 since HelloLink 2.0.0, which writes it at every load; 1, 2 or 3 before, 3 the default from 1.1.0),
  `size2` (the square size, 1 to 4) and `formatRelease` (3; the release that last moved the saved
  data to its default: 2 by 1.0.0, 3 by 1.1.0 and since) are the strip's settings.

- `HelloLinkDB.seen` (HelloLink 0.8.0) says which account folder holds the live character. Each
  login or reload (not an instance's loading screen) writes `seen["<GUID>"] = { name = "FakeHunter", realm = "Test Realm", guid = "Player-1-0000ABCD", at = 1794516378 }`
  (HelloLink 1.18.0; before it, and while the client gives no GUID, the key is `"<name>-<realm>"`
  and there is no `guid`): the name and the realm exactly as object 10 sends them, and the client's `time()` of the login
  or reload (`nil` if unreadable). A name or realm that cannot be read writes nothing. A program that
  knows object 10 looks for its `guid` as the key in every account's `SavedVariables/HelloLink.lua`
  first: the file that has it is the live character's account (a GUID is one character's). Only when
  no file has it (an install not yet logged in with 1.18.0, or a `guid` of `null`), it looks for
  `"<name>-<realm>"`, takes the file with the latest `at`, and holds the answer as unconfirmed: two
  characters with one first name, on two accounts, share that key. One entry for each
  character, kept until removed by hand. The file is written at a logout and a `/reload`.
  From HelloLink 0.8.1 an entry also has `fullName`, the name with the family name from
  `HelloLinkDB.fullNames` (below), under the character's GUID, at the login or reload, and set as soon as
  the loot gives it; `nil` before. A loot that gives the cached name rewrites the GUID's entry
  (`at` then the loot's time) when it lacks that name: after a reload with no GUID, the GUID's entry
  gets it when the GUID comes back, at the next loot or the next loading screen (whichever is first),
  not only at the next login (#201); `at` is then that loot's or loading screen's time. A logout before
  either leaves only the `"<name>-<realm>"` entry, which a reader takes as unconfirmed (an accepted limit:
  it needs a GUID that is nil at a reload, not seen in this client). The WTF folders of a character are named after it
  (`Name-Surname`), so a program can match them.

- `HelloLinkDB.fullNames` (HelloLink 0.8.1): `fullNames["<player GUID>"] = { fullName = "FakeHunter Family", source = "loot", at = 1794516378 }`, keyed by `UnitGUID("player")` (two characters can share a first name and a realm). Only a GUID of the form `Player-<server id>-<hex>` counts: `""` or another form is no GUID, and nothing is kept or sent under it (#201).
  The client's `UnitName("player")` gives the first name only. The loot message gives the name
  with the family name (seen 13 Nov 2026), so HelloLink takes argument 2 of `CHAT_MSG_LOOT` when
  argument 12 is `UnitGUID("player")`, the value is no secret, is UTF-8, at most 60 bytes, and
  is `UnitName("player")`, a space and a family name (the first name alone never counts).
  Argument 5 is not read. The same name again does not write the entry again. Another player's loot never sets it. `at` is the
  client's `time()` when the name was first taken or changed. One entry for each character.

**Not seen in the game (16 Nov 2026).** The event names and the fields are from the client's
own documentation for this build (`BarberShopDocumentation.lua`,
`CharacterCustomizationSharedDocumentation.lua`); nobody has sat in the chair with this
version. It is not known whether every race can use a barber. `plan/05-assistant-link.md`,
section 21, has the check.
