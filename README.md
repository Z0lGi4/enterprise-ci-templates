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
    secrets: inherit
```

Required repo secret: **`CLAUDE_CODE_OAUTH_TOKEN`** — generate with `claude setup-token`
locally (requires a Claude subscription), then `gh secret set CLAUDE_CODE_OAUTH_TOKEN`.
This is *not* `ANTHROPIC_API_KEY` — that name is not used anywhere in this repo.

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

- Third-party actions are pinned to commit SHAs, not mutable tags — update
  deliberately, not automatically.
- If a rollout target repo is owned by a GitHub Organization (not a personal
  account), gitleaks-action v2 requires a `GITLEAKS_LICENSE` secret (free
  tier covers personal accounts and public repos only).
