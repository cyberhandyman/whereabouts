# Whereabouts (何处) — 项目上下文备忘 / Project Context Memo

> 上次更新:2026-07-07(0.2.0 build 1 时;正文大部分仍是 0.1.5 视角,先读下面的「0.2.0 增补」)
> 用途:把 Claude Code 会话里积累的所有项目上下文(决策、文件结构、约定、坑、风格)固化成可重读文档,后续 session 启动后读这一篇就能接着干。

---

## 0. ★ 0.2.0 增补(2026-07-07,Phase 110-113)—— 先读这节

**双 target 结构**(Phase 111 起):
- `Whereabouts`(macOS)= 原有全部代码;`WhereaboutsiOS`(iOS 17+)= 全新 UI,在 `WhereaboutsiOS/` 目录(App 入口 / IOSTheme 设计系统 / Home / Record / Detail / Settings / AISettings 七个文件)。
- 两个 target **同 bundle id** `com.bamcope.whereabouts` → App Store universal purchase。
- 共享层在 `Whereabouts/Shared/`:FilterModel+SortMode、ExportSchema+导出文档、RecordFlow(PendingDuplicate 等)、SharedUI(WrapLayout/Image(data:)/ImageHelpers)、AppPrefs(AppearanceMode/AppLanguage)、Importer(JSON 导入)、AppLinks(网页链接常量)。Models / Parsing / AI / NotificationScheduler 以及 ItemEditView / TagColorPicker / RelatedItemsPicker / AmbiguousLocationPicker 四个跨平台 view 也进 iOS target。
- macOS 专属(不进 iOS):ContentView / WhereaboutsApp / GlobalHotKey / LocationsSettingsTab / AISettingsTab / ItemDetailView / BatchEditSheets。

**构建坑(重要)**:
- 本机 xcodegen 是独立二进制、**缺 SettingPresets** → 平台默认 build settings 不会自动写入。project.yml 里已显式给足:iOS target 的 `SDKROOT/SUPPORTED_PLATFORMS`、project 级 `configs.debug.SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG`。动 project.yml 时别删这些。单平台 target 要用 `platform:` 不能用 `supportedDestinations:`(后者生成空 SUPPORTED_PLATFORMS)。
- 项目在 Desktop(iCloud FileProvider 同步)→ 资源文件常被打 Finder xattr,**codesign 会报 "resource fork ... detritus"**。验证构建一律 `CODE_SIGNING_ALLOWED=NO`;部署时 `cp → xattr -cr → codesign --force --deep --sign -`。
- iOS 模拟器截图辅助(仅 DEBUG):启动参数 `--demo-data` 灌演示数据、`--open-first` 弹首件详情、`--tab-record` / `--tab-settings` 切 tab。

**对外网页(自有域名 whereabouts.top,GitHub Pages 托管,URL 常量在 Shared/AppLinks.swift)**:
- AI 配置教程:https://whereabouts.top/guide.html
- 隐私政策:https://whereabouts.top/privacy.html
- 上架手册:https://whereabouts.top/appstore.html
- 源仓库:github.com/cyberhandyman/whereabouts-site(项目内 `site/` 目录,改内容 push 即上线,URL 不变);首页 index.html 是品牌落地页。DNS 在 NameSilo。

