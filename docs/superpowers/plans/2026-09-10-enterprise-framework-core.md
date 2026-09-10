# Enterprise Framework Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the reusable CI/CD workflows (Python + Node), the shared secret-scan action, the auto-docs workflow, and the global rule file that together define the Enterprise Production Framework — proven working in isolation via smoke tests, before any real product repo depends on them.

**Architecture:** Everything lives in `Z0lGi4/enterprise-ci-templates` as `workflow_call` reusable workflows plus one composite action, so any product repo can adopt them with a 6-line caller file. Each reusable workflow is validated inside this same repo first, via a minimal fixture project + a `workflow_dispatch` caller workflow that exercises it end-to-end — this is the closest equivalent to "write the failing test first" for CI configuration: the caller + fixture are written to prove a specific gate fails/passes before the gate logic exists.

**Tech Stack:** GitHub Actions (`workflow_call` reusable workflows, composite actions), `ruff` + `pytest-cov` + `pip-audit` (Python gates), `eslint` + `tsc` + `vitest` + `pnpm audit` (Node gates), `gitleaks` (secret scan), Claude Code CLI (`claude -p`, review-agent + doc regeneration), Playwright headless Chromium (HTML→PDF).

**Spec:** `docs/superpowers/specs/2026-09-10-enterprise-production-framework-design.md` (this repo, commit `264c592`)

## Global Constraints

- Coverage gate is **80%** on changed code — exact number from the spec (§3), itself sourced from the existing global `testing.md` standard. Do not use a different number.
- The review-agent gate (§3, stage 5) fails the build on **CRITICAL or HIGH** findings only — MEDIUM/LOW never block.
- `docs-sync.yml`'s trigger excludes `docs/**` paths (spec §5) — this is load-bearing (prevents an infinite PR loop) and must not be dropped when this workflow is later wired into product repos.
- All reusable workflows are referenced by product repos as `Z0lGi4/enterprise-ci-templates/.github/workflows/<name>.yml@main` — keep this exact repo/path shape; a later task renames nothing here without updating every caller.

---

### Task 1: Shared secret-scan composite action

**Files:**
- Create: `.github/actions/secret-scan/action.yml`
- Create: `.github/workflows/test-secret-scan.yml`
- Create: `test-fixtures/leaky-file.txt` (temporary — deleted at the end of this task)

**Interfaces:**
- Produces: a composite action callable as `uses: Z0lGi4/enterprise-ci-templates/.github/actions/secret-scan@main` (or `./.github/actions/secret-scan` for same-repo callers) — no inputs, no outputs, fails the step if gitleaks finds a match.

- [ ] **Step 1: Write a fixture file that gitleaks should catch, and the test caller workflow**

```yaml
# .github/workflows/test-secret-scan.yml
name: Test - Secret Scan
on: workflow_dispatch
jobs:
  should-fail:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/secret-scan
```

```txt
# test-fixtures/leaky-file.txt
AWS_SECRET_ACCESS_KEY=AKIAIOSFODNN7EXAMPLE
```

