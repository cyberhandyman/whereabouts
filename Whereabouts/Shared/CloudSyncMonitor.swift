import Foundation
import SwiftData
import CoreData
import CloudKit
import CryptoKit
import Observation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// Phase 122:iCloud 同步可观测 + 当前 iCloud 账号显示 —— 双端共用。
//
// 背景(用户反馈 Mac ↔ iPhone "很久才同步")排查出三条根因:
//   ① iOS 没开 remote-notification 后台模式、Mac 没显式注册推送 → CloudKit 的静默推送
//      到不了 app,另一台设备的改动只在冷启动时才拉下来(见 AppPushRegistration)。
//   ② "立即同步"/下拉刷新走的是 iCloud 云盘 JSON 合并 —— 跟 CloudKit 是两套身份,
//      会把已删物品复活、把移动过的物品复制一份,再经 CloudKit 扩散到所有设备。
//   ③ 用户看不到同步到底有没有在工作、两台设备是不是同一个 iCloud 账号。
// 本文件解决 ③,并给 ② 提供替代:CloudKit 在线时"立即同步" = 落盘 + 等 CloudKit
// 导出/导入事件跑完 + 报告最近一次收发时间。
//
// 事件来源:SwiftData 底层是 NSPersistentCloudKitContainer,它的 eventChangedNotification
// (setup / import / export 三类,带起止时间与错误)照常经 NotificationCenter 广播。
//
// 账号:苹果不向 app 提供 Apple ID 邮箱。能拿到的是
//   - accountStatus(已登录 / 未登录 / 受限 / 暂不可用)
//   - 本 app 容器里的用户记录 ID —— 同一 Apple ID 在所有设备上完全相同,
//     显示它的短指纹,两台设备一对就知道是不是同一个账号
//   - 姓名(尽力而为:shareParticipant 查自己,拿得到才显示)

@MainActor
@Observable
final class CloudSyncMonitor {

    static let shared = CloudSyncMonitor()

    enum AccountState: Equatable {
        case checking
        case available
        case noAccount
        case restricted
        case temporarilyUnavailable
        case couldNotDetermine
    }

    /// iCloud 账号状态。
    private(set) var account: AccountState = .checking
    /// 账号姓名(拿不到为 nil —— 苹果只在部分系统版本 / 账号设置下返回)。
    private(set) var accountName: String?
    /// 账号指纹 "XXXX-XXXX":同一 Apple ID 在所有设备上相同。
    private(set) var accountFingerprint: String?

    /// 最近一次成功从 iCloud 收到改动 / 把改动送上 iCloud 的时间(跨启动持久化)。
    private(set) var lastImportAt: Date?
    private(set) var lastExportAt: Date?
    /// 最近一次失败的友好描述;同类事件之后成功一次就清掉。
    private(set) var lastError: String?
    private var lastErrorType: NSPersistentCloudKitContainer.EventType?

    /// 正在进行中的 CloudKit 事件。非空 = 正在同步。
    private var inFlight: Set<UUID> = []
    var isSyncing: Bool { !inFlight.isEmpty }

    /// 每次 import 成功结束时 +1 —— 视图 / 去重逻辑据此在"新数据到达后"做事。
    private(set) var importGeneration = 0

    private var started = false
    private var lastAccountRefresh: Date = .distantPast
    private var observers: [NSObjectProtocol] = []

    private static let lastImportKey = "cloudSync.lastImport"
    private static let lastExportKey = "cloudSync.lastExport"
    private static let fingerprintKey = "cloudSync.accountFingerprint"

    private init() {}

