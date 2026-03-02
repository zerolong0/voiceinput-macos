import SwiftUI
import AVFoundation
import Speech
import ApplicationServices

// MARK: - 引导流程视图
struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var micGranted = false
    @State private var speechGranted = false
    @State private var accessibilityGranted = false

    private let steps = ["欢迎", "授权", "风格", "完成"]

    var body: some View {
        VStack(spacing: 0) {
            // 顶部进度
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index <= currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            // 步骤标题
            Text(steps[currentStep])
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.bottom, 16)

            // 内容
            Group {
                switch currentStep {
                case 0: WelcomeStepView()
                case 1: PermissionStepView(
                    micGranted: $micGranted,
                    speechGranted: $speechGranted,
                    accessibilityGranted: $accessibilityGranted
                )
                case 2: StyleStepView()
                case 3: CompletionStepView()
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 底部按钮
            HStack {
                if currentStep > 0 && currentStep < 3 {
                    Button("上一步") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button(currentStep < 3 ? "下一步" : "完成") {
                    if currentStep < 3 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentStep += 1
                        }
                    } else {
                        onComplete()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentStep == 1 && !canProceed())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 520, height: 480)
        .onAppear {
            refreshPermissionStatus()
            // 延迟刷新几次以确保获取到最新的权限状态
            schedulePermissionRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatus()
            // 应用激活时也延迟刷新几次
            schedulePermissionRefresh()
        }
    }

    // 延迟刷新权限状态，因为 macOS 可能需要一点时间更新权限缓存
    private func schedulePermissionRefresh() {
        // 0.5秒后刷新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.refreshPermissionStatus()
        }
        // 1秒后再次刷新
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.refreshPermissionStatus()
        }
        // 2秒后再次刷新
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.refreshPermissionStatus()
        }
    }

    private func canProceed() -> Bool {
        switch currentStep {
        case 1: return micGranted && speechGranted && accessibilityGranted
        default: return true
        }
    }

    private func refreshPermissionStatus() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        // 辅助功能权限检查
        // 优先使用 AXIsProcessTrusted() 获取最新状态
        accessibilityGranted = AXIsProcessTrusted()
        // 如果未授权，尝试带选项的检查（但不让系统弹窗）
        if !accessibilityGranted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
            accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        }
    }
}

// MARK: - 欢迎步骤
struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 20)

            Text("欢迎使用 VoiceInput")
                .font(.title)
                .fontWeight(.bold)

            Text("智能语音输入法，让你的输入更高效")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "mic.fill", title: "语音输入", desc: "按住说话，实时转文字")
                FeatureRow(icon: "wand.and.stars", title: "智能润色", desc: "自动删除填充词和重复内容")
                FeatureRow(icon: "cpu", title: "场景识别", desc: "自动识别输入场景，智能处理")
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
    }
}

// MARK: - 授权步骤
struct PermissionStepView: View {
    @Binding var micGranted: Bool
    @Binding var speechGranted: Bool
    @Binding var accessibilityGranted: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("需要以下权限以确保应用正常工作")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            VStack(spacing: 12) {
                PermissionRow(
                    icon: "mic.fill",
                    title: "麦克风",
                    desc: "用于语音输入",
                    isGranted: micGranted,
                    action: requestMicPermission
                )

                PermissionRow(
                    icon: "text.bubble",
                    title: "语音识别",
                    desc: "将语音转换为文字",
                    isGranted: speechGranted,
                    action: requestSpeechPermission
                )

                PermissionRow(
                    icon: "hand.tap",
                    title: "辅助功能",
                    desc: "全局快捷键和文本注入",
                    isGranted: accessibilityGranted,
                    action: openAccessibilitySettings
                )
            }
            .padding(.horizontal, 24)

            if !micGranted || !speechGranted || !accessibilityGranted {
                Text("点击「授权」后，在系统设置中开启对应权限，然后返回此应用")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Button {
                    // 手动刷新权限状态
                    refreshAllPermissions()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("刷新权限状态")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
    }

    private func refreshAllPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        if !accessibilityGranted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
            accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        }
    }

    private func requestMicPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                micGranted = granted
            }
        }
    }

    private func requestSpeechPermission() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                speechGranted = (status == .authorized)
            }
        }
    }

    private func openAccessibilitySettings() {
        // 先尝试触发系统授权对话框
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)

        if !granted {
            // 如果用户拒绝了对话框，打开系统设置让用户手动授权
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - 风格选择步骤
struct StyleStepView: View {
    @AppStorage("selectedStyle") private var selectedStyle = "default"

    private let styles: [(id: String, name: String, icon: String, desc: String)] = [
        ("default", "智能模式", "sparkles", "自动识别场景"),
        ("formal", "商务正式", "briefcase", "邮件、报告、文档"),
        ("casual", "日常聊天", "bubble.left.and.bubble.right", "微信、短信、社交"),
        ("vibe_coding", "Vibe Coding", "chevron.left.forwardslash.chevron.right", "编程、命令行")
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("选择你的默认使用风格")
                .font(.subheadline)
                .foregroundStyle(.secondary)

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
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - 完成步骤
struct CompletionStepView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .padding(.top, 20)

            Text("设置完成！")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 16) {
                NextStepRow(icon: "keyboard", title: "安装输入法", desc: "在系统键盘设置中添加 VoiceInputIM")
                NextStepRow(icon: "command", title: "使用快捷键", desc: "按 Option + Space 激活语音输入")
                NextStepRow(icon: "menubar.dock.rectangle", title: "常驻菜单栏", desc: "点击菜单栏图标可快速设置")
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
    }
}

// MARK: - 下一步指引组件
struct NextStepRow: View {
    let icon: String
    let title: String
    let desc: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - 组件

struct FeatureRow: View {
    let icon: String
    let title: String
    let desc: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let desc: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isGranted ? .green : .orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("授权") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
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
