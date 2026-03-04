# Voice Terminal 能力扩展建议报告

**日期**: 2026-03-04
**综合来源**: macOS Native APIs 调研 / 25+ 开源项目调研 / Apple 官方文档调研

---

## 一、当前状态

Voice Terminal (Mode 2) 已实现 4 种 Agent：

| Agent | 技术 | 状态 |
|-------|------|------|
| CalendarAgent | EventKit | ✅ 已实现 |
| NotesAgent | AppleScript | ✅ 已实现 |
| AppLauncherAgent | NSWorkspace + 别名表 | ✅ 已实现 |
| CLIAgent | Process + /bin/zsh | ✅ 已实现 |

---

## 二、扩展建议（按优先级排序）

### 🟥 Phase 2 — 高优先级（用户价值高 + 实现简单）

| # | 新 Agent | 技术方案 | 工作量 | 新 IntentType |
|---|----------|----------|--------|---------------|
| 1 | **ShortcutsAgent** | `Process("/usr/bin/shortcuts", ["run", name])` | Small | `runShortcut` |
| 2 | **MediaControlAgent** | AppleScript: `tell app "Music" to play/pause/next` + media key 模拟 | Small | `mediaControl` |
| 3 | **VolumeAgent** | AppleScript: `set volume output volume X` | Small | `volumeControl` |
| 4 | **ReminderAgent** | EventKit `EKReminder` (复用已有 EKEventStore) | Small | `addReminder` |
| 5 | **TimerAgent** | `UNUserNotificationCenter` 定时通知 | Small | `setTimer` |
| 6 | **URLSchemeAgent** | `NSWorkspace.shared.open(URL)` — 统一 URL Scheme 调度 | Small | `openURL` |

**理由**: 这 6 个 Agent 都是单文件实现（50-100行），不需要新的 framework 依赖，能覆盖日常高频语音命令。

**示例语音命令**:
- "运行快捷指令 早间流程" → ShortcutsAgent
- "暂停音乐" / "下一首" → MediaControlAgent
- "音量调到 50" / "静音" → VolumeAgent
- "提醒我明天下午三点开会" → ReminderAgent
- "设个 5 分钟的计时器" → TimerAgent
- "打电话给 John" → URLSchemeAgent (`facetime-audio:`)

---

### 🟧 Phase 3 — 中优先级（需要额外权限或较复杂）

| # | 新 Agent | 技术方案 | 工作量 | 备注 |
|---|----------|----------|--------|------|
| 7 | **AppControlAgent** | NSWorkspace: `runningApplications`, `terminate()`, `hide()` | Medium | 退出/隐藏/列出运行中的 App |
| 8 | **ContactsAgent** | Contacts framework: `CNContactStore` | Medium | 需要 `NSContactsUsageDescription` |
| 9 | **FileAgent** | FileManager + NSWorkspace | Medium | 打开/移动/查找文件 |
| 10 | **MailComposeAgent** | `mailto:` URL Scheme + AppleScript | Medium | 发邮件/草稿 |
| 11 | **MessageAgent** | `imessage:` / `sms:` URL Scheme | Small | 发消息 |
| 12 | **BrightnessAgent** | AppleScript / IOKit | Medium | 屏幕亮度调节 |

---

### 🟨 Phase 4 — 战略级（架构变更，高价值）

