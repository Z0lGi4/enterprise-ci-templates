#!/usr/bin/env bash
# Local mirror of the CI gates. Run before pushing: same commands, same
# thresholds, three minutes sooner than the pull request will tell you.
#
#   bash ci.sh            # diff coverage against origin/<default branch>
#   bash ci.sh main       # ...or against a branch you name
#
# Repo-specific setup the CI template does through `pre-test-command`
# (databases, migrations) is not reproduced here; run that first if the
# tests need it.
set -euo pipefail

# The default branch, asked of the remote rather than guessed from the clone
# (origin/HEAD is unset in most clones). No baked-in fallback: a wrong guess
# would silently compare against the wrong branch.
BASE="${1:-$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p' || true)}"
[ -n "$BASE" ] || { echo "Could not determine the default branch from origin; pass it: bash ci.sh <branch>" >&2; exit 1; }
for mod in ruff pytest_cov diff_cover; do
  python -c "import $mod" 2>/dev/null || python -m pip install --quiet ruff pytest-cov diff-cover
done

echo "== ruff"
python -m ruff check .
echo "== pytest (whole-project coverage >= 80%)"
python -m pytest --cov=. --cov-fail-under=80 --cov-report=term --cov-report=xml -q
echo "== diff-cover (changed lines >= 80% vs origin/$BASE)"
git fetch --quiet origin "$BASE"
python -m diff_cover.diff_cover_tool coverage.xml --compare-branch="origin/$BASE" --fail-under=80
echo "== all gates passed"
