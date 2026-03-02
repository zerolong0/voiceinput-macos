import Cocoa
import SwiftUI
import Combine
import AVFoundation
import Speech

class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow?
    var cancellables = Set<AnyCancellable>()
    private let hotkeyService = AppHotkeyVoiceService.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            showWorkspaceWindow()
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
