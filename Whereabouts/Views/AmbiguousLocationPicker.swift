import SwiftUI
import SwiftData

/// Phase 17:用户在歧义 sheet 里点了某个按钮后的两种走向。
/// 用 enum 显式表达,而不是把 Location? 当返回值,避免误判 nil 含义。
enum AmbiguousChoice {
    case existing(Location)   // 复用某条已有同名叶子
    case newTopLevel          // 还是建新顶层 —— 跟旧行为一致
}

/// 输入里给的"单段位置"(例:"抽屉第一层")在库里撞上多个同名叶子时弹的 sheet。
/// 把所有候选用整条祖先链("家 > 卧室 > 抽屉第一层")展示;
/// 用户挑一个或选择"新建顶层"。
struct AmbiguousLocationPicker: View {
    @Environment(\.dismiss) private var dismiss

    let context: PendingAmbiguousLocation
    /// 回调:用户做完选择后调用,把决定送回 ContentView 落库。
    let onResolve: (AmbiguousChoice) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("ambiguousLocation.message \(context.originalLeaf) \(context.candidates.count)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(context.candidates, id: \.persistentModelID) { loc in
                        Button {
                            onResolve(.existing(loc))
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundStyle(.secondary)
                                // loc.path 是用户数据,verbatim 显示
                                Text(verbatim: loc.path)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section {
                    Button {
                        onResolve(.newTopLevel)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(Color.accentColor)
                            Text("ambiguousLocation.button.newTopLevel \(context.originalLeaf)")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("ambiguousLocation.title")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, idealWidth: 480, minHeight: 280, idealHeight: 360)
    }
}
