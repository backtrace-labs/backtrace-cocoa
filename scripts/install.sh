#!/bin/bash
set -ex

brew bundle
gem install bundler:2.1.4
bundle install
bundle exec pod repo update 
bundle exec pod install
