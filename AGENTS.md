# AGENTS.md

AI-SDLC: v3 (2026-11-12)

Routing table only. Each row names the document that governs an area. Rules live in those documents, never here. Read `LESSONS.md` and `docs/autonomy-ledger.md` before every task; read the rest when a row sends you there.

| Area | Governing doc |
|---|---|
| Delivery loop: intent, plan, PR, review, merge, deploy, report | AI-SDLC skill, `SKILL.md` |
| How far each task type runs without the owner | `docs/autonomy-ledger.md` |
| Why this repo exists and how it earns | `docs/north-star.md` |
| Decisions PRs must not reverse; approved expenditure | `docs/owner-decisions.md` |
| Commands: test, lint, deploy, rollback, health | `docs/code-standards.md` (Commands) |
| Repo-specific hard rules and acceptance criteria | `docs/code-standards.md` |
| Lessons from recent mistakes | `LESSONS.md`; older ones in `docs/solutions/` |
| What the reviewer checks; reviewer and fall-backs | `REVIEW.md` |
| Intent (issue) fields | `.github/ISSUE_TEMPLATE/intent.md` |
| PR body | `.github/pull_request_template.md` |
| Plans and specs | `docs/plans/`, `docs/specs/` |
| Hooks and checks | `.claude/settings.json`, `.github/workflows/ai-sdlc-checks.yml` |
| Nightly audit, agent-setup evals, weekly metrics | not set up (`docs/code-standards.md`, Enforcement in this repo) |
| HelloForever saved-data format (what the offline pipeline reads) | `docs/SCHEMA.md` |
| HelloForever version history | `CHANGELOG.md`, `HelloForever/HISTORY.md` |
| HelloAim (proposal only, no code) | `HelloAim/PLAN.md` |
| Work that needs the game client | `plan/` |
| The local game install and what it loads | `docs/code-standards.md` (This machine) |
