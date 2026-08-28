#!/usr/bin/env bash

# Single source of truth for the oldest macOS version supported by the private
# Backtrace Unity bundle. Keep this aligned with Backtrace.podspec and the public
# macOS support policy unless product requirements explicitly diverge.
readonly BTUNITY_MACOS_DEPLOYMENT_TARGET="12.0"
