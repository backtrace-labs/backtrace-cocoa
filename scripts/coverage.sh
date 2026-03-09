#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

# Extract code coverage summary from an xcresult bundle.
#
# Usage: scripts/coverage.sh <path-to-xcresult> [--json-output <path>] [--markdown-output <path>]
# Example: scripts/coverage.sh fastlane/test_output/Backtrace-iOS-lib/Backtrace-iOS-lib.xcresult

XCRESULT_PATH="${1:?Usage: coverage.sh <path-to-xcresult> [--json-output <path>] [--markdown-output <path>]}"
JSON_OUTPUT=""
MARKDOWN_OUTPUT=""

shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json-output)
            JSON_OUTPUT="$2"
            shift 2
            ;;
        --markdown-output)
            MARKDOWN_OUTPUT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [ ! -e "$XCRESULT_PATH" ]; then
    echo "Error: xcresult bundle not found at $XCRESULT_PATH" >&2
    exit 1
fi

# Extract coverage JSON from xcresult
COVERAGE_JSON=$(xcrun xccov view --report --json "$XCRESULT_PATH")

# Pass coverage data via environment variable so heredoc stdin is free for the script
export COVERAGE_JSON
python3 - "$JSON_OUTPUT" "$MARKDOWN_OUTPUT" <<'PYEOF'
import json, os, sys

coverage_json = json.loads(os.environ["COVERAGE_JSON"])
json_output_path = sys.argv[1] if sys.argv[1] else None
markdown_output_path = sys.argv[2] if sys.argv[2] else None

overall_pct = coverage_json.get("lineCoverage", 0) * 100

# Find Backtrace framework targets (exclude test targets, Pods internals, etc.)
backtrace_targets = []
for t in coverage_json.get("targets", []):
    name = t.get("name", "")
    if "Backtrace" in name and "Test" not in name and "Pods_" not in name:
        pct = t.get("lineCoverage", 0) * 100
        covered = t.get("coveredLines", 0)
        executable = t.get("executableLines", 0)
        backtrace_targets.append({
            "name": name,
            "lineCoverage": round(pct, 2),
            "coveredLines": covered,
            "executableLines": executable
        })

# Print human-readable summary
print(f"Overall line coverage: {overall_pct:.2f}%")
for bt in backtrace_targets:
    print(f"  {bt['name']}: {bt['lineCoverage']:.2f}% ({bt['coveredLines']}/{bt['executableLines']} lines)")

# Write machine-readable JSON
summary = {
    "overallLineCoverage": round(overall_pct, 2),
    "targets": backtrace_targets
}

if json_output_path:
    with open(json_output_path, "w") as f:
        json.dump(summary, f, indent=2)
    print(f"Coverage JSON written to {json_output_path}")

# Write Markdown table
if markdown_output_path:
    lines = [
        "| Target | Line Coverage | Covered / Executable |",
        "|--------|:------------:|:--------------------:|",
    ]
    for bt in backtrace_targets:
        lines.append(f"| {bt['name']} | {bt['lineCoverage']:.2f}% | {bt['coveredLines']} / {bt['executableLines']} |")
    lines.append("")
    lines.append(f"**Overall: {overall_pct:.2f}%**")
    with open(markdown_output_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"Markdown summary written to {markdown_output_path}")
PYEOF
