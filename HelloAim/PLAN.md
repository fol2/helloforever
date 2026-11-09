# HelloAim — adaptive secure-button strip

> **Status: proposal, revision 2 (reviewed 2026-11-09). Not implemented and not
> yet approved for implementation.**  
> No runnable addon code ships in this folder yet. This document is the design
> brief only. Do not treat filenames under "Suggested layout" as present files.
> Three owner decisions are still open — see [Open decisions](#open-decisions-from-the-review).

**Client:** World of Warcraft Forever build **1.60.1** / TOC **16001**  
**Date:** 2026-11-09 (Europe/London)

## How far this plan has been checked

- **Client behaviour** was checked against Blizzard's own UI source for this
  build (Gethe/wow-ui-source, `forever` branch, 1.60.1 build 70862). File and
  line references below are to that tree. Where a reference is given, the
  statement was read in the source; it was **not** tried in the game.
- **Matty7500Hunter (MH) internals** could not be checked. The addon is
  distributed as MHP-Hunter-Helper on CurseForge and its source was not
  available to the reviewer. Everything this plan says about `lastDecision`,
  its fields, the tick rate, `/mh style` and the licence is unconfirmed — see
  [MH contract](#mh-contract-to-confirm-before-coding).
- Anything that still needs the real client is listed under
  [In-game checks](#in-game-checks-before-and-during-v01).

## Decided (James)

| Topic | Decision |
|-------|----------|
| Addon name | **HelloAim** |
| Strip position | Just **above the default action bar** |
| Input | **Keyboard** — show keybind labels |
| Keybind labels | Prefer **Bindings.xml** custom bindings; **fallback** to the existing action-bar key bound to the same spell |
| MH suggestion icon | **Hide** Matty7500Hunter / MHP-Hunter-Helper's own suggestion icon while HelloAim is active |
| Packaging | Separate thin addon (not a module inside HelloForever) |

## Open decisions (from the review)

These need an answer from James before v0.1 is written. Each has a
recommendation, but none is decided.

| # | Question | Why it is open | Recommendation |
|---|----------|----------------|----------------|
| 1 | Where exactly does the strip sit? | "Just above the default action bar" is already occupied. Forever's Edit Mode stacks `MultiBarBottomRight`, `MultiBarBottomLeft`, `StanceBar` and `PetActionBar` there (`Blizzard_EditMode/Camelot/EditModeUtil.lua:5-24`), and a hunter with a pet out always has the pet bar. | Default position above the **whole** bottom stack (measured out of combat from the top of whichever of those bars is shown), saved position once the player drags it. |
| 2 | Do bindings belong to a slot or to a spell? | `Bindings.xml` is static, but v0.2 adds and reorders spells. If a binding belongs to slot N, the same key ends up casting a different spell after a reorder. | Bind **per spell**: one button per spell key, e.g. `CLICK HelloAimButton_SERPENT_STING:LeftButton`. Order is display only. |
| 3 | Does v0.1 need secure buttons at all? | Input is keyboard only. In fallback mode (label taken from the action bar) the player presses the action-bar key and the strip button is never clicked. One key holds one binding, so binding a key to the strip takes it away from the action bar. | Ship v0.1 as a **display-only** strip (no secure frames, so no lockdown or taint risk). Add secure buttons in v0.2 for spells that are not on any bar. |

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

- MH already ticks ~20 Hz in combat; **do not** call `MH.State:Build()` /
  `MH.Rotation:Recommend` ourselves (would double CPU on hang-prone hosts).
- If MH is missing: show the strip with **no** highlight (optional tiny local
  fallback priority later — never ship a copy of MH rule tables).
- MH is All Rights Reserved. Calling the live global is fine; shipping
  `Rotations/` is not. Use `OptionalDeps: Matty7500Hunter`.
- `C_AssistedCombat` exists in the API, but Blizzard's own
  `AssistedCombatManager.lua` is only loaded for the mainline game type
  (`Blizzard_ActionBar.toc`), so do not assume it has data on Forever.
  `/dump C_AssistedCombat.IsAvailable()` settles whether it could serve as the
  fallback brain.

Pseudo-keys without a cast button: `AUTO`, `WAIT`, `STEP_BACK`, `MOVE`,
`HOLD_CC`, `IDLE`, `SWING` — banner / dim strip; do not invent a fake secure cast.

### MH contract (to confirm before coding)

None of this is verified. Record the answers here, with the MH version they
were observed on, before any code is written. A `/dump
Matty7500Hunter.lastDecision` once in combat and once out of combat answers
most of it.

| Question | Why it matters |
|----------|----------------|
| MH version tested (`C_AddOns.GetAddOnMetadata("Matty7500Hunter", "Version")`) | Drift detection needs a known-good baseline. |
| Exact fields of `lastDecision` and their types (`key`, `pending`, anything else) | The mapping to strip buttons depends on them. |
| Is the table replaced or mutated on each tick? Is there a timestamp? | Decides how staleness can be detected. |
| Does it update out of combat (with a target, without one)? | The pre-pull Hunter's Mark hint needs an out-of-combat decision. |
| Full list of key strings, including pseudo-keys | Unknown keys must be told apart from new ones. |
| Does MH expose a key → spell ID table? | If not, HelloAim keeps its own small table of key → spell (that is hunter knowledge, not MH's rule tables). |
| Name of the suggestion-icon frame | Needed to hide it at runtime (see below). |
| Licence text | The plan assumes All Rights Reserved. |

Rules that hold whatever the answers are:

- **Staleness.** Clear the highlight on `PLAYER_REGEN_ENABLED` and on target
  loss unless MH is confirmed to keep `lastDecision` current out of combat.
- **Drift.** Validate `type(dec) == "table"` and `type(dec.key) == "string"`.
  An unknown key means no highlight and one chat warning per session that
  names the MH version; it never guesses a button.
- **Read only.** HelloAim reads the global; it does not write to MH's tables or
  saved settings.

## UI architecture

1. **Strip** — one button per spell key. Whether these are secure buttons in
   v0.1 is open decision 3.
2. **Insecure overlay** — highlight, dim and banners. Parented to `UIParent`
   and anchored to the strip, not a child of a secure button.
3. **Keybind labels** — custom binding first, action-bar key second, blank
   with an "unbound" tooltip last. Details below.
4. **Hide MH icon** — at runtime only. Hide the frame (alpha 0 or `Hide`,
   re-applied from its `OnShow`) after MH has loaded. Do **not** change MH's
   saved setting: if HelloAim is later disabled or removed it cannot restore
   it, and the icon would stay hidden. With a runtime hide the icon comes back
   by itself whenever HelloAim is not loaded.

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
  v0.1 shows no label for it; resolving macros (`GetActionInfo` +
  `GetMacroSpell`) is a later improvement.
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
| 5 | `CONCUSSIVE_SHOT` | utility |
| 6 | `RAPTOR_STRIKE` | melee / deadzone |
| 7 | `WING_CLIP` | melee slow |
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
| Overlay, out of combat | Event-driven (`PLAYER_TARGET_CHANGED`, `PLAYER_REGEN_ENABLED`) | No ticker; a slow poll only if MH is confirmed to give out-of-combat decisions |
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
frame.

- **When to compare.** Take the key shown at `UNIT_SPELLCAST_SENT`, not at
  `UNIT_SPELLCAST_SUCCEEDED`. For a spell with a cast time (Aimed Shot) the
  recommendation has moved on by the time the cast completes, so comparing at
  success undercounts.
- **Grace.** A cast counts as followed if its key was shown at any point in
  the 0.5 s before it was sent.
- **Spell matching.** Compare base spells (`C_Spell.GetBaseSpell`) so ranks and
  overrides match their key.
- **Denominator.** `casts` counts only casts of spells that are on the strip.
  Other casts (traps, Feign Death, …) go to `offStrip`. Pseudo-keys (`WAIT`,
  `STEP_BACK`, …) are not counted either way.
- **Joining with HelloForever.** `start` (epoch seconds) and `dur` let the
  offline pipeline match a row to the HelloForever fight record that overlaps
  it. `mh` is the MH version the row was recorded with.

## Slash (draft)

`/aim`, `/aim lock|unlock`, `/aim reset`, `/aim keys`, `/aim debug`,
`/aim style` (hint to `/mh style`).

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

## In-game checks (before and during v0.1)

Before coding:

1. The MH contract table above.
2. `/dump C_AssistedCombat.IsAvailable()`.

With the first build:

3. Cooldown swipe from `GetSpellCooldownDuration` +
   `SetCooldownFromDurationObject` works in combat without an error.
4. `IsSpellUsable` / `IsSpellInRange` return plain booleans in combat.
5. A bound key casts with `ActionButtonUseKeyDown` both on and off
   (secure buttons only).
6. The pet macro revives, calls and mends in the right situations
   (secure buttons only).
7. `/reload` during combat: the strip comes back, nothing is blocked.
8. `/console taintLog 1`, one play session, no HelloAim entries; `/aim debug`
   shows no blocked action.

## Phases

| Phase | Deliverable | Exit criteria |
|-------|-------------|----------------|
| **v0.1** | Strip + overlay; brain = `lastDecision`; keybind labels (custom binding, then action-bar fallback); MH icon hidden at runtime; follow-log summaries; harness green | Can quest pressing only the keys the strip shows; in-game checks pass; no taint; CPU OK |
| **v0.2** | Secure buttons (if not in v0.1) incl. pet button; OOC auto-add on `SPELLS_CHANGED` / level-up; reorder profiles | New spells appear after trainer without manual config; a reorder never changes what a bound key casts |
| **v0.3** | Tune strip layout and visuals using HelloForever fight exports + HelloAim follow rows | Follow rate reported next to own DPS from HelloForever for the same fights; a change counts as an improvement only if DPS does not drop, or the skips are documented as intentional |

Follow rate on its own measures how closely the player obeys the hint, not
whether the hint was good, which is why v0.3 pairs it with damage. MH's
rotation itself is not ours to tune.

Each phase: review → owner OK → deploy → test → only then next phase.

## Risks

1. Secret values degrade MH mid-fight (auras are secret in combat) — strip
   mirrors those mistakes.
2. MH `lastDecision` is de-facto public, not a versioned API, and has not been
   verified for this plan — confirm the contract, then detect drift.
3. Wrong overlay parenting → `ADDON_ACTION_BLOCKED`.
4. Extra ticker on hang-prone hosts — hard-cap 10 Hz.
5. Pet button depends on macro conditionals behaving as on other clients.
6. Cooldown display depends on the duration-object path working for addon code.
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
