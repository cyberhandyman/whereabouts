import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Phase 111(iOS 版):ExportSchema + WhereaboutsExportDocument 从 ContentView.swift
// 挪到这里 —— iOS 设置页的导出 / 导入用同一套 schema,macOS / iOS 两个 target 都编译本文件。

/// 整库导出的 JSON schema。版本号用于将来格式演进时识别。
///
/// **包含什么**:Item 全部字段、位置路径(摊平成字符串数组)、位置历史、照片 base64。
/// **不包含**:SwiftData 的 PersistentIdentifier 等内部 ID。导入端按 name + path 重建。
///
/// internal scope(去 private)— SettingsView 的 import 路径要用同一个 schema 反序列化。
struct ExportSchema: Codable {
    let exportedAt: Date
    let appVersion: String
    /// Phase 90:bump 到 2 —— 加了 tags / lentTo / lentAt / relatedGroupID / isPinned。
    /// 老 v1 文件用 Decoder 读时,新字段都是 optional 默认 nil,**向后兼容**。
    let schemaVersion: Int
    let items: [ExportItem]

    struct ExportItem: Codable {
        let name: String
        let notes: String
        let createdAt: Date
        let updatedAt: Date
        let lastSeenAt: Date
        let locationPath: [String]
        let model: String?
        let version: String?
        let color: String?
        let purchaseDate: Date?
        let purchaseDatePrecision: String?
        let purchaseSource: String?
        /// JPEG 压缩后的照片 base64。可选 —— 没照片就 nil,体积小。
        let photoBase64: String?
        let history: [ExportLog]
        // Phase 90:新增字段。可选 —— 老 v1 文件没有就是 nil。
        let tags: [String]?
        let lentTo: String?
        let lentAt: Date?
        let isPinned: Bool?
        let relatedGroupID: String?  // UUID 字符串
    }

    struct ExportLog: Codable {
        let recordedAt: Date
        let locationPath: [String]
    }
}

/// SwiftUI fileExporter 用的 FileDocument。
/// 构造时同步 encode 整库 → JSON,所以构造耗时跟数据量正相关 —— 在按钮 action 里 lazily 创建,
/// 避免 view body redraw 反复编码。
struct WhereaboutsExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    private let data: Data

    init(items: [Item]) {
        // 拆 location 树成扁平 path:["客厅", "茶几"]。导入端按这个顺序 ensure(path:)。
        func path(of loc: Location?) -> [String] {
            guard let loc else { return [] }
            var parts: [String] = [loc.name]
            var cursor = loc.parent
            while let p = cursor {
                parts.append(p.name)
                cursor = p.parent
            }
            return parts.reversed()
        }

        let exported: [ExportSchema.ExportItem] = items.map { item in
            ExportSchema.ExportItem(
                name: item.name,
                notes: item.notes,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                lastSeenAt: item.lastSeenAt,
                locationPath: path(of: item.location),
                model: item.model,
                version: item.version,
                color: item.color,
                purchaseDate: item.purchaseDate,
                purchaseDatePrecision: item.purchaseDatePrecision,
                purchaseSource: item.purchaseSource,
                photoBase64: item.photoData?.base64EncodedString(),
                history: item.locationHistory
                    .sorted(by: { $0.recordedAt < $1.recordedAt })
                    .map { log in
                        ExportSchema.ExportLog(
                            recordedAt: log.recordedAt,
                            locationPath: path(of: log.location)
                        )
                    },
                // Phase 90:tag names(用名字反查比 UUID 稳)+ lent + pin + related
                tags: item.tags.isEmpty ? nil : item.tags.map(\.name),
                lentTo: item.lentTo,
                lentAt: item.lentAt,
                isPinned: item.isPinned ? true : nil,
                relatedGroupID: item.relatedGroupID?.uuidString
            )
        }

        let schema = ExportSchema(
            exportedAt: .now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
            schemaVersion: 2,
            items: exported
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        self.data = (try? encoder.encode(schema)) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        guard let d = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = d
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    /// 导出的 JSON 原始数据 —— iOS 走 ShareLink / 临时文件路径时直接用。
    var rawData: Data { data }

    /// 默认文件名,带 ISO 日期。SavePanel 仍允许用户改。
    static func defaultFilename() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return "whereabouts-export-\(f.string(from: .now))"
    }
}
