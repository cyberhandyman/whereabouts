import SwiftUI
import SwiftData

/// Phase 87 + Phase 101:位置管理 tab — 树状列出所有 Location,支持重命名 / 删除 /
/// 合并 / 批量操作。
///
/// **语义分层**(Phase 101 重构):
///   - **房间**(Room) = `parent == nil` 且名字看起来像房间(常见房间词 或 用户用作"装东西的容器之外的物理空间")
///   - **位置**(Location) = `parent != nil`(有归属的房间下属位置),或者 `parent == nil` 但**没指定**为房间
///     的孤立位置(跟房间同级别展示,但语义是"未归属于任何房间的独立位置")
///
/// UI 分两个 section:① 房间区(每个房间是一棵 DisclosureGroup) ② 独立位置区(也是 root 但
/// 不当作房间处理 —— 区别在显示上,模型层都还是 parent==nil)。
///
/// **操作**:
///   - 重命名:行内 TextField,改后整棵子树 path 自动跟着变(path 是计算属性)
///   - 删除:空节点直接删;非空 → 警示 dialog,确认后删(items / children 全部断挂或挂到 parent)
///   - 合并:每行 "合并到…" Menu,把当前节点的整棵子树合到选择的目标
///   - 批量:勾选多个,顶部 Toolbar 出现"批量删除"/"批量合并到…"
///
/// **房间词词典** (`roomLikeWords`) 用于自动给 root 节点贴"看起来是房间"标签 — 仅 UI 分类用,
/// 不影响数据。用户可以手动把任何 root 标记为/取消"房间"(下版加)。
struct LocationsSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Location.name) private var allLocations: [Location]

    /// 待删除的节点。non-nil 时 confirmation dialog 弹出。
    @State private var pendingDelete: Location?
    /// Phase 101:被勾选的节点 id 集合 — 批量操作目标。
    @State private var batchSelection: Set<PersistentIdentifier> = []
    /// 批量删除确认。
    @State private var showingBatchDeleteConfirm = false
    /// 批量合并:选择 target 后弹出确认。
    @State private var batchMergeTarget: Location?

    /// Phase 101:用于识别 "这是一个房间词" — 给 UI 区分用,不入库。
    /// 常见房间名 + 一些泛区域词。匹配 fold-form 的全相等(避免半匹配)。
    static let roomLikeWords: Set<String> = [
        "门口", "玄关", "电梯间", "楼梯间", "走廊", "过道",
        "卧室", "主卧", "次卧", "儿童房", "婴儿房", "客房",
        "客厅", "餐厅", "厨房", "卫生间", "洗手间", "浴室",
        "阳台", "露台", "花园", "书房", "办公室", "工作室",
        "储物间", "杂物间", "衣帽间", "更衣室",
        "车库", "地下室", "阁楼", "洗衣房", "茶水间",
        // 英文常见对应词
        "entryway", "hallway", "corridor", "bedroom", "master bedroom",
        "living room", "dining room", "kitchen", "bathroom", "balcony",
        "study", "office", "storage", "garage", "basement", "attic",
        "laundry room",
    ].map(\.foldedForMatch).reduce(into: Set<String>()) { $0.insert($1) }

    /// 判定一个 root 是否"看起来像房间"。简单启发式:名字命中字典即可。
    static func looksLikeRoom(_ loc: Location) -> Bool {
        guard loc.parent == nil else { return false }
        return roomLikeWords.contains(loc.name.foldedForMatch)
    }

    var body: some View {
        Form {
            if allLocations.isEmpty {
                Section {
                    Text("settings.locations.empty")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                let roots = allLocations.filter { $0.parent == nil }
                let rooms = roots.filter { Self.looksLikeRoom($0) }
                let orphans = roots.filter { !Self.looksLikeRoom($0) }

                // Phase 101:批量操作 toolbar(选中 ≥ 1 时出现)
                if !batchSelection.isEmpty {
                    batchToolbar
                }

                if !rooms.isEmpty {
                    Section {
                        ForEach(rooms.sorted(by: { $0.name < $1.name })) { room in
                            LocationTreeRow(
                                location: room,
                                depth: 0,
                                allLocations: allLocations,
                                batchSelection: $batchSelection,
                                onDelete: { pendingDelete = $0 }
                            )
                        }
                    } header: {
                        Text("settings.locations.section.rooms \(rooms.count)")
                    } footer: {
                        Text("settings.locations.section.rooms.hint")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if !orphans.isEmpty {
                    Section {
                        ForEach(orphans.sorted(by: { $0.name < $1.name })) { node in
                            LocationTreeRow(
                                location: node,
                                depth: 0,
                                allLocations: allLocations,
                                batchSelection: $batchSelection,
                                onDelete: { pendingDelete = $0 }
                            )
                        }
                    } header: {
                        Text("settings.locations.section.orphans \(orphans.count)")
                    } footer: {
                        Text("settings.locations.section.orphans.hint")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "settings.locations.delete.title",
            isPresented: .init(get: { pendingDelete != nil },
                               set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("action.delete", role: .destructive) {
                if let node = pendingDelete {
                    deleteNode(node)
                }
                pendingDelete = nil
            }
            Button("action.cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            if let node = pendingDelete {
                let count = LocationTreeRow.countItems(in: node)
                if count > 0 {
                    Text("settings.locations.delete.message.nonEmpty \(node.name) \(count)")
                } else {
                    Text("settings.locations.delete.message \(node.name)")
                }
            }
        }
        .confirmationDialog(
            "settings.locations.batch.delete.title",
            isPresented: $showingBatchDeleteConfirm
        ) {
            Button("action.delete", role: .destructive) {
                batchDelete()
            }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("settings.locations.batch.delete.message \(batchSelection.count)")
        }
    }

    /// Phase 101:顶部批量操作 toolbar。选中至少 1 个时出现。
    @ViewBuilder
    private var batchToolbar: some View {
        Section {
            HStack {
                Text("settings.locations.batch.selected \(batchSelection.count)")
                    .font(.callout.bold())
                Spacer()
                // 批量合并到… —— Menu picker 列出所有可作为 target 的 root
                Menu {
                    let candidates = allLocations
                        .filter { $0.parent == nil && !batchSelection.contains($0.persistentModelID) }
                        .sorted(by: { $0.name < $1.name })
                    ForEach(candidates) { target in
                        Button(target.name) {
                            batchMergeTo(target)
                        }
                    }
                    if allLocations.filter({ $0.parent == nil && !batchSelection.contains($0.persistentModelID) }).isEmpty {
                        Text("settings.locations.batch.merge.noTarget")
                    }
                } label: {
                    Label("settings.locations.batch.merge", systemImage: "arrow.triangle.merge")
                }
                .menuStyle(.borderlessButton)

                Button(role: .destructive) {
                    showingBatchDeleteConfirm = true
                } label: {
                    Label("settings.locations.batch.delete", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)

                Button("action.cancel") {
                    batchSelection.removeAll()
                }
                .buttonStyle(.borderless)
            }
        }
    }

    /// 单节点删除:把所有 items 的 location 改成 parent(或 nil),children reparent 到 parent,再删自己。
    /// 这样数据不丢:之前在被删 location 里的物品现在直接归属其父(或变成"未指定位置")。
    private func deleteNode(_ node: Location) {
        let newParent = node.parent
        // items 提升到 parent
        for item in node.items {
            item.location = newParent
            item.updatedAt = .now
        }
        // children reparent
        for child in Array(node.children) {
            child.parent = newParent
        }
        modelContext.delete(node)
        try? modelContext.save()
    }

    private func batchDelete() {
        let nodes = allLocations.filter { batchSelection.contains($0.persistentModelID) }
        for node in nodes {
            deleteNode(node)
        }
        batchSelection.removeAll()
        showingBatchDeleteConfirm = false
    }

    private func batchMergeTo(_ target: Location) {
        let sources = allLocations.filter { batchSelection.contains($0.persistentModelID) }
        for src in sources {
            _ = Location.mergeUserSelected(source: src, into: target, in: modelContext)
        }
        try? modelContext.save()
        batchSelection.removeAll()
    }
}

/// 单个 Location 节点行,递归渲染子节点。
/// `depth` 控制缩进;0 = root,每下一层 +1。
struct LocationTreeRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var location: Location
    let depth: Int
    let allLocations: [Location]
    @Binding var batchSelection: Set<PersistentIdentifier>
    let onDelete: (Location) -> Void

    /// 是否展开子节点。root 默认展开,深层默认折叠。
    @State private var expanded: Bool

    init(location: Location, depth: Int, allLocations: [Location],
         batchSelection: Binding<Set<PersistentIdentifier>>,
         onDelete: @escaping (Location) -> Void) {
        self.location = location
        self.depth = depth
        self.allLocations = allLocations
        self._batchSelection = batchSelection
        self.onDelete = onDelete
        self._expanded = State(initialValue: depth < 1)
    }

    private var itemCount: Int { location.items.count }
    private var childCount: Int { location.children.count }
    private var subtreeItemCount: Int { Self.countItems(in: location) }
    /// 静态版,供外面用于统计。
    static func countItems(in node: Location) -> Int {
        node.items.count + node.children.reduce(0) { $0 + countItems(in: $1) }
    }
    /// 删除按钮:**始终可用**(deleteNode 会把内容提升到 parent,数据不丢)。
    /// 行为:空节点静默删;非空节点弹确认对话框。
    private var isChecked: Bool { batchSelection.contains(location.persistentModelID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            mainRow
            if expanded {
                childRows
            }
        }
    }

    @ViewBuilder
    private var mainRow: some View {
        HStack(spacing: 6) {
            if depth > 0 {
                Spacer().frame(width: CGFloat(depth) * 16)
            }
            checkboxButton
            expandToggleOrSpacer
            iconView
            TextField("settings.locations.row.name", text: $location.name)
                .textFieldStyle(.roundedBorder)
            Spacer(minLength: 4)
            if subtreeItemCount > 0 {
                Text("settings.locations.row.itemCount \(subtreeItemCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            mergeMenu
            deleteButton
        }
    }

    @ViewBuilder
    private var childRows: some View {
        let sortedChildren = location.children.sorted(by: { $0.name < $1.name })
        ForEach(sortedChildren) { child in
            LocationTreeRow(
                location: child,
                depth: depth + 1,
                allLocations: allLocations,
                batchSelection: $batchSelection,
                onDelete: onDelete
            )
        }
    }

    @ViewBuilder
    private var checkboxButton: some View {
        Button {
            if isChecked {
                batchSelection.remove(location.persistentModelID)
            } else {
                batchSelection.insert(location.persistentModelID)
            }
        } label: {
            Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                .font(.body)
                .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var expandToggleOrSpacer: some View {
        if childCount > 0 {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.bold())
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        } else {
            Spacer().frame(width: 12)
        }
    }

    @ViewBuilder
    private var iconView: some View {
        let isRoom = LocationsSettingsTab.looksLikeRoom(location)
        let name: String = isRoom ? "house" : (childCount > 0 ? "folder" : "mappin.circle")
        Image(systemName: name)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var mergeMenu: some View {
        Menu {
            let candidates = allLocations
                .filter { $0.parent == nil && $0.persistentModelID != location.persistentModelID }
                .sorted(by: { $0.name < $1.name })
            if candidates.isEmpty {
                Text("settings.locations.merge.noTarget")
            }
            ForEach(candidates) { target in
                Button(target.name) {
                    _ = Location.mergeUserSelected(source: location, into: target, in: modelContext)
                    try? modelContext.save()
                }
            }
        } label: {
            Image(systemName: "arrow.triangle.merge")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 20)
        .help("settings.locations.merge.tooltip")
    }

    @ViewBuilder
    private var deleteButton: some View {
        Button(role: .destructive) {
            onDelete(location)
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.red)
        .help("settings.locations.delete.tooltip")
    }
}
