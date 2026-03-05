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

    var onConfirm: ((RecognizedIntent) -> Void)?
    var onCancel: (() -> Void)?
    var onFallbackSelect: ((IntentType, String) -> Void)?

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

        root.addSubview(card)
        card.addSubview(iconView)
        card.addSubview(waveView)
        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)
        card.addSubview(buttonBar)
        card.addSubview(fallbackStack)

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
            titleLabel.stringValue = "按住说话，松开结束"
            titleLabel.textColor = .labelColor
            hideAllButtons()
            relayout(width: calculatedWidth(for: "按住说话，松开结束"), height: 44)
            showPanel()
            playSound("Tink")
            installKeyMonitor()

        case .recognizing(let text):
            applyCompactLayout()
            stopWaveAnimation()
            iconView.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            iconView.contentTintColor = .controlAccentColor
            iconView.isHidden = false
            titleLabel.stringValue = "分析中"
            titleLabel.textColor = .labelColor
            hideAllButtons()
            relayout(width: calculatedWidth(for: "分析中"), height: 44)

        case .autoExecuting(let intent):
            pendingIntent = intent
            applyCompactLayout()
            stopWaveAnimation()
            iconView.image = intentIcon(for: intent.type)
            iconView.contentTintColor = .controlAccentColor
            iconView.isHidden = false
            titleLabel.stringValue = intent.displaySummary
            titleLabel.textColor = .labelColor
            hideAllButtons()
            relayout(width: calculatedWidth(for: intent.displaySummary), height: 44)
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
            titleLabel.stringValue = intent.displaySummary
            titleLabel.textColor = .labelColor
            subtitleLabel.stringValue = "说「确认」执行 · 说「取消」放弃"
            subtitleLabel.isHidden = false
            buttonBar.isHidden = false
            fallbackStack.isHidden = true
            relayout(width: 340, height: 92)
            playSound("Pop")
            installKeyMonitor()

        case .voiceConfirming(let intent, let text):
            pendingIntent = intent
            applyExpandedLayout()
            startWaveAnimation()
            iconView.isHidden = true
            let visible = visibleTextForListening(text)
            titleLabel.stringValue = visible.isEmpty ? "正在聆听..." : visible
            titleLabel.textColor = .labelColor
            subtitleLabel.stringValue = intent.displaySummary
            subtitleLabel.isHidden = false
            buttonBar.isHidden = false
            fallbackStack.isHidden = true
            relayout(width: 340, height: 92)

        case .executing(let intent):
            applyCompactLayout()
            stopWaveAnimation()
            iconView.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
            iconView.contentTintColor = .controlAccentColor
            iconView.isHidden = false
            titleLabel.stringValue = "正在执行..."
            titleLabel.textColor = .labelColor
            hideAllButtons()
            relayout(width: calculatedWidth(for: "正在执行..."), height: 44)
            removeKeyMonitor()

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
            playSound("Basso")
            autoHideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                self?.hide()
            }

        case .idle:
            hide()
        }
    }

    func updateListeningText(_ text: String) {
        guard case .listening = currentState else { return }
        let visible = visibleTextForListening(text)
        titleLabel.stringValue = visible.isEmpty ? "按住说话，松开结束" : visible
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
        subtitleLabel.isHidden = true
        buttonBar.isHidden = true
        fallbackStack.isHidden = false
        relayout(width: 340, height: 80)
        playSound("Morse")
        installKeyMonitor()
    }

    func hide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
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

    private func intentIcon(for type: IntentType) -> NSImage? {
        let name: String
        switch type {
        case .addCalendar: name = "calendar.badge.plus"
        case .createNote: name = "note.text.badge.plus"
        case .openApp: name = "arrow.up.forward.app"
        case .runCommand: name = "terminal"
        case .systemControl: name = "gearshape"
        case .webSearch: name = "magnifyingglass"
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
