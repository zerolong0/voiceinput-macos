# VoiceInput macOS 项目交接文档

## 项目概述

**项目名称**: VoiceInput (语音输入法)
**目标**: 构建类似 Typeless 的跨平台语音输入法
**当前状态**: macOS 主应用开发中，核心引导流程基本完成

---

## 项目结构

```
voiceinput-macos/
├── Sources/
│   ├── App/                    # 主应用
│   │   ├── main.swift          # 应用入口
│   │   ├── AppDelegate.swift   # 应用代理
│   │   ├── OnboardingView.swift # 引导流程视图
│   │   ├── SettingsView.swift  # 设置视图
│   │   └── Info.plist
│   ├── IM/                     # 输入法模块
│   │   ├── main.swift
│   │   ├── VoiceInputController.swift
│   │   └── Info.plist
│   └── Shared/                 # 共享模块
│       ├── AudioCapture/        # 音频采集
│       ├── Whisper/            # 语音识别
│       ├── TextProcessing/     # 文本处理
│       └── SceneDetector.swift # 场景检测
├── Resources/
│   └── Assets.xcassets
└── project.yml                 # XcodeGen 配置
```

---

## 待解决的核心问题

### 🔴 P0 - 辅助功能权限检测问题

**问题描述**:
- 用户在系统设置中开启了辅助功能权限后，应用的 `AXIsProcessTrusted()` 仍返回 `false`
- 这是 macOS TCC (Transparency, Consent, and Control) 权限缓存问题

**可能原因**:
1. 每次 ad-hoc 签名 (`CODE_SIGN_IDENTITY: "-"`) 可能产生不同的代码签名标识
2. TCC 数据库中可能有旧的脏数据
3. 应用需要完全重启才能刷新权限状态

**已尝试的方案**:
1. ✅ 使用 `AXIsProcessTrustedWithOptions()` 带参数检查
2. ✅ 添加延迟刷新机制 (0.5s, 1s, 2s)
3. ✅ 添加手动"刷新权限状态"按钮
4. ✅ 在应用激活时刷新权限

**建议的后续方案**:
1. **方案A**: 使用固定签名 - 在 project.yml 中配置固定的 ad-hoc 签名参数，确保每次编译产生相同的签名
2. **方案B**: 使用开发者签名 - 配置有效的 Apple Developer 签名
3. **方案C**: 改用 `kAXTrustedCheckOptionPrompt` 强制触发系统授权对话框，让用户通过系统对话框授权而不是手动添加
4. **方案D**: 检查是否需要将应用打包成 .app 后安装到 /Applications 才能正确识别权限

**相关代码位置**:
- `Sources/App/OnboardingView.swift` - `refreshPermissionStatus()` 函数 (约第116行)
- `Sources/App/SettingsView.swift` - `refreshStatus()` 函数 (约第194行)

---

### 🟡 P1 - 其他功能待完成

1. **快捷键设置功能**
   - 当前显示固定 "Option + Space"
   - 需要实现可配置的全局热键

2. **输入法集成**
   - `VoiceInputIM` target 已创建但功能未完成
   - 需要实现 Input Method Kit 集成

3. **音频采集与语音识别**
   - 模块框架已搭建，需要实现具体逻辑

---

## 已实现功能

✅ 完整的引导流程 (4步)
- 欢迎页
- 权限授权页 (麦克风、语音识别、辅助功能)
- 风格选择页 (智能模式、商务正式、日常聊天、Vibe Coding)
- 完成页

✅ 设置页面
- 显示当前快捷键
- 风格选择
- 权限状态显示
- 使用说明
- "重新引导"按钮
- 打开系统设置入口

✅ 权限刷新机制
- 应用激活时自动刷新
- 延迟多次刷新
- 手动刷新按钮

---

## 构建与运行

```bash
# 生成 Xcode 项目
xcodegen generate

# 构建
xcodebuild -project VoiceInput.xcodeproj -scheme VoiceInput -configuration Debug build

# 运行
open ~/Library/Developer/Xcode/DerivedData/VoiceInput-*/Build/Products/Debug/VoiceInput.app
```

---

## 技术栈

- **UI**: SwiftUI + AppKit
- **权限**: AVFoundation, Speech, ApplicationServices (Accessibility)
- **输入法**: InputMethodKit
- **项目生成**: XcodeGen

---

## 下一步建议

1. **优先解决辅助功能权限问题** - 这是用户体验的关键阻塞点
2. **完成快捷键设置功能**
3. **实现输入法模块**
4. **集成音频采集和语音识别**

---

## 相关文档

- 项目规划: `/Users/zerolong/Documents/AICODE/best/InputLess/voiceinput-macos/.claude/plans/idempotent-snuggling-torvalds.md`
