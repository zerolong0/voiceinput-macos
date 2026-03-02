import Cocoa

struct InputOverlayModel {
    enum Stage {
        case idle
        case arming
        case listening
        case rewriting
        case copyFallback
        case error
    }

    let stage: Stage
    let statusText: String
    let displayText: String
    let showsCopy: Bool
    let showsClose: Bool
    let a11yLabel: String
}

final class InputStatusPanel {
    private let panel: NSPanel
    private let root = NSView()
    private let card = NSVisualEffectView()

    private let iconView = NSImageView()
    private let waveView = NSView()
    private var waveBars: [CALayer] = []
    private let rewritingOverlay = NSView()
    private var rewritingOverlayWidthConstraint: NSLayoutConstraint?
    private var rewritingOverlayTimer: Timer?
    private var rewritingOverlayProgress: CGFloat = 0.0
    private var rewritingOverlayCompletionWorkItem: DispatchWorkItem?
    private let spinner = NSProgressIndicator()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    private let copyButton = NSButton(title: "复制", target: nil, action: nil)
    private let closeButton = NSButton()
    private let primaryButton = NSButton(title: "好的", target: nil, action: nil)

    private var autoHideTimer: Timer?
    private var currentStage: InputOverlayModel.Stage = .idle

    private var heightConstraint: NSLayoutConstraint?
    private var titleCenterYConstraint: NSLayoutConstraint?
    private var titleTopConstraint: NSLayoutConstraint?
    private var closeCenterYConstraint: NSLayoutConstraint?
    private var closeTopConstraint: NSLayoutConstraint?
    private var iconCenterYConstraint: NSLayoutConstraint?
    private var iconTopConstraint: NSLayoutConstraint?
    private var titleTrailingToCardConstraint: NSLayoutConstraint?
    private var titleTrailingToCopyConstraint: NSLayoutConstraint?
    private var titleTrailingToCloseConstraint: NSLayoutConstraint?

