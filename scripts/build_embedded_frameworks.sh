#!/bin/bash

PROJECT_DIR="$(dirname "$0")/.."
BUILD_PATH="${PROJECT_DIR}/.build"
WORKFLOW_XC_PATH="${PROJECT_DIR}/frameworks"
DERIVED_DATA_PATH="${PROJECT_DIR}/.derivedData"

rm -rf ${BUILD_PATH}
rm -rf ${WORKFLOW_XC_PATH}
rm -rf ${DERIVED_DATA_PATH}
mkdir ${BUILD_PATH}
mkdir ${WORKFLOW_XC_PATH}
mkdir ${DERIVED_DATA_PATH}

xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-iOS-framework" \
    -destination "generic/platform=iOS" \
    -archivePath ${BUILD_PATH}/Backtrace-iOS-framework.xcarchive \
    -derivedDataPath ${DERIVED_DATA_PATH} \
    -configuration Release \
    DEBUG_INFORMATION_FORMAT="dwarf-with-dsym" GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO

    xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-iOSIM-framework" \
    -destination "generic/platform=iOS Simulator" \
    -archivePath ${BUILD_PATH}/Backtrace-iOS-Simulator-framework.xcarchive \
    -derivedDataPath ${DERIVED_DATA_PATH} \
    -configuration Release \
    DEBUG_INFORMATION_FORMAT="dwarf-with-dsym" GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO

xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-catalyst-framework" \
    -destination "platform=macOS,variant=Mac Catalyst" \
    -archivePath ${BUILD_PATH}/Backtrace-iOS-MacCatalyst-framework.xcarchive \
    -derivedDataPath ${DERIVED_DATA_PATH} \
    -configuration Release \
    DEBUG_INFORMATION_FORMAT="dwarf-with-dsym" GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
    SUPPORTS_MACCATALYST=YES BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO    

xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-macOS-framework" \
    -destination "platform=macOS" \
    -archivePath ${BUILD_PATH}/Backtrace-macOS-framework.xcarchive \
    -derivedDataPath ${DERIVED_DATA_PATH} \
    -configuration Release \
    DEBUG_INFORMATION_FORMAT="dwarf-with-dsym" GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO

xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-tvOS-framework" \
    -destination "generic/platform=tvOS" \
    -archivePath ${BUILD_PATH}/Backtrace-tvOS-framework.xcarchive \
    -derivedDataPath ${DERIVED_DATA_PATH} \
    -configuration Release \
    DEBUG_INFORMATION_FORMAT="dwarf-with-dsym" GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO

    xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-tvOSIM-framework" \
    -destination "generic/platform=tvOS Simulator" \
    -archivePath ${BUILD_PATH}/Backtrace-tvOS-Simulator-framework.xcarchive \
    -derivedDataPath ${DERIVED_DATA_PATH} \
    -configuration Release \
    DEBUG_INFORMATION_FORMAT="dwarf-with-dsym" GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO

xcodebuild -create-xcframework \
    -archive ${BUILD_PATH}/Backtrace-iOS-framework.xcarchive -framework Backtrace.framework \
    -archive ${BUILD_PATH}/Backtrace-iOS-Simulator-framework.xcarchive -framework Backtrace.framework \
    -archive ${BUILD_PATH}/Backtrace-iOS-MacCatalyst-framework.xcarchive -framework Backtrace.framework \
    -archive ${BUILD_PATH}/Backtrace-macOS-framework.xcarchive -framework Backtrace.framework \
    -archive ${BUILD_PATH}/Backtrace-tvOS-framework.xcarchive -framework Backtrace.framework \
    -archive ${BUILD_PATH}/Backtrace-tvOS-Simulator-framework.xcarchive -framework Backtrace.framework \
    -output ${WORKFLOW_XC_PATH}/Backtrace.xcframework

rm -rf ${BUILD_PATH}
rm -rf ${DERIVED_DATA_PATH}

if [ ! -d "${WORKFLOW_XC_PATH}/Backtrace.xcframework" ]; then
  echo "Error: xcframework failed"
  rm -rf ${WORKFLOW_XC_PATH}
  exit 1
fi