**上架材料**:`publishing/app-store-metadata.md`(文案包)+ `Whereabouts/Whereabouts-AppStore.entitlements`(macOS 沙箱,提交 App Store 前在 project.yml 挂 CODE_SIGN_ENTITLEMENTS;挂上后本机数据目录会变,先导出 JSON)。
**catalog 坑(Phase 112)**:代码里 `Text("key \(x)")` 运行时查找的 key 是 `"key %lld/%@"`(带格式后缀)。catalog 里 8 个手写条目原本没带后缀 → 界面显示原始 key(dup.alert.* / update.alert.* / detail.history.count / input.preview.willCreate),已补别名条目。以后加带插值的 key,**条目名必须含格式后缀**。
**价格修正(Phase 112)**:ClaudeModel 加了 sonnet5 / opus48;Opus 4.7/4.8 成本估算 $5/$25(旧表 $15/$75 是错的)。
**数据事故 + 专属库路径(Phase 114,2026-07-07)**:苹果系统进程 `/usr/libexec/icloudmailagent` 会写非沙箱 SwiftData 共用的 `~/Library/Application Support/default.store`,把何处的库覆盖了。macOS 版改用专属路径 `~/Library/Application Support/Whereabouts/whereabouts.store`(WhereaboutsApp.sharedContainer 用 ModelConfiguration(url:),所有 Scene 传同一实例);数据恢复脚本 `Tools/recover_store.sh`(sudo 跑,从 TM 本地快照捞)。**任何非沙箱 SwiftData app 都不要用默认路径**。
**iOS 首启体验(Phase 115)**:分页引导(IOSOnboardingView,onboardingShown key,设置→关于可重看)+ 首启演示数据(rawInput 标记 `__hechu_demo__`,横幅一键清除)+ 设置里 iCloud"即将推出"占位。
**GitHub(2026-07-07 起公开)**:主仓库 github.com/cyberhandyman/whereabouts(gitignore 排除 site/、SESSION_TRANSCRIPT.md、.claude/);文档站仓库 cyberhandyman/whereabouts-site。推送用钥匙串里的 HTTPS 凭据。
**iCloud 双端同步(Phase 116-117,2026-07-08 上线)**:
- CloudKit 私有库 `iCloud.com.bamcope.whereabouts`,SwiftData cloudKitDatabase(AppContainer 工厂,失败静默回退本地);**CloudKit 硬性要求已满足**:全部属性带默认值、全部关系可选(XxxStorage 可选存储 + 非可选门面,门面同旧名 → 调用点零改动)、LocationLog.location 的反向在 Location.logsStorage。
- **坑**:①关系不满足要求时 ModelContainer 能创建、**异步 mirror setup 才抛错**(134060 日志);②无 entitlements 的构建(CODE_SIGNING_ALLOWED=NO)运行时 CKContainer **必崩**(SIGTRAP)→ 模拟器构建不要关签名,用默认 "Sign to Run Locally";③模拟器/Desktop 的 derivedData 都放 /tmp(hechu-dd / hechu-dd-sim)避 xattr。
- iCloud Drive JSON 自动备份(CloudBackup):iOS 退后台 / macOS 退出时写 `iCloud Drive/Whereabouts/whereabouts-backup.json`;设置→数据有"立即备份"。entitlements 加了 CloudDocuments + ubiquity 容器,Info.plist 加 NSUbiquitousContainers。
- 签名:Team 6893263DW5 已注册本机为开发设备(ASC API);macOS 构建 `-allowProvisioningUpdates`(走 Xcode 登录态;xcodebuild 的 -authenticationKey* 参数对这把 ASC key 反而报 bearer token 错,别用)。
**Phase 117 其它**:iOS 语音录入(SpeechInput,SFSpeechRecognizer,记一条 tab 麦克风按钮);引导手势页 KeyframeAnimator 循环动画演示(右滑/左滑/长按);作者名改 Chengzhu Zhao;iOS 设置页大标题「J人养成器 - 何处」;名言库 Shared/QuoteBank 双端共用,iOS 首页底部 12s 滚动。付费功能已明确取消,app 永久全免费。

---

## 1. 项目概览

**名字**:Whereabouts(中文显示名「何处」)
**形态**:SwiftUI 应用,主目标 macOS 14+,iOS 17+ 同时支持(iOS 适配未真正完成 —— see §17)
**目的**:记录"我把东西放在哪了" —— 一句话录入,自然语言解析,树状位置,位置历史,照片,标签,关联,AI 理解,搜索,通知,偏好设置
**当前版本**:`MARKETING_VERSION = 0.1.5`,`CURRENT_PROJECT_VERSION = 3`(2026-05-16)
**bundle id**:`com.bamcope.whereabouts`
**作者**:Bam Cope `pluginexpert2@gmail.com`(About 面板里展示 "Built with Claude Code")
**License**:MIT(根目录 LICENSE)
**用户偏好语言**:中文为主,代码注释 / 文档 / commit 全中文写,UI 全中英双语

