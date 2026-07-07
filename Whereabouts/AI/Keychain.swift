import Foundation

/// 持久化 API key 用的存储。**Phase 41 起改成 UserDefaults**(原 Keychain 实现已废)。
///
/// 为什么不再用 Keychain:
///   - 本 app 是 ad-hoc 签名(`codesign --sign -`),每次 rebuild 拿一个新的临时签名 cdhash。
///   - Keychain item 的 ACL 锁死创建它时那个签名;新 build 读旧 item → macOS 弹
///     「想要使用钥匙串中的机密信息」让用户授权。**每出一个 build 用户被打扰一次**。
///   - 正经的 Developer-ID-signed / App Store 版签名稳定,没这个问题 —— 真发布时再换回。
///
/// 当前 trade-off:API key 以**明文**存在
///   `~/Library/Containers/com.bamcope.whereabouts/Data/Library/Preferences/com.bamcope.whereabouts.plist`
///   (沙箱关时是 `~/Library/Preferences/<bundleID>.plist`)。
/// 物理读取用户家目录可见 —— 这对单人 Mac 上的个人 dev app 可接受。
///
/// API 没动:外部仍调 `Keychain.set / .get`,内部 routing 到 UserDefaults。
/// 命名空间用 `kc_<account>` 前缀避免和别的 @AppStorage key 冲突。
enum Keychain {
    private static let prefix = "kc_"

    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        let key = prefix + account
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(value, forKey: key)
        }
        return true
    }

    static func get(account: String) -> String? {
        UserDefaults.standard.string(forKey: prefix + account)
    }
}
