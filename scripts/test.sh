#!/bin/bash
set -ex

fastlane ios tests
fastlane mac tests
fastlane tvos tests

pod lib lint --verbose --allow-warnings --sources='https://cdn.cocoapods.org/'