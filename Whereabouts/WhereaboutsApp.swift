import SwiftUI
import SwiftData
import UserNotifications

// Phase 111:AppearanceMode / AppLanguage 挪到 Shared/AppPrefs.swift ——
// iOS target 的设置页复用同一对枚举。本文件只进 macOS target。

@main
struct WhereaboutsApp: App {
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .system
    @AppStorage("appearance") private var appearance: AppearanceMode = .system
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon: Bool = true
    /// Phase 89:启停全局快捷键 ⌥⌘N。默认开。
    @AppStorage("globalHotKeyEnabled") private var globalHotKeyEnabled: Bool = true

    /// 共享 container —— 所有 Scene 和通知调度器都用**同一个实例**。
    ///
    /// Phase 114(数据事故修复):不再用 SwiftData 的默认存储路径
    /// `~/Library/Application Support/default.store` —— 那是所有非沙箱 SwiftData
    /// 程序共用的一个文件,实测连苹果自家的 `/usr/libexec/icloudmailagent` 都会
    /// 往里写它自己的 schema,直接把我们的库覆盖掉(2026-07-07 真实发生,数据
    /// 靠 Time Machine 快照捞回)。改用专属路径:
    ///   ~/Library/Application Support/Whereabouts/whereabouts.store
    /// 恢复脚本 Tools/recover_store.sh 也把捞回的数据装到这里。
    private let sharedContainer: ModelContainer = {
        let dir = URL.applicationSupportDirectory.appending(path: "Whereabouts", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Phase 116:经 AppContainer 走 CloudKit(可用时)+ 本地回退。
        return AppContainer.make(storeURL: dir.appending(path: "whereabouts.store"))
    }()

    init() {
        // 启动时把 container 注入通知调度器,让它能查置顶物品。
        NotificationScheduler.shared.container = sharedContainer
        // Phase 106:把通知 delegate 设为 NotificationTapForwarder —— 用户点 banner 时,
        // 取出 userInfo["itemName"] 广播 .openItemByName,ContentView 接住后聚焦该物品。
        UNUserNotificationCenter.current().delegate = NotificationTapForwarder.shared
        // 若用户上次开了通知,启动时重新调度(防 reboot 后丢失)。
        NotificationScheduler.shared.rescheduleIfEnabled()
        // Phase 89:启动注册全局快捷键(⌥⌘N)。用户在偏好设置可以关掉。
        #if os(macOS)
        if globalHotKeyEnabled {
            GlobalHotKey.shared.registerDefault()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            // SwiftUI Text / LocalizedStringKey 立刻跟随 environment locale。
            // 但 String(localized:) 是进程级 Bundle lookup,需要 AppleLanguages UserDefaults
            // (由 SettingsView 在切换时写入)+ 应用重启才能完全生效 —— 见 SettingsView 的提示。
            ContentView()
                .environment(\.locale, appLanguage.explicitLocale ?? Locale.autoupdatingCurrent)
                .preferredColorScheme(appearance.colorScheme)
                // Phase 74:给主窗口一个最小尺寸,防止过小撑爆 inputBar / status bar
                // 之间夹的列表;同时强制窗口不再"按内容自适应高度",改由用户拖拽决定。
                .frame(minWidth: 720, minHeight: 540)
                #if os(macOS)
                // Phase 89:全局快捷键 ⌥⌘N 通知到达 → 用 openWindow 弹 quickEntry
                .modifier(QuickEntryHotKeyObserver())
                #endif
        }
        .modelContainer(sharedContainer)  // Phase 114:全部 Scene 共用专属路径的同一实例
        // Phase 74:给主窗口一个稳定的默认尺寸 —— 之前没设,SwiftUI 会按"内容自然高度"
        // 自动调整窗口,展开 facet 行就会把状态栏挤出可视区(用户原报:"会被拉下去")。
        // 加 defaultSize 后窗口稳定在初始大小,facet 展开时 List 自动收缩腾位置。
        .defaultSize(width: 1024, height: 720)
        // contentMinSize:用户可以放大窗口,但不能小于 minWidth/minHeight。
        // 避免拖小到 inputBar+facet+statusBar 总和都装不下的程度。
        #if os(macOS)
        .windowResizability(.contentMinSize)
        #endif
        #if os(macOS)
        .commands {
            // 覆盖默认的 "About <AppName>" 菜单项,用自定义 about panel 注入作者 + 邮箱 credits。
            CommandGroup(replacing: .appInfo) {
                Button {
                    showAboutPanel()
                } label: {
                    Text("about.menu.label")
                }
            }
            // Help 菜单:替换默认空 Help 项,开自定义 Help 窗口。
            // 用单独的 small View 包,从而能在 commands 上下文里拿到 @Environment(\.openWindow)。
            CommandGroup(replacing: .help) {
                OpenHelpWindowMenuItem()
            }
        }
        #endif

        #if os(macOS)
        // Help 窗口 —— 用 Window 单独开,Markdown 渲染 docs/help.*.md。
        Window("help.window.title", id: "help") {
            HelpView()
                .environment(\.locale, appLanguage.explicitLocale ?? Locale.autoupdatingCurrent)
                .preferredColorScheme(appearance.colorScheme)
        }
        .defaultSize(width: 720, height: 600)

        // Phase 89:全局快捷键 ⌥⌘N 召唤的小输入窗口。固定尺寸 + 跟主窗口分开 scene。
        Window("quickEntry.window.title", id: "quickEntry") {
            QuickEntryView()
                .environment(\.locale, appLanguage.explicitLocale ?? Locale.autoupdatingCurrent)
                .preferredColorScheme(appearance.colorScheme)
        }
        .defaultSize(width: 480, height: 220)
        .windowResizability(.contentSize)
        .modelContainer(sharedContainer)  // Phase 114:全部 Scene 共用专属路径的同一实例

        Settings {
            SettingsView()
                .environment(\.locale, appLanguage.explicitLocale ?? Locale.autoupdatingCurrent)
                .preferredColorScheme(appearance.colorScheme)
        }
        // Phase 25:Settings 是独立 Scene,默认不会跟 WindowGroup 共享 modelContainer
        // —— 没有这行,Settings → 标签 里 @Query 永远是空数组。
        .modelContainer(sharedContainer)  // Phase 114:全部 Scene 共用专属路径的同一实例

        // 菜单栏快速录入。.window 风格允许 TextField(.menu 不允许)。
        // isInserted binding 让用户可以在偏好设置里随时关掉。
        // 共享 ModelContainer:.modelContainer 在 Scene 上幂等,相同 schema → 同一个 store。
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environment(\.locale, appLanguage.explicitLocale ?? Locale.autoupdatingCurrent)
                .preferredColorScheme(appearance.colorScheme)
        } label: {
            Image(systemName: "shippingbox")
        }
        .menuBarExtraStyle(.window)
        .modelContainer(sharedContainer)  // Phase 114:全部 Scene 共用专属路径的同一实例
        #endif
    }
}

