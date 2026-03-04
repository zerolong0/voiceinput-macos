import Cocoa
import Carbon
import ApplicationServices
import AVFoundation
import Speech

private enum VoiceInputErrorKind {
    case permission
    case recognition
    case rewrite
    case injection
    case startup
}

final class AppHotkeyVoiceService: NSObject {
    private static weak var activeService: AppHotkeyVoiceService?
    static let shared = AppHotkeyVoiceService()

    private var hotkeyRef: EventHotKeyRef?
    private var terminalHotkeyRef: EventHotKeyRef?
    private var hotkeyHandlerInstalled = false
    private var keyConsumeTap: CFMachPort?
    private var keyConsumeTapSource: CFRunLoopSource?
    private var activeHotkeyModifiers: UInt32 = UInt32(OptionSetFlag.optionSpaceModifiers.rawValue)
    private var activeHotkeyKeyCode: UInt32 = UInt32(OptionSetFlag.spaceKeyCode.rawValue)
    private var isVoiceInputActive = false
    private var currentText = ""
    private var isStoppingRecording = false
    private var hotkeyPressBeganAt: TimeInterval = 0
    private var stopHandledOnPress = false
    private var pendingStopAfterActivation = false

    private let whisperEngine = WhisperEngine()
    private let textProcessor = TextProcessor()
    private let polishClient = PolishClient()
    private let statusPanel = InputStatusPanel()

    private struct PendingCopyContext {
        let originalText: String
        let processedText: String
        let finalText: String
        let style: String
    }

    private var pendingCopyContext: PendingCopyContext?
    private var holdToStopThreshold: TimeInterval {
        let value = SharedSettings.defaults.double(forKey: SharedSettings.Keys.hotkeyHoldToStopThreshold)
        return min(1.2, max(0.15, value > 0 ? value : 0.35))
    }

