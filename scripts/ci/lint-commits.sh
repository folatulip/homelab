#!/usr/bin/env bash
# Checks that commit messages follow Conventional Commits
# (https://www.conventionalcommits.org):
#
#   <type>(<optional scope>)!: <description>
#
#   e.g. feat(traefik): add dashboard IngressRoute
#        fix(talos)!: move kubelet settings to KubeletConfig
#
# Usage:
#   scripts/ci/lint-commits.sh                  check commits on this branch that aren't on main (CI)
#   scripts/ci/lint-commits.sh <rev-range>      check a specific range of commits
#   scripts/ci/lint-commits.sh --file <path>    check one message file (used by the commit-msg hook)
set -euo pipefail

ALLOWED_TYPES="feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"
HEADER_PATTERN="^($ALLOWED_TYPES)(\([a-z0-9._/-]+\))?!?: [^ ].*$"
MAX_LENGTH=72

# Checks one commit header (the first line of the message).
# If it's invalid, prints the reason and returns 1.
check_header() {
  local header=$1

  # Skip the default messages git and GitHub write for merges and reverts
  if [[ $header == "Merge "* || $header == 'Revert "'* ]]; then
    return 0
  fi

  if ! [[ $header =~ $HEADER_PATTERN ]]; then
    echo "does not match '<type>(<scope>): <description>' (types: ${ALLOWED_TYPES//|/, })"
    return 1
  fi

  if [[ ${#header} -gt $MAX_LENGTH ]]; then
    echo "header is ${#header} chars, max is $MAX_LENGTH"
    return 1
  fi

  return 0
}

# Used by the commit-msg hook: check a single message file
check_message_file() {
  local file=$1

  # Use the first line that isn't a comment (git adds help text starting with '#')
  local header
  header=$(grep -v '^#' "$file" | head -1)

  # fixup!/squash! commits are fine locally, they get squashed before pushing
  if [[ $header == "fixup! "* || $header == "squash! "* ]]; then
    return 0
  fi

  local reason
  if ! reason=$(check_header "$header"); then
    echo "✗ commit message rejected: $reason" >&2
    echo "  got: $header" >&2
    echo "  e.g. feat(apps): add vaultwarden" >&2
    return 1
  fi
}

# Used by CI: check every commit in a range (merge commits are skipped)
check_commit_range() {
  local range=$1
  local failed=0

  while IFS=$'\t' read -r sha header; do
    local short_sha=${sha:0:7}
    local reason

    if reason=$(check_header "$header"); then
      echo "✓ $short_sha $header"
    else
      # ::error:: makes GitHub show it as an annotation on the run
      echo "::error title=Bad commit message $short_sha::$header: $reason"
      failed=1
    fi
  done < <(git log --no-merges --format='%H%x09%s' "$range")

  return $failed
}

if [[ ${1:-} == "--file" ]]; then
  if [[ -z ${2:-} ]]; then
    echo "usage: $0 --file <path>" >&2
    exit 2
  fi
  check_message_file "$2"
else
  check_commit_range "${1:-origin/main..HEAD}"
fi
