import Foundation
import CoreAudio
import AppKit

enum SystemAction {
    case volumeUp
    case volumeDown
    case mute
    case unmute
    case setVolume(Float)
    case brightnessUp
    case brightnessDown
    case toggleDarkMode
    case lockScreen
    case sleep
    case toggleDND
    case screenshot
    case screenshotClipboard
    case toggleWiFi
    case unknown
}

final class SystemControlAgent {
    func execute(intent: RecognizedIntent) async -> CommandResult {
        let action = parseAction(from: intent.detail, title: intent.title)
        return await perform(action)
    }

    private func parseAction(from detail: String, title: String) -> SystemAction {
        let d = detail.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Structured detail parsing
        if d.hasPrefix("set_volume:") {
            let numStr = d.replacingOccurrences(of: "set_volume:", with: "")
            if let val = Float(numStr) { return .setVolume(min(100, max(0, val)) / 100.0) }
        }
        switch d {
        case "volume_up": return .volumeUp
        case "volume_down": return .volumeDown
        case "mute": return .mute
        case "unmute": return .unmute
        case "brightness_up": return .brightnessUp
        case "brightness_down": return .brightnessDown
        case "toggle_dark_mode": return .toggleDarkMode
        case "lock_screen": return .lockScreen
        case "sleep": return .sleep
        case "toggle_dnd": return .toggleDND
        case "screenshot": return .screenshot
        case "screenshot_clipboard": return .screenshotClipboard
        case "toggle_wifi": return .toggleWiFi
        default: break
        }

        // Fallback: Chinese keyword matching from title
        let t = title.lowercased()
        if t.contains("音量") {
            if t.contains("调高") || t.contains("大") { return .volumeUp }
            if t.contains("调低") || t.contains("小") { return .volumeDown }
            // Try to extract number
            if let range = t.range(of: #"\d+"#, options: .regularExpression) {
                if let val = Float(t[range]) { return .setVolume(min(100, max(0, val)) / 100.0) }
            }
        }
        if t.contains("静音") { return .mute }
        if t.contains("取消静音") { return .unmute }
        if t.contains("亮度") {
            if t.contains("高") || t.contains("亮") || t.contains("大") { return .brightnessUp }
            return .brightnessDown
        }
        if t.contains("深色") || t.contains("暗色") || t.contains("暗黑") || t.contains("dark") { return .toggleDarkMode }
        if t.contains("锁屏") || t.contains("锁定") { return .lockScreen }
        if t.contains("休眠") || t.contains("睡眠") { return .sleep }
        if t.contains("勿扰") || t.contains("免打扰") { return .toggleDND }
        if t.contains("截图") || t.contains("截屏") {
            if t.contains("剪贴板") || t.contains("粘贴板") { return .screenshotClipboard }
            return .screenshot
        }
        if t.contains("wifi") || t.contains("Wi-Fi") || t.contains("无线") { return .toggleWiFi }

        return .unknown
    }

    private func perform(_ action: SystemAction) async -> CommandResult {
        switch action {
        case .volumeUp:
            let current = getVolumeWithFallback()
            let newVol = min(1.0, current + 0.1)
            return setVolumeWithFallback(newVol)
        case .volumeDown:
            let current = getVolumeWithFallback()
            let newVol = max(0.0, current - 0.1)
            return setVolumeWithFallback(newVol)
        case .setVolume(let vol):
            return setVolumeWithFallback(vol)
        case .mute:
            return setMute(true)
        case .unmute:
            return setMute(false)
        case .brightnessUp:
            return runAppleScript(script: brightnessScript(up: true), successMsg: "亮度已调高")
        case .brightnessDown:
            return runAppleScript(script: brightnessScript(up: false), successMsg: "亮度已调低")
        case .toggleDarkMode:
            return runAppleScript(
                script: "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode",
                successMsg: "已切换深色模式"
            )
        case .lockScreen:
            return runProcess("/usr/bin/pmset", args: ["displaysleepnow"], successMsg: "已锁屏")
        case .sleep:
            return runProcess("/usr/bin/pmset", args: ["sleepnow"], successMsg: "正在休眠")
        case .toggleDND:
            return runProcess("/usr/bin/shortcuts", args: ["run", "Toggle Do Not Disturb"], successMsg: "已切换勿扰模式")
        case .screenshot:
            let path = screenshotPath()
            return runProcess("/usr/sbin/screencapture", args: ["-x", path], successMsg: "截图已保存到桌面")
        case .screenshotClipboard:
            return runProcess("/usr/sbin/screencapture", args: ["-c"], successMsg: "截图已复制到剪贴板")
        case .toggleWiFi:
            return await toggleWiFi()
        case .unknown:
            return CommandResult(success: false, message: "无法识别的系统控制命令")
        }
    }