| # | 能力 | 技术方案 | 工作量 | 价值 |
|---|------|----------|--------|------|
| 13 | **UI 自动化** | AXUIElement (推荐用 [AXorcist](https://github.com/steipete/AXorcist) 库) | Large | 控制任意 App 的 UI 元素 |
| 14 | **AppleScript 脚本库** | 移植 [macos-automator-mcp](https://github.com/steipete/macos-automator-mcp) 200+ 脚本 | Large | 覆盖大量系统操作 |
| 15 | **本地 LLM** | Foundation Models framework (macOS 26) 或 MLX + llama.cpp | Large | 免费、隐私、低延迟意图识别 |
| 16 | **MCP Server** | 将 Voice Terminal Agent 暴露为 MCP 工具 | Medium | 可被其他 AI 工具调用 |
| 17 | **App Intents** | 注册 `AppShortcutsProvider` | Medium | 被 Siri/Shortcuts/Spotlight 发现 |

---

## 三、关键架构建议

### 3.1 推荐技术栈分层

```
语音输入层
  └─ Apple Speech / WhisperEngine (已有)
      │
意图解析层
  └─ OpenAI-compatible LLM (已有)
  └─ Foundation Models (macOS 26, 未来)
      │
命令调度层
  └─ CommandRouter (已有, 需扩展 IntentType)
      │
能力执行层
  ├─ URL Schemes      → 零权限系统 App 触发
  ├─ EventKit         → 日历 + 提醒事项 CRUD
  ├─ AppleScript      → 脚本化 App 控制 (Notes, Mail, Music, Finder, Safari)
  ├─ Shortcuts CLI    → 用户自定义快捷指令
  ├─ NSWorkspace      → App 生命周期管理
  ├─ AXUIElement      → 通用 UI 自动化 (Phase 4)
  ├─ Process          → Shell 命令执行
  └─ UNNotification   → 计时器 + 提醒
```

### 3.2 分发策略

**必须使用 App Store 外分发**（公证 + 直接下载）：

| 能力 | 沙盒内 | 非沙盒 |
|------|--------|--------|
| Accessibility API | ❌ | ✅ |
| AppleScript (无限制) | ❌ | ✅ |
| Process/Shell | ❌ | ✅ |
| Shortcuts CLI | 有 Bug | ✅ |
| URL Schemes | ✅ | ✅ |
| EventKit | ✅ | ✅ |

### 3.3 权限要求汇总

| 权限 | Info.plist Key | 影响的 Agent |
|------|---------------|-------------|
| 麦克风 | `NSMicrophoneUsageDescription` | 所有 (STT) |
| 语音识别 | `NSSpeechRecognitionUsageDescription` | 所有 (STT) |
| 辅助功能 | TCC Accessibility | Hotkey + UI 自动化 |
| 日历 | `NSCalendarsUsageDescription` | CalendarAgent |
| 提醒事项 | `NSRemindersUsageDescription` | ReminderAgent |
| 通讯录 | `NSContactsUsageDescription` | ContactsAgent |
| Apple Events | `NSAppleEventsUsageDescription` | NotesAgent, MediaControlAgent 等 |
| 通知 | UNNotification (自动授权) | TimerAgent |

### 3.4 开源项目值得参考

| 项目 | 用途 | 推荐程度 |
|------|------|----------|
| [AXorcist](https://github.com/steipete/AXorcist) | Swift AX API 封装，模糊匹配 | ⭐⭐⭐ 强烈推荐作为 SPM 依赖 |
| [macos-automator-mcp](https://github.com/steipete/macos-automator-mcp) | 200+ AppleScript/JXA 脚本 | ⭐⭐⭐ 移植核心脚本 |
| [Ghost OS](https://github.com/ghostwright/ghost-os) | AX tree + 自学习工作流 | ⭐⭐ 架构参考 |
| [MacEcho](https://github.com/realtime-ai/mac-echo) | MLX 本地语音 pipeline | ⭐⭐ 本地化参考 |
| [GPT-Automator](https://github.com/chidiwilliams/GPT-Automator) | 语音→LLM→AppleScript | ⭐⭐ 概念验证参考 |

### 3.5 未来战略方向

1. **Foundation Models (macOS 26)** — Apple 提供免费的 ~3B 参数端侧 LLM，支持 tool calling。当 macOS 26 发布时，可替代/补充云端 LLM 做意图识别，实现零成本、完全隐私的语音控制。

2. **App Intents 集成** — 注册 `AppShortcutsProvider`，让 Voice Terminal 的能力被 Siri/Shortcuts/Spotlight 发现和调用，形成双向集成。

3. **MCP Server 暴露** — 将 Agent 能力暴露为 MCP 工具，可被 Claude Code、Cursor 等 AI 工具直接调用。

---

## 四、推荐实施路线图

```
Phase 2 (当前优先):
  Week 1: ShortcutsAgent + VolumeAgent + MediaControlAgent
  Week 2: ReminderAgent + TimerAgent + URLSchemeAgent
  Week 2: IntentRecognizer prompt 扩展 (新增 6 种 IntentType)

Phase 3 (下一阶段):
  AppControlAgent + ContactsAgent + FileAgent
  MailComposeAgent + MessageAgent + BrightnessAgent
  权限管理 UI 完善

Phase 4 (战略投入):
  AXUIElement UI 自动化 (AXorcist 集成)
  AppleScript 脚本库 (移植 macos-automator-mcp)
  App Intents 注册
  MCP Server 暴露

Phase 5 (macOS 26):
  Foundation Models 本地 LLM
  MLX Whisper 本地 STT (可选)
```

---

## 五、风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| TCC 授权复杂性 | 用户体验差 | 已实现 `resetAndReauthorize()` 自动恢复 |
| AppleScript 注入 | 安全漏洞 | 已有输入转义，需持续审计 |
| 非沙盒分发限制 | 无法上 App Store | 使用 notarization + 直接下载 |
| LLM 依赖云端 | 延迟/成本/隐私 | macOS 26 Foundation Models 解决 |
| AXUIElement API 变更 | 跨版本兼容 | 用 AXorcist 库隔离底层变化 |
| CLI Agent 安全风险 | 危险命令执行 | 已有黑名单，需持续扩充 |

---

## 附录：详细调研报告

- [macOS 原生 API 调研](docs/research-macos-native-apis.md) — 17 个框架详细分析
- [开源项目调研](docs/research-opensource-projects.md) — 25+ 个项目分析
- [Apple 官方文档调研](docs/research-apple-official-docs.md) — App Intents, Shortcuts, Foundation Models 等
