import Cocoa
import AVFoundation
import Speech
import ApplicationServices

final class VoiceTerminalService: NSObject {
    static let shared = VoiceTerminalService()

    private let whisperEngine = WhisperEngine()
    private let intentRecognizer = IntentRecognizer()
    private let terminalPanel = TerminalPanel()
    private let commandRouter = CommandRouter()

    private var isActive = false
    private var currentText = ""
    private var isStoppingRecording = false
    private var pendingStopAfterActivation = false
    /// Stays true from stop() until we finish processing, to suppress async errors
    private var suppressErrors = false

    private override init() {
        super.init()
        whisperEngine.delegate = self
        try? whisperEngine.loadModel(from: "")

        terminalPanel.onConfirm = { [weak self] intent in
            self?.executeCommand(intent)
        }
        terminalPanel.onCancel = { [weak self] in
            self?.reset()
        }
        terminalPanel.onFallbackSelect = { [weak self] type, text in
            let intent = RecognizedIntent(
                type: type,
                title: text,
                detail: text,
                confidence: 1.0,
                displaySummary: text
            )
            self?.executeCommand(intent)
        }
    }

    func handleHotkeyPressed() {
        guard !AppHotkeyVoiceService.shared.isMode1Active else { return }
        guard !isActive else { return }

        pendingStopAfterActivation = false
        suppressErrors = false
        isActive = true
        currentText = ""

        terminalPanel.setState(.listening)

        Task { @MainActor in
            let granted = await ensurePermissions()
            guard granted else {
                isActive = false
                return
            }
            startRecording()
        }
    }

    func handleHotkeyReleased() {
        guard isActive else { return }

        // Suppress async errors from recognition task cancellation
        suppressErrors = true
        isStoppingRecording = true
        whisperEngine.stop()
        isStoppingRecording = false

        let capturedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        currentText = ""

        guard !capturedText.isEmpty else {
            terminalPanel.hide()
            isActive = false
            return
        }

        processIntent(capturedText)
    }

    var isMode2Active: Bool { isActive }

    // MARK: - Permission check

    @MainActor
    private func ensurePermissions() async -> Bool {
        // Speech Recognition
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        if speechStatus == .denied || speechStatus == .restricted {
            terminalPanel.setState(.error("未授权语音识别。请在 系统设置 > 隐私与安全性 > 语音识别 中允许 VoiceInput。"))
            openPrivacySettings(anchor: "Privacy_SpeechRecognition")
            return false
        }
        if speechStatus == .notDetermined {
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { result in
                    continuation.resume(returning: result == .authorized)
                }
            }
            if !granted {
                terminalPanel.setState(.error("语音识别权限被拒绝。请在系统设置中授权后重试。"))
                openPrivacySettings(anchor: "Privacy_SpeechRecognition")
                return false
            }
        }

        // Microphone
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .denied || micStatus == .restricted {
            terminalPanel.setState(.error("未授权麦克风。请在 系统设置 > 隐私与安全性 > 麦克风 中允许 VoiceInput。"))
            openPrivacySettings(anchor: "Privacy_Microphone")
            return false
        }
        if micStatus == .notDetermined {
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { result in
                    continuation.resume(returning: result)
                }
            }
            if !granted {
                terminalPanel.setState(.error("麦克风权限被拒绝。请在系统设置中授权后重试。"))
                openPrivacySettings(anchor: "Privacy_Microphone")
                return false
            }
        }

        // Accessibility (needed for hotkey handling)
        if !AccessibilityTrust.isTrusted(prompt: false) {
            // Stale TCC entry from previous build? Reset and re-prompt.
            if !AccessibilityTrust.resetAndReauthorize() {
                // Wait for user to toggle the switch in System Settings.
                for _ in 0..<10 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if AccessibilityTrust.isTrusted(prompt: false) { break }
                }
            }
            if !AccessibilityTrust.isTrusted(prompt: false) {
                terminalPanel.setState(.error("未授权辅助功能。请在 系统设置 > 隐私与安全性 > 辅助功能 中先移除 VoiceInput，再重新添加。"))
                openPrivacySettings(anchor: "Privacy_Accessibility")
                return false
            }
        }

        // LLM API key check
        let apiKey = SharedSettings.defaults.string(forKey: SharedSettings.Keys.llmAPIKey) ?? ""
        if apiKey.count < 10 {
            terminalPanel.setState(.error("语音终端需要 LLM 功能。请先在设置中配置 API Key（≥10字符）。"))
            return false
        }

        return true
    }

    private func openPrivacySettings(anchor: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Recording

    private func startRecording() {
        let shouldMute = SharedSettings.defaults.object(forKey: SharedSettings.Keys.muteExternalAudioDuringInput) as? Bool ?? true
        if shouldMute {
            pauseExternalAudioBestEffort()
        }
        do {
            try whisperEngine.start()
            if pendingStopAfterActivation {
                pendingStopAfterActivation = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.handleHotkeyReleased()
                }
            }
        } catch {
            terminalPanel.setState(.error("录音启动失败: \(error.localizedDescription)"))
            isActive = false
        }
    }

    // MARK: - Intent processing

    private func processIntent(_ text: String) {
        terminalPanel.setState(.recognizing(text))

        Task {
            let intent = await intentRecognizer.recognize(text: text)

            await MainActor.run {
                if intent.type == .unrecognized {
                    terminalPanel.showFallbackSelect(text: text)
                } else {
                    terminalPanel.setState(.confirming(intent))
                }
            }
        }
    }

    private func executeCommand(_ intent: RecognizedIntent) {
        terminalPanel.setState(.executing(intent))

        Task {
            let result = await commandRouter.execute(intent)

            await MainActor.run {
                if result.success {
                    terminalPanel.setState(.success(result.message))
                } else {
                    terminalPanel.setState(.error(result.message))
                }
                isActive = false
            }
        }
    }

    private func reset() {
        suppressErrors = true
        whisperEngine.stop()
        terminalPanel.hide()
        isActive = false
        currentText = ""
        pendingStopAfterActivation = false
    }

    // MARK: - External audio mute

    private func pauseExternalAudioBestEffort() {
        let players: [(bundleID: String, pauseScript: String)] = [
            ("com.apple.Music", "tell application id \"com.apple.Music\" to pause"),
            ("com.spotify.client", "tell application id \"com.spotify.client\" to pause")
        ]

        for player in players {
            if NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty {
                continue
            }
            if let appleScript = NSAppleScript(source: player.pauseScript) {
                var error: NSDictionary?
                _ = appleScript.executeAndReturnError(&error)
            }
        }
    }

}

extension VoiceTerminalService: WhisperEngineDelegate {
    func whisperEngine(_ engine: WhisperEngine, didTranscribe result: TranscriptionResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActive, !self.isStoppingRecording else { return }
            self.currentText = result.text
        }
    }

    func whisperEngine(_ engine: WhisperEngine, didUpdatePartialResult text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActive, !self.isStoppingRecording else { return }
            self.currentText = text
        }
    }

    func whisperEngine(_ engine: WhisperEngine, didFailWithError error: WhisperError) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Suppress errors from intentional stop (async callback from recognitionTask.cancel)
            guard self.isActive, !self.isStoppingRecording, !self.suppressErrors else { return }
            self.terminalPanel.setState(.error("识别失败: \(error.localizedDescription)"))
            self.isActive = false
        }
    }
}
