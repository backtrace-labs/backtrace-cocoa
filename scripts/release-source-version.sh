#!/usr/bin/env bash
set -euo pipefail

readonly RELEASE_TAG="${1:?usage: $0 N.N.N[-rc[.N]]}"
readonly RELEASE_TAG_PATTERN='^([0-9]+\.[0-9]+\.[0-9]+)(-rc(\.(0|[1-9][0-9]*))?)?$'

if [[ ! "$RELEASE_TAG" =~ $RELEASE_TAG_PATTERN ]]; then
  echo "invalid release tag: $RELEASE_TAG" >&2
  exit 1
fi

printf '%s\n' "${BASH_REMATCH[1]}"
