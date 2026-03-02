# Whisper.cpp 集成指南

## 概述

VoiceInput 使用 whisper.cpp 进行本地语音识别。本模块提供了 Swift 封装层 `WhisperEngine` 和 `StreamingWhisperRecognizer`。

## 系统要求

- macOS 12.0+
- Xcode 15.0+
- Homebrew (用于安装编译工具)

## 编译 whisper.cpp

### 1. 安装编译依赖

```bash
# 安装 CMake 和其他编译工具
brew install cmake
```

### 2. 克隆并编译 whisper.cpp

```bash
# 克隆 whisper.cpp 仓库
cd /path/to/your/projects
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp

# 创建构建目录
mkdir -p build && cd build

# 使用 CMake 配置（启用 CoreML 支持）
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_COREML=ON \
    -DWHISPER_METAL=ON \
    -DWHISPER_KEEP_LANGUAGE_MODELS=ON

# 编译静态库
make -j$(sysctl -n hw.ncpu) libwhisper.a
```

### 3. 复制库文件到项目

```bash
# 复制编译好的库文件
cp build/libwhisper.a /Users/zerolong/Documents/AICODE/best/InputLess/voiceinput-macos/Sources/Whisper/

# 复制头文件
cp -r ../src /Users/zerolong/Documents/AICODE/best/InputLess/voiceinput-macos/Sources/Whisper/
```

## 下载模型

### 推荐模型

| 模型 | 大小 | 描述 |
|------|------|------|
| ggml-base.bin | 141 MB | 基础英文模型 |
| ggml-base-cn.bin | 153 MB | 基础中文模型 |
| ggml-medium.bin | 1.5 GB | 中等精度，支持中文 |
| ggml-small.bin | 487 MB | 小型模型，支持中文 |

### 下载命令

```bash
# 创建模型目录
mkdir -p ~/Library/Application\ Support/VoiceInput/Models
cd ~/Library/Application\ Support/VoiceInput/Models

# 下载基础中文模型
curl -L -o ggml-base-cn.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-cn.bin

# 或者下载更大的模型（推荐用于更好的准确性）
curl -L -o ggml-medium.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin
```

## 使用方法

### 1. 加载模型

```swift
import Whisper

let whisperEngine = WhisperEngine()

// 设置语言
whisperEngine.language = .chinese
whisperEngine.threads = 4

// 加载模型
do {
    let modelPath = NSHomeDirectory() + "/Library/Application Support/VoiceInput/Models/ggml-base-cn.bin"
    try whisperEngine.loadModel(from: modelPath)
    print("Model loaded: \(whisperEngine.modelInfo)")
} catch {
    print("Error loading model: \(error)")
}
```

### 2. 离线转录

```swift
// 从音频文件转录
func transcribeAudioFile(path: String) {
    // 读取音频文件（需要转换到 16kHz mono float32）
    // ... 音频处理代码 ...

    do {
        let result = try whisperEngine.transcribe(buffer: audioBuffer)
        print("Transcribed: \(result.text)")
        for segment in result.segments {
            print("[\(segment.startTime)s -> \(segment.endTime)s] \(segment.text)")
        }
    } catch {
        print("Transcription error: \(error)")
    }
}
```

### 3. 流式识别

```swift
// 创建音频捕获管理器
let audioCaptureManager = AudioCaptureManager()

// 创建流式识别器
let recognizer = StreamingWhisperRecognizer(
    whisperEngine: whisperEngine,
    audioCaptureManager: audioCaptureManager
)

// 设置委托
recognizer.delegate = self

// 配置
recognizer.useVAD = true
recognizer.maxSilenceDuration = 2.0

// 开始识别
do {
    try recognizer.start()
} catch {
    print("Error starting recognition: \(error)")
}
```

### 4. 集成到输入控制器

```swift
// 在 VoiceInputController 中集成
class VoiceInputController: IMKInputController {
    private var whisperEngine: WhisperEngine?
    private var recognizer: StreamingWhisperRecognizer?
    private var audioCaptureManager: AudioCaptureManager?

    private func setupWhisper() {
        // 初始化引擎
        whisperEngine = WhisperEngine()
        audioCaptureManager = AudioCaptureManager()
        recognizer = StreamingWhisperRecognizer(
            whisperEngine: whisperEngine!,
            audioCaptureManager: audioCaptureManager!
        )

        // 加载模型
        let modelPath = NSHomeDirectory() + "/Library/Application Support/VoiceInput/Models/ggml-base-cn.bin"
        try? whisperEngine?.loadModel(from: modelPath)

        // 设置回调
        recognizer?.delegate = self
    }
}
```

## 性能优化

### Apple Silicon 优化

```bash
# 使用 Metal 加速
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_METAL=ON
```

### 使用 Neural Engine

```bash
# 启用 CoreML 加速（需要 macOS 13+）
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_COREML=ON
```

### 线程数设置

```swift
// 根据 CPU 核心数设置线程
let processorCount = ProcessInfo.processInfo.processorCount
whisperEngine.threads = max(2, processorCount - 2)
```

## 故障排除

### 编译错误

**问题**: `whisper.h not found`

**解决**: 确保已正确复制头文件到项目目录

**问题**: `Undefined symbols: whisper_full`

**解决**: 确保链接了 `libwhisper.a` 静态库

### 运行时错误

**问题**: `Model not found`

**解决**: 检查模型文件路径是否正确

**问题**: `Invalid audio format`

**解决**: 确保音频是 16kHz mono float32 格式

## 文件结构

```
Sources/Whisper/
├── WhisperBridge.h      # 桥接头文件（C 函数声明）
├── WhisperEngine.swift  # 主要引擎类
└── libwhisper.a         # 编译后的静态库（需要自行编译）
```

## 许可证

whisper.cpp 使用 MIT 许可证。详情请查看 https://github.com/ggerganov/whisper.cpp
