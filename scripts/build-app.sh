#!/usr/bin/env bash
# Builds Marquee.app into ./build.
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
APP="build/Marquee.app"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Marquee" "$APP/Contents/MacOS/Marquee"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon (generated, so there are no binary assets in the repo).
if [[ ! -f build/AppIcon.icns || ! -d build/Icon.xcassets ]]; then
  rm -rf build/AppIcon.iconset build/Icon.xcassets build/AppIcon.icns
  if swift scripts/make-icon.swift build/AppIcon.iconset build/Icon.xcassets && iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns; then
    :
  else
    echo "warning: could not generate the app icon" >&2
  fi
fi
[[ -f build/AppIcon.icns ]] && cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Asset catalog with the dark-mode icon (macOS 26+ picks it automatically). It also
# writes AppIcon.icns, which older macOS versions use.
if [[ -d build/Icon.xcassets ]]; then
  if xcrun actool build/Icon.xcassets --compile "$APP/Contents/Resources" \
      --platform macosx --minimum-deployment-target 13.0 --app-icon AppIcon \
      --output-partial-info-plist build/icon-info.plist --errors --warnings; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Set :CFBundleIconName AppIcon" "$APP/Contents/Info.plist"
    if [[ -n "${CI:-}" ]]; then
      echo "Icon renditions:"
      xcrun assetutil --info "$APP/Contents/Resources/Assets.car" | grep -E '"(Appearance|RenditionName)"' | sort | uniq -c || true
    fi
  else
    echo "warning: actool failed; using the light icon only" >&2
    cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  fi
fi

if ! codesign --force --sign "$SIGN_IDENTITY" "$APP"; then
  echo "warning: signing with '$SIGN_IDENTITY' failed; falling back to ad-hoc signing" >&2
  codesign --force --sign - "$APP"
fi

echo "Built $APP"
