import SwiftUI
import SwiftData
import UniformTypeIdentifiers  // UTType.json — fileExporter / FileDocument

// Phase 111:SortMode / FilterModel 挪到 Shared/FilterModel.swift,
// ExportSchema / WhereaboutsExportDocument 挪到 Shared/ExportSchema.swift ——
// iOS target 复用同一套筛选 / 排序 / 导出语义。本文件只进 macOS target。

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    /// 原始查询:只取未软删除的,再按 updatedAt desc 排;运行时按 sortMode 重排序。
    @Query(filter: #Predicate<Item> { !$0.isDeleted },
           sort: \Item.updatedAt, order: .reverse)
    private var rawItems: [Item]
    @Query private var allTags: [Tag]

    // Phase 116:名言库挪到 Shared/QuoteBank.swift(iOS 也用)。

    @AppStorage("sortMode") private var sortMode: SortMode = .updated

    /// 按当前 sortMode 排序后的列表 —— UI 全部用这个。
    /// 置顶物品(isPinned)永远在前,各自内部仍按 sortMode 排。
    private var items: [Item] {
        let sorted: [Item]
        switch sortMode {
        case .updated:
            sorted = rawItems  // 默认顺序就是 updatedAt desc
        case .seen:
            sorted = rawItems.sorted { $0.lastSeenAt > $1.lastSeenAt }
        case .created:
            sorted = rawItems.sorted { $0.createdAt > $1.createdAt }
        case .name:
            sorted = rawItems.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .location:
            sorted = rawItems.sorted {
                let p1 = $0.location?.path ?? "\u{FFFF}"  // nil 排末尾
                let p2 = $1.location?.path ?? "\u{FFFF}"
                return p1.localizedStandardCompare(p2) == .orderedAscending
            }
        }
        // partition:置顶在前,非置顶在后。各组内部保持上面的 sortMode 顺序(stable)。
        let pinned = sorted.filter { $0.isPinned }
        let unpinned = sorted.filter { !$0.isPinned }
        return pinned + unpinned
    }

    /// 已经 seed 过预设 tag —— 之后用户删掉某个不会被重新 seed 出来。
    @AppStorage("hasSeedTags") private var hasSeedTags: Bool = false

    /// Phase 59:预设标签集合的版本号。当前 v2 = 14 个预设(原 6 个 + 新加 8 个)。
    /// 升级路径:`< 2` → 跑一遍补 seed 缺失的预设名字(用户自建标签不动;用户**删过**
    /// 的预设也不会复活 —— 详见 seedExtendedPresetsIfNeeded 的实现)。
    /// 以后再扩预设时,把这个常量 bump 到 3,加新的预设到 TagPalette.presets,seed
    /// pass 自动只插库里没有的 name。
    @AppStorage("seededTagPresetVersion") private var seededTagPresetVersion: Int = 0

    // Phase 82:位置脏数据清理改为**每次启动跑** —— 幂等且廉价。
    // 早期版本只跑一次的 @AppStorage("mergedDuplicateRoots_v1") flag 被弃用 ——
    // 实测会出现:并发 AI 调用 → 各自 ensure 没看到对方的新 root → 创建多个同名根。
    // 既然 dedup 检测干净时只 fetch 一次就退出,跑成本几乎为零,改成每次启动都跑。

    @State private var draft = ""

    /// 焦点跟踪 —— toolbar 上的 ✏️ / 🔍 按钮通过设置这个值跳焦点。
    private enum FocusField: Hashable { case input, search }
    @FocusState private var focused: FocusField?

    /// 搜索区是否展开。默认折叠 —— 只显示标题 + 展开按钮,与"记一条"区视觉对比更强。
    /// Phase 46:搜索框现在始终常驻,这个 key 只控制下方 4 行 facet 是否展开。
    /// 默认折叠 —— 大多数时候用户只用搜索,facet 行更像高级筛选。
    /// 旧 key 名沿用("searchExpanded"),省一次迁移;旧版用户之前点开过会保留 true。
    @AppStorage("searchExpanded") private var facetsExpanded: Bool = false

    /// 选中行(Set 支持 ⌘/⇧ 多选 —— macOS List 自动支持)。
    /// 单选时驱动右侧 inspector;多选时 inspector 隐藏,只显示批量删除按钮。
    @State private var selection: Set<PersistentIdentifier> = []

    /// 录入时检测到重复 → 弹 alert。
    @State private var pendingDuplicate: PendingDuplicate?

    /// 当前正在编辑的物品 → 弹 sheet。
    @State private var editingItem: Item?

    /// Phase 56:右键"关联到…"触发的 RelatedItemsPicker 的源物品。non-nil 时弹 sheet。
    @State private var relatedPickerSource: Item?

    /// 识别为对已有物品的字段更新意图("X 的 型号是 Y" 等) → 弹 alert。
    @State private var pendingUpdate: PendingUpdate?

    /// 跨详情页共享的筛选条件(@Observable,改它就重渲染所有用到的视图)。
    @State private var filter = FilterModel()

    /// 等待用户确认删除的物品。non-nil 时 confirmationDialog 显示。
    @State private var pendingDelete: Item?

    /// 是否正在导出 JSON。绑 .fileExporter。
    @State private var showingExporter = false

    /// 导出时构造好的 document(避免在 view body 里每次 redraw 都重编码 JSON)。
    @State private var exportDocument: WhereaboutsExportDocument?

    /// 待确认批量删除的 id 集合。non-empty 时弹 confirmationDialog。
    @State private var pendingBulkDelete: Set<PersistentIdentifier> = []

    /// 当前打开的批量编辑 sheet。nil = 都没开。每个 case 携带的是参与本次操作的 Item 列表
    /// (在用户点菜单时就快照下来,避免 sheet 期间 selection 变化导致目标不一致)。
    @State private var batchEdit: BatchEditTarget?

    /// Phase 17:输入里给的单段位置撞上多个同名叶子,等用户挑一个。
    @State private var pendingAmbiguousLocation: PendingAmbiguousLocation?

    /// Phase 91:右键"借给…"打开的 sheet 的目标物品。non-nil 时弹 sheet。
    @State private var lentSheetItem: Item?
    @State private var lentSheetDraft: String = ""

    /// Phase 97:AI 启动 / 重测连接状态。
    /// 无 key → notConfigured(状态栏不显示);有 key → 启动跑一次 testConnection。
    @State private var aiStatus: AIConnectionStatus = .notConfigured

    /// 批量操作完成后短暂展示的 toast 行。非 nil 时悬浮在 statusBar 上方,~2.5 秒后清空。
    @State private var batchAck: String?

    /// 首次启动锚定时间戳 —— 状态栏"已使用 X 天"用它算。
    @AppStorage("firstLaunchTimestamp") private var firstLaunchTimestamp: Double = 0

    /// 本次 session 随机选的金句索引。session 内不变,每次启动重选 —— 用户"打开 app 就能看见一句新的"。
    /// 范围跟 QuoteBank.all.count 对齐(Phase 11 起 35 条)。
    @State private var quoteIndex: Int = Int.random(in: 0..<QuoteBank.all.count)

    /// 回收站 sheet 开关。
    @State private var showingTrash = false

    /// 录入行为开关 —— 偏好设置里可改;关闭则跳过 alert,直接落库。
    @AppStorage("dupDetectionEnabled") private var dupDetectionEnabled: Bool = true
    @AppStorage("updateIntentDetectionEnabled") private var updateIntentDetectionEnabled: Bool = true
    /// Phase 14:录入后按物品名自动建议一个预设 tag 挂上(可在偏好里关掉)。
    @AppStorage("autoTagSuggestEnabled") private var autoTagSuggestEnabled: Bool = true
    /// Phase 36:录入完一条后,是否自动用 AI 重新理解一遍(后台,不阻塞)。
    @AppStorage("useAIOnInput") private var useAIOnInput: Bool = false
    /// Phase 89/100:全局快捷键开关。inputBar 右上角根据它显示/隐藏快捷键提示。
    @AppStorage("globalHotKeyEnabled") private var globalHotKeyEnabled: Bool = true

    /// Phase 22:一次性回填迁移 —— 升级到 v0.1.3 build 6 后,对未挂 tag 的存量物品
    /// 跑一遍 suggestTagColorHex,把命中的预设标签补上。跑过之后 flag 永久置真。
    /// 这个 key 名带 build 号,以便未来再有一次性迁移时换 key 重跑。
    @AppStorage("autoTagMigration_v013_b6") private var autoTagMigrationDone: Bool = false

    /// 最近一次自动挂的 tag —— toast 的"撤销"按钮用,撤销后清空。
    @State private var pendingAutoTagUndo: (item: Item, tag: Tag)?

    // MARK: - Phase 28-29 → Phase 38:AI 理解 state(非阻塞)

    /// 当前正在被 AI 处理的物品 ID 集。row(for:) 渲染时查它,显示 "✨ 正在用 AI 理解…" 状态。
    @State private var aiProcessingIDs: Set<PersistentIdentifier> = []
    /// 刚刚 AI 完成、还在 4 秒"绿色 ✓ 已完成"窗口内的物品 ID 集。
    /// 4 秒后自动清,触发 row 重渲染。
    @State private var aiCompletedIDs: Set<PersistentIdentifier> = []

    var body: some View {
        NavigationStack {
            // Phase 79:主 VStack 现在**只装** facet 展开面板 + content(List)。
            // 顶部固定区(名言 / 记一条 / 搜索头)放进 `.safeAreaInset(edge: .top)`,
            // 这样 SwiftUI 把它们当作 chrome 钉死,无论 facet 怎么展开都不挪。
            VStack(spacing: 0) {
                facetExpansionPanel   // 只在展开时出现,向下挤压 List
                content
            }
            .task {
                // Phase 22:onAppear + .task 等效;放 .task 是因为 SwiftData @Query
                // 首次 fetch 完才能跑迁移,而 .task 比 onAppear 晚一帧执行。
                runAutoTagMigrationIfNeeded()
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                // Phase 79:钉死在顶部 —— 名言 / 记一条 / 搜索框这一坨。
                // 用户拉 facet 时这里**不动**,而是下方 List 被挤压。
                //
                // Phase 84:外层加 windowBackgroundColor 不透明底色 —— 之前
                // inputBar(accent 0.06)和 searchHeaderBar(secondary 0.10)都是
                // 半透明,List 滚到上方后透过来,跟顶栏文字重叠看不清。
                // 这层不透明 base 在最底下,inputBar 的 accent 浅色覆在它上面,List 永远透不过来。
                VStack(spacing: 0) {
                    quoteBanner
                    inputBar
                    Divider()
                    searchHeaderBar
                }
                .background(opaqueChromeBackground)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Phase 84:状态栏同样不透明底,防止 List 滚到下方透过来。
                statusBar
                    .background(opaqueChromeBackground)
            }
            .navigationTitle("app.name")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        // 右侧 inspector / iOS sheet。
        // 之前 ItemDetailView 内的 chip 点击会改 filter + dismiss,但 inspector dismiss 动画
        // 期间 SwiftUI 还会 redraw detail view 一次,此时 .environment(filter) 已不再有效,
        // @Environment(FilterModel.self) 触发 fatalError → 闪退。
        // 解决:detail view 不再使用 FilterModel,chip 改纯展示。这里也无需注入 filter。
        // 筛选完全交给顶部 facet 行 / 搜索框。
        .inspector(isPresented: inspectorBinding) {
            if let item = selectedItem {
                ItemDetailView(
                    item: item,
                    onAIUnderstand: { runAIUnderstand(items: [item]) },
                    isAIProcessing: aiProcessingIDs.contains(item.persistentModelID),
                    // Phase 55:详情页点关联超链接 → 把主列表 selection 改成目标 ID,
                    // inspector 自动用新 selectedItem 重渲。左侧列表 selection 也会高亮;
                    // 如果目标行被滚出了视区,用户手动滚一下,这版先不做自动 scrollTo。
                    onSelectItem: { targetID in
                        selection = [targetID]
                    }
                )
                    .id(item.persistentModelID)  // 切换 item 时强制重建状态
            } else if selection.count > 1 {
                ContentUnavailableView(
                    "inspector.placeholder.multi \(selection.count)",
                    systemImage: "square.stack"
                )
            } else {
                ContentUnavailableView(
                    "inspector.placeholder.empty",
                    systemImage: "sidebar.right"
                )
            }
        }
        .sheet(item: $editingItem) { item in
            ItemEditView(item: item)
        }
        // Phase 56:右键 → 关联到… 触发的挑选器
        .sheet(item: $relatedPickerSource) { src in
            RelatedItemsPicker(source: src) { target in
                flashBatchAck(String(localized: "related.ack.linked \(src.name) \(target.name)"))
            }
        }
        // Phase 91:右键 → 借给… 触发的 sheet
        .sheet(item: $lentSheetItem) { src in
            LentOutSheet(item: src, draft: $lentSheetDraft) { saved in
                if saved {
                    // Phase 95:写 EditLog,详情页时间线显示"借给 XX"
                    let entry = EditLog(
                        recordedAt: .now, source: "lent_out", field: "lent",
                        oldValue: nil, newValue: src.lentTo, item: src
                    )
                    modelContext.insert(entry)
                    flashBatchAck(String(localized: "batch.menu.lent.out.ack \(src.lentTo ?? "")"))
                }
                lentSheetItem = nil
            }
        }
        // 批量编辑 sheet —— 三种 target 复用同一个 sheet 槽,内部按 case 分发。
        .sheet(item: $batchEdit) { target in
            switch target {
            case .tags(let its):
                BatchTagsSheet(items: its) { count, tagCount in
                    flashBatchAck(String(localized: "batch.ack.tagsAdded \(count) \(tagCount)"))
                }
            case .location(let its):
                BatchLocationSheet(items: its) { count in
                    flashBatchAck(String(localized: "batch.ack.locationSet \(count)"))
                }
            case .source(let its):
                BatchSourceSheet(items: its) { count in
                    flashBatchAck(String(localized: "batch.ack.sourceSet \(count)"))
                }
            }
        }
        .alert("dup.alert.title", isPresented: duplicateAlertBinding,
               presenting: pendingDuplicate) { dup in
            // 新句子没说位置 → 不弹"更新位置"按钮,避免把已有 location 清空。
            // 改弹"补充信息"按钮,把新拿到的日期/渠道/型号/颜色补到 existing(已填的不覆盖)。
            if dup.newPath.isEmpty {
                if dup.hasMetadata {
                    Button("dup.alert.button.complete \(dup.existing.name)") {
                        resolveDuplicate(dup, asUpdate: true)
                    }
                }
            } else {
                Button("dup.alert.button.updateLocation \(dup.newPath.joined(separator: " › "))") {
                    resolveDuplicate(dup, asUpdate: true)
                }
            }
            Button("dup.alert.button.createNew") { resolveDuplicate(dup, asUpdate: false) }
            Button("action.cancel", role: .cancel) { pendingDuplicate = nil }
        } message: { dup in
            // 用户数据(name / location path)用 String 内插;"未指定位置" fallback 走 catalog。
            let oldLoc = dup.existing.location?.path ?? String(localized: "location.unspecified")
            if dup.newPath.isEmpty {
                Text("dup.alert.message.noLocation \(dup.existing.name) \(oldLoc) \(dup.metaSummary)")
            } else {
                let newLoc = dup.newPath.joined(separator: " › ")
                Text("dup.alert.message.withLocation \(dup.existing.name) \(oldLoc) \(dup.newName) \(newLoc)")
            }
        }
        // Phase 17:歧义位置选择 sheet —— 多个同名叶子时让用户挑一个。
        // 用 sheet 而非 confirmationDialog —— body 修饰符链已经够长,加一个
        // dialog 会触发 SwiftUI 的 type-check 超时。sheet 是单 modifier,且
        // 候选行的 UI 比 dialog 的扁平按钮列表更易读。
        .sheet(item: $pendingAmbiguousLocation) { ctx in
            AmbiguousLocationPicker(context: ctx) { choice in
                resolveAmbiguousLocation(ctx, choice: choice)
            }
        }
        // Phase 38:AI 进度 sheet 已撤掉 —— 改成行内 inline 状态(aiProcessingIDs / aiCompletedIDs)。
        // 用户在 AI 处理期间能继续录入、删除、切换其它项,而不是被一个 modal 锁住。
        .alert("update.alert.title", isPresented: updateAlertBinding,
               presenting: pendingUpdate) { upd in
            Button("update.alert.button.update \(upd.item.name)") { applyUpdate(upd) }
            Button("update.alert.button.createInstead")            { createFromRawDraft() }
            Button("action.cancel", role: .cancel) { pendingUpdate = nil }
        } message: { upd in
            Text("update.alert.message \(upd.item.name) \(upd.summary)")
        }
        // 删除确认。context menu / detail page 触发(swipe 不触发,swipe 已经是 deliberate 手势)。
        .confirmationDialog(
            "delete.alert.title",
            isPresented: deleteConfirmBinding,
            presenting: pendingDelete
        ) { item in
            Button("action.delete", role: .destructive) {
                selection.remove(item.persistentModelID)
                // 软删除:进回收站,不真删
                item.markDeleted()
                pendingDelete = nil
            }
            Button("action.cancel", role: .cancel) { pendingDelete = nil }
        } message: { item in
            Text("delete.alert.message \(item.name)")
        }
        // 批量删除确认 —— toolbar 触发,会清空 selection。
        .confirmationDialog(
            "bulk.delete.confirm.title",
            isPresented: bulkDeleteBinding
        ) {
            Button("bulk.delete.confirm.button \(pendingBulkDelete.count)", role: .destructive) {
                for id in pendingBulkDelete {
                    if let item = items.first(where: { $0.persistentModelID == id }) {
                        item.markDeleted()
                    }
                }
                selection.removeAll()
                pendingBulkDelete = []
            }
            Button("action.cancel", role: .cancel) { pendingBulkDelete = [] }
        } message: {
            Text("bulk.delete.confirm.message \(pendingBulkDelete.count)")
        }
        .sheet(isPresented: $showingTrash) {
            TrashView()
                .environment(\.locale, Locale.autoupdatingCurrent)
        }
        // 导出 JSON。toolbar 按钮触发,document 在按钮 action 里 lazily 构造。
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: WhereaboutsExportDocument.defaultFilename()
        ) { _ in
            // 成功 / 失败都静默 —— 系统会显示 Save panel 关闭。释放编码后的 data 减内存。
            exportDocument = nil
        }
        .toolbar {
            // 跳到 ✏️ 录入框 —— ⌘N
            ToolbarItem(placement: .primaryAction) {
                Button {
                    focused = .input
                } label: {
                    Label("toolbar.button.input", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: [.command])
                .help("toolbar.button.input.tooltip")
            }
            // 跳到 🔍 搜索框 —— ⌘F;如果搜索区折叠,先展开
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if !facetsExpanded {
                        withAnimation(.snappy) { facetsExpanded = true }
                    }
                    // 加点延迟让 view 先 render 出 searchField,再设 focus
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focused = .search
                    }
                } label: {
                    Label("toolbar.button.search", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: [.command])
                .help("toolbar.button.search.tooltip")
            }
            // 回收站 —— 最近删除的物品,可还原 / 彻底删除
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingTrash = true
                } label: {
                    Label("trash.toolbar.label", systemImage: "archivebox")
                }
                .help("trash.toolbar.tooltip")
            }
            // 排序方式 menu —— 选 = checkmark
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker(selection: $sortMode) {
                        ForEach(SortMode.allCases) { mode in
                            Label(mode.displayKey, systemImage: mode.systemImage).tag(mode)
                        }
                    } label: {
                        Text("sort.menu.label")
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("sort.menu.label", systemImage: "arrow.up.arrow.down")
                }
                .help("sort.menu.tooltip")
            }
            // 批量编辑 —— 多选时下拉出现 5 个动作,右键菜单里也有镜像项。
            // 抽出 toolbarBatchMenu 减轻主 body 的 type-check 负担(Phase 35)。
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    toolbarBatchMenu
                } label: {
                    Label("batch.menu.title", systemImage: "square.and.pencil.circle")
                }
                .disabled(selection.count < 2)
                .help("batch.menu.tooltip")
            }
            // 批量删除 —— 多选时才有意义,默认 disabled
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    pendingBulkDelete = selection
                } label: {
                    Label("bulk.delete.label \(selection.count)", systemImage: "trash")
                }
                .disabled(selection.isEmpty)
                .help("bulk.delete.tooltip")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // 编码当前 items 到 JSON,等 fileExporter 上来用
                    exportDocument = WhereaboutsExportDocument(items: items)
                    showingExporter = true
                } label: {
                    Label("export.button", systemImage: "square.and.arrow.up")
                }
                .disabled(items.isEmpty)
                .help("export.button.tooltip")
            }
        }
        .task {
            // 首次启动 seed 预设 tag。@AppStorage flag 防止用户删了重启被覆盖。
            seedTagsIfNeeded()
            // Phase 59:版本化扩充 —— 升级后补 seed 新加的预设,但不动用户自建/已删的。
            seedExtendedPresetsIfNeeded()
            // Phase 76:合并同名根 Location(早期 case-sensitive ensure 留下的双胞胎)。
            // @AppStorage flag 防止重复跑(每次启动只一次)。
            mergeDuplicateRootsIfNeeded()
        }
    }

    /// 第一次启动 / 用户从未生成过预设时,在数据库里建预设 tag。
    /// 用 @AppStorage("hasSeedTags") 记是否 seed 过 —— 用户后续删任意一个,重启不会被复活。
    /// 这一步 seed 整个 TagPalette.presets 数组(对新装用户来说所有预设一次到位);
    /// 老用户(hasSeedTags=true)走 seedExtendedPresetsIfNeeded 单独补新加的。
    private func seedTagsIfNeeded() {
        guard !hasSeedTags else { return }
        for preset in TagPalette.presets {
            let name = String(localized: String.LocalizationValue(preset.nameKey))
            // 避免同名 tag 反复 seed(理论上 hasSeedTags=false 时库是空的,但保险一下)
            if allTags.contains(where: { $0.name == name }) { continue }
            let tag = Tag(name: name, colorHex: preset.colorHex)
            modelContext.insert(tag)
        }
        hasSeedTags = true
        // 新装用户首次也算"已 seed 到当前版本",避免下面再跑一遍。
        seededTagPresetVersion = TagPresetMigration.currentVersion
    }

    /// Phase 76 → Phase 82:启动时清理位置脏数据。
    /// **每次启动都跑**(幂等;干净时只 fetch 一次就退出)。两步:
    ///   1. splitMalformedNames:Location.name 内含 `>` / `》` / `→` 的脏节点拆成正常路径
    ///      (来自早期 AI 偶尔返回单段含分隔符的 path)
    ///   2. mergeDuplicateRoots:fold-match 同名的根 Location 合并到 item 数最多的那个
    ///      (拆完可能多出更多 root,所以**先拆后合**)
    /// 任一步影响过节点时弹底部 toast 告知。
    private func mergeDuplicateRootsIfNeeded() {
        let split = Location.splitMalformedNames(in: modelContext)
        let merged = Location.mergeDuplicateRoots(in: modelContext)
        let total = split + merged
        if total > 0 {
            flashBatchAck(String(localized: "migrate.dedupRoots.toast \(total)"))
        }
    }

    /// Phase 59:老用户升级后跑一次,把当前 preset 集合里**还没在库**的预设补进来。
    ///
    /// 关键约束(用户原话:"不要动用户自己创建的标签"):
    ///   - 只看 name 是否已存在 → 已存在(无论用户改色 / 改名 / 还是原版)一律跳过
    ///   - 用户删过的 preset name 不会自动复活 —— 因为 `hasSeedTags=true` 时初次 seed
    ///     已经把所有当时存在的预设入了库。**但**:本次新加的 8 个预设属于"以前从未
    ///     seed 过",所以会进库。这是预期行为:**新增的预设默认开启**,用户不喜欢
    ///     可单独删。
    ///   - 用 seededTagPresetVersion @AppStorage 记当前已 seed 到哪版,只跑一次。
    private func seedExtendedPresetsIfNeeded() {
        guard seededTagPresetVersion < TagPresetMigration.currentVersion else { return }
        // 这一版第一次跑 → 取本版新加的预设 keys
        let newPresetKeys = TagPresetMigration.newKeysSince(version: seededTagPresetVersion)
        let newPresets = TagPalette.presets.filter { newPresetKeys.contains($0.nameKey) }
        for preset in newPresets {
            let name = String(localized: String.LocalizationValue(preset.nameKey))
            if allTags.contains(where: { $0.name == name }) { continue }
            let tag = Tag(name: name, colorHex: preset.colorHex)
            modelContext.insert(tag)
        }
        seededTagPresetVersion = TagPresetMigration.currentVersion
    }

    /// Phase 84:safeAreaInset 钉死的顶/底栏需要**不透明**底色,
    /// 否则 List 滚到上方/下方时半透明的 inputBar / statusBar 会让物品文字透过来。
    /// 跨平台:macOS 用窗口背景色,iOS 用 systemBackground —— 两端都是 100% 不透明。
    private var opaqueChromeBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(.systemBackground)
        #endif
    }

    // MARK: - 顶部金句横幅(Phase 11 移过来)

    /// 顶部金句横幅 —— 35 条名人名言风格鸡汤,每次启动随机一条,尾巴署 "—— claude code"。
    /// Phase 11 之前这段在底部 statusBar,现在挪到 "记一条" 输入框上方,打开 app 立刻看得到。
    /// 视觉:斜体灰字 + 右下角小字署名;底色比 inputBar 更淡,显得安静而不抢戏。
    private var quoteBanner: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(QuoteBank.all[quoteIndex])
                .font(.callout)
                .italic()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
            Text(verbatim: "—— claude code")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.05))
    }

    // MARK: - 底部状态栏

    /// 底部状态栏:仅统计行 ——"X 样物品 · Y 个房间 · Z 天"。
    /// Phase 11 之前还显示一条随机鸡汤,现已挪到顶部 quoteBanner。
    /// 用 .safeAreaInset 浮在内容下方,List 滚动不影响它。
    /// 上面可叠两条 toast:
    ///   - 自动建议挂 tag(带"撤销"按钮,Phase 14)
    ///   - 批量操作回执(纯文字,Phase 12)
    ///   - Phase 97:AI 连接状态 / 用量条(只在配了 API key 时显示)
    /// 几者独立显示,不互相覆盖。
    private var statusBar: some View {
        VStack(spacing: 0) {
            if let pair = pendingAutoTagUndo {
                autoTagToast(item: pair.item, tag: pair.tag)
            }
            if let ack = batchAck {
                Text(verbatim: ack)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.08))
                    .transition(.opacity)
            }
            // Phase 97:AI 状态行(只在配了 key 才出现)
            aiStatusRow
            Text(verbatim: summaryLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.bar)
        }
        .animation(.easeInOut(duration: 0.2), value: batchAck)
        .animation(.easeInOut(duration: 0.2), value: pendingAutoTagUndo?.tag.persistentModelID)
        .animation(.easeInOut(duration: 0.2), value: aiStatus)
        .onAppear {
            // 首次启动锚定使用日期(只设一次)
            if firstLaunchTimestamp == 0 {
                firstLaunchTimestamp = Date.now.timeIntervalSince1970
            }
            // Phase 97:启动时检测 AI 连接 —— 有 key 才测;
            // 无 key 时 aiStatus 留 .notConfigured,状态栏不渲染 AI 行。
            checkAIConnection()
        }
        // Phase 100:QuickEntry 在"搜索"模式提交时广播 query;主窗口收到后把
        // 关键词写进 filter.search,并把列表 facet 展开(确保搜索栏可见)。
        .onReceive(NotificationCenter.default.publisher(for: .quickEntrySearch)) { note in
            guard let q = note.userInfo?["query"] as? String else { return }
            filter.search = q
            facetsExpanded = true  // 确保搜索区可见
        }
        // Phase 106:点击置顶通知 banner 后,NotificationTapForwarder 广播
        // `.openItemByName`;主窗口接住后把名字写进搜索,并强制激活窗口。
        .onReceive(NotificationCenter.default.publisher(for: .openItemByName)) { note in
            guard let name = note.userInfo?["itemName"] as? String else { return }
            filter.clearAll()  // 不让旧筛选条件挡住目标物品
            filter.search = name
            #if os(macOS)
            NSApp.activate(ignoringOtherApps: true)
            #endif
        }
        #if os(macOS)
        // Phase 117:退出 app 时自动往 iCloud 云盘写一份 JSON 备份(同步版,quit 前完成)。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            CloudBackup.backUpBlocking(context: modelContext)
        }
        #endif
    }

    /// Phase 97:状态栏 AI 行。
    /// 三态:① ready → 绿色 ✓ "AI 已就绪" + 今 / 本周 / 本月 N 次;② failed → 红色 ⚠️ 提示文字;
    /// ③ testing → spinner;④ notConfigured → 不渲染。每行右侧有"重测"按钮(testing 时禁用)。
    @ViewBuilder
    private var aiStatusRow: some View {
        switch aiStatus {
        case .notConfigured:
            EmptyView()
        case .testing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("status.ai.testing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.06))
            .transition(.opacity)
        case .ready:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("status.ai.ready")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                let today = AISettings.usageToday
                let week  = AISettings.usageThisWeek
                let month = AISettings.usageThisMonth
                Text("status.ai.usage \(today.calls) \(week.calls) \(month.calls)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("status.ai.retest") { checkAIConnection() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.caption2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.06))
            .transition(.opacity)
        case .failed(let msg):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text("status.ai.failed")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                if !msg.isEmpty {
                    Text(verbatim: "· \(msg)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer()
                Button("status.ai.retest") { checkAIConnection() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.caption2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Color.red.opacity(0.08))
            .transition(.opacity)
        }
    }

    /// Phase 97:在后台跑一次 testConnection,把结果写回 aiStatus。
    /// 无 key → 直接归为 .notConfigured。失败错误信息截断到 60 字,避免占满状态栏。
    private func checkAIConnection() {
        guard let client = AISettings.currentClient() else {
            aiStatus = .notConfigured
            return
        }
        aiStatus = .testing
        Task {
            do {
                try await client.testConnection()
                await MainActor.run { aiStatus = .ready }
            } catch {
                let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                let truncated = raw.count > 60 ? String(raw.prefix(60)) + "…" : raw
                await MainActor.run { aiStatus = .failed(truncated) }
            }
        }
    }

    /// Phase 14:自动建议挂 tag 的 toast(带"撤销"按钮)。
    /// 设计:左色点 + "已自动加标签:XX" + 撤销按钮。整行高 ~28pt,跟 statusBar 等宽。
    @ViewBuilder
    private func autoTagToast(item: Item, tag: Tag) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(tagHex: tag.colorHex))
                .frame(width: 10, height: 10)
            // 标签名是用户数据,verbatim 注入到 catalog 模板里
            Text("autoTag.applied \(tag.name)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("autoTag.undo", action: undoAutoTag)
                .buttonStyle(.borderless)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.08))
        .transition(.opacity)
    }

    /// "X 样物品 · 放在 Y 个房间 · 已使用 Z 天"。三段分别 plural 化后用 " · " 拼。
    private var summaryLine: String {
        let itemsText = String(localized: "status.summary.items \(items.count)")
        let roomsText = String(localized: "status.summary.rooms \(roomCount)")
        let daysText  = String(localized: "status.summary.days \(daysUsed)")
        return [itemsText, roomsText, daysText].joined(separator: " · ")
    }

    /// 顶级 location 名字的 distinct 数 —— "X 个房间"。
    private var roomCount: Int {
        var topNames: Set<String> = []
        for item in items {
            var cursor: Location? = item.location
            while let p = cursor?.parent { cursor = p }
            if let name = cursor?.name { topNames.insert(name) }
        }
        return topNames.count
    }

    /// 从首次启动到今天的天数(含今天,至少 1)。
    private var daysUsed: Int {
        guard firstLaunchTimestamp > 0 else { return 1 }
        let first = Date(timeIntervalSince1970: firstLaunchTimestamp)
        let firstDay = Calendar.current.startOfDay(for: first)
        let today = Calendar.current.startOfDay(for: .now)
        let diff = (Calendar.current.dateComponents([.day], from: firstDay, to: today).day ?? 0) + 1
        return max(1, diff)
    }

    // MARK: - 录入栏

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "square.and.pencil")
                    .font(.caption)
                Text("input.section.title")
                    .font(.caption.bold())
                Spacer()
                // Phase 100:右上角显示当前全局快捷键(默认 ⌥⌘N)
                // 用户改键位后这里同步显示;开关关掉时不渲染。
                #if os(macOS)
                if globalHotKeyEnabled {
                    Text("input.hotkey.hint \(HotKeyFormatter.display(keyCode: GlobalHotKey.currentKeyCode, modifiers: GlobalHotKey.currentModifiers))")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
                #endif
            }
            .foregroundStyle(Color.accentColor)
            HStack(spacing: 8) {
                TextField("input.textField.placeholder", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .input)
                    .onSubmit(commit)
                    .submitLabel(.done)

                Button(action: commit) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(InputParser.parseMultiple(draft).isEmpty)
            }
            if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                parsePreview
            } else {
                // Phase 48:空状态展示一段轻量教程,提示"一次可以记多条 / 位置写自然语言即可"。
                // 用户一开始打字就被 parsePreview 顶掉,不打扰流。
                inputHint
            }
            // Phase 13:已经输入了物品名但还没说位置 → 推荐最近用过的位置 chip。
            if shouldShowLocationHints {
                recentLocationHints
            }
            // Phase 36:AI 重新理解开关 —— 勾上后每条录入完都会后台调一次 AI 加工字段。
            // disabled 状态(无 API key)tooltip 提示去偏好设置。
            aiOnInputToggle
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // accent 色浅底:跟下方"搜索/筛选"区拉开
        .background(Color.accentColor.opacity(0.06))
    }

    /// Phase 48:空状态的录入小教程。
    /// Phase 65:无 AI key 时**额外加一行紫色强推荐** —— 点行打开偏好设置 AI tab。
    @ViewBuilder
    private var inputHint: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "lightbulb")
                    .font(.caption2)
                Text("input.hint.line1")
                    .font(.caption2)
            }
            Text("input.hint.line2")
                .font(.caption2)
                .padding(.leading, 17)  // 跟 line1 文字对齐(让出 icon 宽度)
            // Phase 65:没配 AI key → 强推荐配上(本地解析有限)。
            // 配过的用户不重复打扰,免得占位置。
            if !AISettings.hasActiveKey {
                aiRecommendationLine
            }
        }
        .foregroundStyle(.secondary)
    }

    /// Phase 65:AI 配置强推荐行。点击打开 macOS Settings(默认会停在最近一次访问的 tab)。
    /// macOS 14+ 用 SettingsLink 拿到原生"打开偏好设置"行为,跨进程都对。
    @ViewBuilder
    private var aiRecommendationLine: some View {
        SettingsLink {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                Text("input.hint.aiRecommend")
                    .font(.caption2.bold())
                Image(systemName: "arrow.up.forward")
                    .font(.caption2)
            }
            .foregroundStyle(Color.purple)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(Color.purple.opacity(0.10), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var aiOnInputToggle: some View {
        let hasKey = AISettings.hasActiveKey
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Toggle(isOn: Binding(
                get: { useAIOnInput && hasKey },
                set: { useAIOnInput = $0 }
            )) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                    Text("input.aiToggle.label")
                        .font(.caption)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(!hasKey)
            .help(hasKey
                  ? String(localized: "input.aiToggle.hint")
                  : String(localized: "input.aiToggle.disabledHint"))
            Text(hasKey ? "input.aiToggle.hint" : "input.aiToggle.disabledHint")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
    }

    // MARK: - Phase 13:最近位置自动完成

    /// 触发条件:输入框 focused + 已有物品名 + 还没解析出位置 +
    ///   (历史里有过位置 OR draft 里检测到已存在的房间名)。
    /// 用户已经写明位置(parsePreview 里能看到层级)就不打扰 —— chip 行自动收起。
    private var shouldShowLocationHints: Bool {
        guard focused == .input else { return false }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let first = InputParser.parseMultiple(draft).first,
           !first.locationPath.isEmpty {
            return false
        }
        return !recentLocations.isEmpty || !inRoomSuggestions.isEmpty
    }

    /// 去重后最近用过的最多 5 个位置(按 item.lastSeenAt 降序选出 distinct location)。
    /// 注:这里看的是 items(已过滤软删除的),trash 里的不带进来。
    private var recentLocations: [Location] {
        var seen: Set<PersistentIdentifier> = []
        var result: [Location] = []
        for item in items.sorted(by: { $0.lastSeenAt > $1.lastSeenAt }) {
            guard let loc = item.location else { continue }
            if seen.insert(loc.persistentModelID).inserted {
                result.append(loc)
                if result.count >= 5 { break }
            }
        }
        return result
    }

    /// Phase 62:从 draft 文本里检测到一个已存在的 Location(房间 / 大型家具),
    /// 用于给"该 location 内子位置"上浮成 chip 提示。
    /// 策略:**最长** name 命中(避免短名 "床" 抢了 "床头柜"),case-insensitive。
    /// 优先取 parent==nil 的根节点 —— 它们语义上更像"房间";找不到根再退到任意层。
    private var detectedRoomInDraft: Location? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let foldedDraft = trimmed.foldedForMatch
        let all = (try? modelContext.fetch(FetchDescriptor<Location>())) ?? []
        // 候选:name 出现在 draft 里、且至少有一个子节点(没子的没必要提示)
        let candidates = all.filter { loc in
            !loc.name.isEmpty
                && !loc.children.isEmpty
                && foldedDraft.contains(loc.name.foldedForMatch)
        }
        // 先在根里挑最长;没根再退所有候选里挑最长
        let roots = candidates.filter { $0.parent == nil }
        let pool = roots.isEmpty ? candidates : roots
        return pool.max { $0.name.count < $1.name.count }
    }

    /// Phase 62:检测到的房间下的直接子位置 chip 列表。
    /// 去除已在 recentLocations 里出现的(避免两行重复),上限 6 个。
    private var inRoomSuggestions: [Location] {
        guard let room = detectedRoomInDraft else { return [] }
        let recentIDs = Set(recentLocations.map { $0.persistentModelID })
        return room.children
            .sorted { $0.name < $1.name }
            .filter { !recentIDs.contains($0.persistentModelID) }
            .prefix(6)
            .map { $0 }
    }

    /// 横向 chip 行:caption 标题 + 最多 5 个位置 chip。点击 chip 直接追加到 draft。
    ///
    /// Phase 62:在"最近用过"上方再加一行"<房间> 内"chip,
    /// 当 draft 文本里检测到一个已存在房间名 + 该房间有子位置时展示。
    @ViewBuilder
    private var recentLocationHints: some View {
        VStack(alignment: .leading, spacing: 6) {
            // —— in-room 提示行(Phase 62)——
            if let room = detectedRoomInDraft, !inRoomSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "house.fill")
                            .font(.caption2)
                        Text("input.inRoom.label \(room.name)")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    WrapLayout(spacing: 4, lineSpacing: 3) {
                        ForEach(inRoomSuggestions) { loc in
                            locationChip(loc, accent: .accentColor)
                        }
                    }
                }
            }
            // —— 最近用过行(原 Phase 13)——
            if !recentLocations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption2)
                        Text("input.recentLocations.label")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    WrapLayout(spacing: 4, lineSpacing: 3) {
                        ForEach(recentLocations) { loc in
                            locationChip(loc, accent: .accentColor)
                        }
                    }
                }
            }
        }
        .transition(.opacity)
    }

    /// Phase 62:可复用的 location chip 按钮。点 → 追加到 draft。
    @ViewBuilder
    private func locationChip(_ loc: Location, accent: Color) -> some View {
        Button {
            appendLocationToDraft(loc)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption2)
                Text(verbatim: loc.path)
                    .font(.caption2)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(accent.opacity(0.12), in: .capsule)
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    /// 把 loc 追加到 draft 末尾,带"在"分隔。focus 不丢,光标停在末尾。
    /// 不试图智能 dedupe —— 用户可以编辑后再回车。
    private func appendLocationToDraft(_ loc: Location) {
        //   英文用户暂未支持自然语言解析,此处一律用 "在"(parser 的中文分隔符之一)。
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = trimmed.isEmpty ? loc.path : "\(trimmed) 在 \(loc.path)"
        focused = .input
    }

    @ViewBuilder
    private var parsePreview: some View {
        let list = InputParser.parseMultiple(draft)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                if list.count > 1 {
                    // catalog key 实际是 "input.preview.willCreate %lld",zh 用 other variant。
                    Text("input.preview.willCreate \(list.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ForEach(list.indices, id: \.self) { i in
                    let p = list[i]
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            // p.name 是从用户输入解析出的字符串(verbatim 显示)。
                            Text(p.name)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15), in: .capsule)
                            if !p.locationPath.isEmpty {
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(p.locationPath.joined(separator: " › "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        // 自动抽到的元数据:有就以小灰胶囊展示
                        extractedMetaRow(p)
                    }
                }
            }
            .padding(.leading, 2)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func extractedMetaRow(_ p: InputParser.Parsed) -> some View {
        // labelKey 存 catalog key 字符串,显示时 wrap 成 LocalizedStringKey;value 是用户数据 verbatim。
        let pairs: [(labelKey: String, value: String)] = {
            var out: [(String, String)] = []
            if let m = p.model { out.append(("meta.label.model", m)) }
            if let c = p.color { out.append(("meta.label.color", c)) }
            if let s = p.purchaseSource { out.append(("meta.label.source", s)) }
            if let label = formatPurchaseDate(p.purchaseDate, precision: p.purchaseDatePrecision) {
                out.append(("meta.label.purchase", label))
            }
            return out
        }()
        if !pairs.isEmpty {
            HStack(spacing: 4) {
                ForEach(pairs, id: \.0) { (labelKey, value) in
                    HStack(spacing: 2) {
                        Text(LocalizedStringKey(labelKey)).font(.caption2).foregroundStyle(.secondary)
                        Text(value).font(.caption2)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.10), in: .capsule)
                }
                Spacer()
            }
            .padding(.leading, 14)  // 视觉对齐"将创建 N 条"下方
        }
    }

    // MARK: - 搜索 + facet 分面

    /// 派生:全集过滤后的列表(列表显示用)。
    private var filteredItems: [Item] {
        guard !filter.isEmpty else { return items }
        return items.filter { filter.matches($0) }
    }

    /// Phase 79:**搜索头**(始终可见)—— 搜索框 + chevron 切换 facet。
    /// 跟下面的 `facetExpansionPanel` 拆开,这样头部可以被钉死在顶部 safe area,
    /// 而 facet 展开时只挤压下面的 List 区域,不会把顶部元素推走。
    @ViewBuilder
    private var searchHeaderBar: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    searchField
                    Button {
                        withAnimation(.snappy) { facetsExpanded.toggle() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Image(systemName: facetsExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                        .font(.callout)
                        .foregroundStyle(facetsExpanded ? Color.accentColor : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Color.secondary.opacity(facetsExpanded ? 0.18 : 0.10),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("filter.facets.toggle.tooltip")
                }
                // 活动筛选 chip(品牌=X / 年份=Y / ...)即便 facet 折叠也跟搜索一起留在顶部 ——
                // 折叠状态下让用户随时知道当前应用了哪些筛选。
                activeExactFilters
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.10))
            .overlay(alignment: .top) { Divider() }
        }
    }

    /// Phase 79:**facet 展开面板** —— 5 行 chip。只在 facetsExpanded 时出现。
    /// 放在主 VStack 里,夹在顶部固定区和 List 之间;展开时**向下压 List**,
    /// 不影响顶部任何元素。
    ///
    /// Phase 80:外面套 ScrollView + `maxHeight: 280` —— 防止用户库里位置非常多
    /// (chip 行换 5+ 行)把整个面板撑得过高,反过来把顶部 safeAreaInset 的
    /// quote / inputBar 挤出可视区。280pt 大致够 3 行 chip 直接显示,
    /// 更多内容内部滚动。
    @ViewBuilder
    private var facetExpansionPanel: some View {
        if !items.isEmpty && facetsExpanded {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 6) {
                    // Phase 77:房间(根)和位置(完整路径)拆成两行,先房间后位置。
                    facetRow(title: "meta.label.room", values: roomFacets,
                             selected: filter.room) { v in
                        if filter.room == v { filter.room = nil } else { filter.room = v }
                    }
                    facetRow(title: "meta.label.location", values: locationFacets,
                             selected: filter.location) { v in
                        if filter.location == v { filter.location = nil } else { filter.location = v }
                    }
                    // Phase 104:借出状态 facet。只在至少一件被借出去时显示。
                    if lentOutCount > 0 {
                        let outLabel = String(localized: "filter.lent.out")
                        let homeLabel = String(localized: "filter.lent.home")
                        let homeCount = items.count - lentOutCount
                        let selectedLabel: String? = {
                            switch filter.lent {
                            case .some(true):  return outLabel
                            case .some(false): return homeLabel
                            default:           return nil
                            }
                        }()
                        facetRow(title: "meta.label.lent",
                                 values: [(outLabel, lentOutCount), (homeLabel, homeCount)],
                                 selected: selectedLabel) { v in
                            if v == outLabel {
                                filter.lent = (filter.lent == true) ? nil : true
                            } else {
                                filter.lent = (filter.lent == false) ? nil : false
                            }
                        }
                    }
                    facetRow(title: "meta.label.source", values: sourceFacets,
                             selected: filter.source) { v in
                        if filter.source == v { filter.source = nil } else { filter.source = v }
                    }
                    facetRow(title: "meta.label.year", values: yearFacets.map { (String($0.key), $0.value) },
                             selected: filter.year.map(String.init)) { v in
                        let y = Int(v)
                        if filter.year == y { filter.year = nil } else { filter.year = y }
                        filter.exactDate = nil; filter.exactDatePrecision = nil
                    }
                    facetRow(title: "meta.label.brand", values: brandFacets,
                             selected: filter.brand) { v in
                        if filter.brand == v { filter.brand = nil } else { filter.brand = v }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 280)
            .background(Color.secondary.opacity(0.10))
            .overlay(alignment: .bottom) { Divider() }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField("filter.search.placeholder",
                      text: Binding(
                        get: { filter.search },
                        set: { filter.search = $0 }
                      ))
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($focused, equals: .search)
            if !filter.search.isEmpty {
                Button { filter.search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        // 比外层 0.12 再深一档,凸出"这是输入框"
        .background(Color.secondary.opacity(0.22), in: .rect(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.35), lineWidth: 0.5)
        )
    }

    /// 一个 facet 行:左边一个标题,后面横排的 chip(用 WrapLayout 换行)。
    /// values 已按数量降序排好;selected 为选中的 value;tap 回调切换。
    ///
    /// title 是 LocalizedStringKey;value 是用户数据/动态字符串(渠道名/年份字符串/品牌名),verbatim 显示。
    /// count 数字用 `Text(verbatim:)` 避免被 catalog 自动收集成 `%lld` 条目。
    @ViewBuilder
    private func facetRow(title: LocalizedStringKey,
                          values: [(String, Int)],
                          selected: String?,
                          tap: @escaping (String) -> Void) -> some View {
        if !values.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                // Phase 110:标签列 36pt → 56pt + 单行 —— 英文 "Location" 在 36pt 下
                // 会折成两行,把整行 chips 顶矮顶高,各 facet 行排布不齐。
                // 56pt 中英文都装得下;lineLimit(1) + 缩字兜底极端 locale。
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 56, alignment: .leading)
                    .padding(.top, 3)
                WrapLayout(spacing: 4, lineSpacing: 3) {
                    ForEach(values, id: \.0) { (value, count) in
                        Button {
                            tap(value)
                        } label: {
                            HStack(spacing: 3) {
                                Text(value).font(.caption2)
                                Text(verbatim: "\(count)")
                                    .font(.caption2)
                                    .foregroundStyle(selected == value ? Color.white.opacity(0.8) : Color.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                selected == value
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.12),
                                in: .capsule
                            )
                            .foregroundStyle(selected == value ? .white : .primary)
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// 精确筛选条件(从详情 chip 点击带来的)显示成一行可删除的胶囊。
    /// 加上"清除全部"按钮(任何 filter 有值时显示)。
    @ViewBuilder
    private var activeExactFilters: some View {
        let exact = exactFilterChips
        if !exact.isEmpty || !filter.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                // Phase 110:跟 facetRow 的标签列同宽(56pt),上下两个区块左缘对齐。
                Text("filter.active.label")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 56, alignment: .leading)
                    .padding(.top, 3)
                WrapLayout(spacing: 4, lineSpacing: 3) {
                    ForEach(exact) { chip in
                        Button {
                            chip.clear()
                        } label: {
                            HStack(spacing: 3) {
                                Text(chip.label).font(.caption2)
                                Image(systemName: "xmark").font(.caption2)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.18), in: .capsule)
                            .foregroundStyle(Color.accentColor)
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                    }
                    if !filter.isEmpty {
                        Button {
                            filter.clearAll()
                        } label: {
                            Text("filter.button.clearAll")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.18), in: .capsule)
                                .fixedSize()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// 一条 active filter chip。
    /// label 用 LocalizedStringKey 类型,带变量字面量(如 `"filter.chip.model \(m)"`)直接传字面量,
    /// SwiftUI 会自动走 catalog interpolation 路径(catalog 里 key 是 `"filter.chip.model %@"`)。
    /// id 用一个简短的类型 tag,各 chip 类型最多一个,不会撞。
    private struct ActiveFilterChip: Identifiable {
        let id: String
        let label: LocalizedStringKey
        let clear: () -> Void
    }

    /// 当前活跃的"精确筛选" → 一行 chip。
    /// 顶部 facet 行(渠道/年份/品牌)已经显示选中态,这里只列 model/color/version/exactDate。
    private var exactFilterChips: [ActiveFilterChip] {
        var out: [ActiveFilterChip] = []
        if let m = filter.model {
            out.append(ActiveFilterChip(
                id: "model",
                label: "filter.chip.model \(m)",
                clear: { filter.model = nil }
            ))
        }
        if let c = filter.color {
            out.append(ActiveFilterChip(
                id: "color",
                label: "filter.chip.color \(c)",
                clear: { filter.color = nil }
            ))
        }
        if let v = filter.version {
            out.append(ActiveFilterChip(
                id: "version",
                label: "filter.chip.version \(v)",
                clear: { filter.version = nil }
            ))
        }
        if let d = filter.exactDate {
            let label = formatPurchaseDate(d, precision: filter.exactDatePrecision) ?? ""
            out.append(ActiveFilterChip(
                id: "purchase",
                label: "filter.chip.purchase \(label)",
                clear: {
                    filter.exactDate = nil; filter.exactDatePrecision = nil
                }
            ))
        }
        return out
    }

    // MARK: - facet 取值(从当前全集派生)

    /// 渠道 facet:统计 distinct purchaseSource 的数量,按数量降序。
    private var sourceFacets: [(String, Int)] {
        var counts: [String: Int] = [:]
        for item in items {
            if let s = item.purchaseSource, !s.isEmpty { counts[s, default: 0] += 1 }
        }
        return counts.sorted { ($0.value, $0.key) > ($1.value, $1.key) }.map { ($0.key, $0.value) }
    }

    private var yearFacets: [(key: Int, value: Int)] {
        var counts: [Int: Int] = [:]
        for item in items {
            guard let d = item.purchaseDate else { continue }
            let y = Calendar.current.component(.year, from: d)
            counts[y, default: 0] += 1
        }
        return counts.sorted { ($0.value, $0.key) > ($1.value, $1.key) }.map { (key: $0.key, value: $0.value) }
    }

    private var brandFacets: [(String, Int)] {
        var counts: [String: Int] = [:]
        for item in items {
            if let b = InputParser.brand(for: item.name) { counts[b, default: 0] += 1 }
        }
        return counts.sorted { ($0.value, $0.key) > ($1.value, $1.key) }.map { ($0.key, $0.value) }
    }

    /// Phase 77:**房间** facet —— 只取每个 item 的顶层(parent==nil)祖先名字。
    /// 同一 item 只贡献 1 次到对应 room 的 count(subtree 整体计数)。
    /// 用户未填位置的 item 不进 room facet。
    private var roomFacets: [(String, Int)] {
        var counts: [String: Int] = [:]
        for item in items {
            guard var cursor = item.location else { continue }
            while let p = cursor.parent { cursor = p }
            counts[cursor.name, default: 0] += 1
        }
        return counts.sorted { ($0.value, $0.key) > ($1.value, $1.key) }.map { ($0.key, $0.value) }
    }

    /// Phase 77 重构:**位置** facet —— 只取**非根** Location,key 是完整路径
    /// ("书房 > 收纳抽屉")。同一 path 多个 item 累加计数。
    /// 顶层根的物品归 roomFacets,这里不再重复统计;**孤儿位置**(用户输位置不写房间,
    /// 顶层就是该位置)目前会被这条规则漏掉 —— 见下面 orphan 处理。
    private var locationFacets: [(String, Int)] {
        var counts: [String: Int] = [:]
        for item in items {
            guard let loc = item.location else { continue }
            if loc.parent == nil {
                // 顶层 + 是 leaf(没子位置) = 用户没说房间的"孤儿位置",
                // 也归 location facet 里,这样它能被筛到。
                // 顶层但有子(典型"房间")→ 跳过,已在 roomFacets。
                guard loc.children.isEmpty else { continue }
            }
            counts[loc.path, default: 0] += 1
        }
        return counts.sorted { ($0.value, $0.key) > ($1.value, $1.key) }.map { ($0.key, $0.value) }
    }

    /// Phase 104:**借出状态** facet —— 只在至少一件被借出时出现。
    /// 两个 chip:"借出去 N" / "在家 M"。点击在 nil ↔ 当前值之间切换。
    private var lentOutCount: Int {
        items.lazy.filter { $0.isLentOut }.count
    }

    // MARK: - 列表 / 空状态

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            ContentUnavailableView {
                Label("empty.list.title", systemImage: "shippingbox")
            } description: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("empty.list.description")
                    Text("empty.list.example1").font(.callout)
                    Text("empty.list.example2").font(.callout)
                    Text("empty.list.example3").font(.callout)
                }
                .foregroundStyle(.secondary)
            }
        } else if filteredItems.isEmpty {
            ContentUnavailableView {
                Label("empty.search.title", systemImage: "magnifyingglass")
            } description: {
                Button("empty.search.button.clearFilters") { filter.clearAll() }
            }
        } else {
            List(selection: $selection) {
                ForEach(filteredItems) { item in
                    row(for: item)
                        .tag(item.persistentModelID)
                        .contextMenu {
                            // 右键所在行已在多选范围里 → 展示批量动作菜单(Finder 风)。
                            // 否则(单选 / 右键到选中外的行)→ 单条菜单。
                            // 注:macOS List 在右键空白行时不会改 selection,所以这判定够稳。
                            if selection.contains(item.persistentModelID) && selection.count > 1 {
                                batchContextMenu()
                            } else {
                                singleContextMenu(for: item)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            // leading swipe 露出置顶按钮 —— 跟系统邮件 app 的"标记"位一致
                            Button {
                                item.isPinned.toggle()
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
                }
                .onDelete(perform: delete)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            #if os(macOS)
            // Phase 18:macOS 习惯 —— 选中后按 Delete / Backspace 触发删除确认。
            // .onDeleteCommand 走 NSResponder.deleteBackward,Backspace 键命中;
            // 同时 .onKeyPress(.deleteForward) 兜住 fn+Delete(forward delete) —— 全键盘 Mac 上的"Delete"键。
            .onDeleteCommand {
                requestDeleteForSelection()
            }
            .onKeyPress(.deleteForward) {
                requestDeleteForSelection()
                return .handled
            }
            #endif
        }
    }

    /// Phase 18:把当前 selection 送进 pendingBulkDelete,弹原有确认 dialog。
    /// 单选 / 多选都走同一条 dialog;按钮文案带 plural,看起来都自然。
    private func requestDeleteForSelection() {
        guard !selection.isEmpty else { return }
        pendingBulkDelete = selection
    }

    /// 单条物品的右键菜单(Finder 风)。
    /// Phase 21 起也包含 3 个快捷动作(设标签 / 设位置 / 设渠道) —— 复用 batch sheet
    /// 但只传入这一件 item,避免每改个标签都得打开完整的「编辑详情…」表单。
    @ViewBuilder
    private func singleContextMenu(for item: Item) -> some View {
        Button {
            item.isPinned.toggle()
            NotificationScheduler.shared.rescheduleIfEnabled()
        } label: {
            Label(item.isPinned ? "action.unpin" : "action.pin",
                  systemImage: item.isPinned ? "pin.slash" : "pin")
        }
        Divider()
        Button {
            editingItem = item
        } label: {
            Label("action.editWithEllipsis", systemImage: "pencil")
        }
        Divider()
        // 跟批量菜单同款 3 个快捷动作,只是 items 数组只有 1 条。
        Button {
            batchEdit = .tags(items: [item])
        } label: {
            Label("batch.menu.setTags", systemImage: "tag")
        }
        Button {
            batchEdit = .location(items: [item])
        } label: {
            Label("batch.menu.setLocation", systemImage: "mappin.and.ellipse")
        }
        Button {
            batchEdit = .source(items: [item])
        } label: {
            Label("batch.menu.setSource", systemImage: "bag")
        }
        // Phase 56:右键 → 关联到…,弹 RelatedItemsPicker 选另一件
        Button {
            relatedPickerSource = item
        } label: {
            Label("related.menu.linkTo", systemImage: "link.badge.plus")
        }
        // Phase 91:借给… / 归还。已借出的物品菜单项变"归还";未借出显示"借给…"
        if item.isLentOut {
            Button {
                let borrower = item.lentTo ?? ""
                item.markReturned()
                // Phase 95:写 EditLog,详情页时间线显示"归还了"
                let entry = EditLog(
                    recordedAt: .now, source: "returned", field: "returned",
                    oldValue: borrower, newValue: nil, item: item
                )
                modelContext.insert(entry)
                flashBatchAck(String(localized: "batch.menu.lent.returned.ack"))
            } label: {
                Label("batch.menu.markReturned", systemImage: "arrow.uturn.backward.circle")
            }
        } else {
            Button {
                lentSheetDraft = ""
                lentSheetItem = item
            } label: {
                Label("batch.menu.lendOut", systemImage: "person.crop.circle.badge.plus")
            }
        }
        Divider()
        // Phase 28:AI 理解 —— 单条复用同一调用路径,items 数组只有 1 条。
        Button {
            runAIUnderstand(items: [item])
        } label: {
            Label("action.aiUnderstand", systemImage: "sparkles")
        }
        .disabled(!AISettings.hasActiveKey)
        Divider()
        // context menu 的删除走确认对话框,避免误右键 → 误点
        Button(role: .destructive) {
            pendingDelete = item
        } label: {
            Label("action.delete", systemImage: "trash")
        }
    }

    /// 工具栏「批量编辑」下拉的内容(Phase 35 起抽出来,跟右键 batch menu 内容一致)。
    /// 抽成单独 ViewBuilder 避免主 body 修饰符链 type-check 超时。
    @ViewBuilder
    private var toolbarBatchMenu: some View {
        let snapshot = selectedItemsSnapshot()
        Button {
            batchEdit = .tags(items: snapshot)
        } label: {
            Label("batch.menu.setTags", systemImage: "tag")
        }
        Button {
            batchEdit = .location(items: snapshot)
        } label: {
            Label("batch.menu.setLocation", systemImage: "mappin.and.ellipse")
        }
        Button {
            batchEdit = .source(items: snapshot)
        } label: {
            Label("batch.menu.setSource", systemImage: "bag")
        }
        Divider()
        Button(action: batchMarkSeen) {
            Label("batch.menu.markSeen", systemImage: "checkmark.circle")
        }
        Button(action: batchMarkLost) {
            Label("batch.menu.markLost", systemImage: "questionmark.circle")
        }
        Divider()
        Button {
            runAIUnderstand(items: snapshot)
        } label: {
            Label("action.aiUnderstand", systemImage: "sparkles")
        }
        .disabled(!AISettings.hasActiveKey)
    }

    /// 多选时的右键菜单(Phase 12):批量加标签 / 改位置 / 改渠道 / 标记见过 / 找不到 / 删除。
    /// 跟 toolbar 上的 "批量编辑" Menu 内容一致 —— 重复展示,降低用户操作距离。
    @ViewBuilder
    private func batchContextMenu() -> some View {
        let snapshot = selectedItemsSnapshot()
        Button {
            batchEdit = .tags(items: snapshot)
        } label: {
            Label("batch.menu.setTags", systemImage: "tag")
        }
        Button {
            batchEdit = .location(items: snapshot)
        } label: {
            Label("batch.menu.setLocation", systemImage: "mappin.and.ellipse")
        }
        Button {
            batchEdit = .source(items: snapshot)
        } label: {
            Label("batch.menu.setSource", systemImage: "bag")
        }
        Divider()
        Button(action: batchMarkSeen) {
            Label("batch.menu.markSeen", systemImage: "checkmark.circle")
        }
        Button(action: batchMarkLost) {
            Label("batch.menu.markLost", systemImage: "questionmark.circle")
        }
        Divider()
        // Phase 28:AI 批量理解 —— 顺序遍历选中项,每条调一次 AI。
        Button {
            runAIUnderstand(items: snapshot)
        } label: {
            Label("action.aiUnderstand", systemImage: "sparkles")
        }
        .disabled(!AISettings.hasActiveKey)
        Divider()
        Button(role: .destructive) {
            pendingBulkDelete = selection
        } label: {
            Label("bulk.delete.label \(selection.count)", systemImage: "trash")
        }
    }

    private func row(for item: Item) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // 有照片的物品左边放个 40pt 缩略图,扫一眼看得到
            if let data = item.photoData, let img = Image(data: data) {
                img
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                    )
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    // 置顶 indicator —— 列表上一眼能看出哪些是重要物品
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    // 标签色点 —— 详情里每个标签有色 chip,列表行 name 前也对应给个 7pt 小圆点,
                    // 一眼能扫到这件物品属于哪几类(纯展示,不点击)。
                    if !item.tags.isEmpty {
                        HStack(spacing: 2) {
                            ForEach(item.tags) { tag in
                                Circle()
                                    .fill(Color(tagHex: tag.colorHex))
                                    .frame(width: 7, height: 7)
                            }
                        }
                    }
                    Text(item.name)
                        .font(.headline)
                    Spacer(minLength: 4)
                    // Phase 36/38:右侧 AI 状态指示器(行内 inline,不打断列表)。
                    aiStatusIndicator(for: item)
                }
                if let path = item.location?.path {
                    Label(path, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Phase 91:已借出的物品在 location 下方加一行紫色 lent 提示
                if let lentTo = item.lentTo {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill.checkmark")
                            .font(.caption2)
                        Text("row.lent.label \(lentTo)")
                            .font(.caption)
                    }
                    .foregroundStyle(.purple)
                }
                rowMetaChips(item)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())  // 让整行都可点(SwiftUI selection 行为)
    }

    /// Phase 36/38:每行右侧的 AI 状态小字 + emoji。
    /// 处理中:✨ + spinner + "正在用 AI 理解…"(灰色)
    /// 刚完成(4 秒窗口):✓ + 绿色 "AI 已理解"
    /// 不在两个集合里则啥都不渲染。
    @ViewBuilder
    private func aiStatusIndicator(for item: Item) -> some View {
        let id = item.persistentModelID
        if aiProcessingIDs.contains(id) {
            HStack(spacing: 3) {
                ProgressView()
                    .controlSize(.mini)
                Text("row.ai.processing")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if aiCompletedIDs.contains(id) {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text("row.ai.completed")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
            .transition(.opacity)
        }
    }

    /// 列表行的元数据小标签:型号 / 版本 / 颜色 / 渠道 / 购买日期(都是有值才显示)。
    /// 比详情里那排再小一号 —— 列表是"扫一眼",不抢眼。
    ///
    /// labelKey 存 catalog key 字符串;显示时 `Text(LocalizedStringKey(...))` 显式走 catalog。
    @ViewBuilder
    private func rowMetaChips(_ item: Item) -> some View {
        let chips: [(labelKey: String, value: String)] = {
            var out: [(String, String)] = []
            // Phase 45:品牌 chip。InputParser.brand(for:) 现算,不入库,与 facet 过滤一致。
            // 排第一位 —— 它最能帮用户一眼定位"这是哪家的东西"。
            if let b = InputParser.brand(for: item.name) { out.append(("meta.label.brand", b)) }
            if let m = item.model,   !m.isEmpty { out.append(("meta.label.model", m)) }
            if let v = item.version, !v.isEmpty { out.append(("meta.label.version", v)) }
            if let c = item.color,   !c.isEmpty { out.append(("meta.label.color", c)) }
            if let s = item.purchaseSource, !s.isEmpty { out.append(("meta.label.source", s)) }
            if let label = formatPurchaseDate(item.purchaseDate, precision: item.purchaseDatePrecision) {
                out.append(("meta.label.purchase", label))
            }
            return out
        }()
        if !chips.isEmpty {
            // WrapLayout 真正的 flow 排版:每个 chip 锁住自身宽度,挤不下就整 chip 换行,
            // 不会出现 "pixel/buds/pro" 这种字符级折断。
            WrapLayout(spacing: 4, lineSpacing: 3) {
                ForEach(chips, id: \.0) { (labelKey, value) in
                    HStack(spacing: 2) {
                        Text(LocalizedStringKey(labelKey)).font(.caption2).foregroundStyle(.tertiary)
                        Text(value).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.10), in: .capsule)
                    .fixedSize()
                }
            }
        }
    }

    // MARK: - 录入提交 + 重复检测

    private func commit() {
        //       InputParser 当前只懂中文;英文输入暂时整句落到 name 字段,不抽元数据。
        let list = InputParser.parseMultiple(draft)
        guard !list.isEmpty else { return }

        // Phase 43:每条新 item 都存一份"用户写下的整段原文"。多条共用同一份 raw,
        // 这样 AI 后面理解某一条时,能看到当时的整段上下文(其它条的位置参考、别称等)。
        let rawForBatch = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        // 单条输入:先看是不是对已有物品的字段更新意图(可在设置里关掉)
        if list.count == 1, updateIntentDetectionEnabled,
           let intent = InputParser.matchUpdateIntent(draft, candidateNames: items.map(\.name)),
           let target = items.first(where: { $0.name == intent.matchedName }) {
            pendingUpdate = PendingUpdate(
                item: target, changes: intent.changes, summary: intent.summary
            )
            return
        }

        // 单条:走重复检测流程(可在设置里关掉)
        if list.count == 1 {
            let parsed = list[0]
            if dupDetectionEnabled, let dup = findDuplicateMatch(name: parsed.name) {
                pendingDuplicate = PendingDuplicate(
                    existing: dup,
                    newName: parsed.name,
                    newPath: parsed.locationPath,
                    newDate: parsed.purchaseDate,
                    newDatePrecision: parsed.purchaseDatePrecision,
                    newSource: parsed.purchaseSource,
                    newModel: parsed.model,
                    newColor: parsed.color,
                    newVersion: parsed.version
                )
                return  // 等用户决定,不清 draft
            }
            addNewItem(parsed, rawInput: rawForBatch)
            return
        }

        // 多条:批量入库,跳过重复检测(批量录入一般是初次整理,逐条弹框反人类)
        for parsed in list {
            addNewItem(parsed, rawInput: rawForBatch)
        }
        // addNewItem 里会清 draft 并对焦,这里多次调用也无所谓最终都会清空
    }

    /// 同名优先;否则较短一方至少 2 字、且较长包含较短 → 算潜在同一件东西。
    private func findDuplicateMatch(name: String) -> Item? {
        if let exact = items.first(where: { $0.name == name }) { return exact }
        return items.first { existing in
            let a = existing.name, b = name
            guard a != b else { return false }
            let shorter = a.count < b.count ? a : b
            let longer  = a.count < b.count ? b : a
            guard shorter.count >= 2 else { return false }
            return longer.contains(shorter)
        }
    }

    private func addNewItem(_ parsed: InputParser.Parsed, rawInput: String? = nil) {
        // Phase 17:先消歧定位置 —— 单段 path("抽屉第一层")若在库里多处都有同名叶子,
        // 让用户选,而不是直接建一个孤立顶层。
        switch Location.resolve(path: parsed.locationPath, in: modelContext) {
        case .ambiguous(let candidates, let leaf):
            pendingAmbiguousLocation = PendingAmbiguousLocation(
                parsed: parsed, candidates: candidates, originalLeaf: leaf, rawInput: rawInput
            )
            // 不写库;等用户在 confirmationDialog 里点完一个选项再走 finalizeNewItem。
            return
        case .useExisting(let loc):
            finalizeNewItem(parsed, location: loc, rawInput: rawInput)
        case .create(let path):
            let loc = Location.ensure(path: path, in: modelContext)
            finalizeNewItem(parsed, location: loc, rawInput: rawInput)
        }
    }

    /// 处理用户的歧义弹窗选择 —— 把暂存的 Parsed 真正落库。
    private func resolveAmbiguousLocation(_ ctx: PendingAmbiguousLocation, choice: AmbiguousChoice) {
        let loc: Location?
        switch choice {
        case .existing(let chosen):
            loc = chosen
        case .newTopLevel:
            loc = Location.ensure(path: ctx.parsed.locationPath, in: modelContext)
        }
        finalizeNewItem(ctx.parsed, location: loc, rawInput: ctx.rawInput)
        pendingAmbiguousLocation = nil
    }

    /// 真正落库的尾段(Phase 17 拆出来):写 Item / Log / 自动标签 / 清 draft。
    /// addNewItem 决定 location 后调它;消歧弹窗的回调也走它。
    /// Phase 43:rawInput 是用户当次"记一条"里写的整段原文,存到每条新 item 上。
    private func finalizeNewItem(_ parsed: InputParser.Parsed, location loc: Location?, rawInput: String? = nil) {
        let item = Item(name: parsed.name, location: loc)
        // 自然语言里抽出来的元数据一并落库
        item.purchaseDate = parsed.purchaseDate
        item.purchaseDatePrecision = parsed.purchaseDatePrecision
        item.purchaseSource = parsed.purchaseSource
        item.model = parsed.model
        item.color = parsed.color
        item.version = parsed.version
        if let r = rawInput?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty {
            item.rawInput = r
        }
        modelContext.insert(item)
        // 写入首条历史 log
        let log = LocationLog(recordedAt: .now, location: loc, item: item)
        modelContext.insert(log)
        // Phase 14:按物品名建议一个预设 tag 自动挂上,提供撤销。
        applyAutoTagSuggestion(to: item)
        // Phase 36:用户勾了"使用 AI 理解" → 后台异步调 AI 重新拆字段。
        // 立即清 draft + focus 不变,用户能继续录入下一条 —— AI 在后台跑。
        if useAIOnInput && AISettings.hasActiveKey {
            runAIUnderstand(items: [item])
        }
        draft = ""
        focused = .input
    }

    /// Phase 22:升级后跑一次,把没挂任何 tag 的存量物品按物品名匹一遍预设标签。
    /// 用 @AppStorage flag 保证只跑一次。受 autoTagSuggestEnabled 控制 —— 关掉自动建议
    /// 的用户也不希望被迁移惊到。
    private func runAutoTagMigrationIfNeeded() {
        guard !autoTagMigrationDone else { return }
        guard autoTagSuggestEnabled else {
            // 用户禁用了自动建议:不跑迁移,但也置 flag 防止以后开启又来一遍。
            autoTagMigrationDone = true
            return
        }
        var touched = 0
        for item in items where item.tags.isEmpty {
            guard let hex = InputParser.suggestTagColorHex(forName: item.name) else { continue }
            let target = hex.lowercased()
            let candidate = allTags
                .filter { $0.colorHex.lowercased() == target }
                .sorted(by: { $0.createdAt < $1.createdAt })
                .first
            guard let tag = candidate else { continue }
            item.tags.append(tag)
            touched += 1
        }
        autoTagMigrationDone = true
        if touched > 0 {
            // 用底部 toast 提示用户有变化(没"撤销"按钮 —— 一条条人工 ItemEditView 取消即可)。
            flashBatchAck(String(localized: "autoTag.migration.ack \(touched)"))
        }
    }

    /// Phase 14 自动建议挂载逻辑 —— 静默 no-op 如果:开关关 / 没匹中关键词 / 找不到同色 tag。
    /// 命中后展示一个带"撤销"按钮的 toast,~3 秒后自动消失。
    private func applyAutoTagSuggestion(to item: Item) {
        guard autoTagSuggestEnabled else { return }
        guard let hex = InputParser.suggestTagColorHex(forName: item.name) else { return }
        // 按 colorHex 找 tag(大小写都标准化)。同色多 tag 时取最早 seed 的。
        let target = hex.lowercased()
        let candidate = allTags
            .filter { $0.colorHex.lowercased() == target }
            .sorted(by: { $0.createdAt < $1.createdAt })
            .first
        guard let tag = candidate else { return }
        // 已挂过这个 tag 就不再重复挂(理论上新建 item 不会,但保险)
        if item.tags.contains(where: { $0.persistentModelID == tag.persistentModelID }) { return }
        item.tags.append(tag)
        pendingAutoTagUndo = (item, tag)
        // toast 文案在 view 层渲染(看 pendingAutoTagUndo 是否非 nil),
        // 这里只起一个超时,3 秒后清掉撤销窗口。
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            // 只有"这次"的撤销目标还在时才清掉 —— 下次录入又挂时已被覆盖,不要误清。
            if let current = pendingAutoTagUndo,
               current.item.persistentModelID == item.persistentModelID,
               current.tag.persistentModelID == tag.persistentModelID {
                pendingAutoTagUndo = nil
            }
        }
    }

    /// 用户点了 toast 上的"撤销" —— 把那个 tag 从 item 移除,清状态。
    private func undoAutoTag() {
        guard let pair = pendingAutoTagUndo else { return }
        pair.item.tags.removeAll { $0.persistentModelID == pair.tag.persistentModelID }
        pendingAutoTagUndo = nil
    }

    private func applyUpdate(_ pending: PendingUpdate) {
        let i = pending.item
        let c = pending.changes
        // Phase 39:diff 写编辑历史
        let snap = ItemFieldSnapshot(i)
        if let v = c.model          { i.model = v }
        if let v = c.version        { i.version = v }
        if let v = c.color          { i.color = v }
        if let v = c.notes          { i.notes = v }
        if let v = c.purchaseDate   {
            i.purchaseDate = v
            i.purchaseDatePrecision = c.purchaseDatePrecision  // 跟着一起写
        }
        if let v = c.purchaseSource { i.purchaseSource = v }
        i.updatedAt = .now
        snap.recordEdits(against: i, source: "update_intent", in: modelContext)
        draft = ""
        pendingUpdate = nil
        focused = .input
    }

    /// 用户在 update alert 里选了"还是新建一条" —— 不假装是更新,直接把原 draft 走正常 parse 流程。
    /// 这一般会落到一个奇怪的物品名(整句),用户后续可以编辑。
    private func createFromRawDraft() {
        let list = InputParser.parseMultiple(draft)
        if list.isEmpty {
            let raw = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty {
                addNewItem(InputParser.Parsed(name: raw, locationPath: []))
            }
        } else {
            for p in list { addNewItem(p) }
        }
        pendingUpdate = nil
    }

    private func resolveDuplicate(_ dup: PendingDuplicate, asUpdate: Bool) {
        if asUpdate {
            // 关键:只有新句子真的给了位置时才动 location,否则把已有位置清空就太坑了。
            if !dup.newPath.isEmpty {
                let newLoc = Location.ensure(path: dup.newPath, in: modelContext)
                dup.existing.location = newLoc
                dup.existing.lastSeenAt = .now
                let log = LocationLog(recordedAt: .now, location: newLoc, item: dup.existing)
                modelContext.insert(log)
            }
            dup.existing.updatedAt = .now
            // 若用户新写的名字更长,大概率是补充了限定词("金属眼镜"),顺手更名
            if dup.newName.count > dup.existing.name.count {
                dup.existing.name = dup.newName
            }
            // 新写法里如果带了日期/渠道/型号/颜色 → 补到 existing(已填的不覆盖)
            if dup.existing.purchaseDate == nil {
                dup.existing.purchaseDate = dup.newDate
                dup.existing.purchaseDatePrecision = dup.newDatePrecision
            }
            if dup.existing.purchaseSource == nil { dup.existing.purchaseSource = dup.newSource }
            if dup.existing.model          == nil { dup.existing.model          = dup.newModel }
            if dup.existing.color          == nil { dup.existing.color          = dup.newColor }
            if dup.existing.version        == nil { dup.existing.version        = dup.newVersion }
        } else {
            let parsed = InputParser.Parsed(
                name: dup.newName, locationPath: dup.newPath,
                purchaseDate: dup.newDate, purchaseDatePrecision: dup.newDatePrecision,
                purchaseSource: dup.newSource, model: dup.newModel,
                color: dup.newColor, version: dup.newVersion
            )
            addNewItem(parsed)
        }
        draft = ""
        pendingDuplicate = nil
        focused = .input
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            // 软删除 —— swipe / onDelete 都进回收站,不直接物理删
            items[index].markDeleted()
        }
    }

    // MARK: - Phase 12 批量操作

    /// 把当前 selection 解到具体的 Item 列表 —— 给 batch 菜单 / sheet 当快照用。
    /// 一旦点了菜单就锁定这批 item,后续 selection 怎么变都不影响 sheet 内的目标。
    private func selectedItemsSnapshot() -> [Item] {
        items.filter { selection.contains($0.persistentModelID) }
    }

    /// 批量标记"最近见过":跟单条 detail 里"他还在原位"等价 —— 不动 location,
    /// 但把 lastSeenAt 推到现在,并为每件物品写一条历史 log(用当前 location)。
    private func batchMarkSeen() {
        let targets = selectedItemsSnapshot()
        guard !targets.isEmpty else { return }
        for item in targets {
            item.lastSeenAt = .now
            item.updatedAt = .now
            item.lastActionType = "stillThere"
            let log = LocationLog(recordedAt: .now, location: item.location, item: item)
            modelContext.insert(log)
        }
        NotificationScheduler.shared.rescheduleIfEnabled()
        flashBatchAck(String(localized: "batch.ack.markedSeen \(targets.count)"))
    }

    /// 批量标记"找不到了":清掉 location,但保留全部历史(写一条 location=nil 的 log)。
    /// 跟单条 detail 里"不知道在哪"按钮等价。
    private func batchMarkLost() {
        let targets = selectedItemsSnapshot()
        guard !targets.isEmpty else { return }
        for item in targets {
            item.location = nil
            item.lastSeenAt = .now
            item.updatedAt = .now
            item.lastActionType = "unknown"
            let log = LocationLog(recordedAt: .now, location: nil, item: item)
            modelContext.insert(log)
        }
        flashBatchAck(String(localized: "batch.ack.markedLost \(targets.count)"))
    }

    // MARK: - Phase 28 → Phase 38:AI 理解 trigger(非阻塞)

    /// Phase 73:给 AI payload 准备的"用户已有位置列表"。
    /// 排序:按"挂在该 location 下的 item 最新 lastSeenAt"降序 —— 最近用过的位置排前面。
    /// 取前 50 个(AIPayload.userMessage 也会再 cap 一次,这里多一层防御)。
    /// 输出形如 ["书房 > 抽屉", "客厅 > 茶几", ...] —— path 字符串就是 location.path。
    private func locationsSortedByRecency() -> [String] {
        // 用 Item.location → Location 的关系,聚合每个 location 的最新 lastSeenAt
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
        let paths = sorted.compactMap { locByID[$0.key]?.path }
        return Array(paths.prefix(50))
    }

    /// 单选 / 多选 / 录入时 useAIOnInput 都走这个 —— 顺序遍历 items,每件调一次 AI 重新解析。
    /// **不**弹 sheet,**不**锁 UI;状态通过 aiProcessingIDs / aiCompletedIDs 在每行内嵌显示。
    /// 顺序而非并发 —— 避免触发 API rate limit;用户可继续录入下一条。
    private func runAIUnderstand(items targets: [Item]) {
        guard !targets.isEmpty else { return }
        guard let client = AISettings.currentClient() else {
            flashBatchAck(String(localized: "ai.error.missingKey"))
            return
        }
        // 立即把所有目标标记为"处理中" —— UI 行立刻显示 spinner。
        for item in targets {
            aiProcessingIDs.insert(item.persistentModelID)
        }

        let snapshot = targets
        let ctx = modelContext
        // Phase 42:把当前所有 tag name 快照一份传给 AI;AI 只能从中挑一个或选"其他"。
        let tagNames = allTags.map(\.name)
        // Phase 73:把当前所有 Location.path 快照传给 AI,用于 typo 容错 + 优先用已存在写法。
        // 按"最近用过"排序 —— item 排序键是 updatedAt,location 没有自己的时间戳,
        // 用挂在它下面的最新一件 item.lastSeenAt 作为代理。这样列表前面是更可能再用的位置。
        let locPaths = locationsSortedByRecency()

        Task {
            for item in snapshot {
                let id = item.persistentModelID
                do {
                    let result = try await client.understand(item: item, availableTags: tagNames, availableLocations: locPaths)
                    await MainActor.run {
                        applyAIResult(result, to: item, in: ctx)
                        aiProcessingIDs.remove(id)
                        aiCompletedIDs.insert(id)
                    }
                    // 4 秒后清掉"✓ 已完成"标记,行恢复正常。
                    Task {
                        try? await Task.sleep(for: .seconds(4))
                        await MainActor.run { _ = aiCompletedIDs.remove(id) }
                    }
                } catch {
                    // 失败:从"处理中"移除,不写"已完成",静默 print。
                    // 用户可以右键再点一次重试。多选时不刷屏。
                    print("AI understand failed for \(item.name): \(error)")
                    await MainActor.run { _ = aiProcessingIDs.remove(id) }
                }
            }
        }
    }

    /// 给底部状态栏 / 工具栏附近一个临时 toast,~2.5 秒后自动消失。
    private func flashBatchAck(_ msg: String) {
        batchAck = msg
        // 主线程延迟清空 —— 多次连续 toast 时,最后那条覆盖前一条,这是预期行为。
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if batchAck == msg { batchAck = nil }
        }
    }

    // MARK: - Bindings

    /// 只在恰好选中 1 条时展示详情;多选 / 无选都返回 nil(inspector 关闭)。
    private var selectedItem: Item? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return items.first { $0.persistentModelID == id }
    }

    /// Inspector 始终开 —— 没选 / 多选时显示 placeholder,选 1 条时显示详情。
    /// 用户希望"一眼就能看到详情",所以不再跟 selection 联动开关。
    private var inspectorBinding: Binding<Bool> {
        .constant(true)
    }

    private var bulkDeleteBinding: Binding<Bool> {
        Binding(
            get: { !pendingBulkDelete.isEmpty },
            set: { if !$0 { pendingBulkDelete = [] } }
        )
    }

    private var duplicateAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDuplicate != nil },
            set: { if !$0 { pendingDuplicate = nil } }
        )
    }

    private var updateAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingUpdate != nil },
            set: { if !$0 { pendingUpdate = nil } }
        )
    }

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }
}

