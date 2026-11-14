# The live-state strip: a reader's reference (format 1)

HelloLink draws one row of coloured squares along the top of the game. The row carries the
character's live state. Any program may read it from the screen; this page is what such a
program needs. Why the format is as it is, is in `docs/specs/29.md`. The addon side is
`HelloLink/Strip.lua`; a reference reader is `tools/strip1.py` (no I/O) with
`tools/hellolink_strip.py watch`.

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
3. Refuse a row whose squares are under 2 pixels in your capture.
4. Once found, capture only the row's rectangle. Look again when captures stop decoding.
5. On macOS with ScreenCaptureKit (measured 13 Nov 2026):
   - One stream a display at a time. A second stream on a display stops the first one
     ("application connection being interrupted"), and sometimes gets no frame itself. Two
     readers of one display cannot run side by side; streams on different displays can.
   - A stream gives its first frame at once, also of a display where nothing moves. Never
     wait for it without a limit: once, 40 minutes into a reader's run, the capture service
     (`replayd`) gave no frame to any program on any display until it was restarted. The
     cause is not known; killing a few capture processes did not reproduce it. `screencapture`
     still worked then, so the reference reader falls back to it after 3 s of silence.
     Try the stream again from the fall-back: once a stream gave no frame a single time, and
     a reader that never tried again stayed on `screencapture`, at a quarter of the rate, for
     over three hours. The reference reader tries once a minute.
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
the colours 0, 16, 0, 42 at depth 4 and the digits 0, 0, 2, 0, 0, 0, 5, 2 at depth 2.

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
| 5 | state | flags (2): in combat 128, dead or ghost 64, mounted 32, resting 16, AFK 8, casting or channelling 4, has target 2, has pet 1, loot window open 256 | 2 |
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
| 254 | none: the object is too large to send. Drop your copy. |
| 255 | none: the addon cannot read the object now. Drop your copy. |

