#!/usr/bin/env bash
#
# build-release.sh — Archive, export, sign, and (optionally) notarize a
# distributable FootageCalculator.app + .dmg.
#
# Prerequisites (provided by Mark — see README "Deploying"):
#   - An Apple Developer account.
#   - A "Developer ID Application" certificate installed in the login keychain
#     (for direct/DMG distribution), OR a "3rd Party Mac Developer" cert for MAS.
#   - For notarization: an app-specific password stored as a notarytool profile.
#
# Environment variables:
#   DEVELOPMENT_TEAM   Your 10-character Apple Team ID (required to sign).
#   SIGN_IDENTITY      Code-signing identity. Default: "Developer ID Application".
#   NOTARY_PROFILE     notarytool keychain profile name. If set, the script
#                      submits the DMG for notarization and staples the ticket.
#
# Usage:
#   DEVELOPMENT_TEAM=ABCDE12345 ./scripts/build-release.sh
#   DEVELOPMENT_TEAM=ABCDE12345 NOTARY_PROFILE=fc-notary ./scripts/build-release.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="FootageCalculator.xcodeproj"
SCHEME="FootageCalculator"
APP_NAME="FootageCalculator"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "error: DEVELOPMENT_TEAM is not set. Export your Apple Team ID first." >&2
  echo "       e.g. DEVELOPMENT_TEAM=ABCDE12345 $0" >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving (Release)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Automatic \
  archive

echo "==> Exporting signed app"
# Render the ExportOptions template with the real Team ID.
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
sed "s/__TEAM_ID__/$DEVELOPMENT_TEAM/g" scripts/ExportOptions.template.plist > "$EXPORT_PLIST"

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST"

APP_PATH="$EXPORT_DIR/$APP_NAME.app"
echo "==> Exported: $APP_PATH"

echo "==> Building DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$APP_PATH" \
  -ov -format UDZO \
  "$DMG_PATH"

# Sign the DMG itself with the same identity so notarization can staple it.
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "==> Submitting DMG for notarization (profile: $NOTARY_PROFILE)"
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  echo "==> Stapling notarization ticket"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
else
  echo "==> NOTARY_PROFILE not set — skipping notarization."
  echo "    The DMG is signed but NOT notarized; Gatekeeper will warn on first open."
fi

echo "==> Done: $DMG_PATH"
