#!/bin/bash

PROJECT_DIR="$(dirname "$0")/.."
BUILD_PATH="${PROJECT_DIR}/.build"
WORKFLOW_XC_PATH="${PROJECT_DIR}/frameworks"
POD_PATH="${PROJECT_DIR}/Pods/PLCrashReporter"
DERIVED_DATA_PATH="${PROJECT_DIR}/.derivedData"

rm -rf ${BUILD_PATH}
rm -rf ${WORKFLOW_XC_PATH}
rm -rf ${DERIVED_DATA_PATH}
mkdir ${BUILD_PATH}
mkdir ${WORKFLOW_XC_PATH}
mkdir ${DERIVED_DATA_PATH}

xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-iOS-lib" \
    -destination "generic/platform=iOS" \
    -archivePath ${BUILD_PATH}/Backtrace-iOS-lib.xcarchive \
    -derivedDataPath ${DERIVED_DATA_PATH} \
    -configuration Release \
    DEBUG_INFORMATION_FORMAT="dwarf-with-dsym" GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO

    xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-iOS-lib" \
    -destination "generic/platform=iOS Simulator" \
    -archivePath ${BUILD_PATH}/Backtrace-iOS-Simulator-lib.xcarchive \
    -derivedDataPath ${DERIVED_DATA_PATH} \
    -configuration Release \
    DEBUG_INFORMATION_FORMAT="dwarf-with-dsym" GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO

xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-iOS-lib" \
    -destination "platform=macOS,variant=Mac Catalyst" \
    -archivePath ${BUILD_PATH}/Backtrace-iOS-MacCatalyst-lib.xcarchive \
    -derivedDataPath ${DERIVED_DATA_PATH} \
    -configuration Release \
    DEBUG_INFORMATION_FORMAT="dwarf-with-dsym" GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
    SUPPORTS_MACCATALYST=YES BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO    

xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-macOS-lib" \
    -destination "platform=macOS" \
    -archivePath ${BUILD_PATH}/Backtrace-macOS-lib.xcarchive \
    -derivedDataPath ${DERIVED_DATA_PATH} \
    -configuration Release \
    DEBUG_INFORMATION_FORMAT="dwarf-with-dsym" GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO

xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-tvOS-lib" \
    -destination "generic/platform=tvOS" \
    -archivePath ${BUILD_PATH}/Backtrace-tvOS-lib.xcarchive \
    -derivedDataPath ${DERIVED_DATA_PATH} \
    -configuration Release \
    DEBUG_INFORMATION_FORMAT="dwarf-with-dsym" GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO

    xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-tvOS-lib" \
    -destination "generic/platform=tvOS Simulator" \
    -archivePath ${BUILD_PATH}/Backtrace-tvOS-Simulator-lib.xcarchive \
    -derivedDataPath ${DERIVED_DATA_PATH} \
    -configuration Release \
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

rm -rf ${BUILD_PATH}
rm -rf ${DERIVED_DATA_PATH}

if [ ! -d "${WORKFLOW_XC_PATH}/Backtrace.xcframework" ]; then
  echo "Error: xcframework failed"
  rm -rf ${WORKFLOW_XC_PATH}
  exit 1
fi

if [ ! -d "$POD_PATH" ]; then
  echo "Error: Source directory '$POD_PATH' does not exist."
  exit 1
fi

cp -r "$POD_PATH" "$WORKFLOW_XC_PATH"
