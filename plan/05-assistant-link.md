# Find out how the assistant can talk to the running game

**Why.** The assistant (`docs/north-star.md`) lives outside the game: an addon cannot open a
connection or read a file. Today the only way out is SavedVariables at a reload, and
nothing comes back in. Another project, chelinho139/wow-ai (MIT), reports three facts
about the Forever client. On 12 Nov 2026 this repo saw all three hold (sections 1 to 3):

1. The client reads a load-on-demand addon's file from disk when the addon is loaded, so a
   program can put text into a slot addon that existed at client start. No reload.
2. `ReloadUI()` works only from a key press or a click, never from a timer.
3. A program can read coloured squares the addon draws in a corner of the screen. No reload.
   (Their strip, slots and sound-file signals are described in their `docs/ARCHITECTURE.md`.)

`HelloLink` tests 1 and 2. It is a spike: one file, not part of the HelloForever package.

**Install**, while the game is closed (the client only knows addons that existed when it
started). It creates `HelloLink` and 50 slot addons. Installed when
`ls "<AddOns>/HelloLink_S050/Inbox.lua"` finds the file:

```
reader/target/release/hellolink install "/Applications/World of Warcraft/_forever_/Interface/AddOns"
```

## 1. Text into the game without a reload: works (12 Nov 2026)

Seen by the owner on the development Mac, HelloLink 0.0.1, 50 slots, the game running
throughout and no reload or character switch between the polls:

- [x] `/hlink` (slot 2) showed a text written at 20:46:18, after the poll of slot 1.
- [x] `/hlink` (slot 3) showed a text written at 20:48:20 by a timed job, after the poll of
      slot 2. So the client reads a slot's file when the slot is loaded, not before.
- [x] Chinese text shows correctly.
- [x] After a character switch (a UI reload) the slots start at 1 again and show the latest text.
- [x] `nothing new` on an unchanged inbox, and the slots running out: seen on 15 Nov 2026
      (section 9).

**Removed on 14 Nov 2026 (#45):** format 0 (the text strip of `/hlink send`, read by
`tools/hellolink_strip.py read`), `/hlink reloadtest`, and the probes `squares`, `secrets`,
`bars` and `curves` (with `probe --rate`). Sections 2 to 4 below are the record of what they
showed. `/hlink probe depth` stays for the checks of #60. `/hlink send` now gives the
question to the strip (object 1) and draws nothing of its own.

- [x] Seen 14 Nov 2026 on the level 1 bank character, typed by the agent after `/reload`:
      `/hlink send` said "sent to the strip as the question" and the shared reader showed
      object 1 with the text; with the strip off it said "the strip is off" and sent nothing;
      `/hlink probe depth 4` was read by `hellolink_strip.py probe --screen` as 4 levels, 0 of
      240 wrong, the nearest two colours 27 apart; after `/hlink hide` the reader found no
      depth row; `/hlink probe squares` and `/hlink reloadtest` said the usage. That no text
      strip of `/hlink send` was drawn was not checked by eye (the mock test covers it).

## 2. ReloadUI without a key press: refused (12 Nov 2026)

