import SwiftUI
import Carbon

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case home = "首页"
    case voiceInput = "语音输入"
    case voiceAgent = "语音 Agent"
    case settings = "设置"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house"
        case .voiceInput: return "waveform"
        case .voiceAgent: return "sparkles.rectangle.stack"
        case .settings: return "gearshape"
        }
    }
}

struct MainWorkspaceView: View {
    @State private var selection: WorkspaceSection = .home

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(minWidth: 980, minHeight: 640)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VoiceInput")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.top, 16)
                .padding(.horizontal, 14)

            ForEach(WorkspaceSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.icon)
                            .frame(width: 16)
                        Text(section.rawValue)
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(selection == section ? Color.accentColor.opacity(0.16) : Color.clear)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(10)
        .frame(width: 172)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.65))
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .home:
            HomePanelView()
        case .voiceInput:
            SettingsView(embedded: true, initialTab: .voiceInput)
        case .voiceAgent:
            VoiceAgentPanelView()
        case .settings:
            SettingsView(embedded: true, initialTab: .general)
        }
    }
}

struct HomePanelView: View {
    @ObservedObject private var session = RealtimeSessionStore.shared
    @State private var itemCount = 0

    private var currentHotkeyText: String {
        let modifiers = SharedSettings.defaults.object(forKey: SharedSettings.Keys.hotkeyModifiers) as? Int ?? HotkeyConfig.defaultModifiers
        let keyCode = SharedSettings.defaults.object(forKey: SharedSettings.Keys.hotkeyKeyCode) as? Int ?? HotkeyConfig.defaultKeyCode
        return HotkeyConfig.displayString(modifiers: modifiers, keyCode: keyCode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("首页")
                .font(.largeTitle)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                HomeStatCard(title: "当前状态", value: session.stageText)
                HomeStatCard(title: "历史记录", value: "\(itemCount)")
                HomeStatCard(title: "当前热键", value: currentHotkeyText)
                HomeStatCard(title: "热键状态", value: SharedSettings.defaults.string(forKey: SharedSettings.Keys.hotkeyRuntimeStatus) ?? "未知")
            }

            HistoryPanelView()
        }
        .padding(24)
        .onAppear {
            itemCount = InputHistoryStore.shared.all().count
        }
    }
}


struct HomeStatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial)
        .cornerRadius(12)
    }
}

struct RealtimePanelView: View {
    @ObservedObject private var session = RealtimeSessionStore.shared
    @State private var itemCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("实时输入")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                Spacer()
                Text(session.stageText)
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(999)
            }

            HStack(spacing: 12) {
                HomeStatCard(title: "当前状态", value: session.stageText)
                HomeStatCard(title: "历史记录", value: "\(itemCount)")
                HomeStatCard(title: "热键状态", value: SharedSettings.defaults.string(forKey: SharedSettings.Keys.hotkeyRuntimeStatus) ?? "未知")
            }

            HStack(spacing: 10) {
                Image(systemName: "person.wave.2.fill")
            }
            .font(.headline)
            .frame(width: 36, height: 36)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(12)

            TranscriptStreamBox(
                title: "实时原声输入",
                text: session.originalLiveText,
                placeholder: "按快捷键或点击下方按钮后开始说话，原声会在这里实时滚动显示。"
            )

            TranscriptStreamBox(
                title: "Thinking 改写结果",
                text: session.rewrittenText,
                placeholder: "停止输入后，系统进入 Thinking 模式并输出改写结果。"
            )

            HStack(spacing: 10) {
                Button("开始/停止说话输入") {
                    AppHotkeyVoiceService.shared.toggleFromUI()
                }
                .buttonStyle(.borderedProminent)

                Button("复制改写结果") {
                    let text = session.rewrittenText
                    guard !text.isEmpty else { return }
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding(24)
        .onAppear {
            itemCount = InputHistoryStore.shared.all().count
        }
    }
}

struct VoiceAgentPanelView: View {
    @ObservedObject private var session = VoiceAgentSessionStore.shared

