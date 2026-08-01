#!/usr/bin/env bash
# Ask the host to test this branch. Run from inside the workbench, in a feature worktree.
# Builds the candidate image, queues it, and blocks until the host reports back; merges
# the branch on a green result.
#
#   exit 0  passed    exit 1  failed    exit 2  timed out or queue unreachable
set -euo pipefail

CI=/var/lib/lani-ci
POLL_SECONDS=5
POLL_ATTEMPTS=120 # ~10 minutes

# Bails out rather than forcing anything: merging over uncommitted work buries conflicts.
_automerge() {
  local feature="$1" mainrepo target
  mainrepo="$(realpath "$(git rev-parse --git-common-dir)/..")"

  case "$feature" in
  main | master | detached) return ;;
  esac

  target="$(git -C "$mainrepo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  if [ "$target" != "main" ] && [ "$target" != "master" ]; then
    echo "==> [automerge] skipped: the main worktree is on '$target'" >&2
    return
  fi
  if ! git -C "$mainrepo" diff --quiet 2>/dev/null; then
    echo "==> [automerge] skipped: the main worktree has unstaged changes" >&2
    return
  fi
  if ! git -C "$mainrepo" diff --cached --quiet 2>/dev/null; then
    echo "==> [automerge] skipped: the main worktree has staged but uncommitted changes" >&2
    return
  fi

  echo "==> merging $feature into $target"
  git -C "$mainrepo" merge --no-ff "$feature" -m "merge: $feature (green CI)"
  echo "==> deploy it with: sudo nixos-rebuild switch --flake /etc/nixos#<your-host>"
}

if [ ! -d "$CI/queue" ]; then
  echo "CI queue $CI/queue is not there." >&2
  echo "It should be bind-mounted into the workbench by the Lani module — check that" >&2
  echo "lani.serviceHost.enable is true on the host." >&2
  exit 2
fi

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)"
id="${branch//\//-}-$(date +%s)"
system="$(nix eval --raw --impure --expr 'builtins.currentSystem')"

echo "==> [1/3] building the candidate image"
nix build .#tarball --print-build-logs --out-link /tmp/lani-result

echo "==> [2/3] queueing $id (branch: $branch)"
cp -L "/tmp/lani-result/tarball/nixos-system-${system}.tar.xz" "$CI/queue/$id.tar.xz"
# Last, on purpose: the host watches for *.req, so a half-copied tarball is never picked up.
printf '%s\n' "$branch" >"$CI/queue/$id.req"

echo "==> [3/3] waiting for the host to test it"
res="$CI/results/$id.json"
for _ in $(seq 1 "$POLL_ATTEMPTS"); do
  if [ -f "$res" ]; then
    echo
    cat "$res"
    echo
    if grep -q '"status":"pass"' "$res"; then
      _automerge "$branch"
      exit 0
    fi
    exit 1
  fi
  sleep "$POLL_SECONDS"
done

echo "timed out after $((POLL_ATTEMPTS * POLL_SECONDS))s waiting for $res" >&2
exit 2
