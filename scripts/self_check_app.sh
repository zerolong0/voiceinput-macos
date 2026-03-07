#!/bin/zsh
set -euo pipefail

APP_BUNDLE_ID="com.voiceinput.macos"
SUITE_NAME="com.voiceinput.shared"
DIAG_KEY="runtimeDiagnostics.events"
VOICE_INPUT_TEXT="【Codex自测】自动输入成功"
PROJECT_ROOT="/Users/zerolong/Documents/AICODE/best/InputLess/voiceinput-macos"

clear_diagnostics() {
  defaults write "${SUITE_NAME}" "${DIAG_KEY}" -array
}

post_notification() {
  local name="$1"
  local payload="$2"
  swift - "$name" "$payload" <<'SWIFT'
import Foundation

let name = CommandLine.arguments[1]
let payload = CommandLine.arguments[2]
let parts = payload.split(separator: "\u{1f}", omittingEmptySubsequences: false)
var userInfo: [String: String] = [:]

for part in parts {
    let pieces = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
    guard pieces.count == 2 else { continue }
    userInfo[String(pieces[0])] = String(pieces[1])
}

DistributedNotificationCenter.default().postNotificationName(
    Notification.Name(name),
    object: nil,
    userInfo: userInfo,
    deliverImmediately: true
)
SWIFT
}

read_diagnostics() {
  defaults read "${SUITE_NAME}" "${DIAG_KEY}" 2>/dev/null || echo "()"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    echo "SELF-CHECK FAILED: ${message}" >&2
    exit 1
  fi
}

app_window_title() {
  osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
    if not (exists process "VoiceInput") then return ""
    tell process "VoiceInput"
        if (count of windows) is 0 then return ""
        try
            return value of attribute "AXTitle" of window 1
        on error
            return ""
        end try
    end tell
end tell
APPLESCRIPT
}

wait_for_window_title() {
  local expected="$1"
  local retries=30
  local title=""
  while (( retries > 0 )); do
    title="$(app_window_title)"
    if [[ "${title}" == "${expected}" ]]; then
      echo "${title}"
      return 0
    fi
    sleep 0.2
    ((retries--))
  done
  echo "${title}"
  return 1
}

run_onboarding_check() {
  echo "== Onboarding Self Check =="

  osascript -e 'tell application "VoiceInput" to quit' 2>/dev/null || true
  pkill -x VoiceInput 2>/dev/null || true
  sleep 0.8

  defaults delete com.voiceinput.macos hasCompletedOnboarding 2>/dev/null || true
  defaults delete NSGlobalDomain hasCompletedOnboarding 2>/dev/null || true
  defaults delete "${SUITE_NAME}" hotkeyModifiers 2>/dev/null || true
  defaults delete "${SUITE_NAME}" hotkeyKeyCode 2>/dev/null || true
  defaults delete "${SUITE_NAME}" llmModel 2>/dev/null || true
  defaults delete "${SUITE_NAME}" agentModel 2>/dev/null || true
  defaults delete "${SUITE_NAME}" voiceInputModel 2>/dev/null || true
  killall cfprefsd 2>/dev/null || true

  open -b "${APP_BUNDLE_ID}"

  local onboarding_title
  onboarding_title="$(wait_for_window_title "欢迎使用 VoiceInput")" || {
    echo "SELF-CHECK FAILED: onboarding window not shown, got title: ${onboarding_title}" >&2
    exit 1
  }
  echo "Onboarding window title: ${onboarding_title}"

  local step_count
  step_count="$(sed -n '/private enum OnboardingStep/,/var title/p' "${PROJECT_ROOT}/Sources/App/OnboardingView.swift" | rg -n 'case ' | wc -l | tr -d ' ')"
  [[ "${step_count}" == "5" ]] || {
    echo "SELF-CHECK FAILED: expected 5 onboarding steps, got ${step_count}" >&2
    exit 1
  }
  echo "Onboarding step count: ${step_count}"

  local hk_mod hk_code hk_status m_llm m_agent m_voice
  hk_mod="$(defaults read "${SUITE_NAME}" hotkeyModifiers 2>/dev/null || echo "")"
  hk_code="$(defaults read "${SUITE_NAME}" hotkeyKeyCode 2>/dev/null || echo "")"
  hk_status="$(defaults read "${SUITE_NAME}" hotkeyRuntimeStatus 2>/dev/null || echo "")"
  m_llm="$(defaults read "${SUITE_NAME}" llmModel 2>/dev/null || echo "")"
  m_agent="$(defaults read "${SUITE_NAME}" agentModel 2>/dev/null || echo "")"
  m_voice="$(defaults read "${SUITE_NAME}" voiceInputModel 2>/dev/null || echo "")"

  [[ "${hk_mod}" == "8388608" || "${hk_mod}" == "131072" ]] || {
    echo "SELF-CHECK FAILED: onboarding default hotkey modifier should be Fn-like flag (8388608/131072), got ${hk_mod}" >&2
    exit 1
  }
  [[ "${hk_code}" == "63" ]] || {
    echo "SELF-CHECK FAILED: onboarding default hotkey keyCode should be 63(Fn), got ${hk_code}" >&2
    exit 1
  }
  [[ "${hk_status}" == *"Fn"* ]] || {
    echo "SELF-CHECK FAILED: onboarding hotkey runtime status should contain Fn, got ${hk_status}" >&2
    exit 1
  }
  [[ "${m_llm}" == "gemini-2.5-flash-lite" ]] || {
    echo "SELF-CHECK FAILED: llmModel default mismatch: ${m_llm}" >&2
    exit 1
  }
  [[ "${m_agent}" == "gemini-2.5-flash-lite" ]] || {
    echo "SELF-CHECK FAILED: agentModel default mismatch: ${m_agent}" >&2
    exit 1
  }
  [[ "${m_voice}" == "gemini-2.5-flash-lite" ]] || {
    echo "SELF-CHECK FAILED: voiceInputModel default mismatch: ${m_voice}" >&2
    exit 1
  }

  echo "Onboarding defaults: hotkey=Fn(63), models=gemini-2.5-flash-lite"
}

