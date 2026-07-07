import SwiftUI

// Phase 111(iOS 版):AppearanceMode / AppLanguage 从 WhereaboutsApp.swift 挪到这里 ——
// macOS / iOS 两端的设置页共用同一对枚举与同一组 @AppStorage key。

/// 用户在偏好设置里选的语言。
/// - `system`:跟随系统,不覆盖 environment locale
/// - 其他:固定到具体语言
///
/// 切换不会修改任何 SwiftData 持久化数据 —— Item.name 等存的是用户输入原文,
/// 跟 locale 无关;日期/数字走 Date.FormatStyle 跟随 locale 显示,只影响呈现。
/// 外观模式 —— `.environment(\.colorScheme)` 通过 `.preferredColorScheme` 注入到 root view。
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    /// `nil` = 跟随系统(不调用 .preferredColorScheme)。
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
    var displayKey: LocalizedStringKey {
        switch self {
        case .system: return "settings.appearance.system"
        case .light:  return "settings.appearance.light"
        case .dark:   return "settings.appearance.dark"
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case en

    var id: String { rawValue }

    /// 用在 `.environment(\.locale, ...)` 上;`nil` = 不覆盖(跟随系统)。
    var explicitLocale: Locale? {
        switch self {
        case .system: return nil
        case .zhHans: return Locale(identifier: "zh-Hans")
        case .en:     return Locale(identifier: "en")
        }
    }

    /// Picker 显示用。
    var displayKey: LocalizedStringKey {
        switch self {
        case .system: return "settings.language.system"
        case .zhHans: return "settings.language.chinese"
        case .en:     return "settings.language.english"
        }
    }
}