// Phase 119:BatchEditTarget 挪到 Shared/RecordFlow.swift —— iOS 多选批量编辑复用。

// Phase 111:PendingAmbiguousLocation / PendingUpdate / PendingDuplicate
// 挪到 Shared/RecordFlow.swift —— iOS 的"记一条"页复用同一套录入决策数据结构。

// MARK: - 回收站

/// 显示已 soft delete 的物品。右键 / context menu 还原或彻底删除;toolbar 一键清空。
/// 平时主列表 / 搜索 / facet 都过滤掉 isDeleted=true 的,这里是它们唯一可见的入口。
struct TrashView: View {
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
                            TrashRow(item: item)
                                .contextMenu {
                                    Button {
                                        item.restore()
                                    } label: {
                                        Label("trash.action.restore", systemImage: "arrow.uturn.backward")
                                    }
                                    Divider()
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        showingEmptyConfirm = true
                    } label: {
                        Label("trash.action.empty", systemImage: "trash.slash")
                    }
                    .disabled(deletedItems.isEmpty)
                }
            }
            .confirmationDialog(
                "trash.action.empty.confirm.title",
                isPresented: $showingEmptyConfirm
            ) {
                Button("trash.action.empty.confirm.button", role: .destructive) {
                    for item in deletedItems {
                        modelContext.delete(item)
                    }
                }
                Button("action.cancel", role: .cancel) {}
            } message: {
                Text("trash.action.empty.confirm.message")
            }
        }
        .frame(minWidth: 460, idealWidth: 560, minHeight: 360, idealHeight: 480)
    }
}

/// 回收站单行 —— 显示原名、被删之前的位置、删除时间(相对)。
private struct TrashRow: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.headline)
                .strikethrough(color: .secondary)
            HStack(spacing: 8) {
                if let path = item.location?.path {
                    Label(path, systemImage: "mappin.and.ellipse")
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
        .padding(.vertical, 2)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Item.self, Location.self], inMemory: true)
}
