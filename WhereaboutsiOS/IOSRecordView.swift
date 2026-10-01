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

    @Query(filter: #Predicate<Item> { $0.deletedAt == nil },
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
    /// Phase 122:同名叶子待消歧的条目排队,一次弹一个 —— 以前多条录入时每条都覆盖
    /// pendingAmbiguousLocation,只剩最后一条,toast 却报"已录入 N 件"。
    @State private var ambiguousQueue: [PendingAmbiguousLocation] = []
    /// Phase 122:本轮提交实际入库的件数(消歧时点了取消的不算)。
    @State private var savedThisCommit = 0
    /// Phase 122:本轮是否多条录入 —— 多条留在本页连续录,单条完成后切回列表。
    @State private var commitIsBatch = false
    /// Phase 122:当前弹出的消歧条目 + 它是否已选定;sheet 关掉时没选定 = 用户取消了这条。
    @State private var presentedAmbiguous: PendingAmbiguousLocation?
    @State private var presentedResolved = false
    /// Phase 122:本轮里因取消消歧而没存的条目 —— 收尾时放回输入框(与 macOS 一致),不悄悄丢掉。
    @State private var cancelledThisCommit: [InputParser.Parsed] = []
    @State private var aiRunner = IOSAIRunner()

    /// 成功 toast(短暂显示后消失)。
    @State private var savedAck: String?
    /// 无 AI key 时点紫色推荐胶囊 → 弹 AI 设置 sheet。
    @State private var showingAISettings = false

    /// Phase 117:语音输入。识别文本实时追加到 draft(以按下时的内容为基底)。
    @State private var speech = SpeechInput()
    @State private var speechBase = ""
    /// Phase 122:本页发起的一次听写进行中(含停止后等最终结果的那一小段)。
    /// 识别文本只在它为 true 时写回草稿;提交 / 离开页面 / 退后台时置 false。
    @State private var dictating = false
    @Environment(\.scenePhase) private var scenePhase

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
        // Phase 122:选完 / 取消都会 dismiss → onDismiss 统一推进队列(弹下一个或收尾)。
        .sheet(item: $pendingAmbiguousLocation, onDismiss: continueOrFinishCommit) { ctx in
            AmbiguousLocationPicker(context: ctx) { choice in
                resolveAmbiguousLocation(ctx, choice: choice)
            }
        }
        // Phase 122:离开本页 / 退到后台 → 停掉语音识别,别让它在后台继续往草稿里写。
        .onDisappear { stopDictation() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { stopDictation() }
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
                    if !speech.isRecording {
                        speechBase = draft
                        dictating = true
                    }
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
                // Phase 122:看 dictating 而不是 isRecording —— 识别器的最终结果到达时
                // isRecording 已经是 false,旧写法会把最后一段丢掉。
                guard dictating else { return }
                // 识别结果实时接到按下录音时的草稿后面
                let sep = speechBase.isEmpty || speechBase.hasSuffix("\n") ? "" : " "
                draft = speechBase + (new.isEmpty ? "" : sep + new)
            }
            if speech.permissionDenied {
                Label("record.voice.denied", systemImage: "mic.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if speech.unavailable {
                // Phase 122:识别服务 / 麦克风不可用(不是权限问题)单独提示。
                Label("record.voice.unavailable", systemImage: "exclamationmark.triangle")
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
        // Phase 122:提交时先停听写,否则识别回调会把刚提交的文字又写回草稿。
        stopDictation()
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
            beginCommitRound(batch: false)
            addNewItem(parsed, rawInput: rawForBatch)
            continueOrFinishCommit()
            return
        }
        // 多条:批量入库,跳过重复检测
        beginCommitRound(batch: true)
        for parsed in list {
            addNewItem(parsed, rawInput: rawForBatch)
        }
        continueOrFinishCommit()
    }

    /// Phase 122:停听写并清基底(提交 / 离开页面 / 退后台)。
    private func stopDictation() {
        dictating = false
        speechBase = ""
        speech.cancel()
    }

    /// Phase 122:开始一轮"入库 + 可能的逐条消歧"。
    private func beginCommitRound(batch: Bool) {
        savedThisCommit = 0
        ambiguousQueue = []
        commitIsBatch = batch
        presentedAmbiguous = nil
        presentedResolved = false
        cancelledThisCommit = []
    }

    /// Phase 122:一轮提交的推进 —— 还有待消歧的就弹下一个;队列空了才 toast / 清草稿 / 切 tab。
    /// 一件都没存(全部取消)→ 草稿保留,方便改了再提交。
    private func continueOrFinishCommit() {
        guard pendingAmbiguousLocation == nil else { return }
        // 刚关掉的消歧 sheet 没选定 → 这条被取消了,记下来收尾时放回输入框。
        if let shown = presentedAmbiguous {
            if !presentedResolved { cancelledThisCommit.append(shown.parsed) }
            presentedAmbiguous = nil
            presentedResolved = false
        }
        if !ambiguousQueue.isEmpty {
            let next = ambiguousQueue.removeFirst()
            presentedAmbiguous = next
            presentedResolved = false
            pendingAmbiguousLocation = next
            return
        }
        let saved = savedThisCommit
        let cancelled = cancelledThisCommit
        savedThisCommit = 0
        cancelledThisCommit = []
        guard saved > 0 else { return }   // 一件都没存:草稿原样保留
        if cancelled.isEmpty {
            draft = ""
        } else {
            // 只把取消的那几条放回去("名字 在 a > b",多条用全角逗号),避免再次提交时重复录入已存的。
            draft = cancelled.map { p in
                p.locationPath.isEmpty ? p.name : "\(p.name) 在 \(p.locationPath.joined(separator: " > "))"
            }.joined(separator: "\u{FF0C}")
        }
        finishCommit(count: saved, stayHere: commitIsBatch || !cancelled.isEmpty,
                     restored: cancelled.count)
    }

    /// 成功反馈:haptic + toast;单条录入切回列表 tab,多条留在本页连续录。
    /// Phase 122:stayHere 显式传(多条录入哪怕只存下 1 件也留在本页)。
    private func finishCommit(count: Int, stayHere: Bool? = nil, restored: Int = 0) {
        let stay = stayHere ?? (count > 1)
        Haptics.success()
        withAnimation(.snappy) {
            var ack = count > 1
                ? String(localized: "quickEntry.ack.batch \(count)")
                : String(localized: "ios.record.ack")
            if restored > 0 {
                ack += " · " + String(localized: "ambiguousLocation.cancel.restored \(restored)")
            }
            savedAck = ack
        }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            await MainActor.run {
                withAnimation { savedAck = nil }
                if !stay { onSaved() }
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
            // Phase 122:排队,由 continueOrFinishCommit 一次弹一个。
            ambiguousQueue.append(PendingAmbiguousLocation(
                parsed: parsed, candidates: candidates, originalLeaf: leaf, rawInput: rawInput))
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
        presentedResolved = true
        // Phase 122:不在这里收尾 —— 选择器 dismiss 后 sheet 的 onDismiss 推进队列。
        pendingAmbiguousLocation = nil
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
        // Phase 122:草稿不在每件入库时清 —— 等整轮(含逐条消歧)结束再清,见 continueOrFinishCommit。
        savedThisCommit += 1
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
        beginCommitRound(batch: list.count > 1)
        if list.isEmpty {
            let raw = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty {
                addNewItem(InputParser.Parsed(name: raw, locationPath: []))
            }
        } else {
            for p in list { addNewItem(p) }
        }
        pendingUpdate = nil
        continueOrFinishCommit()
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
            draft = ""
            pendingDuplicate = nil
            finishCommit(count: 1)
        } else {
            // Phase 122:"新建一条"可能撞上同名叶子 → 走同一套消歧队列,选完才收尾。
            beginCommitRound(batch: false)
            addNewItem(InputParser.Parsed(
                name: dup.newName, locationPath: dup.newPath,
                purchaseDate: dup.newDate, purchaseDatePrecision: dup.newDatePrecision,
                purchaseSource: dup.newSource, model: dup.newModel,
                color: dup.newColor, version: dup.newVersion
            ))
            pendingDuplicate = nil
            continueOrFinishCommit()
        }
    }
}
