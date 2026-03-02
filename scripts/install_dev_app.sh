#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

DEFAULT_SIGN_IDENTITY="3A2488F793855B22EE97272D98AB8CF83CA9F02B"

reset_tcc_for_bundle() {
  local bid="$1"
  tccutil reset All "$bid" || true
  tccutil reset Accessibility "$bid" || true
  tccutil reset Microphone "$bid" || true
  tccutil reset SpeechRecognition "$bid" || true
  tccutil reset ListenEvent "$bid" || true
  tccutil reset PostEvent "$bid" || true
  tccutil reset AppleEvents "$bid" || true
}

xcodegen generate >/dev/null
xcodebuild -project VoiceInput.xcodeproj -scheme VoiceInput -configuration Debug build >/dev/null

APP_PATH=$(ls -td "$HOME"/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug/VoiceInput.app 2>/dev/null | head -n 1)
if [[ -z "${APP_PATH:-}" ]]; then
  echo "VoiceInput.app not found in DerivedData"
  exit 2
fi

echo "Installing to /Applications/VoiceInput.app"
if rm -rf /Applications/VoiceInput.app 2>/dev/null && cp -R "$APP_PATH" /Applications/VoiceInput.app 2>/dev/null; then
  :
else
  echo "Need admin permission to write /Applications, retrying with sudo..."
  sudo rm -rf /Applications/VoiceInput.app
  sudo cp -R "$APP_PATH" /Applications/VoiceInput.app
fi

# Re-sign app with a stable developer identity to avoid ad-hoc identity drift
# that can make Accessibility permission appear "granted but ineffective".
SIGN_IDENTITY="${SIGN_IDENTITY:-$DEFAULT_SIGN_IDENTITY}"
if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
  echo "Re-signing with stable identity: $SIGN_IDENTITY"
  codesign --force --deep --sign "$SIGN_IDENTITY" /Applications/VoiceInput.app
else
  echo "Stable signing identity not found, keep current signature: $SIGN_IDENTITY"
fi

codesign --verify --deep --strict /Applications/VoiceInput.app || true

if [[ "${RESET_TCC:-0}" == "1" ]]; then
  echo "Resetting TCC permissions to avoid stale authorization state..."
  reset_tcc_for_bundle "com.voiceinput.macos"
  reset_tcc_for_bundle "com.voiceinput.inputmethod"
  killall tccd 2>/dev/null || true
fi

killall VoiceInput 2>/dev/null || true
open /Applications/VoiceInput.app

echo "Installed and launched: /Applications/VoiceInput.app"
