import SwiftUI
import AVFoundation
import Speech
import ApplicationServices

struct PermissionRepairView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var micGranted = false
    @State private var speechGranted = false
    @State private var accessibilityGranted = false
    @State private var axSentToSettings = false  // user went to System Settings for AX
    @State private var pollTimer: Timer?

    private var allGranted: Bool {
        micGranted && speechGranted && accessibilityGranted
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("权限修复")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 8)

            Text("检测到部分权限缺失，应用需要以下权限才能正常工作。")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.bottom, 16)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 12) {
                if !micGranted {
                    PermissionActionRow(icon: "mic.fill", title: "麦克风", desc: "采集语音输入", granted: micGranted, buttonTitle: micButtonTitle) {
                        requestMicrophone()
                    }
                }

                if !speechGranted {
                    PermissionActionRow(icon: "text.bubble", title: "语音识别", desc: "本地实时转写", granted: speechGranted, buttonTitle: speechButtonTitle) {
                        requestSpeech()
                    }
                }

                if !accessibilityGranted {
                    if axSentToSettings {
                        // User came back from System Settings — AX needs restart to take effect
                        HStack(spacing: 10) {
                            Image(systemName: "hand.tap")
                                .foregroundStyle(.blue)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("辅助功能").font(.subheadline.weight(.semibold))
                                Text("授权后需重启应用才能生效").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                Button("立即重启") { restartApp() }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                Button("尚未授权") { axSentToSettings = false }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        PermissionActionRow(icon: "hand.tap", title: "辅助功能", desc: "自动注入文本", granted: false, buttonTitle: "去系统设置") {
                            requestAccessibility()
                        }
                    }
                }

                if allGranted {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("所有权限已就绪")
                            .font(.headline)
                            .foregroundStyle(.green)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 480)

            Spacer(minLength: 12)

            HStack {
                Button("暂时跳过") {
                    stopPolling()
                    onSkip()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("刷新状态") {
                    syncPermissions()
                }
                .buttonStyle(.bordered)

                Button("继续") {
                    stopPolling()
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!allGranted)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            syncPermissions()
            startPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            syncPermissions()
        }
        .onDisappear {
            stopPolling()
        }
    }

    private var micButtonTitle: String {
        AVCaptureDevice.authorizationStatus(for: .audio) == .denied ? "去系统设置" : "授权"
    }

    private var speechButtonTitle: String {
        SFSpeechRecognizer.authorizationStatus() == .denied ? "去系统设置" : "授权"
    }

    private func requestMicrophone() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .denied {
            openPrivacySettings("Privacy_Microphone")
        } else {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { micGranted = granted }
            }
        }
    }

    private func requestSpeech() {
        if SFSpeechRecognizer.authorizationStatus() == .denied {
            openPrivacySettings("Privacy_SpeechRecognition")
        } else {
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async { speechGranted = (status == .authorized) }
            }
        }
    }

    private func requestAccessibility() {
        axSentToSettings = true
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func restartApp() {
        let appURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in }
        NSApp.terminate(nil)
    }

    private func openPrivacySettings(_ anchor: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        NSWorkspace.shared.open(url)
    }

    private func syncPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        accessibilityGranted = AXIsProcessTrusted()
    }

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            syncPermissions()
            if allGranted {
                stopPolling()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
