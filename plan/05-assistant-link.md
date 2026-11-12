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

So a square of N physical pixels, asked for as `N * 768 / physicalHeight /
UIParent:GetEffectiveScale()` UI units, is drawn exactly, down to 2 pixels.

**P2, secret values** (`/hlink probe secrets`; one sample out of combat, one 2 s into a
fight; the result came out through the strip and was read from the screen at 22:11:09):

- Secret in **both** samples, so also out of combat: the player's health and power, the
  target's health and maximum health, the pet's health.
- Readable in both: the maxima of the player's health and power, the power type, level, XP
  and its maximum, dead, mounted, resting, AFK, target exists, target level, target hostile,
  target classification, target tapped, the pet's maximum health, map, position, facing,
  money, free bag slots. The target's name was readable with a target.
- `GetPetHappiness` does not exist on this client. Casting was not tried (no cast at either
  sample).

An addon cannot do arithmetic on a secret value, so the strip cannot carry current health
or power as numbers. The client's own bars show them; whether the strip should show them
as bars for a reader to measure is an open decision (`docs/specs/29.md`).

**P3, capture rate** (`tools/hellolink_strip.py probe --rate`): 8.6 captures a second of a
600 x 80 rectangle, each read and parsed. A capture of all three displays with a decode
took about 0.7 s (`time` of `read --screen`, no strip up).

**P4, compression**: not run yet (`/hello selftest` lists `C_EncodingUtil.CompressString`).

**Done when.** Every box is ticked or has a note saying what the client did instead, and
the next step of priority 3 in `docs/north-star.md` is chosen from the result.