#if os(macOS)
/// Help menu item —— 单独包成 view 才能拿到 `@Environment(\.openWindow)`。
struct OpenHelpWindowMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("help.menu.label") {
            openWindow(id: "help")
        }
        .keyboardShortcut("?", modifiers: [.command])
    }
}

/// Phase 89:挂在主 ContentView 上 —— 收到 .openQuickEntry 通知就 openWindow。
/// 通过 view modifier 注入到 scene 里,这样能拿到 SwiftUI 的 @Environment(\.openWindow)。
struct QuickEntryHotKeyObserver: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openQuickEntry)) { _ in
                openWindow(id: "quickEntry")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

/// Phase 89 + Phase 100:全局快捷键弹出的小窗口。**双模式**:
///   - **记一条**(默认):跟菜单栏 popover 一样 — parse 一段文本 → 建 item
///   - **搜索**:输入关键词 → 打开主窗口 + 把关键词填进 ContentView 的搜索框
///
/// 通过 segmented picker 切换。`@AppStorage("quickEntry.mode")` 记住上次用的模式。
struct QuickEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    enum Mode: String, CaseIterable, Identifiable {
        case record, search
        var id: String { rawValue }
    }

    @AppStorage("quickEntry.mode") private var modeRaw: String = Mode.record.rawValue
    @State private var draft: String = ""
    @State private var ack: String?
    @FocusState private var focused: Bool

