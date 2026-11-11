# HelloAim — adaptive secure-button strip

> **Status: proposal, revision 4 (MH source read locally; trial of MH alone
> under way since 2026-11-10). Not
> implemented and not yet approved for implementation.**  
> No runnable addon code ships in this folder yet. This document is the design
> brief only. Do not treat filenames under "Suggested layout" as present files.
> Five owner decisions are open — see [Open decisions](#open-decisions-from-the-review).
> The first one is whether HelloAim needs to be written at all: read
> [What MH already does](#what-mh-already-does-found-in-revision-3) first.

**Client:** World of Warcraft Forever build **1.60.1** / TOC **16001**  
**Date:** 2026-11-11 (Europe/London)

## How far this plan has been checked

- **Client behaviour** was checked against Blizzard's own UI source for this
  build (Gethe/wow-ui-source, `forever` branch, 1.60.1 build 70862). File and
  line references below are to that tree. Where a reference is given, the
  statement was read in the source; it was **not** tried in the game.
- **Matty7500Hunter (MH) internals** were read in the installed copy on the
  development machine: **MH v.41**, TOC 16001, 17 400 lines. Statements about
  MH below come from that source; they were **not** tried in the game. See
  [MH contract](#mh-contract-read-from-mh-v41).
- **MH v.42** replaced v.41 on 2026-11-10. Re-checked in v.42: the global, the
  SavedVariables name, `version`, and that `lastDecision` is still written in
  one place by the ticker and read by MH's own statistics. The rest of the
  contract table was **not** re-read; treat it as v.41.
- **MH now runs on this client.** `Matty7500HunterDB` exists since 2026-11-10
  with fight history, `showKeybinds` on and a dragged main icon, so the
  phase v0.0 trial has started. Its result (checks a–d) is not written down
  yet, and that result is what decides whether HelloAim is written.
- **Local key bindings** (the account binding caches) hold no custom action-bar
  bindings. The main bar uses the default keys `1`–`=`; the other bars are
  unbound.
- Anything that still needs the real client is listed under
  [In-game checks](#in-game-checks).

## Decided (James)

| Topic | Decision |
|-------|----------|
| Addon name | **HelloAim** |
| Strip position | Just **above the default action bar** |
| Input | **Keyboard** — show keybind labels |
| Keybind labels | Prefer **Bindings.xml** custom bindings; **fallback** to the existing action-bar key bound to the same spell |
| MH suggestion icon | **Hide** Matty7500Hunter / MHP-Hunter-Helper's own suggestion icon while HelloAim is active |
| Packaging | Separate thin addon (not a module inside HelloForever) |

## What MH already does (found in revision 3)

Revisions 1 and 2 were written without the MH source. MH v.41 already ships
most of what v0.1 was going to build.

| HelloAim v0.1 item | MH v.41 | Gap that is left |
|--------------------|---------|------------------|
| Highlight the button to press | **Action glow** (`actionGlow`, on by default). A pulsing border on the player's **own action-bar button** for the recommended spell. It is a non-secure frame parented to `UIParent` and only anchored to the button — the same overlay design this plan chose. It supports the Blizzard bars and Bartender4, Dominos and ElvUI. | Finds a spell placed directly on a bar, not one inside a macro. No dimming of the other buttons. Off whenever the MH HUD is hidden by MH's own visibility rule. |
| Keybind labels | `/mh keys` (`showKeybinds`, off by default) writes the action-bar key on the main, queue and utility icons. It resolves macros through `GetMacroSpell`. The action bar itself already shows its keys. | None for spells that are on a bar. |
| A strip in one fixed place | `/mh layout strip` (default): main icon, next 1–3 predicted spells, swing bar, cooldown bar. `/mh unlock` lets the player drag it, for example to just above the action bar. | It shows *what comes next*, not a fixed set of buttons in fixed slots. |
| Banners for pseudo-keys | The main icon shows WAIT, HOLD, BACK, IN, STOP, CC with a tag and an edge colour. | Position only (solved by dragging the HUD). |
| Follow log | `Stats`: per fight, casts, followed, skipped per key, clipped Auto Shots, mana at end, grade. `/mh stats`, `/mh history`; last 20 fights are saved. | No timestamp, so rows cannot be joined to HelloForever fights. The comparison is made when a cast **succeeds**, which this plan already identified as wrong for cast-time spells (see [Follow log](#follow-log)). |
| Pet button, spells that are on no bar | Nothing. MH never creates a clickable button. | Whole item. This is the only part that needs secure frames. |

So the goal ("the highlighted button is the one to press") can be tried today
with **no code**: put the rotation spells on one bar, keep action glow on, and
drag the MH HUD next to that bar. `MultiBarBottomLeft` sits directly above the
main bar, which is the position James chose for the strip.

## Open decisions (from the review)

These need an answer from James before v0.1 is written. Each has a
recommendation, but none is decided.

| # | Question | Why it is open | Recommendation |
|---|----------|----------------|----------------|
| 0 | Does HelloAim need to be written? | MH's action glow already highlights the real button (see the table above). Nobody has tried it on this client. | **Try MH alone first** ([phase v0.0](#phases)). Write HelloAim only for a gap that the trial shows. Each gap in the table above maps to one small piece; none needs the whole of v0.1. |
| 1 | Where exactly does the strip sit? | "Just above the default action bar" is already occupied. Forever's Edit Mode stacks `MultiBarBottomRight`, `MultiBarBottomLeft`, `StanceBar` and `PetActionBar` there (`Blizzard_EditMode/Camelot/EditModeUtil.lua:5-24`), and a hunter with a pet out always has the pet bar. | Default position above the **whole** bottom stack (measured out of combat from the top of whichever of those bars is shown), saved position once the player drags it. |
| 2 | Do bindings belong to a slot or to a spell? | `Bindings.xml` is static, but v0.2 adds and reorders spells. If a binding belongs to slot N, the same key ends up casting a different spell after a reorder. | Bind **per spell**: one button per spell key, e.g. `CLICK HelloAimButton_SERPENT_STING:LeftButton`. Order is display only. |
| 3 | Does v0.1 need secure buttons at all? | Input is keyboard only. In fallback mode (label taken from the action bar) the player presses the action-bar key and the strip button is never clicked. One key holds one binding, so binding a key to the strip takes it away from the action bar. | Ship v0.1 as a **display-only** strip (no secure frames, so no lockdown or taint risk). Add secure buttons in v0.2 for spells that are not on any bar. Note: a display-only strip is what MH's action glow already gives on the player's own bar, so this answer makes decision 0 more likely to be "no". |
| 4 | Where does the follow log live? | The log needs MH's decision at the moment a cast is sent, and the fight it belongs to. HelloForever already owns fight boundaries and the saved fight record. | Put it in **HelloForever** as a small optional section of the fight record (read `Matty7500Hunter.lastDecision` on `UNIT_SPELLCAST_SENT`). Then no join by timestamp is needed and v0.3 does not depend on HelloAim existing. |

Decisions 1–3 only matter if decision 0 is "yes, write a strip".

If decision 3 goes the other way (secure buttons in v0.1), every rule under
[Secure strip rules](#secure-strip-rules) applies from the first version.

## Goal

A glanceable fixed strip where eye and hand stay on one place: the highlighted
button is the one to press. Same legal model as MHP-Hunter-Helper (suggest
only); better ergonomics than a floating icon plus hunting for the real bind.

### Non-goals

- No casting for the player, no external key spam, no combat-time `SetAttribute`
  on secure buttons.
- No forking MH's rotation engine into our tree (call it; do not copy `Rotations/`).
- No `COMBAT_LOG_EVENT_UNFILTERED` dependency (Forever never delivers CLEU to addons).
- No deploy until this plan and a later code review are approved.

## Hard limits (Forever + Blizzard lockdown)

While `InCombatLockdown()` is true, HelloAim **must not**:

1. Change spell / macro / item attributes on secure buttons (`SetAttribute`).
2. Create, destroy, show, hide, reparent, or move **secure** frames.
3. Call `SetBinding` / clear bindings (binding changes are lockdown-gated).
4. Automate presses or cast without a player click / keybind.

Allowed in combat on a **separate non-secure overlay** (parented to `UIParent`,
`EnableMouse(false)` so clicks pass through):

- Highlight / dim textures, scale, colour, cooldown swipe on the overlay layer,
  centre banners (`STEP BACK`, `WAIT`, …).

Also Forever-specific:

- Meter / unit values may be **secret** in combat — treat unknown as unknown;
  never invent casts from secret data.
- **No CLEU** for addons on Forever.
- Details' segment writer is disabled on Forever (`do return end` in addSegment);
  HelloAim does not depend on Details.

### What is and is not secret (checked in the API documentation)

| Data | In combat | Consequence |
|------|-----------|-------------|
| `C_Spell.GetSpellCooldown` | Secret (`SecretWhenCooldownsRestricted`) | No arithmetic or comparison on cooldown numbers; no "ready in 1.2 s" text computed by us. |
| `Cooldown:SetCooldown(start, duration)` | Does not accept secret arguments from addon code (`SecretArguments = "AllowedWhenUntainted"`) | Do not feed it values from `GetSpellCooldown` in combat. |
| `C_Spell.GetSpellCooldownDuration` → `Cooldown:SetCooldownFromDurationObject` | Returns a duration object, not a number | Intended path for the cooldown swipe. **Confirm in game.** |
| `C_Spell.IsSpellUsable`, `C_Spell.IsSpellInRange` | Not marked secret | `showOOM` and `showRange` are feasible. |
| `UNIT_SPELLCAST_*` for the player and pet | Not secret (`SecretWhenUnitSpellCastRestricted` only applies to other units) | The follow log can read the player's own spell IDs. |
| Unit auras | Secret in combat (`SecretWhenUnitAuraRestricted`) | We never read auras; MH's view of debuffs such as Serpent Sting may be degraded (risk 1). |

## Brain: reuse MH, do not fork

Matty7500Hunter exposes `_G.Matty7500Hunter`. Cheapest path for v0.1:

```lua
local MH = Matty7500Hunter
local dec = MH and MH.lastDecision
-- map dec.key / dec.pending → strip slot; paint overlay only
```

- MH ticks every 0.05 s in combat and every 0.2 s out of combat (`Events.lua`).
  **Do not** call `MH.State:Build()` / `MH.Rotation:Recommend` ourselves: it
  would double the CPU cost, and `Recommend` keeps debounce state that a second
  caller would disturb.
- If MH is missing: show the strip with **no** highlight (optional tiny local
  fallback priority later — never ship a copy of MH rule tables).
- MH's licence (`LICENSE.txt`, "All Rights Reserved") forbids copying, changing
  or adapting any part of it, "including as part of another addon". Reading the
  live global at runtime copies nothing. No MH code, rule table or spell table
  goes into this repository. Use `OptionalDeps: Matty7500Hunter`.
- `C_AssistedCombat` exists in the API, but Blizzard's own
  `AssistedCombatManager.lua` is only loaded for the mainline game type
  (`Blizzard_ActionBar.toc`), so do not assume it has data on Forever.
  `/dump C_AssistedCombat.IsAvailable()` settles whether it could serve as the
  fallback brain.

Pseudo-keys have no cast button — banner / dim strip; do not invent a fake
secure cast. Do not hard-code the list: a key is a pseudo-key when
`MH.Pseudo[key]` exists and `MH.HunterSpells[key]` does not.

### MH contract (read from MH v.41)

Read in the source on 2026-11-09. Not yet observed in the game; one `/dump
Matty7500Hunter.lastDecision` in combat and one out of combat confirms it.

| Question | Answer in MH v.41 |
|----------|-------------------|
| Version | `Matty7500Hunter.version == "v.41"`; also `MH.versions` (engine and per-spec rule versions). |
| When is `lastDecision` written? | In MH's ticker, on hunters only, after `PLAYER_LOGIN` has finished, and only when the engine returned a decision. If the engine throws, MH swallows the error and the old table stays. |
| Does it update out of combat? | **Yes.** The ticker always runs (0.2 s out of combat, 0.05 s in combat or after an urgent event). It does not depend on the HUD being visible. With no attackable target the key is `IDLE`. |
| Replaced or mutated? | A new table on most ticks. When the key changes, MH first returns the **previous** table once more (debounce; the new key must win twice). So a key change shows about one tick late. A finished or interrupted cast skips the debounce. |
| Timestamp | `dec.state.time` — `GetTime()` when the state was built. A decision older than about 0.5 s is stale. |
| Fields | `key` (string); `reason` (English text); `pending` (the spell key to press after a `WAIT`); `wait` (seconds); `window`; `index`; `list`; `outOfRange` (true when `key` is a real spell but the target is too far); `flags` = `{ lowMana, range, move, overkill }`, each a spell key; `rejected` (array of `{ key, why }`); `profile`; `phase` (`NOW`, `NEXT` or `QUEUE` — the last two mean "press after the current cast"); `castLock`; `state` and `baseState` (the full state snapshot). |
| Spell to highlight | `dec.pending or dec.key`, the same expression MH uses for its action glow. |
| Kinds of key | (a) hunter spell: `MH.HunterSpells[key]`; (b) pet ability: `MH.PetUtility:IsKey(key)`; (c) pseudo: `MH.Pseudo[key]`. Pseudo-keys in v.41: `IDLE`, `HOLD_CC`, `AUTO`, `WAIT`, `SWING`, `STEP_BACK`, `STEP_IN`, `MOVE`, `DRINK`, `EAT`, `POTION`. |
| Key → spell ID | `MH.Known[key]` = `{ id = highest known rank, rank, name, ids = all known ranks }`, rebuilt on `SPELLS_CHANGED`. Reverse lookup: `MH.Spells:KeyFromSpell(spellID)`. HelloAim needs no spell table of its own. |
| Key → keybind text | `MH.Widgets:KeyFor(key)` returns the short key text (cached; cleared on `UPDATE_BINDINGS` and `ACTIONBAR_SLOT_CHANGED`). |
| HUD frame names | `Matty7500Hunter_main`, `_queue`, `_swing`, `_cds`, `_utility`, `_debug`; also in `MH.Widgets.elements`. |
| Slash | `/mh style hybrid\|auto\|ranged`, `/mh keys`, `/mh layout strip\|stack`, `/mh unlock`, `/mh stats`, `/mh history`. |
| Licence | All Rights Reserved; see above. |

**Second channel.** `lastDecision` is the main icon only. Utility advice comes
from a separate call, `MH.Common.Utility(state)`, which drives the utility
icon: Wing Clip and Concussive Shot (slow, runner, kite), Feign Death, potion,
drink, eat, aspects, traps. MH does not store its result anywhere. Two of the
eight default strip keys (`WING_CLIP`, `CONCUSSIVE_SHOT`) would therefore
**never** light up from `lastDecision`. If the strip must show them, HelloAim
calls `MH.Common.Utility(dec.state)` itself at overlay rate (≤ 10 Hz) and
treats the first return value as a second, differently coloured highlight.

Rules for reading it:

- **Staleness.** No highlight when `GetTime() - dec.state.time > 0.5`. This
  covers an engine error and a disabled MH; no clearing on
  `PLAYER_REGEN_ENABLED` is needed, because MH keeps the decision current out
  of combat.
- **Drift.** Validate `type(dec) == "table"`, `type(dec.key) == "string"` and
  `type(dec.state) == "table"`. A key that is none of the three kinds above
  means no highlight and one chat warning per session that names the MH
  version; it never guesses a button.
- **Read only.** HelloAim reads the global; it does not write to MH's tables or
  saved settings.
- **Internal names.** Everything except the global itself is MH's private
  structure and can change in any release. Check each name with `type()` before
  use and record the MH version in `/aim debug`.

## UI architecture

1. **Strip** — one button per spell key. Whether these are secure buttons in
   v0.1 is open decision 3.
2. **Insecure overlay** — highlight, dim and banners. Parented to `UIParent`
   and anchored to the strip, not a child of a secure button.
3. **Keybind labels** — custom binding first, action-bar key second, blank
   with an "unbound" tooltip last. Details below.
4. **Hide MH icon** — at runtime only, by **alpha**, not by `Hide`. MH calls
   `SetShown` on every HUD frame on every tick, so a `Hide` lasts 0.05 s. MH
   sets alpha only when it lays the HUD out (`MH.Widgets:Place`). So: set alpha
   0 on the frames in `MH.Widgets.elements` (not `debug`) after `PLAYER_LOGIN`,
   and again after each layout with `hooksecurefunc(MH.Widgets, "Place", …)`.
   Do **not** use MH's own switches: `hiddenByKey` and `showOOC` are saved
   settings (HelloAim could not restore them if it were removed), and both
   also turn MH's action glow off. With an alpha hide the icon comes back by
   itself whenever HelloAim is not loaded. Hardcore alarms are separate frames
   and stay visible. One more piece: the neon / card / glass themes draw a
   background card (`MH.Skin.card`) whose alpha MH sets again in
   `MH.Skin:FitCard` while the main icon is shown; hook that function the same
   way. This is two hooks into MH's private UI code, so it is the part of
   HelloAim most likely to break on an MH update — an in-game check, and a
   reason to prefer moving the HUD over hiding it.

### Position

- The main bar frame on Forever is `MainActionBar`; there is no `MainMenuBar`
  (`Blizzard_ActionBar/Mainline/MainActionBar.xml:29`).
- Default position and saved position are applied out of combat only.
- See open decision 1 for where the default sits.

### Keybind labels

- Custom binding: `GetBindingKey("CLICK <buttonName>:LeftButton")`. Blizzard's
  own action buttons look their hotkey up the same way
  (`Blizzard_ActionBar/Shared/ActionButton.lua:498-499`).
- Fallback: `C_ActionBar.FindSpellActionButtons(baseSpellID)` gives the slots
  holding the spell (it expects the base spell, not an override); map each slot
  to its binding command (`ACTIONBUTTON1`…, `MULTIACTIONBAR1BUTTON1`…, names as
  in `Blizzard_FrameXML/Bindings_Camelot.xml`) and read `GetBindingKey`.
- A spell that only sits on the bar inside a macro is not found by that call.
  Resolving macros needs `GetActionInfo` + `GetMacroSpell`.
- **Cheaper:** when MH is loaded, `MH.Widgets:KeyFor(key)` already does this
  whole fallback, macros included. Use it and keep our own lookup only for the
  case where MH is missing — or drop that case, since without MH there is no
  highlight either.
- Refresh labels on `UPDATE_BINDINGS` and `ACTIONBAR_SLOT_CHANGED`.
- `Bindings.xml` is picked up from the addon folder automatically; it is not
  listed in the `.toc`.
- Assumes the default action bars. Bar addons that use their own buttons and
  bindings are out of scope for the fallback.

### Secure strip rules

Apply from whichever version first ships secure buttons.

- **Click registration.** `SecureActionButton_OnClick` fires on key down or on
  key up depending on the `ActionButtonUseKeyDown` CVar
  (`Blizzard_FrameXML/SecureTemplates.lua:792-811`), and
  `SecureActionButtonTemplate` does not register for key-down clicks itself.
  Every button calls `RegisterForClicks("AnyDown", "AnyUp")`. Without it, a
  bound key does nothing when the CVar is on.
- **Creation.** All buttons are created at file load with fixed global names
  (a `CLICK` binding needs the frame to exist). None is created later.
- **Attributes, show/hide, position.** Out of combat only
  (`PLAYER_LOGIN`, `PLAYER_REGEN_ENABLED`, `SPELLS_CHANGED`), queued if a change
  arrives mid-combat.
- **Dragging.** Only out of combat; stop any drag on `PLAYER_REGEN_DISABLED`.
- **Spell attribute.** `type="spell"` accepts a spell ID or a name
  (`SecureTemplates.lua:396-404`). Which of the two keeps casting the right
  rank after training is an in-game check.
- **Self-test.** Register `ADDON_ACTION_BLOCKED` and `ADDON_ACTION_FORBIDDEN`
  and show the last one in `/aim debug`.

### Strip contents

Default strip keys (hide if unknown), Hunter-oriented baseline:

| # | Key | Notes |
|---|-----|-------|
| 1 | `HUNTERS_MARK` | pre-pull / long TTD |
| 2 | `SERPENT_STING` | maintain |
| 3 | `AIMED_SHOT` | shared CD with Multi |
| 4 | `ARCANE_SHOT` | filler |
| 5 | `CONCUSSIVE_SHOT` | utility — second channel only, never in `lastDecision` |
| 6 | `RAPTOR_STRIKE` | melee / deadzone |
| 7 | `WING_CLIP` | melee slow — second channel only, never in `lastDecision` |
| 8 | `PET` | Mend / Call / Revive in one button — see below |

**Pet button.** A single macro-type button covers all three cases and keeps
working in combat, so no attribute swap is needed:

```text
/cast [@pet,dead] Revive Pet; [nopet] Call Pet; Mend Pet
```

`macrotext` is still handled by the secure template
(`SecureTemplates.lua:450-462`). Spell names must come from
`C_Spell.GetSpellName` so the macro works on non-English clients. Whether the
conditionals behave this way on Forever is an in-game check; if they do not,
fall back to the earlier options (attribute swap out of combat only, or two
fixed buttons). As this is a macro, it only exists once secure buttons do.

### Scope

- Hunter only. On any other class HelloAim loads, creates no frames and
  registers only its slash command.

## Perf budget

| Path | Rate | Work |
|------|------|------|
| Brain | Consume MH's tick | Read `lastDecision` only |
| Overlay, in combat | ≤ **10 Hz** | Paint only when key/flags change |
| Overlay, out of combat | **5 Hz** poll, matching MH's 0.2 s out-of-combat tick | MH gives out-of-combat decisions (pre-pull Hunter's Mark), so events alone would miss them; paint only on change |
| Secure rebuild | OOC only | Login / regen / spells / level |

No CLEU. Optional `/aim rate slow` (5 Hz) if FPS drops.

## SavedVariables (draft) `HelloAimDB`

Position, scale and key order belong to a character, so settings are stored
per character (keyed by `Name-Realm`, the same way HelloForever does it).

```text
version, addonVersion
characters["Name-Realm"] = {
  pos, scale, locked
  keys = ordered known strip keys
  showKeybinds, showOOM, showRange
  rate = "normal"|"slow"
  hideMHIcon = true
  follow = { { start, dur, casts, followed, offStrip, topSkipped, mh }, ... }  -- capped ~50 rows
}
```

### Follow log

One summary row per fight, pushed on combat end. Never one row per overlay
frame. Where it lives is open decision 4; the definition below is the same in
either addon.

**What MH already records.** `MH.Stats` counts `casts`, `followed` and
`skipped[key]` per fight, and saves `{ grade, pct, casts, dur }` for the last
20 fights in `Matty7500HunterDB.history`. `MH.Stats.last` holds the full last
fight. Two limits make it unfit for v0.3 as it is: no timestamp, and the
comparison runs on `UNIT_SPELLCAST_SUCCEEDED`. While a cast is in progress MH
already shows the spell for *after* the cast (`phase` is `NEXT` or `QUEUE`),
so a correctly followed Aimed Shot or Multi-Shot is most likely counted as
not followed (read in the source; confirm in game). The MH grade would then
be biased low for Marksmanship; do not use it as the follow rate. It is still
a free cross-check for instant-cast fights.

- **When to compare.** Take the key shown at `UNIT_SPELLCAST_SENT`, not at
  `UNIT_SPELLCAST_SUCCEEDED`. For a spell with a cast time (Aimed Shot) the
  recommendation has moved on by the time the cast completes, so comparing at
  success undercounts. The wanted key is `dec.pending or dec.key`, whatever
  the `phase`.
- **Grace.** A cast counts as followed if its key was shown at any point in
  the 0.5 s before it was sent.
- **Spell matching.** Map the cast to a key with
  `MH.Spells:KeyFromSpell(spellID)`; it knows every rank. No spell table of our
  own.
- **Denominator.** `casts` counts only casts of spells that are on the strip.
  Other casts (traps, Feign Death, …) go to `offStrip`. Pseudo-keys (`WAIT`,
  `STEP_BACK`, …) are not counted either way.
- **Joining with HelloForever.** If the log lives in HelloForever (decision 4)
  the counters are fields of the fight record and there is nothing to join.
  If it lives in HelloAim, `start` (epoch seconds) and `dur` let the offline
  pipeline match a row to the HelloForever fight record that overlaps it.
  `mh` is the MH version the row was recorded with.

## Slash (draft)

`/aim`, `/aim lock|unlock`, `/aim reset`, `/aim keys`, `/aim debug`,
`/aim style` (hint to `/mh style hybrid|auto|ranged`).

## Suggested layout (future implementation — not in repo yet)

```text
HelloAim/
  HelloAim.toc          ## Interface: 16001, OptionalDeps: Matty7500Hunter
  Bindings.xml          -- loaded automatically; not listed in the .toc
  Core.lua
  SpellSet.lua
  SecureBar.lua         -- OOC only attribute changes
  Overlay.lua           -- combat-safe highlight
  Brain.lua             -- read Matty7500Hunter.lastDecision
  FollowLog.lua
  Options.lua
```

## Tests

"Harness green" means a mock-client run in the style of
`tests/fights_harness_v4.lua`, reusing its strict widget mocks (an unknown
method on a widget throws). It covers:

- **Lockdown.** A mock flag for combat lockdown; while it is set, `SetAttribute`,
  `Show`, `Hide`, `SetPoint`, `SetParent` and `StartMoving` on a frame marked
  protected throw. A scripted fight (enter combat, spell learnt mid-fight,
  leave combat) must pass with no throw, and the queued change must be applied
  after combat.
- **Brain.** Known key, unknown key, missing MH, malformed `lastDecision`,
  stale decision after combat.
- **Labels.** Custom binding, action-bar fallback, unbound.
- **Follow log.** Instant cast, cast-time spell, off-strip cast, pseudo-key,
  row cap.

The harness cannot show taint or real secret-value behaviour; those are
in-game checks.

## In-game checks

Trial of MH alone (phase v0.0 — no HelloAim code):

a. Enable MH on the hunter. It loads with no error and no "blocked action"
   pop-up; `/mh check` is clean.
b. Put the rotation spells on one bar. In a fight, the action glow lands on
   the right button and is easy to see at a glance.
c. `/mh keys`, then `/mh unlock` and drag the HUD to just above the action
   bar. Is that enough to stop "hunting for the bind"?
d. Write down what is still missing. That list is the scope of HelloAim.

Before coding:

1. `/dump Matty7500Hunter.lastDecision.key, Matty7500Hunter.lastDecision.state.time`
   in combat, out of combat with a target, and with no target — confirms the
   [MH contract](#mh-contract-read-from-mh-v41).
2. `/dump C_AssistedCombat.IsAvailable()`.
3. `/mh stats` after a fight with several Aimed Shots: is a followed Aimed
   Shot counted as followed? (Expected: no.)

With the first build:

4. Cooldown swipe from `GetSpellCooldownDuration` +
   `SetCooldownFromDurationObject` works in combat without an error.
5. `IsSpellUsable` / `IsSpellInRange` return plain booleans in combat.
6. A bound key casts with `ActionButtonUseKeyDown` both on and off
   (secure buttons only).
7. The pet macro revives, calls and mends in the right situations
   (secure buttons only).
8. `/reload` during combat: the strip comes back, nothing is blocked.
9. `/console taintLog 1`, one play session, no HelloAim entries; `/aim debug`
   shows no blocked action.
10. The MH HUD (icons and theme card) stays invisible through a relayout
    (`/mh scale 1.1`), a `/reload`, and a fight (only if the HUD is hidden).

## Phases

| Phase | Deliverable | Exit criteria |
|-------|-------------|----------------|
| **v0.0** | **No HelloAim code.** MH alone: action glow on, rotation spells on one bar, `/mh keys`, HUD dragged above the bar. Optional and separate: follow counters in HelloForever (decision 4). | Checks a–d done; James lists what is still missing, or closes HelloAim as not needed |
| **v0.1** | Only the gaps from v0.0. Candidates, each independent: dimming of non-recommended buttons; second-channel highlight (Wing Clip / Concussive); a fixed display strip with labels; MH HUD hidden by alpha. Brain = `lastDecision`; harness green | Can quest pressing only the keys shown; in-game checks pass; no taint; CPU OK |
| **v0.2** | Secure buttons for what no bar holds, incl. pet button; OOC auto-add on `SPELLS_CHANGED` / level-up; reorder profiles | New spells appear after trainer without manual config; a reorder never changes what a bound key casts |
| **v0.3** | Tune layout and visuals using HelloForever fight exports + follow counters | Follow rate reported next to own DPS from HelloForever for the same fights; a change counts as an improvement only if DPS does not drop, or the skips are documented as intentional |

Follow rate on its own measures how closely the player obeys the hint, not
whether the hint was good, which is why v0.3 pairs it with damage. MH's
rotation itself is not ours to tune.

Each phase: review → owner OK → deploy → test → only then next phase.

## Risks

1. Secret values degrade MH mid-fight (auras are secret in combat) — the
   highlight mirrors those mistakes. MH is built for this: every read goes
   through a wrapper that turns a secret value into "unknown", rules are
   tri-state, and cooldowns and DoTs also run on MH's own timers started when
   a cast succeeds. How well that works on this client is unobserved.
2. Only the global `Matty7500Hunter` is meant to be seen from outside. Every
   field and module this plan reads (`lastDecision`, `Known`, `Spells`,
   `Widgets`, `Common.Utility`, `Skin`) is MH's private structure, read in
   v.41. MH releases often (41 versions). Guard every access and detect drift.
3. Wrong overlay parenting → `ADDON_ACTION_BLOCKED`.
4. Extra ticker on hang-prone hosts — hard-cap 10 Hz.
5. Pet button depends on macro conditionals behaving as on other clients.
6. Cooldown display depends on the duration-object path working for addon code.
   Fallback: `MH.Cooldowns:SweepFor(key)` returns plain start / duration
   numbers (MH's own timer when the client hides the real one).
7. Default position depends on Edit Mode's bar stack, which the player can
   rearrange — always fall back to the saved or a fixed position.
8. **ToS:** still player-driven; never automate presses.

## Terms of Use

HelloAim is assistive UI only. Every ability is a player key press or click.
No input injection, no auto-cast, no combat-time rebinding of what a key does.

## Revision history

| Rev | Date | Change |
|-----|------|--------|
| 1 | 2026-11-09 | First proposal. |
| 2 | 2026-11-09 | Review against the 1.60.1 UI source. Added: verification status, open decisions, secret-value table, MH contract checklist, click-registration rule, runtime-only hiding of the MH icon, position facts, binding lookup details, single pet macro button, per-character settings, follow-log definition, test definition, in-game checklist. Phase exit criteria tightened. |
| 3 | 2026-11-09 | MH v.41 source read on the development machine. Added: what MH already does (action glow, `/mh keys`, strip layout, Stats); decision 0 (is HelloAim needed) and decision 4 (follow log in HelloForever); phase v0.0 (trial with no code). MH contract table filled in. New facts: second advice channel (`Common.Utility`) for Wing Clip / Concussive Shot; MH updates out of combat; staleness by `state.time`; HUD must be hidden by alpha, not `Hide`; MH's own follow count compares at cast success; licence text; MH has never run on this client. |
| 4 | 2026-11-11 | MH is now v.42 and has run on this client (saved settings and fight history exist); the trial of phase v0.0 is under way. Core names re-checked in v.42. HelloForever 0.6.0 records `lastDecision` with each fight; `plan/04-matty-hunter-contract.md` lists the in-game confirmation still owed. |
