#!/bin/bash -x

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Ihor Shevchuk

if [ -n "$GITHUB_BUILD" ]; then
   echo "No linting during GitHub build. It is run but separate Job! Skipping"
   exit 0
fi

echo "Start Linting..."

if [ "$1" = "--fix" ] && [ -n "$CI_BUILD" ]; then
   echo "No automatic fixing on CI! Skipping"
   exit 0
fi

if [ "$ENABLE_PREVIEWS" = "YES" ] ; then
   echo "No automatic fixing during SwiftUI preview build! Skipping"
   exit 0
fi


if command -v swiftlint >/dev/null 2>&1; then
   swiftlint "$@" --config $(dirname "$0")/swiftlint.yml
else
    echo "warning: swiftlint not installed"
fi

echo "Done Linting..."
