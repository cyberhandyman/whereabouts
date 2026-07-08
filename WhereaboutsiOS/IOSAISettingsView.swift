import SwiftUI

// Phase 111:iOS AI 设置页 —— provider 切换 + 双 provider 配置 + 用量统计 + 共用 prompt。
// 存取全部走 AISettings facade(与 macOS 同一组 UserDefaults key),两端互不冲突。
// 页面顶部常驻"图文教程"入口 —— 小白用户第一眼就能找到保姆级流程。

struct IOSAISettingsView: View {
    @State private var activeProvider: AIProvider = AISettings.activeProvider

    var body: some View {
        Form {
            guideSection
            providerSection
            usageSection
            // Phase 118:火山引擎在前(国内主力路线),Claude 在后。
            volcSection
            claudeSection
            promptSection
        }
        .navigationTitle("settings.ai.header")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { activeProvider = AISettings.activeProvider }
    }

    // MARK: - 教程 + 简介

    private var guideSection: some View {
        Section {
            Text("settings.ai.intro")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Link(destination: AppLinks.aiSetupGuide) {
                HStack(spacing: 10) {
                    GradientIconTile(systemName: "book.fill", size: 28, cornerRadius: 7)
                    Text("settings.ai.guide.link")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: "arrow.up.forward.square")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Provider 切换

    private var providerSection: some View {
        Section {
            Picker(selection: $activeProvider) {
                ForEach(AIProvider.allCases) { p in
                    Text(verbatim: p.displayName).tag(p)
                }
            } label: {
                Text("settings.ai.activeProvider")
            }
            .pickerStyle(.segmented)
            .onChange(of: activeProvider) { _, new in
                AISettings.activeProvider = new
            }
        } header: {
            Text("settings.ai.activeProvider")
        } footer: {
            Text("settings.ai.activeProvider.hint")
        }
    }

    // MARK: - 用量(Grid,列宽自适应 —— 跟 macOS Phase 110 同款)

    @State private var refreshTick = 0

    private var usageSection: some View {
        let today  = AISettings.usageToday
        let week   = AISettings.usageThisWeek
        let month  = AISettings.usageThisMonth
        let provider = AISettings.activeProvider

        return Section {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    usageHeader("settings.ai.usage.col.today")
                    usageHeader("settings.ai.usage.col.week")
                    usageHeader("settings.ai.usage.col.month")
                }
                usageRow(labelKey: "settings.ai.usage.calls", iconName: "number",
                         a: "\(today.calls)", b: "\(week.calls)", c: "\(month.calls)")
                usageRow(labelKey: "settings.ai.usage.inputTokens", iconName: "arrow.up.circle",
                         a: formatTokens(today.inputTokens),
                         b: formatTokens(week.inputTokens),
                         c: formatTokens(month.inputTokens))
                usageRow(labelKey: "settings.ai.usage.outputTokens", iconName: "arrow.down.circle",
                         a: formatTokens(today.outputTokens),
                         b: formatTokens(week.outputTokens),
                         c: formatTokens(month.outputTokens))
                if provider == .claude {
                    let m = AISettings.claudeModel
                    usageRow(labelKey: "settings.ai.usage.estimatedCost", iconName: "dollarsign.circle",
                             a: String(format: "$%.4f", today.estimatedUSDForClaude(model: m)),
                             b: String(format: "$%.4f", week.estimatedUSDForClaude(model: m)),
                             c: String(format: "$%.4f", month.estimatedUSDForClaude(model: m)))
                }
                if provider == .volcengine {
                    let inP  = AISettings.volcInputPricePerMillionCNY
                    let outP = AISettings.volcOutputPricePerMillionCNY
                    if inP > 0 || outP > 0 {
                        usageRow(labelKey: "settings.ai.usage.estimatedCost", iconName: "yensign.circle",
                                 a: String(format: "¥%.4f", today.estimatedCNYForVolcengine(inputPricePerMillion: inP, outputPricePerMillion: outP)),
                                 b: String(format: "¥%.4f", week.estimatedCNYForVolcengine(inputPricePerMillion: inP, outputPricePerMillion: outP)),
                                 c: String(format: "¥%.4f", month.estimatedCNYForVolcengine(inputPricePerMillion: inP, outputPricePerMillion: outP)))
                    }
                }
            }
            Button("settings.ai.usage.reset", role: .destructive) {
                AISettings.resetUsage()
                refreshTick &+= 1
            }
        } header: {
            Text("settings.ai.usage.header")
        } footer: {
            Text("settings.ai.usage.footer.metric")
        }
        .id(refreshTick)
    }

    @ViewBuilder
    private func usageHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    @ViewBuilder
    private func usageRow(labelKey: LocalizedStringKey, iconName: String,
                          a: String, b: String, c: String) -> some View {
        GridRow {
            Label(labelKey, systemImage: iconName)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: a).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
            Text(verbatim: b).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
            Text(verbatim: c).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n < 1_000 { return "\(n)" }
        if n < 1_000_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return String(format: "%.2fM", Double(n) / 1_000_000)
    }

    // MARK: - Claude

    @State private var claudeKey: String = AISettings.claudeAPIKey
    @State private var claudeEndpoint: String = AISettings.claudeEndpoint
    @State private var claudeModel: ClaudeModel = AISettings.claudeModel
    @State private var showClaudeKey = false
    @State private var claudeTesting = false
    @State private var claudeTestResult: TestState?

    private var claudeSection: some View {
        Section {
            Picker(selection: $claudeModel) {
                ForEach(ClaudeModel.allCases) { m in
                    VStack(alignment: .leading) {
                        Text(verbatim: m.displayName)
                        Text(verbatim: m.tagline).font(.caption2).foregroundStyle(.secondary)
                    }
                    .tag(m)
                }
            } label: {
                Text("settings.ai.model.label")
            }
            .onChange(of: claudeModel) { _, new in AISettings.claudeModel = new }

            keyField(labelKey: "settings.ai.apiKey.label", prompt: "sk-ant-…",
                     text: $claudeKey, show: $showClaudeKey) { new in
                AISettings.claudeAPIKey = new
                claudeTestResult = nil
            }

            TextField("settings.ai.endpoint.label", text: $claudeEndpoint,
                      prompt: Text(verbatim: AIProvider.claude.defaultEndpoint))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption)
                .onChange(of: claudeEndpoint) { _, new in
                    AISettings.claudeEndpoint = new
                    claudeTestResult = nil
                }

            testRow(testing: claudeTesting, result: claudeTestResult,
                    disabled: claudeKey.trimmingCharacters(in: .whitespaces).isEmpty) {
                runClaudeTest()
            }
        } header: {
            Text("settings.ai.claude.header")
        } footer: {
            Text("settings.ai.claude.help")
        }
    }

