//
//  VoiceInputController.swift
//  VoiceInput
//
//  Main input controller for VoiceInput method
//

import Cocoa
import InputMethodKit
import Carbon

/// Main input controller class for VoiceInput
/// Handles text input and provides voice input functionality
@objc(VoiceInputController)
class VoiceInputController: IMKInputController {
    private static var globalHotkeyRef: EventHotKeyRef?
    private static var globalHandlerInstalled = false
    private static weak var activeController: VoiceInputController?

    // MARK: - Properties

    /// Whether voice input is currently active
    private var isVoiceInputActive = false
    private var isHotkeyCurrentlyDown = false
    private var didAttemptRecognitionRecovery = false
    private var hotkeyPressBeganAt: TimeInterval = 0
    private var stopHandledOnPress = false
    private var holdToStopThreshold: TimeInterval {
        let value = SharedSettings.defaults.double(forKey: SharedSettings.Keys.hotkeyHoldToStopThreshold)
        return min(1.2, max(0.15, value > 0 ? value : 0.35))
    }

    /// The candidate window for displaying results
    private var candidateWindow: IMKCandidates?

    /// Current recognized text
    private var currentText: String = ""

    /// Speech and post-processing pipeline
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

    // MARK: - Initialization

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        Self.activeController = self
        SharedSettings.bootstrapDefaults()
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
        setupCandidateWindow()
        setupGlobalHotkey()
    }

    deinit {
        whisperEngine.stop()
        DistributedNotificationCenter.default().removeObserver(self)
        if Self.activeController === self {
            Self.activeController = nil
        }
    }

    // MARK: - Setup

    /// Initialize the candidate window
    private func setupCandidateWindow() {
        guard let server = self.server() else { return }
        candidateWindow = IMKCandidates(server: server, panelType: kIMKSingleColumnScrollingCandidatePanel)
        candidateWindow?.setPanelType(kIMKSingleColumnScrollingCandidatePanel)
    }

    /// Register global hotkey (configured from shared settings)
    private func setupGlobalHotkey() {
        unregisterGlobalHotkey()

        if !Self.globalHandlerInstalled {
            installHotkeyHandler()
            Self.globalHandlerInstalled = true
        }

        let defaults = SharedSettings.defaults
        let imHotkeyEnabled = defaults.object(forKey: SharedSettings.Keys.imHotkeyEnabled) as? Bool ?? false
        guard imHotkeyEnabled else { return }
        let hotkeyEnabled = defaults.object(forKey: SharedSettings.Keys.hotkeyEnabled) as? Bool ?? true
        guard hotkeyEnabled else {
            updateHotkeyRuntimeStatus("已关闭")
            return
        }

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x564F4943) // "VOIC"
        hotKeyID.id = 1

        let rawModifiers = defaults.object(forKey: SharedSettings.Keys.hotkeyModifiers) as? Int ?? OptionSetFlag.optionSpaceModifiers.rawValue
        let rawKeyCode = defaults.object(forKey: SharedSettings.Keys.hotkeyKeyCode) as? Int ?? OptionSetFlag.spaceKeyCode.rawValue
        let validation = HotkeyConfig.validate(modifiers: rawModifiers, keyCode: rawKeyCode)
        let useFallback = !validation.isValid
        let modifiers = UInt32(useFallback ? OptionSetFlag.optionSpaceModifiers.rawValue : rawModifiers)
        let keyCode = UInt32(useFallback ? OptionSetFlag.spaceKeyCode.rawValue : rawKeyCode)

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &Self.globalHotkeyRef
        )
        if status != noErr {
            NSLog("VoiceInput: Hotkey register failed status=\(status), fallback to Option+Space")
            var fallbackRef: EventHotKeyRef?
            let fallbackStatus = RegisterEventHotKey(
                UInt32(OptionSetFlag.spaceKeyCode.rawValue),
                UInt32(OptionSetFlag.optionSpaceModifiers.rawValue),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &fallbackRef
            )
            if fallbackStatus == noErr {
                Self.globalHotkeyRef = fallbackRef
                updateHotkeyRuntimeStatus("回退注册成功: Option + Space")
            } else {
                NSLog("VoiceInput: Fallback hotkey register also failed status=\(fallbackStatus)")
                updateHotkeyRuntimeStatus("注册失败: status=\(status), fallback=\(fallbackStatus)")
            }
        } else {
            NSLog("VoiceInput: Hotkey registered modifiers=\(modifiers) keyCode=\(keyCode)")
            updateHotkeyRuntimeStatus("已注册: \(formattedHotkey(modifiers: Int(modifiers), keyCode: Int(keyCode)))")
        }
    }

    private func formattedHotkey(modifiers: Int, keyCode: Int) -> String {
        if modifiers == 0 {
            return HotkeyConfig.keyTitle(for: keyCode)
        }
        return "\(HotkeyConfig.modifierTitle(for: modifiers)) + \(HotkeyConfig.keyTitle(for: keyCode))"
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
                if kind == UInt32(kEventHotKeyPressed) {
                    VoiceInputController.activeController?.handleHotkeyPressed()
                } else if kind == UInt32(kEventHotKeyReleased) {
                    VoiceInputController.activeController?.handleHotkeyReleased()
                }
                return noErr
            },
            Int(eventTypes.count),
            &eventTypes,
            nil,
            nil
        )
    }

    @objc private func reloadHotkeyConfiguration() {
        setupGlobalHotkey()
    }

    /// Unregister global hotkey
    private func unregisterGlobalHotkey() {
        if let hotkeyRef = Self.globalHotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            Self.globalHotkeyRef = nil
        }
    }

    private func updateHotkeyRuntimeStatus(_ status: String) {
        let defaults = SharedSettings.defaults
        defaults.set(status, forKey: SharedSettings.Keys.hotkeyRuntimeStatus)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(SharedNotifications.hotkeyChanged),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    /// Handle hotkey press
    private func handleHotkeyPressed() {
        if isHotkeyCurrentlyDown {
            return
        }
        isHotkeyCurrentlyDown = true
        hotkeyPressBeganAt = Date().timeIntervalSince1970
        stopHandledOnPress = false

        // Hold-to-talk model: key down starts recording, repeat keyDown while holding is ignored.
        if isVoiceInputActive {
            return
        }
        activateVoiceInput()
    }

    /// Handle hotkey release
    private func handleHotkeyReleased() {
        guard isHotkeyCurrentlyDown else { return }
        isHotkeyCurrentlyDown = false
        defer { stopHandledOnPress = false }
        // Hold-to-talk model: key up always ends recording if active.
        if isVoiceInputActive && !stopHandledOnPress {
            deactivateVoiceInput()
        }
    }

    /// Activate voice input mode
    private func activateVoiceInput() {
        NSLog("VoiceInput: Activated")
        isVoiceInputActive = true
        didAttemptRecognitionRecovery = false
        currentText = ""
        pendingCopyContext = nil
        statusPanel.showListening(text: "")

        do {
            try whisperEngine.start()
        } catch {
            NSLog("VoiceInput: start recognition failed: \(error.localizedDescription)")
            isVoiceInputActive = false
            statusPanel.showError("启动失败：\(error.localizedDescription)")
            return
        }

        candidateWindow?.update()
        candidateWindow?.show()
    }

    /// Deactivate voice input mode
    private func deactivateVoiceInput() {
        NSLog("VoiceInput: Deactivated")

        whisperEngine.stop()
        candidateWindow?.hide()

        let capturedText = currentText
        currentText = ""
        didAttemptRecognitionRecovery = false
        isVoiceInputActive = false

        guard !capturedText.isEmpty else { return }

        // Always run local pipeline first so we have deterministic fallback.
        let localProcessed = textProcessor.process(capturedText)
        statusPanel.showThinking(text: localProcessed)

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
        if insertText(finalText) {
            statusPanel.hide()
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
            pendingCopyContext = nil
            return
        }

        pendingCopyContext = PendingCopyContext(
            originalText: originalText,
            processedText: processedText,
            finalText: finalText,
            style: style
        )
        statusPanel.update(
            status: "未检测到输入焦点。请点击“复制内容”后手动粘贴，避免消息丢失。",
            text: finalText,
            showCopy: true
        )
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

    // MARK: - IMKInputController Overrides

    /// Called when the input method is activated
    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        NSLog("VoiceInput: Server activated")
        Self.activeController = self
        setupGlobalHotkey()
    }

    /// Called when the input method is deactivated
    override func deactivateServer(_ sender: Any!) {
        super.deactivateServer(sender)
        NSLog("VoiceInput: Server deactivated")

        candidateWindow?.hide()
        statusPanel.hide()
        isVoiceInputActive = false
        whisperEngine.stop()
    }

    /// Handle input events
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }

        if event.type == .keyDown {
            return handleKeyDown(event, client: sender)
        }

        return false
    }

    /// Handle key down events
    private func handleKeyDown(_ event: NSEvent, client sender: Any?) -> Bool {
        let keyCode = event.keyCode

        // Escape to cancel voice input
        if keyCode == 53 { // Escape key
            if isVoiceInputActive {
                whisperEngine.stop()
                currentText = ""
                isVoiceInputActive = false
                candidateWindow?.hide()
                statusPanel.hide()
                return true
            }
        }

        // Enter to confirm input
        if keyCode == 36 { // Return key
            if isVoiceInputActive && !currentText.isEmpty {
                deactivateVoiceInput()
                return true
            }
        }

        // Space to complete current input in non-voice mode
        if keyCode == 49 && !isVoiceInputActive { // Space key
            if let client = sender as? IMKTextInput {
                client.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
                return true
            }
        }

        return false
    }

    /// Provide a menu for the input method
    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "VoiceInput")

        let aboutItem = NSMenuItem(title: "About VoiceInput", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(showPrefs), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        return menu
    }

    // MARK: - Text Insertion

    /// Insert text — try IMK client first, then AX API fallback
    private func insertText(_ text: String) -> Bool {
        // Primary: IMK client (synchronous / same app)
        if let client = self.client() as? IMKTextInput {
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            return true
        }
        // Fallback: AX API (works after async LLM delay)
        return insertTextViaAXFallback(text)
    }

    private func insertTextViaAXFallback(_ text: String) -> Bool {
        guard AccessibilityTrust.isTrusted(prompt: false) else { return false }
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let element = focused as! AXUIElement

        // Try direct AX value set on editable element
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String,
           ["AXTextField", "AXTextArea", "AXSearchField"].contains(role) {
            var valueRef: CFTypeRef?
            var rangeRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let current = valueRef as? String,
               AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
               let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() {
                let axRange = rangeRef as! AXValue
                var sel = CFRange()
                if AXValueGetType(axRange) == .cfRange, AXValueGetValue(axRange, .cfRange, &sel) {
                    let ns = current as NSString
                    let loc = max(0, min(sel.location, ns.length))
                    let len = max(0, min(sel.length, ns.length - loc))
                    let merged = ns.replacingCharacters(in: NSRange(location: loc, length: len), with: text)
                    if AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, merged as CFTypeRef) == .success {
                        var caret = CFRange(location: loc + (text as NSString).length, length: 0)
                        if let axCaret = AXValueCreate(.cfRange, &caret) {
                            _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axCaret)
                        }
                        return true
                    }
                }
            }
        }

        // Last resort: Cmd+V via CGEvent
        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let src = CGEventSource(stateID: .privateState)
        let events: [(CGKeyCode, Bool)] = [(0x37, true), (0x09, true), (0x09, false), (0x37, false)]
        for (key, down) in events {
            let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
            if key == 0x09 { e?.flags = .maskCommand }
            e?.post(tap: .cghidEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pasteboard.clearContents()
            if let original { pasteboard.setString(original, forType: .string) }
        }
        return true
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

    // MARK: - Menu Actions

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "VoiceInput"
        alert.informativeText = "Version 1.0\n\nA voice input method for macOS.\n\nPress Option+Space to start voice input."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func showPrefs() {
        NSLog("VoiceInput: Preferences requested")
    }
}