    private var mode: Mode {
        get { Mode(rawValue: modeRaw) ?? .record }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: mode == .record ? "square.and.pencil" : "magnifyingglass")
                    .foregroundStyle(Color.accentColor)
                Text(mode == .record ? "quickEntry.title" : "quickEntry.title.search")
                    .font(.headline)
                Spacer()
                Text(verbatim: HotKeyFormatter.display(
                    keyCode: GlobalHotKey.currentKeyCode,
                    modifiers: GlobalHotKey.currentModifiers
                ))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            // Phase 100:双模式 segmented picker
            Picker(selection: Binding(
                get: { mode },
                set: { newMode in
                    modeRaw = newMode.rawValue
                    focused = true
                }
            )) {
                Label("quickEntry.mode.record", systemImage: "square.and.pencil").tag(Mode.record)
                Label("quickEntry.mode.search", systemImage: "magnifyingglass").tag(Mode.search)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // 记一条:多行;搜索:单行
            if mode == .record {
                TextField("quickEntry.placeholder", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .lineLimit(3...6)
                    .onSubmit(submit)
            } else {
                TextField("quickEntry.placeholder.search", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(submit)
            }
            HStack {
                if let ack {
                    Label(ack, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
                Spacer()
                Button("action.cancel") {
                    dismissWindow(id: "quickEntry")
                }
                .keyboardShortcut(.cancelAction)
                Button(mode == .record ? "quickEntry.commit" : "quickEntry.search.commit",
                       action: submit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(submitDisabled)
            }
            Text(mode == .record ? "quickEntry.footer" : "quickEntry.footer.search")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { focused = true }
    }

    /// 提交按钮的 enable 条件随 mode 变。
    private var submitDisabled: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .record: return InputParser.parseMultiple(draft).isEmpty
        case .search: return trimmed.isEmpty
        }
    }

    private func submit() {
        switch mode {
        case .record: commit()
        case .search: runSearch()
        }
    }

    /// 跟 MenuBarView.commit 一样:parse + 建 item + 写 location log。
    /// 单条提交 → 关窗;多条 → 留窗供继续。
    private func commit() {
        let list = InputParser.parseMultiple(draft)
        guard !list.isEmpty else { return }
        let raw = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        for parsed in list {
            let loc = Location.bestMatchOrEnsure(path: parsed.locationPath, in: modelContext)
            let item = Item(name: parsed.name, location: loc)
            item.purchaseDate = parsed.purchaseDate
            item.purchaseDatePrecision = parsed.purchaseDatePrecision
            item.purchaseSource = parsed.purchaseSource
            item.model = parsed.model
            item.color = parsed.color
            item.version = parsed.version
            item.rawInput = raw
            modelContext.insert(item)
            let log = LocationLog(recordedAt: .now, location: loc, item: item)
            modelContext.insert(log)
        }
        try? modelContext.save()
        if list.count > 1 {
            withAnimation { ack = String(localized: "quickEntry.ack.batch \(list.count)") }
            draft = ""
            focused = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                await MainActor.run { withAnimation { ack = nil } }
            }
        } else {
            dismissWindow(id: "quickEntry")
        }
    }

    /// Phase 100:搜索模式。把关键词通过 NotificationCenter 广播给 ContentView,
    /// 后者收到后 set search text + 唤醒主窗口。
    private func runSearch() {
        let q = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        NotificationCenter.default.post(name: .quickEntrySearch, object: nil, userInfo: ["query": q])
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        dismissWindow(id: "quickEntry")
    }
}

extension Notification.Name {
    /// Phase 100:QuickEntry "搜索"模式触发,把 query 喂给 ContentView 的 search field。
    static let quickEntrySearch = Notification.Name("com.bamcope.whereabouts.quickEntrySearch")
}

/// Phase 100:偏好设置里的键位捕获 row。
///
/// **设计**:左边一个 label,右边一个按钮显示当前键位(如"⌥⌘N")。
/// 点按钮 → 进"capture 模式":按钮变蓝、文字变成"按一下新键位…",装一个 NSEvent.local monitor
/// 捕获下一次按键 + modifiers → 写到 UserDefaults + 重新注册 Carbon hotkey → 退出 capture。
///
/// 按 Esc 取消捕获。
struct HotKeyCaptureRow: View {
    @AppStorage("globalHotKey.keyCode") private var keyCode: Int = Int(GlobalHotKey.defaultKeyCode)
    @AppStorage("globalHotKey.modifiers") private var modifiers: Int = Int(GlobalHotKey.defaultModifiers)
    @State private var capturing = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text("settings.hotkey.keyLabel")
            Spacer()
            Button {
                if capturing {
                    stopCapture()
                } else {
                    startCapture()
                }
            } label: {
                Text(verbatim: capturing
                     ? String(localized: "settings.hotkey.capture.prompt")
                     : HotKeyFormatter.display(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers)))
                    .font(.body.monospaced())
                    .frame(minWidth: 100)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(capturing ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10),
                                in: .capsule)
            }
            .buttonStyle(.plain)
            Button("settings.hotkey.reset") {
                keyCode = Int(GlobalHotKey.defaultKeyCode)
                modifiers = Int(GlobalHotKey.defaultModifiers)
                GlobalHotKey.saveCustom(keyCode: GlobalHotKey.defaultKeyCode,
                                        modifiers: GlobalHotKey.defaultModifiers)
                GlobalHotKey.shared.registerDefault()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.secondary)
        }
        .onDisappear { stopCapture() }
    }

    private func startCapture() {
        capturing = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc → 取消捕获
            if event.keyCode == 53 { stopCapture(); return nil }
            // 必须带至少一个 modifier — 否则太容易跟普通文本输入冲突。
            let nsMods = event.modifierFlags.intersection([.command, .option, .shift, .control])
            guard !nsMods.isEmpty else { return nil }
            let carbonMods = HotKeyFormatter.carbonModifiers(from: nsMods)
            let kc = UInt32(event.keyCode)
            keyCode = Int(kc)
            modifiers = Int(carbonMods)
            GlobalHotKey.saveCustom(keyCode: kc, modifiers: carbonMods)
            GlobalHotKey.shared.registerDefault()
            stopCapture()
            return nil
        }
    }

    private func stopCapture() {
        capturing = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}