    var onCopyRequested: (() -> Void)?
    var onPrimaryRequested: (() -> Void)?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 44),
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

        rewritingOverlay.translatesAutoresizingMaskIntoConstraints = false
        rewritingOverlay.wantsLayer = true
        rewritingOverlay.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        rewritingOverlay.layer?.cornerRadius = 22
        rewritingOverlay.isHidden = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .labelColor

        waveView.translatesAutoresizingMaskIntoConstraints = false
        waveView.wantsLayer = true
        waveView.isHidden = true
        configureWaveBars()

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.isHidden = true

        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.target = self
        copyButton.action = #selector(copyAction)
        copyButton.bezelStyle = .rounded
        copyButton.font = .systemFont(ofSize: 12, weight: .semibold)
        copyButton.controlSize = .small

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.target = self
        closeButton.action = #selector(closeAction)
        closeButton.bezelStyle = .texturedRounded
        closeButton.title = ""
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.controlSize = .small

        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.target = self
        primaryButton.action = #selector(primaryAction)
        primaryButton.bezelStyle = .rounded
        primaryButton.controlSize = .regular
        primaryButton.isHidden = true

        root.addSubview(card)
        card.addSubview(rewritingOverlay)
        card.addSubview(iconView)
        card.addSubview(waveView)
        card.addSubview(spinner)
        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)
        card.addSubview(copyButton)
        card.addSubview(closeButton)
        card.addSubview(primaryButton)

        heightConstraint = card.heightAnchor.constraint(equalToConstant: 44)
        titleCenterYConstraint = titleLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        titleTopConstraint = titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16)
        titleTopConstraint?.isActive = false
        titleCenterYConstraint?.isActive = true
        closeCenterYConstraint = closeButton.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        closeTopConstraint = closeButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 8)
        closeTopConstraint?.isActive = false
        closeCenterYConstraint?.isActive = true
        iconCenterYConstraint = iconView.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        iconTopConstraint = iconView.topAnchor.constraint(equalTo: card.topAnchor, constant: 15)
        iconTopConstraint?.isActive = false
        iconCenterYConstraint?.isActive = true
        titleTrailingToCardConstraint = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -12)
        titleTrailingToCopyConstraint = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: copyButton.leadingAnchor, constant: -8)
        titleTrailingToCloseConstraint = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8)
        titleTrailingToCardConstraint?.isActive = true
        rewritingOverlayWidthConstraint = rewritingOverlay.widthAnchor.constraint(equalToConstant: 0)
        rewritingOverlayWidthConstraint?.isActive = true

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: root.topAnchor),
            card.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            heightConstraint!,

            rewritingOverlay.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            rewritingOverlay.topAnchor.constraint(equalTo: card.topAnchor),
            rewritingOverlay.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            iconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 11),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            waveView.leadingAnchor.constraint(equalTo: iconView.leadingAnchor),
            waveView.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            waveView.widthAnchor.constraint(equalToConstant: 16),
            waveView.heightAnchor.constraint(equalToConstant: 16),

            spinner.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 14),
            spinner.heightAnchor.constraint(equalToConstant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 9),
            titleTrailingToCardConstraint!,
            titleTrailingToCopyConstraint!,
            titleTrailingToCloseConstraint!,

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),

            copyButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            copyButton.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            copyButton.heightAnchor.constraint(equalToConstant: 22),

            closeButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),

            primaryButton.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            primaryButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            primaryButton.heightAnchor.constraint(equalToConstant: 28)
        ])

        copyButton.isHidden = true
        closeButton.isHidden = true
        applyCompactStyle(for: .idle, text: "")
    }

    func render(_ model: InputOverlayModel) {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        currentStage = model.stage

        let text = resolvedText(status: model.statusText, text: model.displayText)
        let isError = model.stage == .error
        let displayed = displayedText(for: model.stage, rawText: text)

        if isError {
            applyErrorStyle(text: text)
        } else {
            applyCompactStyle(for: model.stage, text: text)
        }

        copyButton.isHidden = !model.showsCopy || isError
        closeButton.isHidden = !model.showsClose
        updateTitleTrailingConstraints(showCopy: !copyButton.isHidden, showClose: !closeButton.isHidden)
        panel.setAccessibilityLabel(model.a11yLabel)

        let width = calculatedWidth(
            for: displayed,
            stage: model.stage,
            showAction: model.showsCopy || model.showsClose,
            isError: isError
        )
        let height: CGFloat = calculatedHeight(for: text, isError: isError)
        heightConstraint?.constant = height

        var frame = panel.frame
        frame.size = NSSize(width: width, height: height)
        panel.setFrame(frame, display: true)
        positionBottomCenter()

        if !panel.isVisible {
            panel.orderFrontRegardless()
        }

        if isError {
            autoHideTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false) { [weak self] _ in
                self?.hide()
            }
        }
    }

    func show(status: String, text: String, showCopy: Bool) {
        let stage: InputOverlayModel.Stage = showCopy ? .copyFallback : .idle
        render(.init(stage: stage, statusText: status, displayText: text, showsCopy: showCopy, showsClose: false, a11yLabel: status))
    }

    func update(status: String, text: String, showCopy: Bool) {
        let stage: InputOverlayModel.Stage = showCopy ? .copyFallback : currentStage
        render(.init(stage: stage, statusText: status, displayText: text, showsCopy: showCopy, showsClose: false, a11yLabel: status))
    }

    func showArming() {
        render(.init(stage: .arming, statusText: "", displayText: "准备中", showsCopy: false, showsClose: false, a11yLabel: "准备启动语音输入"))
    }

    func showListening(text: String) {
        render(.init(stage: .listening, statusText: "", displayText: text, showsCopy: false, showsClose: false, a11yLabel: "正在输入"))
    }

    func showThinking(text: String) {
        render(.init(stage: .rewriting, statusText: "", displayText: text, showsCopy: false, showsClose: false, a11yLabel: "正在改写"))
    }

    func showError(_ text: String) {
        render(.init(stage: .error, statusText: "识别失败", displayText: text, showsCopy: false, showsClose: true, a11yLabel: "识别失败"))
    }

    func hide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        spinner.stopAnimation(nil)
        stopWaveAnimation()
        stopRewritingProgressImmediately()
        panel.orderOut(nil)
    }

    private func applyCompactStyle(for stage: InputOverlayModel.Stage, text: String) {
        card.material = .hudWindow
        card.layer?.cornerRadius = 22
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor

        subtitleLabel.isHidden = true
        primaryButton.isHidden = true

        titleTopConstraint?.isActive = false
        titleCenterYConstraint?.isActive = true
        closeTopConstraint?.isActive = false
        closeCenterYConstraint?.isActive = true
        iconTopConstraint?.isActive = false
        iconCenterYConstraint?.isActive = true

        let compactText = displayedText(for: stage, rawText: text)
        titleLabel.stringValue = compactText.isEmpty ? " " : compactText
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor

        switch stage {
        case .listening:
            completeRewritingProgressIfNeeded()
            startWaveAnimation()
            spinner.stopAnimation(nil)
        case .rewriting, .arming:
            stopWaveAnimation()
            iconView.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            iconView.contentTintColor = .controlAccentColor
            iconView.isHidden = false
            spinner.stopAnimation(nil)
            if stage == .rewriting {
                startRewritingProgress()
            } else {
                completeRewritingProgressIfNeeded()
            }
        case .copyFallback:
            completeRewritingProgressIfNeeded()
            stopWaveAnimation()
            iconView.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            iconView.contentTintColor = .controlAccentColor
            iconView.isHidden = false
            spinner.stopAnimation(nil)
        case .idle:
            completeRewritingProgressIfNeeded()
            stopWaveAnimation()
            iconView.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
            iconView.contentTintColor = .controlAccentColor
            iconView.isHidden = false
            spinner.stopAnimation(nil)
        case .error:
            stopRewritingProgressImmediately()
            stopWaveAnimation()
            break
        }
    }

    private func applyErrorStyle(text: String) {
        card.material = .popover
        card.layer?.cornerRadius = 14
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor

        titleCenterYConstraint?.isActive = false
        titleTopConstraint?.isActive = true
        closeCenterYConstraint?.isActive = false
        closeTopConstraint?.isActive = true
        iconCenterYConstraint?.isActive = false
        iconTopConstraint?.isActive = true

        iconView.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        iconView.contentTintColor = .controlAccentColor
        iconView.isHidden = false
        spinner.stopAnimation(nil)
        stopWaveAnimation()
        stopRewritingProgressImmediately()

        titleLabel.stringValue = shortErrorTitle(from: text)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor

        subtitleLabel.stringValue = shortErrorBody(from: text)
        subtitleLabel.isHidden = false

        primaryButton.title = "知道了"
        primaryButton.isHidden = false
    }

    private func shortErrorTitle(from text: String) -> String {
        if text.contains("未授权") || text.contains("权限") {
            return "权限或系统状态异常"
        }
        return "识别失败"
    }

    private func shortErrorBody(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "请稍后重试。" : trimmed
    }

    private func resolvedText(status: String, text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty { return trimmedText }
        if !trimmedStatus.isEmpty { return trimmedStatus }
        return ""
    }

    private func displayedText(for stage: InputOverlayModel.Stage, rawText: String) -> String {
        switch stage {
        case .listening:
            return visibleTextForListening(rawText)
        case .rewriting:
            return "改写中"
        default:
            return rawText
        }
    }

    private func updateTitleTrailingConstraints(showCopy: Bool, showClose: Bool) {
        titleTrailingToCardConstraint?.isActive = !showCopy && !showClose
        titleTrailingToCopyConstraint?.isActive = showCopy
        titleTrailingToCloseConstraint?.isActive = showClose
    }

    private func calculatedWidth(for text: String, stage: InputOverlayModel.Stage, showAction: Bool, isError: Bool) -> CGFloat {
        if isError {
            let titleFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
            let bodyFont = NSFont.systemFont(ofSize: 13, weight: .regular)
            let titleW = (shortErrorTitle(from: text) as NSString).size(withAttributes: [.font: titleFont]).width
            let bodyW = (shortErrorBody(from: text) as NSString).size(withAttributes: [.font: bodyFont]).width
            let contentW = max(titleW, min(bodyW, 220))
            return max(300, min(380, 16 + 16 + 10 + contentW + 56))
        }

        if stage == .listening {
            let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let visible = visibleTextForListening(text)
            let measured = (visible as NSString).size(withAttributes: attrs).width
            let viewport = ("汉汉汉汉汉汉汉汉汉汉" as NSString).size(withAttributes: attrs).width
            let textWidth = min(measured, viewport)
            let trailing = showAction ? CGFloat(80) : 20
            return ceil(11 + 16 + 9 + textWidth + trailing)
        }

        let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let measured = (text.isEmpty ? " " : text as NSString).size(withAttributes: attrs).width
        let maxText = ("汉汉汉汉汉汉汉汉" as NSString).size(withAttributes: attrs).width * 1.1
        let textWidth = min(measured, maxText)
        let trailing = showAction ? CGFloat(80) : 20
        return max(112, min(260, 11 + 16 + 9 + textWidth + trailing))
    }

    private func visibleTextForListening(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "请开始说话" }
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

    private func calculatedHeight(for text: String, isError: Bool) -> CGFloat {
        guard isError else { return 44 }
        let body = shortErrorBody(from: text)
        let bodyFont = NSFont.systemFont(ofSize: 13, weight: .regular)
        let maxBodyWidth: CGFloat = 220
        let bodyRect = (body as NSString).boundingRect(
            with: NSSize(width: maxBodyWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: bodyFont]
        )
        let bodyHeight = min(max(20, ceil(bodyRect.height)), 48)
        return 92 + bodyHeight
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

    @objc private func copyAction() {
        onCopyRequested?()
    }

    @objc private func closeAction() {
        hide()
    }

    @objc private func primaryAction() {
        if let onPrimaryRequested {
            onPrimaryRequested()
        } else {
            hide()
        }
    }

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

    private func startRewritingProgress() {
        rewritingOverlayCompletionWorkItem?.cancel()
        rewritingOverlayCompletionWorkItem = nil
        rewritingOverlay.isHidden = false
        if rewritingOverlayProgress <= 0.01 {
            rewritingOverlayProgress = 0.12
        }
        updateRewritingOverlayWidth()
        if rewritingOverlayTimer != nil { return }
        rewritingOverlayTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self else { return }
            switch self.rewritingOverlayProgress {
            case ..<0.60:
                self.rewritingOverlayProgress += 0.09
            case ..<0.82:
                self.rewritingOverlayProgress += 0.035
            case ..<0.93:
                self.rewritingOverlayProgress += 0.012
            default:
                self.rewritingOverlayProgress += 0.002
            }
            self.rewritingOverlayProgress = min(self.rewritingOverlayProgress, 0.965)
            self.updateRewritingOverlayWidth()
        }
    }

    private func completeRewritingProgressIfNeeded() {
        guard !rewritingOverlay.isHidden else { return }
        rewritingOverlayTimer?.invalidate()
        rewritingOverlayTimer = nil
        rewritingOverlayCompletionWorkItem?.cancel()
        rewritingOverlayProgress = 1.0
        updateRewritingOverlayWidth()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.stopRewritingProgressImmediately()
        }
        rewritingOverlayCompletionWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: item)
    }

    private func stopRewritingProgressImmediately() {
        rewritingOverlayTimer?.invalidate()
        rewritingOverlayTimer = nil
        rewritingOverlayCompletionWorkItem?.cancel()
        rewritingOverlayCompletionWorkItem = nil
        rewritingOverlayProgress = 0.0
        rewritingOverlayWidthConstraint?.constant = 0
        rewritingOverlay.isHidden = true
    }

    private func updateRewritingOverlayWidth() {
        let width = max(0, card.bounds.width * rewritingOverlayProgress)
        rewritingOverlayWidthConstraint?.constant = width
        card.layoutSubtreeIfNeeded()
    }
}
