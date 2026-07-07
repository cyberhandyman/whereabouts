import SwiftUI

/// 9 个 Finder 风预设色的横向选色器。
///
/// 旧版用 SwiftUI Menu —— 但 macOS NSMenu 把 menu item 的 systemImage 渲染成 template,
/// 颜色全被剥掉,用户只能看到一堆"灰圆点 + 颜色名"。这个组件直接画彩色圆,点击即选,
/// 1 click 而不是 2 click,并且立刻看到选中态(粗描边)。
///
/// 用法:
///   TagColorPicker(selected: $tag.colorHex)
struct TagColorPicker: View {
    @Binding var selected: String
    /// 圆点直径。Settings 行用 14;ItemEditView 新标签区可以稍大些。
    var diameter: CGFloat = 14
    /// 圆点间距。
    var spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(TagPalette.all, id: \.hex) { (name, hex) in
                swatch(name: name, hex: hex)
            }
        }
    }

    private func swatch(name: String, hex: String) -> some View {
        let isSelected = selected.lowercased() == hex.lowercased()
        return Button {
            selected = hex
        } label: {
            Circle()
                .fill(Color(tagHex: hex))
                .frame(width: diameter, height: diameter)
                .overlay(
                    // 选中态:粗的 primary 描边 + 内部白色对勾。
                    // 未选:细的灰描边,跟周围视觉一致。
                    Circle()
                        .stroke(
                            isSelected ? Color.primary : Color.secondary.opacity(0.3),
                            lineWidth: isSelected ? 2 : 0.5
                        )
                )
                .overlay(
                    Group {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: diameter * 0.5, weight: .heavy))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.3), radius: 0.5)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .help(name)  // 鼠标悬停显示 "gray" / "red" 等
    }
}
