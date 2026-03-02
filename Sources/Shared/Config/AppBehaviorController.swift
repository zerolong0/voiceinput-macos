import Cocoa
import ServiceManagement

enum AppBehaviorController {
    static func applyFromDefaults() {
        let defaults = SharedSettings.defaults
        let showInDock = defaults.object(forKey: SharedSettings.Keys.showInDockEnabled) as? Bool ?? true
        applyDockVisibility(showInDock: showInDock)

        let launchAtLogin = defaults.object(forKey: SharedSettings.Keys.launchAtLoginEnabled) as? Bool ?? false
        _ = applyLaunchAtLogin(enabled: launchAtLogin)
    }

    @discardableResult
    static func applyLaunchAtLogin(enabled: Bool) -> String? {
        guard #available(macOS 13.0, *) else {
            return "当前系统不支持开机启动配置"
        }
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
                return nil
            }
            if service.status == .enabled {
                try service.unregister()
            }
            return nil
        } catch {
            return "开机启动设置失败：\(error.localizedDescription)"
        }
    }

    static func applyDockVisibility(showInDock: Bool) {
        _ = NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }
}
