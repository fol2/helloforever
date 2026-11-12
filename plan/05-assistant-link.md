# Find out how the assistant can talk to the running game

**Why.** The assistant (`docs/north-star.md`) lives outside the game: an addon cannot open a
connection or read a file. Today the only way out is SavedVariables at a reload, and
nothing comes back in. Another project, chelinho139/wow-ai (MIT), reports three facts
about the Forever client. On 12 Nov 2026 this repo saw 1 and 2 hold (sections 1 and 2); 3 is open:

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

## 3. Text out of the game without a reload (HelloLink 0.0.2): built, not yet seen in the game

`/hlink send <text>` draws the text as coloured squares in the top-left corner of the game
for 30 s. `tools/hellolink_strip.py read --screen` takes a screenshot of every display,
looks for the strip, prints the text and deletes the screenshots. Outside the game the
test passes at scales from 0.7 to 3.3. Two things only the game and the Mac can show:
whether the client draws the squares as asked, and whether the screenshot shows the game.

**Consent.** macOS shows other programs' windows in a screenshot only to a program with
Screen Recording consent (System Settings, Privacy & Security, Screen & System Audio
Recording). Without it the screenshot holds the desktop picture only and the reader says
`no strip`. The consent belongs to the program that runs the reader (the terminal, or the
Claude app). Only the owner can give it.

Install 0.0.2 with the same `install` command as above, while the game is closed. Then, in
the game, windowed or borderless (not exclusive full screen):

- [ ] `/hlink send hello 你好`: a block of coloured squares appears at the top-left, and chat
      says `strip up for 30 s`.
- [ ] Within the 30 s, on the Mac: `python3 tools/hellolink_strip.py read --screen` prints
      `hello 你好`. If it prints `no strip in 3 screenshot(s)`, give the consent above and try
      again; if it still fails, keep one screenshot of the corner for the issue.
- [ ] A long text (a few hundred characters): it comes back whole.
- [ ] `/hlink hide`: the squares go. They also go by themselves after 30 s.
- [ ] Note anything that sits on top of the strip (the top-left of the UI) and breaks it.

**Done when.** Every box is ticked or has a note saying what the client did instead, and
the next step of priority 3 in `docs/north-star.md` is chosen from the result.
