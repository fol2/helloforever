# HelloAim — adaptive secure-button strip

> **Status: proposal, not implemented, for expert review.**  
> No runnable addon code ships in this folder yet. This document is the design
> brief only. Do not treat filenames under "Suggested layout" as present files.

**Client:** World of Warcraft Forever build **1.60.1** / TOC **16001**  
**Date:** 2026-11-09 (Europe/London)

## Decided (James)

| Topic | Decision |
|-------|----------|
| Addon name | **HelloAim** |
| Strip position | Just **above the default action bar** |
| Input | **Keyboard** — show keybind labels |
| Keybind labels | Prefer **Bindings.xml** custom bindings; **fallback** to the existing action-bar key bound to the same spell |
| MH suggestion icon | **Hide** Matty7500Hunter / MHP-Hunter-Helper's own suggestion icon while HelloAim is active |
| Packaging | Separate thin addon (not a module inside HelloForever) |

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

Pseudo-keys without a cast button: `AUTO`, `WAIT`, `STEP_BACK`, `MOVE`,
`HOLD_CC`, `IDLE`, `SWING` — banner / dim strip; do not invent a fake secure cast.

## UI architecture

1. **Secure strip** — `SecureActionButtonTemplate` buttons, each always casts
   one spell. Spell IDs / order / count updated **only out of combat**
   (`PLAYER_REGEN_ENABLED`, `PLAYER_LOGIN`, `SPELLS_CHANGED`, queued if mid-combat).
2. **Insecure overlay** — mirrors MH ActionGlow parenting rules (overlay is
   **not** a child of the secure button).
3. **Keybind labels** — Bindings.xml entries such as
   `CLICK HelloAimButtonN:LeftButton`; label widget shows
   `GetBindingKey(...)` or, if unbound, the key already bound to the same spell
   on the default action bars.
4. **Hide MH icon** — on load / enable, turn off MH's floating suggestion icon
   via its settings API or documented slash if available; restore on disable.

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
| 8 | `MEND_PET` | resolve ourselves (not in MH damage rotation) |
| 9 | `CALL_PET` / `REVIVE_PET` | attribute swap **OOC only**, or two fixed buttons |

## Perf budget

| Path | Rate | Work |
|------|------|------|
| Brain | Consume MH's tick | Read `lastDecision` only |
| Overlay | ≤ **10 Hz** in combat; ~0.25 s OOC | Paint only when key/flags change |
| Secure rebuild | OOC only | Login / regen / spells / level |

No CLEU. Optional `/aim rate slow` (5 Hz) if FPS drops.

## SavedVariables (draft) `HelloAimDB`

```text
version, addonVersion
pos, scale, locked
keys = ordered known strip keys
showKeybinds, showOOM, showRange
rate = "normal"|"slow"
hideMHIcon = true
follow = { { t, followed, casts, topSkipped }, ... }  -- capped ~50 rows
```

Follow log: on `UNIT_SPELLCAST_SUCCEEDED` compare cast to last shown key; on
combat end push one summary row. Do **not** log every overlay frame.

## Slash (draft)

`/aim`, `/aim lock|unlock`, `/aim reset`, `/aim keys`, `/aim debug`,
`/aim style` (hint to `/mh style`).

## Suggested layout (future implementation — not in repo yet)

```text
HelloAim/
  HelloAim.toc          ## Interface: 16001, OptionalDeps: Matty7500Hunter
  Bindings.xml
  Core.lua
  SpellSet.lua
  SecureBar.lua         -- OOC only attribute changes
  Overlay.lua           -- combat-safe highlight
  Brain.lua             -- read Matty7500Hunter.lastDecision
  FollowLog.lua
  Options.lua
```

## Phases

| Phase | Deliverable | Exit criteria |
|-------|-------------|----------------|
| **v0.1** | Secure strip above action bar + overlay; brain = `lastDecision`; Bindings.xml labels + action-bar fallback; hide MH icon; follow-log summaries; box harness green | Can quest pressing only the strip; no taint; CPU OK |
| **v0.2** | OOC auto-add on `SPELLS_CHANGED` / level-up; reorder profiles; Call/Revive slot logic | New spells appear after trainer without manual config |
| **v0.3** | Tune using HelloForever fight exports + HelloAim follow rates | Measurable follow-rate ↑ or documented intentional skips |

Each phase: review → owner OK → deploy → test → only then next phase.

## Risks

1. Secret values degrade MH mid-fight — strip mirrors those mistakes.
2. MH `lastDecision` is de-facto public, not a versioned API — detect drift.
3. Wrong overlay parenting → `ADDON_ACTION_BLOCKED`.
4. Extra ticker on hang-prone hosts — hard-cap 10 Hz.
5. Pet buttons need our own resolver (MH dropped pet reminders).
6. **ToS:** still player-driven; never automate presses.

## Terms of Use

HelloAim is assistive UI only. Every ability is a player key press or click.
No input injection, no auto-cast, no combat-time rebinding of what a key does.
