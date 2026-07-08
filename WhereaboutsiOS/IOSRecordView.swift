import SwiftUI
import SwiftData

// Phase 111:iOS "记一条" tab —— 大输入卡 + 实时解析预览卡 + 位置 chips + AI 开关。
// 解析 / 重复检测 / 字段更新意图 / 同名叶子消歧全部复用共享层
// (InputParser / Location.resolve / AmbiguousLocationPicker),行为与 macOS 一致;
// 多条批量录入跳过重复检测,也跟 macOS 相同。

struct IOSRecordView: View {
    /// 录入成功后回调(切回"物品"tab)。多条时不切,便于连续录。
    var onSaved: () -> Void = {}

    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Item> { !$0.isDeleted },
           sort: \Item.updatedAt, order: .reverse)
    private var items: [Item]
    @Query private var allTags: [Tag]

    @State private var draft = ""
    @FocusState private var focused: Bool

    @AppStorage("dupDetectionEnabled") private var dupDetectionEnabled: Bool = true
    @AppStorage("updateIntentDetectionEnabled") private var updateIntentDetectionEnabled: Bool = true
    @AppStorage("autoTagSuggestEnabled") private var autoTagSuggestEnabled: Bool = true
    @AppStorage("useAIOnInput") private var useAIOnInput: Bool = false

    @State private var pendingDuplicate: PendingDuplicate?
    @State private var pendingUpdate: PendingUpdate?
    @State private var pendingAmbiguousLocation: PendingAmbiguousLocation?
    @State private var aiRunner = IOSAIRunner()

    /// 成功 toast(短暂显示后消失)。
    @State private var savedAck: String?
    /// 无 AI key 时点紫色推荐胶囊 → 弹 AI 设置 sheet。
    @State private var showingAISettings = false

    /// Phase 117:语音输入。识别文本实时追加到 draft(以按下时的内容为基底)。
    @State private var speech = SpeechInput()
    @State private var speechBase = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    composeCard
                    if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                        previewCard
                    } else {
                        hintCard
                    }
                    locationChipsCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(IOSTheme.pageBackground)
            .navigationTitle("ios.tab.record")
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: $showingAISettings) {
            NavigationStack { IOSAISettingsView() }
        }
        .sheet(item: $pendingAmbiguousLocation) { ctx in
            AmbiguousLocationPicker(context: ctx) { choice in
                resolveAmbiguousLocation(ctx, choice: choice)
            }
        }
        .alert("dup.alert.title",
               isPresented: .init(get: { pendingDuplicate != nil },
                                  set: { if !$0 { pendingDuplicate = nil } }),
               presenting: pendingDuplicate) { dup in
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
            let oldLoc = dup.existing.location?.path ?? String(localized: "location.unspecified")
            if dup.newPath.isEmpty {
                Text("dup.alert.message.noLocation \(dup.existing.name) \(oldLoc) \(dup.metaSummary)")
            } else {
                Text("dup.alert.message.withLocation \(dup.existing.name) \(oldLoc) \(dup.newName) \(dup.newPath.joined(separator: " › "))")
            }
        }
        .alert("update.alert.title",
               isPresented: .init(get: { pendingUpdate != nil },
                                  set: { if !$0 { pendingUpdate = nil } }),
               presenting: pendingUpdate) { upd in
            Button("update.alert.button.update \(upd.item.name)") { applyUpdate(upd) }
            Button("update.alert.button.createInstead") { createFromRawDraft() }
            Button("action.cancel", role: .cancel) { pendingUpdate = nil }
        } message: { upd in
            Text("update.alert.message \(upd.item.name) \(upd.summary)")
        }
    }

    // MARK: - 输入卡

    private var composeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                GradientIconTile(systemName: "square.and.pencil", size: 30, cornerRadius: 8)
                Text("input.section.title")
                    .font(.headline)
                Spacer()
            }
            TextField("quickEntry.placeholder", text: $draft, axis: .vertical)
                .font(.body)
                .lineLimit(3...8)
                .focused($focused)
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            // AI 开关行(有 key 才可用;无 key 显示紫色推荐胶囊)
            if AISettings.hasActiveKey {
                Toggle(isOn: $useAIOnInput) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(IOSTheme.actionPurple)
                        Text("input.aiToggle.label")
                            .font(.subheadline)
                    }
                }
                .tint(IOSTheme.actionPurple)
            } else {
                Button {
                    showingAISettings = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                        Text("input.hint.aiRecommend")
                            .font(.caption.bold())
                        Image(systemName: "arrow.up.forward")
                            .font(.caption2)
                    }
                    .foregroundStyle(IOSTheme.actionPurple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(IOSTheme.actionPurple.opacity(0.10), in: .capsule)
                }
                .buttonStyle(.plain)
            }

            // Phase 117:语音按钮 + 提交按钮一行。录音中麦克风变红并脉动。
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    if !speech.isRecording { speechBase = draft }
                    speech.toggle()
                } label: {
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.title3.weight(.semibold))
                        .frame(width: 52, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(speech.isRecording ? AnyShapeStyle(Color.red)
                                                         : AnyShapeStyle(IOSTheme.accent.opacity(0.13)))
                        )
                        .foregroundStyle(speech.isRecording ? .white : IOSTheme.accent)
                        .symbolEffect(.pulse, isActive: speech.isRecording)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(speech.isRecording ? Text("record.voice.stop") : Text("record.voice.start"))

                Button(action: commit) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("ios.record.submit")
                            .font(.headline)
                        let count = InputParser.parseMultiple(draft).count
                        if count > 1 {
                            Text(verbatim: "×\(count)")
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(canSubmit ? AnyShapeStyle(IOSTheme.gradient)
                                            : AnyShapeStyle(Color.secondary.opacity(0.2)))
                    )
                    .foregroundStyle(canSubmit ? .white : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
            .onChange(of: speech.transcript) { _, new in
                guard speech.isRecording else { return }
                // 识别结果实时接到按下录音时的草稿后面
                let sep = speechBase.isEmpty || speechBase.hasSuffix("\n") ? "" : " "
                draft = speechBase + (new.isEmpty ? "" : sep + new)
            }
            if speech.permissionDenied {
                Label("record.voice.denied", systemImage: "mic.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let savedAck {
                Label(savedAck, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .iosCard()
    }

    private var canSubmit: Bool {
        !InputParser.parseMultiple(draft).isEmpty
    }

    // MARK: - 解析预览卡

    private var previewCard: some View {
        let list = InputParser.parseMultiple(draft)
        return VStack(alignment: .leading, spacing: 10) {
            if list.count > 1 {
                Text("input.preview.willCreate \(list.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(list.indices, id: \.self) { i in
                let p = list[i]
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(p.name)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(IOSTheme.accent.opacity(0.13), in: .capsule)
                        if !p.locationPath.isEmpty {
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(verbatim: p.locationPath.joined(separator: " › "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    extractedMetaRow(p)
                }
                if i < list.count - 1 { Divider() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .iosCard()
    }

    @ViewBuilder
    private func extractedMetaRow(_ p: InputParser.Parsed) -> some View {
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
            WrapLayout(spacing: 5, lineSpacing: 4) {
                ForEach(pairs, id: \.0) { (labelKey, value) in
                    HStack(spacing: 3) {
                        Text(LocalizedStringKey(labelKey))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(value).font(.caption2)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.10), in: .capsule)
                    .fixedSize()
                }
            }
        }
    }

    /// 空输入时的使用提示卡(对齐 macOS 的 input.hint 两行)。
    private var hintCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text("input.hint.line1")
            }
            Text("input.hint.line2")
                .padding(.leading, 21)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .iosCard(padding: 14, cornerRadius: 16)
    }

    // MARK: - 位置 chips 卡(最近用过 + 检测到房间的子位置)

    @ViewBuilder
    private var locationChipsCard: some View {
        let recent = recentLocations
        let room = detectedRoomInDraft
        let inRoom = inRoomSuggestions
        if !recent.isEmpty || !inRoom.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if let room, !inRoom.isEmpty {
                    chipRow(labelKey: "input.inRoom.label \(room.name)",
                            icon: "house.fill", locations: inRoom)
                }
                if !recent.isEmpty {
                    chipRow(labelKey: "input.recentLocations.label",
                            icon: "clock.arrow.circlepath", locations: recent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .iosCard(padding: 14, cornerRadius: 16)
        }
    }

    @ViewBuilder
    private func chipRow(labelKey: LocalizedStringKey, icon: String, locations: [Location]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(labelKey).font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
            WrapLayout(spacing: 5, lineSpacing: 5) {
                ForEach(locations) { loc in
                    Button {
                        Haptics.tap()
                        appendLocationToDraft(loc)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.and.ellipse").font(.caption2)
                            Text(verbatim: loc.path).font(.caption)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(IOSTheme.accent.opacity(0.10), in: .capsule)
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

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

    private var detectedRoomInDraft: Location? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let foldedDraft = trimmed.foldedForMatch
        let all = (try? modelContext.fetch(FetchDescriptor<Location>())) ?? []
        let candidates = all.filter { loc in
            !loc.name.isEmpty && !loc.children.isEmpty
                && foldedDraft.contains(loc.name.foldedForMatch)
        }
        let roots = candidates.filter { $0.parent == nil }
        let pool = roots.isEmpty ? candidates : roots
        return pool.max { $0.name.count < $1.name.count }
    }

    private var inRoomSuggestions: [Location] {
        guard let room = detectedRoomInDraft else { return [] }
        let recentIDs = Set(recentLocations.map { $0.persistentModelID })
        return room.children
            .sorted { $0.name < $1.name }
            .filter { !recentIDs.contains($0.persistentModelID) }
            .prefix(6)
            .map { $0 }
    }

    private func appendLocationToDraft(_ loc: Location) {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = trimmed.isEmpty ? loc.path : "\(trimmed) 在 \(loc.path)"
        focused = true
    }

    // MARK: - 提交(对齐 macOS ContentView.commit)

    private func commit() {
        let list = InputParser.parseMultiple(draft)
        guard !list.isEmpty else { return }
        let rawForBatch = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        // 单条:字段更新意图检测("X 的型号是 Y")
        if list.count == 1, updateIntentDetectionEnabled,
           let intent = InputParser.matchUpdateIntent(draft, candidateNames: items.map(\.name)),
           let target = items.first(where: { $0.name == intent.matchedName }) {
            pendingUpdate = PendingUpdate(item: target, changes: intent.changes, summary: intent.summary)
            return
        }
        // 单条:重复检测
        if list.count == 1 {
            let parsed = list[0]
            if dupDetectionEnabled, let dup = findDuplicateMatch(name: parsed.name) {
                pendingDuplicate = PendingDuplicate(
                    existing: dup, newName: parsed.name, newPath: parsed.locationPath,
                    newDate: parsed.purchaseDate, newDatePrecision: parsed.purchaseDatePrecision,
                    newSource: parsed.purchaseSource, newModel: parsed.model,
                    newColor: parsed.color, newVersion: parsed.version
                )
                return
            }
            addNewItem(parsed, rawInput: rawForBatch)
            finishCommit(count: 1)
            return
        }
        // 多条:批量入库,跳过重复检测
        for parsed in list {
            addNewItem(parsed, rawInput: rawForBatch)
        }
        finishCommit(count: list.count)
    }

    /// 成功反馈:haptic + toast;单条录入切回列表 tab,多条留在本页连续录。
    private func finishCommit(count: Int) {
        Haptics.success()
        withAnimation(.snappy) {
            savedAck = count > 1
                ? String(localized: "quickEntry.ack.batch \(count)")
                : String(localized: "ios.record.ack")
        }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            await MainActor.run {
                withAnimation { savedAck = nil }
                if count == 1 { onSaved() }
            }
        }
    }

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
        switch Location.resolve(path: parsed.locationPath, in: modelContext) {
        case .ambiguous(let candidates, let leaf):
            pendingAmbiguousLocation = PendingAmbiguousLocation(
                parsed: parsed, candidates: candidates, originalLeaf: leaf, rawInput: rawInput)
        case .useExisting(let loc):
            finalizeNewItem(parsed, location: loc, rawInput: rawInput)
        case .create(let path):
            finalizeNewItem(parsed, location: Location.ensure(path: path, in: modelContext),
                            rawInput: rawInput)
        }
    }

    private func resolveAmbiguousLocation(_ ctx: PendingAmbiguousLocation, choice: AmbiguousChoice) {
        let loc: Location?
        switch choice {
        case .existing(let chosen): loc = chosen
        case .newTopLevel:          loc = Location.ensure(path: ctx.parsed.locationPath, in: modelContext)
        }
        finalizeNewItem(ctx.parsed, location: loc, rawInput: ctx.rawInput)
        pendingAmbiguousLocation = nil
        finishCommit(count: 1)
    }

    private func finalizeNewItem(_ parsed: InputParser.Parsed, location loc: Location?, rawInput: String? = nil) {
        let item = Item(name: parsed.name, location: loc)
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
        modelContext.insert(LocationLog(recordedAt: .now, location: loc, item: item))
        applyAutoTagSuggestion(to: item)
        if useAIOnInput && AISettings.hasActiveKey {
            aiRunner.understand(items: [item], allTags: allTags, allItems: items, context: modelContext)
        }
        draft = ""
    }

    /// 静默自动挂 tag(iOS 不做撤销 toast,编辑页可手动摘)。
    private func applyAutoTagSuggestion(to item: Item) {
        guard autoTagSuggestEnabled else { return }
        guard let hex = InputParser.suggestTagColorHex(forName: item.name) else { return }
        let target = hex.lowercased()
        let candidate = allTags
            .filter { $0.colorHex.lowercased() == target }
            .sorted(by: { $0.createdAt < $1.createdAt })
            .first
        guard let tag = candidate else { return }
        if item.tags.contains(where: { $0.persistentModelID == tag.persistentModelID }) { return }
        item.tags.append(tag)
    }

    private func applyUpdate(_ pending: PendingUpdate) {
        let i = pending.item
        let c = pending.changes
        let snap = ItemFieldSnapshot(i)
        if let v = c.model          { i.model = v }
        if let v = c.version        { i.version = v }
        if let v = c.color          { i.color = v }
        if let v = c.notes          { i.notes = v }
        if let v = c.purchaseDate {
            i.purchaseDate = v
            i.purchaseDatePrecision = c.purchaseDatePrecision
        }
        if let v = c.purchaseSource { i.purchaseSource = v }
        i.updatedAt = .now
        snap.recordEdits(against: i, source: "update_intent", in: modelContext)
        draft = ""
        pendingUpdate = nil
        finishCommit(count: 1)
    }

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
        finishCommit(count: max(1, list.count))
    }

    private func resolveDuplicate(_ dup: PendingDuplicate, asUpdate: Bool) {
        if asUpdate {
            if !dup.newPath.isEmpty {
                let newLoc = Location.ensure(path: dup.newPath, in: modelContext)
                dup.existing.location = newLoc
                dup.existing.lastSeenAt = .now
                modelContext.insert(LocationLog(recordedAt: .now, location: newLoc, item: dup.existing))
            }
            dup.existing.updatedAt = .now
            if dup.newName.count > dup.existing.name.count {
                dup.existing.name = dup.newName
            }
            if dup.existing.purchaseDate == nil {
                dup.existing.purchaseDate = dup.newDate
                dup.existing.purchaseDatePrecision = dup.newDatePrecision
            }
            if dup.existing.purchaseSource == nil { dup.existing.purchaseSource = dup.newSource }
            if dup.existing.model          == nil { dup.existing.model          = dup.newModel }
            if dup.existing.color          == nil { dup.existing.color          = dup.newColor }
            if dup.existing.version        == nil { dup.existing.version        = dup.newVersion }
        } else {
            addNewItem(InputParser.Parsed(
                name: dup.newName, locationPath: dup.newPath,
                purchaseDate: dup.newDate, purchaseDatePrecision: dup.newDatePrecision,
                purchaseSource: dup.newSource, model: dup.newModel,
                color: dup.newColor, version: dup.newVersion
            ))
        }
        draft = ""
        pendingDuplicate = nil
        finishCommit(count: 1)
    }
}
