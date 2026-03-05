import Foundation
import AppKit
import Carbon

struct HotkeyModifierOption: Identifiable {
    let id: String
    let title: String
    let carbonFlags: Int
}

struct HotkeyKeyOption: Identifiable {
    let id: String
    let title: String
    let keyCode: Int
}

enum HotkeyConfig {
    static let modifierOptions: [HotkeyModifierOption] = [
        HotkeyModifierOption(id: "option", title: "Option", carbonFlags: optionKey),
        HotkeyModifierOption(id: "command", title: "Command", carbonFlags: cmdKey),
        HotkeyModifierOption(id: "control", title: "Control", carbonFlags: controlKey),
        HotkeyModifierOption(id: "shift", title: "Shift", carbonFlags: shiftKey),
        HotkeyModifierOption(id: "option_command", title: "Option + Command", carbonFlags: optionKey | cmdKey),
        HotkeyModifierOption(id: "control_shift", title: "Control + Shift", carbonFlags: controlKey | shiftKey)
    ]

    static let keyOptions: [HotkeyKeyOption] = [
        HotkeyKeyOption(id: "space", title: "Space", keyCode: 49),
        HotkeyKeyOption(id: "return", title: "Return", keyCode: 36),
        HotkeyKeyOption(id: "tab", title: "Tab", keyCode: 48),
        HotkeyKeyOption(id: "f6", title: "F6", keyCode: 97),
        HotkeyKeyOption(id: "f7", title: "F7", keyCode: 98),
        HotkeyKeyOption(id: "f8", title: "F8", keyCode: 100),
        HotkeyKeyOption(id: "1", title: "1", keyCode: 18),
        HotkeyKeyOption(id: "2", title: "2", keyCode: 19),
        HotkeyKeyOption(id: "3", title: "3", keyCode: 20),
        HotkeyKeyOption(id: "4", title: "4", keyCode: 21),
        HotkeyKeyOption(id: "5", title: "5", keyCode: 23),
        HotkeyKeyOption(id: "6", title: "6", keyCode: 22),
        HotkeyKeyOption(id: "7", title: "7", keyCode: 26),
        HotkeyKeyOption(id: "8", title: "8", keyCode: 28),
        HotkeyKeyOption(id: "9", title: "9", keyCode: 25),
        HotkeyKeyOption(id: "0", title: "0", keyCode: 29),
        HotkeyKeyOption(id: "v", title: "V", keyCode: 9),
        HotkeyKeyOption(id: "b", title: "B", keyCode: 11),
        HotkeyKeyOption(id: "n", title: "N", keyCode: 45),
        HotkeyKeyOption(id: "m", title: "M", keyCode: 46),
        HotkeyKeyOption(id: "k", title: "K", keyCode: 40)
    ]

    static func modifierTitle(for flags: Int) -> String {
        if flags == 0 { return "无修饰键" }
        return modifierOptions.first(where: { $0.carbonFlags == flags })?.title ?? "Flags \(flags)"
    }

    static func keyTitle(for keyCode: Int) -> String {
        keyOptions.first(where: { $0.keyCode == keyCode })?.title ?? "KeyCode \(keyCode)"
    }

    static func carbonFlags(from modifiers: NSEvent.ModifierFlags) -> Int {
        var flags = 0
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        return flags
    }

    static func isModifierOnlyKeyCode(_ keyCode: Int) -> Bool {
        // Common modifier key codes on macOS keyboards.
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }

    static func validate(modifiers: Int, keyCode: Int) -> (isValid: Bool, message: String?) {
        if keyCode < 0 {
            return (false, "无效按键")
        }
        if isModifierOnlyKeyCode(keyCode) {
            return (false, "请搭配一个非修饰键（如 F6、Space、B 等）")
        }
        // 单键（无修饰键）直接通过，Carbon RegisterEventHotKey 支持单键注册
        return (true, nil)
    }
}

enum SharedNotifications {
    static let hotkeyChanged = "com.voiceinput.hotkey.changed"
}
