#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="VoiceInput"
SCHEME="VoiceInput"
PROJECT_FILE="VoiceInput.xcodeproj"
CONFIGURATION="Release"
DERIVED_DATA_PATH="$PROJECT_DIR/.build/release"
DIST_DIR="$PROJECT_DIR/dist"
DMG_NAME="${APP_NAME}-macOS.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
APP_OUT_PATH="$DIST_DIR/${APP_NAME}.app"
STAGING_DIR="$DIST_DIR/.dmg-root"

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
TEAM_ID="${TEAM_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-1}"
RUN_XCODEGEN="${RUN_XCODEGEN:-0}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Build signed Release app and package DMG for drag-to-Applications install.

Options:
  --identity <name>         Developer ID Application identity name/hash
  --team-id <TEAMID>        Override DEVELOPMENT_TEAM during build
  --notary-profile <name>   notarytool keychain profile (enables notarization)
  --notarize                Run notarization and stapling
  --skip-notarize           Skip notarization (default)
  --xcodegen                Run xcodegen generate before build
  --clean                   Remove previous dist and derived data
  -h, --help                Show help

Environment alternatives:
  SIGN_IDENTITY, TEAM_ID, NOTARY_PROFILE, SKIP_NOTARIZE, RUN_XCODEGEN

Examples:
  $(basename "$0") --identity "Developer ID Application: Your Name (TEAMID)" --notarize --notary-profile AC_PROFILE
  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" $(basename "$0")
EOF
}

CLEAN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity)
      SIGN_IDENTITY="$2"; shift 2 ;;
    --team-id)
      TEAM_ID="$2"; shift 2 ;;
    --notary-profile)
      NOTARY_PROFILE="$2"; shift 2 ;;
    --notarize)
      SKIP_NOTARIZE=0; shift ;;
    --skip-notarize)
      SKIP_NOTARIZE=1; shift ;;
    --xcodegen)
      RUN_XCODEGEN=1; shift ;;
    --clean)
      CLEAN=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2 ;;
  esac
done

if [[ ! -f "$PROJECT_FILE/project.pbxproj" ]]; then
  echo "Xcode project not found: $PROJECT_FILE" >&2
  exit 1
fi

if [[ "$RUN_XCODEGEN" == "1" ]]; then
  echo "[1/8] Running xcodegen generate"
  xcodegen generate
fi

if [[ "$CLEAN" == "1" ]]; then
  echo "[1/8] Cleaning previous outputs"
  rm -rf "$DERIVED_DATA_PATH" "$DIST_DIR"
fi

mkdir -p "$DIST_DIR"

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1)"
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "No Developer ID Application identity found." >&2
  echo "Pass --identity or install Developer ID certificate in Keychain." >&2
  exit 1
fi

echo "Using signing identity: $SIGN_IDENTITY"

BUILD_ARGS=(
  -project "$PROJECT_FILE"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA_PATH"
  clean build
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
)

if [[ -n "$TEAM_ID" ]]; then
  BUILD_ARGS+=(DEVELOPMENT_TEAM="$TEAM_ID")
fi

echo "[2/8] Building Release app (without Xcode signing; will sign in packaging step)"
xcodebuild "${BUILD_ARGS[@]}" >/tmp/voiceinput_release_build.log

BUILT_APP="$(find "$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION" -maxdepth 1 -name "${APP_NAME}.app" -print -quit)"
if [[ -z "$BUILT_APP" ]]; then
  echo "Built app not found in derived data." >&2
  exit 1
fi

echo "[3/8] Preparing dist app bundle"
rm -rf "$APP_OUT_PATH"
cp -R "$BUILT_APP" "$APP_OUT_PATH"

echo "[4/8] Signing app with Developer ID"
codesign --force --deep --timestamp --options runtime --sign "$SIGN_IDENTITY" "$APP_OUT_PATH"

echo "[5/8] Verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP_OUT_PATH"
spctl -a -t exec -vv "$APP_OUT_PATH" || true

echo "[6/8] Creating DMG"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_OUT_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH" >/tmp/voiceinput_dmg.log

echo "[7/8] Signing DMG"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"

if [[ "$SKIP_NOTARIZE" == "0" ]]; then
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "--notarize requires --notary-profile <profile> (or NOTARY_PROFILE env)." >&2
    exit 1
  fi
  echo "[8/8] Notarizing DMG"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_OUT_PATH"
  xcrun stapler staple "$DMG_PATH"
else
  echo "[8/8] Skipping notarization (use --notarize --notary-profile <profile> to enable)"
fi

echo

echo "Done. Outputs:"
echo "  App: $APP_OUT_PATH"
echo "  DMG: $DMG_PATH"
