#!/usr/bin/env bash
# Release the current main to every adopter.
#
# Adopters pin this repo's reusable workflows by full commit SHA (with a
# `# v1` comment), never by a tag: a moved tag would change what runs in
# every adopter's CI with no pull request anywhere. So a release is a PR
# per adopter that bumps the SHA, and each of those PRs is gated by that
# repo's own checks — including the review-agent this repo ships.
#
# The `v1` tag is still moved, purely as a human-readable marker of what
# the current release is; nothing executes from it.
#
#   bash scripts/release.sh            # after the merge is green on main
#
# Adopters are listed in scripts/adopters.txt, one `owner/repo` per line.
# One adopter failing does not stop the others; failures are listed at the
# end and the script exits non-zero. Needs only git, gh and python3.
set -euo pipefail

git fetch --quiet origin main
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
  echo "HEAD is not origin/main; check out main and pull first." >&2
  exit 1
fi
if ! gh run list --branch main --limit 6 --json conclusion --jq 'all(.[]; .conclusion == "success")' | grep -q true; then
  echo "The latest runs on main are not all green; not releasing." >&2
  gh run list --branch main --limit 6
  exit 1
fi

SHA="$(git rev-parse HEAD)"
SHORT="$(git rev-parse --short HEAD)"
git tag -f v1 >/dev/null
git push --quiet --force origin v1
echo "v1 marker -> $SHORT"

HERE="$(cd "$(dirname "$0")" && pwd)"
FAILED=()

bump_one() {
  # Called from an `if`, where bash suspends errexit for the whole function:
  # every command therefore checks itself, so a failed API call returns 1
  # instead of continuing with empty variables.
  local repo="$1" base cur new br headsha fsha err url
  base="$(gh api "repos/$repo" -q .default_branch)" || return 1
  cur="$(gh api "repos/$repo/contents/.github/workflows/ci.yml?ref=$base" -q .content | base64 -d)" || return 1
  [ -n "$cur" ] || { echo "$repo: no ci.yml on $base" >&2; return 1; }
  # A file with no framework reference is an error, not "up to date": a
  # drifted or hand-edited caller must not be reported as rolled out.
  printf '%s' "$cur" | grep -q "enterprise-ci-templates/.github/workflows/" || { echo "$repo: ci.yml has no framework reference; not an adopter in the expected shape" >&2; return 1; }
  if printf '%s' "$cur" | grep -q "@${SHA}"; then echo "$repo: already at $SHORT"; return 0; fi
  # Any existing pin of a framework workflow (SHA, tag or branch) -> this SHA.
  # `|` is the sed delimiter because the replacement contains `#`.
  new="$(printf '%s' "$cur" | sed -E "s|(Z0lGi4/enterprise-ci-templates/\.github/workflows/[a-z-]+\.yml)@[A-Za-z0-9._-]+( *# *v1)?|\1@${SHA} # v1|g")" || return 1
  [ "$new" != "$cur" ] || { echo "$repo: framework reference present but the pin pattern did not match; fix by hand" >&2; return 1; }
  # The review gate skips drafts, and ready_for_review is not a default
  # pull_request type: a bare `pull_request:` trigger gets the explicit list.
  new="$(printf '%s' "$new" | python3 "$HERE/normalize_trigger.py")" || return 1
  br="ci/framework-${SHORT}"
  headsha="$(gh api "repos/$repo/git/ref/heads/$base" -q .object.sha)" || return 1
  err="$(mktemp)" || return 1
  if ! gh api -X POST "repos/$repo/git/refs" -f ref="refs/heads/$br" -f sha="$headsha" >/dev/null 2>"$err"; then
    if ! grep -q "Reference already exists" "$err"; then cat "$err" >&2; rm -f "$err"; return 1; fi
  fi
  rm -f "$err"
  fsha="$(gh api "repos/$repo/contents/.github/workflows/ci.yml?ref=$br" -q .sha)" || return 1
  # `$(...)` stripped the file's final newline; put it back.
  gh api -X PUT "repos/$repo/contents/.github/workflows/ci.yml" -f message="ci: framework ${SHORT}" -f branch="$br" -f sha="$fsha" -f content="$(printf '%s\n' "$new" | base64 -w0)" >/dev/null || return 1
  url="$(gh pr list -R "$repo" --head "$br" --state open --json url -q '.[0].url')" || return 1
  if [ -z "$url" ]; then
    url="$(gh pr create -R "$repo" -B "$base" -H "$br" -t "ci: framework ${SHORT}"       -b "Pins the framework at enterprise-ci-templates@${SHA} (v1). Changes: https://github.com/Z0lGi4/enterprise-ci-templates/commits/main")" || return 1
  fi
  echo "$repo: $url"
}

while IFS= read -r repo; do
  repo="${repo%$'\r'}"   # a CRLF checkout must not put \r in the URL
  [ -n "$repo" ] && [ "${repo#\#}" = "$repo" ] || continue
  if ! bump_one "$repo"; then FAILED+=("$repo"); fi
done < "$HERE/adopters.txt"

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "FAILED: ${FAILED[*]}" >&2
  exit 1
fi
