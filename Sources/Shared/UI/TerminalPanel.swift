import Cocoa

enum TerminalPanelState {
    case idle
    case listening
    case recognizing(String)
    case autoExecuting(RecognizedIntent)
    case confirming(RecognizedIntent)
    case voiceConfirming(RecognizedIntent, String)
    case executing(RecognizedIntent)
    case success(String)
    case error(String)
    case richContent(AgentResponse)
}

final class TerminalPanel {
    private let panel: NSPanel
    private let root = NSView()
    private let card = NSVisualEffectView()

    // Pill HUD elements
    private let iconView = NSImageView()
    private let waveView = NSView()
    private var waveBars: [CALayer] = []
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    // Rich content
    private let richScrollView = NSScrollView()
    private let richContainer = NSStackView()
    private let richBodyLabel = NSTextField(labelWithString: "")
    private let richKeyValueStack = NSStackView()
    private let richCloseButton = NSButton(title: "✕", target: nil, action: nil)
    private let richContinueButton = NSButton(title: "继续说", target: nil, action: nil)
    private let richCopyButton = NSButton(title: "复制", target: nil, action: nil)
    private let richActionBar = NSStackView()
    private var richHideTimer: Timer?
    private var richBody: String = ""
    private var richActions: [AgentAction] = []
    private var dynamicActionButtons: [NSButton] = []

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
    private let fallbackSystem = NSButton(title: "系统控制", target: nil, action: nil)
    private let fallbackSearch = NSButton(title: "搜索", target: nil, action: nil)

    private var autoHideTimer: Timer?
    private(set) var currentState: TerminalPanelState = .idle
    private var latestTranscript: String = ""

    var onConfirm: ((RecognizedIntent) -> Void)?
    var onCancel: (() -> Void)?
    var onFallbackSelect: ((IntentType, String) -> Void)?
    var onContinue: (() -> Void)?

    private var pendingIntent: RecognizedIntent?
    private var pendingText: String = ""
    private var localKeyMonitor: Any?

    private var heightConstraint: NSLayoutConstraint?
    private var titleCenterYConstraint: NSLayoutConstraint?
    private var titleTopConstraint: NSLayoutConstraint?
    private var iconCenterYConstraint: NSLayoutConstraint?
    private var iconTopConstraint: NSLayoutConstraint?

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
        card.layer?.cornerRadius = 22
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor

        // Icon
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .labelColor

        // Wave
        waveView.translatesAutoresizingMaskIntoConstraints = false
        waveView.wantsLayer = true
        waveView.isHidden = true
        configureWaveBars()

        // Title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        // Subtitle
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.isHidden = true

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
        for btn in [fallbackCalendar, fallbackNote, fallbackApp, fallbackCLI, fallbackSystem, fallbackSearch] {
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.bezelStyle = .rounded
            btn.controlSize = .small
            btn.target = self
        }
        fallbackCalendar.action = #selector(fallbackCalendarAction)
        fallbackNote.action = #selector(fallbackNoteAction)
        fallbackApp.action = #selector(fallbackAppAction)
        fallbackCLI.action = #selector(fallbackCLIAction)
        fallbackSystem.action = #selector(fallbackSystemAction)
        fallbackSearch.action = #selector(fallbackSearchAction)

        fallbackStack.translatesAutoresizingMaskIntoConstraints = false
        fallbackStack.orientation = .horizontal
        fallbackStack.spacing = 6
        fallbackStack.addArrangedSubview(fallbackCalendar)
        fallbackStack.addArrangedSubview(fallbackNote)
        fallbackStack.addArrangedSubview(fallbackApp)
        fallbackStack.addArrangedSubview(fallbackCLI)
        fallbackStack.addArrangedSubview(fallbackSystem)
        fallbackStack.addArrangedSubview(fallbackSearch)
        fallbackStack.addArrangedSubview(cancelButton)
        fallbackStack.isHidden = true

        // Rich content scroll view
        richBodyLabel.translatesAutoresizingMaskIntoConstraints = false
        richBodyLabel.font = .systemFont(ofSize: 13, weight: .regular)
        richBodyLabel.textColor = .labelColor
        richBodyLabel.maximumNumberOfLines = 0
        richBodyLabel.lineBreakMode = .byWordWrapping
        richBodyLabel.isSelectable = true

