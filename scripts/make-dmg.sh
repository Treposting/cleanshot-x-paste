#!/usr/bin/env bash
# Builds a universal ShotPaste.app and packages it as build/ShotPaste-<version>.dmg
# with the usual "drag to Applications" layout.
set -euo pipefail

cd "$(dirname "$0")/.."

UNIVERSAL="${UNIVERSAL:-1}" ./scripts/build-app.sh

VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)"
DMG="build/ShotPaste-${VERSION}.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R build/ShotPaste.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
# hdiutil occasionally fails with "Resource busy" on CI machines; retry a few times.
for attempt in 1 2 3; do
  if hdiutil create -volname "ShotPaste" -srcfolder "$STAGING" -ov -format UDZO "$DMG"; then
    break
  fi
  if [[ $attempt == 3 ]]; then
    echo "hdiutil failed" >&2
    exit 1
  fi
  sleep 5
done

if [[ "${SIGN_IDENTITY:--}" != "-" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" "$DMG"
fi

echo "Created $DMG"