---

## 2. 技术栈

| 层 | 选型 | 备注 |
| --- | --- | --- |
| UI | SwiftUI | 不用 AppKit/UIKit,除非 SwiftUI 实在做不到 |
| 持久化 | SwiftData(`@Model`) | 不用 CoreData |
| 工程生成 | **xcodegen** | `project.yml` 是 source of truth;**不要手动改 `.xcodeproj`** |
| i18n | String Catalog `.xcstrings` | 单一文件,`developmentLanguage: zh-Hans`,知 region: zh-Hans / en / Base |
| 偏好 | `@AppStorage` | UserDefaults 后端 |
| 搜索/筛选 | `@Query` + `#Predicate<Item>` | SwiftData 谓词 |
| 通知 | `UNUserNotificationCenter` + `UNCalendarNotificationTrigger` | 纯本地,无网络 |
| 时间格式 | `Date.RelativeFormatStyle` / `.dateTime.year().month()` | 自带 locale,**不入 catalog** |

平台条件:`macOS 14.0` / `iOS 17.0` 起。任何用 `NSColor`、`NSWindow` 的代码要包 `#if os(macOS)`。`Color(.windowBackgroundColor)` 这种 macOS-only 不能直接用 → 用 `Color.secondary.opacity(...)` 之类跨平台替代。

---

## 3. 仓库结构

```
whereabouts/
├── project.yml                 # xcodegen 源
├── Whereabouts.xcodeproj/      # 生成产物(可重建,不要手编)
├── README.md
├── LICENSE                     # MIT
├── PROJECT_CONTEXT.md          # ← 本文件
├── i18n_step 1.md              # i18n 启动文档(历史)
├── i18n_task.md                # i18n 任务清单(历史)
├── Tools/
│   └── make_icons.swift        # 图标生成脚本
├── docs/                       # 作为 bundle resource 打包进 app
│   ├── CHANGELOG.md            # ← 这是用户看到的更新日志,持续维护
│   ├── help.zh-Hans.md         # ⌘? 帮助窗口 — 中文
│   ├── help.en.md              # ⌘? 帮助窗口 — 英文
│   └── i18n.md                 # i18n 内部技术说明(历史)
└── Whereabouts/
    ├── WhereaboutsApp.swift          # App entry, Settings tabs(5个), About, 通知, MenuBar, 全局快捷键观察
    ├── ContentView.swift             # 主窗口 — 列表 + 顶栏 + Inspector + Export schema
    ├── NotificationScheduler.swift   # 本地通知调度器
    ├── LocationsSettingsTab.swift    # ★ 0.1.5 build 3:位置树管理 tab(rename/delete 空节点)
    ├── GlobalHotKey.swift            # ★ 0.1.5 build 3:Carbon 全局快捷键 ⌥⌘N
    ├── Info.plist                    # 自己维护(GENERATE_INFOPLIST_FILE: NO)
    ├── Localizable.xcstrings         # 所有 UI 文案(411 keys 已翻译)
    ├── Assets.xcassets               # 图标、AppIcon
    ├── AppIcon.icns                  # 中文「何处」图标
    ├── zh-Hans.lproj/                # InfoPlist.strings 本地化(显示名)
    ├── en.lproj/
    ├── AI/                           # ★ 0.1.3 起加,双 provider(Claude + 火山引擎)
    │   ├── AISettings.swift          # static facade — provider/key/endpoint/model/prompt/usage
    │   ├── AISettingsTab.swift       # Settings → AI tab (provider 切换 + usage + 测试)
    │   ├── AIClient.swift            # AIChatClient protocol + Claude/Volc 两个实现 + applyAIResult
    │   └── Keychain.swift            # (历史)key 改存 UserDefaults 后这个不再用,留着
    ├── Models/
    │   ├── Item.swift                # 主实体(详见 §5)
    │   ├── Location.swift            # 树状位置 + sanitizePath + 启动迁移(merge/split)
    │   ├── LocationLog.swift         # 位置历史一条记录
    │   ├── Tag.swift                 # 标签 + 14 个预设(按版本号增量补 seed)
    │   ├── EditLog.swift             # ★ 字段编辑历史 + AI 来源标记
    │   └── RelatedGroup.swift        # ★ 物品关联组(双向 + 传递闭包,≤ 8 件)
    ├── Parsing/
    │   └── InputParser.swift         # 中文 + 英文双语自然语言录入解析器
    └── Views/
        ├── ItemDetailView.swift      # 右侧详情(Inspector 内容)+ LentOutSheet
        ├── ItemEditView.swift        # 编辑 Sheet
        ├── BatchEditSheets.swift     # 批量设置标签 / 位置 / 渠道
        ├── RelatedItemsPicker.swift  # 物品关联挑选器
        ├── AmbiguousLocationPicker.swift # 同名 leaf 消歧弹窗
        └── TagColorPicker.swift      # 标签调色板组件
```