run_voice_input_check() {
  echo "== Voice Input Self Check =="
  clear_diagnostics

  open -a TextEdit
  sleep 1
  osascript <<'APPLESCRIPT'
tell application "TextEdit"
    activate
    if not (exists document 1) then make new document
    set text of front document to ""
end tell
APPLESCRIPT

  /opt/homebrew/bin/cliclick c:500,250
  sleep 0.3

  post_notification "com.voiceinput.debug.injectText" "text=${VOICE_INPUT_TEXT}"
  sleep 1.2

  osascript -e 'tell application "TextEdit" to activate' \
            -e 'delay 0.3' \
            -e 'tell application "System Events" to keystroke "a" using command down' \
            -e 'tell application "System Events" to keystroke "c" using command down'
  sleep 0.3

  local pasted
  pasted="$(pbpaste)"
  echo "TextEdit content: ${pasted}"
  [[ "${pasted}" == "${VOICE_INPUT_TEXT}" ]] || {
    echo "SELF-CHECK FAILED: voice input text was not inserted into TextEdit" >&2
    read_diagnostics >&2
    exit 1
  }

  local diagnostics
  diagnostics="$(read_diagnostics)"
  echo "${diagnostics}"
  assert_contains "${diagnostics}" "Inserted into focused target successfully" "voice input did not report successful insertion"
}

run_voice_agent_check() {
  echo "== Voice Agent Self Check =="
  clear_diagnostics

  open -b "${APP_BUNDLE_ID}"
  sleep 1

  post_notification "com.voiceinput.debug.voiceAgentDemo" $'transcript=帮我打开 Safari\x1fintent=准备打开：Safari\x1fresult=已打开 Safari'
  sleep 1.6

  local diagnostics
  diagnostics="$(read_diagnostics)"
  echo "${diagnostics}"
  assert_contains "${diagnostics}" "Received debug state demo request" "voice agent demo did not start"
  assert_contains "${diagnostics}" "Debug demo listening transcript" "voice agent listening state missing"
  assert_contains "${diagnostics}" "Debug demo recognizing intent" "voice agent recognizing state missing"
  assert_contains "${diagnostics}" "Debug demo executing" "voice agent executing state missing"
  assert_contains "${diagnostics}" "Debug demo finished result" "voice agent result state missing"
}

run_onboarding_check
run_voice_input_check
run_voice_agent_check

echo "SELF-CHECK PASSED"
