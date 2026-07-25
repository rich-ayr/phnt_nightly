#!/usr/bin/env bash
#
# Replay new phnt/include commits from System Informer onto the `upstream` branch.
#
# The mirror flattens upstream's phnt/include to the repo root. Rather than
# re-deriving that history every run (which produces unstable hashes and forces
# a force-push), this appends one commit per new upstream commit onto whatever
# `upstream` already points at, using git commit-tree. The result is
# fast-forward by construction, so no force-push is ever needed.
#
# Resume state is the `Upstream-Commit:` trailer on the tip of `upstream`.
# There is no state file and no cache: the branch describes its own position.
#
# Run from inside a clone of the mirror with `upstream` checked out or fetched.
# Writes nothing to the remote; the caller pushes.

set -euo pipefail

UPSTREAM_URL=${UPSTREAM_URL:-https://github.com/winsiderss/systeminformer.git}
UPSTREAM_REF=${UPSTREAM_REF:-master}
PREFIX=${PREFIX:-phnt/include}
BRANCH=${BRANCH:-upstream}

say() { printf '%s\n' "$*" >&2; }

# Emit key=value to $GITHUB_OUTPUT when running under Actions, else to stderr.
emit() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then printf '%s\n' "$1" >>"$GITHUB_OUTPUT"; fi
  say "  -> $1"
}

git remote get-url si >/dev/null 2>&1 && git remote set-url si "$UPSTREAM_URL" \
                                      || git remote add si "$UPSTREAM_URL"

# Blobless: we need every commit and tree, but only the blobs under $PREFIX,
# which are materialised on demand below. Full history is required — the
# resume point can be arbitrarily far back — so no --depth.
say "fetching $UPSTREAM_URL ($UPSTREAM_REF), blobless..."
git fetch --quiet --filter=blob:none --no-tags si "$UPSTREAM_REF"

head=$(git rev-parse "si/$UPSTREAM_REF")
tip=$(git rev-parse "refs/heads/$BRANCH")

last=$(git show -s --format='%(trailers:key=Upstream-Commit,valueonly)' "$tip" | tr -d '[:space:]')
if [ -z "$last" ]; then
  say "FATAL: no Upstream-Commit trailer on $BRANCH tip ($tip)."
  say "The branch has lost its resume point; replaying blind would duplicate history."
  say "See .github/scripts/bootstrap-upstream.sh to re-seed deliberately."
  exit 1
fi

if ! git cat-file -e "$last^{commit}" 2>/dev/null; then
  say "FATAL: recorded upstream commit $last is not reachable from $UPSTREAM_URL."
  exit 1
fi

say "upstream branch at $(git rev-parse --short "$tip"), tracking upstream $last"
say "upstream $UPSTREAM_REF at $(git rev-parse --short "$head")"

if [ "$last" = "$head" ]; then
  say "already up to date."
  emit "changed=false"
  emit "count=0"
  emit "upstream_sha=$head"
  exit 0
fi

# History simplification (the `-- $PREFIX` filter) reduces this to commits that
# actually changed the subtree, and collapses merges that did not.
mapfile -t commits < <(git rev-list --reverse --topo-order "$last..$head" -- "$PREFIX")
say "${#commits[@]} upstream commit(s) touch $PREFIX"

replayed=0
for c in "${commits[@]}"; do
  tree=$(git rev-parse -q --verify "$c:$PREFIX" 2>/dev/null) || continue
  [ "$tree" = "$(git rev-parse "$tip^{tree}")" ] && continue

  # Pull down the blobs for this tree; the clone is blobless.
  git rev-list --objects --no-object-names "$tree" | git cat-file --batch >/dev/null

  # Assign then export: a `VAR=x cmd | ...` prefix would bind only to the first
  # command in the pipeline, not to the commit-tree at the end of it, and the
  # commit would silently take the ambient identity and the current time.
  tip=$(
    GIT_AUTHOR_NAME=$(git show -s --format='%an' "$c")
    GIT_AUTHOR_EMAIL=$(git show -s --format='%ae' "$c")
    GIT_AUTHOR_DATE=$(git show -s --format='%aI' "$c")
    GIT_COMMITTER_NAME=$(git show -s --format='%cn' "$c")
    GIT_COMMITTER_EMAIL=$(git show -s --format='%ce' "$c")
    GIT_COMMITTER_DATE=$(git show -s --format='%cI' "$c")
    export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_AUTHOR_DATE
    export GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_DATE

    git show -s --format='%B' "$c" \
      | git interpret-trailers --if-exists addIfDifferent --trailer "Upstream-Commit=$c" \
      | git commit-tree "$tree" -p "$tip"
  )
  replayed=$((replayed + 1))
done

if [ "$replayed" -eq 0 ]; then
  say "no subtree changes; nothing to replay."
  emit "changed=false"
  emit "count=0"
  emit "upstream_sha=$head"
  exit 0
fi

git update-ref "refs/heads/$BRANCH" "$tip"
say "replayed $replayed commit(s); $BRANCH now at $(git rev-parse --short "$tip")"
emit "changed=true"
emit "count=$replayed"
emit "upstream_sha=$head"
emit "upstream_tip=$tip"
