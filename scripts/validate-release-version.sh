#!/usr/bin/env bash
set -euo pipefail

readonly VERSION="${1:?usage: $0 N.N.N}"
readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SOURCE_ROOT="$(cd "$SCRIPT_DIRECTORY/.." && pwd -P)"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "invalid release version: $VERSION" >&2
  exit 1
fi

extract_version() {
  local path="$1"
  local pattern="$2"
  local missing_message="$3"
  ruby -e '
    text = File.read(ARGV.fetch(0))
    match = text.match(Regexp.new(ARGV.fetch(1)))
    abort ARGV.fetch(2) unless match
    puts match[1]
  ' "$path" "$pattern" "$missing_message"
}

readonly PODSPEC_VERSION="$(
  extract_version \
    "$SOURCE_ROOT/Backtrace.podspec" \
    's\.version\s*=\s*["\x27]([^"\x27]+)["\x27]' \
    'Backtrace.podspec version not found'
)"
readonly AGENT_VERSION="$(
  extract_version \
    "$SOURCE_ROOT/Sources/Features/Attributes/DefaultAttributes.swift" \
    'backtraceVersion\s*=\s*"([^"]+)"' \
    'LibInfo.backtraceVersion not found'
)"
readonly CHANGELOG_VERSION="$(
  extract_version \
    "$SOURCE_ROOT/CHANGELOG.md" \
    '^## Version ([^\s]+)\s*$' \
    'CHANGELOG.md has no current Version heading'
)"

for source_and_value in \
  "Backtrace.podspec:$PODSPEC_VERSION" \
  "LibInfo.backtraceVersion:$AGENT_VERSION" \
  "CHANGELOG.md:$CHANGELOG_VERSION"; do
  source="${source_and_value%%:*}"
  value="${source_and_value#*:}"
  if [[ "$value" != "$VERSION" ]]; then
    echo "release version mismatch: tag=$VERSION source=$source value=$value" >&2
    exit 1
  fi
done

echo "validated release version $VERSION"
