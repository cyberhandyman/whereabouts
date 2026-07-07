import SwiftUI
import SwiftData

// MARK: - 批量编辑 sheets(Phase 12)
//
// 三个 sheet:加标签 / 设置位置 / 设置购买渠道。
// 共同模式:
//   - 显式 "应用 / 取消" 按钮 —— 跟单条 ItemEditView 的"改完立即写"不同,
//     批量改动一次影响多件物品,加个 commit 步骤让用户有反悔机会。
//   - 没有原子化事务,只是把所有变更累积到点"应用"时统一遍历写回。

// MARK: - 批量加/减标签(Phase 47:三态)

/// 给一组 item 编辑标签 —— 能加也能减。
///
/// 每行 tag 一个三态显示:
///   - **全部**(N/N 件都挂着):勾选 / checkmark
///   - **部分**(K/N 件挂着,0<K<N):横线 / minus(代表"维持现状,不改")
///   - **没有**(0/N 件挂着):空圈 / circle
///
/// 点击循环:partial → on → off → on …
///   (没有回到 partial 的路径 —— partial 只是初始观测态,用户一旦动手就要选定"全要"或"全不要")
///
/// 提交时:任何 row 上 on/off 与"初始观测的 partial 状态"不同 → 写动作;留在 partial 的 row 不动。
///
/// 单条选中 case 也复用这个表:items.count == 1 时,三态退化为二态(每行不是 on 就是 off),
/// 表现等同于单条编辑里勾选标签。
struct BatchTagsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let items: [Item]
    /// 提交后回调:(items 数量, 增/减总变更数)。父视图据此弹 toast。
    let onCommit: (Int, Int) -> Void

    @Query(sort: \Tag.createdAt) private var allTags: [Tag]

    /// 三态枚举 —— 表示**用户当前希望的状态**,不是观测态。
    /// 第一次打开时按观测态初始化,之后用户点击会修改这里。
    enum TriState { case off, partial, on }

    /// 每个 tag 当前在 UI 上是哪种状态。key 用 persistentModelID。
    @State private var states: [PersistentIdentifier: TriState] = [:]
    /// 初始观测态 —— 用来在 commit 时判断"用户改了没"。
    @State private var initialStates: [PersistentIdentifier: TriState] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(items.count == 1 ? "batch.tags.hint.single" : "batch.tags.hint")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section {
                    if allTags.isEmpty {
                        Text("tag.empty")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(allTags) { tag in
                            row(tag)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("batch.tags.title \(items.count)"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("batch.tags.apply", action: commit)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!hasChanges)
                }
            }
            .onAppear(perform: initStates)
        }
        .frame(minWidth: 380, idealWidth: 460, minHeight: 360, idealHeight: 480)
    }

    /// 初始化每个 tag 的观测态。
    private func initStates() {
        var s: [PersistentIdentifier: TriState] = [:]
        for tag in allTags {
            let attached = items.filter { it in
                it.tags.contains { $0.persistentModelID == tag.persistentModelID }
            }.count
            let st: TriState
            if attached == 0                { st = .off }
            else if attached == items.count { st = .on }
            else                            { st = .partial }
            s[tag.persistentModelID] = st
        }
        states = s
        initialStates = s
    }

    /// 用户有没有改过任何一行?(用来 enable/disable "应用"按钮)
    private var hasChanges: Bool {
        for (id, st) in states {
            if initialStates[id] != st { return true }
        }
        return false
    }

    /// 单行 tag:色点 + 名字 + 计数小字(部分态时显示 K/N)+ 三态图标。
    private func row(_ tag: Tag) -> some View {
        let state = states[tag.persistentModelID] ?? .off
        let attached = items.filter { it in
            it.tags.contains { $0.persistentModelID == tag.persistentModelID }
        }.count

        return Button {
            // partial → on → off → on …(没有回到 partial 的路径)
            switch state {
            case .partial, .off: states[tag.persistentModelID] = .on
            case .on:            states[tag.persistentModelID] = .off
            }
        } label: {
            HStack {
                Circle()
                    .fill(Color(tagHex: tag.colorHex))
                    .frame(width: 12, height: 12)
                Text(tag.name)
                Spacer()
                // 部分态下显示 K/N,让用户知道当前有多少件挂着;全部/全无就不展示了
                if state == .partial {
                    Text(verbatim: "\(attached)/\(items.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                triStateIcon(state)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func triStateIcon(_ state: TriState) -> some View {
        switch state {
        case .on:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accentColor)
        case .partial:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.orange)
        case .off:
            Image(systemName: "circle")
                .foregroundStyle(Color.secondary.opacity(0.5))
        }
    }

    private func commit() {
        var changes = 0
        for tag in allTags {
            let id = tag.persistentModelID
            let want = states[id] ?? .off
            let initial = initialStates[id] ?? .off
            guard want != initial else { continue }  // 用户没动这一行 → 跳过

            switch want {
            case .on:
                // 凡是没挂的 item,挂上
                for item in items where !item.tags.contains(where: { $0.persistentModelID == id }) {
                    item.tags.append(tag)
                    item.updatedAt = .now
                    changes += 1
                }
            case .off:
                // 凡是挂着的 item,撤下
                for item in items where item.tags.contains(where: { $0.persistentModelID == id }) {
                    item.tags.removeAll(where: { $0.persistentModelID == id })
                    item.updatedAt = .now
                    changes += 1
                }
            case .partial:
                // 不应该走到 —— UI 不允许用户停在 partial 之外的"未动"。
                // 真到了这里就是 initial==partial 且没动,上面 guard 已 continue。
                break
            }
        }
        onCommit(items.count, changes)
        dismiss()
    }
}

// MARK: - 批量设置位置

/// 给一组 item 设置同一个位置。每件物品独立写一条 LocationLog,
/// 跟单条 detail 里"位置变了"是同一种语义,只是一次操作多件。
///
/// Phase 76:这里也加自动完成 chip 行(跟详情页 locationEditor 一致):
///   - 检测到 draft 里有已存在房间名 → "<房间> 内" chip
///   - 总是显示最近用过的 5 个位置
/// 点击 chip = **替换** draft(不是追加),因为这是"只输位置"字段。
struct BatchLocationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let items: [Item]
    let onCommit: (Int) -> Void

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    /// 预览解析后的层级 —— 跟 detail.locationEditor 一致的行为。
    private var preview: [String] {
        InputParser.parseLocationOnly(draft)
    }

    /// 最近用过的 5 个位置(按 lastSeenAt 降序去重)。跟 detail 一样查 modelContext。
    private var recentLocations: [Location] {
        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate<Item> { !$0.isDeleted },
            sortBy: [SortDescriptor(\Item.lastSeenAt, order: .reverse)]
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        var seen: Set<PersistentIdentifier> = []
        var result: [Location] = []
        for it in all {
            guard let loc = it.location else { continue }
            if seen.insert(loc.persistentModelID).inserted {
                result.append(loc)
                if result.count >= 5 { break }
            }
        }
        return result
    }

    /// 跟 ContentView / detail 同款房间检测 —— draft 里出现某个已知 Location.name 时
    /// 把"该 Location 内的直接子位置"上浮成 chip。
    private var detectedRoom: Location? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var inRoomSuggestions: [Location] {
        guard let room = detectedRoom else { return [] }
        let recentIDs = Set(recentLocations.map { $0.persistentModelID })
        return room.children
            .sorted { $0.name < $1.name }
            .filter { !recentIDs.contains($0.persistentModelID) }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("batch.location.hint")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField("detail.used.location.placeholder", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onSubmit {
                            if !preview.isEmpty { commit() }
                        }
                    // Phase 76:自动完成 chip 行(房间内 + 最近用过)。
                    // 点 chip → 替换 draft,不追加。
                    autocompleteHints
                    if !preview.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.caption2)
                            Text(preview.joined(separator: " › "))
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("batch.location.title \(items.count)"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("batch.location.save", action: commit)
                        .keyboardShortcut(.defaultAction)
                        .disabled(preview.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        // Phase 76:加了 chip 行后内容变高,放宽 minHeight 让 chip 不被挤掉
        .frame(minWidth: 420, idealWidth: 480, minHeight: 360, idealHeight: 420)
    }

    /// Phase 76:同详情页 locationEditor 的两行 chip 提示。
    @ViewBuilder
    private var autocompleteHints: some View {
        let recent = recentLocations
        let room = detectedRoom
        let inRoom = inRoomSuggestions
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
                        // Phase 76 关键:**替换** draft,不追加。
                        // 跟详情页 chipRow 一致 —— 这是"只输位置"字段。
                        draft = loc.path
                        focused = true
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

    private func commit() {
        let path = preview
        guard !path.isEmpty else { return }
        // Phase 68 复用:走 bestMatchOrEnsure 而非 ensure,这样 case-insensitive 命中 +
        // 合并相邻段 + 全局兜底查都生效,跟 AI 路径一致。
        let loc = Location.bestMatchOrEnsure(path: path, in: modelContext)
        for item in items {
            item.location = loc
            item.lastSeenAt = .now
            item.updatedAt = .now
            item.lastActionType = "moved"
            let log = LocationLog(recordedAt: .now, location: loc, item: item)
            modelContext.insert(log)
        }
        onCommit(items.count)
        dismiss()
    }
}

// MARK: - 批量设置购买渠道

/// 给一组 item 设置同一个 purchaseSource。
/// 文本框 + 下拉(复用 InputParser.knownPurchaseSources)。
struct BatchSourceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let items: [Item]
    let onCommit: (Int) -> Void

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("batch.source.hint")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section {
                    HStack {
                        TextField("edit.field.source", text: $draft,
                                  prompt: Text("edit.field.source.placeholder"))
                            .textFieldStyle(.roundedBorder)
                            .focused($focused)
                            .onSubmit {
                                if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                                    commit()
                                }
                            }
                        Menu {
                            // 渠道字典是中文 NLP 数据,源词逐字显示(verbatim),不本地化。
                            ForEach(InputParser.knownPurchaseSources, id: \.self) { source in
                                Button(source) { draft = source }
                            }
                            Divider()
                            Button("edit.menu.clear", role: .destructive) { draft = "" }
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("batch.source.title \(items.count)"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("batch.source.save", action: commit)
                        .keyboardShortcut(.defaultAction)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .frame(minWidth: 380, idealWidth: 460, minHeight: 240, idealHeight: 280)
    }

    private func commit() {
        let v = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        for item in items {
            item.purchaseSource = v
            item.updatedAt = .now
        }
        onCommit(items.count)
        dismiss()
    }
}
