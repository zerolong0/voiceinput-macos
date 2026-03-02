import Foundation

enum SharedSettings {
    private static let suiteName = "com.voiceinput.shared"
    static let defaults: UserDefaults = UserDefaults(suiteName: suiteName) ?? .standard

    enum Keys {
        static let selectedStyle = "selectedStyle"
        static let hotkeyEnabled = "hotkeyEnabled"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyHoldToStopThreshold = "hotkeyHoldToStopThreshold"
        static let hotkeyRuntimeStatus = "hotkeyRuntimeStatus"
        static let imHotkeyEnabled = "imHotkeyEnabled"
        static let llmEnabled = "llmEnabled"
        static let llmAPIBaseURL = "llmAPIBaseURL"
        static let llmAPIKey = "llmAPIKey"
        static let llmModel = "llmModel"
        static let saveHistoryEnabled = "saveHistoryEnabled"
        static let muteExternalAudioDuringInput = "muteExternalAudioDuringInput"
        static let interactionSoundEnabled = "interactionSoundEnabled"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
        static let showInDockEnabled = "showInDockEnabled"
    }

    static func bootstrapDefaults() {
        if defaults.object(forKey: Keys.selectedStyle) == nil {
            defaults.set("default", forKey: Keys.selectedStyle)
        }
        if defaults.object(forKey: Keys.hotkeyEnabled) == nil {
            defaults.set(true, forKey: Keys.hotkeyEnabled)
        }
        if defaults.object(forKey: Keys.hotkeyModifiers) == nil {
            defaults.set(OptionSetFlag.optionSpaceModifiers.rawValue, forKey: Keys.hotkeyModifiers)
        }
        if defaults.object(forKey: Keys.hotkeyKeyCode) == nil {
            defaults.set(OptionSetFlag.spaceKeyCode.rawValue, forKey: Keys.hotkeyKeyCode)
        }
        if defaults.string(forKey: Keys.hotkeyRuntimeStatus) == nil {
            defaults.set("等待注册", forKey: Keys.hotkeyRuntimeStatus)
        }
        if defaults.object(forKey: Keys.hotkeyHoldToStopThreshold) == nil {
            defaults.set(0.35, forKey: Keys.hotkeyHoldToStopThreshold)
        }
        if defaults.object(forKey: Keys.imHotkeyEnabled) == nil {
            defaults.set(false, forKey: Keys.imHotkeyEnabled)
        }
        if defaults.object(forKey: Keys.llmEnabled) == nil {
            defaults.set(false, forKey: Keys.llmEnabled)
        }
        if defaults.string(forKey: Keys.llmAPIBaseURL)?.isEmpty ?? true {
            defaults.set("https://oneapi.gemiaude.com/v1", forKey: Keys.llmAPIBaseURL)
        }
        if defaults.string(forKey: Keys.llmModel)?.isEmpty ?? true {
            defaults.set("gemini-2.5-flash-lite", forKey: Keys.llmModel)
        }
        if defaults.object(forKey: Keys.saveHistoryEnabled) == nil {
            defaults.set(true, forKey: Keys.saveHistoryEnabled)
        }
        if defaults.object(forKey: Keys.muteExternalAudioDuringInput) == nil {
            defaults.set(true, forKey: Keys.muteExternalAudioDuringInput)
        }
        if defaults.object(forKey: Keys.interactionSoundEnabled) == nil {
            defaults.set(false, forKey: Keys.interactionSoundEnabled)
        }
        if defaults.object(forKey: Keys.launchAtLoginEnabled) == nil {
            defaults.set(false, forKey: Keys.launchAtLoginEnabled)
        }
        if defaults.object(forKey: Keys.showInDockEnabled) == nil {
            defaults.set(true, forKey: Keys.showInDockEnabled)
        }
    }
}

enum OptionSetFlag: Int {
    case optionSpaceModifiers = 2048
    case spaceKeyCode = 49
}
