import Cocoa
import Carbon
import ApplicationServices
import AVFoundation
import Speech
import OSLog

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
    private let logger = Logger(subsystem: "com.voiceinput.macos", category: "hotkey")

    private var hotkeyRef: EventHotKeyRef?
    private var terminalHotkeyRef: EventHotKeyRef?
    private var hotkeyHandlerInstalled = false
    private var keyConsumeTap: CFMachPort?
    private var keyConsumeTapSource: CFRunLoopSource?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var activeHotkeyModifiers: UInt32 = UInt32(OptionSetFlag.optionSpaceModifiers.rawValue)
    private var activeHotkeyKeyCode: UInt32 = UInt32(OptionSetFlag.spaceKeyCode.rawValue)
    private var activeTerminalHotkeyModifiers: UInt32 = UInt32(controlKey)
    private var activeTerminalHotkeyKeyCode: UInt32 = 49
    private var eventTapHandlesHotkeys = true
    private var keyTapAvailable = false
    private var isFunctionModifierPressed = false
    private var isVoiceInputActive = false
    private var currentText = ""
    private var isStoppingRecording = false
    private var isHotkeyCurrentlyDown = false
    private var stopHandledOnPress = false
    private var pendingStopAfterActivation = false
    private var didAttemptRecognitionRecovery = false
    private var isPreflightInProgress = false
    private var didPromptAccessibilityThisLaunch = false
    private var insertionTargetElement: AXUIElement?
    private var insertionTargetPID: pid_t?
    private let insertionRetryDelays: [TimeInterval] = [0.12, 0.28, 0.52]

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
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleDebugInjectionRequest(_:)),
            name: Notification.Name("com.voiceinput.debug.injectText"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    deinit {
        whisperEngine.stop()
        unregisterGlobalHotkey()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc
    private func handleDebugInjectionRequest(_ notification: Notification) {
        guard let text = notification.userInfo?["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        RuntimeDiagnosticsStore.record("voice-input", "Received debug injection request")
        captureInsertionTarget()
        deliverResult(
            originalText: text,
            processedText: text,
            finalText: text,
            style: effectiveStyle(),
            note: "debug_injection"
        )
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
            registerTerminalHotkeyIfEnabled()
            return
        }

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x564F4943) // "VOIC"
        hotKeyID.id = 1

        let modifiers = defaults.object(forKey: SharedSettings.Keys.hotkeyModifiers) as? Int ?? HotkeyConfig.defaultModifiers
        let keyCode = defaults.object(forKey: SharedSettings.Keys.hotkeyKeyCode) as? Int ?? HotkeyConfig.defaultKeyCode

        let primaryStatus = registerHotkey(
            hotKeyID: hotKeyID,
            keyCode: UInt32(keyCode),
            modifiers: UInt32(modifiers)
        )
        logger.notice("Attempting to register hotkey modifiers=\(modifiers, privacy: .public) keyCode=\(keyCode, privacy: .public) status=\(primaryStatus, privacy: .public)")
        if primaryStatus == noErr {
            activeHotkeyKeyCode = UInt32(keyCode)
            activeHotkeyModifiers = UInt32(modifiers)
            refreshEventTapHandlingPolicy()
            setupKeyConsumeTap()
            setupKeyEventMonitors()
            updateHotkeyRuntimeStatus("已注册: \(formattedHotkey(modifiers: modifiers, keyCode: keyCode))")
            registerTerminalHotkeyIfEnabled()
            return
        }

        updateHotkeyRuntimeStatus("热键注册失败（可能冲突）: status=\(primaryStatus)")
        activeHotkeyKeyCode = UInt32(keyCode)
        activeHotkeyModifiers = UInt32(modifiers)
        refreshEventTapHandlingPolicy()
        setupKeyConsumeTap()
        setupKeyEventMonitors()
        registerTerminalHotkeyIfEnabled()
    }

    private func registerTerminalHotkeyIfEnabled() {
        if let ref = terminalHotkeyRef {
            UnregisterEventHotKey(ref)
            terminalHotkeyRef = nil
        }

        let defaults = SharedSettings.defaults
        let enabled = defaults.object(forKey: SharedSettings.Keys.terminalHotkeyEnabled) as? Bool ?? false
        guard enabled else {
            updateTerminalHotkeyRuntimeStatus("已关闭")
            refreshEventTapHandlingPolicy()
            return
        }

        let modifiers = defaults.object(forKey: SharedSettings.Keys.terminalHotkeyModifiers) as? Int ?? HotkeyConfig.defaultTerminalModifiers
        let keyCode = defaults.object(forKey: SharedSettings.Keys.terminalHotkeyKeyCode) as? Int ?? HotkeyConfig.defaultTerminalKeyCode
        activeTerminalHotkeyModifiers = UInt32(modifiers)
        activeTerminalHotkeyKeyCode = UInt32(keyCode)

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x564F4943) // "VOIC"
        hotKeyID.id = 2

        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )
        if status == noErr {
            terminalHotkeyRef = newRef
            updateTerminalHotkeyRuntimeStatus("已注册: \(formattedHotkey(modifiers: modifiers, keyCode: keyCode))")
        } else {
            updateTerminalHotkeyRuntimeStatus("热键注册失败（可能冲突）: status=\(status)")
        }
        refreshEventTapHandlingPolicy()
    }

    private func installHotkeyHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        InstallEventHandler(
            GetApplicationEventTarget(),
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
            GetApplicationEventTarget(),
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
        teardownKeyEventMonitors()
    }

    private func setupKeyConsumeTap() {
        teardownKeyConsumeTap()
        keyTapAvailable = false

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
            logger.error("CGEvent tap unavailable; falling back to NSEvent monitors")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }

        keyConsumeTap = tap
        keyConsumeTapSource = source
        keyTapAvailable = true
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
        keyTapAvailable = false
        isFunctionModifierPressed = false
    }

    private func setupKeyEventMonitors() {
        teardownKeyEventMonitors()

        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handleMonitoredKeyEvent(event)
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged], handler: handler)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            self?.handleMonitoredKeyEvent(event)
            return event
        }
    }

    private func teardownKeyEventMonitors() {
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    private func handleMonitoredKeyEvent(_ event: NSEvent) {
        let fnPressedForCurrentEvent = (event.type == .flagsChanged && Int(event.keyCode) == 63)
            ? event.modifierFlags.contains(.function)
            : (isFunctionModifierPressed || event.modifierFlags.contains(.function))

        if handleModifierOnlyFlagsChanged(
            event,
            keyCode: activeHotkeyKeyCode,
            modifiers: activeHotkeyModifiers,
            onPressed: { [weak self] in self?.handleHotkeyPressed() },
            onReleased: { [weak self] in self?.handleHotkeyReleased() }
        ) {
            if event.type == .flagsChanged, Int(event.keyCode) == 63 {
                isFunctionModifierPressed = event.modifierFlags.contains(.function)
            }
            return
        }

        let terminalEnabled = SharedSettings.defaults.object(forKey: SharedSettings.Keys.terminalHotkeyEnabled) as? Bool ?? false
        if terminalEnabled,
           handleModifierOnlyFlagsChanged(
            event,
            keyCode: activeTerminalHotkeyKeyCode,
            modifiers: activeTerminalHotkeyModifiers,
            onPressed: { VoiceTerminalService.shared.handleHotkeyPressed() },
            onReleased: { VoiceTerminalService.shared.handleHotkeyReleased() }
           ) {
            if event.type == .flagsChanged, Int(event.keyCode) == 63 {
                isFunctionModifierPressed = event.modifierFlags.contains(.function)
            }
            return
        }

        if event.type == .flagsChanged,
           Int(event.keyCode) == 63 {
            isFunctionModifierPressed = event.modifierFlags.contains(.function)
        }

        guard shouldUseMonitorFallback(for: event) else { return }

        if matchesHotkey(
            event,
            keyCode: activeHotkeyKeyCode,
            modifiers: activeHotkeyModifiers,
            functionPressedForEvent: fnPressedForCurrentEvent
        ) {
            if event.type == .keyDown || (event.type == .flagsChanged && isModifierPressEvent(event)) {
                handleHotkeyPressed()
            } else if event.type == .keyUp || (event.type == .flagsChanged && !isModifierPressEvent(event)) {
                handleHotkeyReleased()
            }
            return
        }

        guard terminalEnabled else { return }
        guard matchesHotkey(
            event,
            keyCode: activeTerminalHotkeyKeyCode,
            modifiers: activeTerminalHotkeyModifiers,
            functionPressedForEvent: fnPressedForCurrentEvent
        ) else { return }

        if event.type == .keyDown || (event.type == .flagsChanged && isModifierPressEvent(event)) {
            VoiceTerminalService.shared.handleHotkeyPressed()
        } else if event.type == .keyUp || (event.type == .flagsChanged && !isModifierPressEvent(event)) {
            VoiceTerminalService.shared.handleHotkeyReleased()
        }
    }

    private func shouldUseMonitorFallback(for event: NSEvent) -> Bool {
        guard event.type == .keyDown || event.type == .keyUp || event.type == .flagsChanged else { return false }
        if !keyTapAvailable { return true }
        if !eventTapHandlesHotkeys { return true }
        if HotkeyConfig.isModifierOnlyKeyCode(Int(activeHotkeyKeyCode)) || HotkeyConfig.isModifierOnlyKeyCode(Int(activeTerminalHotkeyKeyCode)) {
            return true
        }
        return activeHotkeyModifiers == 0 || activeTerminalHotkeyModifiers == 0
    }

    private func matchesHotkey(
        _ event: NSEvent,
        keyCode: UInt32,
        modifiers: UInt32,
        functionPressedForEvent: Bool?
    ) -> Bool {
        let mask = UInt32(HotkeyConfig.modifierMask)
        var currentModifiers = UInt32(
            HotkeyConfig.carbonFlags(
                from: event.modifierFlags.intersection([.option, .command, .control, .shift, .function])
            )
        )
        if functionPressedForEvent ?? isFunctionModifierPressed {
            currentModifiers |= UInt32(HotkeyConfig.functionModifierFlag)
        }
        if (modifiers & UInt32(HotkeyConfig.functionModifierFlag)) == 0,
           HotkeyConfig.isFunctionRowKeyCode(Int(keyCode)) {
            currentModifiers &= ~UInt32(HotkeyConfig.functionModifierFlag)
        }
        return UInt32(event.keyCode) == keyCode && (currentModifiers & mask) == (modifiers & mask)
    }

    private func handleModifierOnlyFlagsChanged(
        _ event: NSEvent,
        keyCode: UInt32,
        modifiers: UInt32,
        onPressed: () -> Void,
        onReleased: () -> Void
    ) -> Bool {
        guard event.type == .flagsChanged else { return false }
        guard HotkeyConfig.isModifierOnlyKeyCode(Int(keyCode)) else { return false }
        guard UInt32(event.keyCode) == keyCode else { return false }

        let expectedFlag = UInt32(HotkeyConfig.modifierFlag(for: Int(keyCode)) ?? 0)
        guard expectedFlag != 0 else { return false }
        guard (UInt32(modifiers) & expectedFlag) != 0 else { return false }

        if isModifierKeyPressed(event) {
            onPressed()
        } else {
            onReleased()
        }
        return true
    }

    private func isModifierKeyPressed(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        switch Int(event.keyCode) {
        case 55, 54: return flags.contains(.command)
        case 58, 61: return flags.contains(.option)
        case 59, 62: return flags.contains(.control)
        case 56, 60: return flags.contains(.shift)
        case 63: return flags.contains(.function)
        case 57: return flags.contains(.capsLock)
        default: return false
        }
    }

    private func handleKeyConsumeTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = HotkeyConfig.carbonFlags(from: NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)))
        let mask = UInt32(HotkeyConfig.modifierMask)
        if keyCode == 63 {
            isFunctionModifierPressed = (type == .keyDown)
        }
        var current = UInt32(modifiers) & mask
        if isFunctionModifierPressed {
            current |= UInt32(HotkeyConfig.functionModifierFlag)
        }
        let expectedVoice = activeHotkeyModifiers & mask

        if keyCode == activeHotkeyKeyCode && current == expectedVoice {
            if eventTapHandlesHotkeys {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if type == .keyDown {
                        self.logger.notice("Hotkey detected via event tap keyDown")
                        self.handleHotkeyPressed()
                    } else {
                        self.logger.notice("Hotkey detected via event tap keyUp")
                        self.handleHotkeyReleased()
                    }
                }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        let expectedTerminal = activeTerminalHotkeyModifiers & mask
        let terminalEnabled = SharedSettings.defaults.object(forKey: SharedSettings.Keys.terminalHotkeyEnabled) as? Bool ?? false
        if terminalEnabled && keyCode == activeTerminalHotkeyKeyCode && current == expectedTerminal {
            if eventTapHandlesHotkeys {
                DispatchQueue.main.async {
                    if type == .keyDown {
                        VoiceTerminalService.shared.handleHotkeyPressed()
                    } else {
                        VoiceTerminalService.shared.handleHotkeyReleased()
                    }
                }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func refreshEventTapHandlingPolicy() {
        let functionFlag = UInt32(HotkeyConfig.functionModifierFlag)
        let terminalEnabled = SharedSettings.defaults.object(forKey: SharedSettings.Keys.terminalHotkeyEnabled) as? Bool ?? false
        let voiceUsesFunction = (activeHotkeyModifiers & functionFlag) != 0
        let terminalUsesFunction = terminalEnabled && (activeTerminalHotkeyModifiers & functionFlag) != 0
        // Fn combinations are more reliable via NSEvent monitor fallback.
        eventTapHandlesHotkeys = !(voiceUsesFunction || terminalUsesFunction)
    }

    private func isModifierPressEvent(_ event: NSEvent) -> Bool {
        guard event.type == .flagsChanged else { return false }
        let flags = event.modifierFlags
        switch Int(event.keyCode) {
        case 55, 54: return flags.contains(.command)
        case 58, 61: return flags.contains(.option)
        case 59, 62: return flags.contains(.control)
        case 56, 60: return flags.contains(.shift)
        case 63: return flags.contains(.function)
        case 57: return flags.contains(.capsLock)
        default: return false
        }
    }

    private func updateHotkeyRuntimeStatus(_ status: String) {
        let defaults = SharedSettings.defaults
        defaults.set(status, forKey: SharedSettings.Keys.hotkeyRuntimeStatus)
    }

    private func updateTerminalHotkeyRuntimeStatus(_ status: String) {
        let defaults = SharedSettings.defaults
        defaults.set(status, forKey: SharedSettings.Keys.terminalHotkeyRuntimeStatus)
    }

    private func formattedHotkey(modifiers: Int, keyCode: Int) -> String {
        HotkeyConfig.displayString(modifiers: modifiers, keyCode: keyCode)
    }

    private func handleHotkeyPressed() {
        logger.notice("Hotkey pressed active=\(self.isVoiceInputActive, privacy: .public) mode2=\(VoiceTerminalService.shared.isMode2Active, privacy: .public)")
        if isHotkeyCurrentlyDown {
            logger.notice("Ignoring repeated hotkey press while key is already down")
            return
        }
        isHotkeyCurrentlyDown = true
        stopHandledOnPress = false
        // Mutual exclusion: don't activate if Mode 2 is active
        guard !VoiceTerminalService.shared.isMode2Active else { return }

        // Hold-to-talk model: key down starts recording, repeat keyDown while holding is ignored.
        if isVoiceInputActive {
            return
        }

        pendingStopAfterActivation = false
        captureInsertionTarget()
        statusPanel.showArming()
        RealtimeSessionStore.shared.setStage(.arming, text: "已检测到热键，准备启动语音输入")
        Task { @MainActor in
            guard !self.isPreflightInProgress else {
                self.logger.notice("Skipping hotkey press while preflight check is in progress")
                return
            }
            self.isPreflightInProgress = true
            defer { self.isPreflightInProgress = false }
            let granted = await ensurePreflightPermissions()
            self.logger.notice("Preflight permission result granted=\(granted, privacy: .public)")
            RuntimeDiagnosticsStore.record("voice-input", "Preflight permissions granted=\(granted)")
            guard granted else { return }
            startRecording()
        }
    }

    private func handleHotkeyReleased() {
        logger.notice("Hotkey released active=\(self.isVoiceInputActive, privacy: .public) stopHandled=\(self.stopHandledOnPress, privacy: .public)")
        guard isHotkeyCurrentlyDown else { return }
        isHotkeyCurrentlyDown = false
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
        logger.notice("Starting recording")
        RuntimeDiagnosticsStore.record("voice-input", "Starting recording")
        isVoiceInputActive = true
        didAttemptRecognitionRecovery = false
        currentText = ""
        pendingCopyContext = nil
        let shouldMuteExternalAudio = SharedSettings.defaults.object(forKey: SharedSettings.Keys.muteExternalAudioDuringInput) as? Bool ?? true
        if shouldMuteExternalAudio {
            pauseExternalAudioBestEffort()
        }
        statusPanel.showListening(text: "")
        RealtimeSessionStore.shared.setStage(.listening, text: "热键已触发，正在收音")
        RealtimeSessionStore.shared.updateOriginalLiveText("")
        RealtimeSessionStore.shared.updateRewrittenText("")

        do {
            try whisperEngine.start()
            logger.notice("whisperEngine.start succeeded")
            RuntimeDiagnosticsStore.record("voice-input", "Speech engine started")
            if pendingStopAfterActivation {
                pendingStopAfterActivation = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.stopRecordingAndProcess()
                }
            }
        } catch {
            logger.error("whisperEngine.start failed: \(error.localizedDescription, privacy: .public)")
            RuntimeDiagnosticsStore.record("voice-input", "Speech engine start failed: \(error.localizedDescription)")
            isVoiceInputActive = false
            pendingStopAfterActivation = false
            reportError(.startup, message: error.localizedDescription)
        }
    }

    private func stopRecordingAndProcess() {
        guard isVoiceInputActive else { return }
        logger.notice("Stopping recording and processing currentTextLength=\(self.currentText.count, privacy: .public)")
        RuntimeDiagnosticsStore.record("voice-input", "Stopping recording textLength=\(currentText.count)")
        isStoppingRecording = true
        whisperEngine.stop()
        isStoppingRecording = false

        let capturedText = currentText
        currentText = ""
        isVoiceInputActive = false
        didAttemptRecognitionRecovery = false
        pendingStopAfterActivation = false

        guard !capturedText.isEmpty else {
            logger.notice("No microphone input captured after stop")
            RuntimeDiagnosticsStore.record("voice-input", "No microphone input captured, aborting")
            reportError(.recognition, message: "未捕捉到麦克风输入，请检查麦克风权限、输入设备和环境噪声后重试。")
            return
        }

        let localProcessed = textProcessor.process(capturedText)
        RuntimeDiagnosticsStore.record("voice-input", "Captured transcript length=\(capturedText.count)")
        statusPanel.showThinking(text: "改写中")
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
        let model = SharedSettings.defaults.string(forKey: SharedSettings.Keys.voiceInputModel) ?? "gemini-2.5-flash-lite"
        statusPanel.showThinking(text: "改写中")
        RealtimeSessionStore.shared.setStage(.rewriting, text: "改写中")

        let client = polishClient
        Task {
            do {
                let polished = try await client.polish(
                    text: localProcessed,
                    style: style,
                    model: model,
                    baseURL: baseURL,
                    apiKey: apiKey
                )
                DispatchQueue.main.async {
                    let finalText = polished.isEmpty ? localProcessed : polished
                    AppHotkeyVoiceService.shared.deliverResult(
                        originalText: capturedText,
                        processedText: localProcessed,
                        finalText: finalText,
                        style: style,
                        note: "llm_success"
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    AppHotkeyVoiceService.shared.deliverResult(
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
        logger.notice("Delivering result finalLength=\(finalText.count, privacy: .public)")
        RuntimeDiagnosticsStore.record("voice-input", "Deliver result length=\(finalText.count)")
        RealtimeSessionStore.shared.updateRewrittenText(finalText)
        attemptResultInsertion(
            originalText: originalText,
            processedText: processedText,
            finalText: finalText,
            style: style,
            note: note,
            attemptIndex: 0
        )
    }

    private func attemptResultInsertion(
        originalText: String,
        processedText: String,
        finalText: String,
        style: String,
        note: String,
        attemptIndex: Int
    ) {
        if insertTextIntoFocusedApp(finalText) {
            let finalNote = attemptIndex == 0 ? note : note + "|retry_\(attemptIndex)"
            finalizeInsertedResult(
                originalText: originalText,
                processedText: processedText,
                finalText: finalText,
                style: style,
                note: finalNote
            )
            return
        }

        guard insertionTargetPID != nil, attemptIndex < insertionRetryDelays.count else {
            finalizePendingCopyResult(
                originalText: originalText,
                processedText: processedText,
                finalText: finalText,
                style: style,
                note: note
            )
            return
        }

        let delay = insertionRetryDelays[attemptIndex]
        RealtimeSessionStore.shared.setStage(.transcribing, text: "正在写入焦点位置")
        RuntimeDiagnosticsStore.record("voice-input", "Insert attempt \(attemptIndex + 1) missed, retrying in \(String(format: "%.2f", delay))s")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.attemptResultInsertion(
                originalText: originalText,
                processedText: processedText,
                finalText: finalText,
                style: style,
                note: note,
                attemptIndex: attemptIndex + 1
            )
        }
    }

    private func finalizeInsertedResult(
        originalText: String,
        processedText: String,
        finalText: String,
        style: String,
        note: String
    ) {
        clearInsertionTarget()
        statusPanel.hide()
        RealtimeSessionStore.shared.setStage(.inserted, text: "已输入到焦点位置")
        RuntimeDiagnosticsStore.record("voice-input", "Inserted into focused target successfully")
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
    }

    private func finalizePendingCopyResult(
        originalText: String,
        processedText: String,
        finalText: String,
        style: String,
        note: String
    ) {
        pendingCopyContext = PendingCopyContext(
            originalText: originalText,
            processedText: processedText,
            finalText: finalText,
            style: style
        )
        statusPanel.showCopyFallback(finalText: finalText)
        clearInsertionTarget()
        RealtimeSessionStore.shared.setStage(.pendingCopy, text: "未找到可输入焦点，请复制后粘贴")
        RuntimeDiagnosticsStore.record("voice-input", "Fell back to copy flow because no usable focus target")
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
        activateInsertionTargetIfNeeded()
        let axTargets = candidateInsertionTargets()
        guard !axTargets.isEmpty else {
            RuntimeDiagnosticsStore.record("voice-input", "No AX target available for insertion; trying blind paste fallback")
            if pasteTextBlind(text) {
                RuntimeDiagnosticsStore.record("voice-input", "Inserted via blind paste fallback")
                return true
            }
            RuntimeDiagnosticsStore.record("voice-input", "Blind paste fallback failed")
            return false
        }

        for target in axTargets {
            if insertTextViaAX(text, into: target) {
                RuntimeDiagnosticsStore.record("voice-input", "Inserted via AX value path")
                return true
            }

            if replaceSelectedTextViaAX(text, into: target) {
                RuntimeDiagnosticsStore.record("voice-input", "Inserted via AX selected text path")
                return true
            }
        }

        guard let activeFocusedTarget = candidateInsertionTargets().first(where: { hasUsableInjectionTarget($0) }) else {
            RuntimeDiagnosticsStore.record("voice-input", "Focused AX target disappeared; trying blind paste fallback")
            if pasteTextBlind(text) {
                RuntimeDiagnosticsStore.record("voice-input", "Inserted via blind paste fallback after focus loss")
                return true
            }
            RuntimeDiagnosticsStore.record("voice-input", "Paste fallback skipped because focused target disappeared")
            return false
        }
        return pasteTextViaCommandV(text, target: activeFocusedTarget)
    }

    private func pasteTextBlind(_ text: String) -> Bool {
        guard insertionTargetPID != nil else { return false }
        activateInsertionTargetIfNeeded()

        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .privateState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        guard cmdDown != nil, vDown != nil, vUp != nil, cmdUp != nil else { return false }

        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            pasteboard.clearContents()
            if let original {
                pasteboard.setString(original, forType: .string)
            }
        }
        return true
    }

    private func pasteTextViaCommandV(_ text: String, target: AXUIElement) -> Bool {
        guard hasUsableInjectionTarget(target) else { return false }
        let baselineValue = readableAXValue(from: target)
        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .privateState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        guard cmdDown != nil, vDown != nil, vUp != nil, cmdUp != nil else { return false }
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)

        let verified = waitForPasteInsertion(of: text, target: target, baselineValue: baselineValue)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            pasteboard.clearContents()
            if let original = original {
                pasteboard.setString(original, forType: .string)
            }
        }
        if verified {
            RuntimeDiagnosticsStore.record("voice-input", "Paste fallback verified")
            return true
        }

        // Some apps do not expose AX value updates reliably after Cmd+V, causing false negatives.
        // To avoid duplicate pastes and repeated fallback prompts, treat a posted paste as success
        // when verification is not possible.
        RuntimeDiagnosticsStore.record("voice-input", "Paste fallback posted but not AX-verifiable, treating as success")
        return true
    }

    private func replaceSelectedTextViaAX(_ text: String, into element: AXUIElement) -> Bool {
        guard let selectedRange = selectedTextRange(in: element), selectedRange.length > 0 else {
            return false
        }

        let selectedTextAttribute = kAXSelectedTextAttribute as CFString
        var isSettable = DarwinBoolean(false)
        let settableStatus = AXUIElementIsAttributeSettable(element, selectedTextAttribute, &isSettable)
        guard settableStatus == .success, isSettable.boolValue else {
            return false
        }
        guard AXUIElementSetAttributeValue(element, selectedTextAttribute, text as CFTypeRef) == .success else {
            return false
        }

        if let value = readableAXValue(from: element), value.contains(text) {
            return true
        }
        return readableAXSelectedText(from: element) == text
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

    private func candidateInsertionTargets() -> [AXUIElement] {
        var seen = Set<CFHashCode>()
        var targets: [AXUIElement] = []

        func append(_ element: AXUIElement?) {
            guard let element else { return }
            let hash = CFHash(element)
            guard !seen.contains(hash) else { return }
            seen.insert(hash)
            targets.append(element)
        }

        let primary = focusedElement()
        append(primary)
        append(insertionTargetElement)
        for element in [primary, insertionTargetElement] {
            for ancestor in ancestorTargets(from: element, depth: 3) {
                append(ancestor)
            }
        }
        return targets
    }

    private func ancestorTargets(from element: AXUIElement?, depth: Int) -> [AXUIElement] {
        guard let element, depth > 0 else { return [] }
        var result: [AXUIElement] = []
        var current: AXUIElement? = element
        for _ in 0..<depth {
            guard let next = parentElement(of: current) else { break }
            result.append(next)
            current = next
        }
        return result
    }

    private func parentElement(of element: AXUIElement?) -> AXUIElement? {
        guard let element else { return nil }
        var parent: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent)
        guard status == .success, let parent else { return nil }
        guard CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
        return (parent as! AXUIElement)
    }

    private func insertTextViaAX(_ text: String, into element: AXUIElement) -> Bool {
        guard isAXEditable(element) else { return false }
        guard let currentValue = readableAXValue(from: element) else {
            return false
        }
        guard let selected = selectedTextRange(in: element) else {
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
        if let newAXRange = AXValueCreate(.cfRange, &newCaret) {
            _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, newAXRange)
        }
        return readableAXValue(from: element) == merged
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
        let editableRoles: Set<String> = [
            kAXTextAreaRole as String,
            kAXTextFieldRole as String,
            "AXSearchField",
            "AXComboBox",
            "AXDocument",
            "AXWebArea"
        ]
        return editableRoles.contains(role)
    }

    private func captureInsertionTarget() {
        guard let focused = focusedElement() else {
            insertionTargetElement = nil
            insertionTargetPID = nil
            return
        }

        insertionTargetElement = focused
        var pid: pid_t = 0
        if AXUIElementGetPid(focused, &pid) == .success, pid > 0 {
            insertionTargetPID = pid
        } else {
            insertionTargetPID = nil
        }
    }

    private func activateInsertionTargetIfNeeded() {
        guard let pid = insertionTargetPID,
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid }),
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }
        _ = app.activate(options: NSApplication.ActivationOptions.activateIgnoringOtherApps)
        for _ in 0..<12 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
    }

    private func clearInsertionTarget() {
        insertionTargetElement = nil
        insertionTargetPID = nil
    }

    private func hasUsableInjectionTarget(_ element: AXUIElement) -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return false
        }
        return isAXEditable(element)
    }

    private func readableAXValue(from element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success else {
            return nil
        }
        if let string = valueRef as? String {
            return string
        }
        if let attributed = valueRef as? NSAttributedString {
            return attributed.string
        }
        return nil
    }

    private func readableAXSelectedText(from element: AXUIElement) -> String? {
        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef) == .success else {
            return nil
        }
        return selectedRef as? String
    }

    private func selectedTextRange(in element: AXUIElement) -> CFRange? {
        var rangeRef: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        guard rangeStatus == .success, let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else {
            return nil
        }
        let axRange = rangeRef as! AXValue
        var selected = CFRange()
        guard AXValueGetType(axRange) == .cfRange, AXValueGetValue(axRange, .cfRange, &selected) else {
            return nil
        }
        return selected
    }

    private func waitForPasteInsertion(of text: String, target: AXUIElement, baselineValue: String?) -> Bool {
        for _ in 0..<10 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.04))
            let candidateTarget = focusedElement() ?? target
            let newValue = readableAXValue(from: candidateTarget)
            if let baselineValue, let newValue, newValue != baselineValue, newValue.contains(text) {
                return true
            }
            if baselineValue == nil, let newValue, newValue.contains(text) {
                return true
            }
        }
        return false
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
            let msg = "热键已识别，但未授权语音识别。请在 系统设置 > 隐私与安全性 > 语音识别 中允许 VoiceInput，并重启应用后重试。"
            reportError(.permission, message: msg)
            RealtimeSessionStore.shared.setStage(.permissionBlocked, text: msg)
            openSystemPrivacySettings(anchor: "Privacy_SpeechRecognition")
            return false
        }

        let micGranted = await ensureMicrophonePermission()
        guard micGranted else {
            let msg = "热键已识别，但未授权麦克风。请在 系统设置 > 隐私与安全性 > 麦克风 中允许 VoiceInput，并重启应用后重试。"
            reportError(.permission, message: msg)
            RealtimeSessionStore.shared.setStage(.permissionBlocked, text: msg)
            openSystemPrivacySettings(anchor: "Privacy_Microphone")
            return false
        }

        let axGranted = await ensureAccessibilityPermission()
        guard axGranted else {
            let msg = "热键已识别，但未授权辅助功能。请在 系统设置 > 隐私与安全性 > 辅助功能 中允许 VoiceInput，并重启应用后重试。"
            reportError(.permission, message: msg)
            RealtimeSessionStore.shared.setStage(.permissionBlocked, text: msg)
            openSystemPrivacySettings(anchor: "Privacy_Accessibility")
            return false
        }
        return true
    }

    private func ensureSpeechPermission() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        logger.notice("Speech permission status=\(status.rawValue, privacy: .public)")
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
        logger.notice("Microphone permission status=\(status.rawValue, privacy: .public)")
        if status == .authorized { return true }
        if status == .denied || status == .restricted { return false }
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func ensureAccessibilityPermission() async -> Bool {
        let initialTrust = AccessibilityTrust.isTrusted(prompt: false)
        logger.notice("Accessibility permission initialTrust=\(initialTrust, privacy: .public)")
        if initialTrust { return true }

        // Ask the system prompt once per launch; repeated prompting can cause TCC churn.
        if !didPromptAccessibilityThisLaunch {
            _ = AccessibilityTrust.isTrusted(prompt: true)
            didPromptAccessibilityThisLaunch = true
        }

        // Wait for user to toggle the switch in System Settings.
        for _ in 0..<24 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if AccessibilityTrust.isTrusted(prompt: false) { return true }
        }
        let finalTrust = AccessibilityTrust.isTrusted(prompt: false)
        logger.notice("Accessibility permission finalTrust=\(finalTrust, privacy: .public)")
        return finalTrust
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
        RuntimeDiagnosticsStore.record("voice-input", "\(prefix)：\(message)")
        let stageText: String
        switch kind {
        case .permission, .startup, .recognition:
            stageText = "热键已识别，但\(prefix)：\(message)"
        case .rewrite, .injection:
            stageText = "\(prefix)：\(message)"
        }
        RealtimeSessionStore.shared.setStage(.failed, text: stageText)
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
