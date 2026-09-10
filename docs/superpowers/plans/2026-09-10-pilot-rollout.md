# Pilot Rollout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate the Enterprise Production Framework's reusable workflows against two real repos — one from-scratch adoption (memory-medic, Python, no existing CI) and one adoption-onto-a-mature-pipeline (ARIA, Node, already has a sophisticated CI/deploy pipeline) — proving the framework works on real code before rolling out to the remaining nine repos.

**Architecture:** memory-medic gets the full standard adoption: a thin `.github/workflows/ci.yml` calling `python-ci.yml@main` wholesale, plus branch protection. ARIA gets a **selective** adoption: only the two gates it genuinely lacks (secret-scan, dependency-audit) as a new, narrowly-scoped workflow that is **not wired into its existing `deploy.yml`** — a design decision made explicitly because ARIA is a live, revenue-relevant service whose deploy pipeline already keys off its own `test.yml` workflow by name, and a bug in framework code must not be able to block or break a live deploy on day one. ARIA does not get the bundled `node-ci.yml` reusable workflow, the `lint` gate, or `review-agent` in this pilot — its own `test.yml` has no `lint` script (adding one would fight its "deliberately dependency-free" philosophy) and already runs a battle-tested, comprehensive suite (unit tests, architecture-boundary enforcement, red-team security evals, an LLM regression suite) that our generic coverage/test job would either duplicate or conflict with.

**Tech Stack:** GitHub Actions, `gh` CLI for repo administration (secrets, branch protection), the reusable workflows from Plan 1 (`Z0lGi4/enterprise-ci-templates`).

**Spec:** `docs/superpowers/specs/2026-09-10-enterprise-production-framework-design.md` (§4 Rollout strategy) — this plan implements the "pilot before mass rollout" step it specifies.

## Global Constraints

