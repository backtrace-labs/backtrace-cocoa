#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  echo "Usage: $0 OUTPUT_DIRECTORY" >&2
  echo "" >&2
  echo "Environment:" >&2
  echo "  PLCRASHREPORTER_SOURCE_DIR  Verified PLCrashReporter 1.12.0 checkout" >&2
  echo "  BACKTRACE_VERSION            Bundle version (default: 2.1.1)" >&2
  echo "  BACKTRACE_BUILD_NUMBER       Bundle build number (default: 1)" >&2
  echo "  MACOS_SIGNING_IDENTITY       Signing identity (default: ad-hoc '-')" >&2
  echo "  KEEP_BUILD_ARTIFACTS=1       Preserve temporary build products" >&2
}

[[ $# -eq 1 ]] || {
  usage
  exit 64
}

for tool in awk codesign ditto dsymutil dwarfdump find git lipo nm otool plutil \
  python3 shasum sort swift sw_vers xattr xcodebuild xcrun; do
  command -v "$tool" >/dev/null 2>&1 || fail "required tool is unavailable: $tool"
done

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
mkdir -p "$1"
readonly OUTPUT_ROOT="$(cd "$1" && pwd -P)"
[[ "$OUTPUT_ROOT" != "/" ]] || fail "refusing to use the filesystem root as output"

readonly PREFIX_BUILDER="$SCRIPT_DIR/build-prefixed-plcrashreporter.sh"
readonly PRIVACY_MERGER="$SCRIPT_DIR/merge-unity-privacy-manifests.py"
readonly VALIDATOR="$SCRIPT_DIR/validate-unity-macos-bundle.sh"
readonly BRIDGE_SOURCE="$PROJECT_ROOT/BacktraceUnityBridge.mm"
readonly COCOA_PRIVACY_MANIFEST="$PROJECT_ROOT/Sources/Resources/PrivacyInfo.xcprivacy"
for required in "$PREFIX_BUILDER" "$PRIVACY_MERGER" "$VALIDATOR" \
  "$BRIDGE_SOURCE" "$COCOA_PRIVACY_MANIFEST"; do
  [[ -f "$required" ]] || fail "required build input is missing: $required"
done

# Fail before invoking Xcode if a compatibility entry point can ever construct PLCrashReporter without the isolated base path.
# The final artifact validator independently checks binary markers for this storage contract.
python3 - "$BRIDGE_SOURCE" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")

required = [
    'BTUnityCrashStorageRelativePath = @"Backtrace/NativeCrash/v1/plcrash"',
    'BTUnityLegacyIdentifierPrefix = @"io.backtrace.unity.legacy."',
    'BTUnityExceptionContractMarker =',
    'BacktraceUnityExceptionContract:all-c-exports-contained-v1',
    "static NSString *BTLegacyCrashReportBasePath",
    "basePath:reportBasePath",
]
for value in required:
    if value not in source:
        raise SystemExit(f"error: Unity bridge storage contract is missing: {value}")

if "requiresIsolatedStorage" in source:
    raise SystemExit("error: Unity bridge still contains an optional-isolation path")

default_initializer = re.compile(
    r"initWithSignalHandlerType\s*:\s*PLCrashReporterSignalHandlerTypeBSD"
    r"\s*symbolicationStrategy\s*:\s*strategy\s*\]"
)
if default_initializer.search(source):
    raise SystemExit("error: Unity bridge still constructs PLCrashReporter in its default namespace")

def exported_body(name: str, next_name: str) -> str:
    start = source.find(f"BT_EXPORT {name}")
    end = source.find(f"BT_EXPORT {next_name}", start + 1)
    if start < 0 or end < 0:
        raise SystemExit(f"error: cannot inspect Unity bridge entry point: {name}")
    return source[start:end]

v2 = exported_body("int32_t StartBacktraceIntegrationV2", "void StartBacktraceIntegration")
v1 = exported_body("void StartBacktraceIntegration", "void GetAttributes")
for name, body in (("V2", v2), ("V1", v1)):
    if "BTLegacyCrashReportBasePath" not in body or "basePath" not in body:
        raise SystemExit(f"error: Unity bridge {name} does not use isolated compatibility storage")

internal_start = source.find("static BTUnityInitializationResult BTStartIntegration(")
internal_end = source.find("BT_EXPORT ", internal_start)
internal_body = source[internal_start:internal_end]
if internal_start < 0 or internal_end < 0 or "@try" not in internal_body or "@catch" not in internal_body:
    raise SystemExit("error: Unity bridge internal initialization is not exception-contained")
if internal_body.find("@try") > internal_body.find("@autoreleasepool"):
    raise SystemExit("error: Unity bridge initializer does not contain autorelease-pool teardown")

exports = [
    "int32_t BacktraceUnityBridgeVersion(",
    "int32_t StartBacktraceIntegrationV3(",
    "int32_t StartBacktraceIntegrationV2(",
    "void StartBacktraceIntegration(",
    "void GetAttributes(",
    "void FreeAttributes(",
    "void NativeReport(",
    "void AddAttribute(",
    "const char *BtCrash(",
    "void Disable(",
]
for signature in exports:
    start = source.find("BT_EXPORT " + signature)
    end = source.find("BT_EXPORT ", start + 1)
    if end < 0:
        end = len(source)
    body = source[start:end]
    if start < 0 or "@try" not in body or "@catch" not in body:
        raise SystemExit(f"error: Unity bridge export is not exception-contained: {signature}")
    if "@autoreleasepool" in body and body.find("@try") > body.find("@autoreleasepool"):
        raise SystemExit(f"error: Unity bridge export does not contain autorelease-pool teardown: {signature}")
PY

readonly WORK_ROOT="$(mktemp -d "${TMPDIR:-/private/tmp}/backtrace-unity-bundle.XXXXXX")"
cleanup() {
  if [[ "${KEEP_BUILD_ARTIFACTS:-0}" == "1" ]]; then
    echo "Preserving build directory: $WORK_ROOT"
  else
    rm -rf "$WORK_ROOT"
  fi
}
trap cleanup EXIT

resolve_plcrashreporter_source() {
  local candidate="${PLCRASHREPORTER_SOURCE_DIR:-$PROJECT_ROOT/.build/checkouts/plcrashreporter}"
  if [[ ! -f "$candidate/CrashReporter.xcodeproj/project.pbxproj" ]]; then
    local scratch="$WORK_ROOT/swiftpm"
    swift package --package-path "$PROJECT_ROOT" --scratch-path "$scratch" resolve
    candidate="$scratch/checkouts/plcrashreporter"
  fi
  [[ -f "$candidate/CrashReporter.xcodeproj/project.pbxproj" ]] ||
    fail "could not resolve PLCrashReporter source"
  (cd "$candidate" && pwd -P)
}

readonly PLCRASHREPORTER_SOURCE="$(resolve_plcrashreporter_source)"
readonly PRIVATE_RUNTIME="$WORK_ROOT/private-runtime"
bash "$PREFIX_BUILDER" \
  --source "$PLCRASHREPORTER_SOURCE" \
  --output "$PRIVATE_RUNTIME"

readonly PRODUCTS="$WORK_ROOT/products"
readonly DERIVED="$WORK_ROOT/derived"
readonly COCOA_VERSION="${BACKTRACE_VERSION:-2.1.1}"
readonly BUILD_NUMBER="${BACKTRACE_BUILD_NUMBER:-1}"

echo "Building self-contained BacktraceMacUnity.bundle $COCOA_VERSION"
CLANG_MODULE_CACHE_PATH="$WORK_ROOT/module-cache" \
xcodebuild \
  -quiet \
  -project "$PROJECT_ROOT/Backtrace.xcodeproj" \
  -scheme "Backtrace-bundle" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED" \
  'ARCHS=arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
  GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
  MACOSX_DEPLOYMENT_TARGET=12.4 \
  "CONFIGURATION_BUILD_DIR=$PRODUCTS" \
  "DWARF_DSYM_FOLDER_PATH=$PRODUCTS" \
  "BTUNITY_PLCRASHREPORTER_ROOT=$PRIVATE_RUNTIME" \
  "MARKETING_VERSION=$COCOA_VERSION" \
  "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
  build

readonly BUILT_BUNDLE="$PRODUCTS/BacktraceMacUnity.bundle"
readonly BUILT_BINARY="$BUILT_BUNDLE/Contents/MacOS/BacktraceMacUnity"
readonly BUILT_DSYM="$PRODUCTS/BacktraceMacUnity.bundle.dSYM"
[[ -f "$BUILT_BINARY" ]] || fail "BacktraceMacUnity.bundle executable was not produced"
if [[ ! -d "$BUILT_DSYM" ]]; then
  dsymutil "$BUILT_BINARY" -o "$BUILT_DSYM"
fi
[[ -d "$BUILT_DSYM" ]] || fail "BacktraceMacUnity.bundle dSYM was not produced"

readonly STAGED_OUTPUT="$WORK_ROOT/output"
readonly STAGED_BUNDLE="$STAGED_OUTPUT/BacktraceMacUnity.bundle"
readonly STAGED_BINARY="$STAGED_BUNDLE/Contents/MacOS/BacktraceMacUnity"
readonly STAGED_DSYM="$STAGED_OUTPUT/BacktraceMacUnity.bundle.dSYM"
mkdir -p "$STAGED_OUTPUT"
ditto "$BUILT_BUNDLE" "$STAGED_BUNDLE"
ditto "$BUILT_DSYM" "$STAGED_DSYM"

python3 "$PRIVACY_MERGER" \
  --output "$STAGED_BUNDLE/Contents/Resources/PrivacyInfo.xcprivacy" \
  "$COCOA_PRIVACY_MANIFEST" \
  "$PRIVATE_RUNTIME/PrivacyInfo.xcprivacy"

[[ -f "$STAGED_BUNDLE/Contents/Resources/Model.momd/Model.mom" ]] ||
  fail "the direct Core Data model resource is missing"

# Strip extended attributes before the final signing pass. No bundle content may change afterward.
xattr -cr "$STAGED_BUNDLE"
readonly SIGNING_IDENTITY="${MACOS_SIGNING_IDENTITY:--}"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$STAGED_BUNDLE"
else
  codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" "$STAGED_BUNDLE"
fi
codesign --verify --strict --verbose=2 "$STAGED_BUNDLE"

readonly BUNDLE_MANIFEST="$WORK_ROOT/bundle-manifest.sha256"
(
  cd "$STAGED_OUTPUT"
  find BacktraceMacUnity.bundle -type f -print | LC_ALL=C sort |
    while IFS= read -r path; do
      shasum -a 256 "$path"
    done
) > "$BUNDLE_MANIFEST"

readonly BUNDLE_SHA256="$(shasum -a 256 "$BUNDLE_MANIFEST" | awk '{print $1}')"
readonly BINARY_SHA256="$(shasum -a 256 "$STAGED_BINARY" | awk '{print $1}')"
readonly COCOA_HEAD="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
readonly COCOA_DIRTY="$(if [[ -n "$(git -C "$PROJECT_ROOT" status --porcelain)" ]]; then echo true; else echo false; fi)"
readonly WORKTREE_DIGEST="$(python3 - "$PROJECT_ROOT" <<'PY'
import hashlib
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
digest = hashlib.sha256()
diff = subprocess.run(
    ["git", "-C", str(root), "diff", "--binary", "HEAD"],
    check=True,
    stdout=subprocess.PIPE,
).stdout
digest.update(b"tracked-diff\0")
digest.update(diff)
untracked = subprocess.run(
    ["git", "-C", str(root), "ls-files", "--others", "--exclude-standard", "-z"],
    check=True,
    stdout=subprocess.PIPE,
).stdout.split(b"\0")
for raw_path in sorted(path for path in untracked if path):
    path = root / raw_path.decode()
    digest.update(b"untracked\0" + raw_path + b"\0")
    if path.is_file():
        digest.update(path.read_bytes())
print(digest.hexdigest())
PY
)"
readonly BRIDGE_SOURCE_SHA256="$(shasum -a 256 "$BRIDGE_SOURCE" | awk '{print $1}')"
readonly XCODE_VERSION="$(xcodebuild -version | tr '\n' ';' | sed 's/;$//')"
readonly SWIFT_VERSION="$(swift --version | head -1)"
readonly MACOS_VERSION="$(sw_vers -productVersion)"
readonly MACOS_BUILD="$(sw_vers -buildVersion)"
readonly CDHASH="$(codesign -dvvv "$STAGED_BUNDLE" 2>&1 | awk -F= '$1 == "CDHash" {print $2; exit}')"

