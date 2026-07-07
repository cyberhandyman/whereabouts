import SwiftUI
import SwiftData

// Phase 111:PlatformImage / Image(data:) / ImageHelpers / WrapLayout
// 挪到 Shared/SharedUI.swift —— iOS target 也要用,这个文件只进 macOS target。

/// 列表点行后右侧 inspector 显示。
/// 主要承担:展示物品当前位置 + "用过吗?" 三选(放回/位置变了/不管)+ 删除。
struct ItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var item: Item

    /// "位置变了"按钮按下后,展开行内编辑。
    @State private var editingLocation = false
    @State private var locationDraft = ""
    @FocusState private var locationFocused: Bool

    /// 操作完一次提醒后的轻量反馈("✓ 已记下"短暂出现)。
    @State private var ackText: String?

    /// Phase 37:由 ContentView 注入的 AI 理解触发器。nil = 不显示按钮。
    /// 同时传入 isAIProcessing 给按钮显示 loading 状态。
    var onAIUnderstand: (() -> Void)? = nil
    var isAIProcessing: Bool = false

    /// Phase 55:点击关联项目超链接时的跳转回调。ContentView 注入,
    /// 实现是把 selection 改成目标 item 的 ID,inspector 自动重渲。
    /// nil = 关联项目以普通文字渲染(不点击),用于预览 / iOS 等没有 inspector 的场合。
    var onSelectItem: ((PersistentIdentifier) -> Void)? = nil

    /// 编辑 sheet 的开关。
    @State private var showingEditSheet = false

    /// Phase 54:挑选另一件物品来关联的 sheet。
    @State private var showingRelatedPicker = false

    /// 点缩略图弹大图预览(quicklook 风格)。
    @State private var showingPhotoZoom = false

    /// 底部"删除"按钮按下后的确认弹窗。
    @State private var showingDeleteConfirm = false

    /// 借出去 sheet 状态(Phase 91)
    @State private var showingLentSheet = false
    @State private var lentDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                photoBanner
                Divider()
                usedSection
                Divider()
                historySection
                Divider()
                relatedSection
                Divider()
                metaSection
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("detail.button.delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(20)
        }
        .frame(minWidth: 300)
        .sheet(isPresented: $showingEditSheet) {
            ItemEditView(item: item)
        }
        .sheet(isPresented: $showingRelatedPicker) {
            RelatedItemsPicker(source: item) { _ in /* 成功提示交给 ContentView toast 不重复 */ }
        }
        .sheet(isPresented: $showingPhotoZoom) {
            if let data = item.photoData, let img = Image(data: data) {
                PhotoZoomView(image: img) { showingPhotoZoom = false }
            }
        }
        .sheet(isPresented: $showingLentSheet) {
            LentOutSheet(item: item, draft: $lentDraft) { saved in
                if saved {
                    // Phase 95:借出事件写 EditLog,详情时间线显示"借给 XX"
                    let entry = EditLog(
                        recordedAt: .now, source: "lent_out", field: "lent",
                        oldValue: nil, newValue: item.lentTo, item: item
                    )
                    modelContext.insert(entry)
                    ack(String(localized: "detail.lent.ack.lentOut \(item.lentTo ?? "")"))
                }
                showingLentSheet = false
            }
        }
        // 删除前的确认。这里是 soft delete:item 进回收站,可还原。
        // ContentView 的 @Query 过滤掉 isDeleted=true → 主列表立刻消失 → inspector 自动关。
        .confirmationDialog(
            "delete.alert.title",
            isPresented: $showingDeleteConfirm
        ) {
            Button("action.delete", role: .destructive) {
                item.markDeleted()
            }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("delete.alert.message \(item.name)")
        }
    }

    /// 详情页大图带:有照片就显示,点击放大。
    /// 缩略图自然限定高度(240pt),长图会按比例缩放。
    @ViewBuilder
    private var photoBanner: some View {
        if let data = item.photoData, let img = Image(data: data) {
            Button {
                showingPhotoZoom = true
            } label: {
                img
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help("detail.photo.tooltip")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name)
                    .font(.title2.bold())
                Spacer()
                // Phase 49:旧 "理解"(本地 InputParser 再解析)按钮已删除 —— AI 理解能完成它能做的事且更准。
                // 处理中显示 spinner;无 API key 时 disabled。
                // 用 .fixedSize 锁宽避免"用AI理解"被腰斩成两行。
                if let onAIUnderstand {
                    Button(action: onAIUnderstand) {
                        if isAIProcessing {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.mini)
                                Text("action.aiUnderstand")
                                    .lineLimit(1)
                            }
                        } else {
                            Label("action.aiUnderstand", systemImage: "wand.and.stars")
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.borderless)
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(isAIProcessing || !AISettings.hasActiveKey)
                    .help(AISettings.hasActiveKey
                          ? String(localized: "action.aiUnderstand")
                          : String(localized: "action.aiUnderstand.disabledHint"))
                }
                Button {
                    showingEditSheet = true
                } label: {
                    Label("action.edit", systemImage: "pencil")
                        .lineLimit(1)
                }
                .buttonStyle(.borderless)
                .fixedSize(horizontal: true, vertical: false)
                .help("detail.button.edit.tooltip")
            }
            if let path = item.location?.path {
                // path 是用户数据(场所名),用 String overload verbatim 显示,不查 catalog。
                Label(path, systemImage: "mappin.and.ellipse")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Label("location.unspecified", systemImage: "questionmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            // Phase 91:借出状态徽章。橙色 capsule + 行内"归还"按钮。
            lentBadge
            // 已填的可选元数据小标签
            attributesStrip
            // 用户挂的标签(Finder 风格,颜色点 + 名字)
            tagsStrip
        }
    }

    /// Phase 91:借出去时,location 行下方显示"已借给 XX (N 天前)" + "归还"按钮。
    /// 没借出 → 不渲染。
    @ViewBuilder
    private var lentBadge: some View {
        if let lentTo = item.lentTo {
            HStack(spacing: 6) {
                Image(systemName: "person.fill.checkmark")
                    .font(.caption)
                if let lentAt = item.lentAt {
                    Text("detail.lent.badge \(lentTo) \(lentAt.formatted(.relative(presentation: .named)))")
                        .font(.callout)
                } else {
                    Text("detail.lent.badge.noDate \(lentTo)")
                        .font(.callout)
                }
                Button {
                    let borrower = item.lentTo ?? ""
                    item.markReturned()
                    // Phase 95:归还事件写 EditLog,详情时间线显示"归还了" + 谁还的
                    let entry = EditLog(
                        recordedAt: .now, source: "returned", field: "returned",
                        oldValue: borrower, newValue: nil, item: item
                    )
                    modelContext.insert(entry)
                    ack(String(localized: "detail.lent.ack.returned"))
                } label: {
                    Label("detail.lent.button.return", systemImage: "arrow.uturn.backward.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .tint(.orange)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.15), in: .capsule)
            .foregroundStyle(.orange)
        }
    }

    /// 详情页展示物品挂的所有标签。点击 chip 不做事(纯展示,跟 attributesStrip 一致策略 —— 避免 dismiss 时序 crash)。
    @ViewBuilder
    private var tagsStrip: some View {
        if !item.tags.isEmpty {
            WrapLayout(spacing: 6, lineSpacing: 4) {
                ForEach(item.tags) { tag in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(tagHex: tag.colorHex))
                            .frame(width: 8, height: 8)
                        Text(tag.name)
                            .font(.caption2)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.08), in: .capsule)
                    .fixedSize()
                }
            }
            .padding(.top, 2)
        }
    }

    /// 一排小 chip 显示型号/版本/颜色/渠道/购买日期(只显示非空的)。
    ///
    /// 历史上每个 chip 是 Button —— 点击设置对应 filter + dismiss inspector,跳转回列表。
    /// 但 SwiftUI 在 inspector dismiss 动画期间还会 redraw 这棵已半 detached 的子树,
    /// 此时 `.environment(filter)` 的 closure 已不再 evaluate,`@Environment(FilterModel.self)`
    /// 取不到值 → fatalError 闪退。
    ///
    /// 修复方案 = 把 chip 改成**纯展示**:不再 Button、不再写 filter、不再 dismiss。
    /// 用户想按某个值筛选时,直接用顶部 facet 行(渠道/年份/品牌)或搜索框即可。
    @ViewBuilder
    private var attributesStrip: some View {
        let chips: [(labelKey: String, value: String)] = {
            var out: [(String, String)] = []
            // Phase 45:品牌 chip,跟列表行保持一致。
            if let b = InputParser.brand(for: item.name) {
                out.append(("meta.label.brand", b))
            }
            if let m = item.model, !m.isEmpty {
                out.append(("meta.label.model", m))
            }
            if let v = item.version, !v.isEmpty {
                out.append(("meta.label.version", v))
            }
            if let c = item.color, !c.isEmpty {
                out.append(("meta.label.color", c))
            }
            if let s = item.purchaseSource, !s.isEmpty {
                out.append(("meta.label.source", s))
            }
            if let label = formatPurchaseDate(item.purchaseDate, precision: item.purchaseDatePrecision) {
                out.append(("meta.label.purchase", label))
            }
            return out
        }()
        if !chips.isEmpty {
            WrapLayout(spacing: 6, lineSpacing: 4) {
                ForEach(0..<chips.count, id: \.self) { i in
                    HStack(spacing: 3) {
                        Text(LocalizedStringKey(chips[i].labelKey)).font(.caption2).foregroundStyle(.secondary)
                        Text(chips[i].value).font(.caption2)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: .capsule)
                    .fixedSize()
                }
            }
            .padding(.top, 2)
        }
    }

    // MARK: - "用过这个吗?"

    private var usedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hand.tap")
                Text("detail.used.title").font(.headline)
            }
            .foregroundStyle(.primary)

            Text("detail.used.description")
                .font(.caption)
                .foregroundStyle(.secondary)

            // 4 个按钮颜色从积极到警示渐进:mint → blue → orange → red。
            // 上次按过的那个 → .borderedProminent(实色填充);其他 → .bordered(浅色描边)。
            // 强调态按钮下方有一行 caption:"X 时间前 · 动作名"。

            actionButton(
                titleKey: "detail.used.button.stillThere",
                systemImage: "eye.fill",
                tint: .mint,
                actionType: "stillThere"
            ) {
                confirmStillHere(actionType: "stillThere")
            }

            actionButton(
                titleKey: "detail.used.button.putBack",
                systemImage: "checkmark.circle.fill",
                tint: .blue,
                actionType: "putBack"
            ) {
                confirmStillHere(actionType: "putBack")
            }

            // "位置变了…" 用 emphasized 颜色的特殊处理:它是 toggle,真正的 "moved"
            // 动作在 saveNewLocation() 里;这里点开 / 关闭不改 lastActionType。
            actionButton(
                titleKey: editingLocation ? "action.cancel" : "detail.used.button.moved",
                systemImage: "arrow.triangle.2.circlepath",
                tint: .orange,
                actionType: "moved"
            ) {
                withAnimation(.snappy) {
                    editingLocation.toggle()
                    if editingLocation {
                        locationDraft = item.location?.path ?? ""
                        locationFocused = true
                    }
                }
            }

            // "不知道在哪":清空 location + 写一条 location=nil 的 log,标记"这一刻找不到了"。
            actionButton(
                titleKey: "detail.used.button.unknown",
                systemImage: "questionmark.circle",
                tint: .red,
                actionType: "unknown"
            ) {
                item.location = nil
                item.lastSeenAt = .now
                item.updatedAt = .now
                item.lastActionType = "unknown"
                let log = LocationLog(recordedAt: .now, location: nil, item: item)
                modelContext.insert(log)
                ack(String(localized: "detail.used.ack.unknown"))
            }

            // Phase 91:第 5 个按钮 —— "借给…",紫色,跟其他 4 个互斥维度
            // (不是"用过吗" 的子类,而是"借给别人了")。点开 sheet 输入借给谁。
            actionButton(
                titleKey: "detail.used.button.lentOut",
                systemImage: "person.crop.circle.badge.plus",
                tint: .purple,
                actionType: "lent_out"
            ) {
                lentDraft = item.lentTo ?? ""
                showingLentSheet = true
            }

            if editingLocation {
                locationEditor
            }

            if let ack = ackText {
                Text(ack)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
    }

    private var locationEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("detail.used.location.placeholder",
                      text: $locationDraft)
                .textFieldStyle(.roundedBorder)
                .focused($locationFocused)
                .onSubmit(saveNewLocation)

            // Phase 63:文本框上方/下方加自动完成 chip 行 ——
            //   - 检测到房间名 → "<房间> 内" chip 行
            //   - 总是显示 "最近用过"
            // 任一行点击 chip 就把 path 追加到 locationDraft(同输入框逻辑)。
            locationDraftHints

            // 实时预览解析后的层级。
            let preview = InputParser.parseLocationOnly(locationDraft)
            if !preview.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption2)
                    Text(preview.joined(separator: " › "))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            Button("detail.used.button.saveLocation", action: saveNewLocation)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(preview.isEmpty)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 8))
    }

    // MARK: - Phase 63:位置编辑器的自动完成 chip 行

    /// 跟输入框 inputBar 的 recentLocationHints 同款逻辑,简化版:
    ///   - 检测到房间名 → 房间子位置 chips(上)
    ///   - 最近用过 chips(下,最多 5 个)
    /// 点击 chip → 把 path 追加到 locationDraft。
    @ViewBuilder
    private var locationDraftHints: some View {
        let recent = recentLocationsForEditor
        let room = detectedRoomForEditor
        let inRoom = inRoomSuggestionsForEditor
        if !recent.isEmpty || !inRoom.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if let room, !inRoom.isEmpty {
                    chipRow(label: String(localized: "input.inRoom.label \(room.name)"),
                            icon: "house.fill",
                            locations: inRoom)
                }
                if !recent.isEmpty {
                    chipRow(label: String(localized: "input.recentLocations.label"),
                            icon: "clock.arrow.circlepath",
                            locations: recent)
                }
            }
        }
    }

    /// 最近用过的 5 个位置(从 Item @Query 拉,跟 ContentView 同口径)。
    /// 这里需要走 modelContext 查 —— 详情视图没注 @Query。
    private var recentLocationsForEditor: [Location] {
        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate<Item> { !$0.isDeleted },
            sortBy: [SortDescriptor(\Item.lastSeenAt, order: .reverse)]
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        var seen: Set<PersistentIdentifier> = []
        var result: [Location] = []
        for it in items {
            guard let loc = it.location else { continue }
            if seen.insert(loc.persistentModelID).inserted {
                result.append(loc)
                if result.count >= 5 { break }
            }
        }
        return result
    }

    /// 跟 ContentView 同款房间检测,fold-match 最长名命中。
    private var detectedRoomForEditor: Location? {
        let trimmed = locationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let foldedDraft = trimmed.foldedForMatch
        let all = (try? modelContext.fetch(FetchDescriptor<Location>())) ?? []
        let candidates = all.filter {
            !$0.name.isEmpty
                && !$0.children.isEmpty
                && foldedDraft.contains($0.name.foldedForMatch)
        }
        let roots = candidates.filter { $0.parent == nil }
        let pool = roots.isEmpty ? candidates : roots
        return pool.max { $0.name.count < $1.name.count }
    }

    private var inRoomSuggestionsForEditor: [Location] {
        guard let room = detectedRoomForEditor else { return [] }
        let recentIDs = Set(recentLocationsForEditor.map { $0.persistentModelID })
        return room.children
            .sorted { $0.name < $1.name }
            .filter { !recentIDs.contains($0.persistentModelID) }
            .prefix(6)
            .map { $0 }
    }

    /// 一行 chip。
    @ViewBuilder
    private func chipRow(label: String, icon: String, locations: [Location]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(verbatim: label).font(.caption2.weight(.medium))
            }
            .foregroundStyle(.secondary)
            WrapLayout(spacing: 4, lineSpacing: 3) {
                ForEach(locations) { loc in
                    Button {
                        // Phase 76:位置编辑器是"只输位置"的字段,点 chip 应该**替换**整段
                        // 已输内容(不是追加)。否则 user 输了 "AAA",点 "BBB" 会变成 "AAABBB"
                        // 然后保存 → 位置变成 "AAABBB",不是 BBB。
                        // (输入框里的 chip 是追加 —— 因为那是组装 "X 在 Y" 句子)
                        locationDraft = loc.path
                        locationFocused = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.and.ellipse").font(.caption2)
                            Text(verbatim: loc.path).font(.caption2)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 位置历史时间线

    /// 合并 LocationLog + EditLog 的"时间线条目"。Phase 39 起两类历史合并到同一个时间线。
    /// 用 enum 而非协议是为了让 ForEach 的 id 容易拼出来。
    private enum HistoryEntry: Identifiable {
        case location(LocationLog)
        case edit(EditLog)

        var id: String {
            switch self {
            case .location(let l): return "loc-\(ObjectIdentifier(l))"
            case .edit(let e):     return "edit-\(ObjectIdentifier(e))"
            }
        }
        var recordedAt: Date {
            switch self {
            case .location(let l): return l.recordedAt
            case .edit(let e):     return e.recordedAt
            }
        }
    }

    /// 合并 + 倒序(最新 → 最旧)。
    private var combinedHistory: [HistoryEntry] {
        var entries: [HistoryEntry] = item.locationHistory.map { .location($0) }
        entries += item.editHistory.map { .edit($0) }
        return entries.sorted { $0.recordedAt > $1.recordedAt }
    }

    /// 最新一条位置 log —— 用来标"现在所在"那枚高亮 chip。EditLog 不参与"current"判断。
    private var currentLocationLog: LocationLog? {
        item.locationHistory.sorted { $0.recordedAt > $1.recordedAt }.first
    }

    @State private var historyExpanded = true

    @ViewBuilder
    private var historySection: some View {
        let entries = combinedHistory
        let current = currentLocationLog
        DisclosureGroup(isExpanded: $historyExpanded) {
            if entries.isEmpty {
                Text("detail.history.empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                        switch entry {
                        case .location(let log):
                            historyRow(
                                log: log,
                                isCurrent: log === current,
                                isLast: idx == entries.count - 1
                            )
                        case .edit(let log):
                            editHistoryRow(
                                log: log,
                                isLast: idx == entries.count - 1
                            )
                        }
                    }
                }
                .padding(.top, 8)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                Text("detail.history.title")
                    .font(.headline)
                Spacer()
                if !entries.isEmpty {
                    // catalog key 实际是 "detail.history.count %lld",带 plural variants。
                    Text("detail.history.count \(entries.count)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: .capsule)
                }
            }
        }
    }

    /// 字段编辑历史的单行(Phase 39):图标 + "{field} 改为 X(来源:Y)" + 相对时间。
    private func editHistoryRow(log: EditLog, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // 时间线竖线 + 来源色点
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(editSourceColor(log.source).opacity(0.18))
                        .frame(width: 10, height: 10)
                    Circle()
                        .stroke(editSourceColor(log.source), lineWidth: 1.5)
                        .frame(width: 10, height: 10)
                }
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    // 字段标签 chip
                    Text(editFieldLabel(log.field))
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.secondary.opacity(0.15), in: .capsule)
                    // 来源 chip(AI Claude / 火山引擎 / 解析 / 手工)
                    Text(editSourceLabel(log.source))
                        .font(.caption2)
                        .foregroundStyle(editSourceColor(log.source))
                    // Phase 69:AI 改的 name 行加 ↩ 还原按钮 —— 恢复到改之前的名字。
                    // 触发条件:field==name && source 是 AI 来源 && 旧值非空 && 当前 name 还是 AI 改后的值。
                    if shouldShowRestoreButton(for: log) {
                        Spacer(minLength: 0)
                        Button {
                            restoreNameFromLog(log)
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.uturn.backward")
                                Text("detail.history.restoreName")
                            }
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.orange.opacity(0.18), in: .capsule)
                            .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                        .help("detail.history.restoreName.tooltip")
                    }
                }
                // "旧值" → "新值"。空值显示"·"。
                HStack(spacing: 4) {
                    Text(log.oldValue ?? "·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .strikethrough()
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(log.newValue ?? "·")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                Text(relativeDate(log.recordedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, isLast ? 0 : 2)
    }

    /// Phase 69:这条 EditLog 该显示「↩ 还原」按钮吗?
    /// 只对"AI 改了 name"且"旧值还在"且"当前 name 依然是 AI 设的那个"的 log 显示。
    /// 一旦 user 已经手动改了或还原过一次,后续的 AI 改名 log 不再显示按钮。
    private func shouldShowRestoreButton(for log: EditLog) -> Bool {
        guard log.field == "name",
              log.source.hasPrefix("ai_"),
              let old = log.oldValue, !old.isEmpty,
              let new = log.newValue else { return false }
        // 当前 item.name 必须 == log.newValue,才说明这条 AI 改名"还有效"
        return item.name == new
    }

    /// Phase 69:把 item.name 还原回 log.oldValue,并写一条 source="restore" 的 EditLog
    /// 让历史时间线能看到"还原"动作本身。
    private func restoreNameFromLog(_ log: EditLog) {
        guard let old = log.oldValue, !old.isEmpty else { return }
        let snap = ItemFieldSnapshot(item)
        item.name = old
        item.updatedAt = .now
        snap.recordEdits(against: item, source: "restore", in: modelContext)
    }

    /// 把 EditLog.field 翻译成 UI 标签(catalog key)。
    private func editFieldLabel(_ field: String) -> LocalizedStringKey {
        switch field {
        case "name":           return "meta.label.name"
        case "model":          return "meta.label.model"
        case "version":        return "meta.label.version"
        case "color":          return "meta.label.color"
        case "purchaseDate":   return "meta.label.purchase"
        case "purchaseSource": return "meta.label.source"
        case "notes":          return "edit.field.notes"
        // Phase 95:借出 / 归还字段(写在 EditLog 里,详情时间线渲染)
        case "lent":           return "history.field.lent"
        case "returned":       return "history.field.returned"
        default:               return "history.field.unknown"
        }
    }

    /// 来源 → 用户友好标签。
    private func editSourceLabel(_ source: String) -> LocalizedStringKey {
        switch source {
        case "ai_claude":     return "history.source.aiClaude"
        case "ai_volcengine": return "history.source.aiVolc"
        case "parser":        return "history.source.parser"
        case "update_intent": return "history.source.updateIntent"
        case "batch":         return "history.source.batch"
        case "manual":        return "history.source.manual"
        case "restore":       return "history.source.restore"
        // Phase 95:借出 / 归还 source 标签
        case "lent_out":      return "history.source.lentOut"
        case "returned":      return "history.source.returned"
        default:              return "history.source.unknown"
        }
    }

    private func editSourceColor(_ source: String) -> Color {
        switch source {
        case "ai_claude", "ai_volcengine": return .purple
        case "parser", "update_intent":    return .blue
        case "manual", "batch":            return .green
        case "restore":                    return .orange
        // Phase 95:借出/归还色 —— 借出紫(对应借出徽章色)、归还橙(对应归还按钮色)
        case "lent_out":                   return .purple
        case "returned":                   return .orange
        default:                           return .secondary
        }
    }

    /// 一条历史:左边是个小点 + 竖线段,右边时间和位置。
    private func historyRow(log: LocationLog, isCurrent: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // 时间线竖线 + 圆点
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .stroke(isCurrent ? Color.accentColor : Color.secondary.opacity(0.5),
                                lineWidth: isCurrent ? 2 : 1.5)
                        .frame(width: 10, height: 10)
                    if isCurrent {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                    }
                }
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    // path 是用户数据(verbatim);fallback "未指定位置"显式 resolve 成本地化 String。
                    Text(log.location?.path ?? String(localized: "location.unspecified"))
                        .font(.callout)
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                    if isCurrent {
                        Text("detail.history.currentTag")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.accentColor.opacity(0.18), in: .capsule)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(relativeDate(log.recordedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, isLast ? 0 : 2)
    }

    private func relativeDate(_ date: Date) -> String {
        // 5 分钟内 "刚刚" / "Just now",1 周内 "x 小时前" 走系统格式化(locale-aware),再远显示绝对日期。
        let interval = Date.now.timeIntervalSince(date)
        if interval < 60 { return String(localized: "time.justNow") }
        let formatter = RelativeDateTimeFormatter()
        // 不再 hardcode locale,跟随系统(英文 locale 会显示 "5 min ago")。
        formatter.unitsStyle = .short
        if interval < 7 * 24 * 3600 {
            return formatter.localizedString(for: date, relativeTo: .now)
        } else {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
    }

    // MARK: - 关联项目(Phase 54)

    /// 列出与当前物品同组的其它物品。
    /// 每行 link-style 按钮 → 触发 onSelectItem 切换 inspector 内容。
    /// 右上角 "⊕" 添加;每行 hover 出现 × 解除。
    /// 空状态:显示"尚未关联任何物品" + 大 "添加关联" 按钮。
    @ViewBuilder
    private var relatedSection: some View {
        let peers = RelatedGroup.peers(of: item, in: modelContext)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if peers.isEmpty {
                    Text("related.section.title.empty")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                } else {
                    // 加上自己后的总数 / 上限
                    Text("related.section.title \(peers.count + 1) \(RelatedGroup.maxGroupSize)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingRelatedPicker = true
                } label: {
                    Label("related.button.add", systemImage: "plus.circle")
                        .font(.caption)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .disabled(peers.count + 1 >= RelatedGroup.maxGroupSize)
                .help(peers.count + 1 >= RelatedGroup.maxGroupSize
                      ? String(localized: "related.button.add.fullHint")
                      : String(localized: "related.button.add.tooltip"))
            }
            if peers.isEmpty {
                Text("related.section.empty.hint")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(peers) { peer in
                    relatedRow(peer)
                }
            }
        }
    }

    /// 一行关联物品:link-style 按钮(主)+ × 解除按钮。
    /// 点主按钮 → onSelectItem 切换 inspector 内容(由 ContentView 实现)。
    @ViewBuilder
    private func relatedRow(_ peer: Item) -> some View {
        HStack(spacing: 6) {
            // 主按钮 —— 系统 link style 自动加下划线 + accent 色,跟 macOS 链接观感一致
            Button {
                onSelectItem?(peer.persistentModelID)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.forward.square")
                        .font(.caption)
                    Text(peer.name)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.link)
            .disabled(onSelectItem == nil)
            // path 小字辅助
            if let path = peer.location?.path, !path.isEmpty {
                Text(verbatim: "· \(path)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            // × 解除关联 —— 只断 peer 一件,不影响组里其它人之间的关系
            Button {
                RelatedGroup.unlink(peer, in: modelContext)
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("related.button.unlink.tooltip")
        }
    }

    // MARK: - Meta(创建/更新时间)

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            metaRow(label: "detail.meta.lastSeen", date: item.lastSeenAt)
            metaRow(label: "detail.meta.created",  date: item.createdAt)
            if !item.notes.isEmpty {
                Text("detail.meta.notes").font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                // item.notes 是用户数据(verbatim);用 some StringProtocol overload 不查 catalog。
                Text(item.notes).font(.callout)
            }
        }
    }

    /// label 收 LocalizedStringKey,字面量调用处直接传 catalog key 即可。
    private func metaRow(label: LocalizedStringKey, date: Date) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func saveNewLocation() {
        let path = InputParser.parseLocationOnly(locationDraft)
        guard !path.isEmpty else { return }
        let newLoc = Location.ensure(path: path, in: modelContext)
        item.location = newLoc
        item.lastSeenAt = .now
        item.updatedAt = .now
        item.lastActionType = "moved"
        let log = LocationLog(recordedAt: .now, location: newLoc, item: item)
        modelContext.insert(log)
        editingLocation = false
        locationDraft = ""
        ack(String(localized: "detail.used.ack.moved"))
    }

    /// "他还在原位" 和 "放回原位了" 共享的逻辑。
    /// actionType 参数:"stillThere" 或 "putBack",写入 item.lastActionType 用于按钮高亮。
    private func confirmStillHere(actionType: String) {
        item.lastSeenAt = .now
        item.updatedAt = .now
        item.lastActionType = actionType
        let log = LocationLog(recordedAt: .now, location: item.location, item: item)
        modelContext.insert(log)
        ack(String(localized: "detail.used.ack.kept"))
    }

    /// "用过吗?" 区四个按钮的统一构造器。
    /// - actionType:跟 `Item.lastActionType` 对比,等同 = 强调态(.borderedProminent + 下方 caption)
    /// - tint:按钮主色,渐进式 mint → blue → orange → red
    @ViewBuilder
    private func actionButton(
        titleKey: LocalizedStringKey,
        systemImage: String,
        tint: Color,
        actionType: String,
        action: @escaping () -> Void
    ) -> some View {
        let isEmphasized = (item.lastActionType == actionType)
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if isEmphasized {
                    Button(action: action) {
                        Label(titleKey, systemImage: systemImage)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: action) {
                        Label(titleKey, systemImage: systemImage)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .tint(tint)
            .controlSize(.large)

            // 强调态下方一行 caption:"X 时间前 · 动作名"
            if isEmphosizedCaptionVisible(isEmphasized: isEmphasized, actionType: actionType) {
                Text(verbatim: lastActionCaption(actionType: actionType, titleKey: titleKey))
                    .font(.caption2)
                    .foregroundStyle(tint)
                    .padding(.leading, 4)
            }
        }
    }

    /// 是否给这个按钮显示 caption。除了强调外,"moved" 用 lastSeenAt 没保证准确
    /// (lastSeenAt 在 "他还在原位"/"放回"/"不知道" 都更新,只在 saveNewLocation 里
    /// 才真的代表 "moved")。这里简单处理:强调态就显示 caption。
    private func isEmphosizedCaptionVisible(isEmphasized: Bool, actionType: String) -> Bool {
        isEmphasized && item.lastSeenAt > item.createdAt
    }

    /// 拼 caption:"5 分钟前 · 放回原位了"。
    /// `.formatted(.relative(presentation: .named))` 走系统 locale —— 中文 "5 分钟前",英文 "5 min ago"。
    private func lastActionCaption(actionType: String, titleKey: LocalizedStringKey) -> String {
        let timeText = item.lastSeenAt.formatted(.relative(presentation: .named))
        let labelKey: String
        switch actionType {
        case "stillThere": labelKey = "detail.used.button.stillThere"
        case "putBack":    labelKey = "detail.used.button.putBack"
        case "moved":      labelKey = "detail.used.button.moved"
        case "unknown":    labelKey = "detail.used.button.unknown"
        default:           labelKey = ""
        }
        let actionText = NSLocalizedString(labelKey, comment: "")
        return "\(timeText) · \(actionText)"
    }

    private func ack(_ text: String) {
        withAnimation { ackText = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation { ackText = nil }
            }
        }
    }
}

/// "重新解析名字"的预览/确认 sheet。
/// 把 item.name 喂给 InputParser,跟当前各字段比对,只列出"能补"的差异:
///   - parsed.name 比当前 name 短/干净 → 建议改名
///   - parsed.X 非空 且 item.X 为空 → 建议补字段(已填的不覆盖,免得手编被冲)
/// 用户点"采纳"才落库;"取消"什么都不动。
struct RefreshParseSuggestion: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: Item

    /// 一项可采纳的建议。
    /// field 用 LocalizedStringKey 类型存 catalog key,Text(s.field) 直接走 catalog。
    private struct Suggestion: Identifiable {
        let id = UUID()
        let field: LocalizedStringKey  // catalog key,如 "refresh.field.name" / "meta.label.model"
        let oldValue: String?
        let newValue: String
        let apply: () -> Void
    }

    private var suggestions: [Suggestion] {
        let parsed = InputParser.parse(item.name)
        var out: [Suggestion] = []

        // 名字:只有"更干净"(短一些或不同)且 parsed.name 非空时才建议。
        let trimmedOld = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !parsed.name.isEmpty, parsed.name != trimmedOld {
            out.append(Suggestion(
                field: "refresh.field.name",
                oldValue: trimmedOld,
                newValue: parsed.name,
                apply: { item.name = parsed.name }
            ))
        }
        // 型号 / 版本 / 颜色 / 渠道 / 日期:只在当前为空时才补。
        if let m = parsed.model, item.model?.isEmpty != false {
            out.append(Suggestion(field: "meta.label.model", oldValue: item.model, newValue: m,
                                  apply: { item.model = m }))
        }
        if let v = parsed.version, item.version?.isEmpty != false {
            out.append(Suggestion(field: "meta.label.version", oldValue: item.version, newValue: v,
                                  apply: { item.version = v }))
        }
        if let c = parsed.color, item.color?.isEmpty != false {
            out.append(Suggestion(field: "meta.label.color", oldValue: item.color, newValue: c,
                                  apply: { item.color = c }))
        }
        if let s = parsed.purchaseSource, item.purchaseSource?.isEmpty != false {
            out.append(Suggestion(field: "meta.label.source", oldValue: item.purchaseSource, newValue: s,
                                  apply: { item.purchaseSource = s }))
        }
        if let d = parsed.purchaseDate, item.purchaseDate == nil {
            let label = formatPurchaseDate(d, precision: parsed.purchaseDatePrecision) ?? ""
            // "购买日期" 文案和 ItemEditView 的 DatePicker label 同义,复用 edit.field.purchaseDate
            out.append(Suggestion(field: "edit.field.purchaseDate", oldValue: nil, newValue: label,
                                  apply: {
                                      item.purchaseDate = d
                                      item.purchaseDatePrecision = parsed.purchaseDatePrecision
                                  }))
        }
        return out
    }

    var body: some View {
        let list = suggestions
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("refresh.title \(item.name)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if list.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("refresh.empty")
                            .font(.callout)
                    }
                    .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(list) { s in
                            suggestionRow(s)
                        }
                    }
                    Text("refresh.footer")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("refresh.navTitle")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("refresh.button.apply") {
                        for s in list { s.apply() }
                        item.updatedAt = .now
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(list.isEmpty)
                }
            }
        }
        .frame(minWidth: 380, idealWidth: 460, minHeight: 280, idealHeight: 340)
    }

    private func suggestionRow(_ s: Suggestion) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(s.field)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                if let old = s.oldValue, !old.isEmpty {
                    HStack(spacing: 6) {
                        Text(old)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .strikethrough()
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(s.newValue)
                            .font(.callout)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text(s.newValue)
                            .font(.callout)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// 点缩略图弹出的"大图"视图。
/// macOS:适配窗口大小、可拖动滚动;iOS:全屏 sheet,顶部一个 ✕。
/// 没做手势缩放(SwiftUI 上跨平台手势复杂),先够用。
struct PhotoZoomView: View {
    let image: Image
    let dismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            ScrollView([.horizontal, .vertical]) {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white, .black.opacity(0.4))
                    .padding(16)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .frame(minWidth: 400, idealWidth: 800, minHeight: 400, idealHeight: 600)
    }
}

/// Phase 91:借给…sheet。输入借给谁的名字 → 写 item.lentTo/lentAt。
/// 回调 `done(true)` = 已保存,父 view 写 LocationLog + 弹 toast;`done(false)` = 取消。
struct LentOutSheet: View {
    @Bindable var item: Item
    @Binding var draft: String
    let done: (_ saved: Bool) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.plus")
                Text("detail.lent.sheet.title")
                    .font(.headline)
            }
            .foregroundStyle(.purple)
            Text("detail.lent.sheet.description \(item.name)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("detail.lent.sheet.placeholder", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
            HStack {
                Button("action.cancel") { done(false) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("detail.lent.sheet.confirm", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
        .onAppear { focused = true }
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        item.markLentOut(to: trimmed)
        done(true)
    }
}
