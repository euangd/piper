#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Ihor Shevchuk

BUILD_NUMBER="${1:-0}"

HOST_ARCH="$(uname -m)"
if [ "$HOST_ARCH" = "arm64" ]; then
  # On Apple Silicon, building for the generic iOS Simulator destination can trigger a universal
  # (arm64+x86_64) build. Force arm64 to avoid x86_64-only dependency/link issues.
  SIM_ARCHS="arm64"
  EXCLUDED_SIM_ARCHS="x86_64"
else
  # Intel Macs only support x86_64 iOS Simulator slices.
  SIM_ARCHS="x86_64"
  EXCLUDED_SIM_ARCHS="arm64"
fi

xcodebuild build \
  -workspace "Piper.xcworkspace" \
  -scheme Piper \
  -configuration "Release" \
  -sdk iphonesimulator \
  -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS="$SIM_ARCHS" \
  EXCLUDED_ARCHS="$EXCLUDED_SIM_ARCHS" \
  ONLY_ACTIVE_ARCH=YES \
  COPY_PHASE_STRIP=NO \
  STRIP_INSTALLED_PRODUCT=NO \
  DEPLOYMENT_POSTPROCESSING=NO