文件规模(2026-05-16):
- `ContentView.swift` — ~2600 行(主窗口逻辑很重,包含 Export schema)
- `InputParser.swift` — ~1330 行(中文 + 英文 + 词典)
- `ItemDetailView.swift` — ~1370 行(含 LentOutSheet)
- `WhereaboutsApp.swift` — ~880 行(5 个 Settings tab + 2 个独立 Window + QuickEntry)
- `AISettingsTab.swift` — ~470 行(双 provider + Usage section)
- `AISettings.swift` — ~250 行(facade + Usage tracking)
- `LocationsSettingsTab.swift` — ~150 行
- `GlobalHotKey.swift` — ~80 行
- 总计:~9300 行 Swift

数据库(SwiftData)schema:`[Item, Location, LocationLog, Tag, EditLog]`(RelatedGroup 用 UUID 不入 schema)。

---

## 4. 工程配置约定(project.yml)

```yaml
options:
  developmentLanguage: zh-Hans      # 中文优先
knownRegions: [zh-Hans, en, Base]

settings.base:
  MARKETING_VERSION: "0.1.5"
  CURRENT_PROJECT_VERSION: "3"
  GENERATE_INFOPLIST_FILE: NO        # 自己提供 Info.plist
  PRODUCT_NAME: Whereabouts          # ASCII!避免 codesign 把中文当 identifier
  # 用户看到的「何处」靠 CFBundleDisplayName 在 InfoPlist.strings 里给

targets.Whereabouts:
  type: application
  supportedDestinations: [iOS, macOS]
  sources:
    - Whereabouts
    - path: docs                     # ← help.md/help.en.md 作为 bundle resource
      type: folder
      buildPhase: resources
```

**改 project.yml 后必须重新跑 `xcodegen generate`**(用户自己执行)。

---

## 5. 核心数据模型

### Item(`Models/Item.swift`)
```swift
@Model final class Item {
    var name: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var lastSeenAt: Date              // "上次见到"时间;初值 = createdAt

    var location: Location?           // 可空 → 允许"先记下,位置待定"
    @Attribute(.externalStorage) var photoData: Data?  // 大数据存外部文件

    // 可选元数据(空字段 = 轻量迁移,旧数据零影响)
    var model: String?
    var version: String?              // 容量 / 版本 / 规格 "512GB" "亚太版"
    var color: String?
    var purchaseDate: Date?
    var purchaseDatePrecision: String?  // "year" / "month" / "day" / nil
    var purchaseSource: String?

    @Relationship(deleteRule: .cascade, inverse: \LocationLog.item)
    var locationHistory: [LocationLog] = []

    @Relationship var tags: [Tag] = []

    // Phase 10:置顶 = 重要 → 想收通知
    var isPinned: Bool = false

    // 详情页 4 按钮:最近按的是哪个 → 强调那个按钮
    // 值:"stillThere" / "putBack" / "moved" / "unknown" / nil
    var lastActionType: String?

    // 软删除(回收站)
    var isDeleted: Bool = false
    var deletedAt: Date?
}

extension Item {
    func markDeleted() { isDeleted = true; deletedAt = .now; updatedAt = .now }
    func restore()     { isDeleted = false; deletedAt = nil;  updatedAt = .now }
}
```

