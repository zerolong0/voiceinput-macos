import Cocoa

enum TerminalPanelState {
    case idle
    case listening
    case recognizing(String)
    case confirming(RecognizedIntent)
    case executing(RecognizedIntent)
    case success(String)
    case error(String)
}

final class TerminalPanel {
    private let panel: NSPanel
    private let root = NSView()
    private let card = NSVisualEffectView()

    // Streaming log view
    private let logField: NSTextField = {
        let f = NSTextField(wrappingLabelWithString: "")
        f.translatesAutoresizingMaskIntoConstraints = false
        f.font = .systemFont(ofSize: 13, weight: .regular)
        f.textColor = .labelColor
        f.maximumNumberOfLines = 0
        f.lineBreakMode = .byWordWrapping
        f.isEditable = false
        f.isSelectable = false
        f.drawsBackground = false
        f.isBordered = false
        return f
    }()

    // Buttons
    private let buttonBar = NSStackView()
    private let confirmButton = NSButton(title: "确认 ↵", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)

    // Fallback selection buttons
    private let fallbackStack = NSStackView()
    private let fallbackCalendar = NSButton(title: "日历", target: nil, action: nil)
    private let fallbackNote = NSButton(title: "笔记", target: nil, action: nil)
    private let fallbackApp = NSButton(title: "打开App", target: nil, action: nil)
    private let fallbackCLI = NSButton(title: "命令", target: nil, action: nil)

    private var autoHideTimer: Timer?
    private(set) var currentState: TerminalPanelState = .idle

    var onConfirm: ((RecognizedIntent) -> Void)?
    var onCancel: (() -> Void)?
    var onFallbackSelect: ((IntentType, String) -> Void)?

    private var pendingIntent: RecognizedIntent?
    private var pendingText: String = ""
    private var localKeyMonitor: Any?

