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

## 2026-11-12: Agents merge without asking the owner
- Decision: An agent merges a pull request itself once the independent review approves the head and the checks are green. It does not ask the owner first.
- Why: "don't ask me about merge. please apply ai-sdlc"
- Scope: Merges in this repo. Not expenditure, not releases to the game, and not actions outside the repo.