**关键约束**:
- 新增字段一律可空 / 有默认值 → SwiftData 轻量迁移,不会破坏旧库
- `purchaseDate` 总是完整 Date,精度信息单独走 `purchaseDatePrecision` —— 显示用模块函数 `formatPurchaseDate(_:precision:)` 走 `Date.FormatStyle` 不入 catalog
- 软删除:出主列表 / 搜索 / facet / 状态栏统计都要过滤 `!isDeleted`

### Location(`Models/Location.swift`)
- 树状:`parent: Location?` + `children: [Location]`
- 同名同层自动复用(避免一堆"抽屉")
- 改名传导:重命名一个节点,所有引用它的 Item 跟着更新

### LocationLog(`Models/LocationLog.swift`)
- 一条:`recordedAt: Date` + `location: Location?` + `item: Item`
- 每次"放回原位 / 位置变了 / 不知道在哪 / 重复合并更新"都写一条
- 详情页倒序展示

### Tag(`Models/Tag.swift`)
- `name: String` + `color: String`(9 色 Finder 风调色板)
- 首次启动 seed 6 个预设:生活用品 / 3C 电子 / 厨具 / 小工具 / 办公用品 / 文具

---

## 6. 关键功能(已完成,按版本)

按版本归纳;具体 Phase / build 看 `docs/CHANGELOG.md`。

**0.1.0 - 0.1.2 基础**(Phase 0-11):录入、解析、位置树、历史、照片、标签、菜单栏、通知、置顶、回收站。

**0.1.3**(Phase 12-49):
- 批量编辑 + 右键菜单 + Delete 键删除
- AI 接入(Phase 26-29):**Claude + 火山引擎** 双 provider,理解物品字段 + 修 typo
- 自动颜色色点标签建议、自动 tag seed 迁移
- 搜索框常驻 + facet 折叠面板
- EditLog(字段变更历史,带 source 来源)+ rawInput 字段(用户原话)
- AI tag 替换而非追加;AI 改名后详情页 ↩ 还原按钮

**0.1.4**(Phase 50-85):
- 关联物品(同 UUID 组,≤ 8 件,双向 + 传递)
- brand chip + 编辑页只读
- 14 个预设标签(扩自 6 个,按 version 增量补)
- Location case-insensitive + 最长匹配反查 + 合并相邻段
- AI prompt 多版本迭代:多物品不串名、量词保留、available_locations、复合位置串拆段
- 启动迁移:重复 root 合并 + 名字含 `>` 的脏 Location 拆段(每次启动跑,幂等)
- 顶部 safeAreaInset + 底部状态栏不透明底
- 主窗口 defaultSize 1024×720 + windowResizability(.contentMinSize)

**0.1.5**:
- build 1-2:0.1.4 build 10 内容版本号 bump + AI prompt 加"复合位置串拆段"小节
- build 3 (★ 当前):
  - 位置管理 Settings tab(树形显示 + 重命名 + 删除空节点)
  - AI 调用计数 + token tracking + Claude 估算 USD
  - 全局快捷键 ⌥⌘N + QuickEntry 小窗口(Carbon HotKey API)
  - 数据导出 schema bump v1 → v2(tags / lent / pinned / relatedGroupID)+ 导入去重 toggle
  - 物品"借出去"状态(lentTo / lentAt + 右键菜单 + 详情徽章)
  - 英文 parser 模式扩充("X in Y" / "X at Y" / "Y has X")

**Phase 5 iCloud 同步**:⏸ 一直 pending,需要 Apple Developer Team($99/年)。

---

## 7. i18n 约定(很重要)