- [x] `/hlink reloadtest`: chat showed "Interface action failed because of an AddOn", then
      `still here, so the reload was refused (no error)`. Recorded in `plan/01`, section 9;
      HelloForever 0.8.1 removed the feature that needed it (#20).

## 3. Text out of the game without a reload: works (12 Nov 2026)

`/hlink send <text>` draws the text as coloured squares near the top-left corner of the game
for 30 s. `tools/hellolink_strip.py read --screen` takes a screenshot of every display,
looks for the strip, prints the text and deletes the screenshots.

Seen on the development Mac (three displays, the game on the 2560 x 1440 one):

- [x] `/hlink send hello 你好`: chat said `strip up for 30 s: 12 bytes in 54 squares`, and a
      reader polling the screen printed `hello 你好` (21:29:11). A square was 7.17 pixels wide
      in the screenshot, not a whole number; the colours were pure to within 2 of 255, except
      blue, which came back as (0, 46, 255).
- [x] The program that ran the reader already had Screen Recording consent
      (`CGPreflightScreenCaptureAccess()` was true). Without it macOS gives a screenshot of
      the desktop picture only, and the reader says `no strip`. Only the owner can give it
      (System Settings, Privacy & Security, Screen & System Audio Recording).
- [x] **Another addon can sit on top of the strip.** One installed on this Mac draws a row of the same kind
      of squares, 8 pixels high, at the very top-left in the TOOLTIP strata. The first build
      (0.0.2) drew there too and was hidden; the strip now starts 24 UI units lower (#26).
- [x] **Hot load works for a changed `.lua` file**: the new `HelloLink.lua` was copied in
      while the game ran, and `/reload` loaded it (the `send` command appeared). A changed
      `.toc` or a new file still needs the client to restart (not tested here; reported by
      chelinho139/wow-ai).
- [ ] Not tried: a long text (several rows), `/hlink hide`, exclusive full screen.

## 4. Probes for the live-state strip (`docs/specs/29.md`, section 9): run on 12 Nov 2026

HelloLink with the probe commands was copied in while the game ran and loaded by `/reload`.
The game was on the 2560 x 1440 display.

**P1, square sizes** (`/hlink probe squares`, read by `tools/hellolink_strip.py probe --screen`,
twice, one second apart; each row is the finder and 120 digits of a known pattern):

| Asked for | Measured | Wrong digits |
|---|---|---|
| 8 pixels | 8.00 | 0 of 120 |
| 4 pixels | 4.00 | 0 of 120 |
| 3 pixels | 3.00 | 0 of 120 |
| 2 pixels | 2.00 | 0 of 120 |

So squares asked for as `N * 768 / physicalHeight / UIParent:GetEffectiveScale()` UI units
come out N pixels apart, and a reader reads them without an error, down to 2 pixels. That
run measured the spacing along the row and the colours. A second run (22:31, with the
reader that also measures a row's height) gave 8, 4, 3 and 2 pixels high for the four rows,
again with 0 of 120 wrong: the squares are true squares.

**P2, secret values** (`/hlink probe secrets`; every value an API returns is checked, and
for the position the coordinates themselves; samples out of combat, while casting, and 2 s
into a fight; the results came out through the strip and were read from the screen,
22:29:37 to 22:29:59):

- Secret in **every** sample, so also out of combat: the player's health and power, the
  target's health and maximum health, the pet's health.
- Readable in every sample: the maxima of the player's health and power, the power type,
  level, XP and its maximum, dead, mounted, resting, AFK, target exists, target level,
  target hostile, target classification, target tapped, target name, the pet's maximum
  health, map, position (the coordinates), facing, money, free bag slots.
- A cast in progress (`UnitCastingInfo`, all its values) was readable in the casting sample.
  A channel was not tried.
- `GetPetHappiness` does not exist on this client.

An addon cannot do arithmetic on a secret value, so the strip cannot carry current health
or power as numbers.

**P5, bars** (`/hlink probe bars`): the client lets an addon hand a secret value to a status
bar. Four bars of 100 pixels, 3 pixels high, at the very top-left, fed straight from the
API; the reader measures the white part.

- The reader followed a fight: target health 100, 82, 62, 46, 33, 18, 0 per cent over ten
  seconds, power 92 to 100, pet health 99 down to 90.
- Against the game's own numbers in a screenshot taken between two readings: power 1298 of
  1335 (97 %) between readings of 96 and 99; target 99 of 803 (12 %) between 18 and 0; pet
  1258 of 1355 (93 %) at a reading of 93; health 1158 of 1158 at 100.
- With no target the target bar reads 0: the bar alone cannot tell "no target" from "dead".

**P3, capture rate** (`tools/hellolink_strip.py probe --rate`): 7.3 captures a second of a
600 x 80 rectangle, each searched for a text frame and for probe rows (no strip was up; an
earlier run that only parsed the image gave 8.6). Following a moving strip frame by frame
is not measured yet. A capture of all three displays with a decode
took about 0.7 s (`time` of `read --screen`, no strip up).

**P6, colours a square** (`/hlink probe depth <levels> 2`: a palette of every colour, then
240 squares of a known pattern, 2 pixels a square; the reader names each square by its
nearest palette colour):

| Levels a channel | Colours | Bits a square | Wrong of 240 | Nearest two palette colours |
|---|---|---|---|---|
| 4 | 64 | 6 | 0 | 27 apart |
| 6 | 216 | 7.75 | 1 | identical |
| 8 | 512 | 9 | 4 | identical |

Again on 20 Nov 2026 at **1 pixel a square** (`/hlink probe depth <levels> 1` on the level 1 test character,
read with `hellolink depth`, #223; the values are in #213):

| Levels a channel | Colours | Bits a square | Wrong of 240 | Nearest two palette colours |
|---|---|---|---|---|
| 4 | 64 | 6 | 0 | 27 apart |
| 5 | 125 | 6.97 | 0 (3 screenshots) | 5 apart |
| 6 | 216 | 7.75 | 1 | identical |
| 8 | 512 | 9 | 4 | identical |

So 1 pixel reads as well as 2. Five levels read with none wrong, but 5 apart is under the 6
that one colour moved over an hour of play (#213); 4 levels stays the depth.

The palette of the 6-level row, as the screen gave it back: each channel alone keeps its
levels well apart (0, 38, 90, 146, 204, 255 for sent 0, 51, 102, 153, 204, 255, red and
green alike). Blue leaks into green: sent blue 51, 102, 153, 204, 255 came back with green
2, 9, 22, 35, 46. So "full blue, no green" and "full blue, the lowest green" came back the
same colour, and every near-identical pair was of that kind. What this shows for four
levels a channel is one sample with 0 of 240 wrong (the pattern holds 63 of the 64 colours)
and a nearest pair 27 apart; whether that holds over time and on other displays is not
measured. More levels need a palette that avoids those colours, or a capture in another
colour space (not tried).

**P7, colour curves** (`/hlink probe curves` beside `/hlink probe bars`, through four
fights, 23:44 to 23:47): the client turned the secret per cent of health and power into a
step curve's colour, and the reader read 128 levels from three squares.

- The per cent runs 0 to 1. The squares built for a per cent of 0 to 100 put their first
  step at 0.78, so with a per cent of 0 to 1 they can only read level 0 or 1: they read 1
  per cent for player health and for power at 78 per cent or more, and 0 for power at 72 to
  74 per cent and for a target at 0, as that predicts.
- Squares against bars, read from the same screenshot: target health 79/78, 53/53, 9/9,
  45/46, 20/21; pet health 98/98, 91/90, 55/54, 38/38; power 94/94, 84/84, 73/72; player
  health 95/96, 98/98. Never more than 1 apart.
- Full health reads 99: the top level of 128 is 127. A build that wants 100 uses more levels.

**Threat** (bars 5 and 6 of `/hlink probe bars`, the same fights): the pet's threat read
100 while it held the mob and the player's 14 to 76; at 23:45:53 the player's read 100 and
the pet's 82, and the player's health went from 100 to 95 in that reading.

**P2 again, with more values** (`/hlink probe secrets`, 23:48 to 23:50, the last sample
typed in the middle of a fight):

- Threat (`UnitDetailedThreatSituation`, player and pet) is readable, not secret, when the
  unit is on the mob's list; it returns nothing before that (2 s into a fight it had not).
- Readable: the main-hand item, the temporary weapon enchant, whether the target's target
  is the player. A cast again (all its values).
- Secret: `UnitHealthPercent` without a curve, as expected.
- `GetNumSkillLines` and `GetSkillLineInfo` do not exist on this client (HelloForever's
  snapshot reads skills another way). A channel was still not tried.

**P4, compression**: not run yet (`/hello selftest` lists `C_EncodingUtil.CompressString`).

## 5. The live-state strip, format 1 (HelloLink 0.1.0): read in the game on 13 Nov 2026

`HelloLink/Strip.lua` draws the row of `docs/specs/29.md`. It is a new file and the `.toc`
changes, so it is installed while the game is closed (`hellolink install`, which
now makes 200 slots). Installed on the development Mac on 13 Nov 2026, while the game was
closed: HelloLink 0.1.0 and 200 slots; the installed files equal the repository's.

- [ ] HelloLink 0.6.1 (#175), the strip made lighter: with the reader running, the local API
      says `live` for five minutes of play (walking, a fight, the bags changed) with no
      `relocate` and no fall-back; and the client's own count of HelloLink's memory
      (`/run UpdateAddOnMemoryUsage() print(GetAddOnMemoryUsage("HelloLink"))`, twice, a minute
      apart, standing still) grows by less than 1 MB. In the test client the strip asks for 5 to 7
      KB a second (133 before in LuaJIT, 449 in Lua 5.5); the game's number is not known.

- [ ] Every slot sits under HelloLink in the AddOn list (#173): after `hellolink
      install` with the game closed, the list shows HelloLink slot 001 to 200 indented under
      HelloLink. Seen on 17 Nov 2026 before the fix: 001 to 003, whose installed TOC had
      `## Group: HelloLink`, were indented; 004 onward were not.

To follow the row from the Mac, with the game running:

```
reader/target/release/hellolink watch --addons "/Applications/World of Warcraft/_forever_/Interface/AddOns"
```

It builds the capture stream once (`swiftc`), finds the row on any display, then prints a
line for each new state and each object. `--json` prints every event whole. With
`--addons` it asks the strip to fall back when six bits a square do not hold. A single
frame can also be read from a screenshot saved as BMP:
`reader/target/release/hellolink rows <file.bmp>`.

### Result of the game run, 13 Nov 2026

One character (a level 30 hunter with a pet), the game full-screen on a 2560 x 1440 display,
the row at (0, 0), 2 pixels a square. The reader was `watch --json` with the capture stream at
30 frames a second, in runs of ten minutes; the numbers below are from four runs, 2031 s.

| What | Result |
|---|---|
| Frames read | 18 615, every one with a good frame check |
| A new frame | every 0.106 s (median), 0.127 s (95%), 0.160 s (99%); the owner's target is 0.1 s |
| Frames missed | 187 of 18 802 sequence numbers; 122 of them in two loading screens (6 s and 12 s without the row) |
| Depth | six bits a square for 18 497 frames; the reader never asked to fall back |
| Depth 2, by `/hlink strip depth 2` | 118 frames in 12 s, then back to depth 4 with `depth auto`, no frame lost at either change |
| Level squares | health, power, pet health and target health followed four fights (target health 100 down to 0 in steps the reader saw; pet health 100 to 61 and back) |
| Numbers against the game's frames | level, XP, health and power maxima, the pet's maximum, money, free bag slots, skill ranks: the owner compared them, all equal |
| Threat | the pet at 100 and the player rising from 0 to 98; the player at 100 and the pet at 71 when the player took the mob |
| Cast | a spell id and the tenths left, three casts in fights and one of 11.6 s |
| UI error | the counter went from 18 to 38 with the error's number |
| Flags | in combat, target, pet, casting, loot window open, on a taxi |
| Facing | 2 when facing north, 59 after a quarter turn to the left: zero is north, and the number grows counter-clockwise, now written in `docs/STRIP.md` |
| Objects | question (`/hlink send test` came out as object 1), target, place, bags, quests and skills all arrived; a place the client could not give in a loading screen came as format 255 |
| Compression | the larger objects came compressed by the client and Python's `zlib` read them |
| From a new target to its object | 0.42 s (median), 0.92 s (90%), 1.65 s (worst) over 105 targets; 10 took longer than the owner's 1 s |
| From a bag change to the bags object | 0.42 s (median), 0.82 s (90%), 1.89 s (worst) over 21 changes; 1 took longer than 1 s |

Found and fixed in this run:

- The loot counter never counted (#39): the name in the loot message is not `UnitName`.
- The reader waited for ever when the capture service gave no frame (#38). The cause of the
  service's silence is not known.

Still open:

- [x] The owner's word that the row at (0, 0) covers nothing he uses, and that the game does
      not hitch because of it. The owner, 13 Nov 2026: "All good I like it. Without focus it
      is unnoticeable. No distractions or lag at all."
- [ ] Ongoing (#60). The fall-back asked for by a reader (the slot request): never needed in
      this run, so not seen end to end. Only `/hlink strip depth 2` by hand was seen. In the
      logs of 13 Nov 2026 (about five hours of reading) the reader never asked.
- [x] The row was on no display for 35 minutes on 13 Nov 2026 (`waiting: no row on any
      display`), from soon after the owner was asked to change the UI scale until his
      `/reload`. The character's XP was the same before and after. The owner, asked
      whether he was away from the game's screen in that time: "Yes, I was away". The
      reader's log made it look like a row that stood still (#52).
- [ ] Ongoing (#60). Six bits a square for an hour without a break, and on another display.
      Seen on 13 Nov 2026, on the one display: every state of about five hours of reading was
      at six bits (54,427 states in the two longest logs), and the reader never asked for
      the fall-back. An hour without a break was not seen: the longest stretch with no gap
      over 1.5 s was 38 minutes, and that was on the `screencapture` fall-back. The gaps fell
      at times when the owner wrote in another program, when the game's own count stood
      nearly still, or when the reader was on the slow fall-back before #56; their causes
      were not proved. The logs do not count frames that failed the check, and the reader
      asks only above 2 in 100, so how many failed is not known.
- [x] A channelled spell's values. Mend Pet on 13 Nov 2026: `cast` showed spell 3661 with
      `tenths` from 50 down to 1 over five seconds, then nothing. A herb gathered showed
      spell 3570 the same way, from 49 down. Not tried: Eyes of the Beast, Tame Beast, Volley.
- [x] A change of the UI scale in the game's settings (13 Nov 2026, the owner, for more than
      ten seconds): the reader's log, with the time on every line, has no break over 1.5 s
      and no new search. The scale's values were not noted.
- [ ] Ongoing (#60). The row at a scale other than 1 (a window, or a display with a backing
      scale). The development Mac's three displays are all 1:1, so only a window can be tried
      there.
- [x] With no row on any display the reader says `waiting` once a minute (#52). Seen on
      13 Nov 2026, 23:20 to 23:31, the owner away from the game: 10 `waiting` lines in
      10.6 minutes, one `relocate`, then states again without a restart.
- [x] After the capture stream failed the reader tries it again (#56). Seen on 14 Nov 2026,
      the game on screen: the stream failed ("no list of the displays in 3 s"), the reader's
      states fell from about 260 in 30 s to 53, 21 and 106, and were at 263 again after that,
      with no restart. Why the stream failed is not known.
- [x] A hunter's shots change the ammunition count, so the bags object was sent again about
      every two seconds in a fight (item 3030 went down by one 187 times in the run). The
      owner chose on 13 Nov 2026: the ammunition's count alone is not a change, and may be
      late. In the addon since #44, by the item in inventory slot 0. Seen in the game on
      13 Nov 2026: `/dump GetInventoryItemID("player", 0)` printed 3030; in three fights with
      the bow `watch --json` showed no bags object (id 4) for the shots, and one after a
      looted item (the row's clock, in whole seconds, read 17721 at the loot and 17722 at
      the object), with the arrows at 2339 after 2343. Check after a change:
      the same dump, and a fight with the bow. If slot 0 gives nothing, the addon behaves
      as before (every shot is a change).
- [x] **The sixth bag (#50).** The owner received Bruiseweed (item 2453) and Wool Cloth
      (item 2592); the `loot` group reported both, and neither was in the bags object, which
      read bags 0 to 4. `/dump C_Container.GetContainerNumSlots(5)` printed 8. With bags 0 to
      5 read (13 Nov 2026, after `/reload`): the object held `[2453, 2]` and `[2592, 5]`, and
      two more Wool Cloth made a new object with `[2592, 7]`. Check after a change of
      `bagsText`: receive a herb or a cloth, and `watch --json` shows a bags object (id 4)
      with that item. Not known: what bag 5 may hold, so `free` does not count its slots.
- [x] The slow fall-back (`screencapture`) reported "no row" for every second image: it fed
      every display's image to the reader. Fixed in #46: it gives the image of the display
      that shows the row and then captures only that display. Shown by a test with a stand-in
      for `screencapture`. Seen with the game on screen on 13 Nov 2026: the reader's stream
      stopped ("application connection being interrupted") while a second stream was
      started by hand; the reader went on with `screencapture` and gave states and objects.
      How many of its images missed the row was not counted.

Loot (the `loot` group, #39):

- [x] After `/reload`, loot three items one after another. `watch --json` shows `loot.counter`
      1, 2, 3, each with the item's id and quantity. Done on 13 Nov 2026: items 5529, 2592,
      4306, quantities 1, 1, 2.
- [x] What the client gives with `CHAT_MSG_LOOT` (a probe, 13 Nov 2026): arguments 2 and 5 are
      the character's name with a family name and no realm; `UnitName("player")` is the first
      name only; argument 12 is the player's GUID, equal to `UnitGUID("player")`. The addon
      compares the GUID.
- [ ] Ongoing (#60). In a group, another player's item does not move the counter. Not yet
      seen in the game; only the mock client covers it.

The waypoint and the rested XP (objects 7 and 8, #62):

- [x] A probe, 13 Nov 2026 (`/dump`): `RXP.arrowFrame.element` held `zone` 1434, `x`
      40.635038182542, `y` 3.5139672370787 and no `title`; `GetXPExhaustion()` gave nothing
      for a character with no rested XP.
- [x] After the changed `Strip.lua` was copied in and `/reload` (14 Nov 2026, the first
      version, without `step` and `text`): the reader's API gave object 7 as map 1434,
      `x` 21823, `y` 7799 (33.3 and 11.9 per cent), `title` null, with the character on the
      same map at 38.5, 15.0; and object 8 as `{"rested": 0}`. The owner did not compare the
      place with a `/dump` at that moment.
- [x] A second probe, 14 Nov 2026: `element.text` and `element.tooltipText` held nothing;
      `step.index` was 109; `step.text` was the step's line, with colour and texture codes
      and a line break ("Kill ... Young Stranglethorn Tigers ... 6/10 ... slain").
- [x] After the version with `step` and `text` was copied in and `/reload` (14 Nov 2026): the
      reader's API gave object 7 as map 1453, `x` 43269, `y` 48555 (66.0 and 74.1 per cent),
      `title` null, `step` 132 and a `text` of three lines ("Talk to ... Elling Trias", "Turn
      in The Missing Diplomat", "Accept The Missing Diplomat", each with a texture code), with
      the character on the same map at 64.7, 69.9. The step had gone from 109 to 132 between
      the two reloads. Object 8 was `{"rested": 2468}`, the character in a city.
- [ ] Not tried: a hidden arrow (the object does not look whether the arrow is shown); what
      `title` holds for each kind of step; the count in `text` going up without a reload.

The guide's name and the route (object 7's `guide`, object 9, #64):

- [x] A probe, 14 Nov 2026 (`/dump`): `RXP.currentGuide.name` was "29-32 Duskwood".
      `ShortestPathForever.API.Journey()` gave `secondsLeft` 40, a `goal` of map 1415 with
      `x` 0.48728519678116 and `y` 0.52361696958542 and the title "RestedXP", one leg (`mode`
      "walk", 40 s, "Walk to RestedXP"), `owner` "RestedXP", `guided` true, `index` 1.
- [x] After the changed `Strip.lua` was copied in and `/reload`, 14 Nov 2026, read through the
      local API: object 7 named the guide ("29-32 Duskwood", map 1455, step 150). Object 9 had
      the goal (map 1415, "RestedXP"), `guided` true, `index` 1 and one leg ("walk", "Walk to
      RestedXP"). Its time moved with the character: 39, 40, 41, then 39 seconds in half a
      minute. Not compared by eye with the route addon's tracker.
- [ ] Not tried: a journey of several legs (a flight, a boat); what the route object costs
      (it asks the route addon every two seconds); the owner's word that the game does not
      hitch because of it.

The guide's next steps (object 11, #74; asked for by a local program):

- [x] A probe, 14 Nov 2026 (`/dump`, typed by the agent, on a guide of the first levels):
      `RXP.currentGuide.steps` is a list; `steps[3].index` and `steps[4].index` were 3 and 4;
      each `steps[n].text` was a text of several lines with colour and texture codes, as
      the current step's text in object 7. The count of the steps and `RXP.currentStep`
      scrolled out of the chat and were not read.

- [x] A second probe, 14 Nov 2026: `steps[3].elements` had 12 entries; `elements[1]` had
      `zone` 1429, `x` 46.4 and `y` 40.3, per cent of the map as the arrow's element.
- [x] Seen 14 Nov 2026 on the level 1 bank character, after a `/reload` that the agent
      typed, by a reader run for 45 s: with object 7 at step 2 of a guide of the first
      levels, object 11 had steps 3, 4 and 5, each with a place on map 1429. Step 3's place
      (x 30408, y 26411) is the 46.4 and 40.3 per cent of the probe. Steps 4 and 5 had their
      texts of two and three lines. Not compared by eye with the guide's window.
- [x] Step 3's `text` was `null` in that run: its text is longer than the 400 bytes a step
      may have. Decided with the local program (#78): a text over its limit is cut and ends
      with an ellipsis, in object 7 too.
- [x] Seen 14 Nov 2026 on the level 1 bank character, after a login that the agent made,
      read through the shared reader: step 3 came with a text of 399 bytes that ends with an
      ellipsis. The cut fell after a whole texture code, inside a line; the object was whole
      (format 1), with steps 4 and 5 of 231 and 157 bytes beside it. In an hour of the
      owner's play before, no step passed 400 bytes.

The target's id and reaction (object 2, #82; asked for by a local program):

- [x] A probe, 14 Nov 2026 (`/dump`, typed by the owner, on a creature out of combat):
      `UnitGUID("target")` gave `Creature-0-<server>-<instance>-<zone>-1984-<spawn>`,
      `UnitReaction("target", "player")` gave 4, and `issecretvalue` said false of both.
- [x] Seen 14 Nov 2026 on the level 1 bank character, with a city guard targeted by the
      agent (`/target`, no combat): the target object had `id` 68 and `reaction` 5.
- [x] A hostile creature, out of combat, 15 Nov 2026 (`/dump` typed by the owner):
      `UnitGUID("target")` gave `Creature-0-6848-1-6-4341-3A407B17AB` (creature id 4341),
      and `issecretvalue` said false. So the `target` card can read its key out of combat.
- [ ] Not tried: in combat, where the client may keep them secret (then `null`).
- [ ] Not built: what a creature casts (a probe of the target's cast events is asked of
      the owner), and what drops from it.

The instance in the place object (object 3, #91; asked for by a local program):

- [x] A probe, 14 Nov 2026, on the bank character in a city: `IsInInstance()` gave false and
      `"none"`; `GetInstanceInfo()` gave `"Eastern Kingdoms"`, `"none"`, 0, `""`, 0, 0,
      false, 0, 0; `issecretvalue` said false of the name.
- [ ] Inside a dungeon (the owner's character; the agent does no combat): the place object
      has `instance` true, `instanceType` `party`, the dungeon's map id and name, and the
      fast block's position is or is not unknown. The probe line for the owner:
      `/dump C_Map.GetBestMapForUnit("player"), GetRealZoneText(), IsInInstance(), GetInstanceInfo()`

Indoors, swimming and flying in the state flags (#101; asked for by a local program):

- [x] A probe, 15 Nov 2026, on the owner's character: `UnitPosition("player")` gave z 0 (no
      height on this client); outdoors on the ground `IsIndoors`, `IsSwimming`, `IsFlying`
      were false; in a building `IsIndoors` was true and the map stayed the zone's; on a
      flight path `IsFlying` was false. None was secret.
- [x] Seen 15 Nov 2026 after the owner's `/reload`: swimming in a city canal, the shared
      reader showed state flags 1040 (swimming 1024 and resting 16). `IsSwimming` was true
      there by `/dump`, on the city's own map (map type 3).
- [ ] Indoors (512) through the strip: seen true by `/dump` in a building, not yet through
      the reader. Flying (2048) needs a flying mount; not tried. Whether `UnitOnTaxi` tells
      a flight path is not probed (a local program asked for a separate bit, 4096).
- [ ] In a cave or mine: whether the map is the cave's own (map type 5) or the zone's.

The reader streams only (#103, merged 15 Nov 2026):

- [x] Measured the same night, the capture program alone on a side display: the first frame
      came in 4 to 11 s under load. 4 of 12 starts gave no frame: 3 waited 40 s with none (2
      of them with no added load), 1 ended with none (numbers in #103). The reader waits
      15 s, then tries again.
- [x] Seen in play before the change, by the local program's log (01:00 to 02:15 UTC): the
      old reader logged "declined TCCs", "no list of the displays in 3 s" and "no frame in
      3 s", fell back to screenshots and gave one state every 3 to 6 s. The refusal by
      consent came and went; a reader started from a shell saw it once on 14 Nov too. Its
      cause is not known.
- [x] Load test, 15 Nov 2026, the new reader on the bank character in a city: 9.5 states a
      second with no added load (load 13), 9.6 with 10 CPU-bound processes (load 27); the longest
      gap 0.6 s; no stale, no waiting; always on the stream, never on screenshots (#103).
- [x] Seen 15 Nov 2026: the agent's screenshots had failed for an hour, and first frames
      of the capture program took 4 to 11 s. After the owner ran `killall replayd` (it had
      run 1 day 16 h; macOS starts it again), the screenshots worked, the reader took its
      stream again by itself, and 5 of 6 first frames came in 1.06 to 2.03 s; 1 of 6 gave
      none in 40 s. What made the starts slow is not known. If the strip goes stale for a
      long time again, restarting `replayd` is a cheap first step to try.
- [ ] In play after the change: how often the reader says the stream does not answer, and
      how long until the next state (the local program counts them).

Which character is in the game (object 10, #68):

- [x] Seen 14 Nov 2026 on the level 1 bank character, after a login with the changed
      `Strip.lua`, by a reader run for 40 s: object 10 had the first name and the realm's
      display name. `/dump` in the game gave the same from `UnitName("player")` and
      `GetRealmName()`; `UnitFullName` gave no more. They make the key of the character in
      HelloForever's saved data. They are not the names of the client's folders of saved
      files: those were a number and the name with its family name. The first wording of
      the docs said they were; it is corrected (#72). Objects 2 to 9 were read in the same
      run.
- [x] The agent typed that `/dump` itself (owner decision of 14 Nov 2026): the first game
      check without the owner at the keyboard.

**Closed on 13 Nov 2026 by the owner's decision** (`docs/owner-decisions.md`), with the boxes
marked "Ongoing (#60)" not done. They are noted here, with the date and what was seen, when
a play session happens to show them; nobody plays a session for them. A check that fails
becomes a bug of its own. The box on #56 is noted the same way.

The next step of priority 3 in `docs/north-star.md`: a baseline for a fight (spec: `docs/specs/93.md`). The two channels
work in the game: text goes in through the slots, and the state comes out on the row, which
other local programs read from one reader (`docs/STRIP.md`, section 10).

## 6. The fight baseline, step 1 (HelloForever 0.9.0, #99)

The addon keeps the last fights against each enemy at each level (`docs/specs/93.md`,
step 1). The harness proves the rules; the game check needs fights, and the agent does no
combat.

- [ ] Owner: five fights with one kind of enemy, one enemy at a time, at one level. Then
      `/reload` and look in `HelloForever.lua`: `baseline["<creature id>:<level>"]` holds
      five fights, oldest first, each with its `key`, `dur`, `dps`, `taken` and `died`.

## 7. The fight baseline, step 2 (HelloForever 0.10.0, #104)

The line after a fight (`docs/specs/93.md`, step 2). The harness proves the medians and
the commands; the game check needs fights, and the agent does no combat.

- [ ] Owner: `/hello baseline on`, then fights against one kind of enemy, one at a time, at
      one level. After each fight one chat line comes: `first fights, N so far` for the first
      three, then `<name> (lvl <level>): <s> s, usual <s> s · <dps> dps, usual <dps> · taken
      <n>, usual <n> (<N> fights)`. A fight against two enemies gives no line.
      `/hello baseline reset` empties the table; the next fight says `first fights, 1 so far`.

## 8. The fight baseline, step 3 (object 12, HelloForever 0.11.0, #109)

Object 12 on the strip (`docs/specs/93.md`, step 3). The addon test and the harness prove
the object, the hand-over and the revisions; the game check needs fights, and the agent does
no combat.

- [ ] Owner: with the reader running (`hellolink watch --serve 8787`), a
      fight against one enemy. Object 12 then has that fight's `fight` key, `rev` 1,
      `counted: true`, the enemy's `id` and `name`, your `level`, and `dur`, `dps`, `taken`
      and `died` as the chat line has them (`/hello baseline on`). After `/hello baseline
      reset` and after a `/reload` it says `null`.

## 9. The assistant's step 0 probes (`docs/specs/115.md`, section 13): 15 Nov 2026

Run by the agent on the level 1 bank character in Stormwind, out of combat, HelloForever
0.11.0 and HelloLink 0.1.0 installed, each probe a `/run` line pasted into the chat. Rows of
section 13 that are not here wait: the hostile creature's id, the gear hash and the
baseline (the owner's play); the window's widgets and the Chinese font (step 1's game
check).

| Row of section 13 | What was run | Seen |
|---|---|---|
| `time()` is the computer's clock | `time()`, `date("%H:%M:%S")` | `1794743467`, `11:51:07`; the Mac's `date -u +%s` read just after gave `1794743468`. Same clock, to the second. |
| A page in the game's settings | `type()` of `Settings`, `Settings.RegisterCanvasLayoutCategory`, `Settings.RegisterAddOnCategory`, `InterfaceOptions_AddCategory` | `table`, `function`, `function`, `nil`. The page uses `Settings`; the old `InterfaceOptions_AddCategory` is gone. |
| The panel's right-click menu | A right-click on the XP panel; the check box "Lock position"; the radio "Combat log file", `off` | The menu opens (`MenuUtil`). The check box set `settings.locked` to `true` and back to `false`. The radio set `settings.combatLog` to `off`, then `auto` again. A click on a radio closes the menu; a click on a check box leaves it open. The "Scale" radios were not tried. |
| A doubled `\|` shows as one and starts no code | `print` of a colour code, a texture code and a link; `FontString:SetText` of a colour code and a texture code; each `\|` doubled | Each shows the codes as text with one `\|` each: no colour, no icon, and in the chat no link. Not tried: a link on a `FontString`. |
| Talent points, an item's price, the gear's durability | `UnitCharacterPoints`, `C_ClassTalents.HasUnspentTalentPoints()`, `C_Item.GetItemInfo(id)` (11th value), `GetInventoryItemDurability(slot)`; `issecretvalue` on a durability and a price | `UnitCharacterPoints` is `nil`; `C_ClassTalents.HasUnspentTalentPoints()` gives `false` at level 1, `GetActiveConfigID()` a number. The global `GetItemInfo` is `nil`; `C_Item.GetItemInfo` gives the price (Hearthstone 0, Linen Cloth 13 copper; `nil` on the first call for an item not yet cached). Durability of slots 7, 8, 16, 17: `25/25`, `16/16`, `20/20`, `20/20`. The durability and the price were not secret values; the talent values were not checked with `issecretvalue`. |
| `nothing new`, and the slots running out | `/hlink` twice with no write; then the slots read to past the last | `nothing new (slot 6)`, `nothing new (slot 7)`. Past slot 200, each call: `no slot left (HelloLink_S<n>: MISSING). /reload gives the slots back.` (the last lines on screen were S204 to S207). |
| The slots after a `/reload` | `/reload`, then `/hlink` | `nothing new (slot 1)`: slot 1 is read afresh. |
| Bit 8192 in play | The reader's events, read passively while the owner played (15 Nov 2026) | The flags went from 3 to 8195 when the chat was opened to type a line, and back to 3 1.2 s later when it was sent. |
| A chat input is open (for the local program's typing guard) | `ChatEdit_GetActiveWindow()`, and the first chat edit box's `IsShown`, `HasFocus`, `IsVisible`, with an input open and closed | Open: the edit box, `true`, `true`, `true`. Closed: `nil`, `true`, `false`, `true`. Only the active window (or the focus) tells; strip bit 8192 uses the active window (#131). Not tried: a draft left in a box that lost focus. |
| What a look costs | `debugprofilestop()` around 20 calls of `/hlink` | 95.0 ms for 20, so 4.75 ms a look. This holds the chat line each call prints, so a silent look costs less. |
| A doorbell: a file that appears, changes or goes | `PlaySoundFile` on two missing files in `Interface/HelloLinkProbe/` (outside `AddOns`), and on a sound that was in an addon at the start; then the two files made while the game ran (one empty, one a copy of the sound), and called again; then again after a `/reload` | Missing: `nil`. The sound from the start: `true` and a handle. The two new files: `nil`, and still `nil` after the `/reload`. A file that appears while the game runs is not seen, at least outside `AddOns`. Tried on 16 Nov 2026 (the game started at 21:57 with both files in the folder): the copy of the sound gave `true` and a handle; moved out of the folder while the game ran, it still gave `true` and a handle; put back, `true` again. The empty file (0 bytes) gave `true` and a handle too. The four handles: 52674, 64649, 64926, 66180. Whether a sound was heard was not checked. Not tried: a file whose bytes change, a file in `AddOns` (the game must be closed to add one), a texture. |

What this changes for the build:

- The assistant's window can be a page of the game's settings (`Settings.RegisterCanvasLayoutCategory`).
- `sell` and `repair` can read their inputs out of combat; the price needs a call again when
  the first gives `nil`. `talent` has its function (`C_ClassTalents.HasUnspentTalentPoints`);
  whether its value can be secret is not checked.
- A look is cheap enough for the fixed times of `docs/specs/115.md`, section 6; a doorbell by a
  new file outside `AddOns` does not work, and a file the game knew at its start still gives
  `true` after it is gone (16 Nov 2026), so `PlaySoundFile`'s answer is no doorbell either way:
  those fixed times stay.

## 10. The assistant, step 1 (HelloForever 0.12.0, #125): the game check

The harness proves the cards, the bar and the window against the mock client
(`tests/assist_harness.lua`). These need the game. `Assistant.lua` is a new file, so 0.12.0
is installed only with the game closed. Bank character, no fights:

Seen on 15 Nov 2026 (HelloForever 0.13.0, HelloLink 0.2.0, the bank character in Stormwind):

- [x] The window opens by each of its ways: `/hello assist`, the panel's menu (`Assistant`; the
      menu also has `Assistant on`, ticked when on), the fight window's `Assistant` button, and
      the game's settings: Options, AddOns, HelloForever, `Open the assistant`.
- [x] With the assistant off the Cards part says `The assistant is off.`, and `Show a sample
      card` and the topic's button are greyed. The state line then said `HelloLink is not
      loaded`, though it was: fixed in #131 (the tick read HelloLink's table only while on).
- [x] With it on, every control clicked once: on, outside (off), each language, the muted
      subject's `Take back` (after `/hello assist mute bags`). After a `/reload`
      `HelloForeverDB.settings` read `assist = true`, `assistOutside = false`,
      `assistLang = "yue"`, no muted subject; `HelloForeverAssist.lang` was `yue`.
- [x] `Show a sample card` shows the bar under the panel and its tooltip (`from the addon ·
      a sample, not advice · 6 s ago`), in English and in Cantonese: the Chinese characters show
      on the bar, the tooltip and the window. The bar is narrow: a long text is cut with `...`.
      At the window's size `冇` is hard to tell from `有` on a screenshot; drawn five times as
      large they are two different glyphs.
- [ ] The `target` card (0.14.0, #136): the card on a creature fought 3 or more times at the
      level, none on one without fights (owner, in play).
- [ ] Owner, in play: the `fight` card after fights against one kind of enemy.

## 11. The assistant, step 2 (HelloForever 0.13.0, HelloLink 0.2.0, #127): the game check

The tests prove the slot file's part, what HelloLink takes, the looks, HelloForever's side and
object 13 against the stubs (the Rust slot writer's tests, `reader/hellolink/tests/processes/slots.rs`, `tests/hellolink_assist_test.lua`,
`tests/strip1_addon_test.lua`, `tests/assist_harness.lua`). These need the game; both addons
gain or change files, so they are installed with the game closed. Bank character:

Seen on 15 Nov 2026 (session 21517; the reader installed at 651b7a3, started by the local
program):

- [x] A set written by hand for the session (`tools/hellolink.py write <AddOns> --assist`, now `hellolink write`) was
      taken at the next fixed look: the card on the bar and in the window (`from the companion
      · written by hand, ...`), the state line `slots left: 198; last set: 10 s ago`. Object 13
      from the reader: `{"on": true, "lang": "en", "seq": 1, "re": null, "ask": {"n": 1, "topic":
      "session", "t": 1794760294}, "left": 194, "taken": 1, "refused": 0, "shown": "ask"}`.
- [x] A set for another session (21518): after the question's look object 13 said `taken: 0`,
      `seq` still 1, and the card of the first set was gone; the other session's card never showed.
      Not tried: a set written more than 180 s before the look.
- [x] The window's `session` button: `ask` with `n` 1, then 2; the bar said `asked: session`,
      then `no answer: is the companion running?`.
- [x] A text with `|cffff0000red?|r` in a card shows the code as text, with no colour.
- [x] `/hlink strip off`: the state line said `The strip is off: no cards from the companion.`
- Seen too: while the agent held the screen (computer use, full control), the reader's capture
  stream did not start; it was live 35 s after the agent let go.

## 12. The assistant, step 3 (the assistant program, #133): the game check

The assistant program (`hellolink assist`; `tools/assistant.py` until #195 step 3c) is tested
against a stand-in for the reader's API and a scratch AddOns folder
(`reader/hellolink/tests/processes/assistant.rs`). It is installed with the reader
(`hellolink install-reader`). In the game, with the reader and the assistant program running:

Seen on 15 Nov 2026, with the reader and the assistant program (da03084) started by the local
program, in the owner's play (session 21523; the cards in Cantonese, the owner's setting):

- [x] `/hello ask session`, typed by the owner: the set with the answer was written one second
      after the question (`t` 1794768398, the question's 1794768397); object 13 then said
      `"seq": 3, "re": 2, "ask": {"n": 2, ...}, "taken": 1, "shown": "out:session"`. The card:
      `今次：20 場，死 0 次，每個鐘 7,387 XP，+4 s 12 c`, ground `由 18:24 起嘅 strip`, detail
      `比平時慢得最多：Timberling 25 秒，平時 12 秒`. The card was on the bar (`shown`) when object 13 was
      read, 33 s after the question; when it came on the bar was not timed.
- [x] Before the question the program wrote its heartbeat set within seconds of its start
      (`seq = 1`, no card).
- [x] The assistant program started again answers no question twice (object 13's `re`). Seen on
      16 Nov 2026 on the bank character (session 21533, the installed program at f3b7598, started
      by the agent): the program was stopped and started again 16 s after question 2, inside the
      60 s in which a question is answered. Its sets after that (`seq` 5, at 22:15:26 and
      22:16:26) had `"re": 2` and no card: no second answer. About two minutes after the restart
      object 13 still said `"seq": 4` and `"shown": "out:session"`; when the game takes the set
      with no card was not seen.
- [ ] On the bank character, and in play: `/hello ask session` gives the card on the bar within
      20 s, timed from the question to the card shown, not only to the set written.
      Seen on 16 Nov 2026 on the bank character, the times from the reader's event stream,
      stamped by the Mac's clock. Question 2 (`t` 1794867309, the ammo subject muted for the
      check): the set with the answer was written 2 s later; the reader had object 13 with
      `"shown": "ask"` 2.2 s after `t` and with `"shown": "out:session"`, `"seq": 4`, `"re": 2`
      5.9 s after `t`; a screenshot taken some seconds later (its time was not recorded) showed the bar with `今次：0 場，死 0 次，...` (the
      card's whole text: `今次：0 場，死 0 次，每個鐘 0 XP，0 c`, ground `由 22:04 起嘅 strip`).
      Question 1 (`t` 1794866679), with the ammo card (`彈藥：剩 0`, prio 1) on the bar: the set
      was taken (`"taken": 1`, `"re": 1`, read 6.6 s after `t`), and the bar kept the ammo card
      with `+1` beside it, as the order of `docs/specs/115.md`, section 3, says: the answer
      (prio 3) waited behind it and was not on the bar. Still to time: in play.
- Seen too (16 Nov 2026): after `/hello assist unmute ammo` the ammo card did not come back
  (object 13 said `"shown": "out:session"` 25 s later), though the bags still held none of the
  ammunition. It came back after the `/reload`. The supply rules run when the bags or the gear
  change and when the character enters the world, not when a subject is unmuted.
- [ ] HelloForever 0.18.3 (#166): on a character with fewer than 200 of its ammunition,
      `/hello assist mute ammo`, then `/hello assist unmute ammo`: the ammo card is back on the
      bar within seconds, with no change of the bags or the gear and no `/reload`. The harness
      holds it (`tests/assist_harness.lua`, sections A17 and A18); not yet seen in the game.
      The game runs that code since the evening of 16 Nov 2026: `Assistant.lua` and `Core.lua`
      of 0.18.3 were copied over the installed files while the game ran, and after the owner's
      `/reload` `/hello debug` said `addon=0.18.2 sourceRevision=0.18.3` and `assistant: on,
      1 cards; rules off: none`. The mute and unmute were not typed: the owner was on the hunter.


## 13. Strip objects 14 gear, 15 bag slots, 16 bank (HelloLink 0.3.0, #138): the game check

The objects were built from the client's UI source and the item link's documented fields, not
from a probe in the game (the owner's word, 15 Nov 2026). The mock client holds them
(`tests/strip1_addon_test.lua`). In the game, on the bank character, with the reader
reinstalled (`OBJECT_IDS = 16`):

Seen on 15 Nov 2026, HelloLink 0.3.0 and the reader 3d63bee, on the bank character (level 1, in
Stormwind; the owner opened and closed the bank):

- [x] Object 10: `"class": "WARRIOR", "race": "Human"`, the client's file names.
- [x] Object 14: the 4 worn slots, each with its item; `enchant` and `suffix` `null` (none of
      them has either); `dur` `[25, 25]` and `[16, 16]`, and `null` for the shirt (no
      durability). Empty slots left out.
- [ ] Object 14 with an enchanted item and an item with a random suffix: the bank character has
      neither. Not seen in the game; the test holds the link fields. To check on the main.
      Seen on 16 Nov 2026 on the hunter (level 35), about three hours of play: 14 worn slots,
      none with an enchant or a suffix, in every version of the object. Whether the hunter wears
      none is the owner's to confirm; an enchanted or suffixed item is still to see.
- [x] Object 15: the keyring (`-1`, 32 slots, empty), the backpack (20 slots) and bags 1 to 4
      (10, 10, 10, 8 slots), slot by slot as `[slot, item, count]`. No reagent bag: bag 5 has no
      slots and is left out.
- [x] A shot of ammunition, alone, makes no new version of object 15: the bank character has no
      ammunition. Not seen in the game; the test holds it. To check on the main. Seen on 16 Nov
      2026 on the hunter: the arrows (item 3030) went from 2786 to 1393 in the bags, and of 293
      object 15 events none was a version in which only arrow counts changed. Three versions
      (14:03:07, 14:51:03, 15:15:29) came when a stack of arrows was shot empty: that slot of the
      quiver is free from then on, a change of the slots and not of a count only (as
      `docs/STRIP.md`, row 15, says); about one in 200 shots. The bags held
      stacks of up to 200, a 14-slot quiver (bag 1) and an 8-slot reagent bag (bag 5); after the
      quit, the saved snapshot's bags 0 to 4 (63 items) were the same as the strip's last object
      15.
- [x] Object 16: `null` with the bank closed. At the bank, one tab of the character's bank,
      `{"bag": 6, "size": 48, "slots": [...]}` with its 7 filled slots; no tab of the account's
      bank (none bought). `null` again when the bank closed (21:41:59, seconds after).
- [ ] A bank too large for one object (format 254): not reached (the bank is small).
- [x] No object was called stale in the minutes of the check (the round of 16 objects: 57.6 s).
- Seen too: the game, started alone, asks for a password; started from the Battle.net app it
  logs in without one. Battle.net updated the game first; the update did not touch the
  installed addons.

## 14. Strip object 17 trainer (HelloLink 0.4.0, #141): the game check

Built from the client's own trainer UI (`Blizzard_TrainerUI`, forever branch), not from a probe
in the game. The mock client holds it (`tests/strip1_addon_test.lua`). In the game, with the
reader reinstalled (`OBJECT_IDS = 17`):

- [x] Object 17 is `null` with no trainer window open. Seen on 16 Nov 2026 on the hunter.
- [x] At a profession trainer: `npc` is the trainer's creature id, `skill` its profession, and
      `step` points at the stage it teaches; each service as in the window. Seen on 16 Nov 2026
      at a skinning trainer (creature 1292): `"skill": "Skinning", "step": 1`, the one service
      `["Artisan Skinning", null, "available", 0, ["Skinning", 200], 45000]`.
- [ ] Six seconds later, still open: `"skill": null, "step": 2, "services": []`, most likely
      after the service was bought. A `step` past the end of `services` is a fault: a reader
      would take it as an index. To fix: `step` is `null` unless it is in the list.
- [ ] At a class trainer: `skill` and `step` are `null`; the ranks as in the window.
- [ ] A filter turned off in the window shows in `filter`, and the list shrinks to match. Seen on
      16 Nov 2026: `"used": false` in `filter`, and a list of one available service. The
      turning off itself was not seen.
- [x] `null` again when the window closes. Seen on 16 Nov 2026.
- [x] No object is called stale in a quiet minute (the round of 17 objects: 61.2 s). Seen on
      16 Nov 2026: from 12:33 to 14:42 of the hunter's play no object was called stale. From 15:17
      to 15:48 the whole strip was stale or waiting again and again (the game not on screen);
      objects not seen whole across those gaps were called stale with the rest.

## 15. The assistant's gold card (HelloForever 0.15.0, #144): the game check

The hours of play are read from the character's timeline; the harness holds the rule
(`tests/assist_harness.lua`, section A16). In the game, with the assistant on:

- [ ] After an hour of play, with 3 or more earlier hours in the timeline, a `gold` card:
      `This hour: …, usual …`; the money as the character's purse changed in that hour. Seen on
      16 Nov 2026 on the hunter: the bar showed `gold` at 13:16, 14:16 and 15:16, an hour of play
      apart (object 13's `shown`). The card's text and its money were not read.
- [ ] No gold card in a fight; it comes when the fight ends.
- [ ] A logout of more than 6 minutes and a login in the middle of an hour: the hour goes on
      after the login, and the time logged out does not count.
- [ ] A login with earlier hours in the timeline gives no gold card until an hour of play.

## 16. The assistant's ammo card (HelloForever 0.16.0, #146): the game check

The harness holds the rule (`tests/assist_harness.lua`, section A17). In the game, on the
hunter with the assistant on:

- [ ] Fewer than 200 arrows (or bullets) in the bags: `<name>: <n> left`, the count as the
      bags show it; under 50 the card is more urgent (prio 1).
- [x] Seen on 16 Nov 2026 on the bank character (a warrior), in Cantonese: `彈藥：剩 0` on the
      bar. Its ammunition slot holds an item and the bags hold none of it. The client had no
      name for the item yet, so the card used the word for ammunition. On the hunter, with a
      named arrow and a count between 1 and 199, the box above is still open.
- [ ] In a fight the card keeps its count; after the fight it shows the new count.
- [ ] 200 or more after a purchase: the card goes.
- [x] With 200 or more arrows in the bags, no ammo card. Seen on 16 Nov 2026 on the hunter: the
      arrows stayed between 2786 and 1393, and object 13's `shown` was never `ammo`.

## 17. The assistant's bags card (HelloForever 0.17.0, #148): the game check

The harness holds the rule (`tests/assist_harness.lua`, section A18). It reads the client's own
count, `C_Container.CalculateTotalNumberOfFreeBagSlots()`, not yet seen in the game:

- [ ] `/dump C_Container.CalculateTotalNumberOfFreeBagSlots()` gives the free slots the bags
      show (a quiver's slots are not free for other items: note whether they count). Seen on
      16 Nov 2026 on the bank character: 36. Bag by bag (`GetContainerNumSlots`,
      `GetContainerNumFreeSlots`): the keyring (-1) 32 and 32 free, the backpack 20 and 0, bags
      1 to 4 10/8, 10/10, 10/10, 8/8, bag 5 none: bags 0 to 4 have 36 free, so the total leaves
      the keyring out. The bank character has no quiver: whether a quiver counts is still open.
- [ ] With 2 slots or fewer free, the assistant on: `Bags: <n> free`; with none, prio 1. Seen on
      16 Nov 2026 on the hunter: the bar showed `bags` at 14:53, 14:55 and 15:19 (object 13's
      `shown`); its text was not read. The hunter's `/dump` gave 25, the free slots of bags 0 to 4
      as object 15 had them; the quiver and the reagent bag were full, so whether their slots
      count is still open.
- [ ] 3 or more free again: the card goes.

## 18. The settings window (HelloForever 0.18.0, #150): the game check

The harness holds each control (`tests/assist_harness.lua`, section A19). In the game:

- [ ] The panel's right-click menu has Settings; it opens the window. `/hello settings` and
      the game's AddOns options (HelloForever, Settings) open it too; Escape closes it.
      Seen on 16 Nov 2026 on the bank character: the menu (titled `HelloForever 0.18.1`) has
      Settings, which opens the window; `/hello settings` opens it; Escape closes it. Its values
      are the settings (shown, not locked, 100%, both chat lines off, combat log `auto`, 3 MB).
      The AddOns options page was not tried.
- [ ] Each control does what its command does, and the window shows the new value. Seen on
      16 Nov 2026: Locked ticked and unticked; the other controls not tried in the game.
- [ ] Empty the baseline: the first click asks again; the second within 5 s empties it. Seen on
      16 Nov 2026, the first half: one click shows `Click again to confirm` in red, empties
      nothing, and after 5 s the button's own text is back. The second click was not made (the
      baseline was kept).

## 19. HelloLink's strip settings window (HelloLink 0.5.0, #152): the game check

The tests hold each control (`tests/hellolink_strip_test.lua`). In the game:

- [ ] `/hlink settings` and the game's AddOns options (HelloLink) open the window; Escape
      closes it. Seen on 16 Nov 2026 on the bank character: `/hlink settings` opens it (the
      strip on, size 2, depth auto, a chunk 0.10 s, `At (0, 0), 2 pixels a square, depth auto
      (now 4)`); Escape closes it. The AddOns options page was not tried.
- [ ] Each control changes the strip as its `/hlink strip` command does; the line at the
      bottom says where the strip is now. Seen on 16 Nov 2026: size 3 made the strip larger and
      the line said `3 pixels a square`; size 2 put it back. The other controls not tried.
- [x] After a move, the reader finds the strip again. Seen on 16 Nov 2026 (HelloLink 0.5.1, the
      reader at f3b7598): `/hlink strip at 300 40`, then the reader's event `{"kind": "relocate",
      "why": "no row"}`; its next event came 6.4 s later, and the place it remembers was
      `"left": 298, "top": 39`. `/hlink strip at 0 0`: `relocate` again, the next event 4.6 s
      later, the place `"left": 0, "top": 0`; the reader's condition was `live` at each look
      (four a second) through the move back. The move was made by the command, not by the
      window's controls.

## 20. No false numbers in the saved data (HelloForever 0.18.1, #154): the game check

The harness holds the unknown cases (`tests/fights_harness_more.lua`, section 16l, and
`tests/assist_harness.lua`, section A20); a secret or failed read cannot be made in the game on
demand. What the game can show is that the normal cases still read:

- [ ] After a login and some looting: the saved `snapshot.freshness.bags` is `ok`, and each item's
      `count` is the stack the bags show, also a single item (count 1) and a bag slot with no bag.
      Seen on 16 Nov 2026 on the bank character (no looting): after a `/reload` and a quit,
      `freshness.bags` is `ok` and its 22 items each have a count, all single items (count 1),
      as the bags hold. A stack of more than one is still to see. Seen on 16 Nov 2026 on the hunter, after about three
      hours of play and a quit: `freshness.bags` `ok`, and its 63 items (44 stacks of more than
      one) the same as the strip's last object 15. A bag slot with no bag is still to see.
- [x] HelloForever 0.18.2 (#157, hot-loaded and `/reload`ed in play): after the quit the hunter's
      30 skill lines each have a maximum, none 0, and `freshness.professions` is `ok`.
- [ ] The timeline gains entries in play (the tick every 5 minutes), with the level and XP the
      character has; at the level cap, XP 0 is still written. Seen on 16 Nov 2026: the login and
      the `/reload` each wrote a keyframe with level 1, XP 55 and the money, no 0 in their
      place. Seen on 16 Nov 2026 on the bank character, in the game from 21:57 to a `/reload`
      at 22:17:52, standing in one place: after the login's keyframe (21:58:03: level 1, XP 55,
      the money) the timeline has one entry, `t` 21:58:05, `last` 22:17:55, `n` 5. A tick that
      changes nothing adds to the last entry's `n` and moves its `last`
      (`HelloForever/Snapshot.lua`); the first write counts as 1, and a change of zone and a
      logout call the same function as the 5-minute timer. So the entry shows four more calls
      in those 20 minutes and keeps none of their times: that they were the timer's, 5 minutes
      apart, is likely and not proved. A tick that writes a changed level or XP was not seen
      (the character gained none). Still to see: the timer's ticks by their own times, a tick
      with a change in play, and the level cap (no character here is at it).

## 21. The character's looks, taken at a barber (HelloLink 0.6.0, #168): the game check

The tests hold what HelloLink makes of the client's answer and when it keeps the older record
(`tests/strip1_addon_test.lua`, "looks"). The answer in the tests is written by hand from the
client's documentation; nothing of this was seen in the game. Barbers: Stormwind, Ironforge,
Darnassus, Thunder Bluff. In the game, with HelloLink 0.6.0 loaded:

- [ ] The character can sit in a barber's chair, and the barber's window opens. Not known for
      every race (the hunter is a Skyborne).
- [ ] After the chair and a `/reload` or a logout, `SavedVariables/HelloLink.lua` has
      `HelloLinkDB.looks["<name>-<realm>"]` with `at`, `race`, `sex`, `models` and `choices`;
      `choices` has an entry for each option the barber's window shows, and every key and value
      is a number.
- [ ] After a new appearance is accepted and a `/reload`, the changed option's entry in
      `choices` has another choice id, and `at` is later.
- [ ] No Lua error at the chair, and the strip reads as before.

## 22. The hearthstone, object 18 (HelloLink 0.7.0, #180): the game check

The tests hold what HelloLink makes of the client's answers (`tests/strip1_addon_test.lua`,
"the hearthstone"). The answers in the tests are written by hand; nothing of this was seen in
the game. In the game, with HelloLink 0.7.0 loaded and the reader running:

- [ ] With a hearthstone in the bags, the reader's object 18 has `bind` equal to the place the
      hearthstone's tooltip names, `item` 6948 and `readyAt` 0; not format 255.
- [ ] After a use (the bank character's own hearthstone, when the owner allows it), `readyAt`
      is within two seconds of the use plus the cooldown the tooltip shows, and the object's
      version does not change while the cooldown runs.
- [ ] A spell cast with the hearthstone ready leaves `readyAt` at 0 (the global cooldown is not
      taken for the hearthstone's).
- [ ] No Lua error, and the strip reads as before.

## 23. The API probe (HelloLink 0.7.1, #185; the realm line 0.7.2, #188): the game check

The probe for the local program's rounds 4 and 5. Read only; on the bank character or on the
owner's own play.

- [ ] Log in; after 10 s, `/reload`. `HelloLinkDB.probe[1]` in `WTF/Account/<account>/SavedVariables/HelloLink.lua` has `why = "login"` and twenty lines.
- [ ] Open a flight master's map, and a merchant: a run with `why = "TAXIMAP_OPENED"` and one with `why = "MERCHANT_SHOW"`.
- [ ] The `realm` line: does `GetRealmID` equal the number of the realm folder that holds this character under `WTF/Account/<account>/`? Then 0.8.0 adds `"realmId"` to object 10.
- [ ] For each line, write down whether it answered, was `<secret>`, `absent` or `ERROR`. Build 0.8.0 only on the lines that answered.

## 24. The probe's answers on the strip (HelloLink 0.8.0): the game check

The tests hold what HelloLink makes of the client's answers (`tests/strip1_addon_test.lua`,
"HelloLink 0.8.0"). The answers in the tests are written by hand from the probe of 18 Nov 2026.
In the game, with HelloLink 0.8.0 loaded and the reader running:

- [ ] Object 15: each bag has `family` 0; the quiver has its own number (1 seen by the probe).
- [ ] Object 14: slot `"0"` has the ammunition's item and count; while shooting, object 14's
      version does not change, and the count follows at the next change of the gear.
- [ ] Object 19: after login, `ids` has as many ids as the probe counted (480 on 18 Nov 2026);
      after a quest is turned in, its id is there. Not format 254.
- [ ] Object 20: `null` while alive. After a death and a release, `map`, `x`, `y` lie where the
      corpse is on the map; `null` again after the return to life. Never seen yet.
- [ ] Object 21: the factions of the reputation window, in its order, with `standing`,
      `value`, `min`, `max` as the window shows them; the watched one `watched: true`.
- [ ] Object 22: with Auctionator, the last scanned price of an item, as Auctionator's tooltip shows it, and its age;
      after an auction house scan, new prices within a few seconds (Auctionator's update).
- [ ] Object 23: the hunter's pet's experience as the pet frame shows it; `null` with the pet
      dismissed.
- [ ] Object 11: the current step first, with its `tags`, `quests` and `done`; `orphans` and
      `targets` as RXP shows them; no Lua error from RXP.
- [ ] `HelloLinkDB.seen` in the saved file names the character after a `/reload`.
- [ ] No Lua error, the strip reads as before, and the frame time does not rise.

## 25. The full name and the step elements (HelloLink 0.8.1): the game check

The tests hold the rules (`tests/strip1_addon_test.lua`, "HelloLink 0.8.1";
`tests/hellolink_probe_test.lua`, the `fullName` line). The loot message's shape is the one
seen on 13 Nov 2026 (section on loot above). In the game, with HelloLink 0.8.1 loaded:

- [ ] Loot one item. Object 10 has `fullName` with the family name and `fullNameSource` `"loot"`.
      After `/reload`, `HelloLinkDB.fullNames["<player GUID>"]` in the saved file has the same
      name, and `HelloLinkDB.seen["<name>-<realm>"].fullName` too.
- [ ] Does `fullName` equal the WTF folder's name of this character (`Name-Surname`, with a
      space for the hyphen)?
- [ ] `/hlink probe api`, then `/reload`. Read the `fullName` line of `HelloLinkDB.probe[1]`:
      write down what each of `UnitFullName`, `GetUnitName`, `UnitNameUnmodified`,
      `GetPlayerInfoByGUID` and `C_PlayerInfo.GetName` gave (a value, `<secret>`, `absent` or
      `ERROR`). A later release reads the one that gives the family name, the loot staying the fall-back.
- [ ] Object 11: each step has `elements`, in the order RXP shows the step's lines.
- [ ] No Lua error, and the strip reads as before.

## 26. The probe for strip format 2 (HelloLink 0.8.2, #213): the game check

What a unit table, auras, cooldowns and the action bar would read (#213, step 3). Read only.
The tests hold what the probe makes of each answer (`tests/hellolink_probe_test.lua`). After
each part, `/reload` and read `HelloLinkDB.probe` in the saved file.

Seen on 20 Nov 2026, 16:03 to 16:06, the level 39 hunter with its pet, alone, one hostile
creature (HelloLink 0.8.2). Every run of that play was in combat (the login too). Seen again
on 20 Nov 2026, 18:45 to 19:46: the same hunter, about an hour of play, HelloLink 0.8.3. The
`login` and `target` runs were out of combat. The `combat` run was in a fight with a target.
Every value is in the comments of #213 of that day.

- [ ] Log in: a run with `why = "login"` and 43 lines; no Lua error. Seen: 43 lines. Not seen:
      whether a Lua error showed.
- [x] Target a creature: a run with `why = "target"` and 22 lines. For `unit target` and
      `unit targettarget`, write down each value: a value, `<secret>`, `absent` or `ERROR`.
      Seen: 22 lines; identity, level, class, dead, combat, can attack and the unit's own target
      read; health, power and range secret; the hostile's maximum health secret; position
      `nil` for every unit but the player.
- [ ] A fight (the owner's play): a run with `why = "combat"`. The same, in combat: which values
      turned `<secret>` that were not before? Seen (0.8.3, with a target): the auras (an error,
      below), `GetUnitSpeed`, and the cooldowns' `startTime`, `duration` and `modRate`. The
      unit values did not change: health, power and range are secret in and out of combat, and
      the maximum health of every unit but the player and the pet. The target had no target of
      its own in these runs, so `unit targettarget` did not exist. In the 0.8.2 play the
      mouseover's threat was `<secret>` too. Not seen: a live `unit targettarget` in combat.
- [ ] `auras player HELPFUL` and `auras target HARMFUL`: `spellId`, `expirationTime`,
      `sourceUnit` read or secret? Seen: out of combat the player's 7 auras read (`spellId`,
      `name`, `duration`, `expirationTime`, `sourceUnit`). In combat `C_UnitAuras` fails with
      "Auras cannot be accessed when secret while tainted by 'HelloLink'". `UnitAura` is absent.
      Not seen: an aura on the target (it had none out of combat).
- [x] `action bar` and `cooldowns`: the cooldowns, the range and the use of a button read or
      secret? Seen: the spell ids, `isActive`, `isOnGCD`, use and range read; the start, the
      duration and the counts secret in combat, read out of combat.
- [x] `nameplates`: how many units, and the first one's values. Seen: 1 unit, the creature
      fought, read as `unit target`.
- [ ] A party, and a raid (the owner's play): `unit party1`, `unit raid1` and `group`; a run
      with `why = "raid"`. Not seen: no group.
- [x] `addon cost`: HelloLink's memory in KB. Seen: 1,813 to 3,081 KB.
- [x] Each line's time in ms: write down the largest. Seen: `addon cost`, 55.5 to 87.2 ms (out
      of the event runs since 0.8.3); the next, `completed quests`, 2.2 ms.
- [ ] HelloLink 0.8.3 (#216): the `target`, `combat` and `raid` runs have 21 lines and no
      `addon cost`; the `login` run and `/hlink probe api` still have it. If an aura line still
      says `ERROR`, write down the text after it. Seen: `target` and `combat` 21 lines, `login`
      43 lines with `addon cost` (87.2 ms); the aura text is in the box above. Not seen: a `raid`
      run, `/hlink probe api`.

## 27. Strip format 2 (HelloLink 0.9.0, #213): the game check

HelloLink 1.0.0 (21 Nov 2026) makes format 2 the default, at the owner's word; the boxes below
are still the checks of format 2 in play.

Format 2 by setting (`docs/specs/213.md`). The reader reads both formats (#226). Before the
check, the reader of the branch is installed for the local program (`hellolink
install-reader`), and HelloLink 0.9.0 with the game closed.

Seen on 20 Nov 2026, 23:13 to 23:49 (36 min): HelloLink 0.9.0 copied in while the game ran and
loaded by the owner's `/reload` (no file is new to the TOC); the reader of main 43f0141 installed
while the local program was stopped. The owner typed `/hlink strip format 2` on the hunter
and played: travel, a city. Read from the record with `hellolink replay`.

- [ ] `/hlink strip format 2`: the answer says format 2 and 1 pixel a square; the row is
      about 155 pixels long; no Lua error.
- [ ] The reader (`watch --record`) reads it: `state` events with `"format": 2`, deltas among
      them, and the target of target in the fast state. Seen live: `/state` gave `"format": 2`,
      `live` and a `keyAge` of 0.05 to 0.14 s while the position moved (three reads just after the switch),
      so deltas were put over their keyframe. Seen in the record (`hellolink replay`, which
      also feeds the captures of the search): 13,202 states of format 2; 11,352 delta frames
      and 1,991 keyframes; the target of target in 165 states, the pet's target in 156, the
      target of target's health in `more` in 1,923. Not seen live: the target of target in
      `/state` (it was null at the reads).
- [ ] An hour of play with format 2: 0 failed frames in the record (`hellolink replay`), and
      the bytes of a frame within 20 % of section 10 of the spec (about 44). Seen:
      - Seen again on 21 Nov 2026, 09:45 to 10:40 (55 min, the owner's play, HelloLink 1.0.0,
        the record `2026-11-21-0945.jsonl`; the reader under the local program was restarted at
        09:45; the play before it is not measured here): failed frames 0 (208 captures with no
        row); 172 of 25,666 seq values never captured (0.67 %; 126 of the gaps were one value).
        `HelloLinkDB.frames`, saved at 10:40:28, held seq 39190 to 39701 (65 s): 4 never
        captured, each up 26 to 120 ms by the addon's clock; 5 of 511 frames up under 90 ms; the
        captures there 100 to 360 ms apart, the reader seeing each frame 270 to 430 ms after the
        addon drew it (whether in the game's drawing or in the capture is not known; spec 232,
        section 2). Under an hour still: the
        box stays open.
      - The 36 min of 20 Nov 2026:
      - 13,343 frames. Failed: 0. (In the record a failed frame is a line with a `why` other
        than `no row`, or with `bad` bytes: none.)
      - 31 captures with no row (`why: no row`), searches included.
      - A frame of 51.4 bytes on average, 15 to 208: within 20 % (52.8). 6.2 new frames a
        second.
      - Keyframes, while the row was on the screen: 1,991, the gaps between them 1.0 s at the
        median, 1.91 s at the 99th percentile, 2.58 s at most. A gap over 1.5 s makes the state
        old (spec, section 9): most likely a keyframe was up for one dwell and no capture came
        in it. Not measured.
      - The row was off the screen three times. The positions before and after: Swamp of
        Sorrows to Stranglethorn after a cast (a loading screen, most likely), a ride into
        Stormwind (the owner: "perhaps flying"), about 110 s in one place in Stormwind (the game
        hidden or covered, not known).
      - One stop of the captures for about 1 s right after the switch (seq 2557 to 2569): the
        reader said `stale` once, 1.5 s after the keyframe.
      Seen on 21 Nov 2026, 00:39 to 01:42 GMT (63 min), HelloLink 1.0.0 and the reader of main
      667f9a8: the level 1 test character stood in Stormwind with no input, the game on the screen.
      Record `2026-11-21-0023.jsonl`, from the first format-2 frame (t 943.7 s) to the last
      (t 4747.1 s):
      - 14,720 frames in 3,803 s (3.9 new frames a second: few changes). Failed: 0. Captures
        with no row: 0.
      - A frame of 51.7 bytes on average, 15 to 191: within 20 % of section 10.
      - Seq: 14,717 steps of 1 and 44 seq values missed (0.3 %; 1.9 % in the 36 min of play).
        One session. The 44 are in two places, both capture stops: 41 at t 943 to 951 s (the
        8.1 s stop from t 943.7 s, right after the first frame, to 951.8 s) and 3 at t 1094 s (the 1.3 s stop). None
        while captures came at their normal pace (#213, its comment of 21 Nov 2026).
      - Keyframes: 3,800, the gaps between them 1.0 s at the median, 1.09 s at the 99th
        percentile, 2.03 s at most. One `stale` (t 1096 s), after the one stop of the captures
        over 1 s (1.3 s at t 1094 s).
      - Objects: no `bad-object`. Object 24 (209 versions: nameplates none, `mouseover` set and
        unset), 26 (83 versions), 25 and 13 (10 each), the rest once. Object 10 format 255
        (#222).
      Still to see: an hour of play (travel, fights, a group). The 36 min of play and the hour
      standing do not make one.
- [ ] Objects come whole (the local program shows the bags, the place, the quests). Seen in
      the record: objects 2 to 23 whole (9 the route 188 versions, 8 the rest 67), none
      `bad-object`. Object 10 was format 255 all the time (#222, also after the `/reload`).
      Not seen: the local program's own view.
- [ ] `/hlink strip format 1`: the row is format 1 again, 2 pixels a square.
- [ ] HelloLink 1.0.0: the first load after the install draws format 2 (`/hlink strip` says
      format 2), `/hlink strip format 1` then a `/reload` stays format 1, and `/hlink strip
      format 2` goes back. After a logout, `HelloLinkDB.frames` holds that session's frames.
      Seen on 21 Nov 2026: the first load after the install (game closed, then started) drew
      format 2 with no command (`/state` `format` 2 at 00:39). Not seen: `/hlink strip`'s
      answer, the switch to format 1 and back. `HelloLinkDB.frames` after the logout at 01:49: 512
      frames of session 0x543E (seq 16052 to 16563), the row covered at that time; of the 511 gaps between its draws, 33 were
      under the dwell (#213).
- [ ] HelloLink 0.10.0, objects 24 to 27 (format 2): the unit table with a party member and
      nameplates; names; the auras out of combat and format 253 (`secret`) in a fight; the
      cooldowns of the action bar. Whether another unit's cast is given (`cast` in object 24).
      Seen on 21 Nov 2026 (the level 1 test character, Stormwind, no fight, no group): object 24 with
      `mouseover` and no nameplates, no `cast`; 25 with 15 names in `/state`; 26 with the
      player's one aura, its expiry moved in 83 versions (the cause not known); 27 with the
      action bar's slots (spells and an item), every one with no cooldown running. Not seen: a
      party member, nameplates, a fight, format 253, a cooldown running, another unit's cast.

## 28. Strip format 3 (#232, #242): the game check

Format 3 by setting (`/hlink strip format 3`, `docs/specs/232.md` section 6). Before the check:
the reader that reads format 3 (the pull request after #242) installed for the local program,
asked of JevCompanion first (one holder of the game and the reader at a time); HelloLink with
#242 copied in while the game is closed, or by the owner's `/reload`.

Seen on 21 Nov 2026, 11:05 to 11:22 (the level 1 test character in Stormwind, standing; HelloLink 1.0.0 with
main 86d91e9's `Strip.lua`, the reader of 86d91e9; `plan/README.md`, "Installed now"). The game
was brought to the front for the check; twice another window covered it, and the reader saw no
row then. The record is `2026-11-21-1058.jsonl`.

- [x] `/hlink strip format 3`: the answer says format 3; the depth square reads 5 (7 at 3 bits)
      and the layout square 0; no Lua error in what was looked at (the four screenshots of the
      chat; an error at another moment is not ruled out). Seen: the answer "strip on at (0, 0), format 3, 1
      pixels a square, depth auto (now 4), a chunk stays 0.10 s"; the reader read the row as
      format 3 at depth 4, which it does only for the digit 5 with the layout square 0 (and at
      depth 2 below, only for the digit 7); no error window or error line in the four
      screenshots of the chat taken during the check. `/state` gave `"format": 3`, `live`.
- [ ] An hour of play in format 3 (spec, step 5): 0 failed frames in the record; the seq values
      never captured, against format 2 in play (1.9 % on 20 Nov 2026, 36 min; 0.67 % on
      21 Nov 2026, 55 min); where they fell against the stops of the
      captures and the ring of draw times (`HelloLinkDB.frames`).
      Seen so far (2 min 32 s standing, not play): 459 new frames, 0 failed, 1 seq value never
      captured (0.22 %). Objects: most were held whole from format 2 in the same session (the
      chunk length did not change, so neither did their versions) and came again as refreshes;
      new versions came whole for object 15 (bag slots) once and 26 (auras) twice; before 26's second,
      the directory called the held copy old (`stale-object`, then `object` 0.1 s later).
- [ ] The time to recover after each gap: the fast state in the first frame after it; each
      object changed in a gap of 1 s or less whole within 1 s, a longer gap within one refresh
      round (spec, section 4 A).
- [x] No frame went up sooner than a dwell after the one before (the ring of draw times). Seen:
      `HelloLinkDB.frames` saved by a `/reload` in format 3: 512 frames, seq 2658 to 3169 (170 s),
      511 gaps, none under 0.1 s, the smallest 0.100 s. All of them format 3's: the first state of
      format 3 had seq 2066, the switch back to format 2 came after the `/reload`, and in one session
      the seq only goes up (it is past 3169 by then and does not come round in that time). (Format 2 on 21 Nov 2026: 33 of 511.)
- [ ] The squares painted, the slowest update and the reader's processor use, against format 2
      in the same play (rule 4; the Lua time is the lead's decision in the spec).
- [ ] HelloLink 1.18.0 (spec 276, step 2): `/state` gives object 10 with `"guid": "Player-<server>-<hex>"`,
      equal to the HelloForever record's `guid`; after the login `HelloLinkDB.seen` gains the GUID's
      key with `guid`; at a barber, `looks` is written under the GUID. No Lua error.
      Seen 22 Nov 2026, the level 1 test character: `/state` object 10 (format 1) with `"realm": ""` and
      `"guid": "Player-6841-<hex>"`, equal to its HelloForever record's `guid`; after a `/reload`,
      `HelloLinkDB.seen` has the GUID's key with `guid` (the older name keys stay). Still to see: `looks`
      under the GUID at a barber; no Lua error.
- [ ] HelloForever 0.19.0 (a GUID in each record, spec 276 step 2): after a login on each character,
      its record in `HelloForeverDB.characters` holds `guid` (`Player-<server>-<hex>`, equal to
      `HelloLinkDB.fullNames`' key for it) and `guidBy = "name"`; the `Name-` record split off by
      0.18.4 holds the same `guid` with `split = true`; no new record appears; `HelloForeverDB.guids`
      lists each name with its one GUID. No fight filed twice, no Lua error.
      Seen 22 Nov 2026 on the level 1 test character only: its old record (timeline 311, then 313) holds
      `guid` with `guidBy = "name"` and goes on; its `Name-` record holds the same `guid`, `guidBy = "split"`,
      `split = true` and no `fightTrack` (moved); still 5 records; `guids` has its name with one GUID. Still
      to see: the other characters' logins, a fight not filed twice, no Lua error.
- [x] HelloLink 1.17.0 (the probe's `account` line, for more than one account and for telling
      characters apart): after a login, `HelloLinkDB.probe[1]` (`why = "login"`) has an `account` line.
      Write down for each call whether it answered, `absent`, `<secret>` or `ERROR`: `BNGetInfo` (a
      BattleTag's shape only), `BNConnected`, the GUID's form (`Player-<server>-<hex>`), and the
      realm that `C_BattleNet.GetAccountInfoByGUID` and `GetGameAccountInfoByGUID` give. Never write
      the BattleTag itself into this repository. Settles whether a BattleTag and a realm can be read.
      Seen 22 Nov 2026, the level 1 test character, `probe[1]` (`why = "login"`, 50 lines): `BNGetInfo`
      answered (presence `nil`, a BattleTag of 13 bytes, `#` then 4 characters); `BNConnected` true; the
      GUID `Player-6841-<hex>`; `GetAccountInfoByGUID` answered with the same BattleTag shape, and
      `realmName`, `realmID`, `realmDisplayName` all `nil`; `GetGameAccountInfoByGUID` a table with no
      BattleTag and the same three `nil`. The `realm` line: `GetRealmID` 0, both names `""`. So a BattleTag
      can be read, and no call gives the realm (spec 276, steps 3 and 4).
- [ ] HelloLink 1.16.0 (object 10 with the empty realm, the empty ammunition slot): on the level 1 test
      character, `/state` gives object 10 readable (`"format": 0` or 1) with `"realm": ""`, and
      object 14 with no `"0"` slot (no ammunition); `HelloLinkDB.seen` gains the key `Name-`. On the
      owner's hunter, slot 0 with its ammunition as before. No Lua error.
      Seen 22 Nov 2026 on the level 1 test character: object 10 format 1 with `"realm": ""`; object 14
      (format 2) with slots 4, 7, 8, 16 and no `"0"`. `seen` now gains the GUID's key, not `Name-`
      (HelloLink 1.18.0). Still to see: the owner's hunter with its ammunition in slot 0; no Lua error.
- [ ] HelloLink 1.15.0 (the window and spellbook probes, #232, part D): open a merchant, a loot window, a
      quest dialogue and a profession's window once each. `HelloLinkDB.probeWindows` gives `window merchant`,
      `window loot`, `window quest` (from a quest window, not only a gossip) and `window trade skill`, each
      with the event that opened it; `HelloLinkDB.probe`'s login run gives `spellbook`. Each getter's
      answer, "absent" or `<secret>`. Settles part D items 4 and 5 (review of #268: the windows in
      probeWindows, since probe's login run has the same lines with no window open).
      Seen on 22 Nov 2026 at about 01:00 (the level 1 test character in Stormwind; HelloLink 1.15.0, the reader of
      e87c214), in a command run of `/hlink probe api` with no window open: every new line answers.
      `GetMerchantItemInfo` is absent and `C_MerchantFrame.GetItemInfo` there; the old trade-skill calls
      are absent and `C_TradeSkillUI` there (`GetBaseProfessionInfo` a table of zeros, no recipes); the
      old spellbook calls are absent and `C_SpellBook` there (`GetNumSpellBookSkillLines` 2, item 1
      "Attack"). Not seen: any window opened (a click on an NPC moves the owner's pointer), so
      `probeWindows` holds nothing yet; `spellbook` in a login run (only a command run was read); a check for a Lua error. The box stays open.
- [ ] HelloLink 1.14.0 (the lanes probe, #232, part C): in the game, `/hlink probe lanes`, a screenshot
      (`screencapture -x -t bmp`), `hellolink depth` on it: `lines` 4 and `wrongByLine` all 0 settles
      lanes (and `px` 1). Also `/hlink probe depth 8 1 4` for 9 bits (part C): an hour of such
      screenshots, 0 wrong and `apart` at least 12, says the screen carries it. It does not settle 9
      bits: the strip's capture stream reads in sRGB (`tools/strip_capture.swift`), and a screenshot
      and the stream can give a colour back differently. 9 bits goes on only after the stream, in the
      target colour space, gives the same 0 wrong and `apart` (review of #267).
      Seen on 22 Nov 2026 at about 01:05 (the level 1 test character; window screenshots of `agent-desktop`, converted
      to BMP): `/hlink probe lanes` in three screenshots, each `lines` 4, `px` 1, `wrong` 0,
      `wrongByLine` [0, 0, 0, 0], `apart` 27: lanes read true at 1 pixel. `/hlink probe depth 8 1 4` in
      three screenshots, each 15 wrong of 1,024 ([5, 3, 4, 3]) and `apart` 0: in this capture (sRGB) 9
      bits do not hold. Not done: the same in the display's colour space and with the capture stream,
      and the hour; the box stays open.
- [ ] HelloLink 1.13.0 (objects 4 and 14 in binary, #232): in format 3, `/state` gives objects 4 and 14 with
      `"format": 2` and the bags and gear as before; on the hunter, shots of the bow make no new
      version of either (only another change of the bags or the gear does); no Lua error.
      Seen on 22 Nov 2026 at about 01:00 (the level 1 test character): objects 4 and 14 with `"format": 2`, the bags and
      the gear as before. Not seen: shots (the character has no bow), and a check for a Lua error (the
      chat showed none; an error window was not looked for). Also seen, older than format 3 (the same in a record of the
      JSON days, 21 Nov 10:58): an empty ammunition slot comes as `"0": {"item": 0, "count": 1}`, not
      left out. The box stays open.
- [ ] HelloLink 1.12.0 (object 12 in binary, #232): in format 3, after a counted fight (HelloForever),
      `/state` gives object 12 with `"format": 2` and the baseline as before (fight, rev, the four
      triples); after a fight not counted, its three fields; no Lua error.
      Seen on 22 Nov 2026 at about 01:00 (the level 1 test character): object 12 `"format": 2` and `null` (no fight
      yet). Not seen: a counted fight or one not counted, a check for a Lua error; the box stays open.
- [ ] HelloLink 1.11.0 (objects 3 and 8 in binary, #232): in format 3, `/state` gives object 3 with
      `"format": 2` and the place as before (map, zone, sub, the instance's four), and object 8 with
      `"format": 2` and the rested XP; no Lua error.
      Seen on 22 Nov 2026 at about 01:00 (the level 1 test character in Stormwind): object 3 `"format": 2` with map
      1453, zone, sub "Trade District" and the instance's four (false, "none", 0, "Eastern Kingdoms");
      object 8 `"format": 2` with `rested` 600. Not seen: a check for a Lua error (the chat
      showed none; an error window was not looked for); the
      box stays open.
- [ ] HelloLink 1.10.0 (object 13 in binary, #232): in format 3, with HelloForever's assistant on,
      `/state` gives object 13 with `"format": 2` and the acknowledgement as before (lang, seq, re,
      ask, left, taken, refused, shown); with it off, `null`; no Lua error.
      Seen on 22 Nov 2026 at about 01:00 (the level 1 test character, HelloForever's assistant on): object 13 `"format":
      2` with lang, seq 1, left 199, taken 0, refused 0, shown, and `ask` `re` null. Not seen: the
      assistant off, a check for a Lua error; the box stays open.
- [ ] HelloLink 1.9.0 (object 2 in binary, #232): in format 3, with a creature as the target,
      `/state` gives object 2 with `"format": 2` and the target as before (name, type, class, level,
      id, reaction); with a player, `id` `null` and `type` as the client gives it ("Humanoid" for a
      player, as format 2's JSON says); with none, `null`; no Lua error.
      Seen on 22 Nov 2026 at about 01:00 (the level 1 test character): object 2 `"format": 2` and `null` with no target;
      a Stormwind City Guard (class, id 68, level 55, reaction 5, type "Humanoid"); the character itself as
      a player (id `null`, type "Humanoid"). Not seen: a check for a Lua error (the chat showed none; an
      error window was not looked for); the
      box stays open.
- [ ] HelloLink 1.8.0 (object 9 in binary, #232): in format 3, with a journey of the route addon,
      `/state` gives object 9 with `"format": 2` (a short route) or `3` (a long one, deflated), and the
      route as before (goal, seconds, legs); with none, `null`; no Lua error.
      Seen on 22 Nov 2026 at about 01:00 (the level 1 test character): object 9 `"format": 2` with a journey of the
      route addon (goal map 1415, a walk of 148 s, guided, one leg). Not seen: no journey (`null`), a
      long route deflated (format 3), a check for a Lua error; the box stays open.
- [ ] HelloLink 1.7.0 (the events probe, #232). In one UI session (the owner's hunter): `/hlink
      probe api` once (the counts before). With a target and a ranged spell on a visible bar slot, walk
      into range, `/hlink probe api`; walk out of range, `/hlink probe api` (each run right after its
      crossing, the target kept: a lost target also sends the range event). Make one spell unusable
      and usable again (power or a cooldown), `/hlink probe api`. A fight with a target that casts,
      `/hlink probe api`. In the saved line "events seen" (HelloLinkDB.probe), each run against the
      one before: `ACTION_RANGE_CHECK_UPDATE` and
      `ACTION_USABLE_CHANGED` counted or "refused", and their last arguments name that slot (the range
      event with `checksRange` true and `isInRange` changed between the two runs);
      `ACTIONBAR_UPDATE_USABLE` counted; `UNIT_SPELLCAST_START` names `target` among its units.
      Note: the range event may come only for slots the client's own bar watches (the visible ones).
      Settles part D item 2 (the action bar by events or by reads) and item 1's casts.
      Seen on 22 Nov 2026 at about 01:00 (the level 1 test character standing; a command run):
      `ACTION_RANGE_CHECK_UPDATE` 23, last (84, false, false); `ACTIONBAR_UPDATE_COOLDOWN` 13;
      `ACTIONBAR_SLOT_CHANGED` 9; `SPELL_UPDATE_USABLE` 20; `ACTIONBAR_UPDATE_USABLE`,
      `ACTION_USABLE_CHANGED` and the spell-cast events 0. None refused. Not done: the walk across a
      range, a spell made unusable and usable again, the fight with a target that casts; the box stays
      open.
- [ ] HelloLink 1.6.0 (the back-off, #232): in format 3, `/hlink probe api` in a fight gives
      `GetFramerate` a number (not secret). With the game under 20 frames a second, a record shows
      each chunk on the row for two frames in a row, and the fast state still new each frame; no
      Lua error.
      Seen on 22 Nov 2026 at about 01:00 (the level 1 test character, out of combat): `GetFramerate`
      29.9 at that one reading (the `addon cost` line). Not seen: the value in a fight; a frame rate
      under 20 with each chunk on two frames in a row and the fast state new each frame; a check for a
      Lua error. The box stays open.
- [ ] HelloLink 1.5.0 (the event ring, #232): in format 3, `/events` gives a `ring` event for a
      loot (its item and quantity), for money gained and spent (a vendor), for XP (a kill), and
      for a UI error (a spell out of range); each once. A `/reload` gives none of the events before
      it. No Lua error. Not testable on the level 1 test character alone: a level and a death.
      Seen on 22 Nov 2026 at about 01:00 (the level 1 test character; the record 2026-11-22-0101): every format 3 frame
      read holds section 3, the counter 0 and no event. Typed `/cast` lines made no UI error here (the
      error counter did not move), so no `ring` event was seen. Not seen: loot, money, XP, a UI error, a
      `/reload`, a check for a Lua error; the box stays open.
- [ ] HelloLink 1.4.0 (object 27 in binary, #253): in format 3, `/state` gives object 27 with
      `"format": 2` and its slots as before (a spell, an item, a cooldown running with its
      start and duration, an action that is neither, with `null` for what it is; an empty slot
      left out); no Lua error.
      Seen on 21 Nov 2026 at about 15:40 (the level 1 test character in Stormwind, alone; HelloLink 1.4.0's Lua,
      the reader of cc34c56): `/state` gave object 27 as `"format": 2` with its slots, spells
      (`S:...`) and items (`I:...`), each with `false, false, 0.0, 0.0` (no cooldown running);
      objects 24 and 26 also came as format 2. Not seen: a cooldown running, an action with `null`
      for what it is, and the chat (no screenshot could be taken), so the box stays open.
- [ ] HelloLink 1.3.0 (object 24 in binary, #251): in format 3, `/state` gives object 24 with
      `"format": 2` and its units as before (a party member, a nameplate, a target that is one
      of them); no Lua error.
      Seen on 21 Nov 2026 at about 15:05 (the level 1 test character in Stormwind, alone; HelloLink 1.3.0's Lua,
      the reader of 22e6765): `/state` gave object 24 as `"format": 2` with the text
      `{"nameplates":[]}`. Not seen: a party member, a nameplate or a target among them (no group;
      the nameplates are off, a setting of the owner's left as it is), and the chat (no screenshot
      could be taken), so the box stays open.
- [ ] HelloLink 1.2.0 (object 26 in binary, #248): in format 3, `/state` gives object 26 with
      `"format": 2` and its auras as before (the player's and the target's, with times); after
      `/hlink strip format 2` it gives format 0 or 1 again; no Lua error.
      Seen on 21 Nov 2026 at about 14:20 (the level 1 test character in Stormwind; HelloLink 1.2.0's Lua, the
      reader of 5f480a8): `/state` gave object 26 as `"format": 2` with the text
      `{"player":[["S:460939:56239",0,3600.0,188631.3,null]],"target":[]}`; the other objects
      kept formats 0 and 1. After `/hlink strip format 2` object 26 came as format 1, and after
      `/hlink strip format 3` as format 2 again. No error window or line in the screenshot of the
      chat. Not seen: a target's aura (the level 1 test character had no target), so the box stays open. The
      game had been disconnected at its character screen; its Reconnect needed no password.
- [ ] HelloLink 1.1.0 (format 3 by default, #246): loaded over the saved data of 1.0.0, the strip
      draws format 3 before any command (the answer of `/hlink strip` says format 3); after
      `/hlink strip format 2` and a `/reload` it stays format 2; `/hlink strip format 3` goes
      back.
      Seen on 21 Nov 2026 at about 11:50 (the level 1 test character; the saved data said format 2 and
      `formatRelease` 2, as 1.0.0 left it): before any command `/state` gave `"format": 3`;
      after `/hlink strip format 2` it gave 2, and after `/reload` still 2 (the saved data:
      format 2, `formatRelease` 3); `/hlink strip format 3` gave 3 again, and the saved data
      after the logout says format 3. Not seen: the answer of `/hlink strip` (it was sent, but no
      screenshot could be taken then), so the box stays open.
- [x] The fall-back: at 3 bits (`/hlink strip depth 2`) the depth square reads 7 and the reader
      follows. Seen: after `/hlink strip depth 2`, `/state` gave `"format": 3`, `"depth": 2`,
      `live`; back to `depth auto` and then `format 2`, which the saved data keeps.
