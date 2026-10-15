#!/usr/bin/env bash
# Builds a universal Marquee.app and packages it as build/Marquee-<version>.dmg
# with the usual "drag to Applications" layout.
set -euo pipefail

cd "$(dirname "$0")/.."

UNIVERSAL="${UNIVERSAL:-1}" ./scripts/build-app.sh

VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)"
DMG="build/Marquee-${VERSION}.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R build/Marquee.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
# hdiutil occasionally fails with "Resource busy" on CI machines; retry a few times.
for attempt in 1 2 3; do
  if hdiutil create -volname "Marquee" -srcfolder "$STAGING" -ov -format UDZO "$DMG"; then
    break
  fi
  if [[ $attempt == 3 ]]; then
    echo "hdiutil failed" >&2
    exit 1
  fi
  sleep 5
done

# Zip of the app for in-app updates (Updater downloads Marquee-<version>.zip).
ZIP="build/Marquee-${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Marquee.app "$ZIP"
echo "Created $ZIP"

if [[ "${SIGN_IDENTITY:--}" != "-" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" "$DMG"
fi

echo "Created $DMG"
