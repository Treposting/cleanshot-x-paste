#!/usr/bin/env bash
# Builds ShotPaste.app into ./build.
#
#   ./scripts/build-app.sh                 # release build, ad-hoc signed
#   SIGN_IDENTITY="My Cert" ./scripts/build-app.sh
#
# Tip: macOS ties Screen Recording / Accessibility permissions to the code
# signature. Ad-hoc signatures change on every build, so you may have to
# re-grant permissions after rebuilding. Signing with a stable identity (even a
# self-signed "Code Signing" certificate from Keychain Access) avoids that.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/ShotPaste.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ShotPaste" "$APP/Contents/MacOS/ShotPaste"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign "$SIGN_IDENTITY" "$APP"

echo "Built $APP"