    private func runClaudeTest() {
        claudeTesting = true
        claudeTestResult = nil
        let client = ClaudeClient(
            apiKey: claudeKey,
            endpoint: claudeEndpoint.isEmpty ? AIProvider.claude.defaultEndpoint : claudeEndpoint,
            model: claudeModel,
            systemPrompt: AISettings.systemPrompt
        )
        Task {
            do {
                try await client.testConnection()
                await MainActor.run {
                    claudeTestResult = .success; claudeTesting = false; Haptics.success()
                    // Phase 118:配置验证通过 → 直接替用户把"录入时用 AI 理解"打开
                    UserDefaults.standard.set(true, forKey: "useAIOnInput")
                }
            } catch {
                await MainActor.run {
                    claudeTestResult = .failure(error.localizedDescription)
                    claudeTesting = false
                    Haptics.warning()
                }
            }
        }
    }

    // MARK: - Volcengine

    @State private var volcKey: String = AISettings.volcAPIKey
    @State private var volcEndpoint: String = AISettings.volcEndpoint
    @State private var volcModel: String = AISettings.volcModel
    @State private var showVolcKey = false
    @State private var volcTesting = false
    @State private var volcTestResult: TestState?
    @State private var volcInPrice: String = AISettings.volcInputPricePerMillionCNY > 0
        ? String(AISettings.volcInputPricePerMillionCNY) : ""
    @State private var volcOutPrice: String = AISettings.volcOutputPricePerMillionCNY > 0
        ? String(AISettings.volcOutputPricePerMillionCNY) : ""