python3 - \
  "$STAGED_OUTPUT/artifact-provenance.json" \
  "$PRIVATE_RUNTIME/plcrashreporter-provenance.json" \
  "$COCOA_HEAD" \
  "$COCOA_DIRTY" \
  "$WORKTREE_DIGEST" \
  "$BRIDGE_SOURCE_SHA256" \
  "$COCOA_VERSION" \
  "$BUILD_NUMBER" \
  "$XCODE_VERSION" \
  "$SWIFT_VERSION" \
  "$MACOS_VERSION" \
  "$MACOS_BUILD" \
  "$BUNDLE_SHA256" \
  "$BINARY_SHA256" \
  "$SIGNING_IDENTITY" \
  "$CDHASH" \
  "$STAGED_BINARY" \
  "$STAGED_DSYM" <<'PY'
import json
from pathlib import Path
import re
import subprocess
import sys

(
    output,
    plcrash_path,
    cocoa_head,
    cocoa_dirty,
    worktree_digest,
    bridge_source_sha,
    cocoa_version,
    build_number,
    xcode_version,
    swift_version,
    macos_version,
    macos_build,
    bundle_sha,
    binary_sha,
    signing_identity,
    cdhash,
    binary,
    dsym,
) = sys.argv[1:]

with Path(plcrash_path).open(encoding="utf-8") as stream:
    plcrash = json.load(stream)

