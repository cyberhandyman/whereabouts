import SwiftUI
import SwiftData
import UserNotifications

// Phase 111:iOS 版 app 入口。
// 跟 macOS 版共享:SwiftData 模型、解析器、AI 层、通知调度器、String Catalog。
// UI 完全独立(TabView + NavigationStack + 卡片设计语言,见 IOSTheme)。

/// Phase 122:注册远程推送 —— CloudKit 靠静默推送通知"另一台设备有改动",
/// 配合 Info.plist 的 remote-notification 后台模式,iPhone 才能在后台 / 前台及时拉取,
/// 而不是等到下次冷启动。不弹任何权限框(静默推送不需要用户授权)。
final class IOSAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if AppContainer.syncPreferred {
            application.registerForRemoteNotifications()
        }
        // Phase 122:本地库这次没打开(内存兜底)—— 最常见的情形是开机后首次解锁前被
        // 静默推送拉起,数据文件还加着密。等数据可读时如果还在后台,直接结束进程,
        // 用户下次打开就是一次正常启动;用户看过阻断页后切走,同样结束进程。
        if AppContainer.usingInMemoryFallback {
            let nc = NotificationCenter.default
            nc.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                           object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    if UIApplication.shared.applicationState == .background { exit(0) }
                }
            }
            nc.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                           object: nil, queue: .main) { _ in
                exit(0)
            }
        }
        return true
    }
}

@main
struct WhereaboutsiOSApp: App {
    @UIApplicationDelegateAdaptor(IOSAppDelegate.self) private var appDelegate
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .system
    @AppStorage("appearance") private var appearance: AppearanceMode = .system

    /// 共享 container —— 通知调度器要用它查置顶物品(跟 macOS 版同一做法)。
    /// Phase 116:经 AppContainer 走 CloudKit(可用时)+ 本地回退;iOS 用沙箱默认存储位置。
    private let sharedContainer: ModelContainer = AppContainer.make(storeURL: nil)

    init() {
        NotificationScheduler.shared.container = sharedContainer
        // 点通知 banner → NotificationTapForwarder 广播 .openItemByName,首页接住后搜索定位。
        UNUserNotificationCenter.current().delegate = NotificationTapForwarder.shared
        NotificationScheduler.shared.rescheduleIfEnabled()
        // Phase 122:监听 CloudKit 收发事件 + 查 iCloud 账号(设置页显示用)。
        CloudSyncMonitor.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                // Phase 122:本地库没打开时只显示阻断页,不让用户往临时内存库里录东西。
                if AppContainer.usingInMemoryFallback {
                    StoreUnavailableView()
                } else {
                    IOSRootView()
                }
            }
                .environment(\.locale, appLanguage.explicitLocale ?? Locale.autoupdatingCurrent)
                .preferredColorScheme(appearance.colorScheme)
                .tint(IOSTheme.accent)
        }
        .modelContainer(sharedContainer)
    }
}

/// 三个 tab:物品(首页列表)/ 记一条 / 设置。
struct IOSRootView: View {
    /// 用枚举而不是 Int —— 录入成功后要程序化切回"物品"tab。
    enum Tab: Hashable { case items, record, settings }
    @State private var tab: Tab = .items

    /// Phase 122:随 IOSRootView 构造就把通知中转初始化(挂上 .openItemByName 观察者),
    /// 冷启动时点通知的广播即使早于首页订阅也不会丢。
    private let pendingOpen = PendingItemOpen.shared

    /// Phase 117:退到后台时自动往 iCloud 云盘写一份 JSON 备份。
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    /// Phase 115:首次启动引导。看完(或跳过)置 true,永不再弹;
    /// 设置 → 关于 → 重看使用引导 可以把它清掉重看。
    @AppStorage("onboardingShown") private var onboardingShown: Bool = false

    var body: some View {
        TabView(selection: $tab) {
            IOSHomeView(onCompose: { tab = .record })
                .tabItem { Label("ios.tab.items", systemImage: "shippingbox.fill") }
                .tag(Tab.items)
            IOSRecordView(onSaved: { tab = .items })
                .tabItem { Label("ios.tab.record", systemImage: "square.and.pencil") }
                .tag(Tab.record)
            IOSSettingsView()
                .tabItem { Label("ios.tab.settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        // Phase 117:退后台 → 自动备份 JSON 到 iCloud 云盘(静默,失败无感)。
        .onChange(of: scenePhase) { _, new in
            if new == .background {
                let ctx = modelContext
                // 退后台前把未保存的改动落盘 —— CloudKit 只上传已保存的改动。
                if ctx.hasChanges { try? ctx.save() }
                Task { _ = await CloudBackup.backUp(context: ctx, onlyIfChanged: true) }
            }
        }
        // Phase 122:CloudKit 每导入一批别的设备的改动 → 合并同名标签 + 重排置顶提醒。
        .onChange(of: CloudSyncMonitor.shared.importGeneration) { _, _ in
            Tag.mergeDuplicates(in: modelContext)
            NotificationScheduler.shared.rescheduleIfEnabled()
        }
        // Phase 122:点通知 banner → 切回"物品"tab;首页再把名字放进搜索框(见 IOSHomeView)。
        // 以前只有首页改搜索词,用户在别的 tab 时什么也看不到。
        .onChange(of: pendingOpen.generation) { _, _ in
            tab = .items
        }
        // Phase 115:首次启动全屏引导。fullScreenCover 盖在 TabView 上,
        // 看完写 onboardingShown,之后每次启动直接进列表。
        .fullScreenCover(isPresented: .init(
            get: { !onboardingShown },
            set: { if !$0 { onboardingShown = true } }
        )) {
            IOSOnboardingView { onboardingShown = true }
        }
        #if DEBUG
        .onAppear {
            // 模拟器截图 / 验收用:--tab-record / --tab-settings 直接落到对应 tab;
            // --show-onboarding 强制重看引导;--skip-onboarding 跳过(截别的页时不被挡)。
            if CommandLine.arguments.contains("--tab-record") { tab = .record }
            if CommandLine.arguments.contains("--tab-settings") { tab = .settings }
            if CommandLine.arguments.contains("--show-onboarding") { onboardingShown = false }
            if CommandLine.arguments.contains("--skip-onboarding") { onboardingShown = true }
        }
        #endif
    }
}

extension IOSRootView {
    /// Phase 122:通知点击 → "待打开物品名"中转站。
    /// NotificationTapForwarder 广播 .openItemByName;冷启动时这条广播可能早于首页的订阅,
    /// 所以由这个单例(IOSRootView 构造时就初始化)先接住存下,首页出现 / 名字变化时取走应用。
    @Observable
    final class PendingItemOpen {
        static let shared = PendingItemOpen()

        /// 待应用的物品名;首页把它放进搜索框后置 nil。
        var name: String?
        /// 每点一次通知 +1 —— IOSRootView 据此切 tab(首页会把 name 清掉,不能拿它判断)。
        private(set) var generation = 0

        @ObservationIgnored private var observer: NSObjectProtocol?

        private init() {
            observer = NotificationCenter.default.addObserver(
                forName: .openItemByName, object: nil, queue: .main
            ) { [weak self] note in
                guard let self,
                      let itemName = note.userInfo?["itemName"] as? String,
                      !itemName.isEmpty else { return }
                self.name = itemName
                self.generation += 1
            }
        }
    }
}
