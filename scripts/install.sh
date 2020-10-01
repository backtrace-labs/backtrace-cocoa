#!/bin/bash
set -ex

brew bundle
pod repo update 
pod install
