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
while IFS= read -r repo; do
  [ -n "$repo" ] && [ "${repo#\#}" = "$repo" ] || continue
  BASE="$(gh api "repos/$repo" -q .default_branch)"
  CUR="$(gh api "repos/$repo/contents/.github/workflows/ci.yml?ref=$BASE" -q .content 2>/dev/null | base64 -d || true)"
  if [ -z "$CUR" ]; then echo "$repo: no ci.yml on $BASE, skipped"; continue; fi
  # Any existing pin of a framework workflow, by SHA, tag or branch -> this SHA.
  NEW="$(printf '%s' "$CUR" | sed -E "s#(Z0lGi4/enterprise-ci-templates/\.github/workflows/[a-z-]+\.yml)@[A-Za-z0-9._-]+( *# *v1)?#\1@${SHA} # v1#g")"
  if [ "$NEW" = "$CUR" ]; then echo "$repo: already at $SHORT"; continue; fi
  BR="ci/framework-${SHORT}"
  HEADSHA="$(gh api "repos/$repo/git/ref/heads/$BASE" -q .object.sha)"
  gh api -X POST "repos/$repo/git/refs" -f ref="refs/heads/$BR" -f sha="$HEADSHA" >/dev/null 2>&1 || true
  FSHA="$(gh api "repos/$repo/contents/.github/workflows/ci.yml?ref=$BR" -q .sha)"
  printf '%s' "$NEW" | base64 -w0 | jq -Rn --arg m "ci: framework ${SHORT}" --arg b "$BR" --arg s "$FSHA" '{message:$m, branch:$b, sha:$s, content:input}' \
    | gh api -X PUT "repos/$repo/contents/.github/workflows/ci.yml" --input - >/dev/null
  URL="$(gh pr create -R "$repo" -B "$BASE" -H "$BR" -t "ci: framework ${SHORT}" \
    -b "Pins the framework at enterprise-ci-templates@${SHA} (v1). Changes since the previous pin: https://github.com/Z0lGi4/enterprise-ci-templates/commits/main" 2>/dev/null \
    || gh pr list -R "$repo" --head "$BR" --json url -q '.[0].url')"
  echo "$repo: $URL"
done < "$HERE/adopters.txt"
