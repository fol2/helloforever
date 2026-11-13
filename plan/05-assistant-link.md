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
- [ ] Not tried: `nothing new` on an unchanged inbox, and what the client says when the
      slots run out. The harness covers both against the mock only.

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
- [ ] The fall-back asked for by a reader (the slot request): never needed in this run, so not
      seen end to end. Only `/hlink strip depth 2` by hand was seen.
- [ ] Six bits a square for an hour without a break, and on another display.
- [ ] A channelled spell's values. On a hunter, try Mend Pet, Eyes of the Beast, Tame Beast
      or Volley (which of them this client channels is not checked).
- [ ] The row at a scale other than 1 (a window, or a display with a backing scale).
- [ ] A hunter's shots change the ammunition count, so the bags object was sent again about
      every two seconds in a fight (item 3030 went down by one 187 times in the run). The
      owner chose on 13 Nov 2026: the ammunition's count alone is not a change, and may be
      late. In the addon since #44, by the item in inventory slot 0. **Not yet seen in the
      game**: that slot 0 is the ammunition on this client is assumed. Check:
      `/dump GetInventoryItemID("player", 0)` prints the arrow's id (3030 on 13 Nov), and in
      a fight with the bow `watch --json` shows no bags object (id 4) for the shots. If slot
      0 gives nothing, the addon behaves as before (every shot is a change).
- [x] The slow fall-back (`screencapture`) reported "no row" for every second image: it fed
      every display's image to the reader. Fixed in #46: it gives the image of the display
      that shows the row and then captures only that display. Shown by a test with a stand-in
      for `screencapture`; not yet seen on the fall-back with the game on screen.

Loot (the `loot` group, #39):

- [x] After `/reload`, loot three items one after another. `watch --json` shows `loot.counter`
      1, 2, 3, each with the item's id and quantity. Done on 13 Nov 2026: items 5529, 2592,
      4306, quantities 1, 1, 2.
- [x] What the client gives with `CHAT_MSG_LOOT` (a probe, 13 Nov 2026): arguments 2 and 5 are
      the character's name with a family name and no realm; `UnitName("player")` is the first
      name only; argument 12 is the player's GUID, equal to `UnitGUID("player")`. The addon
      compares the GUID.
- [ ] In a group, another player's item does not move the counter. Not yet seen in the game;
      only the mock client covers it.

**Done when.** Every open box above is ticked or has a note saying what the client did instead, and
the next step of priority 3 in `docs/north-star.md` is chosen from the result.