    private var currentHotkeyText: String {
        let modifiers = SharedSettings.defaults.object(forKey: SharedSettings.Keys.terminalHotkeyModifiers) as? Int ?? 4096
        let keyCode = SharedSettings.defaults.object(forKey: SharedSettings.Keys.terminalHotkeyKeyCode) as? Int ?? 49
        return HotkeyConfig.displayString(modifiers: modifiers, keyCode: keyCode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("语音 Agent")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                Spacer()
                Text(session.stageText)
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(999)
            }

            HStack(spacing: 12) {
                HomeStatCard(title: "当前状态", value: session.stageText)
                HomeStatCard(title: "Agent 热键", value: currentHotkeyText)
                HomeStatCard(title: "结果状态", value: session.stage.rawValue)
            }

            TranscriptStreamBox(
                title: "实时语音转写",
                text: session.liveText,
                placeholder: "按住 Voice Agent 热键后开始说话，实时文字会在这里出现。"
            )

            TranscriptStreamBox(
                title: "系统理解的意图",
                text: session.intentText,
                placeholder: "系统理解后的动作会显示在这里，例如打开应用、查询天气或执行命令。"
            )

            AgentResultBox(
                title: "执行结果",
                text: session.resultText,
                placeholder: "执行完成后的结果、错误或结构化反馈会显示在这里。"
            )

            HStack(spacing: 10) {
                Button(session.stage == .listening ? "停止 Voice Agent" : "启动 Voice Agent") {
                    VoiceTerminalService.shared.toggleFromUI()
                }
                .buttonStyle(.borderedProminent)

                Button("清空状态") {
                    VoiceAgentSessionStore.shared.reset()
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding(24)
    }
}

struct TranscriptStreamBox: View {
    let title: String
    let text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ScrollViewReader { hProxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 8) {
                        Text(text.isEmpty ? placeholder : text)
                            .foregroundStyle(text.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .id("tail")
                        Color.clear.frame(width: 1, height: 1).id("end")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                }
                .background(.thinMaterial)
                .cornerRadius(12)
                .frame(height: 56)
                .frame(maxWidth: 860)
                .onChange(of: text) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        hProxy.scrollTo("end", anchor: .trailing)
                    }
                }
            }
        }
    }
}

struct AgentResultBox: View {
    let title: String
    let text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ScrollView {
                Text(text.isEmpty ? placeholder : text)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
            }
            .background(.thinMaterial)
            .cornerRadius(12)
            .frame(minHeight: 96, maxHeight: 180)
            .frame(maxWidth: 860)
        }
    }
}

private enum HistoryFilter: String, CaseIterable {
    case all = "全部"
    case success = "成功"
    case issue = "异常"
}

struct HistoryPanelView: View {
    @State private var items: [InputHistoryItem] = []
    @State private var filter: HistoryFilter = .all
    @State private var retryingId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("历史记录")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                Spacer()
                Picker("筛选", selection: $filter) {
                    ForEach(HistoryFilter.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Button("刷新") { refresh() }
                    .buttonStyle(.bordered)
            }

            Text("最多保留 100 条")
                .foregroundStyle(.secondary)

            List(filteredItems) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(statusLabel(item.status))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(4)
                        Text(Date(timeIntervalSince1970: item.timestamp), style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    Text("原始：\(item.originalText)")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text("改写：\(item.finalText)")
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Button("复制原始") { copy(item.originalText) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("复制改写") { copy(item.finalText) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button(retryingId == item.id ? "重试中..." : "重试改写") {
                            retryPolish(item)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(retryingId == item.id)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(24)
        .onAppear(perform: refresh)
    }

    private var filteredItems: [InputHistoryItem] {
        switch filter {
        case .all:
            return items
        case .success:
            return items.filter { $0.status == .inserted }
        case .issue:
            return items.filter { $0.status != .inserted }
        }
    }

    private func refresh() {
        items = InputHistoryStore.shared.all()
    }

    private func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func statusLabel(_ status: InputDeliveryStatus) -> String {
        switch status {
        case .inserted: return "已注入"
        case .pendingCopy: return "待复制"
        case .copied: return "已复制"
        }
    }

    private func retryPolish(_ item: InputHistoryItem) {
        retryingId = item.id
        let baseURL = SharedSettings.defaults.string(forKey: SharedSettings.Keys.llmAPIBaseURL) ?? "https://oneapi.gemiaude.com/v1"
        let apiKey = SharedSettings.defaults.string(forKey: SharedSettings.Keys.llmAPIKey) ?? ""
        let model = SharedSettings.defaults.string(forKey: SharedSettings.Keys.voiceInputModel) ?? "gemini-2.5-flash-lite"

        let local = TextProcessor().process(item.originalText)
        Task {
            defer {
                DispatchQueue.main.async { retryingId = nil }
            }
            let finalText: String
            if SharedSettings.defaults.object(forKey: SharedSettings.Keys.llmEnabled) as? Bool ?? false {
                do {
                    finalText = try await PolishClient().polish(
                        text: local,
                        style: item.style,
                        model: model,
                        baseURL: baseURL,
                        apiKey: apiKey
                    )
                } catch {
                    finalText = local
                }
            } else {
                finalText = local
            }

            InputHistoryStore.shared.append(
                InputHistoryItem(
                    originalText: item.originalText,
                    processedText: local,
                    finalText: finalText,
                    style: item.style,
                    status: .copied,
                    note: "history_retry"
                )
            )
            RealtimeSessionStore.shared.updateRewrittenText(finalText)
            DispatchQueue.main.async {
                refresh()
            }
        }
    }
}

struct SettingsPanelView: View {
    var body: some View {
        SettingsView(embedded: true)
            .padding(24)
    }
}
