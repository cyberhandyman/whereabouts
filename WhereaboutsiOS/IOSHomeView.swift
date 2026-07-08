import SwiftUI
import SwiftData

// Phase 111:iOS 首页 —— 统计瓷砖 + 房间/借出 facet chips + 卡片式物品列表。
// 语义跟 macOS 主窗口对齐(同一套 FilterModel / SortMode / 软删除 / 置顶规则),
// 但交互按 iOS 习惯重排:searchable 下拉搜索、左右滑动作、长按菜单、push 详情。

struct IOSHomeView: View {
    /// Phase 118:右上角「记一条」按钮 → 切到录入 tab(IOSRootView 注入)。
    var onCompose: () -> Void = {}

    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Item> { !$0.isDeleted },
           sort: \Item.updatedAt, order: .reverse)
    private var rawItems: [Item]
    @Query private var allTags: [Tag]

    @AppStorage("sortMode") private var sortMode: SortMode = .updated
    @AppStorage("hasSeedTags") private var hasSeedTags: Bool = false
    @AppStorage("seededTagPresetVersion") private var seededTagPresetVersion: Int = 0

    @State private var filter = FilterModel()
    @State private var aiRunner = IOSAIRunner()

    /// 滑动"编辑"/ 菜单"编辑详情"打开的 sheet。
    @State private var editingItem: Item?
    /// 借给… sheet 的目标。
    @State private var lentSheetItem: Item?
    /// 待确认删除(长按菜单触发;滑动删除不确认,跟系统习惯一致)。
    @State private var pendingDelete: Item?
    /// 回收站 sheet。
    @State private var showingTrash = false

    #if DEBUG
    /// 截图 / 验收用:--open-first 启动后自动推入第一件物品的详情页。
    @State private var autoOpenFirst = false
    #endif

    /// Phase 97 同款:AI 连接状态(配了 key 启动时测一次)。
    @State private var aiStatus: AIConnectionStatus = .notConfigured

    /// Phase 115:演示数据状态机。"" = 从未灌过;"active" = 已灌、横幅在;
    /// "dismissed" = 用户清除过或选择留着,横幅永不再出现。
    @AppStorage("demoDataState") private var demoDataState: String = ""
    /// 清除演示数据后的 toast。
    @State private var demoClearedToast = false

    // Phase 118:iCloud 手动同步 + 多选编辑
    @AppStorage("icloudSyncEnabled") private var icloudSyncEnabled: Bool = true
    /// 同步结果 toast(短暂显示)。
    @State private var syncToast: String?
    /// 右上角按钮触发的同步进行中(下拉刷新自带转圈,不用这个)。
    @State private var syncing = false
    /// 多选模式 + 选中集合。
    @State private var editMode: EditMode = .inactive
    @State private var multiSelection: Set<PersistentIdentifier> = []
    /// 多选删除确认。
    @State private var showingBulkDelete = false
    /// Phase 119:批量编辑 sheet(标签 / 位置 / 渠道,复用 macOS 三件套)。
    @State private var batchEdit: BatchEditTarget?
    /// 批量操作回执 toast。
    @State private var batchAck: String?

    // MARK: - 派生

    /// 排序 + 置顶置前(逻辑与 macOS ContentView.items 一致)。
    private var items: [Item] {
        let sorted: [Item]
        switch sortMode {
        case .updated:  sorted = rawItems
        case .seen:     sorted = rawItems.sorted { $0.lastSeenAt > $1.lastSeenAt }
        case .created:  sorted = rawItems.sorted { $0.createdAt > $1.createdAt }
        case .name:
            sorted = rawItems.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .location:
            sorted = rawItems.sorted {
                ($0.location?.path ?? "\u{FFFF}").localizedStandardCompare($1.location?.path ?? "\u{FFFF}") == .orderedAscending
            }
        }
        let pinned = sorted.filter { $0.isPinned }
        let unpinned = sorted.filter { !$0.isPinned }
        return pinned + unpinned
    }

    private var filteredItems: [Item] {
        guard !filter.isEmpty else { return items }
        return items.filter { filter.matches($0) }
    }

    /// 房间 facet:顶层祖先名 → 物品数,取前 8。
    private var roomFacets: [(String, Int)] {
        var counts: [String: Int] = [:]
        for item in items {
            guard var cursor = item.location else { continue }
            while let p = cursor.parent { cursor = p }
            counts[cursor.name, default: 0] += 1
        }
        return Array(counts.sorted { ($0.value, $0.key) > ($1.value, $1.key) }
            .map { ($0.key, $0.value) }
            .prefix(8))
    }

    private var lentOutCount: Int { items.lazy.filter { $0.isLentOut }.count }
    private var pinnedCount: Int { items.lazy.filter { $0.isPinned }.count }

    private var roomCount: Int {
        var tops: Set<String> = []
        for item in items {
            var cursor: Location? = item.location
            while let p = cursor?.parent { cursor = p }
            if let n = cursor?.name { tops.insert(n) }
        }
        return tops.count
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    itemList
                }
            }
            .background(IOSTheme.pageBackground)
            // app.name 是 macOS 窗口标题用的长品牌串,手机导航栏放不下 → 用短名。
            .navigationTitle("ios.home.title")
            .environment(\.editMode, $editMode)
            #if DEBUG
            // 截图 / 验收用:--open-first 自动展示第一件物品详情。
            // 用 fullScreenCover 而非 navigationDestination —— 后者在启动初期
            // programmatic 置 true 有时机问题(SwiftUI 已知怪癖),截图场景全屏盖等效。
            .fullScreenCover(isPresented: $autoOpenFirst) {
                if let first = items.first {
                    NavigationStack { IOSItemDetailView(item: first) }
                }
            }
            #endif
            .toolbar {
                // Phase 118:多选(选择/完成)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.snappy) {
                            if editMode == .active {
                                editMode = .inactive
                                multiSelection.removeAll()
                            } else {
                                editMode = .active
                            }
                        }
                    } label: {
                        editMode == .active ? Text("action.done") : Text("ios.toolbar.select")
                    }
                    .disabled(items.isEmpty && editMode == .inactive)
                }
                // Phase 118/119:普通模式 = 记一条 + 同步;多选模式两者隐藏,
                // 只留 ⋯(强调色)装 macOS 同款批量菜单。
                if editMode != .active {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Haptics.tap()
                            onCompose()
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel(Text("ios.toolbar.compose"))
                    }
                    if icloudSyncEnabled {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                guard !syncing else { return }
                                syncing = true
                                let ctx = modelContext
                                Task {
                                    let r = await CloudBackup.sync(context: ctx)
                                    await MainActor.run {
                                        syncing = false
                                        flashSyncResult(r)
                                    }
                                }
                            } label: {
                                if syncing {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath.icloud")
                                }
                            }
                            .accessibilityLabel(Text("ios.toolbar.syncNow"))
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if editMode == .active {
                            batchMenu
                        } else {
                            Picker(selection: $sortMode) {
                                ForEach(SortMode.allCases) { mode in
                                    Label(mode.displayKey, systemImage: mode.systemImage).tag(mode)
                                }
                            } label: {
                                Text("sort.menu.label")
                            }
                            Divider()
                            Button {
                                showingTrash = true
                            } label: {
                                Label("trash.toolbar.label", systemImage: "archivebox")
                            }
                        }
                    } label: {
                        Image(systemName: editMode == .active ? "ellipsis.circle.fill" : "ellipsis.circle")
                            .foregroundStyle(editMode == .active ? IOSTheme.accent : Color.primary)
                    }
                }
            }
            .confirmationDialog("bulk.delete.confirm.title",
                                isPresented: $showingBulkDelete) {
                Button("bulk.delete.confirm.button \(multiSelection.count)", role: .destructive) {
                    for id in multiSelection {
                        if let item = items.first(where: { $0.persistentModelID == id }) {
                            item.markDeleted()
                        }
                    }
                    Haptics.warning()
                    exitEditMode()
                }
                Button("action.cancel", role: .cancel) {}
            } message: {
                Text("bulk.delete.confirm.message \(multiSelection.count)")
            }
        }
        .searchable(text: Binding(get: { filter.search }, set: { filter.search = $0 }),
                    prompt: Text("filter.search.placeholder"))
        .sheet(item: $editingItem) { ItemEditView(item: $0) }
        // Phase 119:批量编辑三件套(与 macOS 完全同款 sheet)
        .sheet(item: $batchEdit) { target in
            switch target {
            case .tags(let its):
                BatchTagsSheet(items: its) { count, tagCount in
                    Haptics.success()
                    flashBatchAck(String(localized: "batch.ack.tagsAdded \(count) \(tagCount)"))
                    exitEditMode()
                }
            case .location(let its):
                BatchLocationSheet(items: its) { count in
                    Haptics.success()
                    flashBatchAck(String(localized: "batch.ack.locationSet \(count)"))
                    exitEditMode()
                }
            case .source(let its):
                BatchSourceSheet(items: its) { count in
                    Haptics.success()
                    flashBatchAck(String(localized: "batch.ack.sourceSet \(count)"))
                    exitEditMode()
                }
            }
        }
        .sheet(item: $lentSheetItem) { item in
            IOSLentSheet(item: item)
                .presentationDetents([.height(300)])
        }
        .sheet(isPresented: $showingTrash) { IOSTrashView() }
        .confirmationDialog(
            "delete.alert.title",
            isPresented: .init(get: { pendingDelete != nil },
                               set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { item in
            Button("action.delete", role: .destructive) {
                item.markDeleted()
                Haptics.warning()
                pendingDelete = nil
            }
            Button("action.cancel", role: .cancel) { pendingDelete = nil }
        } message: { item in
            Text("delete.alert.message \(item.name)")
        }
        .task {
            seedTagsIfNeeded()
            seedExtendedPresetsIfNeeded()
            cleanDirtyLocations()
            checkAIConnection()
            // Phase 115:全新用户首启 → 灌一批演示物品让首页"有样子",
            // 顶部横幅提供一次性「一键清除」。用户自己录过东西就永不触发。
            if demoDataState.isEmpty && rawItems.isEmpty {
                seedDemoData()
                demoDataState = "active"
            }
            #if DEBUG
            if CommandLine.arguments.contains("--open-first") {
                try? await Task.sleep(for: .seconds(0.8))
                autoOpenFirst = true
            }
            if CommandLine.arguments.contains("--edit-mode") {
                try? await Task.sleep(for: .seconds(0.5))
                editMode = .active
            }
            #endif
        }
        // 点通知 banner → 清筛选 + 名字进搜索框,列表直达该物品。
        .onReceive(NotificationCenter.default.publisher(for: .openItemByName)) { note in
            guard let name = note.userInfo?["itemName"] as? String else { return }
            filter.clearAll()
            filter.search = name
        }
    }

    // MARK: - 列表

    private var itemList: some View {
        List(selection: $multiSelection) {
            // 统计瓷砖 + AI 状态 + facet chips:三段都是"透明行",卡片自己带皮肤。
            Section {
                // Phase 115:演示数据横幅(一次性,清除或"留着"后永不再出现)
                if demoDataState == "active" {
                    demoBanner
                        .listRowStyleClear()
                }
                if demoClearedToast {
                    Label("demo.cleared.toast", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                        .listRowStyleClear()
                        .transition(.opacity)
                }
                if let syncToast {
                    Label {
                        Text(verbatim: syncToast)
                    } icon: {
                        Image(systemName: "icloud.fill")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.cyan)
                    .listRowStyleClear()
                    .transition(.opacity)
                }
                if let batchAck {
                    Label {
                        Text(verbatim: batchAck)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
                    .listRowStyleClear()
                    .transition(.opacity)
                }
                statsStrip
                    .listRowStyleClear()
                if aiStatus != .notConfigured {
                    aiStatusPill
                        .listRowStyleClear()
                }
                // Phase 120:原房间 chips 行已并进可点击的统计瓷砖,不再单独渲染。
            }

            Section {
                if filteredItems.isEmpty {
                    ContentUnavailableView {
                        Label("empty.search.title", systemImage: "magnifyingglass")
                    } description: {
                        Button("empty.search.button.clearFilters") { filter.clearAll() }
                    }
                    .listRowStyleClear()
                } else {
                    ForEach(filteredItems) { item in
                        itemRow(item)
                            .tag(item.persistentModelID)  // 多选模式的选择标识
                            .listRowStyleClear(vertical: 5)
                    }
                }
            }

            // Phase 116:claude code 名言 —— 列表末尾一行小字,12 秒换一条(淡入淡出)。
            Section {
                quoteFooter
                    .listRowStyleClear(vertical: 10)
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        // Phase 118:下拉刷新 = 从 iCloud 手动同步(开关关着就只是转一下)
        .refreshable {
            guard icloudSyncEnabled else { return }
            let r = await CloudBackup.sync(context: modelContext)
            flashSyncResult(r)
        }
    }

    // MARK: - Phase 119:多选批量菜单(对齐 macOS toolbarBatchMenu)

    /// 把当前多选解成 Item 快照 —— 点菜单瞬间锁定,selection 后续变化不影响 sheet。
    private func selectedItemsSnapshot() -> [Item] {
        items.filter { multiSelection.contains($0.persistentModelID) }
    }

    /// 批量菜单:设标签 / 设位置 / 设渠道 / 标记见过 / 标记不知道在哪 / AI 理解 / 删除。
    @ViewBuilder
    private var batchMenu: some View {
        let count = multiSelection.count
        Section("bulk.delete.label \(count)") {
            Button {
                batchEdit = .tags(items: selectedItemsSnapshot())
            } label: {
                Label("batch.menu.setTags", systemImage: "tag")
            }
            Button {
                batchEdit = .location(items: selectedItemsSnapshot())
            } label: {
                Label("batch.menu.setLocation", systemImage: "mappin.and.ellipse")
            }
            Button {
                batchEdit = .source(items: selectedItemsSnapshot())
            } label: {
                Label("batch.menu.setSource", systemImage: "bag")
            }
        }
        Section {
            Button(action: batchMarkSeen) {
                Label("batch.menu.markSeen", systemImage: "checkmark.circle")
            }
            Button(action: batchMarkLost) {
                Label("batch.menu.markLost", systemImage: "questionmark.circle")
            }
        }
        Section {
            Button {
                let snapshot = selectedItemsSnapshot()
                aiRunner.understand(items: snapshot, allTags: allTags, allItems: items, context: modelContext)
                exitEditMode()
            } label: {
                Label("action.aiUnderstand", systemImage: "sparkles")
            }
            .disabled(!AISettings.hasActiveKey || multiSelection.isEmpty)
        }
        Section {
            Button(role: .destructive) {
                showingBulkDelete = true
            } label: {
                Label("bulk.delete.label \(count)", systemImage: "trash")
            }
            .disabled(multiSelection.isEmpty)
        }
    }

    private func exitEditMode() {
        multiSelection.removeAll()
        withAnimation(.snappy) { editMode = .inactive }
    }

    /// 批量标记"最近见过"(同 macOS batchMarkSeen)。
    private func batchMarkSeen() {
        let targets = selectedItemsSnapshot()
        guard !targets.isEmpty else { return }
        for item in targets {
            item.lastSeenAt = .now
            item.updatedAt = .now
            item.lastActionType = "stillThere"
            modelContext.insert(LocationLog(recordedAt: .now, location: item.location, item: item))
        }
        NotificationScheduler.shared.rescheduleIfEnabled()
        Haptics.success()
        flashBatchAck(String(localized: "batch.ack.markedSeen \(targets.count)"))
        exitEditMode()
    }

    /// 批量标记"不知道在哪"(同 macOS batchMarkLost)。
    private func batchMarkLost() {
        let targets = selectedItemsSnapshot()
        guard !targets.isEmpty else { return }
        for item in targets {
            item.location = nil
            item.lastSeenAt = .now
            item.updatedAt = .now
            item.lastActionType = "unknown"
            modelContext.insert(LocationLog(recordedAt: .now, location: nil, item: item))
        }
        Haptics.success()
        flashBatchAck(String(localized: "batch.ack.markedLost \(targets.count)"))
        exitEditMode()
    }

    // MARK: - Phase 120:AI 改名一键还原(列表行内)

    /// 若 item 的名字当前仍是 AI 最近一次改出来的值,返回改之前的旧名;否则 nil。
    /// 判定逻辑与 macOS 详情页 shouldShowRestoreButton 一致。
    private func aiRevertableOldName(for item: Item) -> String? {
        let log = item.editHistory
            .filter { $0.field == "name" && $0.source.hasPrefix("ai_") }
            .sorted { $0.recordedAt > $1.recordedAt }
            .first
        guard let log, let old = log.oldValue, !old.isEmpty,
              let new = log.newValue, item.name == new else { return nil }
        return old
    }

    /// 还原为 AI 改名前的名字,并写一条 source="restore" 的 EditLog(时间线可见)。
    private func revertAIName(for item: Item) {
        guard let old = aiRevertableOldName(for: item) else { return }
        let snap = ItemFieldSnapshot(item)
        item.name = old
        item.updatedAt = .now
        snap.recordEdits(against: item, source: "restore", in: modelContext)
        Haptics.success()
        flashBatchAck(String(localized: "row.ai.reverted"))
    }

    private func flashBatchAck(_ msg: String) {
        withAnimation(.snappy) { batchAck = msg }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            await MainActor.run { withAnimation { if batchAck == msg { batchAck = nil } } }
        }
    }

    /// Phase 118:同步结果 toast。合并了 N 条 → 显示条数;0 条 → "同步完成";失败 → 提示。
    private func flashSyncResult(_ r: (ok: Bool, merged: Int)) {
        if r.ok || r.merged > 0 { Haptics.success() } else { Haptics.warning() }
        withAnimation(.snappy) {
            if r.merged > 0 {
                syncToast = String(localized: "settings.sync.merged \(r.merged)")
            } else if r.ok {
                syncToast = String(localized: "settings.backup.done")
            } else {
                syncToast = String(localized: "settings.backup.failed")
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            await MainActor.run { withAnimation { syncToast = nil } }
        }
    }

    /// 单行卡片:缩略图 + 名字/位置/元数据 + 置顶/借出角标 → push 详情。
    @ViewBuilder
    private func itemRow(_ item: Item) -> some View {
        NavigationLink {
            IOSItemDetailView(item: item)
        } label: {
            HStack(spacing: 12) {
                ItemThumb(item: item)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        if !item.tags.isEmpty {
                            HStack(spacing: 2) {
                                ForEach(item.tags) { tag in
                                    Circle()
                                        .fill(Color(tagHex: tag.colorHex))
                                        .frame(width: 6, height: 6)
                                }
                            }
                        }
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        // Phase 120:AI 状态 —— 处理中 spinner+「正在AI理解」;
                        // 完成后 ✓ + 「一键还原」小字(名字被 AI 改过才显示)。
                        if aiRunner.processing.contains(item.persistentModelID) {
                            HStack(spacing: 3) {
                                ProgressView().controlSize(.mini)
                                Text("row.ai.processing")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } else if aiRunner.completed.contains(item.persistentModelID) {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                if aiRevertableOldName(for: item) != nil {
                                    Button {
                                        revertAIName(for: item)
                                    } label: {
                                        Text("row.ai.revert")
                                            .font(.caption2.weight(.medium))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.15), in: .capsule)
                                            .foregroundStyle(.orange)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    if let path = item.location?.path {
                        Label {
                            Text(verbatim: path).lineLimit(1)
                        } icon: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Label("location.unspecified", systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if let lentTo = item.lentTo {
                        Label {
                            Text("row.lent.label \(lentTo)").lineLimit(1)
                        } icon: {
                            Image(systemName: "person.fill.checkmark")
                        }
                        .font(.caption)
                        .foregroundStyle(.purple)
                    }
                }
            }
            .iosCard(padding: 12, cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                item.isPinned.toggle()
                Haptics.tap()
                NotificationScheduler.shared.rescheduleIfEnabled()
            } label: {
                Label(item.isPinned ? "action.unpin" : "action.pin",
                      systemImage: item.isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                item.markDeleted()
                Haptics.warning()
            } label: {
                Label("action.delete", systemImage: "trash")
            }
            Button {
                editingItem = item
            } label: {
                Label("action.edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu { itemMenu(item) }
    }

    /// 长按菜单(对齐 macOS 右键单条菜单的高频项)。
    @ViewBuilder
    private func itemMenu(_ item: Item) -> some View {
        Button {
            item.isPinned.toggle()
            NotificationScheduler.shared.rescheduleIfEnabled()
        } label: {
            Label(item.isPinned ? "action.unpin" : "action.pin",
                  systemImage: item.isPinned ? "pin.slash" : "pin")
        }
        Button {
            editingItem = item
        } label: {
            Label("action.editWithEllipsis", systemImage: "pencil")
        }
        if item.isLentOut {
            Button {
                let borrower = item.lentTo ?? ""
                item.markReturned()
                let entry = EditLog(recordedAt: .now, source: "returned", field: "returned",
                                    oldValue: borrower, newValue: nil, item: item)
                modelContext.insert(entry)
                Haptics.success()
            } label: {
                Label("batch.menu.markReturned", systemImage: "arrow.uturn.backward.circle")
            }
        } else {
            Button {
                lentSheetItem = item
            } label: {
                Label("batch.menu.lendOut", systemImage: "person.crop.circle.badge.plus")
            }
        }
        Button {
            aiRunner.understand(items: [item], allTags: allTags, allItems: items, context: modelContext)
        } label: {
            Label("action.aiUnderstand", systemImage: "sparkles")
        }
        .disabled(!AISettings.hasActiveKey)
        Divider()
        Button(role: .destructive) {
            pendingDelete = item
        } label: {
            Label("action.delete", systemImage: "trash")
        }
    }

    // MARK: - 顶部区块

    /// Phase 120:统计瓷砖 = 筛选器。
    ///   - 物品:点击清除全部筛选(有筛选时高亮成"清除"入口)
    ///   - 房间 / 渠道 / 品牌 / 年份:下拉菜单选一个,选中项再点一次取消
    ///   - 置顶 / 借出:点击开关式筛选,再点取消
    /// 选中的瓷砖描边高亮;瓷砖上的数字 = 当前筛选维度的计数。
    private var statsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // 物品(= 清除全部)
                StatTile(value: items.count, captionKey: "ios.stat.items",
                         systemName: filter.isEmpty ? "shippingbox.fill" : "xmark.circle.fill",
                         tint: IOSTheme.accent,
                         selected: !filter.isEmpty)
                    .onTapGesture {
                        Haptics.tap()
                        withAnimation(.snappy) { filter.clearAll() }
                    }
                // 房间(下拉)
                Menu {
                    ForEach(roomFacets, id: \.0) { (name, count) in
                        Button {
                            withAnimation(.snappy) {
                                filter.room = (filter.room == name) ? nil : name
                            }
                        } label: {
                            if filter.room == name {
                                Label("\(name)(\(count))", systemImage: "checkmark")
                            } else {
                                Text(verbatim: "\(name)(\(count))")
                            }
                        }
                    }
                    if filter.room != nil {
                        Divider()
                        Button("ios.tile.clearHint") {
                            withAnimation(.snappy) { filter.room = nil }
                        }
                    }
                } label: {
                    StatTile(value: roomCount, captionKey: "ios.stat.rooms",
                             systemName: "house.fill", tint: IOSTheme.accentAlt,
                             selected: filter.room != nil,
                             detailText: filter.room)
                }
                .buttonStyle(.plain)
                // 置顶(开关)
                StatTile(value: pinnedCount, captionKey: "ios.stat.pinned",
                         systemName: "pin.fill", tint: .orange,
                         selected: filter.pinned == true)
                    .onTapGesture {
                        Haptics.tap()
                        withAnimation(.snappy) {
                            filter.pinned = (filter.pinned == true) ? nil : true
                        }
                    }
                // 借出(开关)
                StatTile(value: lentOutCount, captionKey: "ios.stat.lent",
                         systemName: "person.fill.checkmark", tint: .purple,
                         selected: filter.lent == true)
                    .onTapGesture {
                        Haptics.tap()
                        withAnimation(.snappy) {
                            filter.lent = (filter.lent == true) ? nil : true
                        }
                    }
                // 渠道 / 品牌 / 年份(下拉,有数据才显示)
                facetTileMenu(values: sourceFacets, captionKey: "meta.label.source",
                              icon: "bag.fill", tint: .teal,
                              selected: filter.source) { v in
                    filter.source = (filter.source == v) ? nil : v
                }
                facetTileMenu(values: brandFacets, captionKey: "meta.label.brand",
                              icon: "seal.fill", tint: .indigo,
                              selected: filter.brand) { v in
                    filter.brand = (filter.brand == v) ? nil : v
                }
                facetTileMenu(values: yearFacets, captionKey: "meta.label.year",
                              icon: "calendar", tint: .pink,
                              selected: filter.year.map(String.init)) { v in
                    let y = Int(v)
                    filter.year = (filter.year == y) ? nil : y
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    /// 下拉式筛选瓷砖(渠道/品牌/年份共用)。values 空则不渲染。
    @ViewBuilder
    private func facetTileMenu(values: [(String, Int)], captionKey: LocalizedStringKey,
                               icon: String, tint: Color,
                               selected: String?, tap: @escaping (String) -> Void) -> some View {
        if !values.isEmpty {
            Menu {
                ForEach(values, id: \.0) { (value, count) in
                    Button {
                        withAnimation(.snappy) { tap(value) }
                    } label: {
                        if selected == value {
                            Label("\(value)(\(count))", systemImage: "checkmark")
                        } else {
                            Text(verbatim: "\(value)(\(count))")
                        }
                    }
                }
                if let selected {
                    Divider()
                    Button("ios.tile.clearHint") {
                        withAnimation(.snappy) { tap(selected) }
                    }
                }
            } label: {
                StatTile(value: values.count, captionKey: captionKey,
                         systemName: icon, tint: tint,
                         selected: selected != nil,
                         detailText: selected)
            }
            .buttonStyle(.plain)
        }
    }

    /// 渠道 facet(同 macOS 口径:distinct purchaseSource,按数量降序)。
    private var sourceFacets: [(String, Int)] {
        var counts: [String: Int] = [:]
        for item in items {
            if let s = item.purchaseSource, !s.isEmpty { counts[s, default: 0] += 1 }
        }
        return counts.sorted { ($0.value, $0.key) > ($1.value, $1.key) }.map { ($0.key, $0.value) }
    }

    /// 品牌 facet(name 词典实时推断,不入库,同 macOS)。
    private var brandFacets: [(String, Int)] {
        var counts: [String: Int] = [:]
        for item in items {
            if let b = InputParser.brand(for: item.name) { counts[b, default: 0] += 1 }
        }
        return counts.sorted { ($0.value, $0.key) > ($1.value, $1.key) }.map { ($0.key, $0.value) }
    }

    /// 年份 facet(购买年份,同 macOS)。
    private var yearFacets: [(String, Int)] {
        var counts: [Int: Int] = [:]
        for item in items {
            guard let d = item.purchaseDate else { continue }
            counts[Calendar.current.component(.year, from: d), default: 0] += 1
        }
        return counts.sorted { ($0.value, $0.key) > ($1.value, $1.key) }
            .map { (String($0.key), $0.value) }
    }

    /// AI 连接状态一行(仅配置了 key 时显示;点击去设置改)。
    @ViewBuilder
    private var aiStatusPill: some View {
        HStack(spacing: 8) {
            switch aiStatus {
            case .ready:
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("status.ai.ready")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                let t = AISettings.usageToday
                let w = AISettings.usageThisWeek
                let m = AISettings.usageThisMonth
                Text("status.ai.usage \(t.calls) \(w.calls) \(m.calls)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            case .testing:
                ProgressView().controlSize(.mini)
                Text("status.ai.testing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed(let msg):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text("status.ai.failed")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                if !msg.isEmpty {
                    Text(verbatim: msg)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            case .notConfigured:
                EmptyView()
            }
            Spacer(minLength: 0)
            Button("status.ai.retest") { checkAIConnection(force: true) }
                .font(.caption2)
                .buttonStyle(.borderless)
        }
        .font(.caption)
        .iosCard(padding: 10, cornerRadius: 14)
    }

    // MARK: - 名言滚动(Phase 116)

    /// 当前显示第几条(启动随机,之后定时轮换)。
    @State private var quoteIndex: Int = Int.random(in: 0..<QuoteBank.all.count)
    /// 12 秒换一条 —— 足够读完,又有"在滚动"的活气。
    private let quoteTimer = Timer.publish(every: 12, on: .main, in: .common).autoconnect()

    /// 列表底部的名言行:斜体小灰字 + 署名,换条时淡入淡出。
    private var quoteFooter: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(QuoteBank.all[quoteIndex])
                .font(.caption)
                .italic()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: "—— claude code")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .id(quoteIndex)  // 换条时整块重建 → transition 生效
        .transition(.opacity)
        .onReceive(quoteTimer) { _ in
            withAnimation(.easeInOut(duration: 0.8)) {
                var next = Int.random(in: 0..<QuoteBank.all.count)
                if next == quoteIndex { next = (next + 1) % QuoteBank.all.count }
                quoteIndex = next
            }
        }
        .padding(.horizontal, 4)
    }

    /// 全空状态(还没有任何物品):品牌渐变图标 + 三个示例句。
    private var emptyState: some View {
        VStack(spacing: 18) {
            GradientIconTile(systemName: "shippingbox.fill", size: 72, cornerRadius: 20)
            Text("empty.list.title")
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                Text("empty.list.description")
                Text("empty.list.example1").font(.callout)
                Text("empty.list.example2").font(.callout)
                Text("empty.list.example3").font(.callout)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .iosCard()
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Phase 115:演示物品的 rawInput 标记 —— 一键清除时按它精确定位,绝不误删用户数据。
    private static let demoMarker = "__hechu_demo__"

    /// 首启演示数据 —— 覆盖典型形态:多层位置、标签、置顶、借出、元数据、历史。
    /// 每件都打 demoMarker,横幅的「一键清除」只删带标记的。
    private func seedDemoData() {
        func make(_ name: String, path: [String], model: String? = nil,
                  color: String? = nil, version: String? = nil, source: String? = nil,
                  pinned: Bool = false, lentTo: String? = nil, tagName: String? = nil) {
            let loc = Location.ensure(path: path, in: modelContext)
            let item = Item(name: name, location: loc)
            item.model = model; item.color = color; item.version = version
            item.purchaseSource = source; item.isPinned = pinned
            item.rawInput = Self.demoMarker
            if let lentTo { item.markLentOut(to: lentTo) }
            if let tagName, let tag = allTags.first(where: { $0.name == tagName }) {
                item.tags.append(tag)
            }
            modelContext.insert(item)
            modelContext.insert(LocationLog(recordedAt: .now, location: loc, item: item))
        }
        make("充电宝", path: ["卧室", "五斗柜", "第二格抽屉"], model: "PB2022ZM",
             color: "黑色", source: "京东", pinned: true, tagName: "3C 电子")
        make("护照", path: ["书房", "保险箱"], pinned: true, tagName: "票据证件")
        make("Sony WH-1000XM5 降噪耳机", path: ["客厅", "电视柜"], color: "铂金银",
             source: "闲鱼", tagName: "3C 电子")
        make("iPad Pro 11 寸", path: ["书房", "桌面"], version: "512GB",
             lentTo: "妈妈", tagName: "3C 电子")
        make("瑞士军刀", path: ["玄关", "钥匙盒"], tagName: "小工具")
        make("防晒霜", path: ["卫生间", "镜柜"], tagName: "化妆护肤")
        make("露营天幕", path: ["储物间", "顶层架子"], source: "迪卡侬", tagName: "户外运动")
        try? modelContext.save()
    }

    /// Phase 115:演示数据横幅 —— 说明 + 「一键清除」/「留着」。
    private var demoBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .foregroundStyle(IOSTheme.accent)
                Text("demo.banner.title")
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button {
                    clearDemoData()
                } label: {
                    Text("demo.banner.clear")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(IOSTheme.gradient,
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Button {
                    Haptics.tap()
                    withAnimation(.snappy) { demoDataState = "dismissed" }
                } label: {
                    Text("demo.banner.keep")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .iosCard(padding: 14, cornerRadius: 18)
    }

    /// 一键清除:硬删带 demoMarker 的物品(cascade 连历史一起),
    /// 再清掉因此变空的位置节点(自底向上,不碰有用户物品/子节点的)。
    private func clearDemoData() {
        let demoItems = rawItems.filter { $0.rawInput == Self.demoMarker }
        for item in demoItems {
            modelContext.delete(item)
        }
        // 清空位置:反复扫直到没有可删的(叶子先掉,父级随后变空)
        var removed = true
        while removed {
            removed = false
            let locs = (try? modelContext.fetch(FetchDescriptor<Location>())) ?? []
            for loc in locs where loc.items.isEmpty && loc.children.isEmpty {
                modelContext.delete(loc)
                removed = true
            }
        }
        try? modelContext.save()
        Haptics.success()
        withAnimation(.snappy) {
            demoDataState = "dismissed"
            demoClearedToast = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            await MainActor.run { withAnimation { demoClearedToast = false } }
        }
    }

    // MARK: - 启动 seeding / 迁移(逻辑与 macOS ContentView 相同)

    private func seedTagsIfNeeded() {
        guard !hasSeedTags else { return }
        for preset in TagPalette.presets {
            let name = String(localized: String.LocalizationValue(preset.nameKey))
            if allTags.contains(where: { $0.name == name }) { continue }
            modelContext.insert(Tag(name: name, colorHex: preset.colorHex))
        }
        hasSeedTags = true
        seededTagPresetVersion = TagPresetMigration.currentVersion
    }

    private func seedExtendedPresetsIfNeeded() {
        guard seededTagPresetVersion < TagPresetMigration.currentVersion else { return }
        let newPresetKeys = TagPresetMigration.newKeysSince(version: seededTagPresetVersion)
        for preset in TagPalette.presets.filter({ newPresetKeys.contains($0.nameKey) }) {
            let name = String(localized: String.LocalizationValue(preset.nameKey))
            if allTags.contains(where: { $0.name == name }) { continue }
            modelContext.insert(Tag(name: name, colorHex: preset.colorHex))
        }
        seededTagPresetVersion = TagPresetMigration.currentVersion
    }

    /// 位置脏数据清理:先拆 name 含分隔符的,再合并同名根(幂等,每次启动跑)。
    private func cleanDirtyLocations() {
        _ = Location.splitMalformedNames(in: modelContext)
        _ = Location.mergeDuplicateRoots(in: modelContext)
    }

    /// Phase 118:AI 连接检测节流 —— 5 分钟内不重测(view 重建 / tab 切回都复用缓存),
    /// 只有点"重测"按钮才强制。跨 view 实例用 static 存。
    private static var lastAICheckAt: Date?
    private static var lastAIStatus: AIConnectionStatus?

    private func checkAIConnection(force: Bool = false) {
        guard let client = AISettings.currentClient() else {
            aiStatus = .notConfigured
            return
        }
        // 节流:5 分钟内直接用上次结果
        if !force,
           let last = Self.lastAICheckAt,
           Date.now.timeIntervalSince(last) < 300,
           let cached = Self.lastAIStatus {
            aiStatus = cached
            return
        }
        aiStatus = .testing
        Task {
            do {
                try await client.testConnection()
                await MainActor.run {
                    aiStatus = .ready
                    Self.lastAICheckAt = .now
                    Self.lastAIStatus = .ready
                }
            } catch {
                let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                let truncated = raw.count > 60 ? String(raw.prefix(60)) + "…" : raw
                await MainActor.run {
                    aiStatus = .failed(truncated)
                    Self.lastAICheckAt = .now
                    Self.lastAIStatus = .failed(truncated)
                }
            }
        }
    }
}

// MARK: - 透明列表行 helper

private extension View {
    /// 首页 List 的"透明行":藏分隔线、清背景、按卡片间距缩 insets。
    func listRowStyleClear(vertical: CGFloat = 6) -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: vertical, leading: 16, bottom: vertical, trailing: 16))
    }
}

// MARK: - AI 理解 runner(iOS)

/// 跟 macOS ContentView.runAIUnderstand 同一套非阻塞行为:
/// 顺序遍历目标(防 rate limit),行内 spinner / ✓ 状态,失败静默。
@MainActor
@Observable
final class IOSAIRunner {
    var processing: Set<PersistentIdentifier> = []
    var completed: Set<PersistentIdentifier> = []

    func understand(items targets: [Item], allTags: [Tag], allItems: [Item], context: ModelContext) {
        guard !targets.isEmpty, let client = AISettings.currentClient() else { return }
        for item in targets { processing.insert(item.persistentModelID) }

        let tagNames = allTags.map(\.name)
        let locPaths = Self.locationsSortedByRecency(items: allItems)

        Task {
            for item in targets {
                let id = item.persistentModelID
                do {
                    let result = try await client.understand(
                        item: item, availableTags: tagNames, availableLocations: locPaths)
                    await MainActor.run {
                        applyAIResult(result, to: item, in: context)
                        self.processing.remove(id)
                        self.completed.insert(id)
                    }
                    Task {
                        // Phase 120:10 秒窗口 —— 给用户看清 ✓ 并有时间点「一键还原」
                        try? await Task.sleep(for: .seconds(10))
                        await MainActor.run { _ = self.completed.remove(id) }
                    }
                } catch {
                    print("AI understand failed for \(item.name): \(error)")
                    await MainActor.run { _ = self.processing.remove(id) }
                }
            }
        }
    }

    /// 按"挂在该位置下的物品最新 lastSeenAt"降序,取前 50 条 path(同 macOS 版口径)。
    static func locationsSortedByRecency(items: [Item]) -> [String] {
        var bestSeen: [PersistentIdentifier: Date] = [:]
        var locByID: [PersistentIdentifier: Location] = [:]
        for item in items {
            guard let loc = item.location else { continue }
            let id = loc.persistentModelID
            locByID[id] = loc
            if let prev = bestSeen[id] {
                if item.lastSeenAt > prev { bestSeen[id] = item.lastSeenAt }
            } else {
                bestSeen[id] = item.lastSeenAt
            }
        }
        let sorted = bestSeen.sorted { $0.value > $1.value }
        return Array(sorted.compactMap { locByID[$0.key]?.path }.prefix(50))
    }
}

// MARK: - 借给… sheet(iOS 版)

/// iOS 风格的"借给…"底部卡:紫色主题 + detent 高度 300。
/// 保存后写 EditLog(跟 macOS 行为一致,详情时间线显示"借给 XX")。
struct IOSLentSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: Item
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    GradientIconTile(systemName: "person.crop.circle.badge.plus",
                                     size: 38, cornerRadius: 10,
                                     gradient: LinearGradient(colors: [.purple, .purple.opacity(0.6)],
                                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("detail.lent.sheet.title")
                        .font(.headline)
                }
                Text("detail.lent.sheet.description \(item.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("detail.lent.sheet.placeholder", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(save)
                Button(action: save) {
                    Text("detail.lent.sheet.confirm")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer(minLength: 0)
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            draft = item.lentTo ?? ""
            focused = true
        }
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        item.markLentOut(to: trimmed)
        let entry = EditLog(recordedAt: .now, source: "lent_out", field: "lent",
                            oldValue: nil, newValue: item.lentTo, item: item)
        modelContext.insert(entry)
        Haptics.success()
        dismiss()
    }
}

// MARK: - 回收站(iOS 版)

struct IOSTrashView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Item> { $0.isDeleted },
           sort: \Item.updatedAt, order: .reverse)
    private var deletedItems: [Item]

    @State private var showingEmptyConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if deletedItems.isEmpty {
                    ContentUnavailableView {
                        Label("trash.empty.title", systemImage: "archivebox")
                    } description: {
                        Text("trash.empty.description")
                    }
                } else {
                    List {
                        ForEach(deletedItems) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                    .strikethrough(color: .secondary)
                                HStack {
                                    if let path = item.location?.path {
                                        Label {
                                            Text(verbatim: path)
                                        } icon: {
                                            Image(systemName: "mappin.and.ellipse")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let d = item.deletedAt {
                                        Text("trash.row.deleted \(d.formatted(.relative(presentation: .named)))")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    item.restore()
                                    Haptics.success()
                                } label: {
                                    Label("trash.action.restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    modelContext.delete(item)
                                } label: {
                                    Label("trash.action.purge", systemImage: "trash.fill")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("trash.window.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        showingEmptyConfirm = true
                    } label: {
                        Image(systemName: "trash.slash")
                    }
                    .disabled(deletedItems.isEmpty)
                }
            }
            .confirmationDialog("trash.action.empty.confirm.title",
                                isPresented: $showingEmptyConfirm) {
                Button("trash.action.empty.confirm.button", role: .destructive) {
                    for item in deletedItems { modelContext.delete(item) }
                }
                Button("action.cancel", role: .cancel) {}
            } message: {
                Text("trash.action.empty.confirm.message")
            }
        }
    }
}