/// Help 窗口 —— 读 `docs/help.{locale}.md`,**当 plain text 显示**(不 parse Markdown)。
/// 之前用 AttributedString from Markdown 渲染时,SwiftUI Text 不变 H1/H2 字号、丢失 list 格式,
/// 整页压成一坨。Plain text + monospace + 自己用 emoji + 分隔线分章节,所见即所得最清晰。
struct HelpView: View {
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            if let raw = loadHelpText() {
                Text(verbatim: raw)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            } else {
                ContentUnavailableView(
                    "Help unavailable",
                    systemImage: "questionmark.circle"
                )
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    /// 按当前 locale 选 help.zh-Hans.md / help.en.md(在 bundle 的 Resources/docs/)。
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

/// 显示自定义 about 面板:在系统标准 about panel 上加 credits(作者 + 可点 mailto 链接)。
/// 用 NSApplication.orderFrontStandardAboutPanel,而不是写 Credits.html —— 这样能本地化、
/// 能用 NSAttributedString.Key.link 加可点超链接。
private func showAboutPanel() {
    let authorLine = String(localized: "about.credits.author")
    let emailLabel = String(localized: "about.credits.email")
    let email = "pluginexpert2@gmail.com"
    let builtWith = String(localized: "about.credits.builtWith")
    let body = "\(authorLine)\n\(emailLabel) \(email)\n\(builtWith)"

    let credits = NSMutableAttributedString(string: body)
    let fullRange = NSRange(location: 0, length: (body as NSString).length)
    credits.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
    credits.addAttribute(.font, value: NSFont.systemFont(ofSize: 11), range: fullRange)
    // 邮箱位置加 mailto 链接
    let emailRange = (body as NSString).range(of: email)
    if emailRange.location != NSNotFound {
        credits.addAttribute(.link, value: "mailto:\(email)", range: emailRange)
    }

    NSApplication.shared.orderFrontStandardAboutPanel(options: [
        .credits: credits
    ])
    NSApplication.shared.activate(ignoringOtherApps: true)
}

/// macOS 菜单栏 popover —— 一行话快速录入,不打扰当前窗口。
///
/// 跟主窗口 `ContentView.commit` 的区别:
/// - 跳过 update-intent 检测和 duplicate 检测(menubar 是 "fire and forget" 风格,不弹 alert)
/// - 提交完清空输入框、保留焦点,准备下一条
///
/// "打开主窗口"按钮通过 `openWindow(id: "main")` 召回 ContentView。
struct MenuBarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    /// 跟主窗口一样过滤掉 soft-deleted。
    @Query(filter: #Predicate<Item> { !$0.isDeleted },
           sort: \Item.updatedAt, order: .reverse)
    private var items: [Item]

    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 录入区
            HStack(spacing: 4) {
                Image(systemName: "square.and.pencil").font(.caption)
                Text("input.section.title").font(.caption.bold())
            }
            .foregroundStyle(Color.accentColor)

            HStack(spacing: 6) {
                TextField("input.textField.placeholder", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                    .onSubmit(commit)
                    .submitLabel(.done)

                Button(action: commit) {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(InputParser.parseMultiple(draft).isEmpty)
            }

            Divider()

            // 最近 5 条
            Text("menu.recent")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if items.isEmpty {
                Text("empty.list.title")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items.prefix(5)) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.name)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if let path = item.location?.path {
                                Text(path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("location.unspecified")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

            Divider()

            // 底部:打开主窗口 + 退出
            HStack {
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("menu.openMain", systemImage: "macwindow")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Spacer()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("menu.quit")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear {
            // 弹出时自动聚焦输入框,快速键入
            inputFocused = true
        }
    }

    private func commit() {
        let list = InputParser.parseMultiple(draft)
        guard !list.isEmpty else { return }
        for parsed in list {
            let loc = Location.ensure(path: parsed.locationPath, in: modelContext)
            let item = Item(name: parsed.name, location: loc)
            item.purchaseDate = parsed.purchaseDate
            item.purchaseDatePrecision = parsed.purchaseDatePrecision
            item.purchaseSource = parsed.purchaseSource
            item.model = parsed.model
            item.color = parsed.color
            modelContext.insert(item)
            // 写首条历史 log
            let log = LocationLog(recordedAt: .now, location: loc, item: item)
            modelContext.insert(log)
        }
        draft = ""
        inputFocused = true
    }
}

/// macOS 偏好设置(⌘, 打开)。Phase 87 起五个 tab:通用 + 标签 + 位置 + AI + 数据。
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("settings.tab.general", systemImage: "gear") }
            TagsSettingsTab()
                .tabItem { Label("settings.tags.header", systemImage: "tag") }
            LocationsSettingsTab()
                .tabItem { Label("settings.locations.header.tab", systemImage: "mappin.and.ellipse") }
            AISettingsTab()
                .tabItem { Label("settings.ai.header", systemImage: "sparkles") }
            DataSettingsTab()
                .tabItem { Label("settings.tab.data", systemImage: "externaldrive") }
        }
        .frame(width: 560, height: 540)
    }
}

