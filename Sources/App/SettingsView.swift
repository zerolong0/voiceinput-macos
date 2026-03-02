import SwiftUI
import AVFoundation
import Speech

// MARK: - 设置视图
struct SettingsView: View {
    @AppStorage("selectedStyle") private var selectedStyle = "default"
    @AppStorage("hotkeyEnabled") private var hotkeyEnabled = true
    @AppStorage("hotkeyModifiers") private var hotkeyModifiers = 768 // Option (0x300)
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode = 49 // Space

    @State private var isRecording = false

    private let styles: [(id: String, name: String, icon: String, desc: String)] = [
        ("default", "智能模式", "sparkles", "自动识别场景"),
        ("formal", "商务正式", "briefcase", "邮件、报告、文档"),
        ("casual", "日常聊天", "bubble.left.and.bubble.right", "微信、短信、社交"),
        ("vibe_coding", "Vibe Coding", "chevron.left.forwardslash.chevron.right", "编程、命令行")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text("VoiceInput 设置")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // 内容
            ScrollView {
                VStack(spacing: 24) {
                    // 快捷键设置
                    SettingsSection(title: "快捷键", icon: "keyboard") {
                        Toggle("启用全局快捷键", isOn: $hotkeyEnabled)
                            .toggleStyle(.switch)

                        HStack {
                            Text("激活按键:")
                            Spacer()
                            Text("Option + Space")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
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

                    // 权限状态
                    SettingsSection(title: "权限状态", icon: "lock.shield") {
                        PermissionStatusRow()
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

            // 底部
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
        .frame(width: 520, height: 560)
    }

    private func openInputMethodSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?InputSources")!
        NSWorkspace.shared.open(url)
    }

    private func openSystemPreferences() {
        let url = URL(string: "x-apple.systempreferences:")!
        NSWorkspace.shared.open(url)
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
            schedulePermissionRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
            schedulePermissionRefresh()
        }
    }

    // 延迟刷新权限状态
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
        // 辅助功能权限检查
        accessibilityGranted = AXIsProcessTrusted()
        if !accessibilityGranted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
            accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        }
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

// MARK: - 通知名称
extension Notification.Name {
    static let restartOnboarding = Notification.Name("restartOnboarding")
}

#Preview("Settings") {
    SettingsView()
}
