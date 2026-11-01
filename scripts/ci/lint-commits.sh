#!/usr/bin/env bash
# Enforce Conventional Commits (https://www.conventionalcommits.org):
#   <type>(<optional scope>)!: <description>
#   e.g. feat(traefik): add dashboard IngressRoute
#        fix(talos)!: move kubelet settings to KubeletConfig
#
# Usage:
#   scripts/ci/lint-commits.sh                 lint commits on this branch not on main (CI)
#   scripts/ci/lint-commits.sh <rev-range>     lint a specific range
#   scripts/ci/lint-commits.sh --file <path>   lint one message file (commit-msg hook)
set -euo pipefail

TYPES='feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert'
PATTERN="^($TYPES)(\([a-z0-9._/-]+\))?!?: [^ ].*$"
MAX_LEN=72

# Prints a reason and returns 1 if the header is invalid.
check() {
  local header=$1
  case $header in
    'Merge '*) return 0 ;;             # merge commits from git/GitHub
    'Revert "'*) return 0 ;;           # git revert's default message
  esac
  if ! [[ $header =~ $PATTERN ]]; then
    echo "does not match '<type>(<scope>): <description>' (types: ${TYPES//|/, })"
    return 1
  fi
  if (( ${#header} > MAX_LEN )); then
    echo "header is ${#header} chars, max $MAX_LEN"
    return 1
  fi
}

if [[ ${1:-} == --file ]]; then
  # First line that isn't a comment (git puts help text after a '#').
  header=$(grep -v '^#' "$2" | head -1)
  case $header in 'fixup! '*|'squash! '*) exit 0 ;; esac  # allowed locally, squashed before push
  if ! reason=$(check "$header"); then
    echo "✗ commit message rejected: $reason" >&2
    echo "  got: $header" >&2
    echo "  e.g. feat(apps): add vaultwarden" >&2
    exit 1
  fi
  exit 0
fi

range=${1:-origin/main..HEAD}
status=0
while IFS=$'\t' read -r sha header; do
  if reason=$(check "$header"); then
    echo "✓ ${sha:0:7} $header"
  else
    echo "::error title=Bad commit message ${sha:0:7}::$header: $reason"
    status=1
  fi
done < <(git log --no-merges --format='%H%x09%s' "$range")
exit $status
