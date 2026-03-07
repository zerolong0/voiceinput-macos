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
        static let llmMaxTokens = "llmMaxTokens"
        static let llmTimeoutSeconds = "llmTimeoutSeconds"
        static let llmRetryCount = "llmRetryCount"
        static let saveHistoryEnabled = "saveHistoryEnabled"
        static let muteExternalAudioDuringInput = "muteExternalAudioDuringInput"
        static let preferredInputDeviceUID = "preferredInputDeviceUID"
        static let interactionSoundEnabled = "interactionSoundEnabled"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
        static let showInDockEnabled = "showInDockEnabled"
        static let terminalHotkeyEnabled = "terminalHotkeyEnabled"
        static let terminalHotkeyModifiers = "terminalHotkeyModifiers"
        static let terminalHotkeyKeyCode = "terminalHotkeyKeyCode"
        static let terminalHotkeyRuntimeStatus = "terminalHotkeyRuntimeStatus"
        static let customRewritePrompt = "customRewritePrompt"
        static let customIntentPrompt = "customIntentPrompt"
        static let agentModel = "agentModel"
        static let voiceInputModel = "voiceInputModel"
    }

    static func customRewritePromptKey(for style: String) -> String {
        "customRewritePrompt_\(style)"
    }

    static let presetModels: [(id: String, label: String)] = [
        ("gemini-2.5-flash",      "Gemini 2.5 Flash"),
        ("gemini-2.5-flash-lite", "Gemini 2.5 Flash Lite（默认快速）"),
        ("gemini-2.5-pro",        "Gemini 2.5 Pro"),
        ("gpt-4o",                "GPT-4o"),
        ("gpt-4o-mini",           "GPT-4o Mini"),
        ("claude-sonnet-4-6",     "Claude Sonnet 4.6"),
        ("claude-haiku-4-5",      "Claude Haiku 4.5"),
    ]

    static func bootstrapDefaults() {
        if defaults.object(forKey: Keys.selectedStyle) == nil {
            defaults.set("default", forKey: Keys.selectedStyle)
        }
        if defaults.object(forKey: Keys.hotkeyEnabled) == nil {
            defaults.set(true, forKey: Keys.hotkeyEnabled)
        }
        if defaults.object(forKey: Keys.hotkeyModifiers) == nil {
            defaults.set(HotkeyConfig.defaultModifiers, forKey: Keys.hotkeyModifiers)
        }
        if defaults.object(forKey: Keys.hotkeyKeyCode) == nil {
            defaults.set(HotkeyConfig.defaultKeyCode, forKey: Keys.hotkeyKeyCode)
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
        if defaults.object(forKey: Keys.llmMaxTokens) == nil {
            defaults.set(2048, forKey: Keys.llmMaxTokens)
        }
        if defaults.object(forKey: Keys.llmTimeoutSeconds) == nil {
            defaults.set(30.0, forKey: Keys.llmTimeoutSeconds)
        }
        if defaults.object(forKey: Keys.llmRetryCount) == nil {
            defaults.set(2, forKey: Keys.llmRetryCount)
        }
        if defaults.object(forKey: Keys.saveHistoryEnabled) == nil {
            defaults.set(true, forKey: Keys.saveHistoryEnabled)
        }
        if defaults.object(forKey: Keys.muteExternalAudioDuringInput) == nil {
            defaults.set(true, forKey: Keys.muteExternalAudioDuringInput)
        }
        if defaults.string(forKey: Keys.preferredInputDeviceUID) == nil {
            defaults.set("", forKey: Keys.preferredInputDeviceUID)
        }
        if defaults.object(forKey: Keys.interactionSoundEnabled) == nil {
            defaults.set(true, forKey: Keys.interactionSoundEnabled)
        }
        if defaults.object(forKey: Keys.launchAtLoginEnabled) == nil {
            defaults.set(false, forKey: Keys.launchAtLoginEnabled)
        }
        if defaults.object(forKey: Keys.showInDockEnabled) == nil {
            defaults.set(true, forKey: Keys.showInDockEnabled)
        }
        if defaults.object(forKey: Keys.terminalHotkeyEnabled) == nil {
            defaults.set(true, forKey: Keys.terminalHotkeyEnabled)
        }
        if defaults.object(forKey: Keys.terminalHotkeyModifiers) == nil {
            defaults.set(HotkeyConfig.defaultTerminalModifiers, forKey: Keys.terminalHotkeyModifiers)
        }
        if defaults.object(forKey: Keys.terminalHotkeyKeyCode) == nil {
            defaults.set(HotkeyConfig.defaultTerminalKeyCode, forKey: Keys.terminalHotkeyKeyCode)
        }
        if defaults.string(forKey: Keys.terminalHotkeyRuntimeStatus) == nil {
            defaults.set("等待注册", forKey: Keys.terminalHotkeyRuntimeStatus)
        }
        if defaults.string(forKey: Keys.customRewritePrompt) == nil {
            defaults.set("", forKey: Keys.customRewritePrompt)
        }
        if defaults.string(forKey: Keys.customIntentPrompt) == nil {
            defaults.set("", forKey: Keys.customIntentPrompt)
        }
        if defaults.string(forKey: Keys.agentModel)?.isEmpty ?? true {
            // Migrate from llmModel if present, otherwise use default
            let migrated = defaults.string(forKey: Keys.llmModel) ?? "gemini-2.5-flash-lite"
            defaults.set(migrated, forKey: Keys.agentModel)
        }
        if defaults.string(forKey: Keys.voiceInputModel)?.isEmpty ?? true {
            defaults.set("gemini-2.5-flash-lite", forKey: Keys.voiceInputModel)
        }
    }
}

enum OptionSetFlag: Int {
    case optionSpaceModifiers = 2048
    case spaceKeyCode = 49
}