uuid_pattern = re.compile(r"UUID: ([0-9A-F-]+) \(([^)]+)\)")
binary_uuids = [
    {"uuid": match.group(1), "architecture": match.group(2)}
    for match in uuid_pattern.finditer(
        subprocess.run(["dwarfdump", "--uuid", binary], check=True, text=True, stdout=subprocess.PIPE).stdout
    )
]
dsym_uuids = [
    {"uuid": match.group(1), "architecture": match.group(2)}
    for match in uuid_pattern.finditer(
        subprocess.run(["dwarfdump", "--uuid", dsym], check=True, text=True, stdout=subprocess.PIPE).stdout
    )
]

value = {
    "schema_version": 1,
    "artifact": "BacktraceMacUnity.bundle",
    "backtrace_cocoa": {
        "head": cocoa_head,
        "dirty": cocoa_dirty == "true",
        "working_tree_digest_sha256": worktree_digest,
        "version": cocoa_version,
        "build_number": build_number,
    },
    "plcrashreporter": plcrash,
    "unity_bridge": {
        "exception_contract": "all-c-exports-contained-v1",
        "source_sha256": bridge_source_sha,
        "storage_contract": "all-entry-points-isolated-v1",
    },
    "toolchain": {
        "xcode": xcode_version,
        "swift": swift_version,
        "macos": macos_version,
        "macos_build": macos_build,
    },
    "architectures": ["arm64", "x86_64"],
    "deployment_target": "12.4",
    "bundle_identifier": "io.backtrace.unity.macos",
    "bridge_abi_version": 3,
    "bundle_sha256": bundle_sha,
    "bundle_sha256_algorithm": "sha256(sorted per-file SHA-256 manifest)",
    "binary_sha256": binary_sha,
    "binary_uuids": binary_uuids,
    "dsym_uuids": dsym_uuids,
    "signing": {"requested_identity": signing_identity, "cdhash": cdhash},
    "build_command": "scripts/build-unity-macos-bundle.sh OUTPUT_DIRECTORY",
}
Path(output).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