    private let panelWidth: CGFloat = 340

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 44),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        card.translatesAutoresizingMaskIntoConstraints = false
        card.material = .hudWindow
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor

        // Buttons
        for btn in [confirmButton, cancelButton] {
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.bezelStyle = .rounded
            btn.controlSize = .small
            btn.target = self
        }
        confirmButton.action = #selector(confirmAction)
        confirmButton.keyEquivalent = "\r"
        cancelButton.action = #selector(cancelAction)
        cancelButton.keyEquivalent = "\u{1b}"

        buttonBar.translatesAutoresizingMaskIntoConstraints = false
        buttonBar.orientation = .horizontal
        buttonBar.spacing = 8
        buttonBar.addArrangedSubview(NSView()) // spacer
        buttonBar.addArrangedSubview(confirmButton)
        buttonBar.addArrangedSubview(cancelButton)
        buttonBar.isHidden = true

        // Fallback buttons
        for btn in [fallbackCalendar, fallbackNote, fallbackApp, fallbackCLI] {
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.bezelStyle = .rounded
            btn.controlSize = .small
            btn.target = self
        }
        fallbackCalendar.action = #selector(fallbackCalendarAction)
        fallbackNote.action = #selector(fallbackNoteAction)
        fallbackApp.action = #selector(fallbackAppAction)
        fallbackCLI.action = #selector(fallbackCLIAction)

        fallbackStack.translatesAutoresizingMaskIntoConstraints = false
        fallbackStack.orientation = .horizontal
        fallbackStack.spacing = 6
        fallbackStack.addArrangedSubview(fallbackCalendar)
        fallbackStack.addArrangedSubview(fallbackNote)
        fallbackStack.addArrangedSubview(fallbackApp)
        fallbackStack.addArrangedSubview(fallbackCLI)
        fallbackStack.addArrangedSubview(cancelButton)
        fallbackStack.isHidden = true

        root.addSubview(card)
        card.addSubview(logField)
        card.addSubview(buttonBar)
        card.addSubview(fallbackStack)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: root.topAnchor),
            card.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            logField.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            logField.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            logField.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),

            buttonBar.topAnchor.constraint(equalTo: logField.bottomAnchor, constant: 8),
            buttonBar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            buttonBar.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),

            fallbackStack.topAnchor.constraint(equalTo: logField.bottomAnchor, constant: 8),
            fallbackStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            fallbackStack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -14),
        ])
    }

    // MARK: - Public API

    func setState(_ state: TerminalPanelState) {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        currentState = state

        switch state {
        case .listening:
            clearLog()
            appendLine("🎤  正在聆听...", color: .secondaryLabelColor)
            hideAllButtons()
            relayout()
            showPanel()
            playSound("Tink")
            installKeyMonitor()

        case .recognizing(let text):
            replaceLast("🎤  收到语音")
            appendLine("📝  「\(truncate(text, 60))」", color: .labelColor)
            appendLine("🔍  正在分析意图...", color: .secondaryLabelColor)
            hideAllButtons()
            relayout()

        case .confirming(let intent):
            pendingIntent = intent
            replaceLast(confirmLine(for: intent))
            buttonBar.isHidden = false
            fallbackStack.isHidden = true
            relayout()
            playSound("Pop")
            installKeyMonitor()

        case .executing(let intent):
            hideAllButtons()
            appendLine("⚡  \(executingLine(for: intent))", color: .controlAccentColor)
            relayout()
            removeKeyMonitor()

        case .success(let msg):
            appendLine("✅  \(msg)", color: .systemGreen)
            hideAllButtons()
            relayout()
            removeKeyMonitor()
            playSound("Glass")
            autoHideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.hide()
            }

        case .error(let msg):
            appendLine("❌  \(msg)", color: .systemRed)
            // Show only cancel
            buttonBar.isHidden = true
            fallbackStack.isHidden = true
            relayout()
            installKeyMonitor()
            playSound("Basso")
            autoHideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                self?.hide()
            }

        case .idle:
            hide()
        }
    }

    func showFallbackSelect(text: String) {
        pendingText = text
        replaceLast("❓  未识别命令，请选择操作类型:")
        buttonBar.isHidden = true
        fallbackStack.isHidden = false
        relayout()
        playSound("Morse")
        installKeyMonitor()
    }

    func hide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    // MARK: - Log management

    private var logLines: [(String, NSColor)] = []

    private func clearLog() {
        logLines.removeAll()
        logField.attributedStringValue = NSAttributedString()
    }

    private func appendLine(_ text: String, color: NSColor = .labelColor) {
        logLines.append((text, color))
        rebuildLogDisplay()
    }

    private func replaceLast(_ text: String, color: NSColor = .labelColor) {
        if !logLines.isEmpty {
            logLines[logLines.count - 1] = (text, color)
        } else {
            logLines.append((text, color))
        }
        rebuildLogDisplay()
    }

    private func rebuildLogDisplay() {
        let result = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4

        for (index, (text, color)) in logLines.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
            result.append(NSAttributedString(string: text, attributes: attrs))
        }
        logField.attributedStringValue = result
    }

    // MARK: - Layout

    private func relayout() {
        let textMaxWidth = panelWidth - 28 // 14 padding each side
        let textHeight = logField.attributedStringValue.boundingRect(
            with: NSSize(width: textMaxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height

        let buttonsHeight: CGFloat
        if !buttonBar.isHidden || !fallbackStack.isHidden {
            buttonsHeight = 8 + 24 // gap + button height
        } else {
            buttonsHeight = 0
        }

        let totalHeight = ceil(10 + textHeight + buttonsHeight + 12) // top + text + buttons + bottom
        let clamped = max(40, min(220, totalHeight))

        var frame = panel.frame
        let oldHeight = frame.size.height
        frame.size = NSSize(width: panelWidth, height: clamped)
        // Adjust origin so panel grows upward from bottom
        frame.origin.y += oldHeight - clamped
        panel.setFrame(frame, display: true)
    }

    private func showPanel() {
        if !panel.isVisible {
            positionBottomCenter()
            panel.orderFrontRegardless()
        }
    }

    private func positionBottomCenter() {
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        guard let screen = targetScreen else { return }
        let visible = screen.visibleFrame
        var frame = panel.frame
        frame.origin.x = visible.midX - frame.size.width / 2
        frame.origin.y = visible.minY + 108
        panel.setFrame(frame, display: true)
    }

    private func hideAllButtons() {
        buttonBar.isHidden = true
        fallbackStack.isHidden = true
    }

    // MARK: - Text helpers

    private func confirmLine(for intent: RecognizedIntent) -> String {
        let icon: String
        switch intent.type {
        case .addCalendar: icon = "📅"
        case .createNote: icon = "📝"
        case .openApp: icon = "🚀"
        case .runCommand: icon = "💻"
        case .unrecognized: icon = "❓"
        }
        return "\(icon)  \(intent.displaySummary)"
    }

    private func executingLine(for intent: RecognizedIntent) -> String {
        switch intent.type {
        case .addCalendar: return "正在添加日历事件..."
        case .createNote: return "正在创建笔记..."
        case .openApp: return "正在打开 \(intent.title)..."
        case .runCommand: return "正在执行命令..."
        case .unrecognized: return "正在处理..."
        }
    }

    private func truncate(_ text: String, _ maxLength: Int) -> String {
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength)) + "..."
    }

    // MARK: - Sound feedback

    private func playSound(_ name: String) {
        let enabled = SharedSettings.defaults.object(forKey: SharedSettings.Keys.interactionSoundEnabled) as? Bool ?? true
        guard enabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    // MARK: - Actions

    @objc private func confirmAction() {
        guard let intent = pendingIntent else { return }
        onConfirm?(intent)
    }

    @objc private func cancelAction() {
        onCancel?()
        hide()
    }

    @objc private func fallbackCalendarAction() {
        onFallbackSelect?(.addCalendar, pendingText)
        hide()
    }

    @objc private func fallbackNoteAction() {
        onFallbackSelect?(.createNote, pendingText)
        hide()
    }

    @objc private func fallbackAppAction() {
        onFallbackSelect?(.openApp, pendingText)
        hide()
    }

    @objc private func fallbackCLIAction() {
        onFallbackSelect?(.runCommand, pendingText)
        hide()
    }

    // MARK: - Key monitoring

    private func installKeyMonitor() {
        removeKeyMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape
                self.cancelAction()
                return nil
            }
            if event.keyCode == 36 { // Return
                if let intent = self.pendingIntent, !self.buttonBar.isHidden {
                    self.onConfirm?(intent)
                    return nil
                }
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }
}