- **单一 catalog 文件**:`Whereabouts/Localizable.xcstrings`,所有 UI 文案都在这里
- **键约定**:点分小写,如 `detail.used.button.stillThere`、`action.pin`、`settings.notifications.enable`
- **动态 key 是坑**:`LocalizedStringKey("status.jquote.\(idx)")` 编译期扫不到,catalog 不会自动收录条目 → 用 `[LocalizedStringKey]` **静态字面量数组**让 Xcode 能扫
- **格式化日期 / 相对时间不入 catalog**:用 `Date.FormatStyle` / `Date.RelativeFormatStyle` 走系统 locale
- **InfoPlist.strings**:`zh-Hans.lproj/InfoPlist.strings` 和 `en.lproj/InfoPlist.strings` 给 `CFBundleDisplayName`(中文显示「何处」/ 英文 "Whereabouts")
- 切换语言:`General Settings` 里有 `AppleLanguages` 写 UserDefaults 实现,无须重启 Xcode

---

## 8. 解析器(InputParser)行为速查

支持的中文写法:
- 「充电宝在卧室抽屉第二格」、「护照:保险箱」、「钥匙 → 玄关 / 钩子」
- 嵌套:` > ` / `/` / `的` 都识别成层级
- 多条:`,` `、` `;` `然后 / 还有 / 接着` 分隔 → 一行多条
- 字段更新意图:「华为手表的型号是 GT6」、「扫地机是 2024 年 5 月在京东买的」→ 直接更新已有物品对应字段
- 重复检测:撞同名 / 包含关系 → 弹窗问「更新位置 / 补信息 / 另起一条」
- ✨「理解」按钮:对老脏数据再跑一遍解析,从 name 里补出 model/color/purchase

**Phase 10 加进去的清洗**:
- 句首语气词剥离:`但 / 可是 / 但是 / 然而 / 不过 / 对了 / 可 / 嗯 / 哦 / 啊 / 诶` → 不留进物品名
- 容量 / 规格抽取:`512g` `1TB` `11寸` 自动挪进 `version` 字段

---

## 9. ContentView 主要结构(1513 行)

- 顶部:`AddBar`(✏️ 一句话录入,⌘N 聚焦)
- 中部:`SearchBar`(默认收起,展开后底色加深,⌘F 聚焦)+ facet chip 4 行
- 列表:`@Query` 过滤 `!isDeleted` + partition sort(置顶物品在最上,其余按 sortMode 排)
- 列表行:置顶图标 `pin.fill` (orange) 在 name 前;右键菜单 / 左滑动作含 pin / unpin / 删除
- 工具栏:✏️ 录入(⌘N)/ 🔍 搜索(⌘F)/ 🗄 回收站 / ↕ 排序 / 🗑 批量删除 / ⬆ 导出
- Inspector:**永远开**,`.constant(true)` 绑定;未选时显示「选一条看详情」,多选时显示「已选 N 条」

---

## 10. ItemDetailView「用过吗?」4 按钮(最近做的)

```
🟢 mint   他还在原位      // .stillThere
🔵 blue   放回原位了      // .putBack
🟠 orange 位置变了…       // .moved
🔴 red    不知道在哪      // .unknown
```

| 项 | 实现 |
| --- | --- |
| 颜色渐进 | `.tint(.mint/.blue/.orange/.red)` |
| 强调态 | `item.lastActionType == actionType` → `.borderedProminent`(实色填充)|
| 非强调 | `.bordered`(描边) |
| 按下/抬起视觉 | `.borderedProminent` 系统自带 highlight(无需自定义)|
| caption | 强调按钮下方一行 `.caption2`:`{相对时间} · {按钮文案}`,颜色跟 tint 同 |
| 相对时间 | `item.lastSeenAt.formatted(.relative(presentation: .named))` |
| 持久化 | `Item.lastActionType: String?` 字段 |