        richKeyValueStack.translatesAutoresizingMaskIntoConstraints = false
        richKeyValueStack.orientation = .vertical
        richKeyValueStack.alignment = .leading
        richKeyValueStack.spacing = 8
        richKeyValueStack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        richKeyValueStack.isHidden = true

        richContainer.translatesAutoresizingMaskIntoConstraints = false
        richContainer.orientation = .vertical
        richContainer.alignment = .leading
        richContainer.spacing = 10
        richContainer.addArrangedSubview(richBodyLabel)
        richContainer.addArrangedSubview(richKeyValueStack)

        richScrollView.translatesAutoresizingMaskIntoConstraints = false
        richScrollView.hasVerticalScroller = true
        richScrollView.hasHorizontalScroller = false
        richScrollView.autohidesScrollers = true
        richScrollView.borderType = .noBorder
        richScrollView.backgroundColor = .clear
        richScrollView.drawsBackground = false
        richScrollView.isHidden = true

        let clipView = richScrollView.contentView
        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        richScrollView.documentView = documentView
        documentView.addSubview(richContainer)

        NSLayoutConstraint.activate([
            richContainer.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 4),
            richContainer.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            richContainer.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            richContainer.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -4),
            richBodyLabel.widthAnchor.constraint(equalTo: richContainer.widthAnchor),
            richKeyValueStack.widthAnchor.constraint(equalTo: richContainer.widthAnchor),
            documentView.widthAnchor.constraint(equalTo: clipView.widthAnchor),
        ])

        richCloseButton.translatesAutoresizingMaskIntoConstraints = false
        richCloseButton.bezelStyle = .rounded
        richCloseButton.controlSize = .mini
        richCloseButton.font = .systemFont(ofSize: 11)
        richCloseButton.target = self
        richCloseButton.action = #selector(richCloseAction)
        richCloseButton.isHidden = true

        richContinueButton.translatesAutoresizingMaskIntoConstraints = false
        richContinueButton.bezelStyle = .rounded
        richContinueButton.controlSize = .mini
        richContinueButton.font = .systemFont(ofSize: 11)
        richContinueButton.target = self
        richContinueButton.action = #selector(richContinueAction)
        richContinueButton.isHidden = true

        richCopyButton.translatesAutoresizingMaskIntoConstraints = false
        richCopyButton.bezelStyle = .rounded
        richCopyButton.controlSize = .mini
        richCopyButton.font = .systemFont(ofSize: 11)
        richCopyButton.target = self
        richCopyButton.action = #selector(richCopyAction)
        richCopyButton.isHidden = true

        richActionBar.translatesAutoresizingMaskIntoConstraints = false
        richActionBar.orientation = .horizontal
        richActionBar.spacing = 6
        richActionBar.addArrangedSubview(NSView()) // spacer
        richActionBar.addArrangedSubview(richContinueButton)
        richActionBar.addArrangedSubview(richCopyButton)
        richActionBar.addArrangedSubview(richCloseButton)
        richActionBar.isHidden = true

        root.addSubview(card)
        card.addSubview(iconView)
        card.addSubview(waveView)
        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)
        card.addSubview(buttonBar)
        card.addSubview(fallbackStack)
        card.addSubview(richScrollView)
        card.addSubview(richActionBar)

        heightConstraint = card.heightAnchor.constraint(equalToConstant: 44)
        titleCenterYConstraint = titleLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        titleTopConstraint = titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12)
        titleTopConstraint?.isActive = false
        titleCenterYConstraint?.isActive = true
        iconCenterYConstraint = iconView.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        iconTopConstraint = iconView.topAnchor.constraint(equalTo: card.topAnchor, constant: 14)
        iconTopConstraint?.isActive = false
        iconCenterYConstraint?.isActive = true

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: root.topAnchor),
            card.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            heightConstraint!,

            iconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 11),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            waveView.leadingAnchor.constraint(equalTo: iconView.leadingAnchor),
            waveView.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            waveView.widthAnchor.constraint(equalToConstant: 16),
            waveView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -12),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

            buttonBar.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 6),
            buttonBar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            buttonBar.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),

            fallbackStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 6),
            fallbackStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            fallbackStack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -14),

            richScrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            richScrollView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            richScrollView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            richScrollView.bottomAnchor.constraint(equalTo: richActionBar.topAnchor, constant: -6),

            richActionBar.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            richActionBar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            richActionBar.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            richActionBar.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    // MARK: - Public API

    func setState(_ state: TerminalPanelState) {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        currentState = state

        switch state {
        case .listening:
            applyCompactLayout()
            startWaveAnimation()
            iconView.isHidden = true
            latestTranscript = ""
            titleLabel.stringValue = "请开始说话"
            titleLabel.textColor = .labelColor
            hideAllButtons()
            relayout(width: calculatedWidth(for: "请开始说话"), height: 44)
            showPanel()
            playSound("Tink")
            installKeyMonitor()

        case .recognizing(let text):
            if !text.isEmpty {
                latestTranscript = text
            }
            let visibleTranscript = visibleTextForListening(text.isEmpty ? latestTranscript : text)
            applyExpandedLayout()
            stopWaveAnimation()
            iconView.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            iconView.contentTintColor = .controlAccentColor
            iconView.isHidden = false
            titleLabel.stringValue = "正在理解你的意图"
            titleLabel.textColor = .labelColor
            subtitleLabel.stringValue = visibleTranscript.isEmpty ? "正在分析你刚才说的话" : visibleTranscript
            subtitleLabel.isHidden = false
            hideAllButtons()
            relayout(width: 340, height: 88)
            showPanel()

        case .autoExecuting(let intent):
            pendingIntent = intent
            if intent.type.riskLevel == .low {
                applyExpandedLayout()
            } else {
                applyCompactLayout()
            }
            stopWaveAnimation()
            iconView.image = intentIcon(for: intent.type)
            iconView.contentTintColor = .controlAccentColor
            iconView.isHidden = false
            titleLabel.stringValue = previewTitle(for: intent)
            titleLabel.textColor = .labelColor
            let executionTranscript = visibleTextForListening(latestTranscript)
            if intent.type.riskLevel == .low {
                subtitleLabel.stringValue = executionTranscript.isEmpty ? "即将执行，按 Esc 或点取消可中止" : executionTranscript
                subtitleLabel.isHidden = false
                confirmButton.isHidden = true
                cancelButton.isHidden = false
                buttonBar.isHidden = false
                fallbackStack.isHidden = true
                richScrollView.isHidden = true
                richCopyButton.isHidden = true
                richCloseButton.isHidden = true
                richActionBar.isHidden = true
                relayout(width: 340, height: 92)
            } else {
                hideAllButtons()
                if executionTranscript.isEmpty {
                    relayout(width: calculatedWidth(for: titleLabel.stringValue), height: 44)
                } else {
                    applyExpandedLayout()
                    subtitleLabel.stringValue = executionTranscript
                    subtitleLabel.isHidden = false
                    relayout(width: 340, height: 88)
                }
            }
            showPanel()
            playSound("Pop")
            installKeyMonitor()

        case .confirming(let intent):
            pendingIntent = intent
            applyExpandedLayout()
            stopWaveAnimation()
            iconView.image = intentIcon(for: intent.type)
            iconView.contentTintColor = .controlAccentColor
            iconView.isHidden = false
            titleLabel.stringValue = previewTitle(for: intent)
            titleLabel.textColor = .labelColor
            let confirmTranscript = visibleTextForListening(latestTranscript)
            subtitleLabel.stringValue = confirmTranscript.isEmpty ? "确认后执行，按 Esc 取消" : confirmTranscript
            subtitleLabel.isHidden = false
            confirmButton.isHidden = false
            cancelButton.isHidden = false
            buttonBar.isHidden = false
            fallbackStack.isHidden = true
            relayout(width: 340, height: 92)
            showPanel()
            playSound("Pop")
            installKeyMonitor()

        case .voiceConfirming(let intent, let text):
            pendingIntent = intent
            applyExpandedLayout()
            startWaveAnimation()
            iconView.isHidden = true
            let visible = visibleTextForListening(text)
            latestTranscript = text
            titleLabel.stringValue = visible.isEmpty ? "请说“确认”或“取消”" : visible
            titleLabel.textColor = .labelColor
            subtitleLabel.stringValue = previewTitle(for: intent)
            subtitleLabel.isHidden = false
            confirmButton.isHidden = false
            cancelButton.isHidden = false
            buttonBar.isHidden = false
            fallbackStack.isHidden = true
            relayout(width: 340, height: 92)
            showPanel()

        case .executing(let intent):
            let executionTranscript = visibleTextForListening(latestTranscript)
            if executionTranscript.isEmpty {
                applyCompactLayout()
            } else {
                applyExpandedLayout()
            }
            stopWaveAnimation()
            iconView.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
            iconView.contentTintColor = .controlAccentColor
            iconView.isHidden = false
            titleLabel.stringValue = executingTitle(for: intent)
            titleLabel.textColor = .labelColor
            hideAllButtons()
            if executionTranscript.isEmpty {
                relayout(width: calculatedWidth(for: titleLabel.stringValue), height: 44)
            } else {
                subtitleLabel.stringValue = executionTranscript
                subtitleLabel.isHidden = false
                relayout(width: 340, height: 88)
            }
            removeKeyMonitor()
            showPanel()

        case .success(let msg):
            applyCompactLayout()
            stopWaveAnimation()
            iconView.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
            iconView.contentTintColor = .systemGreen
            iconView.isHidden = false
            titleLabel.stringValue = msg
            titleLabel.textColor = .labelColor
            hideAllButtons()
            relayout(width: calculatedWidth(for: msg), height: 44)
            removeKeyMonitor()
            showPanel()
            playSound("Glass")
            autoHideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.hide()
            }

        case .error(let msg):
            applyExpandedLayout()
            stopWaveAnimation()
            iconView.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
            iconView.contentTintColor = .systemRed
            iconView.isHidden = false
            let (title, body) = splitErrorMessage(msg)
            titleLabel.stringValue = title
            titleLabel.textColor = .labelColor
            subtitleLabel.stringValue = body
            subtitleLabel.isHidden = body.isEmpty
            hideAllButtons()
            relayout(width: 340, height: body.isEmpty ? 44 : 88)
            installKeyMonitor()
            showPanel()
            playSound("Basso")
            autoHideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                self?.hide()
            }

        case .richContent(let response):
            richBody = response.body
            richActions = response.actions
            applyExpandedLayout()
            stopWaveAnimation()
            iconView.image = richContentIcon(for: response.contentType)
            iconView.contentTintColor = .controlAccentColor
            iconView.isHidden = false
            titleLabel.stringValue = response.title
            titleLabel.textColor = .labelColor
            subtitleLabel.isHidden = true
            hideAllButtons()
            configureRichContent(response)
            richScrollView.isHidden = false
            richContinueButton.isHidden = false
            richCopyButton.isHidden = false
            richCloseButton.isHidden = false
            richActionBar.isHidden = false
            let panelWidth = richPanelWidth(for: response)
            let panelHeight = estimatedPanelHeight(for: response, width: panelWidth)
            relayout(width: panelWidth, height: panelHeight)
            showPanel()
            playSound("Glass")
            installKeyMonitor()
            startRichHideTimer()

        case .idle:
            hide()
        }
    }

    func updateListeningText(_ text: String) {
        guard case .listening = currentState else { return }
        latestTranscript = text
        let visible = visibleTextForListening(text)
        titleLabel.stringValue = visible.isEmpty ? "请开始说话" : visible
        relayout(width: calculatedWidth(for: titleLabel.stringValue), height: 44)
    }

    func showFallbackSelect(text: String) {
        pendingText = text
        pendingIntent = nil
        applyExpandedLayout()
        stopWaveAnimation()
        iconView.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.isHidden = false
        titleLabel.stringValue = "未识别命令，请选择操作类型"
        titleLabel.textColor = .labelColor
        subtitleLabel.stringValue = "我没听懂你要做什么，选一个最接近的操作"
        subtitleLabel.isHidden = false
        buttonBar.isHidden = true
        fallbackStack.isHidden = false
        relayout(width: 340, height: 96)
        playSound("Morse")
        installKeyMonitor()
        showPanel()
    }

    func hide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        richHideTimer?.invalidate()
        richHideTimer = nil
        latestTranscript = ""
        stopWaveAnimation()
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    // MARK: - Layout helpers

    private func applyCompactLayout() {
        titleTopConstraint?.isActive = false
        titleCenterYConstraint?.isActive = true
        iconTopConstraint?.isActive = false
        iconCenterYConstraint?.isActive = true
        subtitleLabel.isHidden = true
    }

    private func applyExpandedLayout() {
        titleCenterYConstraint?.isActive = false
        titleTopConstraint?.isActive = true
        iconCenterYConstraint?.isActive = false
        iconTopConstraint?.isActive = true
    }

    private func relayout(width: CGFloat, height: CGFloat) {
        heightConstraint?.constant = height
        var frame = panel.frame
        let oldHeight = frame.size.height
        frame.size = NSSize(width: width, height: height)
        frame.origin.y += oldHeight - height
        panel.setFrame(frame, display: true)
        positionBottomCenter()
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
        richScrollView.isHidden = true
        richContinueButton.isHidden = true
        richCopyButton.isHidden = true
        richCloseButton.isHidden = true
        richActionBar.isHidden = true
        clearDynamicActionButtons()
        richHideTimer?.invalidate()
        richHideTimer = nil
    }

    private func startRichHideTimer() {
        richHideTimer?.invalidate()
        richHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    private func estimatedBodyHeight(_ body: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let maxWidth: CGFloat = 340 - 28
        let boundingRect = (body as NSString).boundingRect(
            with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        return min(200, max(40, ceil(boundingRect.height)))
    }

    private func estimatedPanelHeight(for response: AgentResponse, width: CGFloat) -> CGFloat {
        let contentHeight: CGFloat
        switch response.contentType {
        case .keyValue:
            let rows = max(1, parseKeyValueLines(from: response.body).count)
            contentHeight = CGFloat(rows) * 38 + 10
        case .text, .markdown:
            contentHeight = estimatedBodyHeight(response.body, width: width)
        }
        return min(380, max(168, 44 + contentHeight + 46))
    }

    private func estimatedBodyHeight(_ body: String, width: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let maxWidth: CGFloat = width - 28
        let boundingRect = (body as NSString).boundingRect(
            with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        return min(220, max(44, ceil(boundingRect.height)))
    }

    private func richPanelWidth(for response: AgentResponse) -> CGFloat {
        switch response.contentType {
        case .keyValue:
            return 380
        case .markdown:
            return 400
        case .text:
            return 360
        }
    }

    // MARK: - Width calculation

    private func calculatedWidth(for text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let measured = (text.isEmpty ? " " : text as NSString).size(withAttributes: attrs).width
        let maxText = ("汉汉汉汉汉汉汉汉汉汉" as NSString).size(withAttributes: attrs).width
        let textWidth = min(measured, maxText)
        return max(112, min(300, ceil(11 + 16 + 9 + textWidth + 20)))
    }

    // MARK: - Text helpers

    private func visibleTextForListening(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let viewport = ("汉汉汉汉汉汉汉汉汉汉" as NSString).size(withAttributes: attrs).width
        var chars = Array(trimmed)
        while !chars.isEmpty {
            let candidate = String(chars.suffix(chars.count))
            let width = (candidate as NSString).size(withAttributes: attrs).width
            if width <= viewport { return candidate }
            chars.removeFirst()
        }
        return String(trimmed.suffix(1))
    }

    private func previewTitle(for intent: RecognizedIntent) -> String {
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

    private func executingTitle(for intent: RecognizedIntent) -> String {
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

    private func intentIcon(for type: IntentType) -> NSImage? {
        let name: String
        switch type {
        case .addCalendar: name = "calendar.badge.plus"
        case .createNote: name = "note.text.badge.plus"
        case .openApp: name = "arrow.up.forward.app"
        case .runCommand: name = "terminal"
        case .systemControl: name = "gearshape"
        case .webSearch: name = "magnifyingglass"
        case .weather: name = "cloud.sun"
        case .queryContact: name = "person.crop.circle"
        case .addReminder: name = "bell.badge"
        case .unrecognized: name = "questionmark.circle"
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func splitErrorMessage(_ msg: String) -> (String, String) {
        if msg.count <= 20 { return (msg, "") }
        if msg.contains("未授权") || msg.contains("权限") {
            return ("权限异常", msg)
        }
        if msg.contains("失败") {
            return ("操作失败", msg)
        }
        return ("出错了", msg)
    }

    private func richContentIcon(for type: AgentResponse.ContentType) -> NSImage? {
        let symbol: String
        switch type {
        case .text:
            symbol = "text.bubble"
        case .markdown:
            symbol = "doc.plaintext"
        case .keyValue:
            symbol = "list.bullet.rectangle.portrait"
        }
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    private func configureRichContent(_ response: AgentResponse) {
        clearDynamicActionButtons()

        switch response.contentType {
        case .text:
            richBodyLabel.stringValue = response.body
            richBodyLabel.isHidden = false
            richKeyValueStack.isHidden = true

        case .markdown:
            if let attributed = try? AttributedString(markdown: response.body) {
                richBodyLabel.attributedStringValue = NSAttributedString(attributed)
            } else {
                richBodyLabel.stringValue = response.body
            }
            richBodyLabel.isHidden = false
            richKeyValueStack.isHidden = true

        case .keyValue:
            richBodyLabel.attributedStringValue = attributedKeyValueBody(from: response.body)
            richBodyLabel.isHidden = false
            richKeyValueStack.isHidden = true
        }

        installDynamicActionButtons(response.actions)
    }

    private func attributedKeyValueBody(from body: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 8

        let keyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]

        let pairs = parseKeyValueLines(from: body)
        for (index, pair) in pairs.enumerated() {
            result.append(NSAttributedString(string: "\(pair.0)\n", attributes: keyAttrs))
            result.append(NSAttributedString(string: pair.1, attributes: valueAttrs))
            if index < pairs.count - 1 {
                result.append(NSAttributedString(string: "\n\n"))
            }
        }
        return result
    }

    private func rebuildKeyValueRows(from body: String) {
        richKeyValueStack.arrangedSubviews.forEach { row in
            richKeyValueStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }

        let pairs = parseKeyValueLines(from: body)
        for (title, value) in pairs {
            let row = NSStackView()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 10

            let keyLabel = NSTextField(labelWithString: title)
            keyLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            keyLabel.textColor = .secondaryLabelColor
            keyLabel.setContentHuggingPriority(.required, for: .horizontal)
            keyLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

            let valueLabel = NSTextField(wrappingLabelWithString: value)
            valueLabel.font = .systemFont(ofSize: 13, weight: .medium)
            valueLabel.textColor = .labelColor
            valueLabel.maximumNumberOfLines = 0

            row.addArrangedSubview(keyLabel)
            row.addArrangedSubview(valueLabel)

            row.widthAnchor.constraint(equalTo: richKeyValueStack.widthAnchor).isActive = true
            keyLabel.widthAnchor.constraint(equalToConstant: 72).isActive = true
            valueLabel.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -82).isActive = true

            richKeyValueStack.addArrangedSubview(row)
        }
    }

    private func parseKeyValueLines(from body: String) -> [(String, String)] {
        body
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let raw = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { return nil }
                if let index = raw.firstIndex(of: "：") ?? raw.firstIndex(of: ":") {
                    let key = String(raw[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = String(raw[raw.index(after: index)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (key.isEmpty ? "信息" : key, value)
                }
                return ("信息", raw)
            }
    }

    private func installDynamicActionButtons(_ actions: [AgentAction]) {
        richActions = actions
        for (index, action) in actions.enumerated() {
            let button = NSButton(title: action.label, target: self, action: #selector(richDynamicAction(_:)))
            button.translatesAutoresizingMaskIntoConstraints = false
            button.bezelStyle = .rounded
            button.controlSize = .mini
            button.tag = index
            if !action.systemImage.isEmpty {
                button.image = NSImage(systemSymbolName: action.systemImage, accessibilityDescription: action.label)
                button.imagePosition = .imageLeading
            }
            dynamicActionButtons.append(button)
            richActionBar.insertArrangedSubview(button, at: max(1, richActionBar.arrangedSubviews.count - 2))
        }
    }

    private func clearDynamicActionButtons() {
        dynamicActionButtons.forEach { button in
            richActionBar.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        dynamicActionButtons.removeAll()
        richActions.removeAll()
    }

    // MARK: - Wave animation

    private func configureWaveBars() {
        guard let layer = waveView.layer else { return }
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        waveBars.removeAll()
        for _ in 0..<4 {
            let bar = CALayer()
            bar.backgroundColor = NSColor.controlAccentColor.cgColor
            bar.cornerRadius = 1
            layer.addSublayer(bar)
            waveBars.append(bar)
        }
        layoutWaveBars()
    }

    private func layoutWaveBars() {
        let barWidth: CGFloat = 2
        let gap: CGFloat = 2
        let heights: [CGFloat] = [6, 12, 8, 10]
        let totalWidth = CGFloat(waveBars.count) * barWidth + CGFloat(max(0, waveBars.count - 1)) * gap
        var x = (16 - totalWidth) / 2
        for (index, bar) in waveBars.enumerated() {
            let h = heights[index % heights.count]
            bar.frame = CGRect(x: x, y: (16 - h) / 2, width: barWidth, height: h)
            x += barWidth + gap
        }
    }

    private func startWaveAnimation() {
        waveView.isHidden = false
        iconView.isHidden = true
        for (index, bar) in waveBars.enumerated() {
            if bar.animation(forKey: "waveScale") == nil {
                let anim = CABasicAnimation(keyPath: "transform.scale.y")
                anim.fromValue = 0.35
                anim.toValue = 1.0
                anim.duration = 0.42
                anim.autoreverses = true
                anim.repeatCount = .infinity
                anim.beginTime = CACurrentMediaTime() + Double(index) * 0.08
                anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bar.add(anim, forKey: "waveScale")
            }
            if bar.animation(forKey: "waveAlpha") == nil {
                let alpha = CABasicAnimation(keyPath: "opacity")
                alpha.fromValue = 0.45
                alpha.toValue = 1.0
                alpha.duration = 0.42
                alpha.autoreverses = true
                alpha.repeatCount = .infinity
                alpha.beginTime = CACurrentMediaTime() + Double(index) * 0.08
                bar.add(alpha, forKey: "waveAlpha")
            }
        }
    }

    private func stopWaveAnimation() {
        waveView.isHidden = true
        waveBars.forEach { bar in
            bar.removeAnimation(forKey: "waveScale")
            bar.removeAnimation(forKey: "waveAlpha")
        }
    }

    // MARK: - Sound feedback

    private func playSound(_ name: String) {
        let enabled = SharedSettings.defaults.object(forKey: SharedSettings.Keys.interactionSoundEnabled) as? Bool ?? true
        guard enabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    // MARK: - Actions

    @objc private func richCloseAction() {
        hide()
    }

    @objc private func richCopyAction() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(richBody, forType: .string)
        richHideTimer?.invalidate()
        startRichHideTimer()
    }

    @objc private func richContinueAction() {
        richHideTimer?.invalidate()
        hide()
        onContinue?()
    }

    @objc private func richDynamicAction(_ sender: NSButton) {
        guard richActions.indices.contains(sender.tag) else { return }
        richHideTimer?.invalidate()
        richActions[sender.tag].handler()
        startRichHideTimer()
    }

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

    @objc private func fallbackSystemAction() {
        onFallbackSelect?(.systemControl, pendingText)
        hide()
    }

    @objc private func fallbackSearchAction() {
        onFallbackSelect?(.webSearch, pendingText)
        hide()
    }

    // MARK: - Key monitoring

    private func installKeyMonitor() {
        removeKeyMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c", !self.richCopyButton.isHidden {
                self.richCopyAction()
                return nil
            }
            if event.keyCode == 53 { // Escape
                if !self.richActionBar.isHidden {
                    self.hide()
                    return nil
                }
                self.cancelAction()
                return nil
            }
            if event.keyCode == 36 { // Return
                if !self.richContinueButton.isHidden {
                    self.richContinueAction()
                    return nil
                }
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
