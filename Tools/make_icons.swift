#!/usr/bin/env swift
// 生成 AppIcon 全套尺寸 PNG。
// 输出两套:
//   1. <iconsetDir>/icon_*.png  —— 用于 iconutil 打包成 AppIcon.icns(macOS)
//   2. <appiconsetDir>/icon-ios-1024.png —— Asset Catalog 里给 iOS 用
//
// 设计:warm amber 圆角方背景(仅 mac)+ 大写白色 "何" 字。
// 用法: swift Tools/make_icons.swift <iconset-dir> <appiconset-dir>

import Foundation
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("Usage: make_icons.swift <iconset-dir> <appiconset-dir>")
    exit(1)
}
let iconsetDir = args[1]
let appiconsetDir = args[2]
let glyph = "何"

let bgColor = NSColor(srgbRed: 232/255, green: 157/255, blue: 52/255, alpha: 1.0)   // warm amber #E89D34
let fgColor = NSColor(srgbRed: 1.0,     green: 1.0,     blue: 1.0,     alpha: 1.0)   // white

func renderIcon(size: Int, macStyle: Bool) -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { fatalError("Failed to create bitmap") }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let s = CGFloat(size)
    let canvasRect: NSRect
    let cornerRadius: CGFloat
    if macStyle {
        let inset = s * 0.0975
        canvasRect = NSRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset)
        cornerRadius = canvasRect.width * 0.2237
    } else {
        canvasRect = NSRect(x: 0, y: 0, width: s, height: s)
        cornerRadius = 0
    }

    let bgPath = cornerRadius > 0
        ? NSBezierPath(roundedRect: canvasRect, xRadius: cornerRadius, yRadius: cornerRadius)
        : NSBezierPath(rect: canvasRect)
    bgColor.setFill()
    bgPath.fill()

    let fontSize = canvasRect.height * 0.70
    let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fgColor]
    let str = NSAttributedString(string: glyph, attributes: attrs)

    let line = CTLineCreateWithAttributedString(str as CFAttributedString)
    let inkBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    let drawOriginX = canvasRect.midX - inkBounds.midX
    let drawOriginY = canvasRect.midY - inkBounds.midY
    NSGraphicsContext.current?.cgContext.textPosition = CGPoint(x: drawOriginX, y: drawOriginY)
    CTLineDraw(line, NSGraphicsContext.current!.cgContext)

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed")
    }
    return data
}

let fm = FileManager.default
// iconutil 要求 .iconset 目录里文件用 Apple 规定的名字
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
try? fm.createDirectory(atPath: appiconsetDir, withIntermediateDirectories: true)

let macSizes: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (pixel, fname) in macSizes {
    let data = renderIcon(size: pixel, macStyle: true)
    let path = "\(iconsetDir)/\(fname)"
    try data.write(to: URL(fileURLWithPath: path))
    print("✓ \(path)  (\(pixel)x\(pixel))")
}

// iOS full-bleed 1024
let iosData = renderIcon(size: 1024, macStyle: false)
let iosPath = "\(appiconsetDir)/icon-ios-1024.png"
try iosData.write(to: URL(fileURLWithPath: iosPath))
print("✓ \(iosPath)  (1024x1024, full-bleed)")

print("Done.")
