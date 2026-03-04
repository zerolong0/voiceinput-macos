import SwiftUI
import AVFoundation
import Speech
import ApplicationServices

// MARK: - 设置视图
struct SettingsView: View {
    var embedded: Bool = false
    @AppStorage("selectedStyle") private var selectedStyle = "default"
    @AppStorage("hotkeyEnabled") private var hotkeyEnabled = true
    @AppStorage("hotkeyModifiers") private var hotkeyModifiers = 2048 // optionKey
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode = 49 // Space
    @AppStorage("hotkeyHoldToStopThreshold") private var hotkeyHoldToStopThreshold = 0.35

    @State private var llmEnabled = false
    @State private var llmAPIBaseURL = "https://oneapi.gemiaude.com/v1"
    @State private var llmAPIKey = ""
    @State private var llmModel = "gemini-2.5-flash-lite"
    @State private var saveHistoryEnabled = true
    @State private var muteExternalAudioDuringInput = true
    @State private var interactionSoundEnabled = true
    @State private var launchAtLoginEnabled = false
    @State private var showInDockEnabled = true
    @State private var terminalHotkeyEnabled = false
    @State private var terminalHotkeyModifiers = 4096 // controlKey
    @State private var terminalHotkeyKeyCode = 49 // Space
    @State private var isCapturingTerminalHotkey = false
    @State private var terminalHotkeyCaptureHint = "点击快捷键框后直接按键盘录入"
    @State private var localTerminalKeyMonitor: Any?
    @State private var showAdvancedLLM = false
    @State private var launchAtLoginMessage = ""
    @State private var isCapturingHotkey = false
    @State private var hotkeyCaptureHint = "点击快捷键框后直接按键盘录入"
    @State private var hotkeyRuntimeStatus = "等待注册"
    @State private var diagnostics = PermissionDiagnostics.snapshot()
    @State private var localKeyMonitor: Any?

    private let styles: [(id: String, name: String, icon: String, desc: String)] = [
        ("default", "智能模式", "sparkles", "自动识别场景"),
        ("formal", "商务正式", "briefcase", "邮件、报告、文档"),
        ("casual", "日常聊天", "bubble.left.and.bubble.right", "微信、短信、社交"),
        ("vibe_coding", "Vibe Coding", "chevron.left.forwardslash.chevron.right", "编程、命令行")
    ]

