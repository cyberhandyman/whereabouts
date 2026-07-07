import Foundation
import SwiftData
import UserNotifications

/// 本地通知调度器 —— 给"置顶"物品按固定时段发"它还在原位吗?"提醒。
///
/// **不调用 user 通知中心服务器**,全部走 `UNUserNotificationCenter` 本地通知(无网络依赖,断网也工作)。
///
/// 设计:
/// - 调度时段:每天 12:00 和 18:00(白天,避开睡眠时间)
/// - 触发器:`UNCalendarNotificationTrigger(repeats: true)` 每天 fire 一次
/// - 限制:macOS 每个 app 最多 64 个 pending notification。每件置顶物品占 2 个 slot,所以最多支持 ~30 件
/// - identifier:`checkup-<itemID hash>-<slot>` 保证可控
///
/// 用户从偏好设置打开通知开关 → 申请权限 → 调度。关闭 → 清空所有 pending。
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private init() {}

    /// 总开关 —— 走 UserDefaults,跟 SettingsView 的 @AppStorage 同 key。
    private var enabled: Bool {
        UserDefaults.standard.bool(forKey: "notificationsEnabled")
    }

    // MARK: - Phase 99:用户可自定义参数(时间 / 频率 / 通知内容)

    /// 频率枚举,字符串存到 UserDefaults。
    enum Frequency: String, CaseIterable, Identifiable {
        case daily, weekly, monthly
        var id: String { rawValue }
    }

    /// 当前频率。默认 daily。
    private var frequency: Frequency {
        let raw = UserDefaults.standard.string(forKey: "notificationFrequency") ?? "daily"
        return Frequency(rawValue: raw) ?? .daily
    }

    /// 提醒时间(hour 0..23)。默认 12。
    private var hour: Int {
        let v = UserDefaults.standard.object(forKey: "notificationHour") as? Int
        return v ?? 12
    }

    /// 提醒时间(minute 0..59)。默认 0。
    private var minute: Int {
        let v = UserDefaults.standard.object(forKey: "notificationMinute") as? Int
        return v ?? 0
    }

    /// Phase 105:weekly 频率下的星期几(Apple DateComponents 约定 1=周日,2=周一,...,7=周六)。
    /// 默认 2(周一)。仅在 frequency == .weekly 时生效。
    private var weekday: Int {
        let v = UserDefaults.standard.object(forKey: "notificationWeekday") as? Int
        let raw = v ?? 2
        return (1...7).contains(raw) ? raw : 2
    }

    /// 通知正文模板。`%@` 会被替换为物品名字。空串 → 用默认。
    private var bodyTemplate: String {
        let raw = UserDefaults.standard.string(forKey: "notificationBodyTemplate") ?? ""
        return raw.isEmpty ? String(localized: "notification.body.template.default") : raw
    }

    // MARK: - 权限

    /// 申请通知权限。成功返回 true,被拒返回 false。多次调用幂等(系统会复用之前的决定)。
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// 查询当前权限状态。
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - 调度

    /// 重新调度:取消旧通知 + 重新建。每次置顶状态变化、app 启动时调用。
    /// 通过 `enabled` 检查总开关 —— 关掉就只取消不建。
    /// Phase 108:之前调的 `cancelAll()` 走的是空 identifier list 的 dead-code,
    /// 老通知永远不会真删,改成 async 版 `cancelAllCheckups()` 用 prefix 精确清。
    func rescheduleIfEnabled() {
        Task { @MainActor in
            await cancelAllCheckups()
            guard enabled else { return }
            let status = await authorizationStatus()
            guard status == .authorized || status == .provisional else { return }
            // 从 SwiftData 取置顶物品并安排
            await scheduleForAllPinned()
        }
    }

    /// 把 ModelContainer 注入进来 —— 调度时要查置顶物品列表。
    /// 由 WhereaboutsApp 在 launch 时设置。
    var container: ModelContainer?

    private func scheduleForAllPinned() async {
        guard let container else { return }
        let context = ModelContext(container)
        // 只对未删除的置顶物品调度。
        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate<Item> { $0.isPinned && !$0.isDeleted }
        )
        guard let pinned = try? context.fetch(descriptor) else { return }

        // Phase 99:用户在偏好设置选了频率 / 时间 / 模板,每件置顶物品只调度 **1 个** trigger
        // (老版本是 12 / 18 两个,每件占 2 slot —— 现在 1 件 1 slot,容量翻倍)。
        for item in pinned {
            schedule(for: item)
        }
    }

    private func schedule(for item: Item) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.title")
        // Phase 99:用户自定义模板。`%@` 占位符替换为 item.name;没有 `%@` 时直接用模板原文。
        if bodyTemplate.contains("%@") {
            content.body = bodyTemplate.replacingOccurrences(of: "%@", with: item.name)
        } else {
            content.body = bodyTemplate
        }
        content.sound = .default
        content.userInfo = ["itemName": item.name]

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        // Phase 99:频率决定 components 的颗粒度
        switch frequency {
        case .daily:
            break  // hour + minute 已经够
        case .weekly:
            // Phase 105:weekday 从 UserDefaults 读,1=周日 ... 7=周六。默认 2(周一)。
            components.weekday = weekday
        case .monthly:
            // 每月 1 号
            components.day = 1
        }
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let id = identifier(for: item)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func identifier(for item: Item) -> String {
        // 用 name 的 stable hash 作 id —— 每件物品只发一个通知,没有 hour slot 后缀了。
        let nameHash = abs(item.name.hashValue) % 1_000_000
        return "checkup-\(nameHash)"
    }
}

extension NotificationScheduler {
    /// 异步版的"取消所有 checkup-* 通知" —— 用 prefix 过滤。
    @MainActor
    func cancelAllCheckups() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .filter { $0.identifier.hasPrefix("checkup-") }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}

// MARK: - Phase 106:通知点击 → 跳转物品

/// 通知中心的 delegate —— 用户点 banner 触发,从 userInfo 取出 itemName 并广播。
/// `UNUserNotificationCenter.current().delegate` 必须是 `NSObject` 子类。
/// 在 `WhereaboutsApp` 启动时 retain 这个单例,赋给 delegate;ContentView 监听 `.openItemByName`
/// 把名字写进搜索框,并把主窗口拽到前台。
final class NotificationTapForwarder: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationTapForwarder()
    private override init() { super.init() }

    /// app 在前台时也允许 banner + sound 出现,否则用户在用 app 时通知会"沉默"。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let name = userInfo["itemName"] as? String, !name.isEmpty {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .openItemByName,
                    object: nil,
                    userInfo: ["itemName": name]
                )
            }
        }
        completionHandler()
    }
}

extension Notification.Name {
    /// Phase 106:用户点击置顶通知后广播 —— ContentView 接住后聚焦该物品。
    static let openItemByName = Notification.Name("com.bamcope.whereabouts.openItemByName")
}
