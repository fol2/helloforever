# A gate that reads a config file validates the whole file once, strictly

Moved from `LESSONS.md` on 2026-11-24, when the live log passed fifteen entries (#348).

- Cause: the adoption test first searched `.claude/settings.json` for hook file names. Then it piped `jq` into `head`, which hid a parse failure and cut a multi-line command. Then it accepted a file with two top-level JSON values. The reviewer found a new hole on three rounds.
- Fix: #9 (`.github/ai_sdlc_adoption.sh`)
- Done right: slurp the file and require exactly one object. Read every value from that validated object. Let the parser's own exit status decide. Give the validator its own refusal cases. After the second hole of one kind, ship the strict version, not another patch.
- Seen: 1× (2026-11-12)
