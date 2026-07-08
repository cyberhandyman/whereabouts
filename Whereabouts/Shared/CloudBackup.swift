import Foundation
import SwiftData

// Phase 117:iCloud 云盘 JSON 自动备份 —— 双端共用。
//
// 跟 CloudKit 同步是两条互补的路:
//   - CloudKit 同步 = 实时、逐条、不可见
//   - 这里 = 整库 JSON 快照落到 iCloud Drive/Whereabouts/,用户在"文件"app / 访达
//     里**看得见摸得着**,可手动拿去导入 / 归档 / 换设备兜底
// 触发:app 退到后台(iOS)/ 退出(macOS)时自动写一份;设置页也有"立即备份"按钮。
// 只保留一个滚动的 latest 文件,避免无限膨胀(带日期的历史归档交给用户手动导出)。

enum CloudBackup {

    private static let lastDateKey = "cloudBackup.lastDate"

    /// iCloud Drive 里我们的 Documents 目录(= 用户看到的 iCloud 云盘/Whereabouts/)。
    /// 未登录 iCloud / 关了 iCloud 云盘 → nil。
    /// ⚠️ 首次调用可能触发磁盘 IO,别在主线程调 —— 调用方都走后台 Task。
    static func folderURL() -> URL? {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        let docs = container.appending(path: "Documents", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        return docs
    }

    /// 上次成功备份时间(设置页显示)。
    static var lastBackupDate: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: lastDateKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: lastDateKey)
        }
    }

    /// 整库备份成 `whereabouts-backup.json`(复用导出 schema,含照片 base64)。
    /// 成功返回 true。UI 按钮 / iOS 退后台走这个 async 版(写盘在后台线程)。
    @MainActor
    static func backUp(context: ModelContext) async -> Bool {
        guard let data = exportData(context: context) else { return false }
        let ok: Bool = await Task.detached(priority: .utility) { write(data) }.value
        if ok { lastBackupDate = .now }
        return ok
    }

    /// Phase 118:**手动同步** —— pull + merge + push 三步:
    ///   ① 读 iCloud 云盘里其它设备写的 JSON → 按 name+位置 去重导入本机
    ///   ② 把合并后的本机全量写回同一文件
    /// 返回 (成功?, 合并进来的条数)。CloudKit 实时同步之外的兜底通道,
    /// 也让"下拉刷新"有实打实的语义。
    @MainActor
    static func sync(context: ModelContext) async -> (ok: Bool, merged: Int) {
        // ① pull(文件不存在不算失败 —— 可能是第一台设备)
        var merged = 0
        let fileData: Data? = await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let dir = folderURL() else { return nil }
            let url = dir.appending(path: "whereabouts-backup.json")
            // iCloud 占位文件(未下载)先触发下载
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return try? Data(contentsOf: url)
        }.value
        if let fileData,
           let result = WhereaboutsImporter.importJSON(fileData, into: context, dedup: true) {
            merged = result.imported
        }
        // ② push(把合并后的全量写回)
        let ok = await backUp(context: context)
        return (ok, merged)
    }

    /// 同步版 —— macOS 退出通知里用(quit 时没有跑 async 的机会,阻塞几百毫秒可接受)。
    @MainActor
    static func backUpBlocking(context: ModelContext) {
        guard let data = exportData(context: context) else { return }
        if write(data) { lastBackupDate = .now }
    }

    @MainActor
    private static func exportData(context: ModelContext) -> Data? {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate<Item> { !$0.isDeleted })
        guard let items = try? context.fetch(descriptor), !items.isEmpty else { return nil }
        let data = WhereaboutsExportDocument(items: items).rawData
        return data.isEmpty ? nil : data
    }

    private static func write(_ data: Data) -> Bool {
        guard let dir = folderURL() else { return false }
        do {
            try data.write(to: dir.appending(path: "whereabouts-backup.json"), options: .atomic)
            return true
        } catch {
            NSLog("[Whereabouts] iCloud Drive backup failed: %@", String(describing: error))
            return false
        }
    }
}
