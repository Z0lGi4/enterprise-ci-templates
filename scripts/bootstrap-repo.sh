#!/usr/bin/env bash
# Put a repo on the Enterprise Production Framework in one command.
#
#   bash scripts/bootstrap-repo.sh <owner/repo> python|node [--branch main] [--python 3.12]
#
# What it does, idempotently (safe to re-run on a repo that already has parts):
#   1. .github/workflows/ci.yml calling python-ci.yml@v1 or node-ci.yml@v1
#      (push to the default branch + pull_request, with concurrency)
#   2. .github/dependabot.yml, weekly, minor/patch grouped
#   3. ci.sh (Python repos): the same gates locally
#   4. The CLAUDE_CODE_OAUTH_TOKEN secret, read from the environment
#   5. Branch protection: the five `ci /` checks required, enforce_admins on
#
# Files go in through a pull request ("ci/bootstrap-framework"), never a
# direct push: the repo's own new gates then review the change that adds
# them. Protection is applied immediately, so merge that PR through the UI
# or `gh pr merge` once it is green — nothing else can land before it.
#
# A repo whose coverage is under 80% will be red after this. That is the
# point: the bar is fixed, the tests come up to it. See README.md.
set -euo pipefail

REPO="${1:?usage: bootstrap-repo.sh <owner/repo> python|node [--branch main] [--python 3.12]}"
KIND="${2:?usage: bootstrap-repo.sh <owner/repo> python|node [--branch main] [--python 3.12]}"
shift 2
BRANCH=""; PYVER="3.12"
while [ $# -gt 0 ]; do
  case "$1" in
    --branch) BRANCH="$2"; shift 2 ;;
    --python) PYVER="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
case "$KIND" in python|node) ;; *) echo "kind must be python or node" >&2; exit 2 ;; esac
[ -n "$BRANCH" ] || BRANCH="$(gh api "repos/$REPO" -q .default_branch)"
if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  echo "CLAUDE_CODE_OAUTH_TOKEN is not set; the review gate would fail closed on every PR." >&2
  echo "Run 'claude setup-token', export the value, then re-run." >&2
  exit 1
fi

HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
gh repo clone "$REPO" "$WORK/repo" -- --quiet --branch "$BRANCH"
cd "$WORK/repo"
git checkout -q -B ci/bootstrap-framework

mkdir -p .github/workflows
if [ ! -f .github/workflows/ci.yml ]; then
  cat > .github/workflows/ci.yml <<EOF
# Enterprise Production Framework — https://github.com/Z0lGi4/enterprise-ci-templates
# lint, tests with the 80% coverage gate (whole project and changed lines),
# secret scan, dependency audit, structured LLM review. Pinned to @v1; the
# templates' release script moves the tag.
name: CI
on:
  push:
    branches: [$BRANCH]
  pull_request:
concurrency:
  group: ci-\${{ github.ref }}
  cancel-in-progress: true
jobs:
  ci:
    uses: Z0lGi4/enterprise-ci-templates/.github/workflows/${KIND}-ci.yml@v1
EOF
  if [ "$KIND" = python ]; then
    printf '    with:\n      python-version: "%s"\n' "$PYVER" >> .github/workflows/ci.yml
  fi
  cat >> .github/workflows/ci.yml <<'EOF'
    secrets:
      # This one secret, explicitly. Never `secrets: inherit` into another repo.
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
EOF
  echo "added .github/workflows/ci.yml"
else
  echo "kept existing .github/workflows/ci.yml (fold the gates in by hand if it is not a framework caller)"
fi

if [ ! -f .github/dependabot.yml ]; then
  ECO=$([ "$KIND" = python ] && echo pip || echo npm)
  cat > .github/dependabot.yml <<EOF
# Minor and patch bumps arrive as one PR per ecosystem per week, so the
# review gate is spent on code, not on lockfile churn. Majors stay separate.
version: 2
updates:
  - package-ecosystem: "$ECO"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 5
    groups:
      minor-and-patch:
        update-types: ["minor", "patch"]
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 5
    groups:
      minor-and-patch:
        update-types: ["minor", "patch"]
EOF
  echo "added .github/dependabot.yml"
fi

if [ "$KIND" = python ] && [ ! -f ci.sh ]; then
  cp "$HERE/scripts/ci.sh" ci.sh
  echo "added ci.sh"
fi

if git diff --quiet && git diff --cached --quiet && [ -z "$(git status --porcelain)" ]; then
  echo "nothing to add; files already present"
else
  git add -A
  git commit -q -m "ci: adopt the Enterprise Production Framework

Lint, tests with the 80% coverage gate (whole project and changed lines),
secret scan, dependency audit and the structured review gate, all from
Z0lGi4/enterprise-ci-templates@v1."
  git push -q -u origin ci/bootstrap-framework
  gh pr create -R "$REPO" -B "$BRANCH" -H ci/bootstrap-framework \
    -t "ci: adopt the Enterprise Production Framework" \
    -b "Adds the framework caller (\`@v1\`), grouped weekly Dependabot$( [ "$KIND" = python ] && echo ', and a local `ci.sh`' ). Branch protection now requires the five \`ci /\` checks, so this PR is gated by the gates it adds." \
    || true
fi

printf '%s' "$CLAUDE_CODE_OAUTH_TOKEN" | gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo "$REPO"
echo "secret set"

gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" --input - >/dev/null <<'EOF'
{"required_status_checks":{"strict":false,"contexts":["ci / lint","ci / test","ci / secret-scan","ci / dependency-audit","ci / review-agent"]},"enforce_admins":true,"required_pull_request_reviews":null,"restrictions":null}
EOF
echo "branch protection on $BRANCH: five ci / checks required, enforce_admins on"
echo
echo "Done. Merge the bootstrap PR once it is green; if coverage is under 80% it will be red until the tests come up."
