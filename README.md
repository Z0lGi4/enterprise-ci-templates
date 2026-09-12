# enterprise-ci-templates

Shared, reusable CI/CD workflows enforcing the Enterprise Production
Framework across every product repo. See
`docs/superpowers/specs/2026-09-10-enterprise-production-framework-design.md`
for the full design and `docs/superpowers/plans/2026-09-10-enterprise-framework-core.md`
for how this was built.

## Using these workflows in your repo

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]   # or master
  pull_request:
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  ci:
    uses: Z0lGi4/enterprise-ci-templates/.github/workflows/python-ci.yml@<sha> # v1
    # or node-ci.yml for TypeScript/JavaScript repos
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

**Pass that one secret explicitly — never `secrets: inherit`.** `inherit` hands
*every* secret the repo holds (AWS deploy credentials, database passwords,
Stripe keys, encryption keys) to a workflow living in a different repository,
referenced by a mutable `@main`. This framework needs exactly one secret, on
one job. There is no upside to giving it the rest.

**No repo-settings change is needed.** Earlier revisions required raising
`default_workflow_permissions` from `read` to `write` on every adopting repo,
because `secret-scan` wrapped `gitleaks-action`, which calls
`GET /pulls/{n}/commits` and therefore needed `pull-requests: read` — and that
setting is a repo-wide *ceiling*, so GitHub refused to start the entire
`workflow_call` while it stayed `read` (a `startup_failure` with zero jobs;
seen on three repos). The scan now reads the same commit range out of the local
checkout, needs no token and no elevated scope, and every job in these
workflows asks only for `contents: read`. If you raised a repo to `write` for a
previous version of this framework, you can put it back.

Required repo secret: **`CLAUDE_CODE_OAUTH_TOKEN`** — generate with `claude setup-token`
locally (requires a Claude subscription), then `gh secret set CLAUDE_CODE_OAUTH_TOKEN`.
This is *not* `ANTHROPIC_API_KEY` — that name is not used anywhere in this repo.

The secret is declared optional at the `workflow_call` level only so that
`lint`, `test`, `secret-scan` and `dependency-audit` can run without it.
**`review-agent` fails closed**: with no token the job errors with a message
saying how to set it; with a rejected token, `claude -p`'s own error is printed.
A gate that passes when it cannot run is not a gate.

### What `review-agent` does on a PR

- Diffs the PR against its base and hands the diff to `claude -p` with a fixed
  JSON schema; read-only tools stay on so it can read the code around the
  change, write/execute tools are off.
- **Findings become inline annotations** on the PR's changed-files view
  (file and line when the model identifies them) and a step-summary table.
  CRITICAL/HIGH fail the check.
- **One retry** if a run ends without a verdict (turn budget, transient API
  error), then it fails closed with claude's own output in the log.
- **Skipped, and says so, for documentation/lockfile-only diffs** (`*.md`,
  `*.rst`, `*.txt`, `LICENSE`, `CHANGELOG` — lockfiles are reviewed: a
  dependency bump is a supply-chain change). The list is fixed in
  the action, never decided by the model.
- Repos with their own lint/test pipeline can call just the gate:
  `.github/workflows/review-agent.yml` (see the header of that file).

### Releasing a template change

Adopters pin the reusable workflows by **full commit SHA** (`@<sha> # v1`),
never by tag or branch: a moved ref would change what runs in every adopter
with no pull request anywhere. After a merge is green here, run
`bash scripts/release.sh`: it opens a bump PR on every repo in
`scripts/adopters.txt`, each gated by that repo's own checks — including the
review-agent this repo ships. The `v1` tag is moved too, as a human-readable
marker of the current release only; nothing executes from it.

Inside the workflows, this repo's own composite actions are used from a
checkout of this repo at `github.job_workflow_sha` — the same commit the
caller pinned — so a pinned workflow can never pull a floating action.
That checkout is why this repo is public; it holds nothing secret.

Coverage is enforced twice on a PR: the whole project must stay at or above
80%, **and** the lines the PR changes must be at least 80% covered
(`diff-cover` against the PR's base branch). The second check is what stops a
large untested addition hiding behind a healthy project-wide number.

## Bootstrapping a repo in one command

```bash
bash scripts/bootstrap-repo.sh <owner>/<repo> python    # or node; --branch, --python
```
Opens the adoption PR (caller pinned to the current release SHA, grouped
Dependabot, `ci.sh`), sets the secret from `CLAUDE_CODE_OAUTH_TOKEN` in your
environment, and merges the five `ci /` checks plus `enforce_admins` into the
branch's existing protection. Idempotent. The steps below are what it does.

## Branch protection

Required status checks are the five job names, not a single `ci` check:
`ci / lint`, `ci / test`, `ci / secret-scan`, `ci / dependency-audit`,
`ci / review-agent` (adjust the `ci /` prefix to match whatever you name
the calling job in your own `.github/workflows/ci.yml`).

## Notes

- `docs-sync.yml` (LLM-regenerated docs, auto-merged) was removed on
  2026-09-11. It was the only workflow needing `pull-requests: write` and the
  repo-wide `write` ceiling; nothing adopted it, and docs stay a human's job.

- Third-party actions are pinned to commit SHAs, not mutable tags — update
  deliberately, not automatically.
  This repo's own composite actions are used from a checkout of this repo
  at `github.job_workflow_sha`, the commit the caller pinned, so nothing in
  the chain is a floating ref.
  Automated supply-chain scanners flag it as "third-party action unpinned";
  it is first-party, same owner, same trust boundary as the workflow calling
  it. Pin it to a SHA only if this repo ever stops being ours.
- If a rollout target repo is owned by a GitHub Organization (not a personal
  account), gitleaks-action v2 requires a `GITLEAKS_LICENSE` secret (free
  tier covers personal accounts and public repos only).
