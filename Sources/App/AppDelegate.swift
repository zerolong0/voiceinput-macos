import Cocoa
import SwiftUI
import Combine
import AVFoundation
import Speech

class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow?
    var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 监听重启引导通知
        NotificationCenter.default.publisher(for: .restartOnboarding)
            .sink { [weak self] _ in
                self?.showOnboardingWindow()
            }
            .store(in: &cancellables)

        // 检查是否完成引导
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        if hasCompletedOnboarding {
            showSettingsWindow()
        } else {
            showOnboardingWindow()
        }
    }

    func showOnboardingWindow() {
        let contentView = OnboardingView(
            onComplete: {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                self.showSettingsWindow()
            }
        )

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
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

    func showSettingsWindow() {
        let settingsView = SettingsView()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window?.title = "VoiceInput 设置"
        window?.contentView = NSHostingView(rootView: settingsView)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
