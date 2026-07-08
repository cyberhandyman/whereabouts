import SwiftUI

// Phase 116:名言库从 ContentView 挪到 Shared —— iOS 首页底部的滚动名言复用同一组文案。
//
// **静态字面量数组是硬约束**:Xcode 编译期扫描这些 LocalizedStringKey 字面量,
// 保证 catalog 条目打进 binary;动态拼 `LocalizedStringKey("...\(i)")` 扫不到,
// 界面会显示 raw key(PROJECT_CONTEXT §7 的老坑)。

enum QuoteBank {
    /// 35 条名人名言风格鸡汤,尾巴署 "—— claude code"。
    /// 1–15:早期 J 人语录;16–35:Phase 11 新增。
    static let all: [LocalizedStringKey] = [
        "status.jquote.1",  "status.jquote.2",  "status.jquote.3",
        "status.jquote.4",  "status.jquote.5",  "status.jquote.6",
        "status.jquote.7",  "status.jquote.8",  "status.jquote.9",
        "status.jquote.10", "status.jquote.11", "status.jquote.12",
        "status.jquote.13", "status.jquote.14", "status.jquote.15",
        "status.jquote.16", "status.jquote.17", "status.jquote.18",
        "status.jquote.19", "status.jquote.20", "status.jquote.21",
        "status.jquote.22", "status.jquote.23", "status.jquote.24",
        "status.jquote.25", "status.jquote.26", "status.jquote.27",
        "status.jquote.28", "status.jquote.29", "status.jquote.30",
        "status.jquote.31", "status.jquote.32", "status.jquote.33",
        "status.jquote.34", "status.jquote.35",
    ]
}
