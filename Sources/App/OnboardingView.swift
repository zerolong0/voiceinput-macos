import SwiftUI
import AVFoundation
import Speech

private enum OnboardingStep: Int, CaseIterable {
    case permissionCore
    case permissionAccessibility
    case style
    case hotkey
    case done

    var title: String {
        switch self {
        case .permissionCore: return "1. 麦克风与语音识别"
        case .permissionAccessibility: return "2. 辅助功能"
        case .style: return "3. 输入风格"
        case .hotkey: return "4. 快捷键"
        case .done: return "5. 完成"
        }
    }
}

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var step: OnboardingStep = .permissionCore
    @State private var micGranted = false
    @State private var speechGranted = false
    @State private var accessibilityGranted = false
    @State private var selectedStyle = "default"
    @State private var hotkeyText = "Option + 0"
    @State private var isCapturingHotkey = false
    @State private var hotkeyCaptureHint = "点击下方快捷键框后，直接按键盘录入"
    @State private var localKeyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("VoiceInput 初始设置")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                stepDots
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 12)

            HStack {
                Text(step.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 12)

            currentStepCard
                .frame(maxWidth: 560)

            Spacer(minLength: 12)

            HStack {
                if step != .permissionCore && step != .done {
                    Button("上一步") { move(-1) }
                        .buttonStyle(.bordered)
                }

                Spacer()

                Button(step == .done ? "进入首页" : "下一步") {
                    primaryAction()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canGoNext)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            SharedSettings.bootstrapDefaults()
            resetInitialConfig()
            syncPermissions()
            startPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            syncPermissions()
            startPolling()
        }
        .onDisappear {
            stopHotkeyCapture()
        }
    }

    @ViewBuilder
    private var currentStepCard: some View {
        switch step {
        case .permissionCore:
            corePermissionPage
        case .permissionAccessibility:
            accessibilityPermissionPage
        case .style:
            stylePage
        case .hotkey:
            hotkeyPage
        case .done:
            donePage
        }
    }

    private var canGoNext: Bool {
        switch step {
        case .permissionCore:
            return micGranted && speechGranted
        case .permissionAccessibility:
            return accessibilityGranted
        default:
            return true
        }
    }

    private var stepDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var corePermissionPage: some View {
        OnboardingCard {
            Text("先完成基础权限，保证可以正常收音和实时转写。")
                .foregroundStyle(.secondary)

            PermissionActionRow(icon: "mic.fill", title: "麦克风", desc: "采集语音输入", granted: micGranted, buttonTitle: "授权") {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async { micGranted = granted }
                }
            }

            PermissionActionRow(icon: "text.bubble", title: "语音识别", desc: "本地实时转写", granted: speechGranted, buttonTitle: "授权") {
                SFSpeechRecognizer.requestAuthorization { status in
                    DispatchQueue.main.async { speechGranted = (status == .authorized) }
                }
            }

            Button("刷新状态") { syncPermissions() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private var accessibilityPermissionPage: some View {
        OnboardingCard {
            Text("辅助功能单独一步：它决定了改写完成后是否能自动写入当前焦点输入框。")
                .foregroundStyle(.secondary)

            PermissionActionRow(icon: "hand.tap", title: "辅助功能", desc: "自动注入文本", granted: accessibilityGranted, buttonTitle: "去设置") {
                _ = AccessibilityTrust.isTrusted(prompt: true)
                if !AccessibilityTrust.isTrusted(prompt: false) {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }
            }

            if !accessibilityGranted {
                Text("开启后回到应用，本页会自动刷新。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("刷新状态") { syncPermissions() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private var stylePage: some View {
        OnboardingCard {
            Text("选择默认改写风格。终端/开发场景建议使用 Vibe Coding。")
                .foregroundStyle(.secondary)

            StyleButton(id: "default", name: "智能模式", icon: "sparkles", desc: "自动识别场景", isSelected: selectedStyle == "default") {
                selectedStyle = "default"
            }
            StyleButton(id: "formal", name: "商务正式", icon: "briefcase", desc: "邮件、报告、文档", isSelected: selectedStyle == "formal") {
                selectedStyle = "formal"
            }
            StyleButton(id: "casual", name: "日常聊天", icon: "bubble.left.and.bubble.right", desc: "微信、短信、社交", isSelected: selectedStyle == "casual") {
                selectedStyle = "casual"
            }
            StyleButton(id: "vibe_coding", name: "Vibe Coding", icon: "chevron.left.forwardslash.chevron.right", desc: "终端、Coding Agent、Web 开发", isSelected: selectedStyle == "vibe_coding") {
                selectedStyle = "vibe_coding"
            }
        }
    }

    private var hotkeyPage: some View {
        OnboardingCard {
            Text("快捷键支持单键和双键组合。点击快捷键框后直接按键录入，可在设置页继续修改。")
                .foregroundStyle(.secondary)

            Button {
                if isCapturingHotkey {
                    stopHotkeyCapture()
                } else {
                    startHotkeyCapture()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前热键")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(isCapturingHotkey ? "请按下快捷键..." : hotkeyText)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Image(systemName: isCapturingHotkey ? "keyboard.badge.ellipsis" : "keyboard")
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isCapturingHotkey ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)

            Text(hotkeyCaptureHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("使用推荐热键（Option + 0）") {
                SharedSettings.defaults.set(true, forKey: SharedSettings.Keys.hotkeyEnabled)
                SharedSettings.defaults.set(2048, forKey: SharedSettings.Keys.hotkeyModifiers)
                SharedSettings.defaults.set(29, forKey: SharedSettings.Keys.hotkeyKeyCode)
                hotkeyText = "Option + 0"
                hotkeyCaptureHint = "已恢复默认热键"
                DistributedNotificationCenter.default().postNotificationName(
                    Notification.Name(SharedNotifications.hotkeyChanged),
                    object: nil,
                    userInfo: nil,
                    deliverImmediately: true
                )
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var donePage: some View {
        OnboardingCard {
            Text("设置完成，已进入可用状态。")
                .font(.title3.weight(.semibold))

            FeatureLine(icon: "waveform", title: "输入逻辑", desc: "短按开始，再按一次结束；长按松手即结束并进入改写。")
            FeatureLine(icon: "brain.head.profile", title: "Thinking", desc: "停止输入后自动改写，并尝试直接注入当前焦点输入框。")
            FeatureLine(icon: "doc.on.doc", title: "无焦点兜底", desc: "如果没有可输入焦点，会弹出轻量复制按钮，防止内容丢失。")
        }
    }

    private func primaryAction() {
        if step == .style {
            SharedSettings.defaults.set(selectedStyle, forKey: SharedSettings.Keys.selectedStyle)
        }
        if step == .done {
            onComplete()
            return
        }
        move(1)
    }

    private func move(_ delta: Int) {
        let next = max(0, min(OnboardingStep.done.rawValue, step.rawValue + delta))
        withAnimation(.easeInOut(duration: 0.2)) {
            step = OnboardingStep(rawValue: next) ?? .permissionCore
        }
    }

    private func resetInitialConfig() {
        SharedSettings.defaults.set("gemini-2.5-flash-lite", forKey: SharedSettings.Keys.llmModel)
        selectedStyle = SharedSettings.defaults.string(forKey: SharedSettings.Keys.selectedStyle) ?? "default"
        let mod = SharedSettings.defaults.object(forKey: SharedSettings.Keys.hotkeyModifiers) as? Int ?? 2048
        let code = SharedSettings.defaults.object(forKey: SharedSettings.Keys.hotkeyKeyCode) as? Int ?? 29
        hotkeyText = formattedHotkey(modifiers: mod, keyCode: code)
    }

    private func syncPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        accessibilityGranted = AccessibilityTrust.isTrusted(prompt: false)
    }

    private func startPolling() {
        var count = 0
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            syncPermissions()
            count += 1
            if count > 20 || (micGranted && speechGranted && accessibilityGranted) {
                timer.invalidate()
            }
        }
    }

    private func startHotkeyCapture() {
        stopHotkeyCapture()
        isCapturingHotkey = true
        hotkeyCaptureHint = "正在录入，按下任意键完成（Esc 取消）"

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard isCapturingHotkey else { return event }
            if event.keyCode == 53 {
                hotkeyCaptureHint = "已取消录入"
                stopHotkeyCapture()
                return nil
            }

            let modifiers = event.modifierFlags.intersection([.option, .command, .control, .shift])
            let modifierFlags = HotkeyConfig.carbonFlags(from: modifiers)
            let keyCode = Int(event.keyCode)
            let validation = HotkeyConfig.validate(modifiers: modifierFlags, keyCode: keyCode)

            guard validation.isValid else {
                hotkeyCaptureHint = validation.message ?? "快捷键无效"
                return nil
            }

            SharedSettings.defaults.set(true, forKey: SharedSettings.Keys.hotkeyEnabled)
            SharedSettings.defaults.set(modifierFlags, forKey: SharedSettings.Keys.hotkeyModifiers)
            SharedSettings.defaults.set(keyCode, forKey: SharedSettings.Keys.hotkeyKeyCode)
            hotkeyText = formattedHotkey(modifiers: modifierFlags, keyCode: keyCode)
            hotkeyCaptureHint = "已保存：\(hotkeyText)"
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(SharedNotifications.hotkeyChanged),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            stopHotkeyCapture()
            return nil
        }
    }

    private func stopHotkeyCapture() {
        isCapturingHotkey = false
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    private func formattedHotkey(modifiers: Int, keyCode: Int) -> String {
        let modTitle = HotkeyConfig.modifierTitle(for: modifiers)
        let keyTitle = HotkeyConfig.keyTitle(for: keyCode)
        if modTitle == "无修饰键" {
            return keyTitle
        }
        return "\(modTitle) + \(keyTitle)"
    }
}

private struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(18)
        .background(.thinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
    }
}

private struct FeatureLine: View {
    let icon: String
    let title: String
    let desc: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct PermissionActionRow: View {
    let icon: String
    let title: String
    let desc: String
    let granted: Bool
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(granted ? .green : .orange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

struct StyleButton: View {
    let id: String
    let name: String
    let icon: String
    let desc: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.weight(.medium))
                    Text(desc).font(.caption).foregroundStyle(isSelected ? Color.white.opacity(0.8) : .secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.white)
                }
            }
            .padding(12)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.08))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Onboarding") {
    OnboardingView(onComplete: {})
}
