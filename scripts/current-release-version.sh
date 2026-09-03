#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

ruby - "$ROOT_DIRECTORY/Backtrace.podspec" <<'RUBY'
path = ARGV.fetch(0)
text = File.read(path)
match = text.match(/s\.version\s*=\s*["']([^"']+)["']/)
abort "Backtrace.podspec version not found" unless match
puts match[1]
RUBY
