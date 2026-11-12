# Find out how the assistant can talk to the running game

**Why.** The assistant (`docs/north-star.md`) lives outside the game: an addon cannot open a
connection or read a file. Today the only way out is SavedVariables at a reload, and
nothing comes back in. Another project, chelinho139/wow-ai (MIT), reports three facts
about the Forever client. This repo has seen none of them:

1. The client reads a load-on-demand addon's file from disk when the addon is loaded, so a
   program can put text into a slot addon that existed at client start. No reload.
2. `ReloadUI()` works only from a key press or a click, never from a timer.
3. A program can read coloured squares the addon draws in a corner of the screen. No reload.

`HelloLink` tests 1 and 2. It is a spike: one file, not part of the HelloForever package.

**Install** (done on the development Mac on 12 Nov 2026, with 50 slots; the client must be
started after it):

```
python3 tools/hellolink.py install "/Applications/World of Warcraft/_forever_/Interface/AddOns"
```

## 1. Text into the game without a reload

With the game running and a character logged in, in a terminal:

```
python3 tools/hellolink.py write "/Applications/World of Warcraft/_forever_/Interface/AddOns" "hello from outside"
```

Then, in the game, **without** `/reload`:

- [ ] `/hlink` prints `slot 1, message <number>:` and `hello from outside`. If it prints
      `no slot left (HelloLink_S001: ...)`, note the reason in the brackets: the client did
      not find or would not load the slot.
- [ ] Write another text, `/hlink` again: the new text, from slot 2. If it shows the old
      text or "nothing new", the client caches the files: fact 1 is false here.
- [ ] `/hlink` once more with nothing written: `nothing new (slot 3)`.
- [ ] Write Chinese text ("你好"): it shows correctly.
- [ ] After `/reload`, `/hlink` starts at slot 1 again and shows the latest text.

## 2. ReloadUI without a key press

- [ ] `/hlink reloadtest`, then touch nothing for 5 s. Either the UI reloads (fact 2 is
      false: `/hello afkreload` can work), or chat says `still here, so the reload was
      refused`. Record which in `plan/01`, section 9, and on issue #20.

## 3. Not built yet: text out of the game without a reload

Fact 3 needs a pixel strip in the addon and a screen reader on the Mac (which needs the
owner's Screen Recording consent for the program that reads). Build it only after section 1
passes; until then questions leave through SavedVariables at a reload.

**Done when.** Every box is ticked or has a note saying what the client did instead, and
the next step of priority 3 in `docs/north-star.md` is chosen from the result.
