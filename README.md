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
on: [push, pull_request]
jobs:
  ci:
    uses: Z0lGi4/enterprise-ci-templates/.github/workflows/python-ci.yml@main
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

`docs-sync.yml` is the one exception: it opens and auto-merges a PR, so it
genuinely needs `pull-requests: write` and the `write` ceiling. Adopt it only
where you want that.

Required repo secret: **`CLAUDE_CODE_OAUTH_TOKEN`** — generate with `claude setup-token`
locally (requires a Claude subscription), then `gh secret set CLAUDE_CODE_OAUTH_TOKEN`.
This is *not* `ANTHROPIC_API_KEY` — that name is not used anywhere in this repo.

This secret is optional at the `workflow_call` level, by design: `lint`, `test`,
`secret-scan` and `dependency-audit` run regardless. **Without it, `review-agent`
reports success without actually reviewing anything** — a visible `::warning::`
fires (and is written to the run's step summary) on every PR, but the check
still passes. Branch protection cannot tell that apart from a clean review.
Set the secret before treating `ci / review-agent` as a meaningful gate.

## Branch protection

Required status checks are the five job names, not a single `ci` check:
`ci / lint`, `ci / test`, `ci / secret-scan`, `ci / dependency-audit`,
`ci / review-agent` (adjust the `ci /` prefix to match whatever you name
the calling job in your own `.github/workflows/ci.yml`).

## Docs auto-sync

To adopt `docs-sync.yml`, add a caller that path-ignores its own output to
avoid a self-triggering loop:
```yaml
# .github/workflows/docs-trigger.yml
name: Docs Sync
on:
  push:
    branches: [main]
    paths-ignore: ['docs/**']
jobs:
  docs-sync:
    uses: Z0lGi4/enterprise-ci-templates/.github/workflows/docs-sync.yml@main
    secrets: inherit
```

## Notes

- The `docs-sync.yml` secret-scan step runs gitleaks' default ruleset, which
  reliably catches `KEYWORD=value`-shaped secrets but does not reliably catch
  a bare credential-looking string embedded in narrative prose (verified:
  gitleaks 8.30.1's defaults did not flag a bare `AKIA...`-shaped string
  sitting in plain sentence text) — so the primary defense against a leaked
  secret in generated docs remains the `claude -p` prompt's own instruction
  to avoid secret-shaped content, not this scan. This scan is a real
  backstop, not the primary control.
- Third-party actions are pinned to commit SHAs, not mutable tags — update
  deliberately, not automatically.
  The one intentional exception is this repo's own
  `Z0lGi4/enterprise-ci-templates/.github/actions/secret-scan@main`, which
  adopters reference by branch so a fix here reaches every repo without ten
  follow-up PRs — the same reason the reusable workflows are called `@main`.
  Automated supply-chain scanners flag it as "third-party action unpinned";
  it is first-party, same owner, same trust boundary as the workflow calling
  it. Pin it to a SHA only if this repo ever stops being ours.
- If a rollout target repo is owned by a GitHub Organization (not a personal
  account), gitleaks-action v2 requires a `GITLEAKS_LICENSE` secret (free
  tier covers personal accounts and public repos only).