(
  cd "$STAGED_OUTPUT"
  find BacktraceMacUnity.bundle BacktraceMacUnity.bundle.dSYM artifact-provenance.json \
    -type f -print | LC_ALL=C sort |
    while IFS= read -r path; do
      shasum -a 256 "$path"
    done > SHA256SUMS
)

bash "$VALIDATOR" "$STAGED_OUTPUT"

rm -rf \
  "$OUTPUT_ROOT/BacktraceMacUnity.bundle" \
  "$OUTPUT_ROOT/BacktraceMacUnity.bundle.dSYM"
rm -f "$OUTPUT_ROOT/artifact-provenance.json" "$OUTPUT_ROOT/SHA256SUMS"
ditto "$STAGED_BUNDLE" "$OUTPUT_ROOT/BacktraceMacUnity.bundle"
ditto "$STAGED_DSYM" "$OUTPUT_ROOT/BacktraceMacUnity.bundle.dSYM"
ditto "$STAGED_OUTPUT/artifact-provenance.json" "$OUTPUT_ROOT/artifact-provenance.json"
ditto "$STAGED_OUTPUT/SHA256SUMS" "$OUTPUT_ROOT/SHA256SUMS"

echo "Built and validated self-contained Unity macOS bundle:"
echo "  $OUTPUT_ROOT/BacktraceMacUnity.bundle"
echo "  $OUTPUT_ROOT/BacktraceMacUnity.bundle.dSYM"
echo "  $OUTPUT_ROOT/artifact-provenance.json"
echo "  $OUTPUT_ROOT/SHA256SUMS"
