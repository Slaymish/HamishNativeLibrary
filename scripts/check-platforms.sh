#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../Examples/NativeDemo"
xcodegen generate --spec project.yml
for target in NativeDemoMac NativeDemoPhone; do
  destination='generic/platform=macOS'
  [[ "$target" == NativeDemoPhone ]] && destination='generic/platform=iOS Simulator'
  xcodebuild -project NativeDemo.xcodeproj -scheme "$target" -destination "$destination" \
    -derivedDataPath ../../work/platform-build CODE_SIGNING_ALLOWED=NO build -quiet
done
