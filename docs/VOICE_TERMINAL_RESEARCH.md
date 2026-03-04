# macOS Voice Terminal 系统能力研究报告

> 研究日期：2026-03-04
> 目标：构建一个通过语音命令控制 Mac 的 "Voice Terminal"

---

## 目录

1. [macOS 原生 API 能力总览](#1-macos-原生-api-能力总览)
2. [各能力详细分析](#2-各能力详细分析)
3. [开源项目参考](#3-开源项目参考)
4. [Apple 官方新动向](#4-apple-官方新动向)
5. [权限要求总表](#5-权限要求总表)
6. [推荐架构方案](#6-推荐架构方案)

---

## 1. macOS 原生 API 能力总览

| 能力类别 | 框架/API | 典型用途 | 沙盒兼容 | TCC 授权 |
|---------|----------|---------|---------|---------|
| UI 自动化 | Accessibility API (AXUIElement) | 点击按钮、读取文本、操控任意 App UI | ❌ | ✅ 辅助功能权限 |
| 脚本执行 | AppleScript / JXA | 跨 App 自动化、系统操作 | 部分 | ✅ Apple Events |
| 快捷指令 | App Intents / Shortcuts | 系统级快捷操作 | ✅ | 视具体 Intent |
| 日历/提醒 | EventKit | 创建事件/提醒 | ✅(需 entitlement) | ✅ 日历/提醒权限 |
| 通讯录 | Contacts | 读写联系人 | ✅(需 entitlement) | ✅ 通讯录权限 |
| 文件操作 | FileManager / NSFileCoordinator | 文件创建/移动/删除/搜索 | 部分 | ✅ 文件和文件夹权限 |
| App 管理 | NSWorkspace | 启动/终止 App、打开文件/URL | ✅ | ❌ |
| 窗口管理 | CGWindowListCopyWindowInfo + AX | 获取窗口列表、移动/调整大小 | ❌ | ✅ 辅助功能权限 |
| 键鼠模拟 | CGEvent | 模拟键盘/鼠标事件 | ❌ | ✅ 辅助功能权限 |
| 搜索 | CoreSpotlight | 索引和搜索内容 | ✅ | ❌ |
| 硬件控制 | IOKit / CoreAudio | 亮度/音量调节 | ❌ | 部分 |
| 音乐控制 | MediaPlayer (MPRemoteCommandCenter) | 播放/暂停/切歌 | ✅ | ❌ |
| 定位 | CoreLocation | 获取用户位置 | ✅(需 entitlement) | ✅ 定位权限 |
| 通知 | UserNotifications | 发送本地通知 | ✅ | ✅ 通知权限 |
| 屏幕捕获 | ScreenCaptureKit | 截图/录屏 | ❌ | ✅ 屏幕录制权限 |
| 服务管理 | ServiceManagement | 开机启动/后台服务 | ✅ | ❌ |
| 蓝牙 | CoreBluetooth / IOBluetooth | 蓝牙设备管理 | ✅(需 entitlement) | ✅ 蓝牙权限 |
| WiFi | CoreWLAN | WiFi 网络管理 | ❌ | ✅ 定位权限(扫描) |
| 剪贴板 | NSPasteboard | 读写剪贴板 | ✅ | ✅ (macOS 15.4+) |
| Shell 执行 | Process (NSTask) | 执行终端命令 | ❌ | ❌ |
| 系统外观 | NSAppearance | 深色/浅色模式 | ✅ | ❌(仅 App 内) |
| 系统设置 | URL Scheme | 打开特定设置面板 | ✅ | ❌ |
| 网络监控 | NWPathMonitor | 网络状态检测 | ✅ | ❌ |

---

## 2. 各能力详细分析

### 2.1 Accessibility API (AXUIElement) — 核心能力

**重要程度：** 最高 — 这是实现通用 UI 自动化的关键

**功能范围：**
- 读取任意 App 的 UI 元素树（按钮、文本框、菜单等）
- 执行 UI 操作（点击、输入、滚动）
- 获取窗口位置和大小信息
- 监听 UI 变化通知

**Swift 集成方式：**

```swift
import ApplicationServices

// 获取当前焦点应用
let app = AXUIElementCreateApplication(pid)

// 读取属性
var value: AnyObject?
AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)

// 执行操作
AXUIElementPerformAction(element, kAXPressAction as CFString)

// 设置值
AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, "Hello" as CFString)
```

**推荐 Swift 封装库：**

| 库名 | 特点 | 链接 |
|------|------|------|
| [AXorcist](https://github.com/steipete/AXorcist) | 现代 Swift API，链式查询，模糊匹配，macOS 14+ | Peter Steinberger 维护 |
| [AXSwift](https://github.com/tmandry/AXSwift) | 类型安全，Observer 支持 | 社区维护 |
| [Swindler](https://github.com/tmandry/Swindler) | 窗口管理专用封装 | 基于 AXSwift |
| [DFAXUIElement](https://github.com/DevilFinger/DFAXUIElement) | 轻量封装 + AXObserver | 快速入门 |

**AXorcist 使用示例：**

```swift
import AXorcist

// 创建命令查找按钮并点击
let command = AXCommand.find(role: .button, title: "Submit")
let envelope = AXCommandEnvelope(command: command, targetPID: appPID)
let response = try await axorcist.run(envelope)

// 支持模糊匹配
let command = AXCommand.find(role: .textField, titleContains: "search")
```

**权限要求：**
- TCC 授权：辅助功能权限（Accessibility）
- `AXIsProcessTrusted()` 检查权限状态
- 通过 `System Settings > Privacy & Security > Accessibility` 授权
- **不兼容 App Sandbox**，无法上架 Mac App Store

```swift
// 检查并请求权限
let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
let trusted = AXIsProcessTrustedWithOptions(options)
```

---

### 2.2 AppleScript / JXA (JavaScript for Automation)

**功能范围：**
- 通过 OSA 脚本控制可脚本化的 App（Finder、Safari、Mail、Music 等）
- 系统级操作（文件操作、UI 交互）
- 支持 App 之间的数据传递

**Swift 集成 AppleScript：**

```swift
import Foundation

// 方式 1：NSAppleScript
let script = NSAppleScript(source: """
    tell application "Music"
        play
    end tell
""")
var error: NSDictionary?
script?.executeAndReturnError(&error)

// 方式 2：Process 执行 osascript
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
process.arguments = ["-e", "tell application \"Finder\" to open home"]
try process.run()
```

**Swift 集成 JXA：**

```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
process.arguments = ["-l", "JavaScript", "-e", """
    var app = Application("Safari");
    app.activate();
    var tab = app.windows[0].currentTab;
    tab.url();
"""]

let pipe = Pipe()
process.standardOutput = pipe
try process.run()
process.waitUntilExit()

let data = pipe.fileHandleForReading.readDataToEndOfFile()
let output = String(data: data, encoding: .utf8)
```

**常用 AppleScript 命令示例：**

```applescript
-- 获取当前 Safari URL
tell application "Safari" to get URL of current tab of window 1

-- 发送系统通知
display notification "任务完成" with title "Voice Terminal"

-- 设置系统音量
set volume output volume 50

-- 获取剪贴板内容
the clipboard

-- 打开 URL
open location "https://example.com"

-- Finder 文件操作
tell application "Finder"
    make new folder at desktop with properties {name:"New Folder"}
    move file "test.txt" of desktop to folder "New Folder" of desktop
end tell
```

**权限要求：**
- TCC 授权：Apple Events（自动化权限）
- Info.plist 需声明 `NSAppleEventsUsageDescription`
- 每个目标 App 都需要单独授权
- 沙盒 App 需要 `com.apple.security.scripting-targets` entitlement

---

### 2.3 App Intents / Shortcuts 框架

**功能范围：**
- 暴露 App 功能为系统级快捷指令
- 与 Siri 集成
- Spotlight 搜索集成
- 支持参数化操作

**定义 App Intent：**

```swift
import AppIntents

struct CreateReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "创建提醒"
    static var description: IntentDescription = "通过语音创建提醒事项"

    @Parameter(title: "提醒内容")
    var content: String

    @Parameter(title: "时间")
    var date: Date?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // 创建提醒逻辑
        return .result(dialog: "已创建提醒：\(content)")
    }
}
```

**定义 App Shortcut：**

```swift
struct VoiceTerminalShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateReminderIntent(),
            phrases: [
                "用 \(.applicationName) 创建提醒",
                "提醒我 \(\.$content)"
            ],
            shortTitle: "创建提醒",
            systemImageName: "bell"
        )
    }
}
```

**调用系统快捷指令：**

```swift
import IntentsUI

// 通过 URL Scheme 运行快捷指令
let shortcutName = "My Shortcut"
let urlString = "shortcuts://run-shortcut?name=\(shortcutName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)"
if let url = URL(string: urlString) {
    NSWorkspace.shared.open(url)
}
```

**权限要求：**
- 无需额外 TCC 权限（框架本身）
- 具体 Intent 执行的操作可能需要各自的权限
- 完全兼容 App Sandbox
- WWDC25 新增：可将 App Intents 放入 Swift Packages

---

### 2.4 EventKit（日历和提醒事项）

**功能范围：**
- 读取/创建/修改/删除日历事件
- 读取/创建/修改/删除提醒事项
- 监听日历变化

**Swift 集成：**

```swift
import EventKit

let eventStore = EKEventStore()

// 请求日历权限
try await eventStore.requestFullAccessToEvents()

// 请求提醒权限
try await eventStore.requestFullAccessToReminders()

// 创建日历事件
let event = EKEvent(eventStore: eventStore)
event.title = "语音创建的会议"
event.startDate = Date()
event.endDate = Date().addingTimeInterval(3600)
event.calendar = eventStore.defaultCalendarForNewEvents
try eventStore.save(event, span: .thisEvent)

// 创建提醒事项
let reminder = EKReminder(eventStore: eventStore)
reminder.title = "买牛奶"
reminder.calendar = eventStore.defaultCalendarForNewReminders()
reminder.dueDateComponents = Calendar.current.dateComponents(
    [.year, .month, .day, .hour, .minute],
    from: Date().addingTimeInterval(3600)
)
try eventStore.save(reminder, commit: true)

// 查询今天的事件
let startOfDay = Calendar.current.startOfDay(for: Date())
let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
let events = eventStore.events(matching: predicate)
```

**权限要求：**
- TCC 授权：日历权限 / 提醒权限（分别授权）
- Info.plist 键：`NSCalendarsUsageDescription`、`NSRemindersUsageDescription`
- macOS 14+：`NSCalendarsFullAccessUsageDescription`、`NSRemindersFullAccessUsageDescription`
- 沙盒 App 需要 `com.apple.security.personal-information.calendars` entitlement
- EKEventStore 建议作为单例，整个 App 生命周期复用

---

### 2.5 Contacts 框架（通讯录）

**功能范围：**
- 读取/创建/修改/删除联系人
- 搜索联系人
- 监听通讯录变化

**Swift 集成：**

```swift
import Contacts

let store = CNContactStore()

// 请求权限
try await store.requestAccess(for: .contacts)

// 搜索联系人
let predicate = CNContact.predicateForContacts(matchingName: "张三")
let keysToFetch = [
    CNContactGivenNameKey,
    CNContactFamilyNameKey,
    CNContactPhoneNumbersKey,
    CNContactEmailAddressesKey
] as [CNKeyDescriptor]
let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

// 创建联系人
let newContact = CNMutableContact()
newContact.givenName = "新"
newContact.familyName = "联系人"
newContact.phoneNumbers = [CNLabeledValue(
    label: CNLabelPhoneNumberMobile,
    value: CNPhoneNumber(stringValue: "13800138000")
)]

let saveRequest = CNSaveRequest()
saveRequest.add(newContact, toContainerWithIdentifier: nil)
try store.execute(saveRequest)
```

**权限要求：**
- TCC 授权：通讯录权限
- Info.plist 键：`NSContactsUsageDescription`
- 沙盒 App 需要 `com.apple.security.personal-information.addressbook` entitlement
- 沙盒 App 还需在 Xcode > Signing & Capabilities > App Sandbox 中勾选 Contacts

---

### 2.6 FileManager / 文件操作

**功能范围：**
- 创建/移动/复制/删除文件和目录
- 文件属性读取和修改
- 目录遍历
- 文件搜索

**Swift 集成：**

```swift
import Foundation

let fm = FileManager.default

// 创建目录
try fm.createDirectory(at: URL(fileURLWithPath: "/path/to/dir"),
                       withIntermediateDirectories: true)

// 复制文件
try fm.copyItem(at: sourceURL, to: destURL)

// 移动文件
try fm.moveItem(at: sourceURL, to: destURL)

// 删除文件
try fm.removeItem(at: fileURL)

// 遍历目录
let contents = try fm.contentsOfDirectory(at: dirURL,
                                           includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
                                           options: .skipsHiddenFiles)

// 文件属性
let attributes = try fm.attributesOfItem(atPath: path)
let fileSize = attributes[.size] as? UInt64

// 在 Finder 中显示文件
NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")

// 用默认 App 打开文件
NSWorkspace.shared.open(URL(fileURLWithPath: path))
```

**NSFileCoordinator 用于安全文件操作：**

```swift
let coordinator = NSFileCoordinator()
var error: NSError?
coordinator.coordinate(writingItemAt: sourceURL, options: .forMoving,
                       writingItemAt: destURL, options: .forReplacing,
                       error: &error) { newSourceURL, newDestURL in
    try? FileManager.default.moveItem(at: newSourceURL, to: newDestURL)
}
```

**权限要求：**
- 沙盒 App：只能访问 App 容器内的文件、用户通过 Open/Save 面板选择的文件
- 非沙盒 App：可访问用户可读写的所有文件
- TCC：Files and Folders 权限（访问桌面、文稿、下载等用户目录时）
- Full Disk Access：访问邮件、Safari 数据等受保护目录

---

### 2.7 NSWorkspace（App 管理）

**功能范围：**
- 启动/激活应用程序
- 打开文件和 URL
- 获取运行中的 App 列表
- 监听 App 启动/退出事件
- 获取 App 图标、信息

**Swift 集成：**

```swift
import AppKit

let workspace = NSWorkspace.shared

// 启动 App
let config = NSWorkspace.OpenConfiguration()
config.activates = true
try await workspace.openApplication(at: URL(fileURLWithPath: "/Applications/Safari.app"),
                                     configuration: config)

// 通过 Bundle ID 启动
workspace.launchApplication(
    withBundleIdentifier: "com.apple.Safari",
    options: .default,
    additionalEventParamDescriptor: nil,
    launchIdentifier: nil
)

// 获取运行中的 App
let runningApps = workspace.runningApplications
for app in runningApps {
    print("\(app.localizedName ?? "Unknown") - \(app.bundleIdentifier ?? "")")
}

// 终止 App
if let app = runningApps.first(where: { $0.bundleIdentifier == "com.apple.Safari" }) {
    app.terminate()
}

// 强制终止
app.forceTerminate()

// 隐藏 App
app.hide()

// 激活（前置）App
app.activate()

// 打开 URL
workspace.open(URL(string: "https://www.apple.com")!)

// 打开文件
workspace.open(URL(fileURLWithPath: "/path/to/file.pdf"))

// 用指定 App 打开文件
workspace.open([URL(fileURLWithPath: "/path/to/file.txt")],
               withApplicationAt: URL(fileURLWithPath: "/Applications/TextEdit.app"),
               configuration: NSWorkspace.OpenConfiguration())

// 监听 App 事件
workspace.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                          object: nil, queue: .main) { notification in
    if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
        print("App launched: \(app.localizedName ?? "")")
    }
}
```

**权限要求：**
- 基本操作无需 TCC 授权
- 完全兼容 App Sandbox（启动 App、打开 URL 等基本操作）
- 注意：NSWorkspace 是 AppKit 的一部分，不能在 daemon 上下文中使用

---

### 2.8 CGEvent（键鼠模拟）

**功能范围：**
- 模拟键盘按键（包括组合键）
- 模拟鼠标点击、移动、拖拽
- 模拟滚轮事件

**Swift 集成：**

```swift
import CoreGraphics

// 模拟键盘输入
func pressKey(keyCode: CGKeyCode, flags: CGEventFlags = []) {
    let source = CGEventSource(stateID: .hidSystemState)

    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

    keyDown?.flags = flags
    keyUp?.flags = flags

    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}

// Cmd+C (复制)
pressKey(keyCode: 8, flags: .maskCommand)  // 8 = 'c'

// Cmd+V (粘贴)
pressKey(keyCode: 9, flags: .maskCommand)  // 9 = 'v'

// 输入文本（逐字符）
func typeText(_ text: String) {
    for char in text {
        let source = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        var unichar = Array(char.utf16)
        event?.keyboardSetUnicodeString(stringLength: unichar.count, unicodeString: &unichar)
        event?.post(tap: .cghidEventTap)

        let upEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        upEvent?.post(tap: .cghidEventTap)
    }
}

// 模拟鼠标点击
func mouseClick(at point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)

    let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                            mouseCursorPosition: point, mouseButton: .left)
    let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                          mouseCursorPosition: point, mouseButton: .left)

    mouseDown?.post(tap: .cghidEventTap)
    mouseUp?.post(tap: .cghidEventTap)
}

// 模拟鼠标移动
func moveMouse(to point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)
    let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                        mouseCursorPosition: point, mouseButton: .left)
    event?.post(tap: .cghidEventTap)
}

// 模拟滚轮
func scroll(deltaY: Int32) {
    let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                        wheelCount: 1, wheel1: deltaY, wheel2: 0, wheel3: 0)
    event?.post(tap: .cghidEventTap)
}
```

**权限要求：**
- TCC 授权：辅助功能权限（Accessibility）
- **不兼容 App Sandbox**
- 目标 App 必须在前台才能接收事件
- Info.plist：`NSAppleEventsUsageDescription`

---

### 2.9 CoreSpotlight（搜索）

**功能范围：**
- 索引 App 内容到系统搜索
- 搜索已索引的内容
- 与 Spotlight 集成

**Swift 集成：**

```swift
import CoreSpotlight
import UniformTypeIdentifiers

// 索引内容
let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
attributeSet.title = "语音命令记录"
attributeSet.contentDescription = "今天执行的所有语音命令"
attributeSet.keywords = ["语音", "命令", "自动化"]

let item = CSSearchableItem(uniqueIdentifier: "command-001",
                             domainIdentifier: "com.app.commands",
                             attributeSet: attributeSet)

CSSearchableIndex.default().indexSearchableItems([item])

// 搜索内容
let query = CSSearchQuery(queryString: "语音*",
                           attributes: ["title", "contentDescription"])
query.foundItemsHandler = { items in
    for item in items {
        print(item.attributeSet.title ?? "")
    }
}
query.completionHandler = { error in
    if let error = error {
        print("搜索错误: \(error)")
    }
}
query.start()
```

**权限要求：**
- 无需 TCC 授权
- 完全兼容 App Sandbox
- 只能搜索自己 App 索引的内容

---

### 2.10 IOKit / CoreAudio（硬件控制）

**亮度控制：**

```swift
import IOKit.graphics

// 方式 1：DisplayServices（私有 API）
@_silgen_name("DisplayServicesSetBrightness")
func DisplayServicesSetBrightness(_ display: CGDirectDisplayID, _ brightness: Float) -> Int32

@_silgen_name("DisplayServicesGetBrightness")
func DisplayServicesGetBrightness(_ display: CGDirectDisplayID, _ brightness: UnsafeMutablePointer<Float>) -> Int32

// 设置亮度
let mainDisplay = CGMainDisplayID()
DisplayServicesSetBrightness(mainDisplay, 0.5)  // 50%

// 方式 2：通过 Shortcuts/AppleScript
let script = NSAppleScript(source: """
    tell application "System Events"
        key code 145  -- brightness down
    end tell
""")
```

**音量控制：**

```swift
import CoreAudio

// 获取默认输出设备
var deviceID = AudioDeviceID(0)
var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                           &address, 0, nil, &propertySize, &deviceID)

// 设置音量
var volume: Float32 = 0.5  // 50%
var volumeAddress = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyVolumeScalar,
    mScope: kAudioDevicePropertyScopeOutput,
    mElement: 1  // channel 1
)
AudioObjectSetPropertyData(deviceID, &volumeAddress, 0, nil,
                           UInt32(MemoryLayout<Float32>.size), &volume)

// 静音/取消静音
var mute: UInt32 = 1  // 1 = mute, 0 = unmute
var muteAddress = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyMute,
    mScope: kAudioDevicePropertyScopeOutput,
    mElement: kAudioObjectPropertyElementMain
)
AudioObjectSetPropertyData(deviceID, &muteAddress, 0, nil,
                           UInt32(MemoryLayout<UInt32>.size), &mute)
```

**推荐库：**
- [SimplyCoreAudio](https://github.com/rnine/SimplyCoreAudio) — CoreAudio 的 Swift 友好封装
- [ISSoundAdditions](https://github.com/InerziaSoft/ISSoundAdditions) — 系统音量控制的简洁封装
- [MonitorControl](https://github.com/MonitorControl/MonitorControl) — 外接显示器亮度/音量控制

**权限要求：**
- IOKit：**不兼容 App Sandbox**
- CoreAudio 基础操作：无需 TCC 授权
- 亮度控制使用私有 API，可能在 macOS 更新后失效

---

### 2.11 MediaPlayer（音乐控制）

**功能范围：**
- 控制当前播放的音乐（播放/暂停/上一曲/下一曲）
- 设置 Now Playing 信息
- 响应远程控制命令

**Swift 集成：**

```swift
import MediaPlayer

// 方式 1：通过 MRMediaRemoteCommand（私有 API，功能更强）
// 控制任意播放器
@_silgen_name("MRMediaRemoteSendCommand")
func MRMediaRemoteSendCommand(_ command: Int, _ options: NSDictionary?) -> Bool

// 播放/暂停
MRMediaRemoteSendCommand(2, nil)  // togglePlayPause

// 方式 2：通过 AppleScript 控制 Music App
let script = NSAppleScript(source: """
    tell application "Music"
        if player state is playing then
            pause
        else
            play
        end if
    end tell
""")

// 获取当前播放信息
let infoScript = NSAppleScript(source: """
    tell application "Music"
        set trackName to name of current track
        set artistName to artist of current track
        return trackName & " - " & artistName
    end tell
""")

// 方式 3：MPRemoteCommandCenter（用于自己 App 的播放控制）
let commandCenter = MPRemoteCommandCenter.shared()
commandCenter.playCommand.addTarget { event in
    // 处理播放
    return .success
}
commandCenter.pauseCommand.addTarget { event in
    // 处理暂停
    return .success
}
commandCenter.nextTrackCommand.addTarget { event in
    // 下一曲
    return .success
}
```

**权限要求：**
- MPRemoteCommandCenter：无需额外权限
- AppleScript 控制其他 App：需要 Apple Events 授权
- MRMediaRemote（私有 API）：可能需要额外 entitlement

---

### 2.12 CoreLocation（定位）

**Swift 集成：**

```swift
import CoreLocation

class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    func setup() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest

        // macOS 需要请求权限
        manager.requestWhenInUseAuthorization()  // macOS 15+
        // 或 manager.requestAlwaysAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorized:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        print("位置: \(location.coordinate.latitude), \(location.coordinate.longitude)")
    }
}
```

**权限要求：**
- TCC 授权：定位服务权限
- Info.plist 键：`NSLocationUsageDescription`、`NSLocationWhenInUseUsageDescription`
- 沙盒 App 需要 `com.apple.security.personal-information.location` entitlement
- macOS 上定位精度可能不如 iOS（依赖 WiFi 和 IP 定位）

---

### 2.13 UserNotifications（通知）

**Swift 集成：**

```swift
import UserNotifications

// 请求权限
let center = UNUserNotificationCenter.current()
let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])

// 发送即时通知
let content = UNMutableNotificationContent()
content.title = "Voice Terminal"
content.body = "命令已执行完成"
content.sound = .default

let request = UNNotificationRequest(identifier: UUID().uuidString,
                                     content: content, trigger: nil)
try await center.add(request)

// 定时通知
let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false)
let timedRequest = UNNotificationRequest(identifier: "timer-001",
                                          content: content, trigger: trigger)
try await center.add(timedRequest)

// 日历触发通知
var dateComponents = DateComponents()
dateComponents.hour = 9
dateComponents.minute = 0
let calendarTrigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

// 带操作按钮的通知
let action = UNNotificationAction(identifier: "RETRY", title: "重试", options: [])
let category = UNNotificationCategory(identifier: "COMMAND_RESULT",
                                       actions: [action], intentIdentifiers: [])
center.setNotificationCategories([category])
content.categoryIdentifier = "COMMAND_RESULT"
```

**权限要求：**
- TCC 授权：通知权限
- 完全兼容 App Sandbox
- 无需 Info.plist 声明

---

### 2.14 ScreenCaptureKit（屏幕捕获）

**功能范围：**
- 捕获特定窗口/App/屏幕的内容
- 支持音频捕获
- 高性能实时流
- 隐私保护（可排除特定窗口）

**Swift 集成：**

```swift
import ScreenCaptureKit

// 获取可用内容
let availableContent = try await SCShareableContent.excludingDesktopWindows(false,
                                                                            onScreenWindowsOnly: true)

// 获取所有窗口
for window in availableContent.windows {
    print("Window: \(window.title ?? "") - App: \(window.owningApplication?.applicationName ?? "")")
}

// 配置截图过滤器
let filter = SCContentFilter(display: availableContent.displays.first!,
                              excludingWindows: [])

// 截取屏幕
let config = SCStreamConfiguration()
config.width = 1920
config.height = 1080
config.pixelFormat = kCVPixelFormatType_32BGRA

let image = try await SCScreenshotManager.captureImage(
    contentFilter: filter,
    configuration: config
)

// 持续捕获流
let stream = SCStream(filter: filter, configuration: config, delegate: self)
try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
try await stream.startCapture()
```

**权限要求：**
- TCC 授权：屏幕录制权限（Screen Recording）
- **不兼容 App Sandbox**（macOS 12.3+）
- 需要 macOS 12.3+
- macOS 15+ 新增了更细粒度的内容选择器 UI

---

### 2.15 ServiceManagement（开机启动）

**Swift 集成：**

```swift
import ServiceManagement

// 注册开机启动
try SMAppService.mainApp.register()

// 取消开机启动
try SMAppService.mainApp.unregister()

// 检查状态
let status = SMAppService.mainApp.status
switch status {
case .enabled:
    print("已启用开机启动")
case .notRegistered:
    print("未注册")
case .requiresApproval:
    print("需要用户批准")
@unknown default:
    break
}
```

**权限要求：**
- 无需 TCC 授权
- 兼容 App Sandbox
- macOS 13+ 必须使用 SMAppService（旧 API 已废弃）
- 用户可在 System Settings > General > Login Items 中管理

---

### 2.16 NSPasteboard（剪贴板）

**Swift 集成：**

```swift
import AppKit

let pasteboard = NSPasteboard.general

// 读取文本
let text = pasteboard.string(forType: .string)

// 写入文本
pasteboard.clearContents()
pasteboard.setString("Hello from Voice Terminal", forType: .string)

// 读取图片
if let imageData = pasteboard.data(forType: .tiff),
   let image = NSImage(data: imageData) {
    // 使用图片
}

// 写入多种类型
pasteboard.clearContents()
pasteboard.writeObjects([
    "Text content" as NSString,
    NSURL(string: "https://example.com")!
])

// 监听剪贴板变化
Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
    let changeCount = NSPasteboard.general.changeCount
    // 比较 changeCount 检测变化
}
```

**权限要求：**
- macOS 15.4+：新增剪贴板隐私保护，程序化读取可能弹出提示
- `NSPasteboard.accessBehavior` 属性可查询访问策略
- 兼容 App Sandbox

---

### 2.17 Process / Shell 执行

**Swift 集成：**

```swift
import Foundation

@discardableResult
func shell(_ command: String) throws -> String {
    let process = Process()
    let pipe = Pipe()

    process.standardOutput = pipe
    process.standardError = pipe
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", command]

    // 设置环境变量
    process.environment = ProcessInfo.processInfo.environment

    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

// 异步执行
func shellAsync(_ command: String) async throws -> String {
    return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
            do {
                let result = try shell(command)
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// 使用示例
let output = try shell("ls -la ~/Desktop")
let gitStatus = try shell("cd /path/to/repo && git status")
let brewList = try shell("brew list")
```

**权限要求：**
- **不兼容 App Sandbox**
- 无需 TCC 授权（但执行的命令可能需要）
- 注意：沙盒 App 内的 PATH 可能不包含 Homebrew 等路径

---

### 2.18 窗口管理

**Swift 集成：**

```swift
import CoreGraphics
import ApplicationServices

// 获取所有窗口信息
if let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] {
    for window in windowList {
        let name = window[kCGWindowName as String] as? String ?? ""
        let ownerName = window[kCGWindowOwnerName as String] as? String ?? ""
        let bounds = window[kCGWindowBounds as String] as? [String: Any]
        print("[\(ownerName)] \(name) - \(bounds ?? [:])")
    }
}

// 通过 Accessibility API 移动/调整窗口大小
func moveWindow(pid: pid_t, to point: CGPoint, size: CGSize? = nil) {
    let app = AXUIElementCreateApplication(pid)
    var windows: AnyObject?
    AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)

    guard let windowArray = windows as? [AXUIElement], let window = windowArray.first else { return }

    // 移动窗口
    var position = point
    let posValue = AXValueCreate(.cgPoint, &position)!
    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)

    // 调整大小
    if var newSize = size {
        let sizeValue = AXValueCreate(.cgSize, &newSize)!
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }
}
```

**权限要求：**
- `CGWindowListCopyWindowInfo`：无需特殊权限（只读）
- AX 操作窗口：需要辅助功能权限
- **不兼容 App Sandbox**

---

### 2.19 系统设置面板跳转

**Swift 集成：**

```swift
import AppKit

// 定义常用系统设置 URL
enum SystemSettingsURL: String {
    // 通用
    case general = "x-apple.systempreferences:com.apple.preference.general"
    case accessibility = "x-apple.systempreferences:com.apple.preference.universalaccess"
    case security = "x-apple.systempreferences:com.apple.preference.security"

    // 隐私
    case privacyAccessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    case privacyCamera = "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
    case privacyMicrophone = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    case privacyScreenRecording = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    case privacyAutomation = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"

    // 网络和硬件
    case network = "x-apple.systempreferences:com.apple.preference.network"
    case bluetooth = "x-apple.systempreferences:com.apple.preferences.Bluetooth"
    case sound = "x-apple.systempreferences:com.apple.preference.sound"
    case displays = "x-apple.systempreferences:com.apple.preference.displays"

    // 通知
    case notifications = "x-apple.systempreferences:com.apple.preference.notifications"

    // WiFi（macOS Ventura+）
    case wifi = "x-apple.systempreferences:com.apple.wifi-settings-extension"
}

func openSystemSettings(_ setting: SystemSettingsURL) {
    if let url = URL(string: setting.rawValue) {
        NSWorkspace.shared.open(url)
    }
}

// 使用
openSystemSettings(.privacyAccessibility)
```

---

### 2.20 CoreBluetooth / IOBluetooth

**Swift 集成：**

```swift
import CoreBluetooth

class BluetoothManager: NSObject, CBCentralManagerDelegate {
    var centralManager: CBCentralManager!

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("蓝牙已开启")
            // 可以开始扫描
            central.scanForPeripherals(withServices: nil)
        case .poweredOff:
            print("蓝牙已关闭")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        print("发现设备: \(peripheral.name ?? "Unknown")")
    }
}

// IOBluetooth（更底层，可获取已配对设备）
import IOBluetooth
let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]
for device in pairedDevices ?? [] {
    print("配对设备: \(device.name ?? "") - \(device.isConnected() ? "已连接" : "未连接")")
}
```

**权限要求：**
- TCC 授权：蓝牙权限
- Info.plist 键：`NSBluetoothAlwaysUsageDescription`
- 沙盒 App 需要 `com.apple.security.device.bluetooth` entitlement
- IOBluetooth 部分 API 不兼容沙盒

---

### 2.21 CoreWLAN（WiFi 管理）

**Swift 集成：**

```swift
import CoreWLAN

// 获取当前 WiFi 接口
if let interface = CWWiFiClient.shared().interface() {
    print("SSID: \(interface.ssid() ?? "无")")
    print("BSSID: \(interface.bssid() ?? "无")")
    print("RSSI: \(interface.rssiValue()) dBm")
    print("信道: \(interface.wlanChannel()?.channelNumber ?? 0)")
    print("传输速率: \(interface.transmitRate()) Mbps")
    print("安全模式: \(interface.security())")
}

// 扫描可用网络
let networks = try interface.scanForNetworks(withSSID: nil)
for network in networks {
    print("\(network.ssid ?? "Hidden") - RSSI: \(network.rssiValue)")
}

// 断开 WiFi
interface.disassociate()

// 连接到指定网络
try interface.associate(to: network, password: "password")
```

**权限要求：**
- **不兼容 App Sandbox**
- 扫描功能需要定位权限（macOS 14+）
- `com.apple.developer.CoreWLAN.allow-setting` entitlement（如需修改设置）

---

## 3. 开源项目参考

### 3.1 macOS AI Agent 项目

| 项目 | 方法 | Star 数(2026) | 语言 | 关键技术 |
|------|------|-------------|------|---------|
| [macOS-use](https://github.com/browser-use/macOS-use) | Accessibility Tree + LLM | 高 | Python | 将 macOS App 的无障碍树暴露给 AI Agent |
| [CUA](https://github.com/trycua/cua) | VM 沙盒 + 截图 | 高 | Python | Apple 虚拟化框架，支持 macOS/Linux/Windows |
| [Agent-S](https://github.com/simular-ai/Agent-S) | 多模态 GUI Agent | 高 | Python | 超越 OpenAI CUA 和 Anthropic Computer Use |
| [GPT-Automator](https://github.com/chidiwilliams/GPT-Automator) | 语音 + AppleScript/JXA | 中 | Python | Whisper 语音识别 → LangChain → AppleScript |
| [MacOS-Agent](https://github.com/Computer-use-agents/MacOS-Agent) | Accessibility + 自然语言 | 中 | Python | Finder/TextEdit/Preview 等系统 App 控制 |
| [macOSpilot](https://github.com/elfvingralf/macOSpilot-ai-assistant) | 语音 + 视觉 AI | 中 | Python | 上下文感知的 AI 助手 |
| [Open Interpreter](https://github.com/openinterpreter/open-interpreter) | 代码执行 | 高 | Python | 本地代码执行的自然语言接口 |
| [01](https://github.com/openinterpreter/01) | 语音接口 | 中 | Python | 开源语音设备接口 |
| [Accomplish](https://github.com/accomplish-ai/accomplish) | 桌面 AI 助手 | 中 | TypeScript | 文件管理、文档创建、浏览器任务 |
| [Nudge](https://mcpmarket.com/server/nudge) | MCP 服务 | 新 | Swift | macOS UI 自动化的 MCP Server |

### 3.2 macOS Accessibility 库

| 库 | 用途 | 语言 |
|----|------|------|
| [AXorcist](https://github.com/steipete/AXorcist) | 现代 AXUIElement Swift 封装，链式查询 | Swift |
| [AXSwift](https://github.com/tmandry/AXSwift) | AXUIElement 类型安全封装 | Swift |
| [Swindler](https://github.com/tmandry/Swindler) | 窗口管理库（基于 AXSwift） | Swift |
| [macapptree](https://github.com/MacPaw/macapptree) | macOS 无障碍树解析器 | Swift |

### 3.3 各项目的技术路线对比

**路线 A：Accessibility API（推荐）**
- 代表项目：macOS-use、MacOS-Agent、AXorcist
- 优点：可精确控制任意 App UI 元素，无需截图
- 缺点：需要辅助功能权限，不兼容沙盒
- 适合：需要精确 UI 操作的场景

**路线 B：截图 + 视觉识别**
- 代表项目：CUA、Agent-S
- 优点：通用性强，不依赖 App 的无障碍实现
- 缺点：速度慢，精度依赖视觉模型
- 适合：App 无障碍支持差的场景

**路线 C：AppleScript / JXA**
- 代表项目：GPT-Automator
- 优点：稳定、成熟，可控制可脚本化 App
- 缺点：仅限支持脚本的 App，苹果逐步弱化
- 适合：控制系统内置 App（Finder、Music、Mail 等）

**路线 D：混合方案（推荐）**
- 结合 A + C：用 AppleScript 控制系统 App，用 AX API 处理其余情况
- 结合 A + B：用 AX API 优先，AX 不可用时回退截图方案
- 这是目前最实用的方案

---

## 4. Apple 官方新动向

### 4.1 App Intents 框架演进

**WWDC25 重要更新：**
- App Intents 可放入 **Swift Packages 和静态库**中（之前只能在框架和动态库中）
- 新增 **Interactive Snippets**：搜索结果中直接显示交互式 UI
- 增强的 Spotlight 集成
- 更多系统 Intent 可供第三方 App 使用

**WWDC24 更新：**
- App Shortcuts 更加自动化，Intent 可自动出现在 Shortcuts App
- 参数化更灵活
- 更好的 Siri 集成

### 4.2 macOS Sequoia (15) 自动化更新

- **Shortcuts Share Sheet** 支持在 macOS 上使用
- **Apple Intelligence** 集成（部分地区）
- 窗口平铺快捷键
- iPhone 镜像功能

### 4.3 macOS Tahoe (26) 预期更新

- **Shortcuts 自动化触发器**：基于时间、文件系统变化等自动触发
- **文件夹自动化**：类似 Hazel 的原生文件夹监控
- **Control Center 集成**
- **Spotlight 深度集成**

### 4.4 Automator 状态

- Apple 仍保留 Automator 但不再积极开发
- 建议新项目使用 App Intents / Shortcuts 替代
- 现有 Automator 工作流可继续使用

### 4.5 Apple 自动化方向总结

Apple 正在将自动化能力向以下方向收敛：
1. **App Intents** — 结构化的 App 能力暴露
2. **Shortcuts** — 用户可视化编排
3. **Siri + Apple Intelligence** — 自然语言驱动
4. **AppleScript/JXA** — 维护但不再发展

---

## 5. 权限要求总表

### 5.1 TCC 权限详细列表

| 权限名称 | 系统设置路径 | 影响的 API | Info.plist 键 |
|----------|------------|-----------|--------------|
| 辅助功能 (Accessibility) | Privacy > Accessibility | AXUIElement, CGEvent | 无（运行时检查） |
| 屏幕录制 (Screen Recording) | Privacy > Screen Recording | ScreenCaptureKit, CGWindowListCreateImage | 无（运行时检查） |
| 自动化 (Automation) | Privacy > Automation | AppleScript, NSAppleScript | `NSAppleEventsUsageDescription` |
| 日历 (Calendars) | Privacy > Calendars | EventKit | `NSCalendarsFullAccessUsageDescription` |
| 提醒事项 (Reminders) | Privacy > Reminders | EventKit | `NSRemindersFullAccessUsageDescription` |
| 通讯录 (Contacts) | Privacy > Contacts | Contacts | `NSContactsUsageDescription` |
| 定位服务 (Location) | Privacy > Location Services | CoreLocation | `NSLocationUsageDescription` |
| 麦克风 (Microphone) | Privacy > Microphone | AVAudioEngine, AVCaptureDevice | `NSMicrophoneUsageDescription` |
| 相机 (Camera) | Privacy > Camera | AVCaptureDevice | `NSCameraUsageDescription` |
| 通知 (Notifications) | Notifications | UserNotifications | 无（运行时请求） |
| 蓝牙 (Bluetooth) | Privacy > Bluetooth | CoreBluetooth | `NSBluetoothAlwaysUsageDescription` |
| 文件和文件夹 | Privacy > Files and Folders | FileManager（用户目录） | 无（运行时请求） |
| 完全磁盘访问 | Privacy > Full Disk Access | FileManager（受保护目录） | 无（用户手动授权） |

### 5.2 Entitlements 详细列表

| Entitlement | 用途 | 沙盒必需 |
|-------------|------|---------|
| `com.apple.security.app-sandbox` | 启用沙盒 | 是 |
| `com.apple.security.personal-information.calendars` | 日历访问 | 是 |
| `com.apple.security.personal-information.addressbook` | 通讯录访问 | 是 |
| `com.apple.security.personal-information.location` | 定位访问 | 是 |
| `com.apple.security.device.bluetooth` | 蓝牙访问 | 是 |
| `com.apple.security.device.audio-input` | 麦克风访问 | 是 |
| `com.apple.security.device.camera` | 相机访问 | 是 |
| `com.apple.security.automation.apple-events` | AppleScript | 是 |
| `com.apple.security.files.user-selected.read-write` | 用户选择的文件 | 是 |
| `com.apple.security.files.downloads.read-write` | 下载文件夹 | 是 |
| `com.apple.security.network.client` | 网络请求 | 是 |
| `com.apple.security.network.server` | 网络监听 | 是 |

### 5.3 沙盒 vs 非沙盒兼容性

| 能力 | 沙盒 App | 非沙盒 App | 备注 |
|------|---------|-----------|------|
| AXUIElement | ❌ | ✅ | 核心 UI 自动化不可用于沙盒 |
| CGEvent 键鼠模拟 | ❌ | ✅ | 同上 |
| Shell 执行 (Process) | ❌ | ✅ | 沙盒内极受限 |
| ScreenCaptureKit | ❌ | ✅ | 需要屏幕录制权限 |
| IOKit 硬件控制 | ❌ | ✅ | — |
| CoreWLAN | ❌ | ✅ | — |
| AppleScript 对外 | ⚠️ | ✅ | 沙盒需 scripting-targets |
| NSWorkspace 基本操作 | ✅ | ✅ | 启动 App、打开 URL |
| EventKit | ✅ | ✅ | 需要 entitlement |
| Contacts | ✅ | ✅ | 需要 entitlement |
| UserNotifications | ✅ | ✅ | — |
| CoreSpotlight | ✅ | ✅ | — |
| CoreLocation | ✅ | ✅ | 需要 entitlement |
| CoreBluetooth | ✅ | ✅ | 需要 entitlement |
| MediaPlayer | ✅ | ✅ | — |
| ServiceManagement | ✅ | ✅ | — |
| NSPasteboard | ✅ | ✅ | macOS 15.4+ 有隐私限制 |
| App Intents | ✅ | ✅ | — |
| FileManager（App 容器内） | ✅ | ✅ | — |
| FileManager（用户目录） | ⚠️ | ✅ | 沙盒需用户授权 |

**结论：Voice Terminal 必须作为非沙盒 App 分发**（不通过 Mac App Store），因为核心功能（AXUIElement、CGEvent、Shell 执行、ScreenCaptureKit）都不兼容沙盒。

---

## 6. 推荐架构方案

### 6.1 整体架构

```
┌─────────────────────────────────────────────────┐
│                 Voice Terminal App               │
│              (非沙盒 macOS App)                   │
├─────────────────────────────────────────────────┤
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
│  │ 语音输入层 │  │ LLM 解析层│  │  反馈输出层   │  │
│  │ Speech   │  │ 意图识别  │  │  TTS + 通知   │  │
│  │ Framework│  │ + 参数提取│  │  + UI 反馈    │  │
│  └────┬─────┘  └────┬─────┘  └──────┬───────┘  │
│       │              │               │           │
│  ┌────▼──────────────▼───────────────▼───────┐  │
│  │            命令调度层 (Command Router)       │  │
│  └────────────────────┬──────────────────────┘  │
│                       │                          │
│  ┌────────────────────▼──────────────────────┐  │
│  │          能力执行层 (Capability Layer)       │  │
│  ├────────────┬──────────┬──────────┬────────┤  │
│  │ AX 自动化   │ Script  │ System  │ Shell  │  │
│  │ (UI 控制)  │ Engine  │ APIs    │ Bridge │  │
│  │            │ (AS/JXA)│ (原生框架)│ (终端) │  │
│  └────────────┴──────────┴──────────┴────────┘  │
│                                                  │
│  ┌──────────────────────────────────────────┐   │
│  │      权限管理层 (Permission Manager)       │   │
│  │  TCC 检查 + 引导授权 + 状态监控              │   │
│  └──────────────────────────────────────────┘   │
│                                                  │
│  ┌──────────────────────────────────────────┐   │
│  │       App Intents 层 (系统集成)            │   │
│  │  暴露 Voice Terminal 能力给 Siri/Shortcuts │   │
│  └──────────────────────────────────────────┘   │
│                                                  │
└─────────────────────────────────────────────────┘
```

### 6.2 能力优先级排序

**第一梯队（核心能力）：**
1. Accessibility API — UI 自动化核心
2. AppleScript/JXA — 系统 App 脚本控制
3. CGEvent — 键鼠模拟
4. NSWorkspace — App 启动/管理
5. Process — Shell 命令执行

**第二梯队（增强能力）：**
6. EventKit — 日历/提醒
7. Contacts — 通讯录
8. FileManager — 文件操作
9. CoreAudio — 音量控制
10. UserNotifications — 通知

**第三梯队（扩展能力）：**
11. ScreenCaptureKit — 屏幕分析（视觉 AI 回退方案）
12. CoreBluetooth — 蓝牙管理
13. CoreWLAN — WiFi 管理
14. CoreLocation — 定位
15. App Intents — 系统集成

### 6.3 权限引导流程

```swift
struct PermissionManager {
    enum Permission: CaseIterable {
        case accessibility    // 最重要
        case automation       // AppleScript
        case microphone       // 语音输入
        case screenRecording  // 屏幕分析（可选）
        case calendar         // 日历
        case reminders        // 提醒
        case contacts         // 通讯录
        case notifications    // 通知
        case location         // 定位
        case bluetooth        // 蓝牙
    }

    // 启动时按优先级引导用户授权
    func requestCriticalPermissions() async {
        // 1. 麦克风（语音输入必需）
        await requestMicrophoneAccess()

        // 2. 辅助功能（UI 自动化必需）
        await requestAccessibilityAccess()

        // 3. 自动化（AppleScript 必需）
        // 这个在首次使用 AppleScript 时系统自动弹出
    }

    // 按需请求其他权限
    func requestPermissionIfNeeded(_ permission: Permission) async -> Bool {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted()
        case .microphone:
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        // ...其他权限检查
        }
    }
}
```

### 6.4 命令示例映射

| 语音命令 | 使用的 API | 执行方式 |
|---------|-----------|---------|
| "打开 Safari" | NSWorkspace | `workspace.launchApplication("Safari")` |
| "关闭当前窗口" | CGEvent | Cmd+W 模拟 |
| "音量调到 50%" | CoreAudio | `AudioObjectSetPropertyData` |
| "创建提醒：明天买菜" | EventKit | `EKReminder` 创建 |
| "搜索联系人张三" | Contacts | `CNContact.predicateForContacts` |
| "把这个文件移到桌面" | FileManager | `moveItem(at:to:)` |
| "播放音乐" | AppleScript | `tell app "Music" to play` |
| "截个屏" | ScreenCaptureKit | `SCScreenshotManager.captureImage` |
| "连接蓝牙耳机" | IOBluetooth | `IOBluetoothDevice.connect` |
| "打开系统设置" | URL Scheme | `x-apple.systempreferences:` |
| "执行 git status" | Process | Shell 命令 |
| "点击提交按钮" | AXUIElement | 查找按钮 → `AXPress` |
| "切换深色模式" | AppleScript | `tell app "System Events"` |
| "新建终端标签" | AppleScript + CGEvent | Cmd+T 或 AppleScript |

---

## 参考来源

### Apple 官方文档
- [AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement)
- [Accessibility API](https://developer.apple.com/documentation/accessibility/accessibility-api)
- [App Intents](https://developer.apple.com/documentation/appintents)
- [EventKit](https://developer.apple.com/documentation/eventkit)
- [Contacts](https://developer.apple.com/documentation/contacts)
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/)
- [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)
- [CoreSpotlight](https://developer.apple.com/documentation/corespotlight)
- [ServiceManagement / SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [CoreWLAN](https://developer.apple.com/documentation/corewlan)
- [IOKit](https://developer.apple.com/documentation/iokit)
- [CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:))
- [MPRemoteCommandCenter](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter)
- [UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)
- [CBCentralManager](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager)

### WWDC Sessions
- [Get to know App Intents - WWDC25](https://developer.apple.com/videos/play/wwdc2025/244/)
- [Explore new advances in App Intents - WWDC25](https://developer.apple.com/videos/play/wwdc2025/275/)
- [Meet ScreenCaptureKit - WWDC22](https://developer.apple.com/videos/play/wwdc2022/10156/)
- [Explore media metadata publishing - WWDC22](https://developer.apple.com/videos/play/wwdc2022/110338/)

### 开源项目
- [AXorcist](https://github.com/steipete/AXorcist) — Swift AXUIElement 封装
- [AXSwift](https://github.com/tmandry/AXSwift) — Swift Accessibility 封装
- [Swindler](https://github.com/tmandry/Swindler) — macOS 窗口管理库
- [macOS-use](https://github.com/browser-use/macOS-use) — AI Agent macOS 控制
- [CUA](https://github.com/trycua/cua) — Computer Use Agent 基础设施
- [Agent-S](https://github.com/simular-ai/Agent-S) — GUI Agent 框架
- [GPT-Automator](https://github.com/chidiwilliams/GPT-Automator) — 语音控制 Mac
- [MacOS-Agent](https://github.com/Computer-use-agents/MacOS-Agent) — 自然语言 macOS 控制
- [Open Interpreter](https://github.com/openinterpreter/open-interpreter) — 自然语言代码执行
- [SimplyCoreAudio](https://github.com/rnine/SimplyCoreAudio) — CoreAudio Swift 封装
- [ISSoundAdditions](https://github.com/InerziaSoft/ISSoundAdditions) — 音量控制封装
- [MonitorControl](https://github.com/MonitorControl/MonitorControl) — 显示器控制
- [macapptree](https://github.com/MacPaw/macapptree) — 无障碍树解析器

### 社区文章
- [UI Automation with AXSwift and AI](https://spin.atomicobject.com/ui-automation-axswift-ai/)
- [Accessibility Permission in macOS](https://jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html)
- [TCC Permissions Guide - macOS Sequoia](https://atlasgondal.com/macos/priavcy-and-security/app-permissions-priavcy-and-security/a-guide-to-tcc-services-on-macos-sequoia-15-0/)
- [Explainer: Permissions, privacy and TCC](https://eclecticlight.co/2025/11/08/explainer-permissions-privacy-and-tcc/)
- [Building a macOS remote control engine](https://multi.app/blog/building-a-macos-remote-control-engine)
- [Build Your Own Operator on macOS - CUA Blog](https://cua.ai/blog/build-your-own-operator-on-macos-1)
- [Open System Settings programmatically](https://blog.rampatra.com/how-to-open-macos-system-settings-or-a-specific-pane-programmatically-with-swift)
- [Introduction to Shortcuts Automation in macOS Tahoe](https://macmost.com/an-introduction-to-shortcuts-automation-in-macos-tahoe.html)
- [Shortcuts updates in iOS 26 / macOS 26](https://support.apple.com/en-us/125148)
