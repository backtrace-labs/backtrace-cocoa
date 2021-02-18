#!/bin/bash
set -o errexit # make your script exit when a command fails
set -o pipefail # to exit when the status of the last command that threw a non-zero exit code is returned
set -o nounset # to exit when your script tries to use undeclared variables
set -o xtrace # to trace what gets executed. Useful for debugging

fastlane ios tests
fastlane mac tests
fastlane tvos tests

pod lib lint --verbose --allow-warnings --sources='https://cdn.cocoapods.org/'
