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
    static let functionModifierFlag = Int(kEventKeyModifierFnMask)
    static let modifierMask = optionKey | cmdKey | controlKey | shiftKey | functionModifierFlag

    static let defaultModifiers = optionKey
    static let defaultKeyCode = 18
    static let defaultTerminalModifiers = optionKey
    static let defaultTerminalKeyCode = 19

    static let modifierOptions: [HotkeyModifierOption] = [
        HotkeyModifierOption(id: "option", title: "Option", carbonFlags: optionKey),
        HotkeyModifierOption(id: "command", title: "Command", carbonFlags: cmdKey),
        HotkeyModifierOption(id: "control", title: "Control", carbonFlags: controlKey),
        HotkeyModifierOption(id: "shift", title: "Shift", carbonFlags: shiftKey),
        HotkeyModifierOption(id: "function", title: "Fn", carbonFlags: functionModifierFlag),
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
        var parts: [String] = []
        if flags & controlKey != 0 { parts.append("Control") }
        if flags & optionKey != 0 { parts.append("Option") }
        if flags & shiftKey != 0 { parts.append("Shift") }
        if flags & cmdKey != 0 { parts.append("Command") }
        if flags & functionModifierFlag != 0 { parts.append("Fn") }
        if !parts.isEmpty { return parts.joined(separator: " + ") }
        return "Flags \(flags)"
    }

    static func keyTitle(for keyCode: Int) -> String {
        if let mapped = keyOptions.first(where: { $0.keyCode == keyCode })?.title {
            return mapped
        }

        // Common modifier key codes (left/right variants where applicable)
        switch keyCode {
        case 63: return "Fn"
        case 55, 54: return "Command"
        case 58, 61: return "Option"
        case 59, 62: return "Control"
        case 56, 60: return "Shift"
        case 57: return "Caps Lock"
        default: return "KeyCode \(keyCode)"
        }
    }

    static func displayString(modifiers: Int, keyCode: Int) -> String {
        if modifiers == 0 {
            return keyTitle(for: keyCode)
        }
        if isModifierOnlyKeyCode(keyCode), let flag = modifierFlag(for: keyCode), (modifiers & flag) != 0 {
            return modifierTitle(for: modifiers)
        }
        return "\(modifierTitle(for: modifiers)) + \(keyTitle(for: keyCode))"
    }

    static func carbonFlags(from modifiers: NSEvent.ModifierFlags) -> Int {
        var flags = 0
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.function) { flags |= functionModifierFlag }
        return flags
    }

    static func isModifierOnlyKeyCode(_ keyCode: Int) -> Bool {
        // Common modifier key codes on macOS keyboards.
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }

    static func modifierFlag(for keyCode: Int) -> Int? {
        switch keyCode {
        case 55, 54: return cmdKey
        case 58, 61: return optionKey
        case 59, 62: return controlKey
        case 56, 60: return shiftKey
        case 63: return functionModifierFlag
        default: return nil
        }
    }

    static func validate(modifiers: Int, keyCode: Int) -> (isValid: Bool, message: String?) {
        if keyCode < 0 {
            return (false, "无效按键")
        }
        // 不限制组合，允许用户自行设置；注册冲突在运行时提示。
        return (true, nil)
    }
}

enum SharedNotifications {
    static let hotkeyChanged = "com.voiceinput.hotkey.changed"
}
