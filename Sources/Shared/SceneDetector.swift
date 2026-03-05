import Foundation
import AppKit
import Carbon

/// 应用场景类型
enum AppScene: String, CaseIterable {
    case email = "email"
    case chat = "chat"
    case coding = "coding"
    case vibeCoding = "vibe_coding"
    case social = "social"
    case formal = "formal"
    case casual = "casual"
    case unknown = "default"

    var displayName: String {
        switch self {
        case .email: return "邮件"
        case .chat: return "聊天"
        case .coding: return "编程"
        case .vibeCoding: return "Vibe Coding"
        case .social: return "社交媒体"
        case .formal: return "正式"
        case .casual: return "休闲"
        case .unknown: return "自动"
        }
    }

    /// 对应的 API 风格
    var apiStyle: String {
        switch self {
        case .email: return "email"
        case .chat: return "chat"
        case .coding: return "vibe_coding"
        case .vibeCoding: return "vibe_coding"
        case .social: return "social"
        case .formal: return "formal"
        case .casual: return "casual"
        case .unknown: return "default"
        }
    }
}

/// 场景检测配置
struct SceneConfig {
    let appBundleIds: Set<String>
    let windowKeywords: Set<String>
    let scene: AppScene
}

/// 场景检测器 - 自动识别用户当前应用场景
class SceneDetector {
    static let shared = SceneDetector()

    private init() {}

    // 场景配置
    private let sceneConfigs: [SceneConfig] = [
        // Email 应用
        SceneConfig(
            appBundleIds: [
                "com.apple.mail",
                "com.microsoft.Outlook",
                "com.tinyspeck.slackmacgap",  // Slack
                "com.hnc.Discord",
                "com.tencent.xinWeChat"  // 微信
            ],
            windowKeywords: ["inbox", "mail", "收件箱", "邮箱"],
            scene: .email
        ),
        // Chat 应用
        SceneConfig(
            appBundleIds: [
                "com.tencent.xinWeChat",  // 微信
                "com.ali.DingTalk",  // 钉钉
                "com.tinyspeck.slackmacgap",  // Slack
                "com.hnc.Discord",  // Discord
                "com.apple.MobileSMS",  // iMessage
                "ru.keepcoder.Telegram",  // Telegram
                "net.whatsapp.WhatsApp"  // WhatsApp
            ],
            windowKeywords: ["chat", "message", "对话", "消息", "聊天"],
            scene: .chat
        ),
        // 编程/开发工具
        SceneConfig(
            appBundleIds: [
                "com.microsoft.VSCode",
                "com.apple.dt.Xcode",
                "com.sublimetext.4",
                "com.jetbrains.intellij",
                "com.jetbrains.pycharm",
                "com.googlecode.iterm2",
                "com.apple.Terminal",
                "com.github.atom"
            ],
            windowKeywords: [
                "terminal", "console", "终端", "git",
                "codex", "agent", "claude code", "autoglm",
                "web coding", "frontend", "backend"
            ],
            scene: .coding
        ),
        // Vibe Coding (代码相关网页)
        SceneConfig(
            appBundleIds: [
                "com.apple.Safari",
                "com.google.Chrome",
                "com.microsoft.edgemac"
            ],
            windowKeywords: [
                "github", "gitlab", "stackoverflow", "Stack Overflow",
                "code", "coding", "developer", "documentation",
                "api", "docs", "reference", "tutorial",
                "codepen", "jsfiddle", "replit"
            ],
            scene: .vibeCoding
        ),
        // 社交媒体
        SceneConfig(
            appBundleIds: [
                "com.apple.Safari",
                "com.google.Chrome",
                "com.microsoft.edgemac",
                "com.twitter.twitter-mac",  // Twitter
                "com.atebits.Tweetie2"
            ],
            windowKeywords: [
                "twitter", "tweet", "x.com",
                "weibo", "微博",
                "xiaohongshu", "小红书",
                "reddit", "facebook", "instagram",
                "linkedin", "youtube", "bilibili"
            ],
            scene: .social
        ),
        // 正式场景 (Office 应用)
        SceneConfig(
            appBundleIds: [
                "com.microsoft.Word",
                "com.microsoft.Excel",
                "com.microsoft.Powerpoint",
                "com.apple.iWork.Pages",
                "com.apple.iWork.Numbers",
                "com.apple.iWork.Keynote",
                "com.notion.id",
                "com.electron.obsidian"
            ],
            windowKeywords: ["doc", "document", "sheet", "presentation", "文档", "笔记"],
            scene: .formal
        )
    ]

    /// 检测当前应用场景
    /// - Returns: 识别出的场景类型
    func detectCurrentScene() -> AppScene {
        // 1. 获取当前活动应用
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return .unknown
        }

        let bundleId = frontApp.bundleIdentifier ?? ""
        let appName = frontApp.localizedName ?? ""

