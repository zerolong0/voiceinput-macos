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

reset_onboarding_state() {
  # Main app onboarding completion flag
  defaults delete com.voiceinput.macos hasCompletedOnboarding 2>/dev/null || true
  # Safety net: if older builds used global domain
  defaults delete NSGlobalDomain hasCompletedOnboarding 2>/dev/null || true
}

reset_all_local_state() {
  echo "Resetting all local app state (onboarding + shared settings + history)..."
  defaults delete com.voiceinput.macos 2>/dev/null || true
  defaults delete com.voiceinput.shared 2>/dev/null || true
  # Backward compatibility: remove any prefixed plist variants if they exist.
  defaults delete com.voiceinput.macos.debug 2>/dev/null || true
  defaults delete com.voiceinput.shared.debug 2>/dev/null || true
  rm -rf "$HOME/Library/Saved Application State/com.voiceinput.macos.savedState" 2>/dev/null || true
  rm -rf "$HOME/Library/Preferences/com.voiceinput.macos.plist" 2>/dev/null || true
  rm -rf "$HOME/Library/Preferences/com.voiceinput.shared.plist" 2>/dev/null || true
  reset_onboarding_state
}

cleanup_running_voiceinput_instances() {
  osascript -e 'tell application "VoiceInput" to quit' 2>/dev/null || true
  killall VoiceInput 2>/dev/null || true
  pkill -f '/Applications/VoiceInput.app/Contents/MacOS/VoiceInput' 2>/dev/null || true
  pkill -f '/Library/Developer/Xcode/DerivedData/.*/VoiceInput.app/Contents/MacOS/VoiceInput' 2>/dev/null || true
  pkill -f '/Users/.*/Library/Developer/Xcode/DerivedData/.*/VoiceInput.app/Contents/MacOS/VoiceInput' 2>/dev/null || true
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

if [[ "${PRESERVE_CONFIG:-0}" != "1" ]]; then
  reset_all_local_state
else
  echo "PRESERVE_CONFIG=1 detected, skipping local state reset."
fi

cleanup_running_voiceinput_instances
open /Applications/VoiceInput.app

echo "Installed and launched: /Applications/VoiceInput.app"
