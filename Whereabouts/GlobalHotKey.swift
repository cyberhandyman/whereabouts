#if os(macOS)
import AppKit
import Carbon.HIToolbox

/// Phase 89 + Phase 100:macOS 全局快捷键(系统级,在任何 app 内按下都触发)。
///
/// 用 Carbon 的 `RegisterEventHotKey` API。**不需要** Accessibility 权限
/// —— 跟 `NSEvent.addGlobalMonitorForEvents` 不同,后者监听键盘事件要弹权限提示框。
/// 而 hot key 注册是注册一个系统级"组合键 → app event"的映射,系统给我们通知。
///
/// **键位**:由用户在偏好设置里捕获。默认 `⌥⌘N`(Option+Command+N)。存到 UserDefaults
/// 两个 key:`globalHotKey.keyCode`(Carbon kVK_*)+ `globalHotKey.modifiers`(cmdKey | optionKey | ...).
///
/// 触发流程:
///   1. Carbon 调 `hotKeyHandler`(C 回调)
///   2. 回调里 post `Notification.Name.openQuickEntry` 通知
///   3. App 主 scene 里有个隐藏观察器收到通知 → 用 `openWindow(id: "quickEntry")` 弹小窗
///
/// 单例 `shared` 持有 EventHotKeyRef + EventHandlerRef,跨整个 app 生命周期。
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    /// Carbon 注册后给我们的 token,uninstall 时用。
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// 默认键位 —— ⌥⌘N。
    static let defaultKeyCode:   UInt32 = UInt32(kVK_ANSI_N)
    static let defaultModifiers: UInt32 = UInt32(cmdKey | optionKey)

    /// 从 UserDefaults 读当前键位,没设过返回默认。
    static var currentKeyCode: UInt32 {
        let v = UserDefaults.standard.object(forKey: "globalHotKey.keyCode") as? Int
        return v.map(UInt32.init) ?? defaultKeyCode
    }
    static var currentModifiers: UInt32 {
        let v = UserDefaults.standard.object(forKey: "globalHotKey.modifiers") as? Int
        return v.map(UInt32.init) ?? defaultModifiers
    }

    /// Phase 100:让用户在偏好设置里点完新键位后,把新键写进 UserDefaults。
    /// modifiers 是 Carbon 风格 (cmdKey | optionKey | shiftKey | controlKey)。
    static func saveCustom(keyCode: UInt32, modifiers: UInt32) {
        UserDefaults.standard.set(Int(keyCode), forKey: "globalHotKey.keyCode")
        UserDefaults.standard.set(Int(modifiers), forKey: "globalHotKey.modifiers")
    }

    /// 注册当前生效的快捷键(默认或用户自定义)。已注册过会先注销再注册。
    func registerDefault() {
        unregister()

        let modifiers = Self.currentModifiers
        let keyCode   = Self.currentKeyCode
        let signature: OSType = OSType(0x57484241)  // 'WHBA' — 任意四字节,只是身份标识
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)

        // 装事件处理器(只装一次,处理所有 hot key)
        if handlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                          eventKind:  UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(),
                                hotKeyHandler,
                                1,
                                &eventType,
                                nil,
                                &handlerRef)
        }

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            self.hotKeyRef = ref
        }
    }

    func unregister() {
        if let r = hotKeyRef {
            UnregisterEventHotKey(r)
            hotKeyRef = nil
        }
    }
}

// MARK: - Phase 100:键位文字渲染

/// 把 Carbon (keyCode, modifiers) 转成用户能看的字符串,比如 "⌥⌘N"。
/// 主要给偏好设置的键位捕获按钮显示当前值用。
enum HotKeyFormatter {
    static func display(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey)     != 0 { parts.append("⌘") }
        parts.append(keyCodeLabel(keyCode))
        return parts.joined()
    }

    /// 把 Carbon 的 keyCode 转成可显示字符 —— 仅做最常用的几个,够日常用。
    private static func keyCodeLabel(_ code: UInt32) -> String {
        let map: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "⏎",
        ]
        return map[code] ?? "?"
    }

    /// NSEvent → Carbon 的 modifier 转换。捕获键位 UI 在按下时拿到的是 NSEvent.modifierFlags
    /// (.command/.option/.shift/.control),需要 -> Carbon (cmdKey/optionKey/...) 才能存。
    static func carbonModifiers(from nsFlags: NSEvent.ModifierFlags) -> UInt32 {
        var out: UInt32 = 0
        if nsFlags.contains(.command) { out |= UInt32(cmdKey) }
        if nsFlags.contains(.option)  { out |= UInt32(optionKey) }
        if nsFlags.contains(.shift)   { out |= UInt32(shiftKey) }
        if nsFlags.contains(.control) { out |= UInt32(controlKey) }
        return out
    }
}

/// Carbon 事件处理器(C 函数指针风格 —— Swift 这里要写成 free function)。
/// 任何被系统识别为"我们注册过"的快捷键按下时,系统就调这里一下。
/// 我们只 post 一个 NotificationCenter 通知,真正的 UI 弹窗逻辑在 SwiftUI 那侧。
private func hotKeyHandler(nextHandler: EventHandlerCallRef?,
                            event: EventRef?,
                            userData: UnsafeMutableRawPointer?) -> OSStatus {
    NotificationCenter.default.post(name: .openQuickEntry, object: nil)
    return noErr
}

extension Notification.Name {
    /// Phase 89:全局快捷键按下时发出 —— 主 scene 监听后弹 quickEntry 窗口。
    static let openQuickEntry = Notification.Name("com.bamcope.whereabouts.openQuickEntry")
}
#endif
