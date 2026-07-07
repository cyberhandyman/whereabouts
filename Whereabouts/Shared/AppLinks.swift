import Foundation

// Phase 111:对外网页链接集中在一处 —— 换域名 / 重新发布文档时只改这里。
// macOS / iOS 两个 target 都编译本文件。

/// app 里所有"打开网页"入口的 URL。
/// 文档托管在自有域名 whereabouts.top(GitHub Pages,
/// 仓库 cyberhandyman/whereabouts-site)—— 改内容推送仓库即可,URL 不变。
enum AppLinks {
    /// AI 配置图文教程(小白向,中英双语):Claude API + 火山引擎两条路线的
    /// 注册 → 充值 → 拿 key → 填入 app 全流程 + 费用估算 + 常见报错排查。
    static let aiSetupGuide = URL(string: "https://whereabouts.top/guide.html")!

    /// 隐私政策(App Store 上架必需;也给关心数据去向的用户看)。
    static let privacyPolicy = URL(string: "https://whereabouts.top/privacy.html")!

    /// 支持页 / 用户帮助入口(App Store 的 support URL 也填它)。
    static let supportPage = URL(string: "https://whereabouts.top/guide.html")!
}
