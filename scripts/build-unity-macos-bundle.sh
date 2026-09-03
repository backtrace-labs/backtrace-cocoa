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
  echo "  BACKTRACE_VERSION            Bundle version (default: Backtrace.podspec)" >&2
  echo "  BACKTRACE_BUILD_NUMBER       Bundle build number (default: 1)" >&2
  echo "  MACOS_SIGNING_IDENTITY       Signing identity (default: ad-hoc '-')" >&2
  echo "  KEEP_BUILD_ARTIFACTS=1       Preserve temporary build products" >&2
}

[[ $# -eq 1 ]] || {
  usage
  exit 64
}

for tool in chmod codesign ditto dsymutil find python3 ruby shasum sort swift \
  xattr xcodebuild; do
  command -v "$tool" >/dev/null 2>&1 || fail "required tool is unavailable: $tool"
done

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly UNITY_MACOS_CONFIG="$SCRIPT_DIR/unity-macos-config.sh"
[[ -f "$UNITY_MACOS_CONFIG" ]] || fail "required build input is missing: $UNITY_MACOS_CONFIG"
# shellcheck source=unity-macos-config.sh
source "$UNITY_MACOS_CONFIG"
mkdir -p "$1"
readonly OUTPUT_ROOT="$(cd "$1" && pwd -P)"
[[ "$OUTPUT_ROOT" != "/" ]] || fail "refusing to use the filesystem root as output"
while IFS= read -r -d '' existing_output; do
  case "${existing_output##*/}" in
    BacktraceMacUnity.bundle|BacktraceMacUnity.bundle.dSYM|SHA256SUMS|artifact-provenance.json) ;;
    *) fail "output directory contains an unexpected entry: $existing_output" ;;
  esac
done < <(find "$OUTPUT_ROOT" -mindepth 1 -maxdepth 1 -print0)

readonly PREFIX_BUILDER="$SCRIPT_DIR/build-prefixed-plcrashreporter.sh"
readonly PRIVACY_MERGER="$SCRIPT_DIR/merge-unity-privacy-manifests.py"
readonly PROJECT_VALIDATOR="$SCRIPT_DIR/validate_unity_xcode_project.py"
readonly VALIDATOR="$SCRIPT_DIR/validate-unity-macos-bundle.sh"
readonly VERSION_RESOLVER="$SCRIPT_DIR/current-release-version.sh"
readonly BRIDGE_SOURCE="$PROJECT_ROOT/BacktraceUnityBridge.mm"
[[ -x "$VERSION_RESOLVER" ]] || fail "release-version resolver is unavailable: $VERSION_RESOLVER"
readonly COCOA_PRIVACY_MANIFEST="$PROJECT_ROOT/Sources/Resources/PrivacyInfo.xcprivacy"
for required in "$PREFIX_BUILDER" "$PRIVACY_MERGER" "$PROJECT_VALIDATOR" "$VALIDATOR" \
  "$BRIDGE_SOURCE" "$COCOA_PRIVACY_MANIFEST"; do
  [[ -f "$required" ]] || fail "required build input is missing: $required"
done

# Resolve the target and its configurations through the Xcode object graph rather than relying
# on generated PBX object identifiers or their serialization order.
python3 -B "$PROJECT_VALIDATOR" \
  --project "$PROJECT_ROOT/Backtrace.xcodeproj/project.pbxproj" \
  --target "Backtrace-bundle" \
  --deployment-target "$BTUNITY_MACOS_DEPLOYMENT_TARGET"

# Fail before invoking Xcode if a compatibility entry point can ever construct PLCrashReporter without the isolated base path.
# The final artifact validator independently checks binary markers for this storage contract.
python3 - \
  "$BRIDGE_SOURCE" \
  "$PROJECT_ROOT/Sources/Public/BacktraceCrashReporter.swift" \
  "$PROJECT_ROOT/Sources/Features/Client/BacktraceOomWatcher.swift" \
  "$PROJECT_ROOT/Sources/Features/Client/BacktraceReporter.swift" \
  "$PROJECT_ROOT/Sources/Features/Repository/PersistentRepository.swift" \
  "$PROJECT_ROOT/Sources/Public/BacktraceLogger.swift" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
crash_reporter_source = Path(sys.argv[2]).read_text(encoding="utf-8")
oom_watcher_source = Path(sys.argv[3]).read_text(encoding="utf-8")
reporter_source = Path(sys.argv[4]).read_text(encoding="utf-8")
repository_source = Path(sys.argv[5]).read_text(encoding="utf-8")
logger_source = Path(sys.argv[6]).read_text(encoding="utf-8")


