# Test Fixtures

These minimal Python/Node projects exist so the reusable workflows in
`.github/workflows/` can be smoke-tested against real code via the
`Test - *` workflows, triggered by pushing to this branch (`push`-triggered
while this repo is pre-merge; `test-docs-sync.yml` also supports manual
`workflow_dispatch`, which will work for all four once this branch merges
to `main`), without needing a real product repo. Keep them — they're the
regression test suite for this repo's own CI templates. Don't delete as
"unused."
