import Foundation
import SwiftData
#if os(iOS)
import UIKit
#endif

// Phase 117:iCloud 云盘 JSON 自动备份 —— 双端共用。
//
// 跟 CloudKit 同步是两条互补的路:
//   - CloudKit 同步 = 实时、逐条、不可见(CloudSyncMonitor 负责可观测)
//   - 这里 = 整库 JSON 快照落到 iCloud Drive/Whereabouts/,用户在"文件"app / 访达
//     里**看得见摸得着**,可手动拿去导入 / 归档 / 换设备兜底
// 触发:app 退到后台(iOS)/ 退出(macOS)时自动写一份;设置页也有"立即备份"按钮。
//
// Phase 122 改动(数据安全):
//   - **不再自动拉取合并**。Phase 118 的"手动同步 = 拉 JSON + 按 name@位置 去重导入"
//     与 CloudKit 是两套身份:被删的物品会被 JSON 里的旧副本复活,移动 / 改名过的物品
//     会多出一份,再经 CloudKit 扩散到所有设备。现在 JSON 只写不读;要从备份恢复,
//     走设置 → 数据 → 导入,用户自己挑文件。
//   - **每台设备写自己的文件**(whereabouts-backup-iPhone-3F2A.json)。原来所有设备
//     共用一个文件,刚装好、数据还没同步下来的新设备一退后台就会用几条数据覆盖掉
//     Mac 写的完整备份。
//   - Debug 构建写 debug- 前缀的文件,开发测试永远碰不到正式备份。

enum CloudBackup {

    private static let lastDateKey = "cloudBackup.lastDate"
    private static let deviceIDKey = "cloudBackup.deviceID"
    /// Phase 122:上次备份时库的"指纹"(条数 + 最近修改时间 + 标签/位置数)。
    /// 自动备份(退后台 / 退出)发现没变化就跳过 —— 原来每次切后台都把含照片的整库
    /// 重新编码、重新上传 iCloud 云盘,费电费流量。
    private static let lastSignatureKey = "cloudBackup.lastSignature"

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

    /// 本机备份文件名:whereabouts-backup-<设备类型>-<4 位本机标识>.json。
    /// 标识是首次备份时随机生成并记在本机偏好里的,重装 app 会换一个(旧文件留着无害)。
    /// 必须在主线程算好再交给后台写(UIDevice 是 MainActor)。
    @MainActor
    static var fileName: String {
        let id: String
        if let saved = UserDefaults.standard.string(forKey: deviceIDKey), !saved.isEmpty {
            id = saved
        } else {
            id = String(UUID().uuidString.prefix(4))
            UserDefaults.standard.set(id, forKey: deviceIDKey)
        }
        #if os(iOS)
        let kind = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #else
        let kind = "Mac"
        #endif
        #if DEBUG
        return "debug-whereabouts-backup-\(kind)-\(id).json"
        #else
        return "whereabouts-backup-\(kind)-\(id).json"
        #endif
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

    /// 整库备份成本机的 JSON 文件(复用导出 schema,含照片 base64)。
    /// 成功返回 true。UI 按钮 / iOS 退后台走这个 async 版(写盘在后台线程)。
    /// `onlyIfChanged`:自动备份传 true,库没变化就跳过(返回 true);手动"立即备份"传 false。
    @MainActor
    static func backUp(context: ModelContext, onlyIfChanged: Bool = false) async -> Bool {
        #if os(iOS)
        // 退后台时系统只给几秒:**先**申请后台时间(导出编码照片本身就要时间),
        // 并在时间耗尽时立刻结束任务 —— 不结束的话系统会直接杀掉 app。
        let bg = BackgroundTaskBox()
        bg.id = UIApplication.shared.beginBackgroundTask(withName: "whereabouts.backup") {
            bg.end()
        }
        defer { bg.end() }
        #endif
        let signature = librarySignature(context: context)
        if onlyIfChanged, let signature,
           signature == UserDefaults.standard.string(forKey: lastSignatureKey) {
            return true
        }
        guard let data = exportData(context: context) else { return false }
        let name = fileName
        let ok: Bool = await Task.detached(priority: .utility) { write(data, name: name) }.value
        if ok {
            lastBackupDate = .now
            UserDefaults.standard.set(signature, forKey: lastSignatureKey)
        }
        return ok
    }

    /// 同步版 —— macOS 退出时用(quit 时没有跑 async 的机会)。
    /// 写盘放到后台线程、最多等 3 秒:iCloud 云盘的文件协调偶尔会卡住,不能让退出跟着卡死。
    /// 超时就放弃这次(原子写,不会留下半个文件)。
    @MainActor
    static func backUpBlocking(context: ModelContext) {
        let signature = librarySignature(context: context)
        if let signature, signature == UserDefaults.standard.string(forKey: lastSignatureKey) { return }
        guard let data = exportData(context: context) else { return }
        let name = fileName
        let result = WriteResultBox()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            result.ok = write(data, name: name)
            done.signal()
        }
        if done.wait(timeout: .now() + 3) == .success, result.ok {
            lastBackupDate = .now
            UserDefaults.standard.set(signature, forKey: lastSignatureKey)
        }
    }

    /// 库的粗粒度指纹:未删物品数 + 最近一次修改时间 + 标签数 + 位置数。
    @MainActor
    private static func librarySignature(context: ModelContext) -> String? {
        let live = #Predicate<Item> { $0.deletedAt == nil }
        guard let count = try? context.fetchCount(FetchDescriptor<Item>(predicate: live)) else { return nil }
        var latest = FetchDescriptor<Item>(predicate: live, sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        latest.fetchLimit = 1
        let newest = (try? context.fetch(latest))?.first?.updatedAt.timeIntervalSince1970 ?? 0
        let tags = (try? context.fetchCount(FetchDescriptor<Tag>())) ?? 0
        let locs = (try? context.fetchCount(FetchDescriptor<Location>())) ?? 0
        return "\(count)|\(newest)|\(tags)|\(locs)"
    }

    /// 空库不写 —— 新设备在 CloudKit 数据下来之前是空的,写了就是一份没用的空备份。
    /// 内存兜底库(本地库打不开)也不写,免得用残缺数据覆盖本机正常的备份。
    @MainActor
    private static func exportData(context: ModelContext) -> Data? {
        guard !AppContainer.usingInMemoryFallback else { return nil }
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.deletedAt == nil })
        guard let items = try? context.fetch(descriptor), !items.isEmpty else { return nil }
        let data = WhereaboutsExportDocument(items: items).rawData
        return data.isEmpty ? nil : data
    }

    private static func write(_ data: Data, name: String) -> Bool {
        guard let dir = folderURL() else { return false }
        let url = dir.appending(path: name)
        // iCloud 云盘里的文件要经 NSFileCoordinator 写,iCloud 守护进程才能正确感知、上传。
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing,
                                                         error: &coordError) { target in
            do {
                try data.write(to: target, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let err = coordError ?? writeError {
            NSLog("[Whereabouts] iCloud Drive backup failed: %@", String(describing: err))
            return false
        }
        return true
    }
}

/// backUpBlocking 里跨线程回传写盘结果用(semaphore 保证读写不重叠)。
private final class WriteResultBox: @unchecked Sendable {
    var ok = false
}

#if os(iOS)
/// 后台任务 id 的小盒子:过期回调和 defer 都要能把它结束掉,且只结束一次。
private final class BackgroundTaskBox: @unchecked Sendable {
    var id: UIBackgroundTaskIdentifier = .invalid
    @MainActor func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
#endif
