#!/usr/bin/env bash

set -euo pipefail

readonly REQUIRED_TAG="1.12.0"
readonly REQUIRED_REVISION="8c61e5e38e9f737dd68512ed1ea5ab081244ad65"
readonly PREFIX="BTUnity"

fail() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  echo "Usage: $0 --source /path/to/plcrashreporter --output /path/to/output" >&2
}

SOURCE=""
OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE="$2"
      shift 2
      ;;
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

[[ -n "$SOURCE" && -n "$OUTPUT" ]] || {
  usage
  exit 64
}

for tool in ditto git lipo nm plutil python3 shasum xcodebuild; do
  command -v "$tool" >/dev/null 2>&1 || fail "required tool is unavailable: $tool"
done

readonly SOURCE_ROOT="$(cd "$SOURCE" && pwd -P)"
mkdir -p "$OUTPUT"
readonly OUTPUT_ROOT="$(cd "$OUTPUT" && pwd -P)"
[[ "$OUTPUT_ROOT" != "/" ]] || fail "refusing to use the filesystem root as output"

readonly PROJECT="$SOURCE_ROOT/CrashReporter.xcodeproj"
[[ -f "$PROJECT/project.pbxproj" ]] || fail "missing PLCrashReporter Xcode project: $PROJECT"

readonly SOURCE_REVISION="$(git -C "$SOURCE_ROOT" rev-parse HEAD)"
readonly SOURCE_TAG="$(git -C "$SOURCE_ROOT" describe --tags --exact-match 2>/dev/null || true)"
[[ "$SOURCE_REVISION" == "$REQUIRED_REVISION" ]] ||
  fail "expected PLCrashReporter revision $REQUIRED_REVISION, found $SOURCE_REVISION"
[[ "$SOURCE_TAG" == "$REQUIRED_TAG" ]] ||
  fail "expected PLCrashReporter tag $REQUIRED_TAG, found ${SOURCE_TAG:-none}"
git -C "$SOURCE_ROOT" diff --quiet || fail "PLCrashReporter checkout has local changes"
git -C "$SOURCE_ROOT" diff --cached --quiet || fail "PLCrashReporter checkout has staged changes"

readonly WORK_ROOT="$(mktemp -d "${TMPDIR:-/private/tmp}/btunity-plcrash.XXXXXX")"
cleanup() {
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

readonly PRODUCTS="$WORK_ROOT/products"
readonly OBJECTS="$WORK_ROOT/objects"
readonly DERIVED="$WORK_ROOT/derived"

CLANG_MODULE_CACHE_PATH="$WORK_ROOT/module-cache" \
xcodebuild \
  -quiet \
  -project "$PROJECT" \
  -scheme "CrashReporter macOS Static Framework" \
  -configuration Release \
  -sdk macosx \
  -derivedDataPath "$DERIVED" \
  "SYMROOT=$PRODUCTS" \
  "OBJROOT=$OBJECTS" \
  'ARCHS=arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  "GCC_PREPROCESSOR_DEFINITIONS=\$(inherited) PLCRASHREPORTER_PREFIX=$PREFIX" \
  build

readonly FRAMEWORK="$PRODUCTS/Release-macosx-static/CrashReporter.framework"
readonly FRAMEWORK_ROOT="$FRAMEWORK/Versions/A"
readonly STATIC_BINARY="$FRAMEWORK_ROOT/CrashReporter"
readonly HEADERS="$FRAMEWORK_ROOT/Headers"
readonly PRIVACY_MANIFEST="$FRAMEWORK_ROOT/Resources/PrivacyInfo.xcprivacy"

[[ -f "$STATIC_BINARY" ]] || fail "prefixed PLCrashReporter static binary was not produced"
[[ -d "$HEADERS" ]] || fail "prefixed PLCrashReporter headers were not produced"
[[ -f "$PRIVACY_MANIFEST" ]] || fail "PLCrashReporter privacy manifest was not produced"

readonly ARCHITECTURES="$(lipo -archs "$STATIC_BINARY" | tr ' ' '\n' | sed '/^$/d' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
[[ "$ARCHITECTURES" == "arm64 x86_64" ]] ||
  fail "prefixed PLCrashReporter has unexpected architectures: $ARCHITECTURES"

readonly SYMBOLS="$WORK_ROOT/symbols.txt"
nm -gU "$STATIC_BINARY" > "$SYMBOLS"
grep -Fq '_OBJC_CLASS_$_BTUnityPLCrashReporter' "$SYMBOLS" ||
  fail "prefixed PLCrashReporter class is missing"
if grep -Eq '(_OBJC_(CLASS|METACLASS)_\$_PLCrash| [A-Za-z] _PLCrash| [A-Za-z] _plcrash_)' "$SYMBOLS"; then
  fail "unprefixed PLCrashReporter symbols remain in the private runtime"
fi

rm -rf "$OUTPUT_ROOT/include"
mkdir -p "$OUTPUT_ROOT/include"
ditto "$HEADERS" "$OUTPUT_ROOT/include"
ditto "$STATIC_BINARY" "$OUTPUT_ROOT/libBTUnityCrashReporter.a"
ditto "$PRIVACY_MANIFEST" "$OUTPUT_ROOT/PrivacyInfo.xcprivacy"

python3 - "$OUTPUT_ROOT/include/BTUnityCrashReporter.h" <<'PY'
from pathlib import Path
import sys

Path(sys.argv[1]).write_text(
    "#ifndef BTUnityCrashReporter_h\n"
    "#define BTUnityCrashReporter_h\n"
    "#ifndef PLCRASHREPORTER_PREFIX\n"
    "#define PLCRASHREPORTER_PREFIX BTUnity\n"
    "#endif\n"
    "#import \"CrashReporter.h\"\n"
    "#endif\n",
    encoding="utf-8",
)
PY

python3 - "$OUTPUT_ROOT/include/module.modulemap" <<'PY'
from pathlib import Path
import sys

Path(sys.argv[1]).write_text(
    "module BTUnityCrashReporter {\n"
    "  umbrella header \"BTUnityCrashReporter.h\"\n"
    "  export *\n"
    "  module * { export * }\n"
    "}\n",
    encoding="utf-8",
)
PY

git -C "$SOURCE_ROOT" archive --format=tar "$SOURCE_REVISION" > "$WORK_ROOT/source.tar"
readonly SOURCE_ARCHIVE_SHA256="$(shasum -a 256 "$WORK_ROOT/source.tar" | awk '{print $1}')"
readonly LIBRARY_SHA256="$(shasum -a 256 "$OUTPUT_ROOT/libBTUnityCrashReporter.a" | awk '{print $1}')"

python3 - \
  "$OUTPUT_ROOT/plcrashreporter-provenance.json" \
  "$SOURCE_TAG" \
  "$SOURCE_REVISION" \
  "$SOURCE_ARCHIVE_SHA256" \
  "$PREFIX" \
  "$LIBRARY_SHA256" <<'PY'
import json
from pathlib import Path
import sys

output, tag, revision, archive_sha, prefix, library_sha = sys.argv[1:]
value = {
    "upstream_tag": tag,
    "source_revision": revision,
    "source_archive_sha256": archive_sha,
    "prefix": prefix,
    "architectures": ["arm64", "x86_64"],
    "library_sha256": library_sha,
}
Path(output).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

echo "Built prefixed PLCrashReporter $SOURCE_TAG ($SOURCE_REVISION)"
echo "  $OUTPUT_ROOT/libBTUnityCrashReporter.a"