    var body: some View {
        VStack(spacing: 0) {
            if !embedded {
                HStack {
                    Text("VoiceInput 设置")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }

            // 内容
            ScrollView {
                VStack(spacing: 24) {
                    // 快捷键设置
                    SettingsSection(title: "快捷键", icon: "keyboard") {
                        Toggle("启用全局快捷键", isOn: $hotkeyEnabled)
                            .toggleStyle(.switch)

                        Button {
                            if isCapturingHotkey {
                                stopHotkeyCapture()
                            } else {
                                startHotkeyCapture()
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("激活按键")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(isCapturingHotkey ? "请直接按下快捷键..." : hotkeyDescription)
                                        .font(.system(size: 14, weight: .semibold))
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

                        Text("推荐热键：F6 / F7 / F8（如键盘需要可配合 Fn）。按住说话松开结束；双击快捷键进入连续模式，再按一次结束。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("运行状态:")
                            Spacer()
                            Text(hotkeyRuntimeStatus)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text("连续模式说明：双击快捷键开始持续收音，期间松开按键不会结束；再次按下同一快捷键即结束并进入改写。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // 语音终端
                    SettingsSection(title: "语音终端 (Mode 2)", icon: "terminal") {
                        Toggle("启用语音终端", isOn: $terminalHotkeyEnabled)
                            .toggleStyle(.switch)

                        Button {
                            if isCapturingTerminalHotkey {
                                stopTerminalHotkeyCapture()
                            } else {
                                startTerminalHotkeyCapture()
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("终端激活按键")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(isCapturingTerminalHotkey ? "请直接按下快捷键..." : terminalHotkeyDescription)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.primary)
                                }
                                Spacer()
                                Image(systemName: isCapturingTerminalHotkey ? "keyboard.badge.ellipsis" : "keyboard")
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
                                    .stroke(isCapturingTerminalHotkey ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)

                        Text(terminalHotkeyCaptureHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("按住快捷键说话，松开后 AI 识别意图并执行（日历/笔记/打开App/命令）。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // 输入风格
                    SettingsSection(title: "输入风格", icon: "wand.and.stars") {
                        VStack(spacing: 8) {
                            ForEach(styles, id: \.id) { style in
                                StyleButton(
                                    id: style.id,
                                    name: style.name,
                                    icon: style.icon,
                                    desc: style.desc,
                                    isSelected: selectedStyle == style.id
                                ) {
                                    selectedStyle = style.id
                                }
                            }
                        }
                    }

                    SettingsSection(title: "Thinking (LLM)", icon: "brain.head.profile") {
                        Toggle("启用 AI 润色", isOn: $llmEnabled)
                            .toggleStyle(.switch)

                        HStack {
                            Text("当前模型")
                            Spacer()
                            Text(llmModel.isEmpty ? "未设置" : llmModel)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        DisclosureGroup("高级设置", isExpanded: $showAdvancedLLM) {
                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("API Base URL")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("https://oneapi.gemiaude.com/v1", text: $llmAPIBaseURL)
                                        .textFieldStyle(.roundedBorder)
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("API Key")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    SecureField("Bearer token (>=10 chars)", text: $llmAPIKey)
                                        .textFieldStyle(.roundedBorder)
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("模型")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("gemini-2.5-flash-lite", text: $llmModel)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }

                    SettingsSection(title: "音频", icon: "speaker.wave.2") {
                        Toggle("语音输入时静音其他音频", isOn: $muteExternalAudioDuringInput)
                            .toggleStyle(.switch)
                        Toggle("交互提示音", isOn: $interactionSoundEnabled)
                            .toggleStyle(.switch)
                        Text("语音终端各阶段播放系统提示音 (聆听/确认/成功/失败)。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    SettingsSection(title: "应用行为", icon: "macwindow") {
                        Toggle("登录时启动应用", isOn: $launchAtLoginEnabled)
                            .toggleStyle(.switch)
                        Toggle("在 Dock 中显示应用", isOn: $showInDockEnabled)
                            .toggleStyle(.switch)
                        if !launchAtLoginMessage.isEmpty {
                            Text(launchAtLoginMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsSection(title: "隐私与历史", icon: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
                        Toggle("保存历史记录（最多 100 条）", isOn: $saveHistoryEnabled)
                            .toggleStyle(.switch)
                        HStack {
                            Button("清空历史记录") {
                                InputHistoryStore.shared.clear()
                            }
                            .buttonStyle(.bordered)

                            Text("仅清空本地记录")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 权限状态
                    SettingsSection(title: "权限状态", icon: "lock.shield") {
                        PermissionStatusRow()
                    }

                    SettingsSection(title: "权限诊断", icon: "stethoscope") {
                        VStack(alignment: .leading, spacing: 8) {
                            DiagnosticRow(title: "Bundle ID", value: diagnostics.bundleID)
                            DiagnosticRow(title: "可执行路径", value: diagnostics.executablePath)
                            DiagnosticRow(title: "路径稳定性", value: diagnostics.inApplications ? "已固定 (/Applications)" : "临时路径 (建议安装到 /Applications)")
                            DiagnosticRow(title: "AX API", value: diagnostics.accessibilityAXAPI ? "已授权" : "未授权")
                            DiagnosticRow(title: "TCC 数据库", value: diagnostics.accessibilityTCC ? "已授权" : "未授权")
                            DiagnosticRow(title: "语音识别", value: diagnostics.speechAuthorized ? "已授权" : "未授权")
                            DiagnosticRow(title: "麦克风", value: diagnostics.microphoneAuthorized ? "已授权" : "未授权")
                            HStack {
                                Button("刷新诊断") {
                                    diagnostics = PermissionDiagnostics.snapshot()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                if !diagnostics.inApplications {
                                    Text("建议使用 /Applications/VoiceInput.app 启动")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }

                    // 使用说明
                    SettingsSection(title: "使用说明", icon: "questionmark.circle") {
                        VStack(alignment: .leading, spacing: 12) {
                            UsageRow(icon: "keyboard", text: "按 Option + Space 激活语音输入")
                            UsageRow(icon: "text.bubble", text: "说话完成后自动识别并输入文字")
                            UsageRow(icon: "hand.tap", text: "在系统偏好设置中添加输入法")
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            if !embedded {
                HStack {
                    Button("重新引导") {
                        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
                        NotificationCenter.default.post(name: .restartOnboarding, object: nil)
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("打开输入法设置") {
                        openInputMethodSettings()
                    }
                    .buttonStyle(.bordered)

                    Button("打开系统设置") {
                        openSystemPreferences()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .frame(
            minWidth: embedded ? 720 : 520,
            maxWidth: .infinity,
            minHeight: embedded ? 560 : 560
        )
        .onAppear {
            SharedSettings.bootstrapDefaults()
            syncFromSharedDefaults()
            diagnostics = PermissionDiagnostics.snapshot()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            refreshHotkeyRuntimeStatus()
            diagnostics = PermissionDiagnostics.snapshot()
        }
        .onChange(of: selectedStyle) { _ in
            syncToSharedDefaults()
        }
        .onChange(of: hotkeyEnabled) { _ in
            syncToSharedDefaults()
        }
        .onChange(of: hotkeyModifiers) { _ in
            syncToSharedDefaults()
        }
        .onChange(of: hotkeyKeyCode) { _ in
            syncToSharedDefaults()
        }
        .onChange(of: hotkeyHoldToStopThreshold) { _ in
            syncToSharedDefaults()
        }
        .onChange(of: terminalHotkeyEnabled) { _ in
            syncToSharedDefaults()
        }
        .onChange(of: terminalHotkeyModifiers) { _ in
            syncToSharedDefaults()
        }
        .onChange(of: terminalHotkeyKeyCode) { _ in
            syncToSharedDefaults()
        }
        .onChange(of: llmEnabled) { _ in
            syncToSharedDefaults()
        }
        .onChange(of: llmAPIBaseURL) { _ in
            syncToSharedDefaults()
        }
        .onChange(of: llmAPIKey) { _ in
            syncToSharedDefaults()
        }
        .onChange(of: llmModel) { _ in
            syncToSharedDefaults()
        }
        .onChange(of: saveHistoryEnabled) { _ in
            syncToSharedDefaults()
        }
        .onChange(of: muteExternalAudioDuringInput) { _ in
            syncToSharedDefaults()
        }
        .onChange(of: interactionSoundEnabled) { _ in
            syncToSharedDefaults()
        }
        .onChange(of: launchAtLoginEnabled) { enabled in
            syncToSharedDefaults()
            launchAtLoginMessage = AppBehaviorController.applyLaunchAtLogin(enabled: enabled) ?? ""
        }
        .onChange(of: showInDockEnabled) { enabled in
            syncToSharedDefaults()
            AppBehaviorController.applyDockVisibility(showInDock: enabled)
        }
        .onDisappear {
            stopHotkeyCapture()
            stopTerminalHotkeyCapture()
        }
    }

    private func openInputMethodSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?InputSources")!
        NSWorkspace.shared.open(url)
    }

    private func openSystemPreferences() {
        let url = URL(string: "x-apple.systempreferences:")!
        NSWorkspace.shared.open(url)
    }

    private var hotkeyDescription: String {
        if hotkeyModifiers == 0 {
            return HotkeyConfig.keyTitle(for: hotkeyKeyCode)
        }
        return "\(HotkeyConfig.modifierTitle(for: hotkeyModifiers)) + \(HotkeyConfig.keyTitle(for: hotkeyKeyCode))"
    }

    private func syncFromSharedDefaults() {
        let defaults = SharedSettings.defaults
        selectedStyle = defaults.string(forKey: SharedSettings.Keys.selectedStyle) ?? selectedStyle
        hotkeyEnabled = defaults.object(forKey: SharedSettings.Keys.hotkeyEnabled) as? Bool ?? hotkeyEnabled
        hotkeyModifiers = defaults.object(forKey: SharedSettings.Keys.hotkeyModifiers) as? Int ?? hotkeyModifiers
        hotkeyKeyCode = defaults.object(forKey: SharedSettings.Keys.hotkeyKeyCode) as? Int ?? hotkeyKeyCode
        hotkeyHoldToStopThreshold = defaults.object(forKey: SharedSettings.Keys.hotkeyHoldToStopThreshold) as? Double ?? hotkeyHoldToStopThreshold
        terminalHotkeyEnabled = defaults.object(forKey: SharedSettings.Keys.terminalHotkeyEnabled) as? Bool ?? false
        terminalHotkeyModifiers = defaults.object(forKey: SharedSettings.Keys.terminalHotkeyModifiers) as? Int ?? 4096
        terminalHotkeyKeyCode = defaults.object(forKey: SharedSettings.Keys.terminalHotkeyKeyCode) as? Int ?? 49
        llmEnabled = defaults.object(forKey: SharedSettings.Keys.llmEnabled) as? Bool ?? false
        llmAPIBaseURL = defaults.string(forKey: SharedSettings.Keys.llmAPIBaseURL) ?? llmAPIBaseURL
        llmAPIKey = defaults.string(forKey: SharedSettings.Keys.llmAPIKey) ?? llmAPIKey
        llmModel = defaults.string(forKey: SharedSettings.Keys.llmModel) ?? llmModel
        saveHistoryEnabled = defaults.object(forKey: SharedSettings.Keys.saveHistoryEnabled) as? Bool ?? true
        muteExternalAudioDuringInput = defaults.object(forKey: SharedSettings.Keys.muteExternalAudioDuringInput) as? Bool ?? true
        interactionSoundEnabled = defaults.object(forKey: SharedSettings.Keys.interactionSoundEnabled) as? Bool ?? false
        launchAtLoginEnabled = defaults.object(forKey: SharedSettings.Keys.launchAtLoginEnabled) as? Bool ?? false
        showInDockEnabled = defaults.object(forKey: SharedSettings.Keys.showInDockEnabled) as? Bool ?? true
        hotkeyRuntimeStatus = defaults.string(forKey: SharedSettings.Keys.hotkeyRuntimeStatus) ?? "等待注册"
        sanitizeHotkeyIfNeeded()
    }

    private func syncToSharedDefaults() {
        let defaults = SharedSettings.defaults
        defaults.set(selectedStyle, forKey: SharedSettings.Keys.selectedStyle)
        defaults.set(hotkeyEnabled, forKey: SharedSettings.Keys.hotkeyEnabled)
        defaults.set(hotkeyModifiers, forKey: SharedSettings.Keys.hotkeyModifiers)
        defaults.set(hotkeyKeyCode, forKey: SharedSettings.Keys.hotkeyKeyCode)
        defaults.set(hotkeyHoldToStopThreshold, forKey: SharedSettings.Keys.hotkeyHoldToStopThreshold)
        defaults.set(terminalHotkeyEnabled, forKey: SharedSettings.Keys.terminalHotkeyEnabled)
        defaults.set(terminalHotkeyModifiers, forKey: SharedSettings.Keys.terminalHotkeyModifiers)
        defaults.set(terminalHotkeyKeyCode, forKey: SharedSettings.Keys.terminalHotkeyKeyCode)
        defaults.set(llmEnabled, forKey: SharedSettings.Keys.llmEnabled)
        defaults.set(llmAPIBaseURL, forKey: SharedSettings.Keys.llmAPIBaseURL)
        defaults.set(llmAPIKey, forKey: SharedSettings.Keys.llmAPIKey)
        defaults.set(llmModel, forKey: SharedSettings.Keys.llmModel)
        defaults.set(saveHistoryEnabled, forKey: SharedSettings.Keys.saveHistoryEnabled)
        defaults.set(muteExternalAudioDuringInput, forKey: SharedSettings.Keys.muteExternalAudioDuringInput)
        defaults.set(interactionSoundEnabled, forKey: SharedSettings.Keys.interactionSoundEnabled)
        defaults.set(launchAtLoginEnabled, forKey: SharedSettings.Keys.launchAtLoginEnabled)
        defaults.set(showInDockEnabled, forKey: SharedSettings.Keys.showInDockEnabled)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(SharedNotifications.hotkeyChanged),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func sanitizeHotkeyIfNeeded() {
        let validation = HotkeyConfig.validate(modifiers: hotkeyModifiers, keyCode: hotkeyKeyCode)
        guard !validation.isValid else { return }
        hotkeyModifiers = OptionSetFlag.optionSpaceModifiers.rawValue
        hotkeyKeyCode = OptionSetFlag.spaceKeyCode.rawValue
        hotkeyCaptureHint = "检测到冲突快捷键，已回退为 Option + Space"
        syncToSharedDefaults()
    }

    private func refreshHotkeyRuntimeStatus() {
        let status = SharedSettings.defaults.string(forKey: SharedSettings.Keys.hotkeyRuntimeStatus) ?? "等待注册"
        if status != hotkeyRuntimeStatus {
            hotkeyRuntimeStatus = status
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

            hotkeyModifiers = modifierFlags
            hotkeyKeyCode = keyCode
            hotkeyCaptureHint = "已保存：\(hotkeyDescription)"
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

    private var terminalHotkeyDescription: String {
        "\(HotkeyConfig.modifierTitle(for: terminalHotkeyModifiers)) + \(HotkeyConfig.keyTitle(for: terminalHotkeyKeyCode))"
    }

    private func startTerminalHotkeyCapture() {
        stopTerminalHotkeyCapture()
        isCapturingTerminalHotkey = true
        terminalHotkeyCaptureHint = "正在录入，按下任意键完成（Esc 取消）"

        localTerminalKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard isCapturingTerminalHotkey else { return event }
            if event.keyCode == 53 {
                terminalHotkeyCaptureHint = "已取消录入"
                stopTerminalHotkeyCapture()
                return nil
            }
            let modifiers = event.modifierFlags.intersection([.option, .command, .control, .shift])
            let modifierFlags = HotkeyConfig.carbonFlags(from: modifiers)
            let keyCode = Int(event.keyCode)
            let validation = HotkeyConfig.validate(modifiers: modifierFlags, keyCode: keyCode)
            guard validation.isValid else {
                terminalHotkeyCaptureHint = validation.message ?? "快捷键无效"
                return nil
            }

            terminalHotkeyModifiers = modifierFlags
            terminalHotkeyKeyCode = keyCode
            terminalHotkeyCaptureHint = "已保存：\(terminalHotkeyDescription)"
            stopTerminalHotkeyCapture()
            return nil
        }
    }

    private func stopTerminalHotkeyCapture() {
        isCapturingTerminalHotkey = false
        if let monitor = localTerminalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localTerminalKeyMonitor = nil
        }
    }

}

// MARK: - 设置区块
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.headline)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 使用说明行
struct UsageRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 权限状态行
struct PermissionStatusRow: View {
    @State private var micGranted = false
    @State private var speechGranted = false
    @State private var accessibilityGranted = false

    var body: some View {
        VStack(spacing: 8) {
            PermissionStatusItem(
                icon: "mic.fill",
                title: "麦克风",
                isGranted: micGranted
            )
            PermissionStatusItem(
                icon: "text.bubble",
                title: "语音识别",
                isGranted: speechGranted
            )
            PermissionStatusItem(
                icon: "hand.tap",
                title: "辅助功能",
                isGranted: accessibilityGranted
            )
        }
        .onAppear {
            refreshStatus()
            startPermissionPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
            startPermissionPolling()
        }
    }

    // 使用 Timer 持续轮询权限状态
    private func startPermissionPolling() {
        var count = 0
        let maxChecks = 20

        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            self.refreshStatus()
            count += 1
            if count >= maxChecks || self.accessibilityGranted {
                timer.invalidate()
            }
        }
    }

    // 旧方法保留用于手动刷新
    private func schedulePermissionRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.refreshStatus()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.refreshStatus()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.refreshStatus()
        }
    }

    private func refreshStatus() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }
}

struct PermissionStatusItem: View {
    let icon: String
    let title: String
    let isGranted: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(isGranted ? .green : .orange)
                .frame(width: 20)
            Text(title)
                .font(.subheadline)
            Spacer()
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isGranted ? .green : .red)
        }
    }
}

struct DiagnosticRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct HistoryItemCard: View {
    let item: InputHistoryItem
    @State private var showOriginal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.style)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(4)
                Text(statusLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(dateLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(item.finalText)
                .font(.subheadline)
                .lineLimit(3)

            if showOriginal {
                Text("原始: \(item.originalText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(showOriginal ? "隐藏原始" : "查看原始") {
                    showOriginal.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("复制改写") {
                    copy(item.finalText)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("复制原始") {
                    copy(item.originalText)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: item.timestamp))
    }

    private var statusLabel: String {
        switch item.status {
        case .inserted: return "已注入"
        case .pendingCopy: return "待手动复制"
        case .copied: return "已复制"
        }
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - 通知名称
extension Notification.Name {
    static let restartOnboarding = Notification.Name("restartOnboarding")
}

#Preview("Settings") {
    SettingsView()
}
