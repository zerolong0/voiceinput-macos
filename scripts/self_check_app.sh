#!/bin/zsh
set -euo pipefail

APP_BUNDLE_ID="com.voiceinput.macos"
SUITE_NAME="com.voiceinput.shared"
DIAG_KEY="runtimeDiagnostics.events"
VOICE_INPUT_TEXT="【Codex自测】自动输入成功"

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

run_voice_input_check
run_voice_agent_check

echo "SELF-CHECK PASSED"
