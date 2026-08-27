#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ $# -eq 1 ]] || {
  echo "Usage: $0 OUTPUT_DIRECTORY" >&2
  exit 64
}

for tool in awk codesign diff ditto dwarfdump file find grep lipo nm otool \
  plutil python3 sed shasum sort strings swift tail tr xcrun; do
  command -v "$tool" >/dev/null 2>&1 || fail "required tool is unavailable: $tool"
done

readonly OUTPUT_ROOT="$(cd "$1" && pwd -P)"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly UNITY_MACOS_CONFIG="$SCRIPT_DIR/unity-macos-config.sh"
[[ -f "$UNITY_MACOS_CONFIG" ]] || fail "required validator input is missing: $UNITY_MACOS_CONFIG"
# shellcheck source=unity-macos-config.sh
source "$UNITY_MACOS_CONFIG"
readonly BUNDLE="$OUTPUT_ROOT/BacktraceMacUnity.bundle"
readonly BINARY="$BUNDLE/Contents/MacOS/BacktraceMacUnity"
readonly INFO_PLIST="$BUNDLE/Contents/Info.plist"
readonly RESOURCES="$BUNDLE/Contents/Resources"
readonly LEGACY_MODEL="$RESOURCES/Model.momd/Model.mom"
readonly CURRENT_MODEL="$RESOURCES/Model.momd/ModelV2.mom"
readonly MODEL_VERSION="$RESOURCES/Model.momd/VersionInfo.plist"
readonly PRIVACY_MANIFEST="$RESOURCES/PrivacyInfo.xcprivacy"
readonly PLCRASHREPORTER_LICENSE="$RESOURCES/ThirdPartyNotices/PLCrashReporter-LICENSE.txt"
readonly PLCRASHREPORTER_NOTICES="$RESOURCES/ThirdPartyNotices/PLCrashReporter-ThirdPartyNotices.txt"
readonly DSYM="$OUTPUT_ROOT/BacktraceMacUnity.bundle.dSYM"
readonly PROVENANCE="$OUTPUT_ROOT/artifact-provenance.json"
readonly CHECKSUMS="$OUTPUT_ROOT/SHA256SUMS"

for required in "$BINARY" "$INFO_PLIST" "$LEGACY_MODEL" "$CURRENT_MODEL" "$MODEL_VERSION" \
  "$PRIVACY_MANIFEST" "$PLCRASHREPORTER_LICENSE" "$PLCRASHREPORTER_NOTICES" \
  "$DSYM" "$PROVENANCE" "$CHECKSUMS"; do
  [[ -e "$required" ]] || fail "required artifact is missing: $required"
done
grep -Fq 'Copyright (c) Microsoft Corporation.' "$PLCRASHREPORTER_LICENSE" ||
  fail "PLCrashReporter license attribution is incomplete"
grep -Fq 'Protobuf-c NOTICES AND INFORMATION' "$PLCRASHREPORTER_NOTICES" ||
  fail "PLCrashReporter third-party attribution is incomplete"

readonly FIRST_SYMLINK="$(find "$BUNDLE" -type l -print -quit)"
[[ -z "$FIRST_SYMLINK" ]] || fail "bundle contains a UPM-unsafe symlink: $FIRST_SYMLINK"

readonly FORBIDDEN_LAYOUT="$(find "$BUNDLE" \
  \( -name '*.framework' -o -name Versions -o -name BacktraceResources.bundle \) \
  -print -quit)"
[[ -z "$FORBIDDEN_LAYOUT" ]] || fail "bundle contains forbidden nested layout: $FORBIDDEN_LAYOUT"
[[ ! -e "$BUNDLE/Contents/Frameworks" ]] || fail "bundle must not contain Contents/Frameworks"

normalized_architectures() {
  lipo -archs "$1" | tr ' ' '\n' | sed '/^$/d' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'
}

readonly ARCHITECTURES="$(normalized_architectures "$BINARY")"
[[ "$ARCHITECTURES" == "arm64 x86_64" ]] ||
  fail "bundle executable must contain exactly arm64 and x86_64; found: $ARCHITECTURES"

