#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FocusLens"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
DMG_DIR="$ROOT_DIR/dist/dmg"
DMG_PATH="$ROOT_DIR/dist/$APP_NAME.dmg"
IDENTITY="${CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-focuslens-notary}"

if [[ -z "$IDENTITY" ]]; then
    echo "Set CODESIGN_IDENTITY to your Developer ID Application identity." >&2
    echo "Example: CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' $0" >&2
    exit 1
fi

if ! security find-identity -v -p codesigning | grep -F "$IDENTITY" >/dev/null; then
    echo "Code signing identity not found: $IDENTITY" >&2
    security find-identity -v -p codesigning >&2
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "Notary profile not found or invalid: $NOTARY_PROFILE" >&2
    echo "Create it first with:" >&2
    echo "xcrun notarytool store-credentials '$NOTARY_PROFILE' --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID --password APP_SPECIFIC_PASSWORD" >&2
    exit 1
fi

"$ROOT_DIR/scripts/build_app.sh"

codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
spctl --assess --type execute --verbose=2 "$APP_DIR" || true

rm -rf "$DMG_DIR" "$DMG_PATH"
mkdir -p "$DMG_DIR"
cp -R "$APP_DIR" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "Built signed and notarized release: $DMG_PATH"