helper 函数(在 ItemDetailView 内):
```swift
@ViewBuilder
private func actionButton(
    titleKey: LocalizedStringKey,
    systemImage: String,
    tint: Color,
    actionType: String,
    action: @escaping () -> Void
) -> some View { ... }

private func confirmStillHere(actionType: String) {
    item.lastSeenAt = .now
    item.updatedAt = .now
    item.lastActionType = actionType
    let log = LocationLog(recordedAt: .now, location: item.location, item: item)
    modelContext.insert(log)
    ack(String(localized: "detail.used.ack.kept"))
}
```

`saveNewLocation()` 写入 `item.lastActionType = "moved"`;
"不知道在哪"内联 handler 写入 `item.lastActionType = "unknown"`。

> 命名注意:helper 里写成了 `isEmphosizedCaptionVisible`(拼错的 "Emphosized"),编译没问题,后续要改先全文搜替。

---

## 11. NotificationScheduler(`NotificationScheduler.swift`,135 行)

- **完全本地** —— `UNUserNotificationCenter` + `UNCalendarNotificationTrigger(repeats: true)`,无网络
- 时段:每天 **12:00** 和 **18:00** 各发一次(白天,避开睡眠)
- 上限:macOS 单 app 64 个 pending,每件置顶 2 个 slot → ~30 件
- identifier:`checkup-{nameHash}-{hour}`
- 总开关:`@AppStorage("notificationsEnabled")` —— 偏好设置里那个 toggle 同 key
- 容器注入:`WhereaboutsApp.init()` 把 ModelContainer 写进 `NotificationScheduler.shared.container`
- `rescheduleIfEnabled()`:置顶状态变化、app 启动时调用;关掉开关 / 卸载时 `cancelAllCheckups()`
- 查置顶物品:`FetchDescriptor<Item>(predicate: #Predicate { $0.isPinned && !$0.isDeleted })`

---

## 12. 偏好设置(WhereaboutsApp.swift 内 SettingsView)

四个 Tab:
1. **通用**:语言(跟随系统 / 中 / 英)、外观(系统 / 浅 / 深)、菜单栏图标开关、重复检测开关、字段更新检测开关、**通知开关**(开启时申请权限)
2. **数据**:**批量导出到 JSON…**、**批量从 JSON 导入…**(各带一行说明 footer);**清空所有数据**(破坏性,二次确认)
3. (其他 tab 视实际为准)

---

## 13. 工具栏快捷键

| 快捷键 | 动作 |
| --- | --- |
| ⌘N | 焦点跳到顶部「记一笔」输入框 |
| ⌘F | 展开搜索区 + 焦点到搜索框 |
| ⌘? | 打开 Help 帮助窗口 |
| ⌘, | 偏好设置 |

实现:`@FocusState` + hashable enum 多字段焦点跟踪。

---

## 14. 部署 / 打包

**Dev 本机部署**(常用):
```bash
xcodegen generate
xcodebuild -project Whereabouts.xcodeproj -scheme Whereabouts -configuration Release \
  -derivedDataPath .build -destination 'generic/platform=macOS' build
cp -R .build/Build/Products/Release/Whereabouts.app ~/Applications/
codesign --force --deep --sign - ~/Applications/Whereabouts.app
```

**DMG 发布**(已做过):
- 用 `hdiutil` 制作可拖拽到 Applications 的 DMG
- 内附中英双语 "安装指南 / Install instructions":
  > **设置 → 隐私与安全性 → 滚到底部 → 「仍要打开」**
  > Settings → Privacy & Security → scroll to the bottom → "Open Anyway"

---

## 15. 已知坑 / 经验