def declaration_body(text: str, declaration: str, label: str) -> str:
    """Return one complete brace-delimited declaration, ignoring braces in comments/quotes."""
    matches = [match.start() for match in re.finditer(re.escape(declaration), text)]
    if len(matches) != 1:
        raise SystemExit(
            f"error: expected exactly one {label} declaration; found {len(matches)}"
        )

    start = matches[0]
    opening_brace = text.find("{", start + len(declaration))
    if opening_brace < 0:
        raise SystemExit(f"error: {label} declaration has no body")

    depth = 0
    state = "code"
    quote = ""
    index = opening_brace
    while index < len(text):
        character = text[index]
        following = text[index + 1] if index + 1 < len(text) else ""

        if state == "code":
            if character == "/" and following == "/":
                state = "line-comment"
                index += 2
                continue
            if character == "/" and following == "*":
                state = "block-comment"
                index += 2
                continue
            if character in ('"', "'"):
                state = "quoted"
                quote = character
            elif character == "{":
                depth += 1
            elif character == "}":
                depth -= 1
                if depth == 0:
                    return text[start:index + 1]
        elif state == "line-comment":
            if character == "\n":
                state = "code"
        elif state == "block-comment":
            if character == "*" and following == "/":
                state = "code"
                index += 2
                continue
        elif state == "quoted":
            if character == "\\":
                index += 2
                continue
            if character == quote:
                state = "code"

        index += 1

    raise SystemExit(f"error: {label} declaration has an unbalanced body")

required = [
    'BTUnityCrashStorageRelativePath = @"Backtrace/NativeCrash/v1/plcrash"',
    'BTUnityLegacyIdentifierPrefix = @"io.backtrace.unity.legacy."',
    'BTPLCrashReporterDefaultNamespace =',
    '@"com.plausiblelabs.crashreporter.data"',
    'BTUnityExceptionContractMarker =',
    'BacktraceUnityExceptionContract:all-c-exports-contained-v1',
    'BacktraceUnityLifecycleContract:process-lifetime-handler-distinct-disabled-v2',
    'BacktraceUnityLoggingContract:warning-default-explicit-setter-silent-none-redacted-v3',
    'BTUnityInitializationResultAlreadyInitializedActive = 1',
    'BTUnityInitializationResultProcessLifetimeDisabled = 7',
    'BTUnityConfiguredLogLevel = BacktraceLogLevelWarning',
    'BTUnityManagedInterfaceEnabled = NO',
    'BTUnityHandlerInstallationAttempted = NO',
    '@interface BacktraceClient (BacktraceUnityBridgeLifecycle)',
    '- (void)shutdownForNativeBridge;',
    "static NSString *BTLegacyCrashReportBasePath",
    "basePath:reportBasePath",
]
for value in required:
    if value not in source:
        raise SystemExit(f"error: Unity bridge storage contract is missing: {value}")

if "requiresIsolatedStorage" in source:
    raise SystemExit("error: Unity bridge still contains an optional-isolation path")
if "NSIntegerMax" in source:
    raise SystemExit("error: Unity bridge must pass unlimited rate mode through as zero")

default_initializer = re.compile(
    r"initWithSignalHandlerType\s*:\s*PLCrashReporterSignalHandlerTypeBSD"
    r"\s*symbolicationStrategy\s*:\s*strategy\s*\]"
)
if default_initializer.search(source):
    raise SystemExit("error: Unity bridge still constructs PLCrashReporter in its default namespace")

storage_preparation = declaration_body(
    source,
    "static NSString *BTPrepareCrashReportBasePath(",
    "BTPrepareCrashReportBasePath",
)
for value in (
    "URLByResolvingSymlinksInPath",
    "NSCachesDirectory",
    "BTPLCrashReporterDefaultNamespace",
    "[resolvedPath isEqualToString:defaultBasePath]",
):
    if value not in storage_preparation:
        raise SystemExit(
            "error: Unity V3 storage validation does not reject the canonical "
            f"PLCrashReporter default namespace: {value}"
        )

def exported_body(signature: str) -> str:
    return declaration_body(source, f"BT_EXPORT {signature}", f"Unity export {signature}")