- memory-medic: `Z0lGi4/memory-medic`, local clone at `C:\Users\Owner\projects\memory-medic`, branch `main`, no existing `.github/workflows/`, no existing repo secrets, no existing branch protection.
- ARIA: `Z0lGi4/ARIA`, local clone at `C:\Claude Projects\ARIA`, branch `main`, existing workflows `test.yml` (name: `tests`) and `deploy.yml` (triggers on `workflow_run: workflows: [tests]`) — **do not modify either file**. Existing secrets: `ANTHROPIC_API_KEY`, `AWS_DEPLOY_ROLE_ARN`, `AWS_EVAL_ROLE_ARN` — **do not touch these**. No existing branch protection.
- Neither repo is owned by a GitHub Organization (both are under the personal account `Z0lGi4`), so `GITLEAKS_LICENSE` is not required for either (per the framework's own README note).
- `CLAUDE_CODE_OAUTH_TOKEN` still does not exist as a secret anywhere (same gap carried from Plan 1 — Daniel has not yet run `claude setup-token`). memory-medic's `review-agent` job will be blocked on this exactly like every workflow in Plan 1 was — this is expected, not a new defect, and is not this plan's problem to solve.
- Every action reference pulled in by the shared reusable workflows is already SHA-pinned (inherited from Plan 1) — nothing new to pin here except if a task hand-writes a new step (ARIA's dependency-audit job), which must follow the same discipline.

---

### Task 1: memory-medic — standard adoption

**Files:**
- Create (in `C:\Users\Owner\projects\memory-medic`): `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `Z0lGi4/enterprise-ci-templates/.github/workflows/python-ci.yml@main` (Plan 1, merged and live)
- Produces: five required status checks (`ci / lint`, `ci / test`, `ci / secret-scan`, `ci / dependency-audit`, `ci / review-agent`) once branch protection is added in Step 5

- [ ] **Step 1: Create a working branch in the memory-medic repo**

```bash
cd "C:\Users\Owner\projects\memory-medic"
git checkout -b ci/adopt-enterprise-framework
```

- [ ] **Step 2: Add the thin caller workflow**

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]
jobs:
  ci:
    uses: Z0lGi4/enterprise-ci-templates/.github/workflows/python-ci.yml@main
    secrets: inherit
```

- [ ] **Step 3: Commit and push, open a real PR**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: adopt the Enterprise Production Framework" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git push -u origin ci/adopt-enterprise-framework
gh pr create --title "ci: adopt the Enterprise Production Framework" \
  --body "Adopts \`python-ci.yml\` from \`Z0lGi4/enterprise-ci-templates\` — see that repo's design spec. Part of the pilot rollout." \
  --base main
```

- [ ] **Step 4: Verify the PR's checks — real evidence, not assumed**

```bash
gh pr checks --watch
```
Expected: `lint`, `test`, `dependency-audit` pass (memory-medic already has real tests and a clean `pyproject.toml`, per its own README this session already wrote). `secret-scan` should pass (no secrets in this small repo). `review-agent` will fail or error — **this is expected**: `CLAUDE_CODE_OAUTH_TOKEN` doesn't exist yet. Confirm via `gh run view <id> --log` that the failure is specifically the missing-secret `workflow_call` validation error (same signature documented throughout Plan 1's ledger), not something memory-medic-specific. If `lint`, `test`, or `dependency-audit` fail for a REAL reason (not the known secret gap), stop and fix memory-medic's code/config — do not merge a red PR.

- [ ] **Step 5: Add branch protection requiring the 4 checks that can currently pass**

Once Step 4 confirms only `review-agent` fails (on the known, expected gap), protect `main` requiring the other four — not `review-agent`, since requiring a check that can never currently pass would permanently block every future PR:

```bash
cat > /tmp/memory-medic-branch-protection.json << 'EOF'
{
  "required_status_checks": {
    "strict": false,
    "contexts": ["ci / lint", "ci / test", "ci / secret-scan", "ci / dependency-audit"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
gh api -X PUT repos/Z0lGi4/memory-medic/branches/main/protection \
  -H "Accept: application/vnd.github+json" \
  --input /tmp/memory-medic-branch-protection.json
```
Verify: `gh api repos/Z0lGi4/memory-medic/branches/main/protection --jq '.required_status_checks.contexts'` returns exactly those four strings.

- [ ] **Step 6: Merge the PR**

```bash
gh pr merge --squash --delete-branch
```
Verify: `gh pr checks` on the merge shows the four required checks green (this is the actual proof the adoption works, not just that it was configured). Note in your report whether `review-agent`'s failure blocked the merge or not (branch protection above does NOT require it, so it should NOT block — confirm this is actually true, not assumed).

---

### Task 2: ARIA — selective adoption (secret-scan + dependency-audit only, not deploy-gating)

**Files:**
- Create (in `C:\Claude Projects\ARIA`): `.github/workflows/ci-security.yml`

**Interfaces:**
- Consumes: `Z0lGi4/enterprise-ci-templates/.github/actions/secret-scan@main` (the composite action directly — NOT the bundled `node-ci.yml` reusable workflow, which assumes a `lint` script and a coverage-tooled test runner ARIA doesn't have)
- Produces: two new status checks (`security / secret-scan`, `security / dependency-audit`) — does NOT produce or touch anything named `tests`, so `deploy.yml`'s `workflow_run: workflows: [tests]` trigger is provably unaffected

- [ ] **Step 1: Create a working branch in the ARIA repo**

```bash
cd "C:\Claude Projects\ARIA"
git status --porcelain
```
Two untracked files (`CLAUDE.md`, `docs/AGI-CAPABILITY-RESEARCH-2026-07-13.md`) are pre-existing from outside this plan — leave them untouched, do not commit or stash them as part of this task.

```bash
git checkout -b ci/security-gates
```

- [ ] **Step 2: Write the new, narrowly-scoped workflow**

```yaml
# .github/workflows/ci-security.yml
name: security
on: [push, pull_request]
jobs:
  secret-scan:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
        with:
          fetch-depth: 0
      - uses: Z0lGi4/enterprise-ci-templates/.github/actions/secret-scan@main

  dependency-audit:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
      - uses: pnpm/action-setup@v6
      - name: Setup Node.js
        uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0
        with:
          node-version: '22'
          cache: pnpm
      - name: Install (dev deps only)
        run: pnpm install --frozen-lockfile
      - name: Audit dependencies
        run: pnpm audit --audit-level=high
```

Note the job/workflow naming deliberately avoids the word "tests" anywhere (workflow name `security`, jobs `secret-scan`/`dependency-audit`) — this is load-bearing, not stylistic: `deploy.yml` matches on `workflows: [tests]` by exact name, and ARIA's own workflow is separately named `tests` (in `test.yml`). Keeping this one named `security` guarantees `workflow_run` can never accidentally match it.

- [ ] **Step 3: Commit, push, open a real PR**

```bash
git add .github/workflows/ci-security.yml
git commit -m "ci: add secret-scan and dependency-audit gates from the Enterprise Production Framework" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git push -u origin ci/security-gates
gh pr create --title "ci: add secret-scan and dependency-audit gates" \
  --body "Selective adoption of the Enterprise Production Framework (see Z0lGi4/enterprise-ci-templates) — only the two gates ARIA doesn't already have. Deliberately NOT wired into deploy.yml (see the plan's design note) and does not touch test.yml or deploy.yml." \
  --base main
```

- [ ] **Step 4: Verify the PR's checks**

```bash
gh pr checks --watch
```
Expected: `security / secret-scan` and `security / dependency-audit` both pass (ARIA's `pnpm audit --audit-level=high` should be clean — if it's not, that's a real finding, not a framework bug; report it, do not silently weaken the audit level to make it pass). ARIA's own pre-existing `tests` workflow (all 6 jobs) should ALSO run on this PR and pass, completely independently — confirm this too, since it's the proof that adding the new workflow didn't perturb the existing one.

- [ ] **Step 5: Confirm `deploy.yml` is genuinely unaffected — do not just assume it**

This is the one verification step in this entire plan with real production stakes. Before merging:
```bash
gh run list --repo Z0lGi4/ARIA --workflow=deploy.yml --limit 5 --json databaseId,event,conclusion,createdAt
```
Record the current state. After Step 6 merges, re-check:
```bash
gh run list --repo Z0lGi4/ARIA --workflow=deploy.yml --limit 5 --json databaseId,event,conclusion,createdAt
```
Expected: exactly one new `deploy.yml` run appears, triggered by the SAME mechanism as always (`workflow_run` off `tests` completing) — not two, not zero, not triggered by anything new. If a second/duplicate deploy run appears, or `deploy.yml` fails to trigger at all, STOP — do not proceed to Task 2's completion, escalate this as a Critical finding regardless of what round of review this is.

- [ ] **Step 6: Merge the PR, then verify deploy behavior per Step 5's plan**

```bash
gh pr merge --squash --delete-branch
```
Wait for the merge-triggered `tests` run to complete (`gh run watch` on it), then perform the Step 5 deploy-trigger check. Report the actual `deploy.yml` run ID that fired, its trigger event, and its conclusion in your report — this is the load-bearing evidence for this task.

- [ ] **Step 7: Do NOT add branch protection in this task**

ARIA's `main` has never had branch protection. Adding it now — for either the new `security` checks or ARIA's own long-standing `tests` checks — is a bigger behavioral change than "adopt two new gates" and deserves its own explicit decision, not something bundled silently into this pilot. Leave `main` unprotected; note this explicitly in your report as a deliberate omission, and flag it as an open question for the controller to raise with the project owner (should `main` require `tests` too, now that it's about to require `security`? — that's a real question, not one this task answers).

---

### Task 3: Cross-pilot report

**Files:** none — this task produces the report that informs Plan 3, not code.

- [ ] **Step 1: Summarize what the pilot proved and what it didn't**

Write a short summary (in your final report, not a new file) covering:
- Did `python-ci.yml` genuinely work end-to-end on a real repo (memory-medic), gates included?
- Did the selective-adoption pattern for a mature repo (ARIA) work without disturbing its existing pipeline?
- What, if anything, surprised you or differed from what Plan 1 assumed about how repos with existing CI would need to adapt?
- Is the "fold in whatever's missing" language in `production-framework.md` (written before this pilot) still accurate, or does it need updating based on what ARIA's case actually required (a hand-written selective workflow, not a bundled reusable-workflow call)? Recommend a specific doc change if you think one's needed — don't just flag it vaguely.
