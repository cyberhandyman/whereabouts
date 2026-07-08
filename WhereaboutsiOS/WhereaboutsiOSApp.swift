import SwiftUI
import SwiftData
import UserNotifications

// Phase 111:iOS 版 app 入口。
// 跟 macOS 版共享:SwiftData 模型、解析器、AI 层、通知调度器、String Catalog。
// UI 完全独立(TabView + NavigationStack + 卡片设计语言,见 IOSTheme)。

@main
struct WhereaboutsiOSApp: App {
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
    }

    var body: some Scene {
        WindowGroup {
            IOSRootView()
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
                Task { _ = await CloudBackup.backUp(context: ctx) }
            }
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
