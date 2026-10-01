import SwiftUI
import SwiftData
import PhotosUI

/// 编辑一件物品的全部字段:名称、备注、可选元数据(型号/版本/颜色/购买日期)。
/// 以 sheet 形式弹出,@Bindable 实时绑定到 Item —— 用户输入立即写回 SwiftData。
/// Phase 122:取消会撤销 —— 但**只撤销用户在本表单里亲手改过的东西**(记 touched 字段 +
/// 标签操作流水),表单开着期间 AI 理解结果、另一台设备同步过来的改动、标签去重合并
/// 都照常保留,不会被"取消"一并抹掉。iOS 有未保存改动时禁止下滑关闭。
/// 关联项目 section 仍是即时生效(跟详情页一致),不参与回滚。
struct ItemEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var item: Item

    /// 所有可选标签 —— 用户在 picker 里勾选 / 取消勾选 / 新建。
    @Query(sort: \Tag.createdAt) private var allTags: [Tag]

    /// Phase 39:进表单时拍一次字段快照,Done 时跟当前状态 diff 写 EditLog。
    /// 表单是直接绑 @Bindable item 实时修改的;Phase 122 起它也是"取消"回滚的依据。
    @State private var openSnapshot: ItemFieldSnapshot?
    /// Phase 122:快照之外再记打开时的照片,取消时(若用户动过照片)还原。
    @State private var openPhotoData: Data?
    /// Phase 122:用户在本表单里亲手改过的字段 —— 取消只回滚这些。
    @State private var touched: Set<EditField> = []
    /// Phase 122:用户在本表单里的标签操作流水(added = 挂上 / false = 摘下),取消时倒序撤销。
    @State private var tagOps: [(tag: Tag, added: Bool)] = []
    /// Phase 122:本次表单里新建的标签 —— 取消时若没有别的物品在用,一并删掉,不留孤儿标签。
    @State private var createdTags: [Tag] = []
    /// Phase 122:照片异步加载任务 —— 取消表单时一并取消,免得加载完又把照片写回去。
    @State private var photoLoadTask: Task<Void, Never>?

    enum EditField: Hashable {
        case name, notes, model, version, color, purchaseDate, purchaseSource, photo
    }

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
                    TextField("edit.field.name", text: trackedText(\.name, .name))
                    TextField("edit.field.notes", text: trackedText(\.notes, .notes), axis: .vertical)
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
                    // Phase 122:取消 = 回滚到打开表单时的状态(macOS Esc 同样走这里)。
                    Button("action.cancel") {
                        revertEdits()
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
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
                    openPhotoData = item.photoData
                }
            }
            // Phase 122:有未保存改动时禁止下滑关闭 —— 只能点取消(回滚)或完成(保存)。
            .interactiveDismissDisabled(hasUnsavedChanges)
            // PhotosPicker 选中变化 → 异步加载原图 → 压缩 → 写回 item.photoData
            .onChange(of: pickedItem) { _, newValue in
                guard let newValue else { return }
                photoLoadTask?.cancel()
                photoLoadTask = Task {
                    if let raw = try? await newValue.loadTransferable(type: Data.self),
                       let compressed = ImageHelpers.compressed(data: raw) {
                        await MainActor.run {
                            // 表单已取消(任务被 cancel)就别再写回
                            guard !Task.isCancelled else { return }
                            item.photoData = compressed
                            touched.insert(.photo)
                            pickedItem = nil  // 重置,允许再次选同一张
                        }
                    }
                }
            }
        }
        // Phase 122:固定最小宽度只给 macOS sheet;iPhone 屏宽 < 380pt 会撑出屏幕。
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 460, minHeight: 420, idealHeight: 520)
        #endif
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

            TextField("meta.label.model", text: optionalString(\.model, .model),
                      prompt: Text("edit.field.model.placeholder"))
            TextField("edit.field.version", text: optionalString(\.version, .version),
                      prompt: Text("edit.field.version.placeholder"))
            TextField("meta.label.color", text: optionalString(\.color, .color),
                      prompt: Text("edit.field.color.placeholder"))

            Toggle("edit.toggle.recordDate", isOn: hasPurchaseDate)
            if item.purchaseDate != nil {
                DatePicker("edit.field.purchaseDate",
                           selection: nonOptionalDate(\.purchaseDate, .purchaseDate),
                           displayedComponents: .date)
            }

            HStack {
                TextField("edit.field.source", text: optionalString(\.purchaseSource, .purchaseSource),
                          prompt: Text("edit.field.source.placeholder"))
                Menu {
                    // 渠道字典是中文 NLP 数据,源词逐字显示,不本地化(verbatim)。
                    ForEach(InputParser.knownPurchaseSources, id: \.self) { source in
                        Button(source) {
                            item.purchaseSource = source
                            touched.insert(.purchaseSource)
                        }
                    }
                    Divider()
                    Button("edit.menu.clear", role: .destructive) {
                        item.purchaseSource = nil
                        touched.insert(.purchaseSource)
                    }
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
                    let applied = isApplied(tag)
                    tagRow(tag)
                        // Phase 122:右键 / 长按 / 左滑只"从这件物品上摘下",不再全局删除标签 ——
                        // 旧版 modelContext.delete(tag) 会把它从所有物品、所有设备上删掉。
                        // 全局删除留给 设置 → 标签。
                        .contextMenu {
                            if applied {
                                Button {
                                    detachTag(tag)
                                } label: {
                                    Label("edit.tag.detach", systemImage: "tag.slash")
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if applied {
                                Button {
                                    detachTag(tag)
                                } label: {
                                    Label("edit.tag.detach", systemImage: "tag.slash")
                                }
                                .tint(.orange)
                            }
                        }
                }
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
        let isApplied = isApplied(tag)
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
        tagOps.append((tag, !applied))
    }

    private func addNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 同名 tag 直接复用,不新建(防重复)
        if let existing = allTags.first(where: { $0.name == trimmed }) {
            if !item.tags.contains(where: { $0.persistentModelID == existing.persistentModelID }) {
                item.tags.append(existing)
                tagOps.append((existing, true))
            }
        } else {
            let tag = Tag(name: trimmed, colorHex: newTagColorHex)
            modelContext.insert(tag)
            item.tags.append(tag)
            createdTags.append(tag)
            tagOps.append((tag, true))
        }
        newTagName = ""
        // Phase 20:连续加多个 tag 时,下一个默认用更换的色,而不是又是上一次那个。
        newTagColorHex = nextUnusedPaletteHex()
    }

    private func isApplied(_ tag: Tag) -> Bool {
        item.tags.contains(where: { $0.persistentModelID == tag.persistentModelID })
    }

    /// Phase 122:只把标签从当前物品上摘下(替代旧的全局 deleteTags)。
    private func detachTag(_ tag: Tag) {
        guard isApplied(tag) else { return }
        item.tags.removeAll { $0.persistentModelID == tag.persistentModelID }
        tagOps.append((tag, false))
    }

    // MARK: - Phase 122:未保存改动检测 + 取消回滚

    /// 空串与 nil 视为相同(optionalString 会把空串写成 nil)。
    private func sameText(_ a: String?, _ b: String?) -> Bool {
        (a ?? "") == (b ?? "")
    }

    /// 用户在本表单里亲手改过、且当前值确实跟打开时不同 → 有未保存改动。
    /// 只看 touched 字段 + 标签操作流水:AI / 同步 / 标签合并在后台写进来的改动不算,
    /// 否则它们会让 iOS 莫名其妙地禁止下滑关闭。
    private var hasUnsavedChanges: Bool {
        guard let snap = openSnapshot else { return false }
        for field in touched {
            switch field {
            case .name:           if item.name != snap.name { return true }
            case .notes:          if item.notes != snap.notes { return true }
            case .model:          if !sameText(item.model, snap.model) { return true }
            case .version:        if !sameText(item.version, snap.version) { return true }
            case .color:          if !sameText(item.color, snap.color) { return true }
            case .purchaseSource: if !sameText(item.purchaseSource, snap.purchaseSource) { return true }
            case .purchaseDate:
                if item.purchaseDate != snap.purchaseDate
                    || item.purchaseDatePrecision != snap.purchaseDatePrecision { return true }
            case .photo:          if item.photoData != openPhotoData { return true }
            }
        }
        return !tagOps.isEmpty
    }

    /// 取消:只把用户亲手改过的字段 / 照片还原成打开时的样子,标签操作倒序撤销;
    /// 本次新建且没人用的标签删掉。只在值真的不同时才写回,避免无改动的取消也触发一次上传。
    private func revertEdits() {
        photoLoadTask?.cancel()
        photoLoadTask = nil
        guard let snap = openSnapshot else { return }
        for field in touched {
            switch field {
            case .name:    if item.name != snap.name { item.name = snap.name }
            case .notes:   if item.notes != snap.notes { item.notes = snap.notes }
            case .model:   if item.model != snap.model { item.model = snap.model }
            case .version: if item.version != snap.version { item.version = snap.version }
            case .color:   if item.color != snap.color { item.color = snap.color }
            case .purchaseSource:
                if item.purchaseSource != snap.purchaseSource { item.purchaseSource = snap.purchaseSource }
            case .purchaseDate:
                if item.purchaseDate != snap.purchaseDate { item.purchaseDate = snap.purchaseDate }
                if item.purchaseDatePrecision != snap.purchaseDatePrecision {
                    item.purchaseDatePrecision = snap.purchaseDatePrecision
                }
            case .photo:
                if item.photoData != openPhotoData { item.photoData = openPhotoData }
            }
        }
        // 标签:倒序撤销用户的每一步;打开期间被删掉的标签(modelContext == nil)跳过。
        for op in tagOps.reversed() where op.tag.modelContext != nil {
            let id = op.tag.persistentModelID
            let attached = item.tags.contains { $0.persistentModelID == id }
            if op.added && attached {
                item.tags.removeAll { $0.persistentModelID == id }
            } else if !op.added && !attached {
                item.tags.append(op.tag)
            }
        }
        tagOps = []
        for tag in createdTags where tag.modelContext != nil && tag.items.isEmpty {
            modelContext.delete(tag)
        }
        createdTags = []
        touched = []
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
                        photoLoadTask?.cancel()
                        item.photoData = nil
                        touched.insert(.photo)
                    } label: {
                        Label("edit.photo.delete", systemImage: "trash")
                    }
                }
            }
            #if os(iOS)
            // Phase 122:iOS Form 里一行放多个默认样式按钮,点整行会把它们全部触发 ——
            // 点"换一张"同时把照片删了。borderless 让每个按钮只响应自己的点击区域。
            .buttonStyle(.borderless)
            #endif
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
                touched.insert(.photo)
            }
        }
        #endif
    }

    // MARK: - Optional 字段桥接到 SwiftUI Binding(Phase 122:写入时记 touched)

    /// String 字段绑定;用户一改就记进 touched,取消时只回滚这些字段。
    private func trackedText(_ kp: ReferenceWritableKeyPath<Item, String>, _ field: EditField) -> Binding<String> {
        Binding(
            get: { item[keyPath: kp] },
            set: {
                item[keyPath: kp] = $0
                touched.insert(field)
            }
        )
    }

    /// String? <-> Binding<String>:空串等同于 nil(节省存储,UI 也更干净)。
    private func optionalString(_ kp: ReferenceWritableKeyPath<Item, String?>, _ field: EditField) -> Binding<String> {
        Binding(
            get: { item[keyPath: kp] ?? "" },
            set: {
                item[keyPath: kp] = $0.isEmpty ? nil : $0
                touched.insert(field)
            }
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
                touched.insert(.purchaseDate)
            }
        )
    }

    /// Date? <-> Binding<Date>(只在 Toggle on 时使用,所以 fallback 不会真的显示)。
    private func nonOptionalDate(_ kp: ReferenceWritableKeyPath<Item, Date?>, _ field: EditField) -> Binding<Date> {
        Binding(
            get: { item[keyPath: kp] ?? .now },
            set: {
                item[keyPath: kp] = $0
                touched.insert(field)
            }
        )
    }
}
