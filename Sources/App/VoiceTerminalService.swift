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
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleDebugVoiceAgentDemo(_:)),
            name: Notification.Name("com.voiceinput.debug.voiceAgentDemo"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

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
        terminalPanel.onContinue = { [weak self] in
            self?.handleHotkeyPressed()
        }
    }

    @objc
    private func handleDebugVoiceAgentDemo(_ notification: Notification) {
        let transcript = (notification.userInfo?["transcript"] as? String) ?? "帮我打开 Safari"
        let intentText = (notification.userInfo?["intent"] as? String) ?? "准备打开：Safari"
        let resultText = (notification.userInfo?["result"] as? String) ?? "已打开 Safari"

        RuntimeDiagnosticsStore.record("voice-agent", "Received debug state demo request")
        VoiceAgentSessionStore.shared.beginSession(status: "准备启动语音 Agent")
        terminalPanel.setState(.listening)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            VoiceAgentSessionStore.shared.setStage(.listening, text: "请开始说话")
            VoiceAgentSessionStore.shared.updateLiveText(transcript)
            self.terminalPanel.updateListeningText(transcript)
            RuntimeDiagnosticsStore.record("voice-agent", "Debug demo listening transcript=\(transcript.prefix(60))")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            VoiceAgentSessionStore.shared.setStage(.recognizing, text: "正在理解你的意图")
            VoiceAgentSessionStore.shared.updateIntentText(intentText)
            self.terminalPanel.setState(.recognizing(transcript))
            RuntimeDiagnosticsStore.record("voice-agent", "Debug demo recognizing intent=\(intentText)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            let demoIntent = RecognizedIntent(
                type: .openApp,
                title: "Safari",
                detail: "Safari",
                confidence: 1.0,
                displaySummary: intentText
            )
            VoiceAgentSessionStore.shared.setStage(.executing, text: "正在打开应用")
            self.terminalPanel.setState(.executing(demoIntent))
            RuntimeDiagnosticsStore.record("voice-agent", "Debug demo executing")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            VoiceAgentSessionStore.shared.setStage(.result, text: resultText)
            VoiceAgentSessionStore.shared.updateResultText(resultText)
            self.terminalPanel.setState(.success(resultText))
            RuntimeDiagnosticsStore.record("voice-agent", "Debug demo finished result=\(resultText)")
        }
    }

    func handleHotkeyPressed() {
        guard !AppHotkeyVoiceService.shared.isMode1Active else { return }
        guard !isActive else { return }

        pendingStopAfterActivation = false
        suppressErrors = false
        isActive = true
        currentText = ""
        VoiceAgentSessionStore.shared.beginSession(status: "准备启动语音 Agent")

        terminalPanel.setState(.listening)

        Task { @MainActor in
            let granted = await ensurePermissions()
            RuntimeDiagnosticsStore.record("voice-agent", "Permissions granted=\(granted)")
            guard granted else {
                isActive = false
                VoiceAgentSessionStore.shared.setStage(.error, text: "权限未就绪")
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
            isActive = false
            terminalPanel.setState(.error("未捕捉到麦克风输入，请检查麦克风权限、输入设备和环境噪声后重试。"))
            VoiceAgentSessionStore.shared.setStage(.error, text: "未捕捉到麦克风输入")
            RuntimeDiagnosticsStore.record("voice-agent", "No microphone input captured, aborting")
            return
        }

        RuntimeDiagnosticsStore.record("voice-agent", "Captured transcript length=\(capturedText.count)")
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
            VoiceAgentSessionStore.shared.setStage(.error, text: "未授权语音识别")
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
                VoiceAgentSessionStore.shared.setStage(.error, text: "语音识别权限被拒绝")
                openPrivacySettings(anchor: "Privacy_SpeechRecognition")
                return false
            }
        }

        // Microphone
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .denied || micStatus == .restricted {
            terminalPanel.setState(.error("未授权麦克风。请在 系统设置 > 隐私与安全性 > 麦克风 中允许 VoiceInput。"))
            VoiceAgentSessionStore.shared.setStage(.error, text: "未授权麦克风")
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
                VoiceAgentSessionStore.shared.setStage(.error, text: "麦克风权限被拒绝")
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
                VoiceAgentSessionStore.shared.setStage(.error, text: "未授权辅助功能")
                openPrivacySettings(anchor: "Privacy_Accessibility")
                return false
            }
        }

        // LLM API key check
        let apiKey = SharedSettings.defaults.string(forKey: SharedSettings.Keys.llmAPIKey) ?? ""
        if apiKey.count < 10 {
            terminalPanel.setState(.error("语音终端需要 LLM 功能。请先在设置中配置 API Key（≥10字符）。"))
            VoiceAgentSessionStore.shared.setStage(.error, text: "未配置 API Key")
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
            RuntimeDiagnosticsStore.record("voice-agent", "Speech engine started")
            VoiceAgentSessionStore.shared.setStage(.listening, text: "请开始说话")
            VoiceAgentSessionStore.shared.updateLiveText("")
            VoiceAgentSessionStore.shared.updateIntentText("")
            VoiceAgentSessionStore.shared.updateResultText("")
            if pendingStopAfterActivation {
                pendingStopAfterActivation = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.handleHotkeyReleased()
                }
            }
        } catch {
            terminalPanel.setState(.error("录音启动失败: \(error.localizedDescription)"))
            isActive = false
            VoiceAgentSessionStore.shared.setStage(.error, text: "录音启动失败")
            RuntimeDiagnosticsStore.record("voice-agent", "Speech engine start failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Intent processing

    private func processIntent(_ text: String) {
        terminalPanel.setState(.recognizing(text))
        VoiceAgentSessionStore.shared.setStage(.recognizing, text: "正在理解你的意图")
        VoiceAgentSessionStore.shared.updateLiveText(text)
        RuntimeDiagnosticsStore.record("voice-agent", "Recognizing intent")

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
                    RuntimeDiagnosticsStore.record("voice-agent", "Intent unrecognized")
                    terminalPanel.showFallbackSelect(text: text)
                    VoiceAgentSessionStore.shared.setStage(.confirming, text: "未识别命令")
                    VoiceAgentSessionStore.shared.updateIntentText("我没听懂你要做什么，请选择最接近的操作类型。")
                } else {
                    RuntimeDiagnosticsStore.record("voice-agent", "Intent recognized type=\(intent.type.rawValue) risk=\(String(describing: intent.type.riskLevel))")
                    switch intent.type.riskLevel {
                    case .safe:
                        self.terminalPanel.setState(.autoExecuting(intent))
                        VoiceAgentSessionStore.shared.setStage(.previewing, text: "准备执行")
                        VoiceAgentSessionStore.shared.updateIntentText(self.previewText(for: intent))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                            guard let self else { return }
                            if case .autoExecuting = self.terminalPanel.currentState {
                                self.executeCommand(intent)
                            }
                        }

                    case .low:
                        self.terminalPanel.setState(.autoExecuting(intent))
                        VoiceAgentSessionStore.shared.setStage(.previewing, text: "即将执行")
                        VoiceAgentSessionStore.shared.updateIntentText(self.previewText(for: intent))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                            guard let self else { return }
                            if case .autoExecuting = self.terminalPanel.currentState {
                                self.executeCommand(intent)
                            }
                        }

                    case .medium:
                        self.terminalPanel.setState(.confirming(intent))
                        VoiceAgentSessionStore.shared.setStage(.confirming, text: "等待确认")
                        VoiceAgentSessionStore.shared.updateIntentText(self.previewText(for: intent))
                        self.startVoiceConfirmation(for: intent)

                    case .dangerous:
                        self.terminalPanel.setState(.confirming(intent))
                        VoiceAgentSessionStore.shared.setStage(.confirming, text: "等待确认")
                        VoiceAgentSessionStore.shared.updateIntentText(self.previewText(for: intent))
                        // No voice confirmation — button only for dangerous commands
                    }
                }
            }
        }
    }

    private func executeCommand(_ intent: RecognizedIntent) {
        terminalPanel.setState(.executing(intent))
        VoiceAgentSessionStore.shared.setStage(.executing, text: executingText(for: intent))
        VoiceAgentSessionStore.shared.updateIntentText(previewText(for: intent))
        RuntimeDiagnosticsStore.record("voice-agent", "Executing intent type=\(intent.type.rawValue) title=\(intent.title)")

        Task {
            let response = await commandRouter.execute(intent: intent)

            await MainActor.run {
                if response.success {
                    RuntimeDiagnosticsStore.record("voice-agent", "Execution succeeded title=\(response.title)")
                    if !response.body.isEmpty {
                        terminalPanel.setState(.richContent(response))
                        VoiceAgentSessionStore.shared.setStage(.result, text: response.title)
                        VoiceAgentSessionStore.shared.updateResultText(response.body)
                    } else {
                        terminalPanel.setState(.success(response.title))
                        VoiceAgentSessionStore.shared.setStage(.result, text: response.title)
                        VoiceAgentSessionStore.shared.updateResultText(response.title)
                    }
                } else {
                    RuntimeDiagnosticsStore.record("voice-agent", "Execution failed title=\(response.title)")
                    terminalPanel.setState(.error(response.title))
                    VoiceAgentSessionStore.shared.setStage(.error, text: response.title)
                    VoiceAgentSessionStore.shared.updateResultText(response.title)
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
            VoiceAgentSessionStore.shared.setStage(.confirming, text: trimmed.isEmpty ? "请说“确认”或“取消”" : trimmed)
            VoiceAgentSessionStore.shared.updateIntentText(previewText(for: intent))
            VoiceAgentSessionStore.shared.updateLiveText(trimmed)
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
        VoiceAgentSessionStore.shared.reset()
        RuntimeDiagnosticsStore.record("voice-agent", "Session reset")
    }

    func toggleFromUI() {
        if isActive {
            handleHotkeyReleased()
        } else {
            handleHotkeyPressed()
        }
    }

    private func previewText(for intent: RecognizedIntent) -> String {
        switch intent.type {
        case .addCalendar:
            return "准备添加日历：\(intent.title)"
        case .createNote:
            return "准备创建笔记：\(intent.title)"
        case .openApp:
            return "准备打开：\(intent.title)"
        case .runCommand:
            return "准备执行命令：\(intent.title)"
        case .systemControl:
            return "准备执行：\(intent.title)"
        case .webSearch:
            return "准备搜索：\(intent.title)"
        case .weather:
            return "准备查询天气：\(intent.title)"
        case .queryContact:
            return "准备查询联系人：\(intent.title)"
        case .addReminder:
            return "准备添加提醒：\(intent.title)"
        case .unrecognized:
            return intent.displaySummary
        }
    }

    private func executingText(for intent: RecognizedIntent) -> String {
        switch intent.type {
        case .addCalendar:
            return "正在添加日历"
        case .createNote:
            return "正在创建笔记"
        case .openApp:
            return "正在打开应用"
        case .runCommand:
            return "正在执行命令"
        case .systemControl:
            return "正在执行系统操作"
        case .webSearch:
            return "正在搜索"
        case .weather:
            return "正在查询天气"
        case .queryContact:
            return "正在查询联系人"
        case .addReminder:
            return "正在添加提醒"
        case .unrecognized:
            return "正在处理"
        }
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
                VoiceAgentSessionStore.shared.updateLiveText(result.text)
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
                VoiceAgentSessionStore.shared.updateLiveText(text)
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
            VoiceAgentSessionStore.shared.setStage(.error, text: "识别失败")
            VoiceAgentSessionStore.shared.updateResultText(error.localizedDescription)
            RuntimeDiagnosticsStore.record("voice-agent", "Recognition failed: \(error.localizedDescription)")
        }
    }
}
