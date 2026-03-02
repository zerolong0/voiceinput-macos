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

    // MARK: - Properties

    /// Whether voice input is currently active
    private var isVoiceInputActive = false

    /// The candidate window for displaying results
    private var candidateWindow: IMKCandidates?

    /// Current recognized text
    private var currentText: String = ""

    /// Global hotkey reference
    private var hotkeyRef: EventHotKeyRef?

    // MARK: - Initialization

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        setupCandidateWindow()
        setupGlobalHotkey()
    }

    deinit {
        unregisterGlobalHotkey()
    }

    // MARK: - Setup

    /// Initialize the candidate window
    private func setupCandidateWindow() {
        guard let server = self.server() else { return }
        candidateWindow = IMKCandidates(server: server, panelType: kIMKSingleColumnScrollingCandidatePanel)
        candidateWindow?.setPanelType(kIMKSingleColumnScrollingCandidatePanel)
    }

    /// Register global hotkey (Option + Space)
    private func setupGlobalHotkey() {
        // Register for Option+Space hotkey
        // Using Carbon API for global hotkey registration
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x564F4943) // "VOIC"
        hotKeyID.id = 1

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)

        // Install event handler
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let controller = Unmanaged<VoiceInputController>.fromOpaque(userData).takeUnretainedValue()
                controller.handleHotkey()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )

        // Register the hotkey: Option (kOptionKey) + Space (0x31)
        let modifiers: UInt32 = UInt32(optionKey)
        let keyCode: UInt32 = 0x31 // Space key

        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
    }

    /// Unregister global hotkey
    private func unregisterGlobalHotkey() {
        if let hotkeyRef = hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
    }

    /// Handle hotkey activation
    private func handleHotkey() {
        toggleVoiceInput()
    }

    /// Toggle voice input on/off
    private func toggleVoiceInput() {
        isVoiceInputActive.toggle()

        if isVoiceInputActive {
            activateVoiceInput()
        } else {
            deactivateVoiceInput()
        }
    }

    /// Activate voice input mode
    private func activateVoiceInput() {
        // Notify user that voice input is active
        NSLog("VoiceInput: Activated")

        // Show visual indicator - use candidates method
        candidateWindow?.update()
        candidateWindow?.show()
    }

    /// Deactivate voice input mode
    private func deactivateVoiceInput() {
        NSLog("VoiceInput: Deactivated")

        // Hide candidate window
        candidateWindow?.hide()

        // If there's recognized text, insert it
        if !currentText.isEmpty {
            insertText(currentText)
        }

        // Reset state
        currentText = ""
        isVoiceInputActive = false
    }

    // MARK: - IMKInputController Overrides

    /// Called when the input method is activated
    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        NSLog("VoiceInput: Server activated")
    }

    /// Called when the input method is deactivated
    override func deactivateServer(_ sender: Any!) {
        super.deactivateServer(sender)
        NSLog("VoiceInput: Server deactivated")

        // Clean up
        candidateWindow?.hide()
        isVoiceInputActive = false
    }

    /// Handle input events
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }

        // Handle key events
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
                isVoiceInputActive = false
                currentText = ""
                candidateWindow?.hide()
                return true
            }
        }

        // Enter to confirm input
        if keyCode == 36 { // Return key
            if isVoiceInputActive && !currentText.isEmpty {
                insertText(currentText)
                currentText = ""
                isVoiceInputActive = false
                candidateWindow?.hide()
                return true
            }
        }

        // Space to complete current input in non-voice mode
        if keyCode == 49 && !isVoiceInputActive { // Space key
            // Insert space if we have text
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

        // About item
        let aboutItem = NSMenuItem(title: "About VoiceInput", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // Preferences item
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(showPrefs), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        return menu
    }

    // MARK: - Text Insertion

    /// Insert text into the client application
    private func insertText(_ text: String) {
        guard let client = self.client() as? IMKTextInput else { return }
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
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
        // Preferences would be implemented here
        NSLog("VoiceInput: Preferences requested")
    }
}