v3 = exported_body("int32_t StartBacktraceIntegrationV3(")
v2 = exported_body("int32_t StartBacktraceIntegrationV2(")
v1 = exported_body("void StartBacktraceIntegration(")
for name, body in (("V2", v2), ("V1", v1)):
    if "BTLegacyCrashReportBasePath" not in body or "basePath" not in body:
        raise SystemExit(f"error: Unity bridge {name} does not use isolated compatibility storage")

internal_body = declaration_body(
    source,
    "static BTUnityInitializationResult BTStartIntegration(",
    "BTStartIntegration",
)
if "@try" not in internal_body or "@catch" not in internal_body:
    raise SystemExit("error: Unity bridge internal initialization is not exception-contained")
if internal_body.find("@try") > internal_body.find("@autoreleasepool"):
    raise SystemExit("error: Unity bridge initializer does not contain autorelease-pool teardown")
client_initialization = internal_body.find("initWithConfiguration:configuration")
installation_record = internal_body.find("BTRecordHandlerInstallationState(crashReporter)")
if client_initialization < 0 or installation_record < client_initialization:
    raise SystemExit("error: Unity bridge does not inspect actual handler installation after client initialization")
if "BTUnityHandlerInstallationAttempted = YES" in internal_body:
    raise SystemExit("error: Unity bridge latches the process handler before PLCrashReporter enable is entered")
if internal_body.count("BTRecordHandlerInstallationState(crashReporter)") < 2:
    raise SystemExit("error: Unity bridge does not record installation state on success/error and exception paths")
for value in (
    "BTUnityManagedInterfaceEnabled",
    "BTUnityInitializationResultAlreadyInitializedActive",
    "BTUnityInitializationResultProcessLifetimeDisabled",
    "preserveLegacyAlreadyInitializedResult",
    "restart the process",
):
    if value not in internal_body:
        raise SystemExit(f"error: Unity bridge initialization-state contract is missing: {value}")

v2_disabled_mapping = (
    "result == BTUnityInitializationResultProcessLifetimeDisabled"
    "\n                ? BTUnityInitializationResultAlreadyInitializedActive"
)
if v2_disabled_mapping not in v2:
    raise SystemExit("error: Unity V2 bridge no longer preserves its legacy already-initialized result")

legacy_shared_mapping = (
    "preserveLegacyAlreadyInitializedResult"
    "\n                        ? BTUnityInitializationResultAlreadyInitializedActive"
    "\n                        : BTUnityInitializationResultClientInitializationFailed"
)
if legacy_shared_mapping not in internal_body:
    raise SystemExit("error: Unity bridge no longer isolates the legacy shared-client result mapping")

for name, body, compatibility_value in (
    ("V3", v3, "false"),
    ("V2", v2, "true"),
    ("V1", v1, "true"),
):
    if not re.search(
        rf"BTStartIntegration\s*\([\s\S]*?,\s*{compatibility_value}\s*\)",
        body,
    ):
        raise SystemExit(
            f"error: Unity {name} bridge does not pass the required shared-client compatibility mode"
        )

state_helper = declaration_body(
    source,
    "static void BTRecordHandlerInstallationState(",
    "BTRecordHandlerInstallationState",
)
for value in (
    "crashReporter.handlerInstallationAttempted",
    "BTUnityHandlerInstallationAttempted = YES",
    "removeObjectIdenticalTo:crashReporter",
):
    if value not in state_helper:
        raise SystemExit(f"error: Unity handler-installation state contract is missing: {value}")

enable_body = declaration_body(
    crash_reporter_source,
    "func enableCrashReporting() throws",
    "BacktraceCrashReporter.enableCrashReporting",
)
attempt_marker = enable_body.find("installationWasAttempted = true")
plcrash_enable = enable_body.find("reporter.enableAndReturnError()")
if attempt_marker < 0 or plcrash_enable < 0 or attempt_marker > plcrash_enable:
    raise SystemExit("error: BacktraceCrashReporter does not mark the attempt before PLCrashReporter enable")

