import SwiftUI
import AVFoundation
import Speech

private enum OnboardingStep: Int, CaseIterable {
    case permissionCore
    case permissionAccessibility
    case style
    case fnExperience
    case done

    var title: String {
        switch self {
        case .permissionCore: return "1. 麦克风与语音识别"
        case .permissionAccessibility: return "2. 辅助功能"
        case .style: return "3. 输入风格"
        case .fnExperience: return "4. Fn 首次体验"
        case .done: return "5. 完成"
        }
    }
}

struct OnboardingView: View {
    let onComplete: () -> Void

    @ObservedObject private var realtime = RealtimeSessionStore.shared
    @State private var step: OnboardingStep = .permissionCore
    @State private var micGranted = false
    @State private var speechGranted = false
    @State private var accessibilityGranted = false
    @State private var selectedStyle = "default"
    @State private var hotkeyText = "Fn"
    @State private var didFinishFnExperience = false
    @State private var fnExperienceHint = "按住 Fn 开始说话，松开 Fn 自动结束并进入改写。"
    @State private var permissionPollTimer: Timer?

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
        .onDisappear {
            stopPolling()
        }
        .onChange(of: realtime.updatedAt) { _ in
            guard step == .fnExperience else { return }
            if realtime.stage == .rewriting || realtime.stage == .inserted || realtime.stage == .pendingCopy {
                didFinishFnExperience = true
                fnExperienceHint = "体验完成：你已经触发了“按住 Fn 说话，松开改写”。"
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            syncPermissions()
            startPolling()
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
        case .fnExperience:
            fnExperiencePage
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
        case .fnExperience:
            return didFinishFnExperience
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

    private var fnExperiencePage: some View {
        OnboardingCard {
            Text("这一页只做一件事：完成一次 Fn 输入体验。")
                .foregroundStyle(.secondary)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("默认输入热键")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(hotkeyText)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                Spacer()
                Text(realtime.stageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            )

            Text(fnExperienceHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(realtime.stage == .listening || realtime.stage == .transcribing ? "停止体验" : "开始 Fn 体验") {
                    AppHotkeyVoiceService.shared.toggleFromUI()
                }
                .buttonStyle(.borderedProminent)

                if !didFinishFnExperience {
                    Button("我已了解，继续") {
                        didFinishFnExperience = true
                        fnExperienceHint = "已跳过实际语音体验，可在首页立即开始使用。"
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var donePage: some View {
        OnboardingCard {
            Text("设置完成，已进入可用状态。")
                .font(.title3.weight(.semibold))

            FeatureLine(icon: "waveform", title: "输入逻辑", desc: "按住说话，松开结束。")
            FeatureLine(icon: "brain.head.profile", title: "Thinking", desc: "停止输入后自动改写，并尝试直接注入当前焦点输入框。")
            FeatureLine(icon: "doc.on.doc", title: "无焦点兜底", desc: "如果没有可输入焦点，会弹出轻量复制按钮，防止内容丢失。")
        }
    }

    private func primaryAction() {
        if step == .style {
            SharedSettings.defaults.set(selectedStyle, forKey: SharedSettings.Keys.selectedStyle)
        }
        if step == .done {
            applyDefaultFnHotkey()
            onComplete()
            return
        }
        move(1)
    }

    private func move(_ delta: Int) {
        let next = max(0, min(OnboardingStep.done.rawValue, step.rawValue + delta))
        step = OnboardingStep(rawValue: next) ?? .permissionCore
    }

    private func resetInitialConfig() {
        SharedSettings.defaults.set("gemini-2.5-flash-lite", forKey: SharedSettings.Keys.llmModel)
        SharedSettings.defaults.set("gemini-2.5-flash-lite", forKey: SharedSettings.Keys.agentModel)
        SharedSettings.defaults.set("gemini-2.5-flash-lite", forKey: SharedSettings.Keys.voiceInputModel)
        applyDefaultFnHotkey()
        selectedStyle = SharedSettings.defaults.string(forKey: SharedSettings.Keys.selectedStyle) ?? "default"
        let mod = SharedSettings.defaults.object(forKey: SharedSettings.Keys.hotkeyModifiers) as? Int ?? HotkeyConfig.defaultModifiers
        let code = SharedSettings.defaults.object(forKey: SharedSettings.Keys.hotkeyKeyCode) as? Int ?? HotkeyConfig.defaultKeyCode
        hotkeyText = formattedHotkey(modifiers: mod, keyCode: code)
    }

    private func applyDefaultFnHotkey() {
        SharedSettings.defaults.set(true, forKey: SharedSettings.Keys.hotkeyEnabled)
        SharedSettings.defaults.set(HotkeyConfig.functionModifierFlag, forKey: SharedSettings.Keys.hotkeyModifiers)
        SharedSettings.defaults.set(63, forKey: SharedSettings.Keys.hotkeyKeyCode)
        SharedSettings.defaults.set("Fn", forKey: SharedSettings.Keys.hotkeyRuntimeStatus)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(SharedNotifications.hotkeyChanged),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func syncPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        accessibilityGranted = AccessibilityTrust.isTrusted(prompt: false)
    }

    private func startPolling() {
        stopPolling()
        var count = 0
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            syncPermissions()
            count += 1
            if count > 20 || (micGranted && speechGranted && accessibilityGranted) {
                timer.invalidate()
                if permissionPollTimer === timer {
                    permissionPollTimer = nil
                }
            }
        }
        if let timer = permissionPollTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    private func formattedHotkey(modifiers: Int, keyCode: Int) -> String {
        HotkeyConfig.displayString(modifiers: modifiers, keyCode: keyCode)
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

// PermissionActionRow and StyleButton are in PermissionActionRow.swift

#Preview("Onboarding") {
    OnboardingView(onComplete: {})
}
