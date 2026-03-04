import Foundation
import AppKit

final class AppLauncherAgent {

    // 常见中文别名 → (英文名, Bundle ID)
    private static let aliasMap: [(aliases: [String], englishName: String, bundleID: String)] = [
        (["记事本", "苹果记事本", "苹果记事", "备忘录", "笔记"], "Notes", "com.apple.Notes"),
        (["日历", "苹果日历", "日程"], "Calendar", "com.apple.iCal"),
        (["邮件", "苹果邮件", "邮箱", "Mail"], "Mail", "com.apple.mail"),
        (["信息", "消息", "短信", "苹果信息", "iMessage"], "Messages", "com.apple.MobileSMS"),
        (["浏览器", "Safari浏览器", "苹果浏览器"], "Safari", "com.apple.Safari"),
        (["设置", "系统设置", "系统偏好设置", "偏好设置"], "System Settings", "com.apple.systempreferences"),
        (["终端", "命令行"], "Terminal", "com.apple.Terminal"),
        (["访达", "Finder", "文件管理器"], "Finder", "com.apple.finder"),
        (["音乐", "苹果音乐", "Apple Music", "iTunes"], "Music", "com.apple.Music"),
        (["照片", "苹果照片", "相册"], "Photos", "com.apple.Photos"),
        (["提醒事项", "提醒", "待办事项", "Reminders"], "Reminders", "com.apple.reminders"),
        (["地图", "苹果地图"], "Maps", "com.apple.Maps"),
        (["天气", "苹果天气"], "Weather", "com.apple.Weather"),
        (["时钟", "闹钟", "计时器"], "Clock", "com.apple.Clock"),
        (["计算器"], "Calculator", "com.apple.calculator"),
        (["预览", "图片预览"], "Preview", "com.apple.Preview"),
        (["文本编辑", "文本编辑器", "TextEdit"], "TextEdit", "com.apple.TextEdit"),
        (["活动监视器", "任务管理器"], "Activity Monitor", "com.apple.ActivityMonitor"),
        (["磁盘工具"], "Disk Utility", "com.apple.DiskUtility"),
        (["快捷指令", "Shortcuts"], "Shortcuts", "com.apple.shortcuts"),
        (["FaceTime", "FaceTime通话", "视频通话"], "FaceTime", "com.apple.FaceTime"),
        (["App Store", "应用商店", "苹果商店"], "App Store", "com.apple.AppStore"),
        (["Xcode", "开发工具"], "Xcode", "com.apple.dt.Xcode"),
        (["微信", "WeChat"], "WeChat", "com.tencent.xinWeChat"),
        (["钉钉", "DingTalk"], "DingTalk", "com.alibaba.DingTalkMac"),
        (["飞书", "Feishu", "Lark"], "Lark", "com.bytedance.macos.feishu"),
        (["腾讯会议", "VooV"], "腾讯会议", "com.tencent.meeting"),
        (["QQ"], "QQ", "com.tencent.qq"),
        (["网易云音乐"], "NeteaseMusic", "com.netease.163music"),
        (["VS Code", "VSCode", "Visual Studio Code", "代码编辑器"], "Visual Studio Code", "com.microsoft.VSCode"),
        (["Chrome", "谷歌浏览器", "Google Chrome"], "Google Chrome", "com.google.Chrome"),
        (["Firefox", "火狐浏览器"], "Firefox", "org.mozilla.firefox"),
        (["Slack"], "Slack", "com.tinyspeck.slackmacgap"),
        (["Telegram", "电报"], "Telegram", "ru.keepcoder.Telegram"),
        (["Spotify"], "Spotify", "com.spotify.client"),
        (["Notion"], "Notion", "notion.id"),
        (["Obsidian"], "Obsidian", "md.obsidian"),
    ]

    func execute(intent: RecognizedIntent) async -> CommandResult {
        let appName = intent.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appName.isEmpty else {
            return CommandResult(success: false, message: "未指定应用名称")
        }

        // 1. 查别名映射表
        if let match = Self.resolveAlias(appName) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: match.bundleID) {
                return await openApp(at: url, name: match.englishName)
            }
            // Bundle ID 没找到，用英文名搜路径
            if let url = Self.findAppByName(match.englishName) {
                return await openApp(at: url, name: match.englishName)
            }
        }

        // 2. 直接当 Bundle ID 试
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appName) {
            return await openApp(at: url, name: appName)
        }

        // 3. 按名称搜索 /Applications 和 /System/Applications
        if let url = Self.findAppByName(appName) {
            return await openApp(at: url, name: appName)
        }

        // 4. 用 mdfind 搜索（Spotlight）
        if let url = await Self.findAppViaSpotlight(appName) {
            return await openApp(at: url, name: appName)
        }

        return CommandResult(success: false, message: "找不到应用「\(appName)」")
    }

    private static func resolveAlias(_ name: String) -> (englishName: String, bundleID: String)? {
        let lowered = name.lowercased()
        for entry in aliasMap {
            // 精确匹配英文名
            if entry.englishName.lowercased() == lowered {
                return (entry.englishName, entry.bundleID)
            }
            // 匹配中文别名
            for alias in entry.aliases {
                if alias.lowercased() == lowered || lowered.contains(alias.lowercased()) || alias.lowercased().contains(lowered) {
                    return (entry.englishName, entry.bundleID)
                }
            }
        }
        return nil
    }

    private static func findAppByName(_ name: String) -> URL? {
        let searchDirs = [
            "/Applications",
            "/System/Applications",
            "/Applications/Utilities",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices"
        ]

        // 直接路径匹配
        for dir in searchDirs {
            let path = "\(dir)/\(name).app"
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // 遍历目录查找本地化名匹配
        let fm = FileManager.default
        for dir in searchDirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let appPath = "\(dir)/\(item)"
                let plistPath = "\(appPath)/Contents/Info.plist"
                guard let plist = NSDictionary(contentsOfFile: plistPath) else { continue }
                let displayName = plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String ?? ""
                let bundleName = (item as NSString).deletingPathExtension
                if displayName.localizedCaseInsensitiveContains(name) ||
                   bundleName.localizedCaseInsensitiveContains(name) ||
                   name.localizedCaseInsensitiveContains(displayName) ||
                   name.localizedCaseInsensitiveContains(bundleName) {
                    return URL(fileURLWithPath: appPath)
                }
            }
        }

        return nil
    }

    private static func findAppViaSpotlight(_ name: String) async -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemKind == 'Application' && kMDItemDisplayName == '*\(name)*'cd"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            if let firstLine = output.components(separatedBy: "\n").first(where: { $0.hasSuffix(".app") }) {
                return URL(fileURLWithPath: firstLine)
            }
        } catch {}
        return nil
    }

    private func openApp(at url: URL, name: String) async -> CommandResult {
        do {
            let config = NSWorkspace.OpenConfiguration()
            try await NSWorkspace.shared.openApplication(at: url, configuration: config)
            return CommandResult(success: true, message: "已打开「\(name)」")
        } catch {
            return CommandResult(success: false, message: "打开失败: \(error.localizedDescription)")
        }
    }
}
