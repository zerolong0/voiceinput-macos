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

    // Voice confirmation
    private var confirmationEngine: WhisperEngine?
    private var confirmationIntent: RecognizedIntent?
    private var confirmationTimer: Timer?
    private var isInVoiceConfirmation = false

    private let confirmKeywords = ["确认", "好的", "执行", "是", "是的", "可以", "对"]
    private let cancelKeywords = ["取消", "不要", "算了", "不", "不是", "停"]

    private override init() {
        super.init()
        whisperEngine.delegate = self
        try? whisperEngine.loadModel(from: "")

        terminalPanel.onConfirm = { [weak self] intent in
            self?.stopVoiceConfirmation()
            self?.executeCommand(intent)
        }
        terminalPanel.onCancel = { [weak self] in
            self?.stopVoiceConfirmation()
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

        let detector = SceneDetector.shared
        let context = IntentContext(
            appName: detector.getCurrentAppName(),
            bundleID: detector.getCurrentBundleId(),
            windowTitle: detector.getCurrentWindowTitle(),
            scene: detector.detectCurrentScene()
        )

        Task {
            let intent = await intentRecognizer.recognize(text: text, context: context)

            await MainActor.run {
                if intent.type == .unrecognized {
                    terminalPanel.showFallbackSelect(text: text)
                } else {
                    switch intent.type.riskLevel {
                    case .safe:
                        self.executeCommand(intent)

                    case .low:
                        self.terminalPanel.setState(.autoExecuting(intent))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            guard let self else { return }
                            if case .autoExecuting = self.terminalPanel.currentState {
                                self.executeCommand(intent)
                            }
                        }

                    case .medium:
                        self.terminalPanel.setState(.confirming(intent))
                        self.startVoiceConfirmation(for: intent)

                    case .dangerous:
                        self.terminalPanel.setState(.confirming(intent))
                        // No voice confirmation — button only for dangerous commands
                    }
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

    // MARK: - Voice confirmation

    private func startVoiceConfirmation(for intent: RecognizedIntent) {
        confirmationIntent = intent
        isInVoiceConfirmation = true

        let engine = WhisperEngine()
        engine.delegate = self
        try? engine.loadModel(from: "")
        confirmationEngine = engine
        try? engine.start()

        confirmationTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            self?.stopVoiceConfirmation()
        }
    }

    private func handleConfirmationPartialResult(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let intent = confirmationIntent {
            terminalPanel.setState(.voiceConfirming(intent, trimmed))
        }

        let lower = trimmed.lowercased()
        if confirmKeywords.contains(where: { lower.contains($0) }) {
            stopVoiceConfirmation()
            if let intent = confirmationIntent {
                executeCommand(intent)
            }
        } else if cancelKeywords.contains(where: { lower.contains($0) }) {
            stopVoiceConfirmation()
            reset()
        }
    }

    private func stopVoiceConfirmation() {
        confirmationTimer?.invalidate()
        confirmationTimer = nil
        confirmationEngine?.stop()
        confirmationEngine = nil
        isInVoiceConfirmation = false
        confirmationIntent = nil
    }

    private func reset() {
        suppressErrors = true
        stopVoiceConfirmation()
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
            guard let self else { return }
            if engine === self.confirmationEngine {
                self.handleConfirmationPartialResult(result.text)
            } else if self.isActive, !self.isStoppingRecording {
                self.currentText = result.text
            }
        }
    }

    func whisperEngine(_ engine: WhisperEngine, didUpdatePartialResult text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if engine === self.confirmationEngine {
                self.handleConfirmationPartialResult(text)
            } else if self.isActive, !self.isStoppingRecording {
                self.currentText = text
                if case .listening = self.terminalPanel.currentState {
                    self.terminalPanel.updateListeningText(text)
                }
            }
        }
    }

    func whisperEngine(_ engine: WhisperEngine, didFailWithError error: WhisperError) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if engine === self.confirmationEngine {
                // Confirmation engine failed — just stop voice confirmation, keep button mode
                self.stopVoiceConfirmation()
                return
            }
            // Suppress errors from intentional stop (async callback from recognitionTask.cancel)
            guard self.isActive, !self.isStoppingRecording, !self.suppressErrors else { return }
            self.terminalPanel.setState(.error("识别失败: \(error.localizedDescription)"))
            self.isActive = false
        }
    }
}
