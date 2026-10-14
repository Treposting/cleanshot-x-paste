#!/usr/bin/env bash
# Builds ShotPaste.app into ./build.
#
#   ./scripts/build-app.sh                       # release build for this Mac's CPU
#   UNIVERSAL=1 ./scripts/build-app.sh           # Apple Silicon + Intel
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

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ShotPaste" "$APP/Contents/MacOS/ShotPaste"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon (generated, so there are no binary assets in the repo).
if [[ ! -f build/AppIcon.icns ]]; then
  rm -rf build/AppIcon.iconset
  if swift scripts/make-icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns; then
    :
  else
    echo "warning: could not generate the app icon" >&2
  fi
fi
[[ -f build/AppIcon.icns ]] && cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "$SIGN_IDENTITY" "$APP"

echo "Built $APP"