exports = [
    "int32_t BacktraceUnityBridgeVersion(",
    "int32_t SetBacktraceLogLevel(",
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
    body = exported_body(signature)
    if "@try" not in body or "@catch" not in body:
        raise SystemExit(f"error: Unity bridge export is not exception-contained: {signature}")
    if "@autoreleasepool" in body and body.find("@try") > body.find("@autoreleasepool"):
        raise SystemExit(f"error: Unity bridge export does not contain autorelease-pool teardown: {signature}")

disable_body = exported_body("void Disable(")
if "BTUnityRuntime = nil" in disable_body:
    raise SystemExit("error: Disable releases process-lifetime Unity crash-handler state")
if "BacktraceClient.shared = nil" not in disable_body:
    raise SystemExit("error: Disable no longer detaches the managed-facing client")
if "BTUnityManagedInterfaceEnabled = NO" not in disable_body:
    raise SystemExit("error: Disable no longer deactivates managed bridge operations")
if "shutdownForNativeBridge" not in disable_body:
    raise SystemExit("error: Disable no longer stops non-fatal Cocoa background activity")
if "BTUnityHandlerInstallationAttempted = NO" in disable_body:
    raise SystemExit("error: Disable permits a second process-wide handler installation attempt")
monitor_end = disable_body.find("[client shutdownForNativeBridge]")
detach = disable_body.find("BacktraceClient.shared = nil")
if monitor_end < 0 or detach < 0 or monitor_end < detach:
    raise SystemExit("error: Disable may invoke shutdown while holding the bridge class monitor")
reporter_shutdown = declaration_body(
    reporter_source,
    "internal func shutdown()",
    "BacktraceReporter.shutdown",
)
shutdown_phases = (
    "watcher.prepareForShutdown()",
    "backtraceOomWatcher.prepareForShutdown()",
    "submissionCoordinator.prepareForShutdown()",
    "api.shutdown()",
    "watcher.finishShutdown()",
    "backtraceOomWatcher.finishShutdown()",
    "submissionCoordinator.finishShutdown",
    "repository.prepareForNativeBridgeShutdown()",
    "repository.finishNativeBridgeShutdown()",
)
phase_offsets = [reporter_shutdown.find(phase) for phase in shutdown_phases]
if any(offset < 0 for offset in phase_offsets) or phase_offsets != sorted(phase_offsets):
    raise SystemExit("error: native shutdown does not quiesce submissions before transport cancellation and deferred repository closure")
for value in (
    "var sessionIdentifier: String? = UUID().uuidString",
    "markerState.sessionIdentifier == currentSessionIdentifier",
    "stateIOLock",
):
    if value not in oom_watcher_source:
        raise SystemExit(f"error: OOM shutdown durability contract is missing: {value}")
for value in (
    "internal func prepareForNativeBridgeShutdown()",
    "internal func finishNativeBridgeShutdown()",
    "guard !isShutdown else { return }",
    "transactionLock.lock()",
):
    if value not in repository_source:
        raise SystemExit(f"error: retained repository shutdown contract is missing: {value}")
sanitizer_body = declaration_body(
    source,
    "static NSString *BTSanitizeBridgeLogText(",
    "BTSanitizeBridgeLogText",
)
for value in ("<redacted-url>", "<redacted-path>", "<redacted-credential>"):
    if value not in sanitizer_body:
        raise SystemExit(f"error: Unity bridge log sanitizer is missing: {value}")
log_body = declaration_body(
    source,
    "static void BTLogBridgeMessage(",
    "BTLogBridgeMessage",
)
if "BTSanitizeBridgeLogText(message)" not in log_body:
    raise SystemExit("error: Unity bridge does not sanitize bridge-owned log messages")
exception_log_body = declaration_body(
    source,
    "static void BTLogCaughtException(",
    "BTLogCaughtException",
)
for value in ("BTSanitizeBridgeLogText(exception.name", "BTSanitizedExternalDetail(exception.reason)"):
    if value not in exception_log_body:
        raise SystemExit(f"error: Unity bridge exception logging is not sanitized: {value}")
error_detail_body = declaration_body(
    source,
    "static NSString *BTInitializationErrorDetail(",
    "BTInitializationErrorDetail",
)
if "BTSanitizedExternalDetail(error.localizedDescription)" not in error_detail_body:
    raise SystemExit("error: Unity bridge initialization errors are not sanitized")
if source.count("NSLog(") != 1 or "NSLog(" not in log_body:
    raise SystemExit("error: Unity bridge bypasses its centralized sanitized NSLog path")
if "BTUnityConfiguredLogLevel != BacktraceLogLevelNone" not in source:
    raise SystemExit("error: Unity bridge does not make log level none fully silent")
for value in ("destinationsLock", "storedDestinations", "let destinationsSnapshot = destinations"):
    if value not in logger_source:
        raise SystemExit(f"error: concurrent logger destination contract is missing: {value}")
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
readonly SOURCE_VERSION="$("$VERSION_RESOLVER")"
readonly COCOA_VERSION="${BACKTRACE_VERSION:-$SOURCE_VERSION}"
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
  "MACOSX_DEPLOYMENT_TARGET=$BTUNITY_MACOS_DEPLOYMENT_TARGET" \
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
readonly STAGED_DSYM="$STAGED_OUTPUT/BacktraceMacUnity.bundle.dSYM"
mkdir -p "$STAGED_OUTPUT"
ditto "$BUILT_BUNDLE" "$STAGED_BUNDLE"
ditto "$BUILT_DSYM" "$STAGED_DSYM"

python3 "$PRIVACY_MERGER" \
  --output "$STAGED_BUNDLE/Contents/Resources/PrivacyInfo.xcprivacy" \
  "$COCOA_PRIVACY_MANIFEST" \
  "$PRIVATE_RUNTIME/PrivacyInfo.xcprivacy"

readonly STAGED_NOTICES="$STAGED_BUNDLE/Contents/Resources/ThirdPartyNotices"
[[ -f "$PRIVATE_RUNTIME/ThirdPartyNotices/PLCrashReporter-LICENSE.txt" ]] ||
  fail "the PLCrashReporter license attribution is missing"
[[ -f "$PRIVATE_RUNTIME/ThirdPartyNotices/PLCrashReporter-ThirdPartyNotices.txt" ]] ||
  fail "the PLCrashReporter third-party attribution is missing"
mkdir -p "$STAGED_NOTICES"
ditto "$PRIVATE_RUNTIME/ThirdPartyNotices/PLCrashReporter-LICENSE.txt" \
  "$STAGED_NOTICES/PLCrashReporter-LICENSE.txt"
ditto "$PRIVATE_RUNTIME/ThirdPartyNotices/PLCrashReporter-ThirdPartyNotices.txt" \
  "$STAGED_NOTICES/PLCrashReporter-ThirdPartyNotices.txt"
chmod 0644 \
  "$STAGED_NOTICES/PLCrashReporter-LICENSE.txt" \
  "$STAGED_NOTICES/PLCrashReporter-ThirdPartyNotices.txt"

[[ -f "$STAGED_BUNDLE/Contents/Resources/Model.momd/Model.mom" ]] ||
  fail "the legacy Core Data model resource is missing"
[[ -f "$STAGED_BUNDLE/Contents/Resources/Model.momd/ModelV2.mom" ]] ||
  fail "the current Core Data model resource is missing"

# Strip extended attributes before the final signing pass. No bundle content may change afterward.
xattr -cr "$STAGED_BUNDLE"
readonly SIGNING_IDENTITY="${MACOS_SIGNING_IDENTITY:--}"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$STAGED_BUNDLE"
else
  codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" "$STAGED_BUNDLE"
fi
codesign --verify --strict --verbose=2 "$STAGED_BUNDLE"

(
  cd "$STAGED_OUTPUT"
  find BacktraceMacUnity.bundle BacktraceMacUnity.bundle.dSYM \
    -type f -print | LC_ALL=C sort |
    while IFS= read -r path; do
      shasum -a 256 "$path"
    done > SHA256SUMS
)

bash "$VALIDATOR" "$STAGED_OUTPUT"

rm -rf \
  "$OUTPUT_ROOT/BacktraceMacUnity.bundle" \
  "$OUTPUT_ROOT/BacktraceMacUnity.bundle.dSYM"
# Remove the legacy generated metadata when rebuilding into an output directory
# previously used by a provenance-producing version of this script.
rm -f "$OUTPUT_ROOT/artifact-provenance.json" "$OUTPUT_ROOT/SHA256SUMS"
ditto "$STAGED_BUNDLE" "$OUTPUT_ROOT/BacktraceMacUnity.bundle"
ditto "$STAGED_DSYM" "$OUTPUT_ROOT/BacktraceMacUnity.bundle.dSYM"
ditto "$STAGED_OUTPUT/SHA256SUMS" "$OUTPUT_ROOT/SHA256SUMS"

echo "Built and validated self-contained Unity macOS bundle:"
echo "  $OUTPUT_ROOT/BacktraceMacUnity.bundle"
echo "  $OUTPUT_ROOT/BacktraceMacUnity.bundle.dSYM"
echo "  $OUTPUT_ROOT/SHA256SUMS"