- **SourceKit 跨文件假阳性**:`Item / Tag / InputParser not found in scope` 之类在 diagnostics 里经常出现,实际 `xcodebuild` 通过 → 一直忽略
- **`Color(.windowBackgroundColor)` 是 macOS-only** → 跨平台 view 里用 `Color.secondary.opacity(0.1)` 之类
- **`LocalizedStringKey` 动态拼接** Xcode 不扫 catalog → 静态字面量数组
- **SwiftUI Text 渲染 AttributedString from Markdown 不显式区分 H1/H2 大小** → 帮助文档用纯文本 + emoji 分隔 + `Text(verbatim:)` + monospace font
- **SwiftUI `#if` + `.commands` + `Window` scene 容易语法歧义** → 拆成多个独立 `#if` 块
- **Inspector dismiss 时 filter env 失效崩溃** → 已通过移除 `ItemDetailView` 对 `FilterModel` 的依赖修复
- **`PRODUCT_NAME` 必须 ASCII**(`Whereabouts`),中文走 `CFBundleDisplayName`,否则 codesign 把中文当 identifier 炸掉
- **新增 SwiftData 字段必须可空 / 默认值** —— 走轻量迁移,否则现存库打不开
- **新建 subagent 在当前 session 不可用** —— `.claude/agents/*.md` 只在 session 启动时读,临时要用就 fall back 到 general-purpose

---

## 16. 用户工作风格 / 偏好

- 中文沟通,代码注释也用中文
- 喜欢一次提多条改动(列点 1/2/3/…)
- 改完倾向于"顺手 build + deploy 到 ~/Applications/"再说,而不是 Xcode 里跑
- DMG 打包是显式动作,**不会主动做**,要等用户点头
- **未发布到 GitHub**(用户明说"先不发布,改改 bug 再说")
- 喜欢看到清单 / 表格 / 视觉对照(用 ASCII 框图说明 UI 效果他很受用)
- 不喜欢空话和奉承,直接说"改完了"或"build 失败,原因 X"
- 改 catalog 后会要求确认中英双语都齐了

---

## 17. 当前未做 / 后续可能(0.1.5 起视角)

**已搁置 / 待决策**:
- ⏸ **Phase 5(iCloud 同步)** —— 需要 Apple Developer Team($99/年),CloudKit 同步对 SwiftData 模型有强约束(每字段非 optional 要默认值)。开干前要把所有 @Model 的 schema 评一遍。
- **iOS build 真做出来** —— `project.yml supportedDestinations: [iOS, macOS]` 声称支持 iOS,但实际 ContentView 用了大量 `safeAreaInset`、固定窗口尺寸、MenuBarExtra、Carbon HotKey 都是 macOS 专属。要么真适配 iOS,要么从 supportedDestinations 摘掉。
- **存量脏 Location** —— 0.1.5 build 3 加了位置管理 tab,用户现在可以手动改;但还没自动 heuristic 拆 "门口电梯间鞋架上方" 这种隐式中文复合串(房间词词典靠 app 端维护风险高,先靠用户手动整理 + AI 新规则)。
- **GitHub 发布** —— 用户暂时不想公开。

**可能近期做的小事**:
- AI 自定义快捷键(目前 ⌥⌘N 固定,有人会想改成别的)
- 物品历史时间线"借给/归还" 渲染(目前借出 toast,但 EditLog 没专门列条)
- 关联组的 "解散" 操作(目前只能逐一移除)
- 标签拖拽排序(目前按 createdAt)

**结构性技术债**:
- ContentView.swift 已 2600 行,该按"列表 / 录入 / 工具栏 / Export"分文件
- ItemDetailView.swift 1370 行,LentOutSheet / PhotoZoomView 可以挪到 Views/
- `formatPurchaseDate` 在 Item.swift,但 InputParser 也引用 → 建议放进 common 工具

---

## 18. 记忆系统快照(`.claude/memory/`)

当前已存:
- `phase-3-search-ui.md` — 顶栏搜索 + 下方 facet chip 行,品牌从 name 词典推断不入库

记忆原则(参 MEMORY 规则):
- `user` / `feedback` / `project` / `reference` 四类
- 别存代码 / git history / CLAUDE.md 已记录的事
- 相对日期转绝对(用户开发期是 2026 年)
- 索引 `MEMORY.md` 每条一行,内容写到对应 .md 文件

---

## 19. 一句话续场

> 下次开 session,读 `PROJECT_CONTEXT.md`(本文件)+ `docs/CHANGELOG.md` + `project.yml` + `Models/Item.swift`,就能 90% 上手。剩下 10% 在 `ContentView.swift` / `ItemDetailView.swift` 里现读。
