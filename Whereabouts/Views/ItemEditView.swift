import SwiftUI
import SwiftData
import PhotosUI

/// 编辑一件物品的全部字段:名称、备注、可选元数据(型号/版本/颜色/购买日期)。
/// 以 sheet 形式弹出,@Bindable 实时绑定到 Item —— 用户输入立即写回 SwiftData。
/// 取消会撤销吗?不会 —— 这跟系统笔记/提醒事项一致(直接修改的 model)。
/// 想要"原子化保存/取消",得多写一份草稿副本,现在 MVP 阶段不值。
struct ItemEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var item: Item

    /// 所有可选标签 —— 用户在 picker 里勾选 / 取消勾选 / 新建。
    @Query(sort: \Tag.createdAt) private var allTags: [Tag]

    /// Phase 39:进表单时拍一次字段快照,Done 时跟当前状态 diff 写 EditLog。
    /// 表单是直接绑 @Bindable item 实时修改的 —— 没有"取消"回滚,
    /// 但我们至少能记录"哪些字段被人工改了"以及"前后值"。
    @State private var openSnapshot: ItemFieldSnapshot?

    /// 新标签输入(picker 末尾的输入框)。
    /// Phase 20:`newTagColorHex` 初始为 nil,在 onAppear 时算出"下一个没被用过的预设色",
    /// 每次成功加完一个 tag 也重算一次 —— 保证连续添加 N 个标签会拿到 N 个不同色。
    @State private var newTagName: String = ""
    @State private var newTagColorHex: String = TagPalette.all[0].hex

    /// PhotosPicker 当前选中。每次选完会 reset,以便用户能再选同一张。
    @State private var pickedItem: PhotosPickerItem?

    /// macOS:打开 .fileImporter 选任意图片文件(从 Finder / 下载等)。
    /// PhotosPicker 只能选系统 Photos 库,Mac 用户更常见是从文件系统拖。
    @State private var showingFileImporter = false

    /// Phase 56:关联项目 section 里点"添加"弹的 RelatedItemsPicker sheet 开关。
    @State private var showingRelatedPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("edit.section.basic") {
                    TextField("edit.field.name", text: $item.name)
                    TextField("edit.field.notes", text: $item.notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                // 顺序:基本 → 可选信息 → 照片 → 标签 → 关联项目
                // 可选信息(型号 / 颜色等)在表单上半部分更容易看到。
                optionalInfoSection

                photoSection

                tagSection

                relatedSection
            }
            .formStyle(.grouped)
            .navigationTitle("edit.navTitle")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") {
                        item.updatedAt = .now
                        // Phase 39:diff 写 EditLog,来源 "manual"。
                        openSnapshot?.recordEdits(against: item, source: "manual", in: modelContext)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                // 进表单时按"已用色"挑下一个没被占的预设色,避免 9 个新标签一个颜色。
                newTagColorHex = nextUnusedPaletteHex()
                // Phase 39:拍一张快照,Done 时跟当前 item 比对生成 EditLog。
                if openSnapshot == nil {
                    openSnapshot = ItemFieldSnapshot(item)
                }
            }
            // PhotosPicker 选中变化 → 异步加载原图 → 压缩 → 写回 item.photoData
            .onChange(of: pickedItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let raw = try? await newValue.loadTransferable(type: Data.self),
                       let compressed = ImageHelpers.compressed(data: raw) {
                        await MainActor.run {
                            item.photoData = compressed
                            pickedItem = nil  // 重置,允许再次选同一张
                        }
                    }
                }
            }
        }
        .frame(minWidth: 380, idealWidth: 460, minHeight: 420, idealHeight: 520)
    }

    /// 可选信息 section —— 在基本 section 下面,顺序靠前。
    /// 跟 photoSection / tagSection 一致的 @ViewBuilder 提取。
    @ViewBuilder
    private var optionalInfoSection: some View {
        Section("edit.section.optional") {
            // Phase 51:品牌只读派生显示 —— 跟列表 chip / 详情页 chip 三处统一。
            // 不存库,实时从 name 用 InputParser.brand 推断。改 name 时这里自动跟着变。
            HStack {
                Text("meta.label.brand")
                    .foregroundStyle(.secondary)
                Spacer()
                if let b = InputParser.brand(for: item.name) {
                    Text(b)
                } else {
                    Text("edit.field.brand.empty")
                        .foregroundStyle(.tertiary)
                }
            }
            .help("edit.field.brand.tooltip")

            TextField("meta.label.model", text: optionalString(\.model),
                      prompt: Text("edit.field.model.placeholder"))
            TextField("edit.field.version", text: optionalString(\.version),
                      prompt: Text("edit.field.version.placeholder"))
            TextField("meta.label.color", text: optionalString(\.color),
                      prompt: Text("edit.field.color.placeholder"))

            Toggle("edit.toggle.recordDate", isOn: hasPurchaseDate)
            if item.purchaseDate != nil {
                DatePicker("edit.field.purchaseDate",
                           selection: nonOptionalDate(\.purchaseDate),
                           displayedComponents: .date)
            }

            HStack {
                TextField("edit.field.source", text: optionalString(\.purchaseSource),
                          prompt: Text("edit.field.source.placeholder"))
                Menu {
                    // 渠道字典是中文 NLP 数据,源词逐字显示,不本地化(verbatim)。
                    ForEach(InputParser.knownPurchaseSources, id: \.self) { source in
                        Button(source) { item.purchaseSource = source }
                    }
                    Divider()
                    Button("edit.menu.clear", role: .destructive) { item.purchaseSource = nil }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    /// 标签 section:展示所有已有 tag,每个前面 toggle 状态(已挂 = 蓝色对勾),底部一行新建。
    /// 颜色用 Finder 风格的 9 色调色板,新建时点小圆切色;Phase 20 起轮换默认色。
    @ViewBuilder
    private var tagSection: some View {
        Section {
            if allTags.isEmpty {
                Text("tag.empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(allTags) { tag in
                    tagRow(tag)
                        // Phase 20:macOS 没有 swipe;右键菜单提供删除入口。
                        .contextMenu {
                            Button(role: .destructive) {
                                modelContext.delete(tag)
                            } label: {
                                Label("action.delete", systemImage: "trash")
                            }
                        }
                }
                .onDelete(perform: deleteTags)  // 留给 iOS swipe
            }

            // 新建一行:Phase 31 起把 Menu 拆成两层 ——
            //   row 1: 横向色板(9 个彩色圆点直接显示),
            //   row 2: 名字 TextField + 添加按钮。
            // 旧版 Menu 在 macOS 上把彩色 systemImage 渲染成单色,完全看不到颜色。
            VStack(alignment: .leading, spacing: 6) {
                TagColorPicker(selected: $newTagColorHex, diameter: 16, spacing: 5)
                HStack(spacing: 8) {
                    TextField("tag.new.placeholder", text: $newTagName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addNewTag)
                    Button("tag.new.button", action: addNewTag)
                        .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        } header: {
            Text("tag.section.header")
        } footer: {
            // Phase 20:小字提示去 Settings 批量管理(改色/重命名/删除),降低本表单复杂度。
            Text("tag.section.footer.hint")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Phase 56:关联项目 section —— 跟详情页的 relatedSection 等价,只是 Form 风格。
    /// 行为:
    ///   - 头部显示 K/8 计数 + "添加" 按钮(满了 disabled)
    ///   - 每个 peer 一行,显示 name + 路径,右边一个 × 解除按钮
    ///   - 编辑表单里点 × 立刻生效(不等 Done) —— 跟 tagSection 一致
    ///   - 这里不点击跳转(用户已经在编辑了);跳转能力在详情页 relatedSection
    @ViewBuilder
    private var relatedSection: some View {
        let peers = RelatedGroup.peers(of: item, in: modelContext)
        Section {
            if peers.isEmpty {
                Text("related.section.empty.hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(peers) { peer in
                    HStack {
                        Image(systemName: "link")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(peer.name)
                                .lineLimit(1)
                            if let path = peer.location?.path, !path.isEmpty {
                                Text(verbatim: path)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
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
            }
            Button {
                showingRelatedPicker = true
            } label: {
                Label(
                    peers.isEmpty ? "related.button.add" : "related.button.addMore",
                    systemImage: "link.badge.plus"
                )
            }
            .disabled(peers.count + 1 >= RelatedGroup.maxGroupSize)
        } header: {
            HStack {
                Text("related.section.title.short")
                Spacer()
                if !peers.isEmpty {
                    Text(verbatim: "\(peers.count + 1)/\(RelatedGroup.maxGroupSize)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showingRelatedPicker) {
            RelatedItemsPicker(source: item) { _ in /* 编辑表单里不弹 toast */ }
        }
    }

    /// 单个标签行 —— 左边颜色点 + 名字,右边对勾(已挂)/ 空圈(未挂)。整行可点。
    private func tagRow(_ tag: Tag) -> some View {
        let isApplied = item.tags.contains(where: { $0.persistentModelID == tag.persistentModelID })
        return Button {
            toggleTag(tag, applied: isApplied)
        } label: {
            HStack {
                Circle()
                    .fill(Color(tagHex: tag.colorHex))
                    .frame(width: 12, height: 12)
                Text(tag.name)
                Spacer()
                Image(systemName: isApplied ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isApplied ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Phase 20:挑下一个"还没被占用"的预设颜色;9 色都满了就回到第 0 个。
    /// 让连续添加 N 个标签拿到 N 个不同色,而不是清一色灰。
    private func nextUnusedPaletteHex() -> String {
        let used = Set(allTags.map { $0.colorHex.lowercased() })
        if let next = TagPalette.all.first(where: { !used.contains($0.hex.lowercased()) }) {
            return next.hex
        }
        // 9 色全占满 —— 退到 createdAt 排序的索引
        return TagPalette.all[allTags.count % TagPalette.all.count].hex
    }

    private func toggleTag(_ tag: Tag, applied: Bool) {
        if applied {
            item.tags.removeAll { $0.persistentModelID == tag.persistentModelID }
        } else {
            item.tags.append(tag)
        }
    }

    private func addNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 同名 tag 直接复用,不新建(防重复)
        if let existing = allTags.first(where: { $0.name == trimmed }) {
            if !item.tags.contains(where: { $0.persistentModelID == existing.persistentModelID }) {
                item.tags.append(existing)
            }
        } else {
            let tag = Tag(name: trimmed, colorHex: newTagColorHex)
            modelContext.insert(tag)
            item.tags.append(tag)
        }
        newTagName = ""
        // Phase 20:连续加多个 tag 时,下一个默认用更换的色,而不是又是上一次那个。
        newTagColorHex = nextUnusedPaletteHex()
    }

    private func deleteTags(at offsets: IndexSet) {
        // 从全集里删 — SwiftData 的 nullify rule 会自动从所有 item 上断挂载。
        for index in offsets {
            modelContext.delete(allTags[index])
        }
    }

    /// 照片 section:已有则显示缩略图 + 删除 + 换;没有则两个来源选(系统 Photos / Finder 文件)。
    @ViewBuilder
    private var photoSection: some View {
        Section("edit.section.photo") {
            if let data = item.photoData, let img = Image(data: data) {
                img
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            HStack(spacing: 8) {
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Label(item.photoData == nil ? "edit.photo.pickFirst" : "edit.photo.replace",
                          systemImage: "photo")
                }
                #if os(macOS)
                // macOS:并排一个"从文件…"按钮,用 .fileImporter 选 Finder 里的图片。
                Button {
                    showingFileImporter = true
                } label: {
                    Label("edit.photo.fromFile", systemImage: "folder")
                }
                #endif
                if item.photoData != nil {
                    Spacer()
                    Button(role: .destructive) {
                        item.photoData = nil
                    } label: {
                        Label("edit.photo.delete", systemImage: "trash")
                    }
                }
            }
        }
        #if os(macOS)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            // 沙箱外文件:必须 startAccessingSecurityScopedResource,否则读不到。
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url),
               let compressed = ImageHelpers.compressed(data: data) {
                item.photoData = compressed
            }
        }
        #endif
    }

    // MARK: - Optional 字段桥接到 SwiftUI Binding

    /// String? <-> Binding<String>:空串等同于 nil(节省存储,UI 也更干净)。
    private func optionalString(_ kp: ReferenceWritableKeyPath<Item, String?>) -> Binding<String> {
        Binding(
            get: { item[keyPath: kp] ?? "" },
            set: { item[keyPath: kp] = $0.isEmpty ? nil : $0 }
        )
    }

    /// 是否记录购买日期(Toggle 绑这个;切换时初始化/清空 purchaseDate)。
    private var hasPurchaseDate: Binding<Bool> {
        Binding(
            get: { item.purchaseDate != nil },
            set: { newValue in
                if newValue {
                    if item.purchaseDate == nil { item.purchaseDate = .now }
                } else {
                    item.purchaseDate = nil
                }
            }
        )
    }

    /// Date? <-> Binding<Date>(只在 Toggle on 时使用,所以 fallback 不会真的显示)。
    private func nonOptionalDate(_ kp: ReferenceWritableKeyPath<Item, Date?>) -> Binding<Date> {
        Binding(
            get: { item[keyPath: kp] ?? .now },
            set: { item[keyPath: kp] = $0 }
        )
    }
}
