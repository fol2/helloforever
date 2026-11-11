# Confirm what Matty Hunter exposes

**Why.** HelloForever records a read-only sample of the Matty7500Hunter / MHP-Hunter-Helper
recommendation with each fight, and the HelloAim proposal (`HelloAim/PLAN.md`) is built on
the same reading. The names it looks for (`lastDecision`, `lastScores`, `scores` on a
global table, or a SavedVariables table) are a hypothesis: MH's source is All Rights
Reserved, so it could not be read here. Nothing should be built on it before the game
confirms it.

**Do** (hunter, MH installed and enabled, HelloForever 0.6.0):

1. `/hello selftest`: note the `Matty Hunter:` line (`ok`, `unknown` or `unavailable`).
2. `/hello debug`: note `mh status=… addon=…`.
3. Fight a few mobs, `/reload`, and look at a fight's `mh` block in the SavedVariables:
   - `status = "ok"` with a `decision` table that matches the hint MH showed at the pull:
     the hypothesis holds. Record the keys of `decision` and `scores`.
   - `status = "unknown"`: MH is loaded but exposes none of the expected tables. Find what
     it does expose, without calling it: `/dump` the candidate globals
     (`Matty7500Hunter`, `MHPHunterHelper`, `MHP_Hunter_Helper`) and its SavedVariables
     names, and record the shape.
4. Confirm HelloForever never writes to MH: MH's SavedVariables file has no HelloForever
   keys, and MH behaves the same with HelloForever disabled.

**Then.** Update `docs/SCHEMA.md` ("Matty Hunter (MH) observe") and `HelloAim/PLAN.md` with
what was found; adjust the name lists in `Snapshot.lua` (`MH_ADDONS`, `MH_GLOBALS`, `MH_SV`)
if they differ. HelloForever must stay read-only: `rawget`, no method calls, no callbacks.

**Done when.** The plan states the verified shape (or states that MH exposes nothing
readable, in which case HelloAim needs a different source).
