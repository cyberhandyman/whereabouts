import Foundation
import Security

/// API key 的安全存储。
///
/// 历史:开发期曾因 ad-hoc 签名(每次 rebuild 换 cdhash → 钥匙串每次弹授权框)
/// 临时改存 UserDefaults 明文(Phase 41)。Phase 121 起签名已稳定(正式开发者
/// 证书),换回真 Keychain:
///   - `kSecUseDataProtectionKeychain`(iOS 风格数据保护钥匙串,macOS 10.15+)
///     —— 按 application-identifier 隔离,**不会**弹传统 ACL 授权框
///   - `kSecAttrAccessibleAfterFirstUnlock` —— 解锁过一次即可读(后台同步也够用)
///   - 首次读取时自动把旧 UserDefaults 明文迁移进来并删除原值
enum Keychain {
    /// 旧 UserDefaults 键前缀(迁移用)。
    private static let legacyPrefix = "kc_"
    /// Keychain service 命名空间。
    private static let service = "com.bamcope.whereabouts.ai"

    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // 清空 = 删除条目
        if trimmed.isEmpty {
            SecItemDelete(baseQuery(account: account) as CFDictionary)
            UserDefaults.standard.removeObject(forKey: legacyPrefix + account)
            return true
        }
        let data = Data(value.utf8)
        // 先试更新,不存在再新增
        let updateStatus = SecItemUpdate(
            baseQuery(account: account) as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var attrs = baseQuery(account: account)
            attrs[kSecValueData] = data
            attrs[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(attrs as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                NSLog("[Whereabouts] Keychain add failed: %d", addStatus)
                return false
            }
        } else if updateStatus != errSecSuccess {
            NSLog("[Whereabouts] Keychain update failed: %d", updateStatus)
            return false
        }
        // 写成功后清掉旧明文(若还在)
        UserDefaults.standard.removeObject(forKey: legacyPrefix + account)
        return true
    }

    static func get(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecSuccess, let data = out as? Data,
           let s = String(data: data, encoding: .utf8), !s.isEmpty {
            return s
        }
        // 迁移路径:Keychain 没有 → 看旧 UserDefaults 明文,有就搬进 Keychain
        if let legacy = UserDefaults.standard.string(forKey: legacyPrefix + account),
           !legacy.isEmpty {
            set(legacy, account: account)  // set 内部会删旧值
            return legacy
        }
        return nil
    }

    private static func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
        ]
    }
}