    private var volcSection: some View {
        Section {
            // Phase 118:模型下拉(推荐置顶)+ 自由输入并存 —— 下拉选中直接覆盖输入框。
            HStack {
                TextField("settings.ai.volc.model.label", text: $volcModel,
                          prompt: Text(verbatim: VolcModelPreset.recommended + " 或 ep-xxxxx"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: volcModel) { _, new in
                        AISettings.volcModel = new
                        volcTestResult = nil
                    }
                Menu {
                    ForEach(VolcModelPreset.all, id: \.id) { preset in
                        Button {
                            volcModel = preset.id
                        } label: {
                            if preset.id == volcModel {
                                Label(preset.label, systemImage: "checkmark")
                            } else {
                                Text(verbatim: preset.label)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(IOSTheme.accent)
                }
            }

            keyField(labelKey: "settings.ai.apiKey.label", prompt: "Volcengine API Key",
                     text: $volcKey, show: $showVolcKey) { new in
                AISettings.volcAPIKey = new
                volcTestResult = nil
            }

            TextField("settings.ai.endpoint.label", text: $volcEndpoint,
                      prompt: Text(verbatim: AIProvider.volcengine.defaultEndpoint))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption)
                .onChange(of: volcEndpoint) { _, new in
                    AISettings.volcEndpoint = new
                    volcTestResult = nil
                }

            LabeledContent("settings.ai.volc.inputPrice.label") {
                TextField("settings.ai.volc.inputPrice.label", text: $volcInPrice,
                          prompt: Text(verbatim: "0.80"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .labelsHidden()
                    .onChange(of: volcInPrice) { _, new in
                        AISettings.volcInputPricePerMillionCNY = Double(new) ?? 0
                    }
            }
            LabeledContent("settings.ai.volc.outputPrice.label") {
                TextField("settings.ai.volc.outputPrice.label", text: $volcOutPrice,
                          prompt: Text(verbatim: "2.00"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .labelsHidden()
                    .onChange(of: volcOutPrice) { _, new in
                        AISettings.volcOutputPricePerMillionCNY = Double(new) ?? 0
                    }
            }

            testRow(testing: volcTesting, result: volcTestResult,
                    disabled: volcKey.trimmingCharacters(in: .whitespaces).isEmpty
                              || volcModel.trimmingCharacters(in: .whitespaces).isEmpty) {
                runVolcTest()
            }
        } header: {
            Text("settings.ai.volc.header")
        } footer: {
            VStack(alignment: .leading, spacing: 3) {
                Text("settings.ai.volc.help")
                Text("settings.ai.volc.price.help")
            }
        }
    }

    private func runVolcTest() {
        volcTesting = true
        volcTestResult = nil
        let client = VolcengineClient(
            apiKey: volcKey,
            endpoint: volcEndpoint.isEmpty ? AIProvider.volcengine.defaultEndpoint : volcEndpoint,
            model: volcModel,
            systemPrompt: AISettings.systemPrompt
        )
        Task {
            do {
                try await client.testConnection()
                await MainActor.run {
                    volcTestResult = .success; volcTesting = false; Haptics.success()
                    // Phase 118:配置验证通过 → 直接替用户把"录入时用 AI 理解"打开
                    UserDefaults.standard.set(true, forKey: "useAIOnInput")
                }
            } catch {
                await MainActor.run {
                    volcTestResult = .failure(error.localizedDescription)
                    volcTesting = false
                    Haptics.warning()
                }
            }
        }
    }

    // MARK: - Prompt

    @State private var systemPrompt: String = AISettings.systemPrompt

    private var promptSection: some View {
        Section {
            TextEditor(text: $systemPrompt)
                .font(.system(.caption2, design: .monospaced))
                .frame(minHeight: 140)
                .onChange(of: systemPrompt) { _, new in
                    AISettings.systemPrompt = new
                }
            Button("settings.ai.prompt.reset") {
                systemPrompt = AISettings.defaultSystemPrompt
                AISettings.systemPrompt = systemPrompt
            }
        } header: {
            Text("settings.ai.prompt.label")
        } footer: {
            Text("settings.ai.prompt.hint")
        }
    }

    // MARK: - 共用小组件

    enum TestState: Equatable {
        case success
        case failure(String)
    }

    /// API key 输入行:SecureField / TextField 切换 + 小眼睛。
    @ViewBuilder
    private func keyField(labelKey: LocalizedStringKey, prompt: String,
                          text: Binding<String>, show: Binding<Bool>,
                          onChange: @escaping (String) -> Void) -> some View {
        HStack {
            Group {
                if show.wrappedValue {
                    TextField(labelKey, text: text, prompt: Text(verbatim: prompt))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField(labelKey, text: text, prompt: Text(verbatim: prompt))
                }
            }
            Button {
                show.wrappedValue.toggle()
            } label: {
                Image(systemName: show.wrappedValue ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .onChange(of: text.wrappedValue) { _, new in onChange(new) }
    }

    /// 测试连接行:按钮 + 结果标签。
    @ViewBuilder
    private func testRow(testing: Bool, result: TestState?, disabled: Bool,
                         action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: action) {
                if testing {
                    ProgressView().controlSize(.small)
                } else {
                    Text("settings.ai.test.button")
                }
            }
            .disabled(testing || disabled)
            switch result {
            case .success:
                Text("settings.ai.test.success")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failure(let msg):
                Text("settings.ai.test.failed \(msg)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            case nil:
                EmptyView()
            }
            Spacer()
        }
    }
}
