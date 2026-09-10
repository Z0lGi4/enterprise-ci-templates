# Test Fixtures

These minimal Python/Node projects exist so the reusable workflows in
`.github/workflows/` can be smoke-tested against real code via the
`Test - *` workflows, without needing a real product repo. Three
(`test-secret-scan.yml`, `test-python-ci.yml`, `test-node-ci.yml`) are
`push`-triggered only. `test-docs-sync.yml` also declares
`workflow_dispatch`, which will start working once this branch merges to
`main` (GitHub only allows manually dispatching a workflow that's already
on the default branch) — the other three would need the same trigger added
if you want that for them too, merging alone won't grant it. Keep these
fixtures — they're the regression test suite for this repo's own CI
templates. Don't delete as "unused."
