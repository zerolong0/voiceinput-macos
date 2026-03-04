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
    private var hotkeyHandlerInstalled = false
    private var keyConsumeTap: CFMachPort?
    private var keyConsumeTapSource: CFRunLoopSource?
    private var activeHotkeyModifiers: UInt32 = UInt32(OptionSetFlag.optionSpaceModifiers.rawValue)
    private var activeHotkeyKeyCode: UInt32 = UInt32(OptionSetFlag.spaceKeyCode.rawValue)
    private var isVoiceInputActive = false
    private var isContinuousMode = false
    private var currentText = ""
    private var isStoppingRecording = false
    private var isHotkeyCurrentlyDown = false
    private var shouldStartContinuousOnActivation = false
    private var lastHotkeyReleaseAt: TimeInterval = 0
    private var stopHandledOnPress = false
    private var pendingStopAfterActivation = false
    private var didAttemptRecognitionRecovery = false

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
    private let doubleTapWindow: TimeInterval = 0.35

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
            if modifiers == 0 {
                setupKeyConsumeTap()
            } else {
                teardownKeyConsumeTap()
            }
            updateHotkeyRuntimeStatus("已注册: \(formattedHotkey(modifiers: modifiers, keyCode: keyCode))")
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
            return
        }

        updateHotkeyRuntimeStatus("热键注册失败: main=\(primaryStatus), fallback=\(fallbackStatus)")
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
                if kind == UInt32(kEventHotKeyPressed) {
                    DispatchQueue.main.async {
                        AppHotkeyVoiceService.activeService?.handleHotkeyPressed()
                    }
                } else if kind == UInt32(kEventHotKeyReleased) {
                    DispatchQueue.main.async {
                        AppHotkeyVoiceService.activeService?.handleHotkeyReleased()
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

    private func unregisterGlobalHotkey() {
        if let hotkeyRef = hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
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

    private func formattedHotkey(modifiers: Int, keyCode: Int) -> String {
        if modifiers == 0 {
            return HotkeyConfig.keyTitle(for: keyCode)
        }
        return "\(HotkeyConfig.modifierTitle(for: modifiers)) + \(HotkeyConfig.keyTitle(for: keyCode))"
    }

    private func handleHotkeyPressed() {
        if isHotkeyCurrentlyDown {
            return
        }
        isHotkeyCurrentlyDown = true
        stopHandledOnPress = false
        let now = Date().timeIntervalSince1970

        // In continuous mode, a single press ends recording immediately.
        if isVoiceInputActive && isContinuousMode {
            stopHandledOnPress = true
            stopRecordingAndProcess()
            return
        }

        // Hold-to-talk model: key down starts recording, repeat keyDown while holding is ignored.
        if isVoiceInputActive {
            return
        }

        let isDoubleTap = lastHotkeyReleaseAt > 0 && (now - lastHotkeyReleaseAt) <= doubleTapWindow
        pendingStopAfterActivation = false
        shouldStartContinuousOnActivation = isDoubleTap
        statusPanel.showArming()
        RealtimeSessionStore.shared.setStage(.arming, text: "准备中")
        Task { @MainActor in
            let granted = await ensurePreflightPermissions()
            guard granted else { return }
            startRecording(startInContinuousMode: shouldStartContinuousOnActivation)
        }
    }

    private func handleHotkeyReleased() {
        guard isHotkeyCurrentlyDown else { return }
        isHotkeyCurrentlyDown = false
        lastHotkeyReleaseAt = Date().timeIntervalSince1970
        defer { stopHandledOnPress = false }

        if isContinuousMode {
            // Continuous mode keeps recording across key release.
            return
        }

        // Hold-to-talk model: key up always ends recording if active.
        if isVoiceInputActive && !stopHandledOnPress {
            stopRecordingAndProcess()
            return
        }

        // If key is released while still arming, stop immediately after activation.
        if !isVoiceInputActive && !shouldStartContinuousOnActivation {
            pendingStopAfterActivation = true
        }
    }

    private func startRecording(startInContinuousMode: Bool = false) {
        guard !isVoiceInputActive else { return }
        isVoiceInputActive = true
        didAttemptRecognitionRecovery = false
        isContinuousMode = startInContinuousMode
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
            if isContinuousMode {
                statusPanel.show(status: "连续输入已开启", text: "双击进入连续模式后，可按一次快捷键结束", showCopy: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                    guard let self else { return }
                    guard self.isVoiceInputActive, self.isContinuousMode else { return }
                    self.statusPanel.showListening(text: self.currentText)
                }
            }
            if pendingStopAfterActivation && !isContinuousMode {
                pendingStopAfterActivation = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.stopRecordingAndProcess()
                }
            }
        } catch {
            isVoiceInputActive = false
            isContinuousMode = false
            pendingStopAfterActivation = false
            shouldStartContinuousOnActivation = false
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
        didAttemptRecognitionRecovery = false
        isContinuousMode = false
        pendingStopAfterActivation = false
        shouldStartContinuousOnActivation = false

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
        guard let focused = focusedElement() else { return false }

        // Prefer AX direct insertion for editable controls; fallback to pasteboard Cmd+V.
        if insertTextViaAX(text, into: focused) {
            return true
        }

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

    private func focusedElement() -> AXUIElement? {
        guard AccessibilityTrust.isTrusted(prompt: false) else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard status == .success, let focused else { return nil }
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return (focused as! AXUIElement)
    }

    private func insertTextViaAX(_ text: String, into element: AXUIElement) -> Bool {
        guard isAXEditable(element) else { return false }

        var valueRef: CFTypeRef?
        let valueStatus = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        guard valueStatus == .success, let valueRef, let currentValue = valueRef as? String else {
            return false
        }

        var rangeRef: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        guard rangeStatus == .success, let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else {
            return false
        }
        let axRange = (rangeRef as! AXValue)

        var selected = CFRange()
        guard AXValueGetType(axRange) == .cfRange, AXValueGetValue(axRange, .cfRange, &selected) else {
            return false
        }

        let nsCurrent = currentValue as NSString
        let safeLocation = max(0, min(selected.location, nsCurrent.length))
        let safeLength = max(0, min(selected.length, nsCurrent.length - safeLocation))
        let safeRange = NSRange(location: safeLocation, length: safeLength)
        let merged = nsCurrent.replacingCharacters(in: safeRange, with: text)

        let setStatus = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, merged as CFTypeRef)
        guard setStatus == .success else { return false }

        var newCaret = CFRange(location: safeLocation + (text as NSString).length, length: 0)
        guard let newAXRange = AXValueCreate(.cfRange, &newCaret) else { return true }
        _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, newAXRange)
        return true
    }

    private func isAXEditable(_ element: AXUIElement) -> Bool {
        let axEditableAttr = "AXEditable" as CFString
        var editableRef: CFTypeRef?
        let editableStatus = AXUIElementCopyAttributeValue(element, axEditableAttr, &editableRef)
        if editableStatus == .success, let editable = editableRef as? Bool, editable {
            return true
        }

        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else {
            return false
        }
        return role == kAXTextAreaRole as String || role == kAXTextFieldRole as String || role == "AXSearchField"
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
        if AccessibilityTrust.isTrusted(prompt: true) { return true }

        // TCC sometimes updates with delay after user toggles switch.
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if AccessibilityTrust.isTrusted(prompt: false) { return true }
            if PermissionDiagnostics.snapshot().accessibilityEffective { return true }
        }
        return PermissionDiagnostics.snapshot().accessibilityEffective
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

            if !self.didAttemptRecognitionRecovery {
                self.didAttemptRecognitionRecovery = true
                let preservedText = self.currentText
                do {
                    try self.whisperEngine.start()
                    self.currentText = preservedText
                    self.statusPanel.showListening(text: preservedText)
                    RealtimeSessionStore.shared.setStage(.transcribing, text: "实时转写中...")
                    RealtimeSessionStore.shared.updateOriginalLiveText(preservedText)
                    return
                } catch {
                    self.isVoiceInputActive = false
                    self.reportError(.recognition, message: "自动恢复失败：\(error.localizedDescription)")
                    return
                }
            }

            self.isVoiceInputActive = false
            self.reportError(.recognition, message: error.localizedDescription)
        }
    }
}
