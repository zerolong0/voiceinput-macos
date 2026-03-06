import Cocoa
import SwiftUI
import Combine
import AVFoundation
import Speech
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow?
    var cancellables = Set<AnyCancellable>()
    private let hotkeyService = AppHotkeyVoiceService.shared
    private let voiceTerminalService = VoiceTerminalService.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateConflictingVoiceInputInstances()
        SharedSettings.bootstrapDefaults()
        AppBehaviorController.applyFromDefaults()
        hotkeyService.start()

        // 监听重启引导通知
        NotificationCenter.default.publisher(for: .restartOnboarding)
            .sink { [weak self] _ in
                self?.showOnboardingWindow()
            }
            .store(in: &cancellables)

        // 检查是否完成引导
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        if hasCompletedOnboarding {
            // 先主动请求 .notDetermined 的权限（重编译后系统会自动授权）
            resolveNotDeterminedPermissions { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if self.hasMissingPermissions() {
                        self.showPermissionRepairWindow()
                    } else {
                        self.showWorkspaceWindow()
                    }
                }
            }
        } else {
            showOnboardingWindow()
        }
    }

    func showOnboardingWindow() {
        let contentView = OnboardingView(
            onComplete: {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                self.showWorkspaceWindow()
            }
        )

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window?.title = "欢迎使用 VoiceInput"
        window?.contentView = NSHostingView(rootView: contentView)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showWorkspaceWindow() {
        window?.close()
        let rootView = MainWorkspaceView()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window?.title = "VoiceInput"
        window?.toolbar = nil
        window?.contentView = NSHostingView(rootView: rootView)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 对 .notDetermined 状态的权限主动发起请求，重编译后系统若已授权会自动通过
    private func resolveNotDeterminedPermissions(completion: @escaping () -> Void) {
        let group = DispatchGroup()

        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            group.enter()
            AVCaptureDevice.requestAccess(for: .audio) { _ in group.leave() }
        }

        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            group.enter()
            SFSpeechRecognizer.requestAuthorization { _ in group.leave() }
        }

        group.notify(queue: .main) { completion() }
    }

    private func hasMissingPermissions() -> Bool {
        let micOK = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let speechOK = SFSpeechRecognizer.authorizationStatus() == .authorized
        let axOK = AXIsProcessTrusted()
        return !(micOK && speechOK && axOK)
    }

    func showPermissionRepairWindow() {
        let contentView = PermissionRepairView(
            onContinue: { [weak self] in
                self?.showWorkspaceWindow()
            },
            onSkip: { [weak self] in
                self?.showWorkspaceWindow()
            }
        )

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window?.title = "VoiceInput - 权限修复"
        window?.contentView = NSHostingView(rootView: contentView)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    private func terminateConflictingVoiceInputInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let currentBundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath()

        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            guard app.processIdentifier != currentPID else { continue }

            let otherBundleURL = app.bundleURL?.resolvingSymlinksInPath()
            if otherBundleURL == currentBundleURL {
                continue
            }

            if !app.forceTerminate() {
                kill(app.processIdentifier, SIGKILL)
            }
        }
    }
}