    private override init() {
        super.init()
        Self.activeService = self
        whisperEngine.delegate = self
        try? whisperEngine.loadModel(from: "")
        statusPanel.onCopyRequested = { [weak self] in
            self?.copyPendingTextToClipboard()
        }
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(reloadHotkeyConfiguration),
            name: Notification.Name(SharedNotifications.hotkeyChanged),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    deinit {
        whisperEngine.stop()
        unregisterGlobalHotkey()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func start() {
        setupGlobalHotkey()
    }

    func toggleFromUI() {
        if isVoiceInputActive {
            stopRecordingAndProcess()
        } else {
            statusPanel.showArming()
            RealtimeSessionStore.shared.setStage(.arming, text: "准备中")
            Task { @MainActor in
                let granted = await ensurePreflightPermissions()
                guard granted else { return }
                startRecording()
            }
        }
    }

    private func setupGlobalHotkey() {
        unregisterGlobalHotkey()

        if !hotkeyHandlerInstalled {
            installHotkeyHandler()
            hotkeyHandlerInstalled = true
        }

        let defaults = SharedSettings.defaults
        let hotkeyEnabled = defaults.object(forKey: SharedSettings.Keys.hotkeyEnabled) as? Bool ?? true
        guard hotkeyEnabled else {
            updateHotkeyRuntimeStatus("已关闭")
            return
        }

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x564F4943) // "VOIC"
        hotKeyID.id = 1

        var modifiers = defaults.object(forKey: SharedSettings.Keys.hotkeyModifiers) as? Int ?? OptionSetFlag.optionSpaceModifiers.rawValue
        var keyCode = defaults.object(forKey: SharedSettings.Keys.hotkeyKeyCode) as? Int ?? OptionSetFlag.spaceKeyCode.rawValue
        let validation = HotkeyConfig.validate(modifiers: modifiers, keyCode: keyCode)
        if !validation.isValid || (modifiers & cmdKey) != 0 {
            modifiers = OptionSetFlag.optionSpaceModifiers.rawValue
            keyCode = OptionSetFlag.spaceKeyCode.rawValue
            defaults.set(modifiers, forKey: SharedSettings.Keys.hotkeyModifiers)
            defaults.set(keyCode, forKey: SharedSettings.Keys.hotkeyKeyCode)
            updateHotkeyRuntimeStatus("检测到冲突组合，已回退为 Option + Space")
        }

        let primaryStatus = registerHotkey(
            hotKeyID: hotKeyID,
            keyCode: UInt32(keyCode),
            modifiers: UInt32(modifiers)
        )
        if primaryStatus == noErr {
            activeHotkeyKeyCode = UInt32(keyCode)
            activeHotkeyModifiers = UInt32(modifiers)
            teardownKeyConsumeTap()
            updateHotkeyRuntimeStatus("已注册: \(HotkeyConfig.modifierTitle(for: modifiers)) + \(HotkeyConfig.keyTitle(for: keyCode))")
            registerTerminalHotkeyIfEnabled()
            return
        }

        // Fallback to a safer default to avoid leaving user on a key combo
        // that still triggers foreground app shortcuts.
        let fallbackModifiers = OptionSetFlag.optionSpaceModifiers.rawValue
        let fallbackKeyCode = OptionSetFlag.spaceKeyCode.rawValue
        let fallbackStatus = registerHotkey(
            hotKeyID: hotKeyID,
            keyCode: UInt32(fallbackKeyCode),
            modifiers: UInt32(fallbackModifiers)
        )
        if fallbackStatus == noErr {
            defaults.set(fallbackModifiers, forKey: SharedSettings.Keys.hotkeyModifiers)
            defaults.set(fallbackKeyCode, forKey: SharedSettings.Keys.hotkeyKeyCode)
            activeHotkeyKeyCode = UInt32(fallbackKeyCode)
            activeHotkeyModifiers = UInt32(fallbackModifiers)
            teardownKeyConsumeTap()
            updateHotkeyRuntimeStatus("原组合注册失败，已回退为 Option + Space")
            registerTerminalHotkeyIfEnabled()
            return
        }

        updateHotkeyRuntimeStatus("热键注册失败: main=\(primaryStatus), fallback=\(fallbackStatus)")

        registerTerminalHotkeyIfEnabled()
    }

    private func registerTerminalHotkeyIfEnabled() {
        if let ref = terminalHotkeyRef {
            UnregisterEventHotKey(ref)
            terminalHotkeyRef = nil
        }

        let defaults = SharedSettings.defaults
        let enabled = defaults.object(forKey: SharedSettings.Keys.terminalHotkeyEnabled) as? Bool ?? false
        guard enabled else { return }

        let modifiers = defaults.object(forKey: SharedSettings.Keys.terminalHotkeyModifiers) as? Int ?? controlKey
        let keyCode = defaults.object(forKey: SharedSettings.Keys.terminalHotkeyKeyCode) as? Int ?? 49

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x564F4943) // "VOIC"
        hotKeyID.id = 2

        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &newRef
        )
        if status == noErr {
            terminalHotkeyRef = newRef
        }
    }

    private func installHotkeyHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ in
                guard let event else { return noErr }
                let kind = GetEventKind(event)

                var hotKeyID = EventHotKeyID()
                let idStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                let hotkeyIndex: UInt32 = (idStatus == noErr) ? hotKeyID.id : 1

                if kind == UInt32(kEventHotKeyPressed) {
                    DispatchQueue.main.async {
                        if hotkeyIndex == 2 {
                            VoiceTerminalService.shared.handleHotkeyPressed()
                        } else {
                            AppHotkeyVoiceService.activeService?.handleHotkeyPressed()
                        }
                    }
                } else if kind == UInt32(kEventHotKeyReleased) {
                    DispatchQueue.main.async {
                        if hotkeyIndex == 2 {
                            VoiceTerminalService.shared.handleHotkeyReleased()
                        } else {
                            AppHotkeyVoiceService.activeService?.handleHotkeyReleased()
                        }
                    }
                }
                return noErr
            },
            Int(eventTypes.count),
            &eventTypes,
            nil,
            nil
        )
    }

    private func registerHotkey(hotKeyID: EventHotKeyID, keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &newRef
        )
        if status == noErr {
            hotkeyRef = newRef
        }
        return status
    }

    @objc private func reloadHotkeyConfiguration() {
        if Thread.isMainThread {
            setupGlobalHotkey()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.setupGlobalHotkey()
            }
        }
    }

    var isMode1Active: Bool { isVoiceInputActive }

    private func unregisterGlobalHotkey() {
        if let hotkeyRef = hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
        if let ref = terminalHotkeyRef {
            UnregisterEventHotKey(ref)
            terminalHotkeyRef = nil
        }
        teardownKeyConsumeTap()
    }

    private func setupKeyConsumeTap() {
        teardownKeyConsumeTap()

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            guard let service = AppHotkeyVoiceService.activeService else {
                return Unmanaged.passUnretained(event)
            }
            return service.handleKeyConsumeTap(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: nil
        ) else {
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }

        keyConsumeTap = tap
        keyConsumeTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func teardownKeyConsumeTap() {
        if let source = keyConsumeTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            keyConsumeTapSource = nil
        }
        if let tap = keyConsumeTap {
            CFMachPortInvalidate(tap)
            keyConsumeTap = nil
        }
    }

    private func handleKeyConsumeTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == activeHotkeyKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        let modifiers = HotkeyConfig.carbonFlags(from: NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)))
        let mask = UInt32(optionKey | cmdKey | controlKey | shiftKey)
        let current = UInt32(modifiers) & mask
        let expected = activeHotkeyModifiers & mask
        if current == expected {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func updateHotkeyRuntimeStatus(_ status: String) {
        let defaults = SharedSettings.defaults
        defaults.set(status, forKey: SharedSettings.Keys.hotkeyRuntimeStatus)
    }

    private func handleHotkeyPressed() {
        hotkeyPressBeganAt = Date().timeIntervalSince1970
        stopHandledOnPress = false

        // Mutual exclusion: don't activate if Mode 2 is active
        guard !VoiceTerminalService.shared.isMode2Active else { return }

        // Hold-to-talk model: key down starts recording, repeat keyDown while holding is ignored.
        if isVoiceInputActive {
            return
        }

        pendingStopAfterActivation = false
        statusPanel.showArming()
        RealtimeSessionStore.shared.setStage(.arming, text: "准备中")
        Task { @MainActor in
            let granted = await ensurePreflightPermissions()
            guard granted else { return }
            startRecording()
        }
    }

    private func handleHotkeyReleased() {
        defer { stopHandledOnPress = false }

        // Hold-to-talk model: key up always ends recording if active.
        if isVoiceInputActive && !stopHandledOnPress {
            stopRecordingAndProcess()
            return
        }

        // If key is released while still arming, stop immediately after activation.
        if !isVoiceInputActive {
            pendingStopAfterActivation = true
        }
    }

    private func startRecording() {
        guard !isVoiceInputActive else { return }
        isVoiceInputActive = true
        currentText = ""
        pendingCopyContext = nil
        let shouldMuteExternalAudio = SharedSettings.defaults.object(forKey: SharedSettings.Keys.muteExternalAudioDuringInput) as? Bool ?? true
        if shouldMuteExternalAudio {
            pauseExternalAudioBestEffort()
        }
        statusPanel.showListening(text: "")
        RealtimeSessionStore.shared.setStage(.listening, text: "正在收音...")
        RealtimeSessionStore.shared.updateOriginalLiveText("")
        RealtimeSessionStore.shared.updateRewrittenText("")

        do {
            try whisperEngine.start()
            if pendingStopAfterActivation {
                pendingStopAfterActivation = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.stopRecordingAndProcess()
                }
            }
        } catch {
            isVoiceInputActive = false
            pendingStopAfterActivation = false
            reportError(.startup, message: error.localizedDescription)
        }
    }

    private func stopRecordingAndProcess() {
        guard isVoiceInputActive else { return }
        isStoppingRecording = true
        whisperEngine.stop()
        isStoppingRecording = false

        let capturedText = currentText
        currentText = ""
        isVoiceInputActive = false
        pendingStopAfterActivation = false

        guard !capturedText.isEmpty else {
            statusPanel.hide()
            RealtimeSessionStore.shared.setStage(.idle, text: "已停止")
            return
        }

        let localProcessed = textProcessor.process(capturedText)
        statusPanel.showThinking(text: localProcessed)
        RealtimeSessionStore.shared.setStage(.rewriting, text: "改写中")
        RealtimeSessionStore.shared.updateOriginalLiveText(capturedText)

        guard shouldUseLLM else {
            deliverResult(
                originalText: capturedText,
                processedText: localProcessed,
                finalText: localProcessed,
                style: effectiveStyle(),
                note: "local_only"
            )
            return
        }

        let style = effectiveStyle()
        let baseURL = SharedSettings.defaults.string(forKey: SharedSettings.Keys.llmAPIBaseURL) ?? "https://oneapi.gemiaude.com/v1"
        let apiKey = SharedSettings.defaults.string(forKey: SharedSettings.Keys.llmAPIKey) ?? ""
        let model = SharedSettings.defaults.string(forKey: SharedSettings.Keys.llmModel) ?? "gemini-2.5-flash-lite"
        statusPanel.showThinking(text: localProcessed)
        RealtimeSessionStore.shared.setStage(.rewriting, text: "改写中")

        Task {
            do {
                let polished = try await polishClient.polish(
                    text: localProcessed,
                    style: style,
                    model: model,
                    baseURL: baseURL,
                    apiKey: apiKey
                )
                DispatchQueue.main.async {
                    let finalText = polished.isEmpty ? localProcessed : polished
                    self.deliverResult(
                        originalText: capturedText,
                        processedText: localProcessed,
                        finalText: finalText,
                        style: style,
                        note: "llm_success"
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self.deliverResult(
                        originalText: capturedText,
                        processedText: localProcessed,
                        finalText: localProcessed,
                        style: style,
                        note: "llm_fallback:\(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func deliverResult(
        originalText: String,
        processedText: String,
        finalText: String,
        style: String,
        note: String
    ) {
        RealtimeSessionStore.shared.updateRewrittenText(finalText)

        if insertTextIntoFocusedApp(finalText) {
            statusPanel.hide()
            RealtimeSessionStore.shared.setStage(.inserted, text: "已输入到焦点位置")
            InputHistoryStore.shared.append(
                InputHistoryItem(
                    originalText: originalText,
                    processedText: processedText,
                    finalText: finalText,
                    style: style,
                    status: .inserted,
                    note: note
                )
            )
            return
        }

        pendingCopyContext = PendingCopyContext(
            originalText: originalText,
            processedText: processedText,
            finalText: finalText,
            style: style
        )
        statusPanel.show(status: "无法直接输入", text: "未检测到输入框，点击复制后手动粘贴", showCopy: true)
        RealtimeSessionStore.shared.setStage(.pendingCopy, text: "无焦点，等待复制")
        InputHistoryStore.shared.append(
            InputHistoryItem(
                originalText: originalText,
                processedText: processedText,
                finalText: finalText,
                style: style,
                status: .pendingCopy,
                note: note + "|no_focus"
            )
        )
    }

    private var shouldUseLLM: Bool {
        SharedSettings.defaults.object(forKey: SharedSettings.Keys.llmEnabled) as? Bool ?? false
    }

    private func effectiveStyle() -> String {
        let selected = SharedSettings.defaults.string(forKey: SharedSettings.Keys.selectedStyle) ?? "default"
        if selected == "default" {
            return SceneDetector.shared.detectCurrentScene().apiStyle
        }
        return selected
    }

    private func insertTextIntoFocusedApp(_ text: String) -> Bool {
        guard hasFocusedElement() else { return false }

        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            pasteboard.clearContents()
            if let original = original {
                pasteboard.setString(original, forType: .string)
            }
        }
        return true
    }

    private func hasFocusedElement() -> Bool {
        guard AccessibilityTrust.isTrusted(prompt: false) else { return false }
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        return status == .success && focused != nil
    }

    private func copyPendingTextToClipboard() {
        guard let context = pendingCopyContext else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(context.finalText, forType: .string)
        statusPanel.update(status: "内容已复制。请回到目标输入框粘贴。", text: context.finalText, showCopy: true)
        InputHistoryStore.shared.append(
            InputHistoryItem(
                originalText: context.originalText,
                processedText: context.processedText,
                finalText: context.finalText,
                style: context.style,
                status: .copied,
                note: "manual_copy"
            )
        )
    }

    @MainActor
    private func ensurePreflightPermissions() async -> Bool {
        let diag = PermissionDiagnostics.snapshot()
        if !diag.inApplications {
            #if DEBUG
            let msg = "当前从临时构建路径运行，权限可能不稳定。建议安装到 /Applications/VoiceInput.app。"
            statusPanel.show(status: "开发模式提示", text: msg, showCopy: false)
            RealtimeSessionStore.shared.setStage(.idle, text: msg)
            #else
            let msg = "当前从临时构建路径运行，权限可能不稳定。请先安装到 /Applications/VoiceInput.app 再试。"
            reportError(.permission, message: msg)
            RealtimeSessionStore.shared.setStage(.permissionBlocked, text: msg)
            return false
            #endif
        }

        let speechGranted = await ensureSpeechPermission()
        guard speechGranted else {
            let msg = "未授权语音识别。请在 系统设置 > 隐私与安全性 > 语音识别 中允许 VoiceInput，并重启应用后重试。"
            reportError(.permission, message: msg)
            RealtimeSessionStore.shared.setStage(.permissionBlocked, text: msg)
            openSystemPrivacySettings(anchor: "Privacy_SpeechRecognition")
            return false
        }

        let micGranted = await ensureMicrophonePermission()
        guard micGranted else {
            let msg = "未授权麦克风。请在 系统设置 > 隐私与安全性 > 麦克风 中允许 VoiceInput，并重启应用后重试。"
            reportError(.permission, message: msg)
            RealtimeSessionStore.shared.setStage(.permissionBlocked, text: msg)
            openSystemPrivacySettings(anchor: "Privacy_Microphone")
            return false
        }

        let axGranted = await ensureAccessibilityPermission()
        guard axGranted else {
            let msg = "未授权辅助功能。请在 系统设置 > 隐私与安全性 > 辅助功能 中允许 VoiceInput，并重启应用后重试。"
            reportError(.permission, message: msg)
            RealtimeSessionStore.shared.setStage(.permissionBlocked, text: msg)
            openSystemPrivacySettings(anchor: "Privacy_Accessibility")
            return false
        }
        return true
    }

    private func ensureSpeechPermission() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return true }
        if status == .denied || status == .restricted { return false }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { result in
                continuation.resume(returning: result == .authorized)
            }
        }
    }

    private func ensureMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .authorized { return true }
        if status == .denied || status == .restricted { return false }
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func ensureAccessibilityPermission() async -> Bool {
        if AccessibilityTrust.isTrusted(prompt: false) { return true }

        // Stale TCC entry from previous build? Reset and re-prompt.
        if AccessibilityTrust.resetAndReauthorize() { return true }

        // Wait for user to toggle the switch in System Settings.
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if AccessibilityTrust.isTrusted(prompt: false) { return true }
        }
        return AccessibilityTrust.isTrusted(prompt: false)
    }

    private func reportError(_ kind: VoiceInputErrorKind, message: String) {
        let prefix: String
        switch kind {
        case .permission:
            prefix = "权限异常"
        case .recognition:
            prefix = "识别失败"
        case .rewrite:
            prefix = "改写失败"
        case .injection:
            prefix = "注入失败"
        case .startup:
            prefix = "启动失败"
        }
        statusPanel.showError("\(prefix)：\(message)")
        RealtimeSessionStore.shared.setStage(.failed, text: "\(prefix)：\(message)")
    }

    private func openSystemPrivacySettings(anchor: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        NSWorkspace.shared.open(url)
    }

    private func pauseExternalAudioBestEffort() {
        // Avoid "Where is <App>?" chooser popups by only targeting installed + running apps.
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

extension AppHotkeyVoiceService: WhisperEngineDelegate {
    func whisperEngine(_ engine: WhisperEngine, didTranscribe result: TranscriptionResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.isVoiceInputActive && !self.isStoppingRecording else { return }
            self.currentText = result.text
        }
    }

    func whisperEngine(_ engine: WhisperEngine, didUpdatePartialResult text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.isVoiceInputActive && !self.isStoppingRecording else { return }
            self.currentText = text
            self.statusPanel.showListening(text: text)
            RealtimeSessionStore.shared.setStage(.transcribing, text: "实时转写中...")
            RealtimeSessionStore.shared.updateOriginalLiveText(text)
        }
    }

    func whisperEngine(_ engine: WhisperEngine, didFailWithError error: WhisperError) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Ignore late errors emitted while we are intentionally stopping.
            if self.isStoppingRecording || !self.isVoiceInputActive {
                return
            }
            self.isVoiceInputActive = false
            self.reportError(.recognition, message: error.localizedDescription)
        }
    }
}
