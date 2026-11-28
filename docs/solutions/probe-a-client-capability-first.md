# Probe a client capability in the game before building a feature on it

Moved from `LESSONS.md` on 2026-11-28, when the live log passed fifteen entries.

- Cause: 0.8.0 shipped a reload when AFK that calls `ReloadUI` from a timer. The harness mock allowed it; the client refuses a reload without a key press. The feature could never work and was removed one release later. A one-line probe in the game (`/hlink reloadtest`) settled it in a minute.
- Fix: #20 (0.8.1)
- Done right: when a feature stands on one client behaviour nobody has seen, ship the probe first (a slash command that tries it and reports), get the result, then build. "Fails safe" does not make an unproven feature worth a release.
- Seen: 1× (2026-11-12)
