# Owner decisions

Decisions that PRs must not reverse. Append-only. The orchestrator adds entries with `scripts/record_decision.sh` from the AI-SDLC skill; nobody edits or removes one. CI fails a PR that removes a line from this file.

- The orchestrator records a decision when the owner states one and quotes the owner's words. A paraphrase says so. The owner can add or correct entries at any time.
- If a task seems to need a reversal, stop and ask the owner. If the owner's new direction conflicts with an entry, ask once. Do not open a PR that contradicts an entry.
- A step may wait on a human only at the three AI-SDLC touchpoints (north star, owner decisions, expenditure), or when an entry here names that step as the owner's.
- **Expenditure** entries record approved spend: a new paid service, an API key for a paid service, a spend-cap rise, a one-off purchase or ad spend. Without an entry the agent proposes and waits; see `docs/autonomy-ledger.md`.
- The autonomy levels live in `docs/autonomy-ledger.md`, not here. An entry here can set a level by hand.

Entry format (newest first):

```markdown
## YYYY-MM-DD: <decision, one line>
- Decision: <what was decided>
- Why: <the owner's reason, quoted; or "Paraphrased: ...">
- Scope: <what it covers, and what it does not>
```

## Decisions

## 2026-11-13: The strip uses six bits a square by default and falls back to three on errors
- Decision: The live-state strip starts at four colour levels a channel (six bits a square). When a reader finds it unstable (frames failing the check, or palette colours too close) it asks the addon, through the slots, to fall back to two levels (three bits) for the session.
- Why: "let's try default 6bit. it should be fine. if unstable and received certain error, then fallback to lower bit. i think this is the better work" The lead had proposed three bits as the default and six as a setting, because six bits were measured once, on one display.
- Scope: The live-state strip's default depth (docs/specs/29.md). The player can still set the depth by hand.

## 2026-11-12: A changed Lua file of HelloForever is hot-loaded too; the TOC waits for a restart
- Decision: A HelloForever release whose code changes are in existing .lua files is copied in while the game runs and loaded by /reload, like any other addon here. The .toc (with the new version number) is replaced when the game is next closed; until then the addon reports the old version and the new source revision.
- Why: "aren't we say we do hot load?" The lead had held HelloForever releases back because they change the .toc version.
- Scope: HelloForever in the local game. It corrects the sentence in the entry of 2026-11-12 on hot loading that said HelloForever releases still wait.

## 2026-11-12: The strip is one row of 2 or 3 pixels at the very top-left
- Decision: The live-state strip is a single row, 2 pixels high by default (3 can be set), starting at (0, 0) of the game's UI.
- Why: "the colour bar i suggest 1 line only and can do 3/2 px start from 0,0 so it won't interrupt normal plays"
- Scope: The live-state strip's default geometry. The player can still move it or switch it off.

## 2026-11-12: The strip shows live health and power, as bars
- Decision: Values the client keeps secret from addons (the player's health and power, the target's health, the pet's health) are shown on the live-state strip as status bars, which the client lets an addon feed with such values; a reader measures them. The addon passes the value straight from the API to the bar and never tests, compares or computes on it.
- Why: "that's a part of our box features, i prefer real live, as you are not the only user. i'll expand to other use cases. so please do that." The lead had proposed to leave them unknown in the first version.
- Scope: The live-state strip (docs/specs/29.md). It does not lift the rule that nothing here presses a key or casts.

## 2026-11-12: HelloForever stays an adviser; the live-state strip is a shared, public channel
- Decision: The rule that no addon here automates a key press or a cast stays. This repository provides a general live-state strip (the coloured squares) with a public format, which the assistant needs itself. Another, private project of the owner may read the same strip from its own repository, under its own rules, like any client of a public interface; what it does with the data is not part of this repository. No code that presses a key or casts for the player is added here.
- Why: "I agree", answering the lead's question whether to keep the no-automation rule and share the channel only. Paraphrased: the owner had proposed to move the addons of that private project here as an integration, and to put more information into the coloured squares by compression or other means. Later: "what you will do is leave a note ... just like API working. what they doing not involve your side".
- Scope: This repository and what it ships. Not the other project, which is not changed from here without the owner asking.

## 2026-11-12: A changed Lua file may be copied in while the game runs, then /reload
- Decision: When a release changes only existing .lua files of an addon, the agent may copy them into the running game and ask the owner to /reload. A changed .toc, a new file or a new addon still waits until the game is closed. HelloForever releases change the .toc version, so they still wait.
- Why: "can we support hot load? can i just type reload?" Seen to work on 12 Nov 2026 with HelloLink.lua.
- Scope: Addons of this repository in the local game. It narrows the entry of 2026-11-12 on installing (the folder is never replaced while the game runs): a file copy of unchanged file names is allowed; replacing the folder is not.

## 2026-11-12: The agent installs a build when the game is closed, without asking
- Decision: Before installing, the agent checks whether the game is running. If it is, the agent waits until it has closed. It does not ask the owner to close it or to confirm.
- Why: "You can always check if game is running or not. Then you can adjust time and gap to install"
- Scope: Installing HelloForever into the local game. The addon folder is never replaced while the game runs.

## 2026-11-12: The agent acts as code owner and may start work itself
- Decision: The agent may start work in this repository without an owner message (fixes, features, reports, releases), merge it after an independent APPROVE on the head, and install a build into the game.
- Why: "You can do whatever you want. You are code owner"
- Scope: This repository and the local game install. Not expenditure. The loop's gates stay: independent review on the head, checks, and a report of what was done.

## 2026-11-12: Agents merge without asking the owner
- Decision: An agent merges a pull request itself once the independent review approves the head and the checks are green. It does not ask the owner first.
- Why: "don't ask me about merge. please apply ai-sdlc"
- Scope: Merges in this repo. Not expenditure, not releases to the game, and not actions outside the repo.