An object you have not seen whole for `3 × 9 × 12 × dwell` (32.4 s at the default) is stale:
three rounds of the nine objects, each as large as it may be. (Six objects and 21.6 s until 14 Nov 2026, #62; eight and 28.8 s until #64.)
The last chunk of an object you hold, seen again, counts as seeing it whole: with one
one-chunk object in the queue the row shows nothing else.

| Id | Object | Text |
|---|---|---|
| 1 | question | Plain text the player typed (`/hlink send`). Sent in two rounds, then gone. Act once for each `(session, objectVersion)` that differs from the last one you acted on. |
| 2 | target | `{"name": "Wetlands Crocolisk", "type": "Beast", "class": "normal", "level": 23}`, or `null` with no target. `type` may be `null`. `class`: `normal`, `elite`, `rare`, `rareelite`, `worldboss`, `trivial`, `minus`. `level` -1 = hidden. |
| 3 | place | `{"map": 1437, "zone": "Wetlands", "sub": "Black Channel Marsh"}`; `sub` may be `""`. |
| 4 | bags | `{"free": 12, "items": [[2318, 16], [4234, 3]]}`: item id and how many the bags hold, by id. The items are those of bags 0 to 5; `free` is the free slots of bags 0 to 4, as `bagFree` of the fast block. A change of the ammunition's count alone (a shot), or a slot freed because a stack of ammunition ran out, does not make a new version: those two are as of the last other change of the bags. |
| 5 | quests | `[{"id": 290, "title": "...", "state": "accepted", "objectives": [{"text": "...", "have": 0, "need": 9, "done": false}]}]`, by id. `state`: `accepted`, `in_progress`, `ready`, `failed`, `unknown`. `have` and `need` are `null` for an objective without a count. |
| 6 | skills | `[{"id": 165, "name": "Leatherworking", "rank": 75, "max": 150}]`, by id. |
| 7 | waypoint | `{"source": "RXPGuides", "guide": "29-32 Duskwood", "map": 1434, "x": 21823, "y": 7799, "title": null, "step": 109, "text": "   Kill \|cFFFF5722Young Stranglethorn Tigers\|r\n6/10 Young Stranglethorn Tiger slain"}`, or `null`: where a guide addon's arrow points. `map`, `x`, `y` are as the fast block's position has them. `guide` is the name of the guide that is followed; `title` is the place's title or the step's arrow text; `step` is the step's number in the guide; `text` is the step's text. Each of the four is `null` when the addon holds none. The texts are as the addon holds them: with the client's colour codes (`\|c...\|r`), texture codes (`\|T...\|t`) and line breaks; a text that is not UTF-8 or is too long (200 bytes for `guide` and `title`, 600 for `text`) is `null`. `source` names the addon; RestedXP Guides is the only one read. The whole object is `null` with no such addon, or when its arrow holds no place. It does not say whether the arrow is shown. It follows the arrow, and a count in the text, within about a second. |
| 8 | rest | `{"rested": 12345}`: the rested XP, 0 for none. Format 255 when the client's value is no amount. |
| 9 | route | `{"source": "ShortestPathForever", "owner": "RestedXP", "goal": {"map": 1415, "x": 31934, "y": 34315, "title": "RestedXP"}, "seconds": 40, "index": 1, "guided": true, "legCount": 1, "legs": [{"mode": "walk", "seconds": 40, "text": "Walk to RestedXP"}]}`, or `null`: the journey that a route addon has planned. `goal` is where it ends: `map`, and `x`, `y` as the fast block's position has them, on that map, which can be a continent's; `title` as the addon names it. `seconds` is the time left, `legs` the legs from the one under way on, each with `mode` (the addon's word: `walk`, `flight`, ...), `seconds` and `text` (what to do). `index` is the number of the leg under way in the whole plan, `guided` whether the addon guides now, `owner` who asked for the journey. `legCount` is how many legs are left, or `null` when there are more than 200; `legs` has the first 20 of them. Seconds are cut to whole seconds. A value that is no amount, no word or no UTF-8 text of a fit length (120 bytes for a leg's `text`) is `null`. A leg has no place: the addon's interface gives none. `source` names the addon; Shortest Path Forever is the only one asked, through its public interface, which only reads. `null`: no such addon, no journey, or a plan that is not ready. While a journey goes on the time left changes, so the object comes anew about every two seconds. |

JSON keys are exactly those shown; ignore keys you do not know. "Nothing there" is content
(`null`, `[]`), not a missing object.

## 7. When six bits do not hold

The addon cannot see the screen. With its depth setting on `auto` (the default) it starts
each UI session at depth 4 and falls back to depth 2 when a reader asks. With the setting on
`2` or `4` the player fixed the depth: the addon keeps it and looks at no request, so a
reader must not wait for a fall-back that the depth square never shows. A reader that finds
depth 4 unreadable asks by writing a field into the slot files that carry text into the
game (`tools/hellolink.py write <AddOns> "" --strip-session <n>`):

```lua
HelloLink_Inbox = { seq = 1794516378971, text = "", strip = { session = 4711, depth = 2 } }
```

`session` is the number from the row's session squares, which are two-level and readable
when no six-bit frame is. Ask when, over your last 200 frames at depth 4, more than 2 in 100
failed the check (count every frame as failed if you never read one), or when the two
nearest palette colours came back less than 12 apart (the largest of the three channel
differences, 0 to 255). The addon looks at a slot 30 s, 1, 2 and 5 minutes after the UI
loaded and every 10 minutes after that, and acts only on a request that names its own
session. Leave the request in every slot while the row shows that session (a later write of
a text must carry it over; `tools/hellolink.py` does). Each look uses one of the session's
slots (200 as installed); when they are used up the addon stops looking and keeps its depth.
Until the depth square shows 2, drop the frames that fail.

## 8. Later versions

Version 1 only grows: bytes at the end of the fast block, `known` bits, object ids, JSON
keys. Ignore what you do not know. A change of the layout, the finder, the bit order, a
frame field or the meaning of an existing field is a new version, announced in
`CHANGELOG.md`.

## 9. Test vectors

`tests/vectors/strip1.json` has one state, the frame's bytes (`frame`, 139 bytes), its
squares at both depths, the object it carries, and what the level squares read. Two images
are that row as the addon draws it at 2 pixels a square, from the image's top-left corner:
`tests/vectors/strip1_depth4.bmp` and `tests/vectors/strip1_depth2.bmp`. A reader is right
when it gets the state, the session 4711, the seq 9, the object and the levels 76, 83, 12
and unknown from each image. `tests/strip1_test.py` does that with the reference reader;
`tests/make_vectors.py` made the files.

`objects` in the same file has three more frames of that state, each with one whole object
in one chunk: a waypoint, a waypoint of `null`, the rested XP, a route and a route of `null`
(ids 7, 7, 8, 9, 9). For each:
`text`, `bytes` (the joined object: format, text, check) and `frame`. A reader is right when
it joins each frame to the id and the text.

## 10. The reference reader's local API

One display takes one capture stream (section 1), so two readers cannot run side by side.
A second program on the same computer asks the one reader instead:

    python3 tools/hellolink_strip.py watch --serve 8787

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