extension VoiceInputController: WhisperEngineDelegate {
    func whisperEngineDidStart(_ engine: WhisperEngine) {
        NSLog("VoiceInput: Recognition started")
    }

    func whisperEngineDidStop(_ engine: WhisperEngine) {
        NSLog("VoiceInput: Recognition stopped")
    }

    func whisperEngine(_ engine: WhisperEngine, didTranscribe result: TranscriptionResult) {
        currentText = result.text
    }

    func whisperEngine(_ engine: WhisperEngine, didUpdatePartialResult text: String) {
        currentText = text
        statusPanel.showListening(text: text)
    }

    func whisperEngine(_ engine: WhisperEngine, didFailWithError error: WhisperError) {
        NSLog("VoiceInput: Recognition error: \(error.localizedDescription)")
        if !didAttemptRecognitionRecovery && isVoiceInputActive {
            didAttemptRecognitionRecovery = true
            let preservedText = currentText
            do {
                try whisperEngine.start()
                currentText = preservedText
                statusPanel.showListening(text: preservedText)
                return
            } catch {
                isVoiceInputActive = false
                candidateWindow?.hide()
                statusPanel.showError("识别失败：自动恢复失败：\(error.localizedDescription)")
                return
            }
        }
        isVoiceInputActive = false
        candidateWindow?.hide()
        statusPanel.showError("识别失败：\(error.localizedDescription)")
    }
}