/// Phase 20:标签管理 tab —— 列出所有 tag,行内可改色 / 重命名 / 删除。
/// 删除走 SwiftData 的 .nullify rule,自动把所有挂载断掉,但 item 本身不删。
private struct TagsSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.createdAt) private var allTags: [Tag]

    var body: some View {
        Form {
            Section {
                if allTags.isEmpty {
                    Text("settings.tags.empty")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(allTags) { tag in
                        TagSettingsRow(tag: tag)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// 单行 tag:色点 menu + 名字 TextField + 物品数 + 删除按钮。
/// @Bindable 让 colorHex / name 编辑实时持久化。
private struct TagSettingsRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var tag: Tag

    var body: some View {
        // Phase 31:横向色板 + 名字一行 + 元信息一行 —— 两行布局让色板有空间展开。
        VStack(alignment: .leading, spacing: 6) {
            TagColorPicker(selected: $tag.colorHex, diameter: 14, spacing: 4)
            HStack(spacing: 8) {
                TextField("settings.tags.name.label", text: $tag.name)
                    .textFieldStyle(.roundedBorder)

                Spacer(minLength: 4)

                // 该 tag 挂在几件 item 上(简单计数,无昂贵查询)
                Text("settings.tags.row.itemCount \(tag.items.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    modelContext.delete(tag)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("settings.tags.delete.tooltip")
            }
        }
        .padding(.vertical, 2)
    }
}

/// 通用 tab:语言 / 外观 / 菜单栏 / 录入行为 / 通知。
private struct GeneralSettingsTab: View {
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .system
    @AppStorage("appearance") private var appearance: AppearanceMode = .system
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon: Bool = true
    @AppStorage("dupDetectionEnabled") private var dupDetectionEnabled: Bool = true
    @AppStorage("updateIntentDetectionEnabled") private var updateIntentDetectionEnabled: Bool = true
    @AppStorage("autoTagSuggestEnabled") private var autoTagSuggestEnabled: Bool = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
    /// Phase 89:全局快捷键 ⌥⌘N。改 toggle 时立即注册/注销。
    @AppStorage("globalHotKeyEnabled") private var globalHotKeyEnabled: Bool = true
    // Phase 99:通知自定义
    @AppStorage("notificationFrequency") private var notificationFrequency: String = "daily"
    @AppStorage("notificationHour") private var notificationHour: Int = 12
    @AppStorage("notificationMinute") private var notificationMinute: Int = 0
    @AppStorage("notificationBodyTemplate") private var notificationBodyTemplate: String = ""
    /// Phase 105:weekly 频率下提醒哪一天。Apple DateComponents 约定 1=周日,2=周一,...,7=周六。
    @AppStorage("notificationWeekday") private var notificationWeekday: Int = 2

    /// 切换语言后变 true,显示"重启 app 完全生效"。不持久化。
    @State private var languageChanged = false
    /// 用户开了通知开关但系统拒绝权限时的提示。
    @State private var notificationsPermissionDenied = false
    /// Phase 116:iCloud 同步偏好(默认开;key 与 AppContainer.syncPrefKey 一致)。
    @AppStorage("icloudSyncEnabled") private var icloudSyncEnabled: Bool = true
    /// 本次会话改过开关 → 显示"重启生效"提示。
    @State private var icloudPrefChanged = false

    var body: some View {
        Form {
            Section {
                Picker(selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayKey).tag(lang)
                    }
                } label: {
                    Text("settings.language.label")
                }
                .pickerStyle(.menu)
                .onChange(of: appLanguage) { _, newValue in
                    persistAppleLanguages(for: newValue)
                    languageChanged = true
                }

                if languageChanged {
                    Label("settings.language.restartHint", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("settings.language.header")
            }

            Section {
                Picker(selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayKey).tag(mode)
                    }
                } label: {
                    Text("settings.appearance.label")
                }
                .pickerStyle(.menu)
            } header: {
                Text("settings.appearance.header")
            }

            // Phase 116:iCloud 同步(CloudKit 私有库,双端同一开关语义)。
            Section {
                Toggle(isOn: $icloudSyncEnabled) {
                    HStack(spacing: 6) {
                        Text("settings.icloud.toggle")
                        Text(AppContainer.cloudKitActive
                             ? "settings.icloud.status.on"
                             : "settings.icloud.status.local")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
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
                Group {
                    if !icloudSyncEnabled {
                        Text("settings.icloud.footer.off")
                    } else if AppContainer.cloudKitActive {
                        Text("settings.icloud.footer.active")
                    } else {
                        Text("settings.icloud.footer.inactive")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Section {
                Toggle("settings.menubar.toggle", isOn: $showMenuBarIcon)
                // Phase 89:全局快捷键 toggle。改 → 立即注册/注销 Carbon hotkey。
                Toggle("settings.hotkey.toggle", isOn: $globalHotKeyEnabled)
                    .onChange(of: globalHotKeyEnabled) { _, new in
                        #if os(macOS)
                        if new {
                            GlobalHotKey.shared.registerDefault()
                        } else {
                            GlobalHotKey.shared.unregister()
                        }
                        #endif
                    }
                // Phase 100:键位捕获按钮 —— 仅在 enabled 时显示。
                #if os(macOS)
                if globalHotKeyEnabled {
                    HotKeyCaptureRow()
                }
                #endif
            } header: {
                Text("settings.menubar.header")
            } footer: {
                Text("settings.hotkey.footer")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Section {
                Toggle("settings.input.dupDetection", isOn: $dupDetectionEnabled)
                Toggle("settings.input.updateIntent", isOn: $updateIntentDetectionEnabled)
                Toggle("settings.toggle.autoTag", isOn: $autoTagSuggestEnabled)
            } header: {
                Text("settings.input.header")
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.input.footer")
                    Text("settings.toggle.autoTag.hint")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Section {
                Toggle("settings.notifications.toggle", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, new in
                        Task {
                            if new {
                                // 用户开启 → 申请权限。被拒就回滚 toggle + 提示。
                                let ok = await NotificationScheduler.shared.requestAuthorization()
                                if !ok {
                                    notificationsEnabled = false
                                    notificationsPermissionDenied = true
                                } else {
                                    NotificationScheduler.shared.rescheduleIfEnabled()
                                }
                            } else {
                                // 用户关掉 → 取消所有已排的通知。
                                await NotificationScheduler.shared.cancelAllCheckups()
                            }
                        }
                    }

                // Phase 99:三组自定义控件,仅在 enabled 时显示(关掉就不晃)。
                if notificationsEnabled {
                    Picker(selection: $notificationFrequency) {
                        Text("settings.notifications.frequency.daily").tag("daily")
                        Text("settings.notifications.frequency.weekly").tag("weekly")
                        Text("settings.notifications.frequency.monthly").tag("monthly")
                    } label: {
                        Text("settings.notifications.frequency.label")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: notificationFrequency) { _, _ in
                        NotificationScheduler.shared.rescheduleIfEnabled()
                    }

                    // Phase 105:weekly 频率下露 weekday picker。
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
                        .pickerStyle(.menu)
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
                        .datePickerStyle(.compact)

                    // Phase 110:去掉手拼的 80pt 标签列,改原生带 label 的 TextField ——
                    // grouped Form 自动排版,英文长标签不再把输入框挤歪。
                    TextField(
                        "settings.notifications.body.label",
                        text: $notificationBodyTemplate,
                        prompt: Text("settings.notifications.body.placeholder"),
                        axis: .vertical
                    )
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
                VStack(alignment: .leading, spacing: 3) {
                    Text("settings.notifications.footer")
                    if notificationsEnabled {
                        Text("settings.notifications.customize.footer")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }

    /// 写入进程级 preferred languages —— 让 `String(localized:)` 等
    /// 走 Bundle.main 默认 lookup 的代码也跟随这个选择(下次启动生效)。
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
}

/// 数据 tab:批量导入 / 批量导出 / 清空所有数据。
private struct DataSettingsTab: View {
    @Environment(\.modelContext) private var modelContext

    /// 用 @Query 取当前所有未删除物品,导出时用。
    @Query(filter: #Predicate<Item> { !$0.isDeleted },
           sort: \Item.updatedAt, order: .reverse)
    private var items: [Item]

    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportDocument: WhereaboutsExportDocument?
    @State private var showingClearConfirm = false
    /// Phase 90:导入时是否跳过已存在的物品(按 name + path 比对)。默认 ON。
    @AppStorage("importDedupEnabled") private var importDedupEnabled: Bool = true
    /// Phase 90:导入结果摘要,弹完 importer 短暂显示。
    @State private var importAck: String?
    // Phase 98:导入 / 导出 前的警示 dialog
    @State private var showingExportConfirm = false
    @State private var showingImportConfirm = false
    // Phase 117:iCloud 云盘备份状态行
    @State private var backupBusy = false
    @State private var backupResult: Bool?

    var body: some View {
        Form {
            Section {
                Button {
                    // Phase 98:导出前先弹警示,确认后才弹 fileExporter
                    showingExportConfirm = true
                } label: {
                    Label("settings.data.export", systemImage: "square.and.arrow.up")
                }
                .disabled(items.isEmpty)

                Button {
                    // Phase 98:导入前先弹警示(尤其在 dedup 关闭时强调风险)
                    showingImportConfirm = true
                } label: {
                    Label("settings.data.import", systemImage: "square.and.arrow.down")
                }
                Toggle("settings.data.import.dedup", isOn: $importDedupEnabled)
                if let ack = importAck {
                    Text(ack)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            } header: {
                Text("settings.data.header")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings.data.export.footer")
                    Text("settings.data.import.footer")
                    Text("settings.data.import.dedup.hint")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            // Phase 117:iCloud 云盘备份(退出时自动;这里手动 + 显示上次时间)。
            Section {
                HStack {
                    Label("settings.backup.row", systemImage: "icloud.and.arrow.up")
                    Spacer()
                    if let d = CloudBackup.lastBackupDate {
                        Text("settings.backup.last \(d.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("settings.backup.never")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        backupBusy = true
                        backupResult = nil
                        let ctx = modelContext
                        Task {
                            let ok = await CloudBackup.backUp(context: ctx)
                            await MainActor.run { backupBusy = false; backupResult = ok }
                        }
                    } label: {
                        if backupBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("settings.backup.now")
                        }
                    }
                    .disabled(backupBusy || items.isEmpty)
                }
                if let ok = backupResult {
                    Label(ok ? "settings.backup.done" : "settings.backup.failed",
                          systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(ok ? .green : .orange)
                }
            } footer: {
                Text("settings.backup.footer")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Section {
                Button(role: .destructive) {
                    showingClearConfirm = true
                } label: {
                    Label("settings.data.clear", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("settings.data.clear.warning")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        // Phase 98:导出前确认 dialog —— 让用户明确知道导出的 JSON 包含哪些字段。
        .confirmationDialog(
            "settings.data.export.confirm.title",
            isPresented: $showingExportConfirm
        ) {
            Button("settings.data.export.confirm.button") {
                exportDocument = WhereaboutsExportDocument(items: items)
                showingExporter = true
            }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("settings.data.export.confirm.message \(items.count)")
        }
        // Phase 98:导入前确认 dialog —— 在 dedup 关闭时**强调风险**。
        .confirmationDialog(
            "settings.data.import.confirm.title",
            isPresented: $showingImportConfirm
        ) {
            Button("settings.data.import.confirm.button") {
                showingImporter = true
            }
            Button("action.cancel", role: .cancel) {}
        } message: {
            // dedup 开 → 给出"会跳过同名同位置"的安心提示;
            // dedup 关 → 强烈警示"重复项目难以批量删除"。
            Text(importDedupEnabled
                 ? "settings.data.import.confirm.message.dedup"
                 : "settings.data.import.confirm.message.noDedup")
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
        .confirmationDialog(
            "settings.data.clear.confirm.title",
            isPresented: $showingClearConfirm
        ) {
            Button("settings.data.clear.confirm.button", role: .destructive) {
                clearAll()
            }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("settings.data.clear.confirm.message")
        }
    }

    /// Phase 90 → Phase 111:从 JSON 文件导入。解码 / 去重 / 建树 / 挂标签在
    /// `WhereaboutsImporter.importJSON`(Shared,iOS 设置页共用同一实现),
    /// 这里只负责沙箱安全读文件(startAccessingSecurityScopedResource)+ 结果 toast。
    private func importJSON(from url: URL) {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        guard let result = WhereaboutsImporter.importJSON(data, into: modelContext,
                                                          dedup: importDedupEnabled) else {
            withAnimation { importAck = String(localized: "settings.data.import.ack.failed") }
            return
        }
        withAnimation {
            importAck = String(localized: "settings.data.import.ack \(result.imported) \(result.skipped)")
        }
        Task {
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run {
                withAnimation { importAck = nil }
            }
        }
    }

    /// SwiftData 17+ 提供 `delete(model:)` 批量清空 entity。
    /// 顺序:先 Item / LocationLog(有 cascade / inverse 引用) → 再 Location / Tag。
    private func clearAll() {
        try? modelContext.delete(model: LocationLog.self)
        try? modelContext.delete(model: Item.self)
        try? modelContext.delete(model: Location.self)
        try? modelContext.delete(model: Tag.self)
        try? modelContext.save()
    }
}
#endif
