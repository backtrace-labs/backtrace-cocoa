#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(dirname "$0")/.."
BUILD_PATH="${PROJECT_DIR}/.build"
WORKFLOW_XC_PATH="${PROJECT_DIR}/frameworks"
UNITY_WORKFLOW_XC_PATH="${PROJECT_DIR}/frameworks-unity/frameworks"
POD_PATH="${PROJECT_DIR}/Pods/PLCrashReporter"
DERIVED_DATA_PATH="${PROJECT_DIR}/.derivedData"
SOURCE_VERSION="$("${PROJECT_DIR}/scripts/current-release-version.sh")"
BACKTRACE_VERSION="${BACKTRACE_VERSION:-$SOURCE_VERSION}"

"${PROJECT_DIR}/scripts/validate-release-version.sh" "$BACKTRACE_VERSION"

rm -rf ${BUILD_PATH}
rm -rf ${WORKFLOW_XC_PATH}
rm -rf "${UNITY_WORKFLOW_XC_PATH}"
rm -rf ${DERIVED_DATA_PATH}
mkdir ${BUILD_PATH}
mkdir ${WORKFLOW_XC_PATH}
mkdir -p "${UNITY_WORKFLOW_XC_PATH}"
mkdir ${DERIVED_DATA_PATH}

xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-iOS-lib" \
    -destination "generic/platform=iOS" \
    -archivePath ${BUILD_PATH}/Backtrace-iOS-lib.xcarchive \
    -derivedDataPath ${DERIVED_DATA_PATH} \
    -configuration Release \
    MARKETING_VERSION="$BACKTRACE_VERSION" \
    DEBUG_INFORMATION_FORMAT="dwarf-with-dsym" GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO

    xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-iOS-lib" \
    -destination "generic/platform=iOS Simulator" \
    -archivePath ${BUILD_PATH}/Backtrace-iOS-Simulator-lib.xcarchive \
    -derivedDataPath ${DERIVED_DATA_PATH} \
    -configuration Release \
    MARKETING_VERSION="$BACKTRACE_VERSION" \
    DEBUG_INFORMATION_FORMAT="dwarf-with-dsym" GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO

xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-iOS-lib" \
    -destination "platform=macOS,variant=Mac Catalyst" \
    -archivePath ${BUILD_PATH}/Backtrace-iOS-MacCatalyst-lib.xcarchive \
    -derivedDataPath ${DERIVED_DATA_PATH} \
    -configuration Release \
    MARKETING_VERSION="$BACKTRACE_VERSION" \
    DEBUG_INFORMATION_FORMAT="dwarf-with-dsym" GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
    SUPPORTS_MACCATALYST=YES BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO    

xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-macOS-lib" \
    -destination "platform=macOS" \
    -archivePath ${BUILD_PATH}/Backtrace-macOS-lib.xcarchive \
    -derivedDataPath ${DERIVED_DATA_PATH} \
    -configuration Release \
    MARKETING_VERSION="$BACKTRACE_VERSION" \
    DEBUG_INFORMATION_FORMAT="dwarf-with-dsym" GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO

xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-tvOS-lib" \
    -destination "generic/platform=tvOS" \
    -archivePath ${BUILD_PATH}/Backtrace-tvOS-lib.xcarchive \
    -derivedDataPath ${DERIVED_DATA_PATH} \
    -configuration Release \
    MARKETING_VERSION="$BACKTRACE_VERSION" \
    DEBUG_INFORMATION_FORMAT="dwarf-with-dsym" GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO

    xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-tvOS-lib" \
    -destination "generic/platform=tvOS Simulator" \
    -archivePath ${BUILD_PATH}/Backtrace-tvOS-Simulator-lib.xcarchive \
    -derivedDataPath ${DERIVED_DATA_PATH} \
    -configuration Release \
    MARKETING_VERSION="$BACKTRACE_VERSION" \
    DEBUG_INFORMATION_FORMAT="dwarf-with-dsym" GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO

xcodebuild -create-xcframework \
    -archive ${BUILD_PATH}/Backtrace-iOS-lib.xcarchive -framework Backtrace.framework \
    -archive ${BUILD_PATH}/Backtrace-iOS-Simulator-lib.xcarchive -framework Backtrace.framework \
    -archive ${BUILD_PATH}/Backtrace-iOS-MacCatalyst-lib.xcarchive -framework Backtrace.framework \
    -archive ${BUILD_PATH}/Backtrace-macOS-lib.xcarchive -framework Backtrace.framework \
    -archive ${BUILD_PATH}/Backtrace-tvOS-lib.xcarchive -framework Backtrace.framework \
    -archive ${BUILD_PATH}/Backtrace-tvOS-Simulator-lib.xcarchive -framework Backtrace.framework \
    -output ${WORKFLOW_XC_PATH}/Backtrace.xcframework

# Unity's iOS package uses only device and simulator slices. Reuse the archives
# above so both release packages contain the same iOS binaries.
xcodebuild -create-xcframework \
    -archive ${BUILD_PATH}/Backtrace-iOS-lib.xcarchive -framework Backtrace.framework \
    -archive ${BUILD_PATH}/Backtrace-iOS-Simulator-lib.xcarchive -framework Backtrace.framework \
    -output "${UNITY_WORKFLOW_XC_PATH}/Backtrace.xcframework"

rm -rf ${BUILD_PATH}
rm -rf ${DERIVED_DATA_PATH}

for framework_path in "$WORKFLOW_XC_PATH" "$UNITY_WORKFLOW_XC_PATH"; do
  if [ ! -d "${framework_path}/Backtrace.xcframework" ]; then
    echo "Error: xcframework failed: $framework_path"
    rm -rf "$WORKFLOW_XC_PATH" "$UNITY_WORKFLOW_XC_PATH"
    exit 1
  fi
done

if [ ! -d "$POD_PATH" ]; then
  echo "Error: Source directory '$POD_PATH' does not exist."
  exit 1
fi

cp -r "$POD_PATH" "$WORKFLOW_XC_PATH"
cp -r "$POD_PATH" "$UNITY_WORKFLOW_XC_PATH"

# Trims only the Unity copy, including its manifest. Keeps Pods and the standard archive intact, and signs the modified XCFramework later in the release job.
python3 - "$UNITY_WORKFLOW_XC_PATH/PLCrashReporter/CrashReporter.xcframework" <<'PY'
import plistlib
import shutil
import sys
from pathlib import Path

xcframework = Path(sys.argv[1])
manifest_path = xcframework / "Info.plist"
with manifest_path.open("rb") as manifest_file:
    manifest = plistlib.load(manifest_file)

libraries = manifest["AvailableLibraries"]
unity_libraries = [
    library for library in libraries
    if library["SupportedPlatform"] == "ios"
    and library.get("SupportedPlatformVariant", "") in ("", "simulator")
]
if {library.get("SupportedPlatformVariant", "") for library in unity_libraries} != {"", "simulator"}:
    sys.exit("Error: Unity CrashReporter XCFramework requires iOS device and simulator slices")

for library in libraries:
    slice_path = xcframework / library["LibraryIdentifier"]
    if library not in unity_libraries:
        shutil.rmtree(slice_path)
    elif not (slice_path / library["LibraryPath"]).is_dir():
        sys.exit(f"Error: missing Unity CrashReporter framework: {slice_path}")

signature_path = xcframework / "_CodeSignature"
if signature_path.exists():
    shutil.rmtree(signature_path)
manifest["AvailableLibraries"] = unity_libraries
with manifest_path.open("wb") as manifest_file:
    plistlib.dump(manifest, manifest_file, sort_keys=False)
PY
