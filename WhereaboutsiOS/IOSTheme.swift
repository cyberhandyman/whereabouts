import SwiftUI
#if os(iOS)
import UIKit
#endif

// Phase 111:iOS 版设计系统 —— 比 macOS 版更"高级 / 科技感"的视觉基建。
// 设计语言:
//   - 品牌渐变:靛蓝 → 电光蓝(indigo → cyan),用在 hero、强调按钮、图标底座
//   - 卡片:大圆角(20pt continuous)+ 次级底色 + 发丝描边 + 极轻投影
//   - 数字:SF Rounded + monospacedDigit,统计瓷砖有"仪表盘"感
//   - 触觉:轻点 / 成功两档 haptic,录入成功给正反馈

enum IOSTheme {

    // MARK: - 品牌色

    /// 主品牌色(靛蓝)。TabView tint / 链接色 / 选中态都用它。
    static let accent = Color(red: 0.35, green: 0.36, blue: 0.95)

    /// 副品牌色(电光蓝)。渐变的另一端。
    static let accentAlt = Color(red: 0.12, green: 0.62, blue: 0.98)

    /// 品牌渐变 —— hero 区、主按钮、图标底座。
    static let gradient = LinearGradient(
        colors: [accent, accentAlt],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 更含蓄的一版渐变(低饱和),用于页面背景顶部的氛围光。
    static let ambientGradient = LinearGradient(
        colors: [accent.opacity(0.16), accentAlt.opacity(0.05), .clear],
        startPoint: .top,
        endPoint: .bottom
    )

    /// 页面背景:系统分组底色打底 + 顶部一层品牌氛围光。
    /// 用法:`.background(IOSTheme.pageBackground)`。
    static var pageBackground: some View {
        ZStack {
            Color(.systemGroupedBackground)
            ambientGradient
                .frame(maxHeight: 360)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
    }

    /// "用过吗?" 动作色带(跟 macOS 详情页一致的渐进语义色)。
    static let actionMint   = Color.mint
    static let actionBlue   = Color.blue
    static let actionOrange = Color.orange
    static let actionRed    = Color.red
    static let actionPurple = Color.purple
}

// MARK: - 卡片容器

/// 统一的卡片外观:大圆角 + 次级底色 + 发丝描边 + 轻投影。
/// 列表行 / 统计瓷砖 / 详情分区都套它,整个 app 一套皮肤。
struct IOSCard: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.quaternary.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

extension View {
    /// `.iosCard()` —— 见 IOSCard。
    func iosCard(padding: CGFloat = 16, cornerRadius: CGFloat = 20) -> some View {
        modifier(IOSCard(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - 触觉反馈

enum Haptics {
    /// 轻点(chip 选中 / 次级按钮)。
    static func tap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// 成功(录入完成 / 归还完成)。
    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// 警告(删除 / 失败)。
    static func warning() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}

// MARK: - 通用小组件

/// 渐变底座 + 白色 SF Symbol 的方形图标 —— 设置行 / 统计瓷砖 / 空状态都用。
struct GradientIconTile: View {
    let systemName: String
    var size: CGFloat = 34
    var cornerRadius: CGFloat = 9
    var gradient: LinearGradient = IOSTheme.gradient

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(gradient)
            Image(systemName: systemName)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// 物品缩略图:有照片显示照片,没照片显示品牌渐变 + 盒子图标的占位。
/// 列表行 44pt / 详情页可放大尺寸复用。
struct ItemThumb: View {
    let item: Item
    var size: CGFloat = 46
    var cornerRadius: CGFloat = 12

    var body: some View {
        Group {
            if let data = item.photoData, let img = Image(data: data) {
                img
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    IOSTheme.gradient.opacity(0.85)
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: size * 0.42, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.6), lineWidth: 0.5)
        )
    }
}

/// 首页顶部的统计瓷砖:渐变图标 + 大数字(SF Rounded)+ 小标题。
/// Phase 120 起兼作筛选器:`selected` 时描边高亮 + 底色染色;
/// `detailText` 显示当前选中的筛选值(如房间名),替换掉数字行。
struct StatTile: View {
    let value: Int
    let captionKey: LocalizedStringKey
    let systemName: String
    var tint: Color = IOSTheme.accent
    var selected: Bool = false
    var detailText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GradientIconTile(
                systemName: systemName,
                size: 30,
                cornerRadius: 8,
                gradient: LinearGradient(colors: [tint, tint.opacity(0.65)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            if let detailText {
                Text(verbatim: detailText)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(tint)
            } else {
                Text(verbatim: "\(value)")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Text(captionKey)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 92, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(selected ? tint.opacity(0.12) : Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? tint : Color(.quaternaryLabel).opacity(0.5),
                              lineWidth: selected ? 1.5 : 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        .contentShape(Rectangle())
    }
}

/// 横向滚动的 facet 胶囊 chip(选中 = 品牌实色,未选 = 灰底)。
struct FacetChip: View {
    let label: String
    let count: Int?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 5) {
                Text(verbatim: label)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                if let count {
                    Text(verbatim: "\(count)")
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? AnyShapeStyle(IOSTheme.gradient)
                                   : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.quaternary.opacity(selected ? 0 : 0.6), lineWidth: 0.5)
            )
            .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
