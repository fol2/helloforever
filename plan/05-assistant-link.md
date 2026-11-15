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
python3 tools/hellolink.py install "/Applications/World of Warcraft/_forever_/Interface/AddOns"
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
changes, so it is installed while the game is closed (`tools/hellolink.py install`, which
now makes 200 slots). Installed on the development Mac on 13 Nov 2026, while the game was
closed: HelloLink 0.1.0 and 200 slots; the installed files equal the repository's.

To follow the row from the Mac, with the game running:

```
python3 tools/hellolink_strip.py watch --addons "/Applications/World of Warcraft/_forever_/Interface/AddOns"
```

It builds the capture stream once (`swiftc`), finds the row on any display, then prints a
line for each new state and each object. `--json` prints every event whole. With
`--addons` it asks the strip to fall back when six bits a square do not hold. A single
frame can also be read from a screenshot saved as BMP:
`python3 tools/hellolink_strip.py rows <file.bmp>`.

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

- [ ] Owner: with the reader running (`tools/hellolink_strip.py watch --serve 8787`), a
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
| A doorbell: a file that appears, changes or goes | `PlaySoundFile` on two missing files in `Interface/HelloLinkProbe/` (outside `AddOns`), and on a sound that was in an addon at the start; then the two files made while the game ran (one empty, one a copy of the sound), and called again; then again after a `/reload` | Missing: `nil`. The sound from the start: `true` and a handle. The two new files: `nil`, and still `nil` after the `/reload`. A file that appears while the game runs is not seen, at least outside `AddOns`. Not tried: a file that was there when the game started and then changes or goes (the folder stays for that, at the next start), a file in `AddOns` (the game must be closed to add one), a texture. |

What this changes for the build:

- The assistant's window can be a page of the game's settings (`Settings.RegisterCanvasLayoutCategory`).
- `sell` and `repair` can read their inputs out of combat; the price needs a call again when
  the first gives `nil`. `talent` has its function (`C_ClassTalents.HasUnspentTalentPoints`);
  whether its value can be secret is not checked.
- A look is cheap enough for the fixed times of `docs/specs/115.md`, section 6; a doorbell by a
  new file outside `AddOns` does not work, so those fixed times stay until the rest of the
  doorbell row is tried.

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
- [ ] No card on a creature without fights: there is no `target` card yet (its probe waits).
- [ ] Owner, in play: the `fight` card after fights against one kind of enemy.

## 11. The assistant, step 2 (HelloForever 0.13.0, HelloLink 0.2.0, #127): the game check

The tests prove the slot file's part, what HelloLink takes, the looks, HelloForever's side and
object 13 against the stubs (`tests/hellolink_assist_test.py`, `tests/hellolink_assist_test.lua`,
`tests/strip1_addon_test.lua`, `tests/assist_harness.lua`). These need the game; both addons
gain or change files, so they are installed with the game closed. Bank character:

Seen on 15 Nov 2026 (session 21517; the reader installed at 651b7a3, started by the local
program):

- [x] A set written by hand for the session (`tools/hellolink.py write <AddOns> --assist`) was
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

`tools/assistant.py` is tested against a stand-in for the reader's API and a scratch AddOns
folder (`tests/assistant_test.py`). It is installed with the reader
(`tools/install_reader.py`). In the game, with the reader and the assistant program running:

Seen on 15 Nov 2026, with the reader and the assistant program (da03084) started by the local
program, in the owner's play (session 21523; the cards in Cantonese, the owner's setting):

- [x] `/hello ask session`, typed by the owner: the set with the answer was written one second
      after the question (`t` 1794768398, the question's 1794768397); object 13 then said
      `"seq": 3, "re": 2, "ask": {"n": 2, ...}, "taken": 1, "shown": "out:session"`. The card:
      `今次：20 場，死 0 次，每個鐘 7,387 XP，+4 s 12 c`, ground `由 18:24 起嘅 strip`, detail
      `比平時慢得最多：Timberling 25 秒，平時 12 秒`.
- [x] Before the question the program wrote its heartbeat set within seconds of its start
      (`seq = 1`, no card).
- [ ] The assistant program started again answers no question twice (object 13's `re`): not
      tried in the game (the test holds it).

