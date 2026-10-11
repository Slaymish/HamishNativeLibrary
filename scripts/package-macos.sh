#!/bin/bash
# Packages a PREBUILT, already code-signed app. Never creates or imports signing credentials.
set -euo pipefail
umask 077
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# == 5 ]] || { echo 'Usage: package-macos.sh APP OWNER/REPO VERSION OUTPUT_DIRECTORY self-signed|notarized' >&2; exit 1; }
app="$1"; repo="$2"; version="$3"; output="$4"; mode="$5"
: "${SPARKLE_BIN:?Set the bin directory from the same Sparkle 2.10.0 distribution as the app}"
: "${SPARKLE_KEY_FILE:?Set a private Sparkle key file outside the repository}"
[[ "$mode" == self-signed || "$mode" == notarized ]] || { echo 'Invalid mode' >&2; exit 1; }
[[ -d "$app/Contents" && "$app" == *.app && ! -e "$output" ]] || { echo 'App must exist; output must not exist.' >&2; exit 1; }
[[ -x "$SPARKLE_BIN/sign_update" && -s "$SPARKLE_KEY_FILE" ]] || { echo 'Missing Sparkle signing tool/key file' >&2; exit 1; }
metadata=$(python3 "$root/scripts/appcast.py" --app "$app" --repo "$repo" --version "$version")
public=$(printf '%s\n' "$metadata" | tail -n 1)
codesign --verify --deep --strict "$app"
if [[ "$mode" == notarized ]]; then
  codesign -dv "$app" 2>&1 | /usr/bin/grep -q '^Authority=Developer ID Application:'
  xcrun stapler validate "$app"
  spctl --assess --type execute "$app"
fi
mkdir -p "$(dirname "$output")"
staging=$(mktemp -d "$(dirname "$output")/.release.XXXXXX")
trap 'rm -rf "$staging"' EXIT
name=$(basename "$app" .app)
[[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || { echo 'Use an app bundle filename without spaces for release archives.' >&2; exit 1; }
archive="$staging/$name-v$version.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
unzip -t "$archive" >/dev/null
signature=$("$SPARKLE_BIN/sign_update" --ed-key-file "$SPARKLE_KEY_FILE" -p "$archive")
swift "$root/scripts/verify-update.swift" "$archive" "$public" "$signature"
python3 "$root/scripts/appcast.py" --app "$app" --repo "$repo" --version "$version" \
  --archive "$archive" --signature "$signature" --output "$staging/appcast.xml"
"$SPARKLE_BIN/sign_update" --ed-key-file "$SPARKLE_KEY_FILE" "$staging/appcast.xml"
"$SPARKLE_BIN/sign_update" --ed-key-file "$SPARKLE_KEY_FILE" --verify "$staging/appcast.xml"
(
  cd "$staging"
  shasum -a 256 "$name-v$version.zip" appcast.xml > SHA256SUMS
)
mv "$staging" "$output"
echo "Prepared $output ($mode). Test an actual update before publishing."
