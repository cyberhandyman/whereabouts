import SwiftUI
import SwiftData

// Phase 118:iOS 标签管理 —— 对齐 macOS 的 TagsSettingsTab:
// 改名(行内 TextField)、改色(TagColorPicker 调色板)、删除(左滑,nullify 不删物品)、
// 新建(底部输入行,自动挑未用过的预设色)。

struct IOSTagsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.createdAt) private var allTags: [Tag]

    @State private var newTagName = ""
    @State private var newTagColorHex: String = TagPalette.all[0].hex

    var body: some View {
        Form {
            Section {
                if allTags.isEmpty {
                    Text("settings.tags.empty")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(allTags) { tag in
                        IOSTagRow(tag: tag)
                    }
                    .onDelete { offsets in
                        for i in offsets { modelContext.delete(allTags[i]) }
                        Haptics.warning()
                    }
                }
            } header: {
                Text("settings.tags.header")
            } footer: {
                Text("settings.tags.delete.tooltip")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    TagColorPicker(selected: $newTagColorHex, diameter: 22, spacing: 8)
                    HStack(spacing: 8) {
                        TextField("tag.new.placeholder", text: $newTagName)
                            .onSubmit(addNewTag)
                        Button("tag.new.button", action: addNewTag)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("tag.section.header")
            }
        }
        .navigationTitle("ios.tags.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { newTagColorHex = nextUnusedPaletteHex() }
    }

    /// 挑下一个"还没被占用"的预设颜色(逻辑同 macOS ItemEditView)。
    private func nextUnusedPaletteHex() -> String {
        let used = Set(allTags.map { $0.colorHex.lowercased() })
        if let next = TagPalette.all.first(where: { !used.contains($0.hex.lowercased()) }) {
            return next.hex
        }
        return TagPalette.all[allTags.count % TagPalette.all.count].hex
    }

    private func addNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 同名直接忽略(不重复建)
        guard !allTags.contains(where: { $0.name == trimmed }) else {
            newTagName = ""
            return
        }
        modelContext.insert(Tag(name: trimmed, colorHex: newTagColorHex))
        newTagName = ""
        newTagColorHex = nextUnusedPaletteHex()
        Haptics.success()
    }
}

/// 单行:调色板 + 名字 TextField + 挂载数。
private struct IOSTagRow: View {
    @Bindable var tag: Tag

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TagColorPicker(selected: $tag.colorHex, diameter: 18, spacing: 6)
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(tagHex: tag.colorHex))
                    .frame(width: 12, height: 12)
                TextField("settings.tags.name.label", text: $tag.name)
                Spacer(minLength: 4)
                Text("settings.tags.row.itemCount \(tag.items.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
