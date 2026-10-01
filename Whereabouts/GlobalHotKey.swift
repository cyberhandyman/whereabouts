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
///   3. Phase 122:app 级 `MainWindowRouter`(WhereaboutsApp.swift)收到通知 → `openWindow(id: "quickEntry")` 弹小窗
///      (以前观察器挂在主窗口上,⌘W 关掉主窗口后快捷键就失灵了)
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

    /// Phase 122:当前**真正注册成功**的那组键位(注册失败时用来恢复)。
    private var registeredCombo: (keyCode: UInt32, modifiers: UInt32)?

    /// 注册当前生效的快捷键(默认或用户自定义)。已注册过会先注销再注册。
    /// Phase 122:返回 OSStatus;失败时自动恢复之前注册着的那组。
    @discardableResult
    func registerDefault() -> OSStatus {
        register(keyCode: Self.currentKeyCode, modifiers: Self.currentModifiers)
    }

    /// Phase 122:注册指定键位。**不写 UserDefaults** —— 调用方确认成功后再 saveCustom。
    /// 之前先 unregister 再注册,RegisterEventHotKey 失败时旧键已经没了、UI 却显示新键位,
    /// 用户就落得"什么快捷键都不灵"。现在失败会把原来那组重新注册回去。
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        let previous = registeredCombo
        unregister()

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
            self.registeredCombo = (keyCode, modifiers)
            return noErr
        }
        // 失败 → 恢复原来那组(若原来就有)
        if let prev = previous {
            var prevRef: EventHotKeyRef?
            if RegisterEventHotKey(prev.keyCode, prev.modifiers, hotKeyID,
                                   GetApplicationEventTarget(), 0, &prevRef) == noErr {
                self.hotKeyRef = prevRef
                self.registeredCombo = prev
            }
        }
        return status
    }

    func unregister() {
        if let r = hotKeyRef {
            UnregisterEventHotKey(r)
            hotKeyRef = nil
        }
        registeredCombo = nil
    }

    // MARK: - Phase 122:键位校验

    enum ComboCheck: Equatable {
        case ok
        /// 没有 ⌘ / ⌥ / ⌃(单独 ⇧ 不算 —— ⇧A 会吞掉所有大写 A)
        case needsModifier
        /// 跟系统 / 常用编辑快捷键或打字冲突(⌘Q、⌘C、⌘Tab、⌃Space、⌥A 打 å……)
        case reserved
    }

    /// 校验用户捕获到的键位能不能当**全局**快捷键。
    static func check(keyCode: UInt32, modifiers: UInt32) -> ComboCheck {
        let cmd = UInt32(cmdKey), opt = UInt32(optionKey)
        let ctrl = UInt32(controlKey), shift = UInt32(shiftKey)
        let mods = modifiers & (cmd | opt | ctrl | shift)
        guard mods & (cmd | opt | ctrl) != 0 else { return .needsModifier }
        // 只有 ⌘(可带 ⇧ 以外):⌘+任意键都是各 app 菜单的地盘(⌘Q/W/C/V/X/Z/A/S/N/Tab/Space/`…),
        // 全局注册会把它们全劫持掉。
        if mods == cmd { return .reserved }
        // 只有 ⌥ 或 ⌥⇧:这些组合在键盘上是"打特殊字符"(⌥A=å、⌥Space=不换行空格)。
        if mods == opt || mods == (opt | shift) { return .reserved }
        // 其余组合:逐条列出系统 / 编辑常用的那几个
        let reservedByMods: [UInt32: [Int]] = [
            // ⌘⇧Z 重做、⌘⇧3/4/5/6 截屏、⌘⇧Q 注销、⌘⇧Tab 反向切 app
            cmd | shift: [kVK_ANSI_Z, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6,
                          kVK_ANSI_Q, kVK_Tab],
            // ⌃Space 切输入法;⌃A/E/K/N/P/F/B/D/H/T/O/Y/V 是全系统文本框的 Emacs 编辑键
            ctrl: [kVK_Space, kVK_ANSI_A, kVK_ANSI_E, kVK_ANSI_K, kVK_ANSI_N, kVK_ANSI_P,
                   kVK_ANSI_F, kVK_ANSI_B, kVK_ANSI_D, kVK_ANSI_H, kVK_ANSI_T, kVK_ANSI_O,
                   kVK_ANSI_Y, kVK_ANSI_V],
            // ⌃⌥Space 切输入法
            ctrl | opt: [kVK_Space],
            // ⌃⌘Q 锁屏、⌃⌘F 全屏、⌃⌘Space 表情与符号、⌃⌘D 查词典
            ctrl | cmd: [kVK_ANSI_Q, kVK_ANSI_F, kVK_Space, kVK_ANSI_D],
            // ⌥⌘Space Finder 搜索、⌥⌘D 隐藏程序坞、⌥⌘H 隐藏其他、⌥⌘W 关闭全部窗口
            opt | cmd: [kVK_Space, kVK_ANSI_D, kVK_ANSI_H, kVK_ANSI_W],
        ]
        if reservedByMods[mods]?.contains(Int(keyCode)) == true { return .reserved }
        return .ok
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