        // 2. 尝试获取当前窗口标题
        let windowTitle = getCurrentWindowTitle()

        // 3. 根据应用和窗口标题匹配场景
        for config in sceneConfigs {
            // 检查 bundle ID
            if config.appBundleIds.contains(bundleId) {
                // 如果有关键字，进一步确认
                if let title = windowTitle?.lowercased() {
                    for keyword in config.windowKeywords {
                        if title.contains(keyword.lowercased()) {
                            return config.scene
                        }
                    }
                }
                // 没有特定窗口标题时，返回默认场景
                return config.scene
            }

            // 检查窗口标题中的关键字（适用于浏览器等）
            if let title = windowTitle?.lowercased() {
                for keyword in config.windowKeywords {
                    if title.contains(keyword.lowercased()) {
                        return config.scene
                    }
                }
            }
        }

        // 4. 根据应用名称推断
        return inferSceneFromAppName(appName)
    }

    /// 从应用名称推断场景
    private func inferSceneFromAppName(_ appName: String) -> AppScene {
        let name = appName.lowercased()

        // 邮件
        if name.contains("mail") || name.contains("outlook") || name.contains("邮箱") {
            return .email
        }

        // 聊天
        if name.contains("wechat") || name.contains("微信") ||
           name.contains("dingtalk") || name.contains("钉钉") ||
           name.contains("slack") || name.contains("discord") ||
           name.contains("telegram") || name.contains("whatsapp") ||
           name.contains("message") || name.contains("短信") {
            return .chat
        }

        // 编程
        if name.contains("xcode") || name.contains("vscode") ||
           name.contains("terminal") || name.contains("terminal") ||
           name.contains("iterm") || name.contains("pycharm") ||
           name.contains("intellij") || name.contains("sublime") ||
           name.contains("atom") || name.contains("terminal") {
            return .coding
        }

        // 社交
        if name.contains("twitter") || name.contains("x") ||
           name.contains("weibo") || name.contains("微博") ||
           name.contains("xiaohongshu") || name.contains("小红书") ||
           name.contains("reddit") || name.contains("facebook") ||
           name.contains("instagram") || name.contains("bilibili") ||
           name.contains("youtube") || name.contains("linkedin") {
            return .social
        }

        // 正式文档
        if name.contains("word") || name.contains("pages") ||
           name.contains("excel") || name.contains("numbers") ||
           name.contains("powerpoint") || name.contains("keynote") ||
           name.contains("notion") || name.contains("obsidian") ||
           name.contains("文档") || name.contains("笔记") {
            return .formal
        }

        // 默认返回智能模式
        return .unknown
    }

    /// 获取当前窗口标题
    func getCurrentWindowTitle() -> String? {
        // 使用 AppleScript 获取当前窗口标题
        let script = """
        tell application "System Events"
            set frontApp to first application process whose frontmost is true
            set windowTitle to ""
            try
                set windowTitle to name of first window of frontApp
            end try
            return windowTitle
        end tell
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let output = scriptObject.executeAndReturnError(&error)
            if error == nil {
                return output.stringValue
            }
        }

        return nil
    }

    /// 获取当前活动应用的名称
    func getCurrentAppName() -> String? {
        return NSWorkspace.shared.frontmostApplication?.localizedName
    }

    /// 获取当前活动应用的 Bundle ID
    func getCurrentBundleId() -> String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}

// MARK: - 场景管理器
class SceneManager {
    static let shared = SceneManager()

    /// 是否启用自动场景检测
    var isAutoDetectEnabled: Bool = true

    /// 用户手动指定的场景（优先级高于自动检测）
    var manualScene: AppScene?

    private init() {
        // 从 UserDefaults 加载设置
        isAutoDetectEnabled = UserDefaults.standard.bool(forKey: "autoSceneDetect")
        if let manualSceneRaw = UserDefaults.standard.string(forKey: "manualScene"),
           let scene = AppScene(rawValue: manualSceneRaw) {
            manualScene = scene
        }
    }

    /// 获取当前应该使用的场景
    func getActiveScene() -> AppScene {
        // 手动指定优先
        if let manual = manualScene {
            return manual
        }

        // 自动检测
        if isAutoDetectEnabled {
            return SceneDetector.shared.detectCurrentScene()
        }

        // 默认
        return .unknown
    }

    /// 获取 API 风格
    func getApiStyle() -> String {
        return getActiveScene().apiStyle
    }

    /// 设置手动场景
    func setManualScene(_ scene: AppScene?) {
        manualScene = scene
        UserDefaults.standard.set(scene?.rawValue, forKey: "manualScene")
    }

    /// 切换自动检测
    func setAutoDetect(_ enabled: Bool) {
        isAutoDetectEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "autoSceneDetect")
    }
}
