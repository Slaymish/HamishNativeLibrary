#!/bin/bash
# The app project owns entitlements and nested signing. Use an existing identity; no credential setup.
set -euo pipefail
[[ $# == 5 ]] || { echo 'Usage: build-macos.sh PROJECT SCHEME VERSION BUILD ARCHIVE_PATH' >&2; exit 1; }
: "${MACOS_SIGNING_IDENTITY:?Set an existing code-signing identity, or - for an ad-hoc personal build}"
[[ "$3" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$4" =~ ^[1-9][0-9]*$ && ! -e "$5" ]] || { echo 'Invalid version/build or archive already exists' >&2; exit 1; }
xcodebuild -project "$1" -scheme "$2" -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$5" -derivedDataPath "${MACOS_DERIVED_DATA:-work/release-build}" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$MACOS_SIGNING_IDENTITY" \
  MARKETING_VERSION="$3" CURRENT_PROJECT_VERSION="$4" ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO archive
echo "Archive ready at $5. Inspect its Products/Applications app before packaging."