- [ ] **Step 2: Commit and push, then trigger the workflow to confirm it fails (action doesn't exist yet)**

```bash
git add .github/workflows/test-secret-scan.yml test-fixtures/leaky-file.txt
git commit -m "test: add secret-scan smoke test (expected to fail, no action yet)"
git push origin main
gh workflow run "Test - Secret Scan"
```

Wait ~10s, then: `gh run list --workflow="Test - Secret Scan" --limit 1`
Expected: run status `failure` (the action doesn't exist at `./.github/actions/secret-scan`)

- [ ] **Step 3: Write the composite action**

```yaml
# .github/actions/secret-scan/action.yml
name: 'Secret Scan'
description: 'Fail the job if gitleaks finds a committed secret'
runs:
  using: 'composite'
  steps:
    - name: Run gitleaks
      uses: gitleaks/gitleaks-action@v2
      env:
        GITHUB_TOKEN: ${{ github.token }}
        GITLEAKS_ENABLE_COMMENTS: 'false'
```

- [ ] **Step 4: Commit, push, re-run, confirm it now correctly fails on the leaky fixture (proving detection works)**

```bash
git add .github/actions/secret-scan/action.yml
git commit -m "feat: add secret-scan composite action"
git push origin main
gh workflow run "Test - Secret Scan"
```

Wait ~15s, then: `gh run list --workflow="Test - Secret Scan" --limit 1`
Expected: run status `failure` — but now failing because gitleaks *found* `test-fixtures/leaky-file.txt`, not because the action was missing. Confirm via `gh run view <run-id> --log | grep -i "leaky-file"`.

- [ ] **Step 5: Remove the leaky fixture, confirm the workflow now passes clean, commit**

```bash
git rm test-fixtures/leaky-file.txt
git commit -m "test: remove secret-scan fixture after verifying detection"
git push origin main
gh workflow run "Test - Secret Scan"
```

Wait ~15s, then: `gh run list --workflow="Test - Secret Scan" --limit 1`
Expected: run status `success`

---

### Task 2: `python-ci.yml` reusable workflow

**Files:**
- Create: `.github/workflows/python-ci.yml`
- Create: `test-fixtures/python-sample/pyproject.toml`
- Create: `test-fixtures/python-sample/src/sample/__init__.py`
- Create: `test-fixtures/python-sample/src/sample/greet.py`
- Create: `test-fixtures/python-sample/tests/test_greet.py`
- Create: `.github/workflows/test-python-ci.yml`

**Interfaces:**
- Consumes: `secret-scan` composite action from Task 1 (`./.github/actions/secret-scan`)
- Produces: `python-ci.yml` callable as `uses: Z0lGi4/enterprise-ci-templates/.github/workflows/python-ci.yml@main` with inputs `python-version` (string, default `'3.12'`) and `working-directory` (string, default `'.'`), and required secret `ANTHROPIC_API_KEY`. Runs four jobs: `lint`, `test`, `secret-scan`, `dependency-audit` on every call; a fifth job `review-agent` runs only `if: github.event_name == 'pull_request'`.

- [ ] **Step 1: Write a minimal real Python package as the test fixture**

```toml
# test-fixtures/python-sample/pyproject.toml
[build-system]
requires = ["setuptools>=77"]
build-backend = "setuptools.build_meta"

[project]
name = "sample"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = []

[project.optional-dependencies]
dev = ["pytest>=8", "pytest-cov>=5"]

[tool.setuptools.packages.find]
where = ["src"]

[tool.pytest.ini_options]
testpaths = ["tests"]
pythonpath = ["src"]
```

```python
# test-fixtures/python-sample/src/sample/__init__.py
```

```python
# test-fixtures/python-sample/src/sample/greet.py
def greet(name: str) -> str:
    return f"Hello, {name}!"
```

```python
# test-fixtures/python-sample/tests/test_greet.py
from sample.greet import greet


def test_greet():
    assert greet("world") == "Hello, world!"
```

- [ ] **Step 2: Write the test caller workflow and confirm it fails (python-ci.yml doesn't exist yet)**

```yaml
# .github/workflows/test-python-ci.yml
name: Test - Python CI
on: workflow_dispatch
jobs:
  call-python-ci:
    uses: ./.github/workflows/python-ci.yml
    with:
      working-directory: test-fixtures/python-sample
    secrets: inherit
```

```bash
git add test-fixtures/python-sample .github/workflows/test-python-ci.yml
git commit -m "test: add python-ci smoke test fixture (expected to fail, no workflow yet)"
git push origin main
gh workflow run "Test - Python CI"
```

Wait ~10s: `gh run list --workflow="Test - Python CI" --limit 1`
Expected: run status `failure` (workflow file referenced doesn't exist)

- [ ] **Step 3: Write `python-ci.yml`**

```yaml
# .github/workflows/python-ci.yml
name: Python CI (reusable)
on:
  workflow_call:
    inputs:
      python-version:
        type: string
        default: '3.12'
      working-directory:
        type: string
        default: '.'
    secrets:
      ANTHROPIC_API_KEY:
        required: true

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ inputs.python-version }}
      - run: pip install ruff
      - run: ruff check .
        working-directory: ${{ inputs.working-directory }}

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ inputs.python-version }}
      - name: Install project (editable, with dev extras)
        working-directory: ${{ inputs.working-directory }}
        run: |
          pip install -e ".[dev]" 2>/dev/null || pip install -e . pytest pytest-cov
          [ -f requirements.txt ] && pip install -r requirements.txt || true
      - name: Run tests with 80% coverage gate
        working-directory: ${{ inputs.working-directory }}
        run: pytest --cov=. --cov-fail-under=80

  secret-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: Z0lGi4/enterprise-ci-templates/.github/actions/secret-scan@main

  dependency-audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ inputs.python-version }}
      - run: pip install pip-audit
      - name: Audit dependencies
        working-directory: ${{ inputs.working-directory }}
        run: |
          if [ -f requirements.txt ]; then pip-audit -r requirements.txt; else pip-audit --local || true; fi

  review-agent:
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - name: Install Claude Code
        run: npm install -g @anthropic-ai/claude-code
      - name: Get PR diff
        run: git diff origin/${{ github.base_ref }}...HEAD > /tmp/pr.diff
      - name: Structured review
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          claude -p "Review this diff for correctness, security, and quality issues. List every real issue you find." \
            --output-format json \
            --json-schema '{"type":"object","properties":{"findings":{"type":"array","items":{"type":"object","properties":{"severity":{"type":"string","enum":["CRITICAL","HIGH","MEDIUM","LOW"]},"summary":{"type":"string"}},"required":["severity","summary"]}}},"required":["findings"]}' \
            --max-turns 5 < /tmp/pr.diff > /tmp/review.json
      - name: Fail on CRITICAL/HIGH findings
        run: |
          python3 - <<'PYEOF'
          import json, sys
          with open('/tmp/review.json') as f:
              data = json.load(f)
          findings = data.get('structured_output', {}).get('findings', [])
          blocking = [x for x in findings if x.get('severity') in ('CRITICAL', 'HIGH')]
          for x in blocking:
              print(f"::error::{x['severity']}: {x['summary']}")
          if blocking:
              sys.exit(1)
          print(f"Review passed ({len(findings)} findings, none blocking)")
          PYEOF
```

- [ ] **Step 4: Commit, push, re-run, confirm all four always-on jobs pass (the `review-agent` job is skipped — `workflow_dispatch` isn't a `pull_request` event, which is expected and correct per the `if:` condition)**

```bash
git add .github/workflows/python-ci.yml
git commit -m "feat: add python-ci.yml reusable workflow"
git push origin main
gh workflow run "Test - Python CI"
```

Wait ~30s: `gh run list --workflow="Test - Python CI" --limit 1`
Expected: run status `success`, with `lint`, `test`, `secret-scan`, `dependency-audit` jobs completed and `review-agent` skipped.

**Known gap, deliberately deferred:** `workflow_dispatch` has no `pull_request` context, so this smoke test cannot exercise the `review-agent` job's actual pass/fail behavior — only that it's correctly skipped outside a PR. The review-agent gate's real end-to-end validation (does it actually catch a CRITICAL-severity issue and block merge?) happens in the pilot plan, against a real PR on memory-medic, where `ANTHROPIC_API_KEY` is a real configured secret and a real diff exists to review.

- [ ] **Step 5: Prove the coverage gate actually blocks — add an uncovered function, confirm failure, then revert**

```python
# test-fixtures/python-sample/src/sample/greet.py  (temporary addition)
def farewell(name: str) -> str:
    return f"Goodbye, {name}!"
```

```bash
git add test-fixtures/python-sample/src/sample/greet.py
git commit -m "test: temporarily add uncovered function to prove coverage gate blocks"
git push origin main
gh workflow run "Test - Python CI"
```

Wait ~30s: `gh run list --workflow="Test - Python CI" --limit 1`
Expected: run status `failure`, `test` job fails on `--cov-fail-under=80`

```bash
git revert --no-edit HEAD
git push origin main
```

---

### Task 3: `node-ci.yml` reusable workflow

**Files:**
- Create: `.github/workflows/node-ci.yml`
- Create: `test-fixtures/node-sample/package.json`
- Create: `test-fixtures/node-sample/tsconfig.json`
- Create: `test-fixtures/node-sample/src/greet.ts`
- Create: `test-fixtures/node-sample/src/greet.test.ts`
- Create: `.github/workflows/test-node-ci.yml`

**Interfaces:**
- Consumes: `secret-scan` composite action from Task 1
- Produces: `node-ci.yml` callable as `uses: Z0lGi4/enterprise-ci-templates/.github/workflows/node-ci.yml@main` with inputs `node-version` (string, default `'22'`) and `working-directory` (string, default `'.'`), required secret `ANTHROPIC_API_KEY`. Same five jobs as `python-ci.yml`: `lint`, `test`, `secret-scan`, `dependency-audit`, `review-agent` (PR-only).

- [ ] **Step 1: Write a minimal real TypeScript package as the test fixture**

```json
// test-fixtures/node-sample/package.json
{
  "name": "sample",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "lint": "eslint . && tsc --noEmit",
    "test": "vitest run --coverage"
  },
  "devDependencies": {
    "@vitest/coverage-v8": "^2.0.0",
    "eslint": "^9.0.0",
    "typescript": "^5.5.0",
    "vitest": "^2.0.0"
  }
}
```

```json
// test-fixtures/node-sample/tsconfig.json
{
  "compilerOptions": {
    "strict": true,
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "bundler",
    "noEmit": true
  },
  "include": ["src"]
}
```

```typescript
// test-fixtures/node-sample/src/greet.ts
export function greet(name: string): string {
  return `Hello, ${name}!`;
}
```

```typescript
// test-fixtures/node-sample/src/greet.test.ts
import { describe, it, expect } from 'vitest';
import { greet } from './greet';

describe('greet', () => {
  it('greets by name', () => {
    expect(greet('world')).toBe('Hello, world!');
  });
});
```

- [ ] **Step 2: Write the test caller workflow and confirm it fails (node-ci.yml doesn't exist yet)**

```yaml
# .github/workflows/test-node-ci.yml
name: Test - Node CI
on: workflow_dispatch
jobs:
  call-node-ci:
    uses: ./.github/workflows/node-ci.yml
    with:
      working-directory: test-fixtures/node-sample
    secrets: inherit
```

```bash
git add test-fixtures/node-sample .github/workflows/test-node-ci.yml
git commit -m "test: add node-ci smoke test fixture (expected to fail, no workflow yet)"
git push origin main
gh workflow run "Test - Node CI"
```

Wait ~10s: `gh run list --workflow="Test - Node CI" --limit 1`
Expected: run status `failure`

- [ ] **Step 3: Write `node-ci.yml`**

```yaml
# .github/workflows/node-ci.yml
name: Node CI (reusable)
on:
  workflow_call:
    inputs:
      node-version:
        type: string
        default: '22'
      working-directory:
        type: string
        default: '.'
    secrets:
      ANTHROPIC_API_KEY:
        required: true

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ inputs.node-version }}
      - working-directory: ${{ inputs.working-directory }}
        run: |
          corepack enable
          [ -f pnpm-lock.yaml ] && pnpm install --frozen-lockfile || npm install
      - working-directory: ${{ inputs.working-directory }}
        run: npm run lint --if-present

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ inputs.node-version }}
      - working-directory: ${{ inputs.working-directory }}
        run: |
          corepack enable
          [ -f pnpm-lock.yaml ] && pnpm install --frozen-lockfile || npm install
      - name: Run tests with 80% coverage gate
        working-directory: ${{ inputs.working-directory }}
        run: npm test -- --coverage.thresholds.lines=80 --coverage.thresholds.statements=80

  secret-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: Z0lGi4/enterprise-ci-templates/.github/actions/secret-scan@main

  dependency-audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ inputs.node-version }}
      - working-directory: ${{ inputs.working-directory }}
        run: |
          corepack enable
          [ -f pnpm-lock.yaml ] && pnpm audit --audit-level=high || npm audit --audit-level=high

  review-agent:
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - name: Install Claude Code
        run: npm install -g @anthropic-ai/claude-code
      - name: Get PR diff
        run: git diff origin/${{ github.base_ref }}...HEAD > /tmp/pr.diff
      - name: Structured review
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          claude -p "Review this diff for correctness, security, and quality issues. List every real issue you find." \
            --output-format json \
            --json-schema '{"type":"object","properties":{"findings":{"type":"array","items":{"type":"object","properties":{"severity":{"type":"string","enum":["CRITICAL","HIGH","MEDIUM","LOW"]},"summary":{"type":"string"}},"required":["severity","summary"]}}},"required":["findings"]}' \
            --max-turns 5 < /tmp/pr.diff > /tmp/review.json
      - name: Fail on CRITICAL/HIGH findings
        run: |
          python3 - <<'PYEOF'
          import json, sys
          with open('/tmp/review.json') as f:
              data = json.load(f)
          findings = data.get('structured_output', {}).get('findings', [])
          blocking = [x for x in findings if x.get('severity') in ('CRITICAL', 'HIGH')]
          for x in blocking:
              print(f"::error::{x['severity']}: {x['summary']}")
          if blocking:
              sys.exit(1)
          print(f"Review passed ({len(findings)} findings, none blocking)")
          PYEOF
```

- [ ] **Step 4: Commit, push, re-run, confirm all four always-on jobs pass**

```bash
git add .github/workflows/node-ci.yml
git commit -m "feat: add node-ci.yml reusable workflow"
git push origin main
gh workflow run "Test - Node CI"
```

Wait ~45s (npm installs take longer than pip): `gh run list --workflow="Test - Node CI" --limit 1`
Expected: run status `success`, `review-agent` skipped (not a `pull_request` event)

**Same known gap as Task 2:** real review-agent pass/fail validation happens against a real PR in the pilot plan (ARIA), not here.

- [ ] **Step 5: Prove the coverage gate blocks — add an uncovered function, confirm failure, then revert**

```typescript
// test-fixtures/node-sample/src/greet.ts (temporary addition)
export function farewell(name: string): string {
  return `Goodbye, ${name}!`;
}
```

```bash
git add test-fixtures/node-sample/src/greet.ts
git commit -m "test: temporarily add uncovered function to prove coverage gate blocks"
git push origin main
gh workflow run "Test - Node CI"
```

Wait ~45s: `gh run list --workflow="Test - Node CI" --limit 1`
Expected: run status `failure`, `test` job fails on the coverage threshold

```bash
git revert --no-edit HEAD
git push origin main
```

---

### Task 4: `docs-sync.yml` reusable workflow

**Files:**
- Create: `.github/workflows/docs-sync.yml`
- Create: `.github/workflows/test-docs-sync.yml`
- Modify: `test-fixtures/python-sample/` (used as the target for doc regeneration in the smoke test — no structural changes, just the checkout target)

**Interfaces:**
- Produces: `docs-sync.yml` callable as `uses: Z0lGi4/enterprise-ci-templates/.github/workflows/docs-sync.yml@main`, required secret `ANTHROPIC_API_KEY`. Regenerates `docs/TECHNICAL_OVERVIEW.md` and `docs/deck.html`/`docs/deck.pdf` at the repo root of whichever repo calls it, opens a PR labeled `automated-docs`, auto-merges once its own (lint-only, no review-agent) checks pass.
- Note for later plans (pilot/rollout): the **per-repo caller** that triggers this on push-to-main with the `docs/**` path-ignore filter (spec §5) is wired in when this workflow is adopted by a real repo — not part of this task, which only proves the reusable workflow itself works via `workflow_dispatch`.

- [ ] **Step 1: Write the test caller workflow and confirm it fails (docs-sync.yml doesn't exist yet)**

```yaml
# .github/workflows/test-docs-sync.yml
name: Test - Docs Sync
on: workflow_dispatch
jobs:
  call-docs-sync:
    uses: ./.github/workflows/docs-sync.yml
    secrets: inherit
```

```bash
git add .github/workflows/test-docs-sync.yml
git commit -m "test: add docs-sync smoke test caller (expected to fail, no workflow yet)"
git push origin main
gh workflow run "Test - Docs Sync"
```

Wait ~10s: `gh run list --workflow="Test - Docs Sync" --limit 1`
Expected: run status `failure`

- [ ] **Step 2: Write `docs-sync.yml`**

```yaml
# .github/workflows/docs-sync.yml
name: Docs Sync (reusable)
on:
  workflow_call:
    secrets:
      ANTHROPIC_API_KEY:
        required: true

jobs:
  regenerate:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: actions/setup-node@v4
        with: { node-version: '22' }
      - name: Install Claude Code
        run: npm install -g @anthropic-ai/claude-code
      - name: Regenerate technical overview
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          mkdir -p docs
          claude -p "Write or overwrite docs/TECHNICAL_OVERVIEW.md to accurately describe the current state of this codebase: architecture, tech stack, key components, and API surface. Base it only on what you actually find in the repository." \
            --allowedTools "Read,Write,Glob,Grep" --max-turns 15
      - name: Regenerate slide deck HTML
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          claude -p "Write or overwrite docs/deck.html as a concise, self-contained HTML slide deck (inline CSS, no external assets, no network requests) covering: what this product is, its architecture, and current status. Base it only on what you actually find in the repository." \
            --allowedTools "Read,Write,Glob,Grep" --max-turns 15
      - name: Render deck.html to deck.pdf
        run: |
          npx --yes playwright install --with-deps chromium
          node -e "
          const { chromium } = require('playwright');
          (async () => {
            const browser = await chromium.launch();
            const page = await browser.newPage();
            await page.goto('file://' + process.cwd() + '/docs/deck.html');
            await page.pdf({ path: 'docs/deck.pdf', format: 'A4', printBackground: true });
            await browser.close();
          })();
          "
      - name: Open automated-docs PR
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          git config user.name "docs-sync-bot"
          git config user.email "docs-sync-bot@users.noreply.github.com"
          if git diff --quiet -- docs/TECHNICAL_OVERVIEW.md docs/deck.html docs/deck.pdf 2>/dev/null; then
            echo "No doc changes, skipping PR"
            exit 0
          fi
          BRANCH="automated-docs-${{ github.run_id }}"
          git checkout -b "$BRANCH"
          git add docs/TECHNICAL_OVERVIEW.md docs/deck.html docs/deck.pdf
          git commit -m "docs: auto-regenerate technical overview and slide deck"
          git push origin "$BRANCH"
          gh pr create --title "docs: auto-regenerate technical overview and slide deck" \
            --body "Automated by docs-sync.yml." \
            --label "automated-docs" \
            --base main --head "$BRANCH"
          gh pr merge "$BRANCH" --auto --squash
```

- [ ] **Step 3: Commit, push, re-run, confirm it succeeds and opens a real PR against this repo**

```bash
git add .github/workflows/docs-sync.yml
git commit -m "feat: add docs-sync.yml reusable workflow"
git push origin main
gh workflow run "Test - Docs Sync"
```

Wait ~60s: `gh run list --workflow="Test - Docs Sync" --limit 1`
Expected: run status `success`

```bash
gh pr list --label automated-docs
```
Expected: one open (or already auto-merged) PR titled "docs: auto-regenerate technical overview and slide deck", containing `docs/TECHNICAL_OVERVIEW.md`, `docs/deck.html`, `docs/deck.pdf` for **this** repo (`enterprise-ci-templates` itself).

- [ ] **Step 4: If the PR auto-merged, pull main; verify the generated files landed and look reasonable**

```bash
git checkout main && git pull origin main
cat docs/TECHNICAL_OVERVIEW.md | head -30
ls -la docs/deck.html docs/deck.pdf
```
Expected: `TECHNICAL_OVERVIEW.md` describes this repo's actual purpose (reusable CI templates); `deck.html`/`deck.pdf` exist and are non-trivial in size (deck.pdf > 10KB).

---

### Task 5: Global rule file + cross-references

**Files:**
- Create: `~/.claude/rules/ecc/common/production-framework.md`
- Modify: `~/.claude/rules/ecc/common/code-review.md`
- Modify: `~/.claude/rules/ecc/common/testing.md`
- Modify: `~/.claude/rules/ecc/common/git-workflow.md`

**Interfaces:** none (documentation only, not code) — this task has no automated test; verification is a manual read-through in Step 3.

Note: `~/.claude` is **not** a git repository (verified — `git status` there returns "not a git repository"), so this task has no commit step. Write the files directly.

- [ ] **Step 1: Write the rule file**

```markdown
<!-- ~/.claude/rules/ecc/common/production-framework.md -->
# Enterprise Production Framework

## What every repo gets

Every product repo — regardless of maturity, from a week-old prototype to
a live production system — runs the same fixed bar, defined and enforced
by [`Z0lGi4/enterprise-ci-templates`](https://github.com/Z0lGi4/enterprise-ci-templates):

1. Lint (`ruff` / `eslint`+`tsc`)
2. Tests with an 80% coverage gate on changed code (same number as [testing.md](testing.md))
3. Secret scan (`gitleaks`)
4. Dependency audit (`pip-audit` / `pnpm audit`), failing on known high/critical CVEs
5. An automated review-agent gate (`claude -p`, structured JSON findings) that
   blocks the merge on any CRITICAL or HIGH finding — see [code-review.md](code-review.md)
   for the same severity vocabulary

Full design: `docs/superpowers/specs/2026-09-10-enterprise-production-framework-design.md`
in that repo.

## Bootstrapping a new repo

Before the first real feature lands in a new repo:

1. Add `.github/workflows/ci.yml`:
   ```yaml
   name: CI
   on: [push, pull_request]
   jobs:
     ci:
       uses: Z0lGi4/enterprise-ci-templates/.github/workflows/python-ci.yml@main
       # or node-ci.yml
       secrets: inherit
   ```
2. Add branch protection on `main` requiring that `ci` check.
3. Add `.github/workflows/docs-trigger.yml` calling `docs-sync.yml` on push to
   `main`, path-ignoring `docs/**` (prevents the auto-merge loop — see the spec, §5).

## Existing repos with their own CI

Don't rip out what's already there. Fold in whichever of the 5 gates above
are missing — most commonly the review-agent gate and the coverage
threshold, since lint/test pipelines already exist in several repos.
```

- [ ] **Step 2: Add the cross-reference lines to the three existing rule files**

In `code-review.md`, under its "Integration with Other Rules" section, add:
```markdown
- [production-framework.md](production-framework.md) - the CI-enforced version of this checklist
```

In `testing.md`, near the top (after the "Minimum Test Coverage: 80%" heading), add:
```markdown
> Enforced in CI for every repo — see [production-framework.md](production-framework.md).
```

In `git-workflow.md`, at the end, add a new section:
```markdown
## Enterprise Production Framework

Every repo's `main` branch requires CI (lint, tests, coverage, secret scan,
dependency audit, automated review) to pass before merge. See
[production-framework.md](production-framework.md).
```

- [ ] **Step 3: Verify by reading all four files back**

```bash
cat /c/Users/Owner/.claude/rules/ecc/common/production-framework.md
grep -A1 "production-framework" /c/Users/Owner/.claude/rules/ecc/common/code-review.md
grep -B1 "production-framework" /c/Users/Owner/.claude/rules/ecc/common/testing.md
grep -A3 "Enterprise Production Framework" /c/Users/Owner/.claude/rules/ecc/common/git-workflow.md
```
Expected: all four greps return the lines just added, no typos in the relative links.

---

### Task 6: Clean up smoke-test scaffolding

The `test-*.yml` workflows and `test-fixtures/` exist only to prove Tasks 1–4 work in isolation. Leave them in place — they're cheap regression protection for the template repo itself (if someone edits `python-ci.yml` later, `gh workflow run "Test - Python CI"` immediately proves it still works before any real product repo is affected). No action needed; this task exists only to document that decision so a future editor doesn't delete them as "leftover test files."

- [ ] **Step 1: Add a short README explaining this**

```markdown
<!-- test-fixtures/README.md -->
# Test Fixtures

These minimal Python/Node projects exist so the reusable workflows in
`.github/workflows/` can be smoke-tested against real code via the
`Test - *` workflows (`workflow_dispatch`-triggered), without needing a
real product repo. Keep them — they're the regression test suite for this
repo's own CI templates. Don't delete as "unused."
```

```bash
git add test-fixtures/README.md
git commit -m "docs: explain why test-fixtures/ exists"
git push origin main
```
