import SwiftUI
import SwiftData

/// 从已有物品里挑一件,把它跟 `source` 关联起来(Phase 53)。
///
/// 候选列表自动排除:
///   - source 自己
///   - 已经跟 source 同组的物品(防重复)
///   - soft-deleted 的物品
///
/// 顶部展示"当前组 K/8"(无组时显示"未关联"),底部一个搜索框 + 滚动列表。
/// 点中候选 → 调 RelatedGroup.link → 出错就 alert,成功就 dismiss。
struct RelatedItemsPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// 发起关联的物品 —— 候选要排除自己 + 已同组成员。
    let source: Item

    /// 成功 link 之后回调,给父视图弹 toast。
    let onLinked: (Item) -> Void

    /// 全集:按更新时间倒序,排除 deleted。SwiftData 不能在 @Query 里
    /// 直接用 source.relatedGroupID(运行时值)过滤,所以这里取全集后内存里 filter。
    @Query(filter: #Predicate<Item> { !$0.isDeleted },
           sort: \Item.updatedAt, order: .reverse) private var allItems: [Item]

    @State private var search: String = ""
    @State private var errorMessage: String?
    @FocusState private var searchFocused: Bool

    /// 当前组里有几件(包括 source 自己)。0 = source 还没入组。
    private var currentGroupSize: Int {
        guard let gid = source.relatedGroupID else { return 0 }
        return RelatedGroup.members(of: gid, in: modelContext).filter { !$0.isDeleted }.count
    }

    /// 候选 = 全集 - 自己 - 已同组 - (按搜索词过滤)。
    private var candidates: [Item] {
        let mySelfID = source.persistentModelID
        let myGroup = source.relatedGroupID
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allItems.filter { item in
            if item.persistentModelID == mySelfID { return false }
            if let mg = myGroup, item.relatedGroupID == mg { return false }
            if !q.isEmpty {
                return item.name.lowercased().contains(q)
            }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                searchField
                Divider()
                candidateList
            }
            .navigationTitle(Text("related.picker.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
            .onAppear { searchFocused = true }
            .alert(
                "related.error.title",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                ),
                presenting: errorMessage
            ) { _ in
                Button("action.ok", role: .cancel) { errorMessage = nil }
            } message: { msg in
                Text(verbatim: msg)
            }
        }
        .frame(minWidth: 420, idealWidth: 520, minHeight: 420, idealHeight: 560)
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
            if currentGroupSize == 0 {
                Text("related.picker.notInGroup")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("related.picker.currentSize \(currentGroupSize) \(RelatedGroup.maxGroupSize)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("related.picker.searchPlaceholder", text: $search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var candidateList: some View {
        if candidates.isEmpty {
            ContentUnavailableView(
                "related.picker.empty",
                systemImage: "magnifyingglass",
                description: Text("related.picker.empty.hint")
            )
            .padding()
        } else {
            List(candidates) { item in
                Button { tryLink(item) } label: {
                    row(item)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func row(_ item: Item) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                if let path = item.location?.path, !path.isEmpty {
                    Text(verbatim: path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            // 候选本身已经在另外一个组里 → 给用户提示"链上后会合并组"
            if let gid = item.relatedGroupID, gid != source.relatedGroupID {
                let n = RelatedGroup.members(of: gid, in: modelContext)
                    .filter { !$0.isDeleted }.count
                Text("related.picker.willMerge \(n)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Image(systemName: "link.badge.plus")
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 4)
    }

    private func tryLink(_ target: Item) {
        do {
            try RelatedGroup.link(source, target, in: modelContext)
            onLinked(target)
            dismiss()
        } catch let err as RelatedGroup.LinkError {
            errorMessage = err.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
