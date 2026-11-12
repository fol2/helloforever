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

**Seen in the saved data of 12 Nov 2026** (HelloForever 0.6.0 and 0.7.0, MH v.42). These are
fight records decoded from the SavedVariables, nothing else:

- 63 fights carry `mh.status = "ok"`, `addon = "Matty7500Hunter"`, `version = "v.42"`. None
  is `unknown`.
- The three fights pulled under 0.6.0 have `decision.key = "SERPENT_STING"` and no `approx`.
  The other 60 are catch-up reads at login: `decision.key = "IDLE"`, `approx = true`.
- Keys kept in `decision`: `baseState`, `key`, `phase`, `profile`, `reason`, `state` on all
  63. The three pulled fights also have `list`; one of them also has `flags` and
  `outOfRange`. `pending` and `wait` were on none. So `key` survives the 20-key cap.
- `scores` and a decision from SavedVariables never appeared, as the source said.

**What the data answers, and what it does not:**

| Step below | State |
|---|---|
| 1. `/hello selftest` line | **Not checked.** The command was not run (the saved data has no selftest result). |
| 2. `/hello debug` line | **Not checked.** |
| 3. A fight's `mh` block | **Answered** by the records above, except whether the key was the hint MH showed on screen. |
| 4. HelloForever never writes to MH | **Not checked.** |

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

**Done when.** Steps 1, 2 and 4 are checked, and one recorded `decision.key` is compared
with the hint MH showed at that pull (a screenshot or a note is enough).
