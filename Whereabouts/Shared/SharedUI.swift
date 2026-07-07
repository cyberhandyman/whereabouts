import SwiftUI
import ImageIO
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
typealias PlatformImage = NSImage
#endif

// Phase 111(iOS 版):跨平台 UI 基建从 ItemDetailView.swift 挪到这里 ——
// macOS / iOS 两个 target 都编译本文件;ItemDetailView 只进 macOS target。

/// 从 Data 直接构造 Image(SwiftUI 没原生 API,iOS 和 macOS 的桥接不同)。
extension Image {
    init?(data: Data) {
        guard let img = PlatformImage(data: data) else { return nil }
#if os(iOS)
        self.init(uiImage: img)
#elseif os(macOS)
        self.init(nsImage: img)
#endif
    }
}

/// 用 ImageIO 把原图缩到长边 ≤ maxDimension,输出 JPEG。
/// thumbnail 模式不会先解码整张大图,内存友好。1024+0.85 在视觉上几乎无损,文件压到 100-300KB。
enum ImageHelpers {
    static func compressed(data: Data, maxDimension: Int = 1024, quality: CGFloat = 0.85) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}

/// 真正的 flow / wrap 布局:subview 自己的尺寸由它决定(用 .fixedSize 防止内部折行),
/// 父容器宽度够就横排,装不下就把整个 subview 推到下一行。
/// SwiftUI 14+ 的 Layout 协议实现,没有外部依赖。
struct WrapLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalMaxX: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalMaxX = max(totalMaxX, x - spacing)
        }
        return CGSize(width: min(totalMaxX, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
