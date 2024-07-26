#!/bin/bash

PROJECT_DIR="$(dirname "$0")/.."
BUILD_PATH="${PROJECT_DIR}/.build"
WORKFLOW_XC_PATH="${PROJECT_DIR}/.github/workflows/frameworks"

rm -rf ${BUILD_PATH}
rm -rf ${WORKFLOW_XC_PATH}
mkdir ${BUILD_PATH}
mkdir ${WORKFLOW_XC_PATH}


xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-iOS-lib" \
    -destination "generic/platform=iOS" \
    -archivePath ${BUILD_PATH}/Backtrace-iOS-lib.xcarchive \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO


xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-macOS-lib" \
    -destination "platform=macOS" \
    -archivePath ${BUILD_PATH}/Backtrace-macOS-lib.xcarchive \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO


xcodebuild archive \
    -workspace Backtrace.xcworkspace \
    -scheme "Backtrace-tvOS-lib" \
    -destination "generic/platform=tvOS" \
    -archivePath ${BUILD_PATH}/Backtrace-tvOS-lib.xcarchive \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO

xcodebuild -create-xcframework \
    -archive ${BUILD_PATH}/Backtrace-iOS-lib.xcarchive -framework Backtrace.framework \
    -archive ${BUILD_PATH}/Backtrace-macOS-lib.xcarchive -framework Backtrace.framework \
    -archive ${BUILD_PATH}/Backtrace-tvOS-lib.xcarchive -framework Backtrace.framework \
    -output ${WORKFLOW_XC_PATH}/Backtrace.xcframework

rm -rf ${BUILD_PATH}

