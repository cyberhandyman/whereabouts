import SwiftUI
import SwiftData

// Phase 111:iOS 详情页 —— hero 照片 / 渐变横幅 + 位置面包屑 + "用过吗?" 2×2 动作网格
// + 借给(整宽紫)+ 合并时间线 + 关联物品 + 元信息卡。
// 数据语义与 macOS ItemDetailView 完全一致(lastActionType 高亮、LocationLog/EditLog 合并等)。

struct IOSItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: Item

    @Query private var allTags: [Tag]
    @Query(filter: #Predicate<Item> { !$0.isDeleted },
           sort: \Item.updatedAt, order: .reverse)
    private var allItems: [Item]

    @State private var aiRunner = IOSAIRunner()
    @State private var showingEditSheet = false
    @State private var showingLentSheet = false
    @State private var showingPhotoZoom = false
    @State private var showingDeleteConfirm = false
    @State private var editingLocation = false
    @State private var locationDraft = ""
    @FocusState private var locationFocused: Bool
    @State private var ackText: String?

    private var isAIProcessing: Bool {
        aiRunner.processing.contains(item.persistentModelID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                heroBanner
                headerCard
                if item.isLentOut { lentCard }
                actionsCard
                historyCard
                relatedCard
                metaCard
                deleteButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(IOSTheme.pageBackground)
        .navigationTitle(Text(verbatim: item.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    aiRunner.understand(items: [item], allTags: allTags,
                                        allItems: allItems, context: modelContext)
                } label: {
                    if isAIProcessing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                }
                .disabled(isAIProcessing || !AISettings.hasActiveKey)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) { ItemEditView(item: item) }
        .sheet(isPresented: $showingLentSheet) {
            IOSLentSheet(item: item)
                .presentationDetents([.height(300)])
        }
        .fullScreenCover(isPresented: $showingPhotoZoom) {
            if let data = item.photoData, let img = Image(data: data) {
                IOSPhotoZoom(image: img) { showingPhotoZoom = false }
            }
        }
        .confirmationDialog("delete.alert.title", isPresented: $showingDeleteConfirm) {
            Button("action.delete", role: .destructive) {
                item.markDeleted()
                Haptics.warning()
            }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("delete.alert.message \(item.name)")
        }
    }

    // MARK: - Hero

    /// 有照片:照片横幅(点开全屏);无照片:品牌渐变 + 大盒子图标横幅。
    @ViewBuilder
    private var heroBanner: some View {
        if let data = item.photoData, let img = Image(data: data) {
            Button {
                showingPhotoZoom = true
            } label: {
                img
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(.quaternary.opacity(0.6), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(IOSTheme.gradient.opacity(0.9))
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(height: 130)
        }
    }

    // MARK: - Header 卡:名字 + 位置面包屑 + 标签 + 属性 chips

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.name)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            // 位置面包屑:每段一个胶囊,chevron 相连;未指定时问号胶囊。
            locationBreadcrumb

            if !item.tags.isEmpty {
                WrapLayout(spacing: 6, lineSpacing: 5) {
                    ForEach(item.tags) { tag in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(tagHex: tag.colorHex))
                                .frame(width: 7, height: 7)
                            Text(tag.name).font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(tagHex: tag.colorHex).opacity(0.12), in: .capsule)
                        .fixedSize()
                    }
                }
            }

            attributeChips
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .iosCard()
    }

    @ViewBuilder
    private var locationBreadcrumb: some View {
        let segments: [String] = item.location?.path.components(separatedBy: " > ") ?? []
        if segments.isEmpty {
            Label("location.unspecified", systemImage: "questionmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            WrapLayout(spacing: 4, lineSpacing: 5) {
                ForEach(segments.indices, id: \.self) { i in
                    HStack(spacing: 4) {
                        if i == 0 {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.caption2)
                                .foregroundStyle(IOSTheme.accent)
                        }
                        Text(verbatim: segments[i])
                            .font(.subheadline.weight(i == segments.count - 1 ? .semibold : .regular))
                        if i < segments.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(IOSTheme.accent.opacity(i == segments.count - 1 ? 0.14 : 0.07),
                                in: .capsule)
                    .fixedSize()
                }
            }
        }
    }

    /// 品牌 / 型号 / 版本 / 颜色 / 渠道 / 购买时间 —— 有值才显示的小 chips。
    @ViewBuilder
    private var attributeChips: some View {
        let chips: [(labelKey: String, value: String)] = {
            var out: [(String, String)] = []
            if let b = InputParser.brand(for: item.name) { out.append(("meta.label.brand", b)) }
            if let m = item.model, !m.isEmpty { out.append(("meta.label.model", m)) }
            if let v = item.version, !v.isEmpty { out.append(("meta.label.version", v)) }
            if let c = item.color, !c.isEmpty { out.append(("meta.label.color", c)) }
            if let s = item.purchaseSource, !s.isEmpty { out.append(("meta.label.source", s)) }
            if let label = formatPurchaseDate(item.purchaseDate, precision: item.purchaseDatePrecision) {
                out.append(("meta.label.purchase", label))
            }
            return out
        }()
        if !chips.isEmpty {
            WrapLayout(spacing: 6, lineSpacing: 5) {
                ForEach(chips, id: \.0) { (labelKey, value) in
                    HStack(spacing: 3) {
                        Text(LocalizedStringKey(labelKey))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(value).font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.10), in: .capsule)
                    .fixedSize()
                }
            }
        }
    }

    // MARK: - 借出徽章卡

    private var lentCard: some View {
        HStack(spacing: 10) {
            GradientIconTile(systemName: "person.fill.checkmark", size: 34, cornerRadius: 9,
                             gradient: LinearGradient(colors: [.orange, .orange.opacity(0.6)],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: 2) {
                if let lentTo = item.lentTo, let lentAt = item.lentAt {
                    Text("detail.lent.badge \(lentTo) \(lentAt.formatted(.relative(presentation: .named)))")
                        .font(.subheadline.weight(.medium))
                } else if let lentTo = item.lentTo {
                    Text("detail.lent.badge.noDate \(lentTo)")
                        .font(.subheadline.weight(.medium))
                }
            }
            Spacer()
            Button {
                let borrower = item.lentTo ?? ""
                item.markReturned()
                let entry = EditLog(recordedAt: .now, source: "returned", field: "returned",
                                    oldValue: borrower, newValue: nil, item: item)
                modelContext.insert(entry)
                Haptics.success()
                flashAck(String(localized: "detail.lent.ack.returned"))
            } label: {
                Label("detail.lent.button.return", systemImage: "arrow.uturn.backward.circle")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
        .foregroundStyle(.orange)
        .iosCard(padding: 12, cornerRadius: 18)
    }

    // MARK: - "用过吗?" 动作卡

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "hand.tap")
                Text("detail.used.title").font(.headline)
            }
            Text("detail.used.description")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                      spacing: 10) {
                actionButton(titleKey: "detail.used.button.stillThere",
                             systemImage: "eye.fill",
                             tint: IOSTheme.actionMint, actionType: "stillThere") {
                    confirmStillHere(actionType: "stillThere")
                }
                actionButton(titleKey: "detail.used.button.putBack",
                             systemImage: "checkmark.circle.fill",
                             tint: IOSTheme.actionBlue, actionType: "putBack") {
                    confirmStillHere(actionType: "putBack")
                }
                actionButton(titleKey: editingLocation ? "action.cancel" : "detail.used.button.moved",
                             systemImage: "arrow.triangle.2.circlepath",
                             tint: IOSTheme.actionOrange, actionType: "moved") {
                    withAnimation(.snappy) {
                        editingLocation.toggle()
                        if editingLocation {
                            locationDraft = item.location?.path ?? ""
                            locationFocused = true
                        }
                    }
                }
                actionButton(titleKey: "detail.used.button.unknown",
                             systemImage: "questionmark.circle",
                             tint: IOSTheme.actionRed, actionType: "unknown") {
                    item.location = nil
                    item.lastSeenAt = .now
                    item.updatedAt = .now
                    item.lastActionType = "unknown"
                    modelContext.insert(LocationLog(recordedAt: .now, location: nil, item: item))
                    flashAck(String(localized: "detail.used.ack.unknown"))
                }
            }

            // 第 5 个动作:借给…(整宽紫,跟其它 4 个语义维度不同)
            actionButton(titleKey: "detail.used.button.lentOut",
                         systemImage: "person.crop.circle.badge.plus",
                         tint: IOSTheme.actionPurple, actionType: "lent_out",
                         fullWidth: true) {
                showingLentSheet = true
            }

            if editingLocation {
                locationEditor
            }

            if let ack = ackText {
                Label(ack, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }

            let lastAction = lastActionCaption()
            if let lastAction {
                Text(verbatim: lastAction)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .iosCard()
    }

    /// 自绘动作按钮:强调态 = 实色填充 + 白字;普通态 = 12% 色底 + 彩字。
    /// 比系统 bordered 更"卡片化",与整页设计语言一致。
    @ViewBuilder
    private func actionButton(
        titleKey: LocalizedStringKey,
        systemImage: String,
        tint: Color,
        actionType: String,
        fullWidth: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let isEmphasized = (item.lastActionType == actionType)
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                Text(titleKey)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isEmphasized
                          ? AnyShapeStyle(LinearGradient(colors: [tint, tint.opacity(0.75)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(tint.opacity(0.13)))
            )
            .foregroundStyle(isEmphasized ? Color.white : tint)
        }
        .buttonStyle(.plain)
        .gridCellColumns(fullWidth ? 2 : 1)
    }

    /// 强调按钮下的说明:"{相对时间} · {动作名}"(有过动作才显示)。
    private func lastActionCaption() -> String? {
        guard let actionType = item.lastActionType,
              item.lastSeenAt > item.createdAt else { return nil }
        let labelKey: String
        switch actionType {
        case "stillThere": labelKey = "detail.used.button.stillThere"
        case "putBack":    labelKey = "detail.used.button.putBack"
        case "moved":      labelKey = "detail.used.button.moved"
        case "unknown":    labelKey = "detail.used.button.unknown"
        case "lent_out":   labelKey = "detail.used.button.lentOut"
        default:           return nil
        }
        let timeText = item.lastSeenAt.formatted(.relative(presentation: .named))
        return "\(timeText) · \(NSLocalizedString(labelKey, comment: ""))"
    }

    /// "位置变了…" 展开的行内编辑器(逻辑同 macOS:parseLocationOnly + ensure + log)。
    private var locationEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("detail.used.location.placeholder", text: $locationDraft)
                .textFieldStyle(.roundedBorder)
                .focused($locationFocused)
                .onSubmit(saveNewLocation)
            let preview = InputParser.parseLocationOnly(locationDraft)
            if !preview.isEmpty {
                Label {
                    Text(verbatim: preview.joined(separator: " › "))
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Button("detail.used.button.saveLocation", action: saveNewLocation)
                .buttonStyle(.borderedProminent)
                .tint(IOSTheme.actionOrange)
                .controlSize(.small)
                .disabled(preview.isEmpty)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
    }

    // MARK: - 时间线卡(LocationLog + EditLog 合并倒序,同 macOS)

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

    private var combinedHistory: [HistoryEntry] {
        var entries: [HistoryEntry] = item.locationHistory.map { .location($0) }
        entries += item.editHistory.map { .edit($0) }
        return entries.sorted { $0.recordedAt > $1.recordedAt }
    }

    @State private var historyExpanded = false

    private var historyCard: some View {
        let entries = combinedHistory
        let current = item.locationHistory.sorted { $0.recordedAt > $1.recordedAt }.first
        let visible = historyExpanded ? entries : Array(entries.prefix(3))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                Text("detail.history.title").font(.headline)
                Spacer()
                if !entries.isEmpty {
                    Text("detail.history.count \(entries.count)")
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: .capsule)
                }
            }
            if entries.isEmpty {
                Text("detail.history.empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { idx, entry in
                        let isLast = idx == visible.count - 1
                        switch entry {
                        case .location(let log):
                            timelineRow(dotColor: log === current ? IOSTheme.accent : .secondary,
                                        filled: log === current, isLast: isLast) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(log.location?.path ?? String(localized: "location.unspecified"))
                                            .font(.subheadline)
                                            .foregroundStyle(log === current ? .primary : .secondary)
                                        if log === current {
                                            Text("detail.history.currentTag")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1.5)
                                                .background(IOSTheme.accent.opacity(0.15), in: .capsule)
                                                .foregroundStyle(IOSTheme.accent)
                                        }
                                    }
                                    Text(verbatim: relativeDate(log.recordedAt))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        case .edit(let log):
                            timelineRow(dotColor: editSourceColor(log.source),
                                        filled: false, isLast: isLast) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(editFieldLabel(log.field))
                                            .font(.caption2.weight(.medium))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1.5)
                                            .background(Color.secondary.opacity(0.12), in: .capsule)
                                        Text(editSourceLabel(log.source))
                                            .font(.caption2)
                                            .foregroundStyle(editSourceColor(log.source))
                                        // Phase 120:AI 改名且仍生效 → ↩ 还原(同 macOS)
                                        if shouldShowRestoreButton(for: log) {
                                            Spacer(minLength: 0)
                                            Button {
                                                restoreNameFromLog(log)
                                            } label: {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "arrow.uturn.backward")
                                                    Text("row.ai.revert")
                                                }
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.orange.opacity(0.16), in: .capsule)
                                                .foregroundStyle(.orange)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
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
                                    }
                                    Text(verbatim: relativeDate(log.recordedAt))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
                if entries.count > 3 {
                    Button {
                        withAnimation(.snappy) { historyExpanded.toggle() }
                    } label: {
                        Label(historyExpanded ? "action.collapse" : "action.expandAll",
                              systemImage: historyExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .iosCard()
    }

    /// 时间线行骨架:左侧点 + 竖线,右侧内容。
    @ViewBuilder
    private func timelineRow<Content: View>(
        dotColor: Color, filled: Bool, isLast: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .stroke(dotColor, lineWidth: 1.5)
                        .frame(width: 9, height: 9)
                    if filled {
                        Circle().fill(dotColor).frame(width: 5, height: 5)
                    }
                }
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.22))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            .padding(.top, 4)
            content()
            Spacer(minLength: 0)
        }
    }

    /// Phase 120:这条 EditLog 该显示「还原」吗?(判定与 macOS 一致)
    private func shouldShowRestoreButton(for log: EditLog) -> Bool {
        guard log.field == "name",
              log.source.hasPrefix("ai_"),
              let old = log.oldValue, !old.isEmpty,
              let new = log.newValue else { return false }
        return item.name == new
    }

    /// 还原名字 + 写 source="restore" 的 EditLog。
    private func restoreNameFromLog(_ log: EditLog) {
        guard let old = log.oldValue, !old.isEmpty else { return }
        let snap = ItemFieldSnapshot(item)
        item.name = old
        item.updatedAt = .now
        snap.recordEdits(against: item, source: "restore", in: modelContext)
        Haptics.success()
        flashAck(String(localized: "row.ai.reverted"))
    }

    private func editFieldLabel(_ field: String) -> LocalizedStringKey {
        switch field {
        case "name":           return "meta.label.name"
        case "model":          return "meta.label.model"
        case "version":        return "meta.label.version"
        case "color":          return "meta.label.color"
        case "purchaseDate":   return "meta.label.purchase"
        case "purchaseSource": return "meta.label.source"
        case "notes":          return "edit.field.notes"
        case "lent":           return "history.field.lent"
        case "returned":       return "history.field.returned"
        default:               return "history.field.unknown"
        }
    }

    private func editSourceLabel(_ source: String) -> LocalizedStringKey {
        switch source {
        case "ai_claude":     return "history.source.aiClaude"
        case "ai_volcengine": return "history.source.aiVolc"
        case "parser":        return "history.source.parser"
        case "update_intent": return "history.source.updateIntent"
        case "batch":         return "history.source.batch"
        case "manual":        return "history.source.manual"
        case "restore":       return "history.source.restore"
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
        case "lent_out":                   return .purple
        case "returned":                   return .orange
        default:                           return .secondary
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let interval = Date.now.timeIntervalSince(date)
        if interval < 60 { return String(localized: "time.justNow") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        if interval < 7 * 24 * 3600 {
            return formatter.localizedString(for: date, relativeTo: .now)
        } else {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
    }

    // MARK: - 关联物品卡

    @ViewBuilder
    private var relatedCard: some View {
        let peers = RelatedGroup.peers(of: item, in: modelContext)
        if !peers.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                    Text("related.section.title \(peers.count + 1) \(RelatedGroup.maxGroupSize)")
                        .font(.headline)
                }
                ForEach(peers) { peer in
                    NavigationLink {
                        IOSItemDetailView(item: peer)
                    } label: {
                        HStack(spacing: 10) {
                            ItemThumb(item: peer, size: 36, cornerRadius: 9)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(peer.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                if let path = peer.location?.path {
                                    Text(verbatim: path)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .iosCard()
        }
    }

    // MARK: - 元信息卡 + 删除

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            metaRow(label: "detail.meta.lastSeen", date: item.lastSeenAt)
            metaRow(label: "detail.meta.created", date: item.createdAt)
            if !item.notes.isEmpty {
                Text("detail.meta.notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Text(item.notes).font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .iosCard()
    }

    private func metaRow(label: LocalizedStringKey, date: Date) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showingDeleteConfirm = true
        } label: {
            Label("detail.button.delete", systemImage: "trash")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.red.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func confirmStillHere(actionType: String) {
        item.lastSeenAt = .now
        item.updatedAt = .now
        item.lastActionType = actionType
        modelContext.insert(LocationLog(recordedAt: .now, location: item.location, item: item))
        flashAck(String(localized: "detail.used.ack.kept"))
    }

    private func saveNewLocation() {
        let path = InputParser.parseLocationOnly(locationDraft)
        guard !path.isEmpty else { return }
        let newLoc = Location.ensure(path: path, in: modelContext)
        item.location = newLoc
        item.lastSeenAt = .now
        item.updatedAt = .now
        item.lastActionType = "moved"
        modelContext.insert(LocationLog(recordedAt: .now, location: newLoc, item: item))
        withAnimation(.snappy) { editingLocation = false }
        locationDraft = ""
        Haptics.success()
        flashAck(String(localized: "detail.used.ack.moved"))
    }

    private func flashAck(_ text: String) {
        withAnimation { ackText = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation { ackText = nil }
            }
        }
    }
}

// MARK: - 全屏照片查看

struct IOSPhotoZoom: View {
    let image: Image
    let dismiss: () -> Void
    /// 双指捏合缩放(1x–4x),松手回弹到范围内。
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                image
                    .resizable()
                    .scaledToFit()
                    .containerRelativeFrame(.horizontal)
                    .scaleEffect(scale * pinch)
            }
            .defaultScrollAnchor(.center)
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in
                        state = value.magnification
                    }
                    .onEnded { value in
                        scale = min(max(scale * value.magnification, 1), 4)
                    }
            )
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white, .black.opacity(0.45))
                    .padding(16)
            }
            .buttonStyle(.plain)
        }
    }
}
