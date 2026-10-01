import Foundation
import SwiftData

// Phase 116:iCloud 同步 —— 双端共用的 ModelContainer 工厂。
//
// 设计:
//   - CloudKit 私有库 `iCloud.com.bamcope.whereabouts`(entitlements 里声明)
//   - 开关走 UserDefaults("icloudSyncEnabled",默认开);改开关要重启 app 生效
//     (SwiftData 的 CloudKit 绑定在容器创建时决定,运行中无法切换)
//   - **任何失败都回退纯本地**:签名没带 CK entitlement / 存量库迁移问题……
//     app 永远能打开,数据永远在本地,同步只是"有条件时的增益"
//   - `cloudKitActive` 记录本次启动 CloudKit 镜像是否挂上。注意:没登录 iCloud 时
//     容器照样建得起来(只是不同步)—— 账号状态看 CloudSyncMonitor.account。

enum AppContainer {

    static let schema = Schema([Item.self, Location.self, LocationLog.self, Tag.self, EditLog.self])

    /// CloudKit 容器 ID(entitlements 同名)。
    static let cloudKitContainerID = "iCloud.com.bamcope.whereabouts"

    /// 用户开关的 UserDefaults key(设置页 @AppStorage 同名)。默认 true。
    static let syncPrefKey = "icloudSyncEnabled"

    static var syncPreferred: Bool {
        UserDefaults.standard.object(forKey: syncPrefKey) as? Bool ?? true
    }

    /// 本次启动 CloudKit 镜像是否挂上了(容器创建成功)。设置页据此显示状态。
    private(set) static var cloudKitActive = false

    /// CloudKit 起不来时的具体原因(NSLog 进系统日志,诊断用;UI 不直接展示技术细节)。
    private(set) static var cloudKitStatusDetail: String?

    /// Phase 122:本地库也打不开时退到内存库(app 不至于启动即崩),设置页据此警示。
    private(set) static var usingInMemoryFallback = false

    /// Phase 122:本次启动建好的容器 —— app delegate(退出时备份)等拿不到
    /// SwiftUI environment 的地方用。
    private(set) static var current: ModelContainer?

    /// 建容器。`storeURL == nil` 用平台默认位置(iOS 沙箱内);
    /// macOS 传专属路径(Phase 114,避开被系统进程污染的共享 default.store)。
    static func make(storeURL: URL?) -> ModelContainer {
        let container = makeContainer(storeURL: storeURL)
        current = container
        return container
    }

    private static func makeContainer(storeURL: URL?) -> ModelContainer {
        if syncPreferred {
            let cloudConfig: ModelConfiguration
            if let url = storeURL {
                cloudConfig = ModelConfiguration(schema: schema, url: url,
                                                 cloudKitDatabase: .private(cloudKitContainerID))
            } else {
                cloudConfig = ModelConfiguration(schema: schema,
                                                 cloudKitDatabase: .private(cloudKitContainerID))
            }
            do {
                let c = try ModelContainer(for: schema, configurations: cloudConfig)
                cloudKitActive = true
                return c
            } catch {
                // CloudKit 起不来(无 entitlement / 存量库迁移问题)→ 记录原因,静默回退本地。
                cloudKitStatusDetail = String(describing: error)
                NSLog("[Whereabouts] CloudKit container failed, falling back to local: %@",
                      String(describing: error))
            }
        }
        let localConfig: ModelConfiguration
        if let url = storeURL {
            localConfig = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            localConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        }
        cloudKitActive = false
        do {
            return try ModelContainer(for: schema, configurations: localConfig)
        } catch {
            // Phase 122:原来是 try! —— 库文件本身打不开(迁移失败 / 磁盘满 / 首次解锁前)
            // 会让 app 每次启动即崩。改为退到内存库:库文件原封不动留在磁盘上,
            // 下次启动条件恢复后照常读到;本次会话设置页给出警示。
            NSLog("[Whereabouts] Local store failed to open, using in-memory store: %@",
                  String(describing: error))
            usingInMemoryFallback = true
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                            cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: memory)
        }
    }
}