readonly BUNDLE_HEADERS="$(otool -hv "$BINARY" | awk '$5 == "BUNDLE" { count += 1 } END { print count + 0 }')"
[[ "$BUNDLE_HEADERS" == "2" ]] || fail "bundle executable is not MH_BUNDLE for both architectures"

readonly BUILD_PLATFORMS="$(xcrun vtool -show-build "$BINARY" |
  awk '$1 == "platform" { print $2 }' | LC_ALL=C sort -u)"
[[ "$BUILD_PLATFORMS" == "MACOS" ]] || fail "unexpected build platform: $BUILD_PLATFORMS"
readonly MINIMUM_VERSIONS="$(xcrun vtool -show-build "$BINARY" |
  awk '$1 == "minos" { print $2 }' | LC_ALL=C sort -u)"
[[ "$MINIMUM_VERSIONS" == "$BTUNITY_MACOS_DEPLOYMENT_TARGET" ]] ||
  fail "unexpected minimum macOS version: $MINIMUM_VERSIONS"

while IFS= read -r dependency; do
  case "$dependency" in
    /System/Library/*|/usr/lib/*) ;;
    *) fail "bundle contains a non-system dynamic dependency: $dependency" ;;
  esac
done < <(otool -L "$BINARY" | awk '/^\t/ {print $1}')

readonly GLOBAL_SYMBOLS="$(nm -gU "$BINARY")"
for symbol in \
  _BacktraceUnityBridgeVersion \
  _SetBacktraceLogLevel \
  _StartBacktraceIntegrationV3 \
  _StartBacktraceIntegrationV2 \
  _StartBacktraceIntegration \
  _GetAttributes \
  _FreeAttributes \
  _NativeReport \
  _AddAttribute \
  _BtCrash \
  _Disable; do
  grep -Eq "(^|[[:space:]])${symbol}$" <<<"$GLOBAL_SYMBOLS" || fail "required ABI export is missing: $symbol"
done

readonly ALL_SYMBOLS="$(nm -m "$BINARY")"
grep -Fq '_OBJC_CLASS_$_BTUnityPLCrashReporter' <<<"$ALL_SYMBOLS" ||
  fail "private BTUnityPLCrashReporter runtime is missing"
if grep -Eq '(_OBJC_(CLASS|METACLASS)_\$_PLCrash| [A-Za-z] _PLCrash| [A-Za-z] _plcrash_)' <<<"$ALL_SYMBOLS"; then
  fail "bundle contains unprefixed PLCrashReporter definitions"
fi

readonly BINARY_STRINGS="$(strings -a "$BINARY")"
grep -Fxq 'Backtrace/NativeCrash/v1/plcrash' <<<"$BINARY_STRINGS" ||
  fail "bundle does not declare the versioned isolated crash-storage contract"
grep -Fq 'io.backtrace.unity.legacy.' <<<"$BINARY_STRINGS" ||
  fail "bundle does not contain a per-application legacy storage fallback"
grep -Fxq 'BacktraceUnityExceptionContract:all-c-exports-contained-v1' <<<"$BINARY_STRINGS" ||
  fail "bundle does not declare the C-export exception-containment contract"
grep -Fxq 'BacktraceUnityLifecycleContract:process-lifetime-handler-distinct-disabled-v2' <<<"$BINARY_STRINGS" ||
  fail "bundle does not declare the process-lifetime crash-handler contract"
grep -Fxq 'BacktraceUnityLoggingContract:warning-default-explicit-setter-silent-none-redacted-v3' <<<"$BINARY_STRINGS" ||
  fail "bundle does not declare the native logging contract"

(
readonly RUNTIME_TEST_ROOT="$(mktemp -d "${TMPDIR:-/private/tmp}/btunity-runtime.XXXXXX")"
cleanup_runtime_test() {
  rm -rf "$RUNTIME_TEST_ROOT"
}
trap cleanup_runtime_test EXIT
mkdir -p "$RUNTIME_TEST_ROOT/home" "$RUNTIME_TEST_ROOT/plcrash"

# Exercise the V2/V3 pre-existing-shared-client distinction in a dedicated process. The
# protocol-only Objective-C fixture is sufficient for the preflight check but must never be
# allowed to reach real BacktraceClient initialization or process teardown.
CFFIXED_USER_HOME="$RUNTIME_TEST_ROOT/home" python3 - \
  "$BINARY" \
  "$RUNTIME_TEST_ROOT/plcrash" <<'PY'
import ctypes
import os
import sys

library = ctypes.CDLL(sys.argv[1])
char_pointer = ctypes.POINTER(ctypes.c_char_p)

start_v3 = library.StartBacktraceIntegrationV3
start_v3.argtypes = [
    ctypes.c_char_p,
    char_pointer,
    char_pointer,
    ctypes.c_int32,
    ctypes.c_bool,
    char_pointer,
    ctypes.c_int32,
    ctypes.c_bool,
    ctypes.c_int32,
    ctypes.c_char_p,
]
start_v3.restype = ctypes.c_int32
start_v2 = library.StartBacktraceIntegrationV2
start_v2.argtypes = start_v3.argtypes[:-1]
start_v2.restype = ctypes.c_int32

set_log_level = library.SetBacktraceLogLevel
set_log_level.argtypes = [ctypes.c_int32]
set_log_level.restype = ctypes.c_int32
if set_log_level(4) != 0:
    raise SystemExit("error: bridge rejected the none log level in V2 compatibility test")

objc = ctypes.CDLL("/usr/lib/libobjc.A.dylib")
objc.objc_getClass.argtypes = [ctypes.c_char_p]
objc.objc_getClass.restype = ctypes.c_void_p
objc.sel_registerName.argtypes = [ctypes.c_char_p]
objc.sel_registerName.restype = ctypes.c_void_p
objc.objc_allocateClassPair.argtypes = [
    ctypes.c_void_p,
    ctypes.c_char_p,
    ctypes.c_size_t,
]
objc.objc_allocateClassPair.restype = ctypes.c_void_p
objc.class_copyProtocolList.argtypes = [
    ctypes.c_void_p,
    ctypes.POINTER(ctypes.c_uint),
]
objc.class_copyProtocolList.restype = ctypes.POINTER(ctypes.c_void_p)
objc.class_addProtocol.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
objc.class_addProtocol.restype = ctypes.c_bool
objc.objc_registerClassPair.argtypes = [ctypes.c_void_p]
objc.objc_registerClassPair.restype = None

client_class = objc.objc_getClass(b"_TtC9Backtrace15BacktraceClient")
object_class = objc.objc_getClass(b"NSObject")
if not client_class or not object_class:
    raise SystemExit("error: could not resolve Objective-C classes for V2 compatibility test")

validator_class = objc.objc_allocateClassPair(
    object_class,
    b"BTUnityValidatorSharedClient",
    0,
)
if not validator_class:
    raise SystemExit("error: could not allocate V2 compatibility test class")

protocol_count = ctypes.c_uint(0)
protocols = objc.class_copyProtocolList(client_class, ctypes.byref(protocol_count))
if not protocols or protocol_count.value == 0:
    raise SystemExit("error: BacktraceClient exposes no Objective-C protocols")
for index in range(protocol_count.value):
    if not objc.class_addProtocol(validator_class, protocols[index]):
        raise SystemExit("error: could not mirror a BacktraceClient protocol")
objc.objc_registerClassPair(validator_class)

message_address = ctypes.cast(objc.objc_msgSend, ctypes.c_void_p).value
send_id = ctypes.CFUNCTYPE(
    ctypes.c_void_p,
    ctypes.c_void_p,
    ctypes.c_void_p,
)(message_address)
send_void_id = ctypes.CFUNCTYPE(
    None,
    ctypes.c_void_p,
    ctypes.c_void_p,
    ctypes.c_void_p,
)(message_address)
instance = send_id(validator_class, objc.sel_registerName(b"new"))
if not instance:
    raise SystemExit("error: could not instantiate V2 compatibility test client")
send_void_id(client_class, objc.sel_registerName(b"setShared:"), instance)

arguments = (
    b"https://submit.backtrace.io/example/example/plcrash",
    None,
    None,
    0,
    False,
    None,
    0,
    False,
    0,
    sys.argv[2].encode(),
)
legacy_shared_result = start_v2(*arguments[:-1])
v3_shared_result = start_v3(*arguments)
if legacy_shared_result != 1:
    raise SystemExit(
        "error: V2 must preserve alreadyInitialized for an unrelated shared client; "
        f"found {legacy_shared_result}"
    )
if v3_shared_result != 5:
    raise SystemExit(
        "error: V3 must reject an unrelated shared client as clientInitializationFailed; "
        f"found {v3_shared_result}"
    )

# Avoid tearing down a deliberately method-less protocol fixture in the Swift runtime.
os._exit(0)
PY

CFFIXED_USER_HOME="$RUNTIME_TEST_ROOT/home" python3 - \
  "$BINARY" \
  "$RUNTIME_TEST_ROOT/plcrash" <<'PY'
import ctypes
import os
import sys
from pathlib import Path

library = ctypes.CDLL(sys.argv[1])
version = library.BacktraceUnityBridgeVersion
version.argtypes = []
version.restype = ctypes.c_int32
actual = version()
if actual != 3:
    raise SystemExit(f"error: expected bridge ABI version 3, found {actual}")

set_log_level = library.SetBacktraceLogLevel
set_log_level.argtypes = [ctypes.c_int32]
set_log_level.restype = ctypes.c_int32
if set_log_level(99) != 2:
    raise SystemExit("error: bridge did not reject an invalid log level")

char_pointer = ctypes.POINTER(ctypes.c_char_p)
start = library.StartBacktraceIntegrationV3
start.argtypes = [
    ctypes.c_char_p,
    char_pointer,
    char_pointer,
    ctypes.c_int32,
    ctypes.c_bool,
    char_pointer,
    ctypes.c_int32,
    ctypes.c_bool,
    ctypes.c_int32,
    ctypes.c_char_p,
]
start.restype = ctypes.c_int32

def capture_stderr(callback):
    read_fd, write_fd = os.pipe()
    saved_stderr = os.dup(2)
    os.dup2(write_fd, 2)
    os.close(write_fd)
    try:
        result = callback()
        ctypes.CDLL(None).fflush(None)
    finally:
        os.dup2(saved_stderr, 2)
        os.close(saved_stderr)
    output = os.read(read_fd, 1024 * 1024)
    os.close(read_fd)
    return result, output

# Level `none` must silence both BacktraceLogger destinations and bridge-owned
# NSLog/fprintf fallbacks. Trigger a deterministic invalid-arguments diagnostic.
if set_log_level(4) != 0:
    raise SystemExit("error: bridge rejected the none log level")
silent_result, silent_output = capture_stderr(
    lambda: start(None, None, None, 0, False, None, 0, False, 0, sys.argv[2].encode())
)
if silent_result != 2:
    raise SystemExit(f"error: silent logging smoke test returned {silent_result}, expected 2")
if b"[Backtrace]" in silent_output:
    raise SystemExit("error: Backtrace bridge emitted output at log level none")
if set_log_level(1) != 0:
    raise SystemExit("error: bridge rejected the warning log level")

credential_sentinel = b"BTUNITY_CREDENTIAL_SENTINEL_DO_NOT_LOG"
parent_path_sentinel = "BTUNITY_PARENT_PATH_SENTINEL_DO_NOT_LOG"
path_sentinel = "BTUNITY_PATH_SENTINEL_DO_NOT_LOG"
submission_url = b"https://submit.backtrace.io/example/" + credential_sentinel + b"/plcrash"
blocked_parent = Path(sys.argv[2]).with_name(parent_path_sentinel)
blocked_parent.write_text("not a directory", encoding="utf-8")
blocked_storage_path = blocked_parent / path_sentinel
storage_failure_arguments = (
    submission_url,
    None,
    None,
    0,
    False,
    None,
    0,
    False,
    0,
    str(blocked_storage_path).encode(),
)
storage_failure_result, storage_failure_output = capture_stderr(
    lambda: start(*storage_failure_arguments)
)
if storage_failure_result != 3:
    raise SystemExit(
        "error: invalid storage smoke test must fail before handler installation; "
        f"found {storage_failure_result}"
    )
for sentinel in (
    credential_sentinel,
    parent_path_sentinel.encode(),
    path_sentinel.encode(),
    str(blocked_storage_path).encode(),
):
    if sentinel in storage_failure_output:
        raise SystemExit("error: bridge storage diagnostic disclosed a sentinel value")
if b"<redacted-detail>" not in storage_failure_output:
    raise SystemExit("error: bridge storage diagnostic did not exercise external-detail redaction")

invalid_url = b"invalid://" + credential_sentinel
invalid_url_result, invalid_url_output = capture_stderr(
    lambda: start(
        invalid_url,
        None,
        None,
        0,
        False,
        None,
        0,
        False,
        0,
        sys.argv[2].encode(),
    )
)
if invalid_url_result != 4:
    raise SystemExit(f"error: invalid URL redaction smoke test returned {invalid_url_result}")
if credential_sentinel in invalid_url_output or invalid_url in invalid_url_output:
    raise SystemExit("error: bridge URL diagnostic disclosed a sentinel credential")
PY

# Python command-line hosts do not carry the AppKit application metadata that
# ScreenInfo's immutable defaults need. Exercise the real initialization lifecycle
# in a Swift/AppKit host while retaining Python for the preflight-only checks above.
mkdir -p "$RUNTIME_TEST_ROOT/swift-module-cache"
CLANG_MODULE_CACHE_PATH="$RUNTIME_TEST_ROOT/swift-module-cache" \
SWIFT_MODULECACHE_PATH="$RUNTIME_TEST_ROOT/swift-module-cache" \
CFFIXED_USER_HOME="$RUNTIME_TEST_ROOT/home" \
swift - "$BINARY" "$RUNTIME_TEST_ROOT/plcrash" <<'SWIFT'
import AppKit
import Darwin
import Foundation

typealias StartV3 = @convention(c) (
    UnsafePointer<CChar>?,
    UnsafePointer<UnsafePointer<CChar>?>?,
    UnsafePointer<UnsafePointer<CChar>?>?,
    Int32,
    Bool,
    UnsafePointer<UnsafePointer<CChar>?>?,
    Int32,
    Bool,
    Int32,
    UnsafePointer<CChar>?
) -> Int32
typealias Disable = @convention(c) () -> Void
typealias GetAttributes = @convention(c) (
    UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    UnsafeMutablePointer<Int32>?
) -> Void
typealias SetLogLevel = @convention(c) (Int32) -> Int32

guard CommandLine.arguments.count == 3 else {
    fatalError("error: lifecycle smoke test requires a bundle and storage path")
}
guard let handle = dlopen(CommandLine.arguments[1], RTLD_NOW | RTLD_LOCAL) else {
    fatalError("error: could not load bundle: \(String(cString: dlerror()))")
}

func loadSymbol<T>(_ name: String, as type: T.Type) -> T {
    guard let address = dlsym(handle, name) else {
        fatalError("error: required lifecycle symbol is missing: \(name)")
    }
    return unsafeBitCast(address, to: type)
}

let start = loadSymbol("StartBacktraceIntegrationV3", as: StartV3.self)
let disable = loadSymbol("Disable", as: Disable.self)
let getAttributes = loadSymbol("GetAttributes", as: GetAttributes.self)
let setLogLevel = loadSymbol("SetBacktraceLogLevel", as: SetLogLevel.self)
guard setLogLevel(4) == 0 else {
    fatalError("error: bridge rejected the none log level in lifecycle smoke test")
}

let submissionURL = "https://submit.backtrace.io/example/example/plcrash"
let storagePath = CommandLine.arguments[2]
func startIntegration(with submissionURL: String = submissionURL) -> Int32 {
    submissionURL.withCString { submissionURLPointer in
        storagePath.withCString { storagePathPointer in
            start(
                submissionURLPointer,
                nil,
                nil,
                0,
                false,
                nil,
                0,
                false,
                0,
                storagePathPointer
            )
        }
    }
}

// A failure before PLCrashReporter enable must not latch process-wide handler state.
let invalidURLResult = startIntegration(with: "invalid://pre-enable-lifecycle-check")
guard invalidURLResult == 4 else {
    fatalError(
        "error: pre-enable lifecycle check must return invalidSubmissionUrl; " +
        "found \(invalidURLResult)"
    )
}
guard startIntegration() == 0 else {
    fatalError("error: lifecycle smoke-test start failed")
}
let activeResult = startIntegration()
guard activeResult == 1 else {
    fatalError(
        "error: a second start while active must return alreadyInitializedActive; " +
        "found \(activeResult)"
    )
}

disable()
var entries: UnsafeMutableRawPointer?
var entryCount: Int32 = -1
getAttributes(&entries, &entryCount)
guard entries == nil && entryCount == 0 else {
    fatalError("error: Disable did not deactivate managed bridge operations")
}

let disabledResult = startIntegration()
guard disabledResult == 7 else {
    fatalError(
        "error: Start/Disable/Start must retain the process-lifetime handler " +
        "and return processLifetimeDisabled; found \(disabledResult)"
    )
}
SWIFT
)

plutil -lint "$INFO_PLIST" >/dev/null
plutil -lint "$PRIVACY_MANIFEST" >/dev/null
readonly CURRENT_MODEL_VERSION="$(plutil -extract NSManagedObjectModel_CurrentVersionName raw -o - "$MODEL_VERSION")"
[[ "$CURRENT_MODEL_VERSION" == "ModelV2" ]] ||
  fail "unexpected current Core Data model version: $CURRENT_MODEL_VERSION"
readonly BUNDLE_IDENTIFIER="$(plutil -extract CFBundleIdentifier raw -o - "$INFO_PLIST")"
readonly BUNDLE_EXECUTABLE="$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")"
readonly BUNDLE_TYPE="$(plutil -extract CFBundlePackageType raw -o - "$INFO_PLIST")"
readonly PLIST_MINIMUM="$(plutil -extract LSMinimumSystemVersion raw -o - "$INFO_PLIST")"
[[ "$BUNDLE_IDENTIFIER" == "io.backtrace.unity.macos" ]] ||
  fail "unexpected bundle identifier: $BUNDLE_IDENTIFIER"
[[ "$BUNDLE_EXECUTABLE" == "BacktraceMacUnity" ]] ||
  fail "unexpected bundle executable: $BUNDLE_EXECUTABLE"
[[ "$BUNDLE_TYPE" == "BNDL" ]] || fail "unexpected package type: $BUNDLE_TYPE"
[[ "$PLIST_MINIMUM" == "$BTUNITY_MACOS_DEPLOYMENT_TARGET" ]] ||
  fail "unexpected plist deployment target: $PLIST_MINIMUM"

python3 - "$PRIVACY_MANIFEST" <<'PY'
import plistlib
from pathlib import Path
import sys

path = Path(sys.argv[1])
with path.open("rb") as stream:
    manifest = plistlib.load(stream)
if manifest.get("NSPrivacyTracking") is not False:
    raise SystemExit("error: privacy manifest must explicitly disable tracking")
if manifest.get("NSPrivacyTrackingDomains") != []:
    raise SystemExit("error: privacy manifest must not contain tracking domains")

accessed = {
    item["NSPrivacyAccessedAPIType"]: set(item["NSPrivacyAccessedAPITypeReasons"])
    for item in manifest.get("NSPrivacyAccessedAPITypes", [])
}
required_accessed = {
    "NSPrivacyAccessedAPICategorySystemBootTime": {"35F9.1"},
    "NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1"},
}
for api_type, reasons in required_accessed.items():
    if not reasons.issubset(accessed.get(api_type, set())):
        raise SystemExit(f"error: privacy manifest is missing {api_type}: {sorted(reasons)}")

collected = {
    item["NSPrivacyCollectedDataType"]: item
    for item in manifest.get("NSPrivacyCollectedDataTypes", [])
}
required_collected = {
    "NSPrivacyCollectedDataTypeCrashData": {
        "NSPrivacyCollectedDataTypePurposeAnalytics",
        "NSPrivacyCollectedDataTypePurposeAppFunctionality",
    },
    "NSPrivacyCollectedDataTypeOtherDiagnosticData": {
        "NSPrivacyCollectedDataTypePurposeAppFunctionality",
    },
}
for data_type, purposes in required_collected.items():
    item = collected.get(data_type)
    if item is None:
        raise SystemExit(f"error: privacy manifest is missing {data_type}")
    if not purposes.issubset(set(item.get("NSPrivacyCollectedDataTypePurposes", []))):
        raise SystemExit(f"error: privacy manifest has incomplete purposes for {data_type}")
    if item.get("NSPrivacyCollectedDataTypeTracking") is not False:
        raise SystemExit(f"error: privacy manifest marks {data_type} as tracking")
PY

uuid_set() {
  dwarfdump --uuid "$1" | awk '{print toupper($2) " " $3}' | LC_ALL=C sort
}

readonly BINARY_UUIDS="$(uuid_set "$BINARY")"
readonly DSYM_UUIDS="$(uuid_set "$DSYM")"
[[ "$BINARY_UUIDS" == "$DSYM_UUIDS" ]] || fail "binary and dSYM UUIDs do not match"
readonly DSYM_ARCHITECTURES="$(normalized_architectures "$DSYM/Contents/Resources/DWARF/BacktraceMacUnity")"
[[ "$DSYM_ARCHITECTURES" == "arm64 x86_64" ]] || fail "dSYM does not contain both architectures"
readonly COMPILE_UNITS="$(dwarfdump --debug-info "$DSYM" |
  awk '$2 == "DW_TAG_compile_unit" { count += 1 } END { print count + 0 }')"
(( COMPILE_UNITS > 0 )) || fail "dSYM contains no debug compile units"

codesign --verify --strict --verbose=2 "$BUNDLE"

(
  cd "$OUTPUT_ROOT"
  shasum -a 256 -c SHA256SUMS
)

readonly GENERATED_MANIFEST="$(mktemp "${TMPDIR:-/private/tmp}/btunity-bundle-manifest.XXXXXX")"
cleanup_manifest() {
  rm -f "$GENERATED_MANIFEST"
}
trap cleanup_manifest EXIT
(
  cd "$OUTPUT_ROOT"
  find BacktraceMacUnity.bundle -type f -print | LC_ALL=C sort |
    while IFS= read -r path; do
      shasum -a 256 "$path"
    done
) > "$GENERATED_MANIFEST"
readonly BUNDLE_SHA256="$(shasum -a 256 "$GENERATED_MANIFEST" | awk '{print $1}')"
readonly BINARY_SHA256="$(shasum -a 256 "$BINARY" | awk '{print $1}')"

python3 - \
  "$PROVENANCE" \
  "$BUNDLE_SHA256" \
  "$BINARY_SHA256" \
  "$BINARY_UUIDS" \
  "$BTUNITY_MACOS_DEPLOYMENT_TARGET" \
  "${BTUNITY_REQUIRE_CLEAN_SOURCE:-0}" <<'PY'
import json
import hashlib
from pathlib import Path
import sys

path, bundle_sha, binary_sha, uuid_lines, deployment_target, require_clean = sys.argv[1:]
with Path(path).open(encoding="utf-8") as stream:
    value = json.load(stream)
expected = {
    "schema_version": 1,
    "artifact": "BacktraceMacUnity.bundle",
    "architectures": ["arm64", "x86_64"],
    "deployment_target": deployment_target,
    "bundle_identifier": "io.backtrace.unity.macos",
    "bridge_abi_version": 3,
    "bundle_sha256": bundle_sha,
    "binary_sha256": binary_sha,
}
for key, expected_value in expected.items():
    if value.get(key) != expected_value:
        raise SystemExit(f"error: provenance {key} mismatch: {value.get(key)!r}")
if require_clean == "1" and value.get("backtrace_cocoa", {}).get("dirty") is not False:
    raise SystemExit("error: release validation requires clean Backtrace Cocoa source provenance")
if value.get("plcrashreporter", {}).get("upstream_tag") != "1.12.0":
    raise SystemExit("error: provenance has an unexpected PLCrashReporter tag")
if value.get("plcrashreporter", {}).get("prefix") != "BTUnity":
    raise SystemExit("error: provenance has an unexpected PLCrashReporter prefix")
expected_notice_paths = {
    "BacktraceMacUnity.bundle/Contents/Resources/ThirdPartyNotices/PLCrashReporter-LICENSE.txt",
    "BacktraceMacUnity.bundle/Contents/Resources/ThirdPartyNotices/PLCrashReporter-ThirdPartyNotices.txt",
}
recorded_notices = value.get("third_party_notices", [])
if {item.get("path") for item in recorded_notices} != expected_notice_paths:
    raise SystemExit("error: provenance has incomplete PLCrashReporter attribution paths")
for item in recorded_notices:
    if item.get("component") != "PLCrashReporter":
        raise SystemExit("error: provenance has an unexpected third-party notice component")
    notice_path = Path(path).parent / item["path"]
    if not notice_path.is_file():
        raise SystemExit(f"error: attributed notice is missing: {notice_path}")
    digest = hashlib.sha256(notice_path.read_bytes()).hexdigest()
    if item.get("sha256") != digest:
        raise SystemExit(f"error: attributed notice checksum mismatch: {notice_path}")
bridge = value.get("unity_bridge", {})
if bridge.get("storage_contract") != "all-entry-points-isolated-v1":
    raise SystemExit("error: provenance has an unexpected Unity bridge storage contract")
if bridge.get("exception_contract") != "all-c-exports-contained-v1":
    raise SystemExit("error: provenance has an unexpected Unity bridge exception contract")
expected_initialization_results = {
    "success": 0,
    "already_initialized_active": 1,
    "invalid_arguments": 2,
    "storage_initialization_failed": 3,
    "invalid_submission_url": 4,
    "client_initialization_failed": 5,
    "unexpected_failure": 6,
    "process_lifetime_disabled": 7,
}
if bridge.get("initialization_results") != expected_initialization_results:
    raise SystemExit("error: provenance has unexpected Unity bridge initialization results")
if bridge.get("lifecycle_contract") != "process-lifetime-handler-distinct-disabled-v2":
    raise SystemExit("error: provenance has an unexpected Unity bridge lifecycle contract")
if bridge.get("logging_contract") != "warning-default-explicit-setter-silent-none-redacted-v3":
    raise SystemExit("error: provenance has an unexpected Unity bridge logging contract")
if not __import__("re").fullmatch(r"[0-9a-f]{64}", bridge.get("source_sha256", "")):
    raise SystemExit("error: provenance has an invalid Unity bridge source hash")
if value.get("toolchain", {}).get("host_architecture") not in {"arm64", "x86_64"}:
    raise SystemExit("error: provenance has an invalid build-host architecture")
expected_uuids = sorted(line.split()[0] for line in uuid_lines.splitlines())
recorded_uuids = sorted(item["uuid"] for item in value.get("binary_uuids", []))
if recorded_uuids != expected_uuids:
    raise SystemExit("error: provenance binary UUIDs do not match")
PY

readonly ROUND_TRIP_ROOT="$(mktemp -d "${TMPDIR:-/private/tmp}/btunity-bundle-roundtrip.XXXXXX")"
cleanup_round_trip() {
  rm -rf "$ROUND_TRIP_ROOT"
}
trap 'cleanup_manifest; cleanup_round_trip' EXIT
ditto -c -k --keepParent "$BUNDLE" "$ROUND_TRIP_ROOT/bundle.zip"
mkdir -p "$ROUND_TRIP_ROOT/extracted"
ditto -x -k "$ROUND_TRIP_ROOT/bundle.zip" "$ROUND_TRIP_ROOT/extracted"
readonly EXTRACTED_BUNDLE="$ROUND_TRIP_ROOT/extracted/BacktraceMacUnity.bundle"
[[ -d "$EXTRACTED_BUNDLE" ]] || fail "archive round trip did not preserve the bundle"
[[ -z "$(find "$EXTRACTED_BUNDLE" -type l -print -quit)" ]] ||
  fail "archive round trip introduced a symlink"
codesign --verify --strict --verbose=2 "$EXTRACTED_BUNDLE"
(
  cd "$ROUND_TRIP_ROOT/extracted"
  find BacktraceMacUnity.bundle -type f -print | LC_ALL=C sort |
    while IFS= read -r path; do
      shasum -a 256 "$path"
    done
) > "$ROUND_TRIP_ROOT/extracted-manifest.sha256"
diff -u "$GENERATED_MANIFEST" "$ROUND_TRIP_ROOT/extracted-manifest.sha256" >/dev/null ||
  fail "archive round trip changed bundle contents"

echo "Validated self-contained BacktraceMacUnity.bundle"
echo "  identifier: $BUNDLE_IDENTIFIER"
echo "  architectures: $ARCHITECTURES"
echo "  minimum macOS: $MINIMUM_VERSIONS"
echo "  bridge ABI: 3"
echo "  bundle SHA-256: $BUNDLE_SHA256"
