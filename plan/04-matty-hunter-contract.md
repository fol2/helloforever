# Confirm in the game what Matty Hunter exposes

**Why.** HelloForever records a read-only sample of the Matty7500Hunter (MH) recommendation
with each fight, and the HelloAim proposal (`HelloAim/PLAN.md`) is built on the same
reading. The names were a hypothesis when 0.6.0 was written.

**Known from the MH source** (read in the installed copy, v.41 on 9 Nov 2026 and v.42 on
11 Nov 2026; nothing of it is copied here, its licence is All Rights Reserved):

- The addon folder and the global are both `Matty7500Hunter`; the SavedVariables table is
  `Matty7500HunterDB`.
- `Matty7500Hunter.lastDecision` is a plain field, so HelloForever's `rawget` finds it.
  Its fields are listed in `HelloAim/PLAN.md` ("MH contract").
- There is no `lastScores` or `scores`, and `Matty7500HunterDB` holds settings and fight
  history, not a decision. A fight's `mh.scores` will always be absent, and the
  SavedVariables fallback never yields a decision.
- The other names in `MH_ADDONS`, `MH_GLOBALS` and `MH_SV` (`Snapshot.lua`) match nothing in
  MH. They cost one failed lookup each and are left in place.
- MH has run on this client since 10 Nov 2026 (`Matty7500HunterDB` has fight history).

So the hypothesis holds on paper. What is left needs HelloForever 0.6.0 in the game
(`01-in-game-verification.md`; the development Mac still loads 0.5.0, which does not
sample MH).

**Do** (hunter, MH enabled, HelloForever 0.6.0):

1. `/hello selftest`: the `Matty Hunter:` line says `ok`.
2. `/hello debug`: note `mh status=… addon=…`.
3. Fight a few mobs, `/reload`, and look at a fight's `mh` block in the SavedVariables:
   `status = "ok"`, and `decision.key` matches the hint MH showed at the pull. Record
   which keys of `decision` were kept: the copy takes at most 20 keys and 10 per
   sub-table, so the two state snapshots inside the decision arrive as an arbitrary
   sample. If `decision.key` is ever missing, that cap is the cause.
4. Confirm HelloForever never writes to MH: `Matty7500Hunter.lua` in SavedVariables has no
   HelloForever keys, and MH behaves the same with HelloForever disabled.

**Then.** Update `docs/SCHEMA.md` ("Matty Hunter (MH) observe") and `HelloAim/PLAN.md`
from "read in the source" to "seen in the game". HelloForever must stay read-only:
`rawget`, no method calls, no callbacks.

**Done when.** A recorded fight shows `mh.status = "ok"` with the right `decision.key`.
