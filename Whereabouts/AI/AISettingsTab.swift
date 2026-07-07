import SwiftUI

/// 偏好设置 → AI tab。
/// 上半:provider 选择。
/// 中半:两个 provider 的配置同时展示(用户可以预先填好两家,然后切 active)。
/// 下半:共用 system prompt + 测试。
///
/// 各小节拆成独立子 View,避免主 View body 修饰符链过长触发 SwiftUI 的 type-check 超时。
struct AISettingsTab: View {
    @State private var activeProvider: AIProvider = AISettings.activeProvider

    var body: some View {
        Form {
            introSection
            providerPickerSection
            UsageSection()
            ClaudeProviderSection()
            VolcengineProviderSection()
            SharedPromptSection()
        }
        .formStyle(.grouped)
        .onAppear {
            activeProvider = AISettings.activeProvider
        }
    }

    @ViewBuilder
    private var introSection: some View {
        Section {
            Text("settings.ai.intro")
                .font(.callout)
                .foregroundStyle(.secondary)
            // Phase 113:小白友好的网页版图文教程 —— 注册、充值、拿 key、填进来、
            // 常见报错,一步一图。比下面 footer 里的两行速记友好得多。
            Link(destination: AppLinks.aiSetupGuide) {
                HStack(spacing: 6) {
                    Image(systemName: "book.fill")
                    Text("settings.ai.guide.link")
                        .font(.callout.weight(.medium))
                    Image(systemName: "arrow.up.forward.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    @ViewBuilder
    private var providerPickerSection: some View {
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
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Claude

private struct ClaudeProviderSection: View {
    @State private var apiKey: String     = AISettings.claudeAPIKey
    @State private var endpoint: String   = AISettings.claudeEndpoint
    @State private var model: ClaudeModel = AISettings.claudeModel
    @State private var showKey: Bool      = false
    @State private var testing: Bool      = false
    @State private var testResult: TestResult?

    var body: some View {
        Section {
            Picker(selection: $model) {
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
            .pickerStyle(.menu)
            .onChange(of: model) { _, new in AISettings.claudeModel = new }

            TextField("settings.ai.endpoint.label", text: $endpoint,
                      prompt: Text(verbatim: AIProvider.claude.defaultEndpoint))
                .textFieldStyle(.roundedBorder)
                .onChange(of: endpoint) { _, new in
                    AISettings.claudeEndpoint = new
                    testResult = nil
                }

            apiKeyField

            HStack(spacing: 10) {
                Button(action: runTest) {
                    if testing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("settings.ai.test.button")
                    }
                }
                .disabled(testing || apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                testResultLabel
                Spacer()
            }
        } header: {
            Text("settings.ai.claude.header")
        } footer: {
            Text("settings.ai.claude.help")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var apiKeyField: some View {
        HStack {
            Group {
                if showKey {
                    TextField("settings.ai.apiKey.label", text: $apiKey,
                              prompt: Text(verbatim: "sk-ant-…"))
                } else {
                    SecureField("settings.ai.apiKey.label", text: $apiKey,
                                prompt: Text(verbatim: "sk-ant-…"))
                }
            }
            .textFieldStyle(.roundedBorder)
            Button {
                showKey.toggle()
            } label: {
                Image(systemName: showKey ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
        }
        .onChange(of: apiKey) { _, new in
            AISettings.claudeAPIKey = new
            testResult = nil
        }
    }

    @ViewBuilder
    private var testResultLabel: some View {
        switch testResult {
        case .success:
            Text("settings.ai.test.success")
                .font(.caption).foregroundStyle(.green)
        case .failure(let msg):
            Text("settings.ai.test.failed \(msg)")
                .font(.caption).foregroundStyle(.red).lineLimit(2)
        case nil:
            EmptyView()
        }
    }

    private func runTest() {
        testing = true
        testResult = nil
        // 用 当前页面里的 state 而非 AISettings 拿 —— UI 还没失焦写回时也能立刻测。
        let client = ClaudeClient(
            apiKey: apiKey,
            endpoint: endpoint.isEmpty ? AIProvider.claude.defaultEndpoint : endpoint,
            model: model,
            systemPrompt: AISettings.systemPrompt
        )
        Task {
            do {
                try await client.testConnection()
                await MainActor.run { testResult = .success; testing = false }
            } catch {
                await MainActor.run {
                    testResult = .failure(error.localizedDescription)
                    testing = false
                }
            }
        }
    }
}

// MARK: - Volcengine

private struct VolcengineProviderSection: View {
    @State private var apiKey: String   = AISettings.volcAPIKey
    @State private var endpoint: String = AISettings.volcEndpoint
    @State private var model: String    = AISettings.volcModel
    @State private var showKey: Bool    = false
    @State private var testing: Bool    = false
    @State private var testResult: TestResult?
    // Phase 107:用户自填的火山引擎单价(¥/百万 token),用 String 以便 TextField 编辑。
    @State private var inputPriceText: String  = AISettings.volcInputPricePerMillionCNY > 0
        ? String(AISettings.volcInputPricePerMillionCNY) : ""
    @State private var outputPriceText: String = AISettings.volcOutputPricePerMillionCNY > 0
        ? String(AISettings.volcOutputPricePerMillionCNY) : ""

    var body: some View {
        Section {
            TextField("settings.ai.volc.model.label", text: $model,
                      prompt: Text(verbatim: "doubao-seed-1-6-250615 或 ep-xxxxx"))
                .textFieldStyle(.roundedBorder)
                .onChange(of: model) { _, new in
                    AISettings.volcModel = new
                    testResult = nil
                }

            TextField("settings.ai.endpoint.label", text: $endpoint,
                      prompt: Text(verbatim: AIProvider.volcengine.defaultEndpoint))
                .textFieldStyle(.roundedBorder)
                .onChange(of: endpoint) { _, new in
                    AISettings.volcEndpoint = new
                    testResult = nil
                }

            apiKeyField

            // Phase 107:用户自填的火山引擎单价(¥/百万 token)。任一 > 0 时
            // 用量统计区会显示「估算费用」¥ 行。空 / 0 → 不显示估算。
            //
            // Phase 110:改 LabeledContent + 固定宽度小输入框 —— 旧版给标签钉死 140pt,
            // 中英文标签长度不同会把输入框挤到不同起点 / 标签折两行,两行排布不齐。
            // 现在标签自然宽度靠左,输入框统一 110pt 贴右,两行永远对齐。
            LabeledContent("settings.ai.volc.inputPrice.label") {
                TextField("settings.ai.volc.inputPrice.label",
                          text: $inputPriceText,
                          prompt: Text(verbatim: "0.80"))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
                    .labelsHidden()
                    .onChange(of: inputPriceText) { _, new in
                        AISettings.volcInputPricePerMillionCNY = Double(new) ?? 0
                    }
            }
            LabeledContent("settings.ai.volc.outputPrice.label") {
                TextField("settings.ai.volc.outputPrice.label",
                          text: $outputPriceText,
                          prompt: Text(verbatim: "2.00"))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
                    .labelsHidden()
                    .onChange(of: outputPriceText) { _, new in
                        AISettings.volcOutputPricePerMillionCNY = Double(new) ?? 0
                    }
            }

            HStack(spacing: 10) {
                Button(action: runTest) {
                    if testing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("settings.ai.test.button")
                    }
                }
                .disabled(testing
                          || apiKey.trimmingCharacters(in: .whitespaces).isEmpty
                          || model.trimmingCharacters(in: .whitespaces).isEmpty)
                testResultLabel
                Spacer()
            }
        } header: {
            Text("settings.ai.volc.header")
        } footer: {
            VStack(alignment: .leading, spacing: 3) {
                Text("settings.ai.volc.help")
                Text("settings.ai.volc.price.help")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var apiKeyField: some View {
        HStack {
            Group {
                if showKey {
                    TextField("settings.ai.apiKey.label", text: $apiKey,
                              prompt: Text(verbatim: "Volcengine API Key"))
                } else {
                    SecureField("settings.ai.apiKey.label", text: $apiKey,
                                prompt: Text(verbatim: "Volcengine API Key"))
                }
            }
            .textFieldStyle(.roundedBorder)
            Button {
                showKey.toggle()
            } label: {
                Image(systemName: showKey ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
        }
        .onChange(of: apiKey) { _, new in
            AISettings.volcAPIKey = new
            testResult = nil
        }
    }

    @ViewBuilder
    private var testResultLabel: some View {
        switch testResult {
        case .success:
            Text("settings.ai.test.success")
                .font(.caption).foregroundStyle(.green)
        case .failure(let msg):
            Text("settings.ai.test.failed \(msg)")
                .font(.caption).foregroundStyle(.red).lineLimit(2)
        case nil:
            EmptyView()
        }
    }

    private func runTest() {
        testing = true
        testResult = nil
        let client = VolcengineClient(
            apiKey: apiKey,
            endpoint: endpoint.isEmpty ? AIProvider.volcengine.defaultEndpoint : endpoint,
            model: model,
            systemPrompt: AISettings.systemPrompt
        )
        Task {
            do {
                try await client.testConnection()
                await MainActor.run { testResult = .success; testing = false }
            } catch {
                await MainActor.run {
                    testResult = .failure(error.localizedDescription)
                    testing = false
                }
            }
        }
    }
}

// MARK: - 共用 system prompt

private struct SharedPromptSection: View {
    @State private var systemPrompt: String = AISettings.systemPrompt

    var body: some View {
        Section {
            TextEditor(text: $systemPrompt)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 160, idealHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
                .onChange(of: systemPrompt) { _, new in
                    AISettings.systemPrompt = new
                }
            HStack {
                Spacer()
                Button("settings.ai.prompt.reset") {
                    systemPrompt = AISettings.defaultSystemPrompt
                    AISettings.systemPrompt = systemPrompt
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        } header: {
            Text("settings.ai.prompt.label")
        } footer: {
            Text("settings.ai.prompt.hint")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - 测试结果(两个 provider section 共用)

enum TestResult: Equatable {
    case success
    case failure(String)
}

// MARK: - 用量统计(Phase 88)

/// 显示三个时间窗口的用量(今天 / 本周 / 本月),口径跟 Claude / 火山引擎账单一致。
/// 数据来源 AISettings.usageToday/ThisWeek/ThisMonth。
private struct UsageSection: View {
    /// 用一个 trigger @State 在用户点"清零"后强制重渲染。
    @State private var refreshTick = 0

    var body: some View {
        let today  = AISettings.usageToday
        let week   = AISettings.usageThisWeek
        let month  = AISettings.usageThisMonth
        let provider = AISettings.activeProvider

        Section {
            // Phase 110:三列数字表改用 Grid —— 旧版给每列钉死 70pt,中英文标签宽度不同、
            // 金额位数一多($12.3456 之类)就截断/挤歪。Grid 列宽按内容自适应,
            // 三列统一右对齐,label 列吃掉剩余宽度,任何语言 / 数字长度下都对齐。
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 7) {
                GridRow {
                    Color.clear
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                    headerCell("settings.ai.usage.col.today")
                    headerCell("settings.ai.usage.col.week")
                    headerCell("settings.ai.usage.col.month")
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
                // Claude 才显示估算美元成本
                if provider == .claude {
                    let m = AISettings.claudeModel
                    usageRow(labelKey: "settings.ai.usage.estimatedCost", iconName: "dollarsign.circle",
                             a: String(format: "$%.4f", today.estimatedUSDForClaude(model: m)),
                             b: String(format: "$%.4f", week.estimatedUSDForClaude(model: m)),
                             c: String(format: "$%.4f", month.estimatedUSDForClaude(model: m)))
                }
                // Phase 107:火山引擎 — 用户在 Settings 自填价格 > 0 时显示 ¥ 估算。
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
            HStack {
                Spacer()
                Button("settings.ai.usage.reset") {
                    AISettings.resetUsage()
                    refreshTick &+= 1
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.red)
            }
        } header: {
            Text("settings.ai.usage.header")
        } footer: {
            VStack(alignment: .leading, spacing: 3) {
                Text("settings.ai.usage.footer.metric")
                Text(provider == .claude
                     ? "settings.ai.usage.footer.claude"
                     : "settings.ai.usage.footer.other")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .id(refreshTick)
    }

    /// 表头单元格:列标题,整列右对齐(gridColumnAlignment 对整列生效)。
    @ViewBuilder
    private func headerCell(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    /// 单行 4 列:icon + 标签 + 今天 / 本周 / 本月(Grid 行,数字列自适应宽度)。
    @ViewBuilder
    private func usageRow(labelKey: LocalizedStringKey, iconName: String,
                          a: String, b: String, c: String) -> some View {
        GridRow {
            Label(labelKey, systemImage: iconName)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: a).monospacedDigit().foregroundStyle(.secondary)
            Text(verbatim: b).monospacedDigit().foregroundStyle(.secondary)
            Text(verbatim: c).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    /// 1234 → "1,234";12345 → "12.3K";9876543 → "9.88M"。简短显示,避免占满一行。
    private func formatTokens(_ n: Int) -> String {
        if n < 1_000 { return "\(n)" }
        if n < 1_000_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return String(format: "%.2fM", Double(n) / 1_000_000)
    }
}