    // MARK: - CoreAudio Volume

    private func getDefaultOutputDeviceID() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    private func getVolume() -> Float {
        let deviceID = getDefaultOutputDeviceID()
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        // Try channel 1, 2, then main (0)
        for ch in [UInt32(1), UInt32(2), UInt32(kAudioObjectPropertyElementMain)] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: ch
            )
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            let result = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
            if result == noErr { return volume }
        }
        return volume
    }

    private func setVolume(_ volume: Float) -> Bool {
        let deviceID = getDefaultOutputDeviceID()
        var vol = volume
        var didSet = false
        for ch in [UInt32(1), UInt32(2), UInt32(kAudioObjectPropertyElementMain)] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: ch
            )
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            var isSettable: DarwinBoolean = false
            AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
            guard isSettable.boolValue else { continue }
            let result = AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
            if result == noErr { didSet = true }
        }
        return didSet
    }

    private func setVolumeWithFallback(_ volume: Float) -> CommandResult {
        let set = setVolume(volume)
        if set {
            return CommandResult(success: true, message: "音量: \(Int(volume * 100))%")
        }
        // Fallback: AppleScript
        let pct = Int(volume * 100)
        return runAppleScript(script: "set volume output volume \(pct)", successMsg: "音量: \(pct)%")
    }

    private func setMute(_ mute: Bool) -> CommandResult {
        let deviceID = getDefaultOutputDeviceID()
        var value: UInt32 = mute ? 1 : 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &address) {
            var isSettable: DarwinBoolean = false
            AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
            if isSettable.boolValue {
                let result = AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
                if result == noErr {
                    return CommandResult(success: true, message: mute ? "已静音" : "已取消静音")
                }
            }
        }
        // Fallback: AppleScript
        let script = mute ? "set volume output muted true" : "set volume output muted false"
        return runAppleScript(script: script, successMsg: mute ? "已静音" : "已取消静音")
    }

    private func getVolumeWithFallback() -> Float {
        let v = getVolume()
        if v > 0 { return v }
        // Fallback: read via AppleScript
        var error: NSDictionary?
        if let s = NSAppleScript(source: "output volume of (get volume settings)") {
            let r = s.executeAndReturnError(&error)
            if error == nil, let str = r.stringValue, let val = Float(str) {
                return val / 100.0
            }
        }
        return 0.5 // safe default
    }

    private func screenshotPath() -> String {
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return desktop.appendingPathComponent("Screenshot \(formatter.string(from: Date())).png").path
    }

    // MARK: - Brightness (AppleScript key simulation)

    private func brightnessScript(up: Bool) -> String {
        let keyCode = up ? 144 : 145
        return """
        tell application "System Events"
            key code \(keyCode)
        end tell
        """
    }

    // MARK: - WiFi

    private func toggleWiFi() async -> CommandResult {
        // Check current state
        let checkProcess = Process()
        checkProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        checkProcess.arguments = ["-getairportpower", "en0"]
        let pipe = Pipe()
        checkProcess.standardOutput = pipe
        do {
            try checkProcess.run()
            checkProcess.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let isOn = output.lowercased().contains("on")
            let newState = isOn ? "off" : "on"
            return runProcess("/usr/sbin/networksetup", args: ["-setairportpower", "en0", newState],
                            successMsg: isOn ? "WiFi 已关闭" : "WiFi 已开启")
        } catch {
            return CommandResult(success: false, message: "WiFi 切换失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func runAppleScript(script: String, successMsg: String) -> CommandResult {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                return CommandResult(success: false, message: "执行失败: \(error)")
            }
            return CommandResult(success: true, message: successMsg)
        }
        return CommandResult(success: false, message: "脚本创建失败")
    }

    private func runProcess(_ path: String, args: [String], successMsg: String) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        do {
            try process.run()
            process.waitUntilExit()
            return CommandResult(success: process.terminationStatus == 0, message: process.terminationStatus == 0 ? successMsg : "命令执行失败")
        } catch {
            return CommandResult(success: false, message: "执行失败: \(error.localizedDescription)")
        }
    }
}
