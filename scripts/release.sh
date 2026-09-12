#!/usr/bin/env bash
# Move the `v1` tag to the current main, which is what every adopter runs.
#
# Adopters reference this repo as `@v1`, not `@main`, so a merge here does
# not change their CI until someone runs this — a broken merge (it has
# happened: an unparseable python-ci.yml took every adopter down for ten
# minutes) stays contained to this repo's own fixture workflows.
#
# Usage: bash scripts/release.sh            # after the merge is green on main
set -euo pipefail

git fetch --quiet origin main
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
  echo "HEAD is not origin/main; check out main and pull first." >&2
  exit 1
fi

# Refuse to release something the fixtures have not proven.
if ! gh run list --branch main --limit 6 --json conclusion --jq 'all(.[]; .conclusion == "success")' | grep -q true; then
  echo "The latest runs on main are not all green; not releasing." >&2
  gh run list --branch main --limit 6
  exit 1
fi

git tag -f v1
git push --force origin v1
echo "v1 -> $(git rev-parse --short HEAD)"
