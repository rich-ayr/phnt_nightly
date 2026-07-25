#!/usr/bin/env bash
#
# One-time: give the `upstream` branch a resume point.
#
# `upstream` is seeded at the last pure-headers commit of the pre-CI mirror
# history (i.e. `master` minus the README/LICENSE overlay commit), so all
# previously mirrored history is kept rather than re-derived. That commit came
# from the old filter-branch pipeline and carries no `Upstream-Commit:` trailer,
# so replay-upstream.sh has nothing to resume from.
#
# This adds a single commit with an unchanged tree whose only purpose is to
# record which upstream commit the branch corresponds to. It refuses to run
# unless the mirror tree and the upstream subtree are byte-identical, which is
# what makes the seed provably correct rather than assumed.
#
# Usage:  SEED_UPSTREAM_SHA=<sha> .github/scripts/bootstrap-upstream.sh

set -euo pipefail

UPSTREAM_URL=${UPSTREAM_URL:-https://github.com/winsiderss/systeminformer.git}
PREFIX=${PREFIX:-phnt/include}
BRANCH=${BRANCH:-upstream}
: "${SEED_UPSTREAM_SHA:?set SEED_UPSTREAM_SHA to the upstream commit the branch tip mirrors}"

say() { printf '%s\n' "$*" >&2; }

git remote get-url si >/dev/null 2>&1 && git remote set-url si "$UPSTREAM_URL" \
                                      || git remote add si "$UPSTREAM_URL"
git fetch --quiet --filter=blob:none --no-tags si master

tip=$(git rev-parse "refs/heads/$BRANCH")

if [ -n "$(git show -s --format='%(trailers:key=Upstream-Commit,valueonly)' "$tip" | tr -d '[:space:]')" ]; then
  say "$BRANCH already has a resume point; nothing to do."
  exit 0
fi

mirror_tree=$(git rev-parse "$tip^{tree}")
upstream_tree=$(git rev-parse "$SEED_UPSTREAM_SHA:$PREFIX")

if [ "$mirror_tree" != "$upstream_tree" ]; then
  say "FATAL: tree mismatch — refusing to seed."
  say "  $BRANCH tip $(git rev-parse --short "$tip") tree: $mirror_tree"
  say "  upstream ${SEED_UPSTREAM_SHA:0:12}:$PREFIX tree: $upstream_tree"
  say "Pick the upstream commit whose subtree matches the branch tip exactly."
  exit 1
fi

say "verified: $BRANCH tip and $SEED_UPSTREAM_SHA:$PREFIX are identical ($mirror_tree)"

new=$(
  printf 'chore: record upstream sync point\n\nSeeds the resume state for .github/scripts/replay-upstream.sh.\nTree is unchanged; this commit exists only to carry the trailer.\n' \
    | git interpret-trailers --trailer "Upstream-Commit=$SEED_UPSTREAM_SHA" \
    | git commit-tree "$mirror_tree" -p "$tip"
)

git update-ref "refs/heads/$BRANCH" "$new"
say "seeded $BRANCH at $(git rev-parse --short "$new") tracking upstream ${SEED_UPSTREAM_SHA:0:12}"
