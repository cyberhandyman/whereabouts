import Foundation
import SwiftData

// Phase 116:iCloud 同步 —— 双端共用的 ModelContainer 工厂。
//
// 设计:
//   - CloudKit 私有库 `iCloud.com.bamcope.whereabouts`(entitlements 里声明)
//   - 开关走 UserDefaults("icloudSyncEnabled",默认开);改开关要重启 app 生效
//     (SwiftData 的 CloudKit 绑定在容器创建时决定,运行中无法切换)
//   - **任何失败都回退纯本地**:没登录 iCloud / 签名没带 CK entitlement /
//     模拟器无账号……app 永远能打开,数据永远在本地,同步只是"有条件时的增益"
//   - `cloudKitActive` 记录本次启动实际生效与否,设置页显示状态用

enum AppContainer {

    static let schema = Schema([Item.self, Location.self, LocationLog.self, Tag.self, EditLog.self])

    /// CloudKit 容器 ID(entitlements 同名)。
    static let cloudKitContainerID = "iCloud.com.bamcope.whereabouts"

    /// 用户开关的 UserDefaults key(设置页 @AppStorage 同名)。默认 true。
    static let syncPrefKey = "icloudSyncEnabled"

    static var syncPreferred: Bool {
        UserDefaults.standard.object(forKey: syncPrefKey) as? Bool ?? true
    }

    /// 本次启动 CloudKit 是否真的挂上了(容器创建成功)。设置页据此显示状态。
    private(set) static var cloudKitActive = false

    /// 建容器。`storeURL == nil` 用平台默认位置(iOS 沙箱内);
    /// macOS 传专属路径(Phase 114,避开被系统进程污染的共享 default.store)。
    static func make(storeURL: URL?) -> ModelContainer {
        if syncPreferred {
            let cloudConfig: ModelConfiguration
            if let url = storeURL {
                cloudConfig = ModelConfiguration(schema: schema, url: url,
                                                 cloudKitDatabase: .private(cloudKitContainerID))
            } else {
                cloudConfig = ModelConfiguration(schema: schema,
                                                 cloudKitDatabase: .private(cloudKitContainerID))
            }
            if let c = try? ModelContainer(for: schema, configurations: cloudConfig) {
                cloudKitActive = true
                return c
            }
            // CloudKit 起不来(未登录 iCloud / 无 entitlement / 网络策略)→ 静默回退本地。
        }
        let localConfig: ModelConfiguration
        if let url = storeURL {
            localConfig = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            localConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        }
        cloudKitActive = false
        return try! ModelContainer(for: schema, configurations: localConfig)
    }
}
