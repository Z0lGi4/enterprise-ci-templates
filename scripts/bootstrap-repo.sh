#!/usr/bin/env bash
# Put a repo on the Enterprise Production Framework in one command.
#
#   bash scripts/bootstrap-repo.sh <owner/repo> python|node [--branch main] [--python 3.12]
#
# What it does, in this order, each step idempotent:
#   1. The CLAUDE_CODE_OAUTH_TOKEN secret, read from the environment
#   2. Branch protection: the five `ci /` checks ADDED to whatever is already
#      required, enforce_admins on; existing review rules, push restrictions,
#      linear-history and signature settings are read first and preserved
#   3. A pull request ("ci/bootstrap-framework") adding
#      .github/workflows/ci.yml (python-ci.yml@v1 or node-ci.yml@v1),
#      grouped weekly Dependabot, and ci.sh for Python repos. If that branch
#      already exists from an earlier run it is reused, never overwritten.
#
# Files go in through a PR, never a direct push: the repo's own new gates
# then review the change that adds them. Merge it once green; nothing else
# can land before it.
#
# A repo whose coverage is under 80% will be red after this. That is the
# point: the bar is fixed, the tests come up to it. See README.md.
set -euo pipefail

usage() { echo "usage: bootstrap-repo.sh <owner/repo> python|node [--branch main] [--python 3.12]" >&2; exit 2; }
REPO="${1:-}"; KIND="${2:-}"; [ -n "$REPO" ] && [ -n "$KIND" ] || usage
shift 2
BRANCH=""; PYVER="3.12"
while [ $# -gt 0 ]; do
  case "$1" in
    --branch) BRANCH="$2"; shift 2 ;;
    --python) PYVER="$2"; shift 2 ;;
    *) usage ;;
  esac
done
case "$KIND" in python|node) ;; *) usage ;; esac
[ -n "$BRANCH" ] || BRANCH="$(gh api "repos/$REPO" -q .default_branch)"
if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  echo "CLAUDE_CODE_OAUTH_TOKEN is not set; the review gate would fail closed on every PR." >&2
  echo "Run 'claude setup-token', export the value, then re-run." >&2
  exit 1
fi
HERE="$(cd "$(dirname "$0")/.." && pwd)"

# ---------------------------------------------------------------- 1. secret
printf '%s' "$CLAUDE_CODE_OAUTH_TOKEN" | gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo "$REPO"
echo "secret set on $REPO"

# ------------------------------------------------------ 2. branch protection
# The protection endpoint is a full replace, so the current rules are read
# and carried over; only the required contexts grow and enforce_admins is set.
CURRENT="$(gh api "repos/$REPO/branches/$BRANCH/protection" 2>/dev/null || echo '{}')"
PAYLOAD="$(printf '%s' "$CURRENT" | python3 -c '
import json, sys
cur = json.load(sys.stdin)
want = ["ci / lint", "ci / test", "ci / secret-scan", "ci / dependency-audit", "ci / review-agent"]
rsc = cur.get("required_status_checks") or {}
contexts = list(dict.fromkeys((rsc.get("contexts") or []) + want))
reviews = cur.get("required_pull_request_reviews")
if reviews:
    reviews = {
        "dismiss_stale_reviews": reviews.get("dismiss_stale_reviews", False),
        "require_code_owner_reviews": reviews.get("require_code_owner_reviews", False),
        "required_approving_review_count": reviews.get("required_approving_review_count", 0),
        "require_last_push_approval": reviews.get("require_last_push_approval", False),
    }
restr = cur.get("restrictions")
if restr:
    restr = {"users": [u["login"] for u in restr.get("users", [])],
             "teams": [t["slug"] for t in restr.get("teams", [])],
             "apps": [a["slug"] for a in restr.get("apps", [])]}
out = {
    "required_status_checks": {"strict": bool(rsc.get("strict", False)), "contexts": contexts},
    "enforce_admins": True,
    "required_pull_request_reviews": reviews,
    "restrictions": restr,
    "required_linear_history": bool((cur.get("required_linear_history") or {}).get("enabled", False)),
    "allow_force_pushes": bool((cur.get("allow_force_pushes") or {}).get("enabled", False)),
    "allow_deletions": bool((cur.get("allow_deletions") or {}).get("enabled", False)),
    "required_conversation_resolution": bool((cur.get("required_conversation_resolution") or {}).get("enabled", False)),
}
print(json.dumps(out))
')"
printf '%s' "$PAYLOAD" | gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" --input - >/dev/null
echo "branch protection on $BRANCH: five ci / checks required (existing rules kept), enforce_admins on"

# ------------------------------------------------------------- 3. the PR
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
gh repo clone "$REPO" "$WORK/repo" -- --quiet --branch "$BRANCH"
cd "$WORK/repo"
PRBRANCH=ci/bootstrap-framework
if git ls-remote --exit-code --heads origin "$PRBRANCH" >/dev/null 2>&1; then
  git fetch --quiet origin "$PRBRANCH"
  git checkout -q -B "$PRBRANCH" "origin/$PRBRANCH"
  echo "reusing existing branch $PRBRANCH"
else
  git checkout -q -b "$PRBRANCH"
fi

mkdir -p .github/workflows
if [ ! -f .github/workflows/ci.yml ]; then
  cat > .github/workflows/ci.yml <<EOF
# Enterprise Production Framework — https://github.com/Z0lGi4/enterprise-ci-templates
# lint, tests with the 80% coverage gate (whole project and changed lines),
# secret scan, dependency audit, structured LLM review. Pinned to @v1, the
# framework's own release tag (first-party: same owner, same trust boundary
# as this file); the templates' release script moves it deliberately.
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
# The framework's own @v1 ref is ignored: it is moved by the templates'
# release script, and Dependabot cannot read that private repo anyway.
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
    ignore:
      - dependency-name: "Z0lGi4/enterprise-ci-templates*"
EOF
  echo "added .github/dependabot.yml"
fi

if [ "$KIND" = python ] && [ ! -f ci.sh ]; then
  cp "$HERE/scripts/ci.sh" ci.sh
  echo "added ci.sh"
fi

if [ -z "$(git status --porcelain)" ]; then
  echo "nothing new to add"
else
  git add -A
  git commit -q -m "ci: adopt the Enterprise Production Framework

Lint, tests with the 80% coverage gate (whole project and changed lines),
secret scan, dependency audit and the structured review gate, all from
Z0lGi4/enterprise-ci-templates@v1."
  git push -q -u origin "$PRBRANCH"
fi
if [ -z "$(gh pr list -R "$REPO" --head "$PRBRANCH" --json number -q '.[].number')" ]; then
  gh pr create -R "$REPO" -B "$BRANCH" -H "$PRBRANCH" \
    -t "ci: adopt the Enterprise Production Framework" \
    -b "Adds the framework caller (\`@v1\`), grouped weekly Dependabot$( [ "$KIND" = python ] && echo ', and a local `ci.sh`' ). Branch protection now requires the five \`ci /\` checks, so this PR is gated by the gates it adds."
else
  echo "bootstrap PR already open: $(gh pr list -R "$REPO" --head "$PRBRANCH" --json url -q '.[0].url')"
fi
echo
echo "Done. Merge the bootstrap PR once it is green; if coverage is under 80% it will be red until the tests come up."
