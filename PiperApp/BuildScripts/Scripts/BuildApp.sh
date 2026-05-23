#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Ihor Shevchuk

BUILD_NUMBER=$1
PLATFORM=$2

rm -fr BuildOutput

echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "PLATFORM=${PLATFORM}"

export BUILD_NUMBER

xcodebuild clean archive \
  -workspace "Piper.xcworkspace" \
  -configuration "Release" \
  -scheme Piper \
  -allowProvisioningUpdates \
  -archivePath "BuildOutput/Piper${PLATFORM}.xcarchive" \
  -destination "generic/platform=${PLATFORM}"

xcodebuild -exportArchive \
  -allowProvisioningUpdates \
  -archivePath "BuildOutput/Piper${PLATFORM}.xcarchive" \
  -exportPath "BuildOutput/binary/${PLATFORM}" \
  -exportOptionsPlist "PiperApp/BuildScripts/Configs/${PLATFORM}ExportOptions.plist"
