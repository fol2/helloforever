# Model a client event from what the client does, not from its name

Moved from `LESSONS.md` on 2026-11-24, when the live log passed fifteen entries (#348).

- Cause: the mock client emptied its session list whenever it fired `DAMAGE_METER_RESET`. The real client fires it at login and keeps the list, so every login filed about 30 fights again, from 0.5.0 on. 230 green harness checks said nothing, because the mock agreed with the code.
- Fix: #14
- Done right: decode the real SavedVariables after the first run of a change and compare them with what the harness predicts. Write a mock from an observation; mark every assumed behaviour as unverified in `plan/01`.
- Seen: 1× (2026-11-12)
