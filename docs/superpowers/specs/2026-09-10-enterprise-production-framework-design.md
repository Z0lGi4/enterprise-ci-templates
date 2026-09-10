# Enterprise Production Framework — Design

**Date:** 2026-09-10 · **Owner:** Daniel Stafrace · **Status:** approved, pre-implementation

## 1. Goal

One fixed production bar — codified standards *and* enforced CI — applied
identically across every product repo in the portfolio (11 repos:
seoforge-ai, ContentAIPlatform, ai-booking-agent, ai-company-orchestrator,
branded-video-factory, memory-medic, social-mind, vibetest, churnsignal,
ARIA, faceless-video-factory), regardless of current maturity. Retrofitted
onto all of them now, not phased in only for new work.

`faceless-video-factory`'s canonical repo lives on GitHub
(`Z0lGi4/faceless-video-factory`) and is developed primarily from the VPS —
the desktop copy at `~/faceless-revamp` is not git-tracked and is out of
scope for this framework; the retrofit targets the real repo.

Development across this portfolio is almost entirely AI-agent-driven
(Claude Code, Hermes Agent, Antigravity, and in ai-company-orchestrator's
case a 21-agent orchestrator). The framework is designed for that reality:
the review gate is an automated agent, not a human bottleneck.

## 2. Architecture

**New repo (this one), `Z0lGi4/enterprise-ci-templates`**, is the single
source of truth. It holds two reusable GitHub Actions workflows:

- `.github/workflows/python-ci.yml`
- `.github/workflows/node-ci.yml`

Both are `on: workflow_call`. A shared secret-scanning step is factored out
so that logic lives once, called by both, not duplicated.

Each product repo gets one thin file:

```yaml
# .github/workflows/ci.yml (in each product repo)
name: CI
on: [push, pull_request]
jobs:
  ci:
    uses: Z0lGi4/enterprise-ci-templates/.github/workflows/python-ci.yml@main
    secrets: inherit
```

Updating the standard means editing it once here; every repo picks up the
change on its next run — no per-repo edits for a standard change.

**Branch protection:** each repo's `main` requires the `ci` check to pass
before merge. Applied per-repo during rollout (a repo setting, not a file).

**Documentation layer:** `~/.claude/rules/ecc/common/production-framework.md`
(global, on the desktop) states this bar in prose and points here, so any
agent bootstrapping a *new* repo already knows the target before CI ever
runs. Cross-referenced from the existing `code-review.md`, `testing.md`,
and `git-workflow.md` rule files, matching how those already cross-reference
each other.

## 3. The five CI gates

Both `python-ci.yml` and `node-ci.yml` run the same five stages with
language-appropriate tools:

1. **Lint** — `ruff check .` (Python) / `eslint` + `tsc --noEmit` (Node)
2. **Tests + coverage gate** — `pytest --cov` / `vitest --coverage`, failing
   under **80%** on changed code (the existing global `testing.md` number,
   not a new one)
3. **Secret scan** — `gitleaks detect` (already a tool in active use;
   `./gitleaks.exe` is in the existing Bash permission allowlist)
4. **Dependency audit** — `pip-audit` / `pnpm audit`, failing on known
   high/critical CVEs
5. **Automated review gate** — `claude -p "review this diff for
   correctness, security, and quality issues" --output-format json`
   against the PR diff, using an `ANTHROPIC_API_KEY` repo secret. Parses
   the JSON result and **fails the build on any CRITICAL or HIGH finding**
   — same severity vocabulary as the existing `code-review.md` rule.

**Error handling:** any stage failing blocks the PR via branch protection.
A stage that can't run at all (e.g. a brand-new repo with no tests yet) is
a **failure**, not a skip — "no tests" is a finding.

**Known trade-off, accepted:** stage 5 costs a small amount of real API
spend per PR and adds latency. This was chosen deliberately over a
CI-only gate or a human-review gate.

## 4. Rollout strategy

Repos are not starting from the same place:

- **Already have real CI** (ContentAIPlatform: 7 workflows including a
  tenant-isolation gate + promptfoo compliance eval; seoforge-ai:
  zero-tolerance ruff + 190 tests; ai-company-orchestrator: ruff + bandit +
  pre-commit): fold in whatever's missing from the 5 gates — coverage
  enforcement, secret scan, dependency audit, and the review-agent gate
  specifically. Nothing existing is removed.
- **Have none** (ai-booking-agent, memory-medic, social-mind, vibetest,
  churnsignal): bootstrap from scratch via the templates.

**Pilot before mass rollout:** validate both templates against one real
repo per language before touching the remaining nine — cheaper to fix the
template once than debug it nine times over.

- Python pilot: **memory-medic** (smallest surface, already has real tests)
- Node pilot: **ARIA** (the most demanding real test suite — ~1650 tests —
  so a template that survives it will survive the simpler Node repos)

The remaining nine repos (ContentAIPlatform, ai-booking-agent,
ai-company-orchestrator, branded-video-factory, social-mind, vibetest,
churnsignal, seoforge-ai, faceless-video-factory) follow in any order once
both pilots are green, since the bar is identical for all of them.

## 5. Auto-updating technical doc + slide deck

Separate workflow, `docs-sync.yml`, triggered on push to `main` (i.e.
**after** a PR merges — it writes back, it doesn't gate).

**Steps:**
1. `claude -p` regenerates `docs/TECHNICAL_OVERVIEW.md` (architecture,
   stack, components, API surface — reflecting current `main`, not a
   snapshot from when someone last remembered to update it) and
   `docs/deck.html` (a concise product/architecture slide deck).
2. `deck.html` → `deck.pdf` via **Playwright's headless Chromium**
   (already available via the Playwright MCP/plugin; chosen over the
   desktop-Chrome-path pattern in the existing Hermes
   `multi-project-build` skill because it's portable to a Linux CI
   runner, which a local Chrome install path is not).
3. Opens a PR labeled `automated-docs` with the regenerated files.

**Deliberate exception to the review gate:** a docs-only PR that's
regenerated from already-reviewed code doesn't re-run the review-agent
gate (stage 5) — only lint/build need to pass, then it auto-merges. This
was an explicit trade-off, not an oversight: re-reviewing generated
documentation of already-approved code adds cost with no signal.

**Loop prevention:** `docs-sync.yml`'s trigger path-filters out `docs/**`,
so the auto-merge of its own output doesn't re-trigger itself.

## 6. Explicitly out of scope (not decided here, don't assume)

- Environment promotion / staging-vs-prod strategy — most repos aren't
  deployed yet; this framework governs code landing on `main`, not what
  happens after
- Publishing the tech doc / deck externally (Gamma, Drive) — in-repo only,
  per the approved decision in section 5
- Any change to repos not in the list in §1
