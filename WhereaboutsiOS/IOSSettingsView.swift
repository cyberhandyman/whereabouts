import SwiftUI
import SwiftData
import UserNotifications

// Phase 111:iOS 设置页 —— 通用 / 录入 / 通知 / AI / 数据 / 关于。
// 偏好 key 与 macOS 完全同名(@AppStorage 同一组 UserDefaults),
// 语义一致;界面按 iOS Settings app 风格(彩色图标 + inset grouped)。

struct IOSSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Item> { !$0.isDeleted },
           sort: \Item.updatedAt, order: .reverse)
    private var items: [Item]

    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .system
    @AppStorage("appearance") private var appearance: AppearanceMode = .system
    @AppStorage("dupDetectionEnabled") private var dupDetectionEnabled: Bool = true
    @AppStorage("updateIntentDetectionEnabled") private var updateIntentDetectionEnabled: Bool = true
    @AppStorage("autoTagSuggestEnabled") private var autoTagSuggestEnabled: Bool = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
    @AppStorage("notificationFrequency") private var notificationFrequency: String = "daily"
    @AppStorage("notificationHour") private var notificationHour: Int = 12
    @AppStorage("notificationMinute") private var notificationMinute: Int = 0
    @AppStorage("notificationBodyTemplate") private var notificationBodyTemplate: String = ""
    @AppStorage("notificationWeekday") private var notificationWeekday: Int = 2
    @AppStorage("importDedupEnabled") private var importDedupEnabled: Bool = true

    @State private var languageChanged = false
    @State private var notificationsPermissionDenied = false
    /// Phase 115:置 false 即重放首启引导(IOSRootView 的 fullScreenCover 监听它)。
    @AppStorage("onboardingShown") private var onboardingShown: Bool = false
    /// Phase 116:iCloud 同步偏好(默认开;key 与 AppContainer.syncPrefKey 一致)。
    @AppStorage("icloudSyncEnabled") private var icloudSyncEnabled: Bool = true
    /// 本次会话改过开关 → 显示"重启生效"提示。
    @State private var icloudPrefChanged = false

    // 数据导入 / 导出
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportDocument: WhereaboutsExportDocument?
    @State private var showingExportConfirm = false
    @State private var showingImportConfirm = false
    @State private var showingClearConfirm = false
    @State private var importAck: String?

    var body: some View {
        NavigationStack {
            Form {
                aiSection
                generalSection
                inputSection
                notificationSection
                icloudSection
                dataSection
                aboutSection
            }
            // 用户指定:设置页大标题用品牌梗「J人养成器 - 何处」(英文版意译)。
            .navigationTitle("ios.settings.title")
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: WhereaboutsExportDocument.defaultFilename()
        ) { _ in
            exportDocument = nil
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            importJSON(from: url)
        }
        .confirmationDialog("settings.data.export.confirm.title",
                            isPresented: $showingExportConfirm) {
            Button("settings.data.export.confirm.button") {
                exportDocument = WhereaboutsExportDocument(items: items)
                showingExporter = true
            }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("settings.data.export.confirm.message \(items.count)")
        }
        .confirmationDialog("settings.data.import.confirm.title",
                            isPresented: $showingImportConfirm) {
            Button("settings.data.import.confirm.button") {
                showingImporter = true
            }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text(importDedupEnabled
                 ? "settings.data.import.confirm.message.dedup"
                 : "settings.data.import.confirm.message.noDedup")
        }
        .confirmationDialog("settings.data.clear.confirm.title",
                            isPresented: $showingClearConfirm) {
            Button("settings.data.clear.confirm.button", role: .destructive) { clearAll() }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("settings.data.clear.confirm.message")
        }
    }

    // MARK: - AI(放最上,配置价值最高)

    private var aiSection: some View {
        Section {
            NavigationLink {
                IOSAISettingsView()
            } label: {
                settingsRow(icon: "sparkles", tint: IOSTheme.actionPurple,
                            titleKey: "settings.ai.header") {
                    if AISettings.hasActiveKey {
                        Text(verbatim: AISettings.activeProvider.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Link(destination: AppLinks.aiSetupGuide) {
                settingsRow(icon: "book.fill", tint: IOSTheme.accent,
                            titleKey: "settings.ai.guide.link") {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - 通用

    private var generalSection: some View {
        Section {
            Picker(selection: $appLanguage) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayKey).tag(lang)
                }
            } label: {
                settingsRow(icon: "globe", tint: .blue, titleKey: "settings.language.label")
            }
            .onChange(of: appLanguage) { _, newValue in
                persistAppleLanguages(for: newValue)
                languageChanged = true
            }
            if languageChanged {
                Label("settings.language.restartHint", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker(selection: $appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.displayKey).tag(mode)
                }
            } label: {
                settingsRow(icon: "circle.lefthalf.filled", tint: .indigo,
                            titleKey: "settings.appearance.label")
            }
        } header: {
            Text("settings.tab.general")
        }
    }

    // MARK: - 录入行为

    private var inputSection: some View {
        Section {
            Toggle(isOn: $dupDetectionEnabled) {
                settingsRow(icon: "doc.on.doc", tint: .teal, titleKey: "settings.input.dupDetection")
            }
            Toggle(isOn: $updateIntentDetectionEnabled) {
                settingsRow(icon: "arrow.triangle.2.circlepath", tint: .cyan,
                            titleKey: "settings.input.updateIntent")
            }
            Toggle(isOn: $autoTagSuggestEnabled) {
                settingsRow(icon: "tag", tint: .green, titleKey: "settings.toggle.autoTag")
            }
        } header: {
            Text("settings.input.header")
        } footer: {
            Text("settings.input.footer")
        }
    }

    // MARK: - 通知

    private var notificationSection: some View {
        Section {
            Toggle(isOn: $notificationsEnabled) {
                settingsRow(icon: "bell.badge.fill", tint: .red,
                            titleKey: "settings.notifications.toggle")
            }
            .onChange(of: notificationsEnabled) { _, new in
                Task {
                    if new {
                        let ok = await NotificationScheduler.shared.requestAuthorization()
                        if !ok {
                            notificationsEnabled = false
                            notificationsPermissionDenied = true
                        } else {
                            NotificationScheduler.shared.rescheduleIfEnabled()
                        }
                    } else {
                        await NotificationScheduler.shared.cancelAllCheckups()
                    }
                }
            }

            if notificationsEnabled {
                Picker(selection: $notificationFrequency) {
                    Text("settings.notifications.frequency.daily").tag("daily")
                    Text("settings.notifications.frequency.weekly").tag("weekly")
                    Text("settings.notifications.frequency.monthly").tag("monthly")
                } label: {
                    Text("settings.notifications.frequency.label")
                }
                .onChange(of: notificationFrequency) { _, _ in
                    NotificationScheduler.shared.rescheduleIfEnabled()
                }

                if notificationFrequency == "weekly" {
                    Picker(selection: $notificationWeekday) {
                        Text("settings.notifications.weekday.mon").tag(2)
                        Text("settings.notifications.weekday.tue").tag(3)
                        Text("settings.notifications.weekday.wed").tag(4)
                        Text("settings.notifications.weekday.thu").tag(5)
                        Text("settings.notifications.weekday.fri").tag(6)
                        Text("settings.notifications.weekday.sat").tag(7)
                        Text("settings.notifications.weekday.sun").tag(1)
                    } label: {
                        Text("settings.notifications.weekday.label")
                    }
                    .onChange(of: notificationWeekday) { _, _ in
                        NotificationScheduler.shared.rescheduleIfEnabled()
                    }
                }

                DatePicker("settings.notifications.time.label",
                           selection: Binding(
                            get: {
                                var c = DateComponents()
                                c.hour = notificationHour
                                c.minute = notificationMinute
                                return Calendar.current.date(from: c) ?? .now
                            },
                            set: { newDate in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                                notificationHour = c.hour ?? 12
                                notificationMinute = c.minute ?? 0
                                NotificationScheduler.shared.rescheduleIfEnabled()
                            }
                           ),
                           displayedComponents: .hourAndMinute)

                TextField("settings.notifications.body.label",
                          text: $notificationBodyTemplate,
                          prompt: Text("settings.notifications.body.placeholder"),
                          axis: .vertical)
                    .lineLimit(2...3)
                    .onChange(of: notificationBodyTemplate) { _, _ in
                        NotificationScheduler.shared.rescheduleIfEnabled()
                    }
            }

            if notificationsPermissionDenied {
                Label("settings.notifications.permission.denied",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("settings.notifications.header")
        } footer: {
            Text("settings.notifications.footer")
        }
    }

    // MARK: - iCloud 同步(Phase 116,正式上线)

    /// 真开关:偏好默认开;CloudKit 绑定在容器创建时决定 → 改动下次启动生效。
    /// 状态徽章显示本次启动实际是否挂上了 CloudKit(AppContainer.cloudKitActive)。
    private var icloudSection: some View {
        Section {
            Toggle(isOn: $icloudSyncEnabled) {
                settingsRow(icon: "icloud.fill", tint: .cyan,
                            titleKey: "settings.icloud.toggle") {
                    Text(AppContainer.cloudKitActive
                         ? "settings.icloud.status.on"
                         : "settings.icloud.status.local")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background((AppContainer.cloudKitActive ? Color.green : Color.secondary).opacity(0.14),
                                    in: .capsule)
                        .foregroundStyle(AppContainer.cloudKitActive ? .green : .secondary)
                }
            }
            .onChange(of: icloudSyncEnabled) { _, _ in icloudPrefChanged = true }
            if icloudPrefChanged {
                Label("settings.icloud.restartHint", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if !icloudSyncEnabled {
                Text("settings.icloud.footer.off")
            } else if AppContainer.cloudKitActive {
                Text("settings.icloud.footer.active")
            } else {
                Text("settings.icloud.footer.inactive")
            }
        }
    }

    // MARK: - 数据

    private var dataSection: some View {
        Section {
            Button {
                showingExportConfirm = true
            } label: {
                settingsRow(icon: "square.and.arrow.up", tint: .blue,
                            titleKey: "settings.data.export")
            }
            .disabled(items.isEmpty)

            Button {
                showingImportConfirm = true
            } label: {
                settingsRow(icon: "square.and.arrow.down", tint: .green,
                            titleKey: "settings.data.import")
            }
            Toggle(isOn: $importDedupEnabled) {
                Text("settings.data.import.dedup")
            }
            if let ack = importAck {
                Text(verbatim: ack)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Button(role: .destructive) {
                showingClearConfirm = true
            } label: {
                settingsRow(icon: "trash.fill", tint: .red, titleKey: "settings.data.clear")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("settings.tab.data")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("settings.data.export.footer")
                Text("settings.data.import.footer")
            }
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section {
            LabeledContent {
                Text(verbatim: appVersionString)
                    .foregroundStyle(.secondary)
            } label: {
                settingsRow(icon: "shippingbox.fill", tint: IOSTheme.accent,
                            titleKey: "ios.about.version")
            }
            NavigationLink {
                IOSHelpView()
            } label: {
                settingsRow(icon: "questionmark.circle.fill", tint: .orange,
                            titleKey: "ios.about.help")
            }
            // Phase 115:随时重看首启引导
            Button {
                onboardingShown = false
            } label: {
                settingsRow(icon: "play.rectangle.fill", tint: .indigo,
                            titleKey: "ios.about.replayOnboarding")
            }
            Link(destination: AppLinks.privacyPolicy) {
                settingsRow(icon: "hand.raised.fill", tint: .gray,
                            titleKey: "ios.about.privacy") {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Text("about.credits.author")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("about.credits.builtWith")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } header: {
            Text("ios.about.header")
        }
    }

    private var appVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    // MARK: - helpers

    /// 设置行:彩色圆角图标 + 标题(iOS Settings app 风格)+ 可选 trailing 内容。
    @ViewBuilder
    private func settingsRow(
        icon: String, tint: Color, titleKey: LocalizedStringKey
    ) -> some View {
        settingsRow(icon: icon, tint: tint, titleKey: titleKey) { EmptyView() }
    }

    @ViewBuilder
    private func settingsRow<Trailing: View>(
        icon: String, tint: Color, titleKey: LocalizedStringKey,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            GradientIconTile(systemName: icon, size: 28, cornerRadius: 7,
                             gradient: LinearGradient(colors: [tint, tint.opacity(0.65)],
                                                      startPoint: .topLeading,
                                                      endPoint: .bottomTrailing))
            Text(titleKey)
            Spacer(minLength: 0)
            trailing()
        }
    }

    private func persistAppleLanguages(for lang: AppLanguage) {
        switch lang {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .zhHans:
            UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        case .en:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        }
    }

    private func importJSON(from url: URL) {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        guard let result = WhereaboutsImporter.importJSON(data, into: modelContext,
                                                          dedup: importDedupEnabled) else {
            withAnimation { importAck = String(localized: "settings.data.import.ack.failed") }
            return
        }
        Haptics.success()
        withAnimation {
            importAck = String(localized: "settings.data.import.ack \(result.imported) \(result.skipped)")
        }
        Task {
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run { withAnimation { importAck = nil } }
        }
    }

    private func clearAll() {
        try? modelContext.delete(model: LocationLog.self)
        try? modelContext.delete(model: Item.self)
        try? modelContext.delete(model: Location.self)
        try? modelContext.delete(model: Tag.self)
        try? modelContext.save()
        Haptics.warning()
    }
}

// MARK: - 帮助(读 bundle 里的 help md,与 macOS HelpView 同一份文档)

struct IOSHelpView: View {
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            if let raw = loadHelpText() {
                Text(verbatim: raw)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                ContentUnavailableView("ios.about.help", systemImage: "questionmark.circle")
            }
        }
        .navigationTitle("ios.about.help")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func loadHelpText() -> String? {
        let langCode = locale.language.languageCode?.identifier ?? "en"
        let candidate = langCode.hasPrefix("zh") ? "help.zh-Hans" : "help.en"
        guard let url = Bundle.main.url(forResource: candidate, withExtension: "md", subdirectory: "docs")
                ?? Bundle.main.url(forResource: "help.en", withExtension: "md", subdirectory: "docs") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
