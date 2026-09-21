#!/bin/bash
set -o errexit # make your script exit when a command fails
set -o pipefail # to exit when the status of the last command that threw a non-zero exit code is returned
set -o nounset # to exit when your script tries to use undeclared variables
set -o xtrace # to trace what gets executed. Useful for debugging

# This script requires the `COCOAPODS_TRUNK_TOKEN` env var to be set. 
# See more: https://fuller.li/posts/automated-cocoapods-releases-with-ci/.

PODSPEC="Backtrace.podspec"
POD_NAME="Backtrace"

version="$(pod ipc spec "$PODSPEC" | python3 -c 'import sys, json; print(json.load(sys.stdin)["version"])')"

# Skip the push when trunk already has this exact version.
if pod trunk info "$POD_NAME" | grep -qE "^\s+- ${version//./\\.} \("; then
  echo "${POD_NAME} ${version} is already published on CocoaPods trunk, skipping push."
  exit 0
fi

pod trunk push "$PODSPEC" --allow-warnings
