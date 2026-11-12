# REVIEW.md

What the independent reviewer checks on every PR. The reviewer reads this file first, then uses the AI-SDLC review prompt (`references/review-prompt.md`). Changed by PR.

## Reviewer

- Primary: codex (OpenAI, the codex CLI's default model), read-only: no file edits, no state-changing git commands, no network writes.
- Fall-backs when the primary's quota is spent, in order: grok, cursor.
- Last resort: a Claude subagent in a fresh context. The PR says so, and the task type cannot merge above level 2 on that review.

Findings P0–P3, each with `file:line`, posted on the PR as a comment with `VERDICT:` and `Reviewed head: <sha>` lines. Re-reviews cover only the fix diff.

## Passes

Run all three, in order, against the PR's diff:

1. **Bugs and logic:** correctness on real inputs (empty and missing values, boundaries, time zones, encodings, concurrency, retries), failure behaviour when a dependency is down or wrong, silent failures, and whether the regression test really fails on the old code.
2. **Security:** secrets, injection, authorisation, untrusted input, new dependencies.
3. **Compliance:** the diff against the issue, the spec and plan when present, `docs/code-standards.md`, `docs/owner-decisions.md` and `docs/north-star.md`. A diff that departs from the plan without an update to the plan fails this pass. A diff that spends money without an `Expenditure:` decision fails this pass.

## Severity

- **Important** (blocks): P0 data loss, security hole, outage or irreversible damage; P1 wrong behaviour on a real path, or an acceptance criterion fails; P2 edge-case bug, weak or missing test, undisclosed unrun check, missing docs.
- **Nit** (never blocks): P3. Report at most **5** per review; drop the rest.

## Exclusions

Do not review:

- generated files: `dist/`;
- skill-owned copies: `.ai-sdlc/`, `.github/workflows/ai-sdlc-checks-impl.yml`, `.claude/hooks/` (check only that they match the skill);
- anything CI already enforces: luacheck on `HelloForever/` and `tests/`; the version agreement checked by `tools/package.py --check`.

## Doc-only fast lane

A diff takes the doc-only fast lane when it changes nothing that runs, is copied, or is read as an instruction. In: `README.md`, `LESSONS.md`, `docs/solutions/`, `docs/metrics.md`, and prose under `docs/` that no agent or tool acts on. Out, always the full lane: `AGENTS.md`, `CLAUDE.md`, `REVIEW.md`, `docs/code-standards.md`, `docs/owner-decisions.md`, `docs/autonomy-ledger.md`, `docs/north-star.md`, `docs/plans/TEMPLATE.md`, skills, modules, prompts, agent definitions, hooks, workflows, scripts, templates of any kind, configuration, code and tests. The lane gets the compliance pass and the writing check (`modules/writing.md`). No regression test is required.

## Human review required

None. The owner's decision of 2026-11-12 (`docs/owner-decisions.md`) is that agents merge without asking. `docs/owner-decisions.md` stays append-only; the `owner-decisions` check holds that.

## Separation of duties

- The agent that wrote the change never reviews or approves it.
- A security fix is never approved by the agent that wrote it.

## Feedback

A kind of finding seen on two PRs becomes a `LESSONS.md` entry. A promoted lesson that a machine can check becomes a hook, lint or CI check, not another review pass.
