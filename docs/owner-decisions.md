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
