# Changelog

See also [`HelloForever/HISTORY.md`](HelloForever/HISTORY.md) for API / schema detail.

## The reader — 2026-11-20

**New: `hellolink depth`, the colour depth probe read again** (#213, step 4)

- `hellolink depth <image>...` reads the rows of `/hlink probe depth <levels> [pixels]` from
  screenshots, as the Python reader did before #210. One JSON line an image: the levels a
  channel, the pixels a square, the pattern squares named wrong (of 240), and how far apart
  the nearest two palette colours came back. It fails when no image holds the rows.

**New: `hellolink replay`, a record read back** (#213, step 5)

- `hellolink replay <record>` reads a file of `watch --record` and feeds it through the same
  Watcher as `watch`. It prints the events `watch --json` said, one JSON line each, with the
  capture's time `t`. Each run's header becomes `{"kind": "record", "started": ...}`.
- It measures a record offline: which fast-block groups and objects change, and how often.
  A record of an hour of play replays in about a second.

## The reader — 2026-11-19

**New: the strip reader in Rust, used by the tests** (#195, step 1; CI under a minute, #193)

- `reader/` holds a Rust crate, `hellolink`: the format-1 codec and the row reader of
  `tools/strip1.py`, and the bitmap, `render` and `rows` parts of `tools/hellolink_strip.py`.
  Its commands are `rows`, `render`, `render-rows` and `serve`, as the Python ones.
- On the cells files of the addon test it prints the same lines as the Python reader, byte
  for byte, and draws the same images. The addon test reads its frames through it (`render-rows`); the live reader is still the Python one.
- Step 2a: the Watcher (the reader that follows the row), its request to fall back and the
  record of `--record` are in Rust too, with the same events and lines as the Python ones.
- Step 2b: `hellolink watch` follows the row in Rust: the capture stream and its time limits,
  the look at every display, the slow fall-back, `--json`, `--record`, `--remember`. On the
  same capture stream it writes what `hellolink_strip.py watch` writes, byte for byte.
- Step 2c: `watch --serve PORT` serves the local HTTP API (`/state`, `/events`) and
  `watch --addons DIR` asks the strip to fall back through the slots, in Rust. `hellolink
  write` writes the slots as `tools/hellolink.py write` does: the same slot files, byte for
  byte, and the two tools can take turns on the same slots.
- Step 3a: `hellolink assist` is the assistant program in Rust: on the same events and clock
  it writes the same sets as `tools/assistant.py`.
- Step 3b: `hellolink install` (the slots), `install-reader` (this program and the capture
  source, outside any checkout) and `package` (the release checks and zip) are in Rust. The
  slot install is the same files as `tools/hellolink.py install`; the release zip holds the
  same entries as `tools/package.py`'s. Checked with `rust-anything app replay` too. The
  Python tools are still the ones in use.
- Step 3c: the Python tools and tests are gone; `hellolink` is the only reader, and
  `install-reader` is guarded by the lock beside the folder, not by `ps` and `lsof`.

## HelloLink 0.8.3 — 2026-11-20

**The probe no longer stalls a fight** (#213)

- In 0.8.2 the probe's run a second into your first fight also measured HelloLink's memory. That
  asks the game to measure every addon, and took 55 to 78 ms: one frame that long. The runs at
  the first target, in a fight and in a raid now skip it; the login run and `/hlink probe api`
  still measure it.
- In the new format-2 lines, a call that fails now keeps the error's text, so the next play
  shows why the auras could not be read.

## HelloLink 0.8.2 — 2026-11-20

**The probe for strip format 2** (#213)

- `/hlink probe api` also asks what a denser strip would carry: each unit (you, your pet,
  your target and its target, your pet's target, the mouseover, the focus, the first party and
  raid member, the first boss and the first nameplate), your and your target's auras, a few
  cooldowns, your first three action buttons, the group, the hunter's fields, the breath and
  fatigue timers, and HelloLink's own memory. Each value is written as it came back: a value,
  `<secret>`, `absent` or `ERROR`.
- These lines also run once when you first target something, once a second into your first
  fight, and once in your first raid, since the client may keep more secret in a fight.
- Nothing on the strip changes. The results stay in your saved data on this computer.

## HelloLink 0.8.1 — 2026-11-19

**The character's full name, and each guide step's elements** (#199)

- The character's name with the family name (`FakeHunter Family`), taken from your own loot
  message, is on the strip (object 10, `fullName`) and in the saved data, per character. It
  stays across a `/reload`. Another player's loot never sets it.
- The saved list of characters that logged in has the full name too, so a program can match
  the game's own folders (`Name-Surname`).
- Each guide step lists its first 20 elements in order, as tag and quest id pairs (at most 40
  pairs a step, so the object stays small enough to send).
- `/hlink probe api` has a new line, `fullName`: what five client getters answer for the name.
  HelloLink 0.8.2 uses the one that answers.

## HelloLink 0.8.0 — 2026-11-18

**New on the strip: what the probe of 18 Nov 2026 saw answer** (#191)

- Five new objects: the quests you have completed (`done`, read only at login and when you
  turn one in), where your corpse lies (`corpse`), your reputations (`rep`), the price Auctionator
  last scanned for your items (a listing, not a sale; `ah`, with Auctionator installed), and your pet's experience
  (`pet`).
- The guide's steps now start at the current step and show four after it, each with its tags,
  quests and whether it is done, and RXP's orphaned quests and the names it looks for.
- The gear shows your ammunition and its count (a shot sends nothing new); each bag says what
  it may hold (a quiver).
- The saved data notes which characters logged in, so a program finds the live account.
- Twenty-three objects: a reader calls an object old after 82.8 s without it (64.8 s before).
- Not sent: repair cost, flight points, talents, pet happiness (this client has none) and
  crafting. Not yet seen in the game: a corpse while dead.

## HelloLink 0.7.2 — 2026-11-18

**The probe also asks for the realm's number** (#188)

- `/hlink probe api` asks the client for the realm's id and name, to learn which number names
  the realm's folder in the game's saved data (`WTF/Account/<account>/<number>/`). The
  account's own name is not asked: it is private.

## HelloLink 0.7.1 — 2026-11-18

**New: `/hlink probe api`** (#185)

- Asks this client, once, each call that HelloLink 0.8.0 would read: bag family, repair cost,
  completed quests, corpse, flight points, reputation, hearthstone, rested XP, talents, pet,
  ammo slot, and the guide, route, auction and profession addons that are installed. Read only:
  a function of another addon that would write or build (the guide's orphan list, the
  profession plan) is only looked at, not called, and a value the client keeps secret is only
  named.
- The answers are kept in the saved data (`HelloLinkDB.probe`, the last 8 runs), for the
  program outside to read after a `/reload` or a logout. It also runs 10 s after login; a
  flight master's map runs the flight-point probe once, a merchant window the repair probes.

## HelloLink 0.7.0 — 2026-11-18

**New: the hearthstone on the strip** (#180)

- Object 18 `hearth` says where your hearthstone is bound and when it is ready: the end of its
  cooldown as a time, so a program counts down by itself and the strip sends nothing new while
  the cooldown runs. `null` when your bags hold no hearthstone.
- The global cooldown is not taken for the hearthstone's. A count or a cooldown that the client
  does not give, fails or keeps secret makes the object unreadable, never "ready" or "none";
  a bind it does not give is sent as `null` with the rest.
- Eighteen objects: a reader calls an object old after 64.8 s without it (61.2 s before).
- Not yet seen in the game: whether this client answers these calls.

## The reader — 2026-11-18

**New: a record of a play session** (#178)

- `tools/hellolink_strip.py watch --record <file>` appends one line for each capture: the
  frame's bytes when they change, the reason and the bytes of a read that failed, and the
  palette as read when it moves. It is the ground for measuring a denser strip (format 2)
  offline, with real play in place of estimates.
- The addon and the strip do not change. The record holds the character's state: keep it on
  this computer.

## HelloLink 0.6.1 — 2026-11-18

**Lighter: the strip asks for almost no memory while you play** (#175)

- The strip read the game's state ten times a second and made new tables, texts and names for
  every read, then threw them away: 133 KB a second in the test client (LuaJIT with the JIT off; 449 KB
  in Lua 5.5). It now keeps and reuses them: 5 to 7 KB a second there, and about a third less CPU
  time in that client.
- An object's bytes are not made again while its newest version was made from the same text by
  the same compressor (a question typed again is still a new version), and its chunks are kept
  while it is sent again and again.
- Nothing on the strip changes: a test holds every square's colour over thirty seconds of play
  against what 0.6.0 drew, and the Python reader reads the row as before.
- Not yet measured in the game.

## HelloLink 0.6.0 — 2026-11-16

**New: the character's looks, taken at a barber** (#168)

- When you sit in a barber's chair, and when you accept a new appearance there, HelloLink keeps
  your character's appearance choices (skin, face, hair and the rest) in its saved data,
  `HelloLinkDB.looks`. A program outside reads them after a logout or a `/reload`
  (`docs/STRIP.md`, section 11). The game gives these choices nowhere else.
- Nothing on the strip changes.
- Not yet seen in the game: nobody has sat in the chair with this version.

## HelloLink 0.5.1 — 2026-11-16

**Fixed: the trainer object's step** (#160)

- Once, most likely after a service was bought, the client gave a step past the end of the list it shows; object
  17 passed it on, and a reader would take it as an index. `step` is now `null` unless it is in
  `services`.

## HelloForever 0.18.3 — 2026-11-16

**Fixed: a subject taken back from mute shows its card at once** (#166)

- After `/hello assist unmute ammo` (or the window's Take back) the ammo or bags card came back
  only when the bags or the gear next changed, though its condition held all along. It now
  comes back at once; in a fight, when the fight ends.

## HelloForever 0.18.2 — 2026-11-16

**Fixed: no false skill maximum in the saved data** (#157)

- When the game cannot give a skill line in full, the skills in the snapshot keep their last
  good read, marked stale; a missing maximum was written as 0, and a line that failed was left
  out. A skill-up after such a moment is still found.

## HelloForever 0.18.1 — 2026-11-16

**Fixed: no false numbers in the saved data** (#154)

- When the game cannot give a bag's size or an item's count, the bags in the snapshot keep
  their last good read, marked stale; they had a count of 1 or an empty bag.
- When it cannot give your XP or level, that timeline tick is left out; it was written as 0,
  which the offline reports took as XP gained.

## HelloLink 0.5.0 — 2026-11-16

**New: the strip's settings window** (#152)

- `/hlink settings`, or the game's AddOns options (HelloLink): the strip on or off, its size
  (2, 3 or 4 pixels a square), its depth (auto, 2 or 4), how long a chunk stays (5 to 100
  hundredths of a second), and its place (from the left, from the top, or back to 0, 0),
  without typing. The `/hlink strip` commands stay.
- A change of place moves the strip: the reader looks for it again.

## HelloForever 0.18.0 — 2026-11-16

**New: a settings window** (#150)

- Every setting that could only be typed has a control: the panel (shown, locked, scale,
  position), the line after each fight, the baseline line, the combat log file, the fight
  log's size budget, and the assistant. Emptying the baseline and dropping fights over 30 or
  90 days ask for a second click.
- Open it from the panel's right-click menu (Settings), from the game's AddOns options, or
  with `/hello settings`. The commands stay.

## HelloForever 0.17.0 — 2026-11-15

**New: the assistant's `bags` card** (`docs/specs/115.md`, section 5, #148)

- With 2 bag slots or fewer free, the bar says so: `Bags: 2 free`; more urgent with none.
  The count is the game's own. In English or Cantonese.

## HelloForever 0.16.0 — 2026-11-15

**New: the assistant's `ammo` card** (`docs/specs/115.md`, section 5, #146)

- When your bags hold fewer than 200 of the ammunition you have on, the bar says how many are
  left: `Rough Arrow: 140 left`; more urgent under 50. In English or Cantonese.
- In a fight the count waits for the fight's end. When a bag slot cannot be read there is no
  card, rather than a count that is too low.

## HelloForever 0.15.0 — 2026-11-15

**New: the assistant's `gold` card** (`docs/specs/115.md`, section 5, #144)

- After each hour of play, the bar shows what the last hour brought against your usual hour:
  `This hour: 1 g 20 s, usual 2 g`, the median of up to 20 earlier hours. It needs 3 earlier
  hours, and hours played before this login give no card. In English or Cantonese.
- An hour of play is an hour in the game, and may span two logins. Time logged out does not
  count, except a logout shorter than 6 minutes, which counts as play. The money is net: what
  you spent counts against what you gained.
- A timeline tick whose money the client cannot give is skipped; it was written as 0.
- Read from the character's timeline, which HelloForever already keeps: saved data does not
  change.

## HelloLink 0.4.0 — 2026-11-15

**New: the strip carries the trainer window** (`docs/STRIP.md`, section 6, #141)

- Object 17 `trainer`: while a trainer window is open, the trainer's creature id, the
  profession it trains, the stage it teaches, the window's filter, and each service it lists
  (name, rank, state, required level and skill, cost). `null` while no trainer window is open.
- The window's filter decides what the client lists; HelloLink does not change it, and says
  which states are shown.
- Seventeen objects take turns on the row: an object is stale after 61.2 s (57.6 s before).
  Reinstall the reader (`tools/strip1.py`) with the addon.
- Read from the client's own trainer UI, not probed in the game; the game check follows
  (`plan/05-assistant-link.md`, section 14).

## HelloLink 0.3.0 — 2026-11-15

**New: the strip carries the character's gear, bags and bank** (`docs/STRIP.md`, section 6, #138)

- Object 14 `gear`: each equipped slot, with its item, enchant, random suffix and durability.
- Object 15 `bagslots`: the bags slot by slot (the keyring, the backpack, bags 1 to 4 and the
  reagent bag). A change in the ammunition's count alone sends nothing new.
- Object 16 `bank`: the bank's tabs, slot by slot, while the bank is open; `null` while it is
  closed.
- Object 10 `who` gains the character's `class` and `race`.
- Sixteen objects take turns on the row, so an object is stale after 57.6 s (46.8 s before).
  The reader (`tools/strip1.py`) knows the new objects; reinstall it with the addon.
- A read that fails, or a value the client keeps secret, makes the object unreadable (format
  255), never a part of it: a bank without the account's tabs, gear without an enchant, a
  character without a class. This holds now for the ammunition in object 4 too.
- Read from the client's own UI source and the item link's documented fields, not probed in
  the game; the game check follows (`plan/05-assistant-link.md`, section 13).

## HelloForever 0.14.0 — 2026-11-15

**New: the assistant's `target` card** (`docs/specs/115.md`, section 5, #136)

- Out of combat, target a creature you have fought at least 3 times at your level: the bar
  shows what those fights usually were. `Defias Thug: usual 15 s, taken 340, died 2 of 8`.
  Prio 2 when one of them was a death. In English or Cantonese.
- The card goes when the target goes, or is not a creature. It does not change in a fight;
  a target picked in a fight gets its card when the fight ends.
- Saved data does not change.

## HelloForever 0.13.1 and HelloLink 0.2.1 — 2026-11-15

- HelloLink: the live-state strip's state flags gain bit 8192, a chat input is open (#131), so a
  program that types into the game can refuse while one is open. The client's active chat edit
  box tells it (seen in the game); when the client cannot say, the whole state group is
  unknown. `docs/STRIP.md`, section 5.
- HelloForever: the assistant's window says what HelloLink says also while the assistant is
  off; it said `HelloLink is not loaded` (seen in the game check of 15 Nov 2026).
- The game check of the assistant's steps 1 and 2 is recorded in `plan/05-assistant-link.md`,
  sections 10 and 11.

## HelloForever 0.13.0 and HelloLink 0.2.0 — 2026-11-15

**New: cards from outside the game, and a question** (step 2 of `docs/specs/115.md`, #127)

- A program on your computer (the companion, step 3) can put cards on the assistant's bar:
  `tools/hellolink.py write <AddOns> --assist <json>` writes a set of cards into the slot
  files; HelloLink 0.2.0 checks the set strictly and takes it only for this UI session and
  when it was written a moment ago; HelloForever shows its cards beside its own. Every `|` of
  a text from outside is doubled, so it draws no colour, icon or link.
- `/hello ask <topic>`, or the topic's button in the assistant's window, asks the companion.
  The bar says `asked: session` until the answer comes, or `no answer: is the companion
  running?` after 30 s. The one topic is `session` (the companion is step 3).
- The window's state line: the slots left and when the last set came, or that the strip is
  off. The setting `Take cards from the companion` now does what it says.
- HelloLink looks at a slot also for the assistant, while the assistant is on: at the fixed
  times at any depth, when a rest starts, at a level up, and 3, 8 and 20 s after a question.
  Never in combat; with 20 slots left only after a question.
- The live-state strip gains object 13, `assist`: what the game took from the companion and
  the last question (`docs/STRIP.md`). With thirteen objects an object is stale after 46.8 s
  (it was 43.2 s). `null` while the assistant is off.
- The slot file says `slots`, and a write of a part keeps the others: a reader's request no
  longer replaces a text.
- Saved data does not change.

## HelloForever 0.12.0 — 2026-11-15

**New: the assistant** (step 1 of `docs/specs/115.md`, #125). Off by default.

- Turn it on in its window (`/hello assist`, the panel's right-click menu, the button in the
  fight window, or the game's settings page) or with `/hello assist on`.
- A bar under the XP panel shows one card at a time: a line of advice that says what it
  stands on. Hover for the detail, who made it and its age; right-click to send it away;
  left-click for the window.
- The first card, `fight`: after a fight against one enemy, this fight against the usual
  fight with that enemy at your level. `Defias Thug: 12 s, usual 15 s · taken 210, usual 340`.
  It stays 120 s or until the next fight.
- The window lists the cards and has a control for every setting: on or off, the language
  (English or Cantonese), cards from the companion, the muted subjects, and a sample card.
  The commands are a second way: `/hello assist on|off|list|test|lang <code>|mute <key>|unmute <key>|outside on|off`.
- Nothing on the bar changes in a fight. A rule that fails three times is off for the session,
  and the fight is saved as before.
- Saved data: `settings.assist`, `assistOutside`, `assistLang`, `assistMuted`, and
  `characters[key].assist` (how often each card was shown and sent away) (`docs/SCHEMA.md`).
  Fight records do not change.

## HelloForever 0.11.0 and HelloLink — 2026-11-15

**New: the fight baseline on the live-state strip** (step 3 of the fight baseline, #109)

- HelloLink's strip carries object 12, `baseline`: after a counted fight, this fight's
  length, damage per second, damage taken and death against the usual fight with that enemy
  at your level, for a program on your computer (`docs/STRIP.md`, section 6). A later
  revision of that fight sends it again. `null` before the first counted fight after a login
  or reload, and after `/hello baseline reset`.
- HelloForever 0.11.0 hands the numbers to HelloLink in a plain table that is not saved.
  Without HelloForever the object is `null` and the strip runs as before.
- For a reader: with twelve objects an object is stale after 43.2 s without a whole copy (it
  was 39.6 s). Nothing else in the format changed.
- Saved data does not change.

## HelloForever 0.10.0 — 2026-11-15

**New: after a fight, how it went against the usual fight** (step 2 of the fight baseline, #104)

- Type `/hello baseline on`. After a fight against one enemy, one chat line compares this
  fight with the earlier fights against that enemy at your level:
  `Defias Thug (lvl 14): 12 s, usual 15 s · 38 dps, usual 31 · taken 210, usual 340 (8 fights)`.
- The usual value is the median of up to 10 earlier fights. A number gets its usual value
  only when at least 3 earlier fights know it. Before that the line says
  `first fights, 2 so far`. A death adds `DIED (usual: 0 of 8 died)`.
- No line for a fight against two or more enemies, or for a later revision of a fight.
- `/hello baseline off` turns the line off (off is the default). `/hello baseline reset`
  forgets the kept fights; fights that started before the reset are not kept again.
- Saved data: the setting `settings.baseline`, and `baselineResetAt` after a reset
  (`docs/SCHEMA.md`). Fight records do not change.

## HelloForever 0.9.0 — 2026-11-14

**New: the addon keeps the usual fights against each enemy** (step 1 of a fight baseline, #99)

- After a fight against one enemy, the addon keeps its length, damage per second, damage
  taken and death under that enemy and your level at the pull. It keeps the last 10 fights
  of each enemy and level, for at most 200 of them. Fights against two or more enemies, and
  fights where your level changed in the pull, are not kept.
- Nothing is shown yet. The next release compares a fight with the usual one, in one chat
  line that you turn on (`docs/specs/93.md`).
- Saved data: `characters[key].baseline` (`docs/SCHEMA.md`, "Fight baseline"). Fight records
  do not change.

## HelloLink: the live-state strip grows — 2026-11-14

**New on the strip: where the guide's arrow points, and the rested XP** (format 1, objects 7 and 8)

- Object 7, `waypoint`: the map and place that the arrow of RestedXP Guides points at, with
  the step's number and text, or `null`. Object 8, `rest`: the rested XP. `docs/STRIP.md`, section 6.
- For a reader: there are more objects now, so an object is stale after 28.8 s without a
  whole copy (it was 21.6 s), and after 32.4 s since object 9. A reader with the old time may call an object stale too early
  when many objects are large. Nothing else in the format changed.
- Object 7 also names the guide (`guide`). Object 9, `route` (#64): the journey that Shortest
  Path Forever has planned, as its public interface gives it: the goal, the time left and
  the legs (what to do, by what means, how many seconds). A leg has no place. With nine
  objects an object is stale after 32.4 s.
- Object 10, `who` (#68): the character's name and realm, so that a reader can tell which
  character's saved files belong to the one in the game. With ten objects an object is
  stale after 36 s.
- Object 11, `steps` (#74): the three steps of the guide after the current one, each with
  its number, text and place. With eleven objects an object is stale after 39.6 s.
- Object 12, `baseline` (#109): see HelloForever 0.11.0 above. With twelve objects an object
  is stale after 43.2 s.
- A guide text over its limit (object 7: 600 bytes; object 11: 400 bytes a step) is cut and
  ends with `…` (#78). It was `null` before. The cut is not inside a character, a texture
  code or a colour code.
- Object 2, `target`, has two more keys (#82): `id`, the creature's id, and `reaction`, the
  target's reaction to the player (1 to 3 hostile, 4 neutral, 5 to 8 friendly).
- Removed (#45): format 0, the text strip that `/hlink send` drew, and its reader
  (`hellolink_strip.py read`); `/hlink reloadtest`; the probes `squares`, `secrets`, `bars`,
  `curves` and `probe --rate`. `/hlink send` gives the question to the strip (object 1) only.
  `/hlink probe depth` stays.
- Object 3, `place`, says whether the player is in an instance, and which (#91):
  `instance`, `instanceType`, `instanceMap`, `instanceName`.
- The fast block's state flags say indoors (512), swimming (1024) and flying (2048) (#101).
  The client gives no height: `UnitPosition`'s z was 0 on 15 Nov 2026.
- The reader streams only (#103): it waits 15 s for a capture's first frame (4.5 to 10 s
  were seen under load) and tries a failed stream again after 2 to 30 s, saying `waiting`;
  it no longer falls back to `screencapture` while it has a capture program.
- The addon's version stays 0.1.0: `Strip.lua` and `HelloLink.lua` changed, no file was
  added or removed.
- The reader (#80): `waiting` is its first event, said at the start; `--remember <file>`
  keeps the row's place for the next start.

## HelloForever 0.8.1 — 2026-11-12

**Removed: the reload when AFK** (`/hello afkreload`, new in 0.8.0)

- Seen in the game on 12 Nov 2026: Forever refuses `ReloadUI` when it is not called from a
  key press or a click ("Interface action failed because of an AddOn"). The feature
  printed its warning and then nothing happened. It is gone; `/hello afkreload` now says so.
- Your data is still written at `/reload`, logout and exit, as before 0.8.0.
- The setting `afkReload` and the key `afkReloadAt` are no longer read or written. A file
  that has them keeps them; they mean nothing.

## HelloForever 0.8.0 — 2026-11-12

**New: save the data when you go AFK** (`/hello afkreload on|off`, off by default)

- The client writes the addon's data to disk only at `/reload`, logout and exit. An addon
  cannot write a file, and `/hello snap` only changes memory. So data collected before a
  long AFK stayed in the game until you came back.
- With the setting on, the addon reloads the UI once when you go AFK: after a 5 s warning in
  chat (move and it is cancelled), never in combat, and at most once in 10 minutes.
- Not yet seen in the game: that this client fires `PLAYER_FLAGS_CHANGED` for AFK and lets an
  addon reload without a key press. If either is not so, nothing happens and nothing breaks
  (`plan/01-in-game-verification.md`, section 9).

## HelloForever 0.7.1 — 2026-11-12

**Fix: fights were filed again at every login**

- The client announces a meter reset when it starts and still lists the fights of the last
  session, with the same ids. The addon threw its "already read" markers away on that
  reset, so it read all of them again and stored each as a new fight with an estimated
  start time. Seen in real data: about 30 copies at each login, and at least 98 copies
  among 724 collected fight files. The fault is in 0.5.0 and 0.6.0 as well.
- The markers are now kept across a reset (and across a restart of the session numbering)
  and marked as having left the list. A session that is listed afterwards is read and
  compared: the same content stores nothing, a session that grew is a new revision, other
  content is another fight under its own key. A marker whose session never returns is
  forgotten after an hour, as before.
- "The same content" is now proven, not assumed: the marker keeps a fingerprint of the whole
  meter content (everything but the rates, in any row order). Another fight on the same id with the same
  name, length and totals is stored under its own key. A marker written before 0.7.1 has no
  fingerprint, so **the first login after the update files the last session once more**;
  after that, never again.
- A reset also lets a session that had stopped changing be read again, and a marker whose
  session is gone expires after the hour by a timer, not only at the next read.
- Copies already stored are not removed. The offline pipeline's report counts a fight once.

## HelloForever 0.7.0 — 2026-11-12

**What a pull cost and used** (`record.pull`, new on every fight)

The damage meter gives totals only. Each fight record now also has:

- **Before and after:** XP, level, health, mana and pet health when combat started and
  when it ended. XP per fight and the cost of a fight no longer need a guess.
- **Target:** the name, level, classification and creature type of the target when combat
  started.
- **Cast counts:** per spell, for the player and for the pet, from
  `UNIT_SPELLCAST_SUCCEEDED`. A cast that landed up to 3 seconds before combat counts as the
  opener (`lead`). At most 40 different spells a pull; the rest are counted in `castsDropped`.
- **Spell names** (`record.spellNames`): id to name for the casts and for the player's
  damage and damage-taken rows, so a report needs no spell database.

A value the client keeps secret is left out, never guessed. The in-combat handler only
writes into a table. A different fight found on a reused session id gets the latest pull's
block marked `approx`, never the earlier fight's. Additive: `schemaVersion` stays 6.

Only run against the mock client. `plan/01-in-game-verification.md` lists what the game
must confirm (are health, mana and the target's level readable at the two combat events;
has the kill's XP arrived by then; does Auto Shot fire the cast event).

## HelloForever 0.6.0 — 2026-11-11

**Version alignment**

- TOC, `VERSION_FALLBACK`, README and docs all report **0.6.0** (the v0.5.0
  fallback could previously lag the TOC, so a metadata miss stamped `0.4.0`
  while the game showed `0.5.0`).
- Every export (SavedVariables root, character snapshot, fight record, gap
  record) carries `addonVersion`, `sourceRevision`, `schemaVersion` (6),
  `gameBuild` (the build string from `GetBuildInfo`) and `client`
  `{ version, build, date, toc }`.
- A per-install `installId` (8 hex chars) is generated once per SavedVariables
  file so later fight IDs can be unique across machines.

See [`docs/SCHEMA.md`](docs/SCHEMA.md).

**Fight IDs**

- New keys: `hf1-<installId>-<unixStart>-<sessionId>-<seq>` (PCRE
  `^hf1-[0-9a-f]{8}-\d+-\d+-\d+$`). Unique across two machines via `installId`.
- `seq` is always present so uniqueness is not an optional suffix on
  `{unix}-{sid}` (the form the wow-data importer previously rejected).
- Existing `{unix}-{sid}` and `{unix}-{sid}-{n}` keys are never rewritten;
  `ns.ParseFightKey` accepts all three. Combined importer PCRE is in SCHEMA.md.

**Freshness and quests**

- Each snapshot section has its own `observedAt` + `status` (`ok` /
  `unavailable` / `stale`). Money/gear patches no longer make talents or
  quests look fresh.
- Quest log states: `accepted`, `in_progress`, `ready`, `failed`, `completed`
  (history), `abandoned`, `unknown`. `C_QuestLog.GetInfo` has no `isComplete`
  on Forever; that missing field is no longer treated as false.
- Bags (backpack + equipped bags, occupied slots only) as their own section.

**Hunter pet**

- Permanent hunter pet: name, family, level, abilities with ranks, Growl
  autocast, happiness, training points, XP. Temporary summons (`UnitExists`
  without `HasPetUI`) are stored as `kind = "temporary"`, not mixed with the
  stable pet. Missing API values are `"unknown"`, never guessed. Classic-era
  APIs only (`HasPetUI`, `GetPetHappiness`, `GetPetTrainingPoints`,
  `GetPetActionInfo`, `HasPetSpells` / `C_SpellBook.HasPetSpells`).

**Fight context, professions, Matty Hunter**

- Each fight references pre-pull gear/talent/pet hashes (`contextBlobs`), not
  a full copy. Context ids are an O(1) copy at combat start (no snapshot APIs).
- Profession events: skill-ups, OOC gathering/fishing/craft casts and the
  following loot/tradeskill line.
- Read-only observe of Matty7500Hunter `lastDecision` / scores when the
  global exists. MH is never modified. If it is not loaded or not readable,
  the fight record says why.

**Self-test, smaller saves, release packaging**

- `/hello selftest` lists the client events the addon asked for that this
  client does not know or has not fired yet, the APIs it did not find, and the
  snapshot sections that could not be read. The result is also saved
  (`HelloForeverDB.selftest`). Run it after playing a few minutes on a new
  client build.
- Smaller SavedVariables: fight records no longer repeat the client table
  (`gameBuild` stays; the rest is on the root), and skill rows keep `id` and
  `cat` instead of the whole 16-field API table (`_raw`).
- `tools/package.py` checks that the TOC version, `VERSION_FALLBACK`,
  `SOURCE_REVISION` and this changelog agree, runs the tests and builds a zip
  with SHA-256 sums.
- `plan/` lists what still needs the game client or more GitHub access:
  in-game verification, the CI workflow, release tags, the Matty Hunter contract.

**Review fixes before release**

- Quests: `abandoned` is recorded only when the client says the quest was not
  turned in, and an entry goes away again if the quest returns to the log or
  its completed flag arrives late. Finished objectives are counted instead of
  summing kill counts, so `10/10` plus an unfinished objective is no longer
  `ready`. The turned-in history (thousands of ids) is copied on a full
  snapshot or when a quest leaves the log, not on every `QUEST_LOG_UPDATE`;
  `completedTotal` shows when the list was capped (cap raised to 4000).
- Fight context is stamped per session, so a fight read late (chain pull,
  secret values, `/reload`) keeps the gear / talents / pet it was pulled with.
  Talent changes now refresh the talents hash between snapshots.
- Profession casts match skill names exactly. A substring match filed class
  spells such as Arcane Shot under the `Arcane` skill line.
- Matty Hunter is read with `rawget` under `pcall`: its metamethods never run
  and a surprise in its tables cannot break the combat-start handler. The
  "not installed" stamp on each fight is two fields instead of a paragraph.
- `installId` no longer reseeds the RNG other addons share, and no longer
  needs `math.randomseed` to exist.
- Freshness: a section that was never read has no `observedAt`; logout and
  time-played values carried over from an earlier read are `stale`, not `ok`.
- Skill-up chat lines parse through the client's `SKILL_RANK_UP` format, and
  the same rank is not logged twice.
- Bags refresh on `BAG_UPDATE_DELAYED` where the client has it.
- A later revision of a fight keeps the start its key was made with. After
  the session list had been empty for a moment, 0.5.0 re-estimated the start,
  so the key and the record disagreed.
- A repeatable quest (never flagged completed by the client) handed in this
  session is recognised from `QUEST_TURNED_IN` and not listed as abandoned.
- A session the meter announces just before `PLAYER_REGEN_DISABLED` gets that
  pull's Matty Hunter sample, and a different fight found on a recycled session
  id gets the latest pull's context (marked `approx`) instead of inheriting the
  earlier fight's.

## HelloForever 0.5.0 — 2026-11-09

**New**

- XP panel redesign: XP bar with rested overlay, XP/hour, time to level, last fight;
  gold/hour at the level cap; tooltip with session totals; lock, scale, hide; right-click menu.
- Fight history window (`/hello ui`): newest 50 fights with a per-fight breakdown.
- Session counters (XP, gold, fights, best fight, deaths) and a level-up log (`/hello levels`).
- Optional one-line chat announcement per fight (`/hello announce on`).
- `/hello budget <MB>`, `/hello purge <days>` (inside the 7-day keep window it asks for
  `force`), `/hello fights <n>`, `/hello help`.
- Addon compartment entry and addon-list icon.

**Fixed**

- Equipment, money and zone changes arriving within 10 s of the previous one were
  dropped; a second gear swap could stay out of the snapshot until relog.
- A fight reusing a session id (same name) could overwrite or be skipped as the earlier
  fight; it now gets its own record when the player's own totals went down. A session
  that merely got shorter is treated as a correction of the same fight.
- A session list that was empty for a moment made every fight look new when it came back.
- After a relog that restarted numbering at the same id, a fight against the same mob
  could be skipped or stored over the previous login's record.
- A re-read in which one meter type failed replaced the good record with the error.
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
- Plan revision 2: reviewed against the 1.60.1 UI source; open decisions, in-game
  checks and the Matty7500Hunter contract checklist added.
- Plan revision 3: Matty7500Hunter v.41 source read locally. MH already glows the
  action-bar button to press, so the plan now starts with a trial of MH alone
  (phase v0.0, no code); MH contract filled in; follow log proposed for HelloForever.
- Plan revision 4: MH is now v.42 and has run on this client; the phase v0.0 trial
  is under way. The MH names HelloForever 0.6.0 reads are confirmed in the MH source
  (`docs/SCHEMA.md`); the in-game confirmation is in `plan/04-matty-hunter-contract.md`.