    /// app 启动时调一次(幂等)。
    func start() {
        guard !started else { return }
        started = true
        lastImportAt = Self.loadDate(Self.lastImportKey)
        lastExportAt = Self.loadDate(Self.lastExportKey)

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
                                        object: nil, queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            MainActor.assumeIsolated { self?.handle(event) }
        })
        observers.append(nc.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccountSoon(force: true) }
        })
        #if os(iOS)
        let activeName = UIApplication.didBecomeActiveNotification
        #else
        let activeName = NSApplication.didBecomeActiveNotification
        #endif
        observers.append(nc.addObserver(forName: activeName, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccountSoon(force: false) }
        })
        refreshAccountSoon(force: true)
    }

    // MARK: - 事件

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        guard let end = event.endDate else {
            inFlight.insert(event.identifier)
            return
        }
        inFlight.remove(event.identifier)
        if event.succeeded {
            switch event.type {
            case .import:
                lastImportAt = end
                Self.saveDate(end, Self.lastImportKey)
                importGeneration += 1
            case .export:
                lastExportAt = end
                Self.saveDate(end, Self.lastExportKey)
            default:
                break
            }
            if lastErrorType == event.type {
                lastError = nil
                lastErrorType = nil
            }
        } else if let error = event.error {
            // 网络抖动 / 冲突重试这类 CloudKit 会自己恢复的错误不打扰用户。
            guard let text = Self.friendlyDescription(of: error) else { return }
            lastError = text
            lastErrorType = event.type
            NSLog("[Whereabouts] CloudKit %@ event failed: %@",
                  String(describing: event.type.rawValue), String(describing: error))
        }
    }

    // MARK: - 账号

    private func refreshAccountSoon(force: Bool) {
        guard force || Date().timeIntervalSince(lastAccountRefresh) > 30 else { return }
        lastAccountRefresh = Date()
        Task { await refreshAccount() }
    }

    func refreshAccount() async {
        // 未签名的验证构建没有 iCloud entitlement,碰 CKContainer 会直接崩 ——
        // 只有 CloudKit 容器真的挂上了(说明 entitlement 在),或系统确认登录了 iCloud
        // (ubiquityIdentityToken 非 nil,同样要求 entitlement)才去问 CloudKit。
        guard AppContainer.cloudKitActive || FileManager.default.ubiquityIdentityToken != nil else {
            account = .noAccount
            accountName = nil
            accountFingerprint = nil
            return
        }
        let container = CKContainer(identifier: AppContainer.cloudKitContainerID)
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            account = .couldNotDetermine
            return
        }
        switch status {
        case .available:              account = .available
        case .noAccount:              account = .noAccount
        case .restricted:             account = .restricted
        case .temporarilyUnavailable: account = .temporarilyUnavailable
        default:                      account = .couldNotDetermine
        }
        guard status == .available else {
            accountName = nil
            accountFingerprint = nil
            // 登出 iCloud 时系统会清掉本机镜像数据;上次收发时间随之作废。
            if status == .noAccount { resetSyncHistory() }
            return
        }
        guard let recordID = try? await container.userRecordID() else { return }
        let fp = Self.fingerprint(of: recordID.recordName)
        // 换了 iCloud 账号 → 旧账号的收发时间不再有意义(也会误导"云端是否为空"的判断)。
        if let old = UserDefaults.standard.string(forKey: Self.fingerprintKey), old != fp {
            resetSyncHistory()
        }
        UserDefaults.standard.set(fp, forKey: Self.fingerprintKey)
        accountFingerprint = fp
        if let participant = try? await container.shareParticipant(forUserRecordID: recordID),
           let comps = participant.userIdentity.nameComponents {
            let name = PersonNameComponentsFormatter.localizedString(from: comps, style: .default)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            accountName = name.isEmpty ? nil : name
        }
    }

    // MARK: - 立即同步

    enum SyncOutcome {
        /// CloudKit 在线,事件都跑完了(或超时前没有新事件)。
        case cloudKitIdle
        /// 账号不可用(未登录 / 受限)。
        case accountUnavailable
        /// 最近一次同步出错(lastError 有描述)。
        case failed
    }

    /// CloudKit 在线时的"立即同步":
    ///   ① 把未保存的改动落盘 —— NSPersistentCloudKitContainer 只导出已保存的改动
    ///   ② 等进行中的导出 / 导入事件结束(最多 ~12 秒)
    ///   ③ 顺手刷新账号状态
    /// 不再做 JSON 合并(会复活已删物品 / 复制移动过的物品)。
    func syncNow(context: ModelContext) async -> SyncOutcome {
        if context.hasChanges { try? context.save() }
        await refreshAccount()
        guard account == .available else { return .accountUnavailable }
        // 保存后 CloudKit 镜像有一个很短的合并窗口才开始导出,先给它一点时间冒头。
        // 调用方(下拉刷新)被取消时 sleep 会立刻抛错 —— 必须跳出,否则 while 会在主线程空转。
        do {
            try await Task.sleep(for: .milliseconds(1200))
            let deadline = Date().addingTimeInterval(12)
            while isSyncing && Date() < deadline && !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(300))
            }
        } catch {
            // 取消:不再等,直接按当前状态返回
        }
        return lastError == nil ? .cloudKitIdle : .failed
    }

    /// 清空收发时间记录(账号登出 / 切换时)。
    private func resetSyncHistory() {
        lastImportAt = nil
        lastExportAt = nil
        lastError = nil
        lastErrorType = nil
        UserDefaults.standard.removeObject(forKey: Self.lastImportKey)
        UserDefaults.standard.removeObject(forKey: Self.lastExportKey)
        UserDefaults.standard.removeObject(forKey: Self.fingerprintKey)
    }

    // MARK: - 工具

    /// 用户记录 ID → "XXXX-XXXX"。哈希一下,不直接暴露原始 ID。
    static func fingerprint(of recordName: String) -> String {
        let digest = SHA256.hash(data: Data(recordName.utf8))
        let hex = digest.prefix(4).map { String(format: "%02X", $0) }.joined()
        return "\(hex.prefix(4))-\(hex.suffix(4))"
    }

    /// 把 CloudKit / Core Data 错误翻成一句人话。返回 nil = 会自动恢复,不必显示。
    static func friendlyDescription(of error: Error) -> String? {
        let ns = error as NSError
        let ck: CKError? = (error as? CKError)
            ?? (ns.userInfo[NSUnderlyingErrorKey] as? CKError)
        guard let ck else {
            // Core Data 包一层的 CloudKit 镜像错误(NSCocoaErrorDomain 1344xx,私有码):
            //   134400 = 没登录 iCloud,初始化不了 —— 账号行已经显示"未登录",不重复报
            //   134407 / 134419 = 请求被取消 / 镜像忙,会自动重试
            if ns.domain == NSCocoaErrorDomain, [134400, 134407, 134419].contains(ns.code) {
                return nil
            }
            return ns.localizedDescription
        }
        switch ck.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .requestRateLimited, .zoneBusy, .serverRecordChanged, .operationCancelled:
            return nil
        case .partialFailure:
            // 部分失败里只要有一条是"真问题"就报它,全是可恢复的就不报。
            let inner = (ck.partialErrorsByItemID ?? [:]).values
            for e in inner {
                if let text = friendlyDescription(of: e) { return text }
            }
            return nil
        case .notAuthenticated:
            return String(localized: "sync.error.notSignedIn")
        case .quotaExceeded:
            return String(localized: "sync.error.quota")
        default:
            return ck.localizedDescription
        }
    }

    private static func loadDate(_ key: String) -> Date? {
        let t = UserDefaults.standard.double(forKey: key)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    private static func saveDate(_ date: Date, _ key: String) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: key)
    }
}
