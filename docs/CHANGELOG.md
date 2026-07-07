# Whereabouts 更新日志 / Changelog

## v0.2.0 — 2026-07-07

### build 1 — 2026-07-07

0.2.0 是"何处"第一个跨平台版本 —— iOS 版正式落地,macOS 版同步补上 AI 配置图文教程、2026 新模型与一批排布 / 文案修复。/ 0.2.0 is Whereabouts' first cross-platform release — the iOS app officially lands, while the macOS side picks up an illustrated AI setup guide, the 2026 models, and a batch of layout / string fixes.

**🎯 亮点 / Highlights**

- **iOS 版正式落地**(Phase 111):全新 iOS app,支持 iPhone 和 iPad(iOS 17+),独立的设计语言 —— 靛蓝→电光蓝品牌渐变、卡片式列表、统计瓷砖(物品 / 房间 / 置顶 / 借出)、房间 facet chips、原生下拉搜索、滑动置顶 / 删除、长按菜单;详情页全面卡片化:hero 照片区、位置面包屑、2×2「用过吗?」动作网格 + 整宽「借给…」按钮、合并时间线;底部三 tab:物品 / 记一条 / 设置。与 macOS 版共享全部数据模型、解析器和 AI 层,偏好设置的存储 key 双端同名 —— 两端行为一致。工程拆为双 target(Whereabouts=macOS、WhereaboutsiOS=iOS),共用同一个 bundle id `com.bamcope.whereabouts` 以支持 App Store universal purchase(买一次,两个平台都能用)。录入成功 / 归还 / 警告均配触觉反馈;深浅色完全适配。/ **The iOS app officially lands** (Phase 111): a brand-new iOS app for iPhone and iPad (iOS 17+) with its own design language — indigo→electric-blue brand gradient, card-style list, stat tiles (items / rooms / pinned / lent), room facet chips, native pull-down search, swipe to pin / delete, long-press menus; a fully card-based detail page with hero photo area, location breadcrumb, a 2×2 "Used it?" action grid plus a full-width "Lend to…" button, and a merged timeline; three tabs at the bottom: Items / Record / Settings. It shares every data model, the parser, and the AI layer with the macOS app, and preference keys are identical on both platforms — behavior matches on both ends. The project is now split into two targets (Whereabouts = macOS, WhereaboutsiOS = iOS) under one bundle id `com.bamcope.whereabouts` for App Store universal purchase (buy once, use on both platforms). Haptic feedback on record success / return / warnings; full light & dark mode support.
- **AI 配置图文教程网页 + app 内一键打开**(Phase 113):新的中英双语网页教程,覆盖火山引擎 / Claude 两条路线的完整流程 —— 注册 → 充值 → 拿 API key → 填入 app → 费用估算 → 报错排查。macOS 设置 → AI 顶部与 iOS 设置里都新增「查看图文配置教程(网页)」链接,一键在浏览器打开(新文案 key `settings.ai.guide.link`;链接统一收在新文件 `Shared/AppLinks.swift` 集中管理)。/ **Illustrated AI setup guide on the web, one tap away in-app** (Phase 113): a new bilingual web tutorial covering both the Volcengine and Claude routes end to end — sign up → top up → get an API key → paste it into the app → cost estimation → error troubleshooting. Both macOS Settings → AI (at the top) and iOS Settings gain a "View the illustrated setup guide (web)" link that opens it in your browser (new catalog key `settings.ai.guide.link`; all links centralized in the new `Shared/AppLinks.swift`).

**✨ 新增 / Added**

- **Claude 模型选择器补 2026 新模型**(Phase 112):新增 **Sonnet 5** 和 **Opus 4.8** 两档,旧档位全部保留。/ The Claude model picker gains the two 2026 models — **Sonnet 5** and **Opus 4.8** (Phase 112). All older tiers remain available.
- **隐私政策网页(中英)与 App Store 上架手册网页发布**;仓库同步新增 `publishing/app-store-metadata.md`(App Store 元数据文案包)与 `Whereabouts/Whereabouts-AppStore.entitlements`(macOS 沙箱 entitlements,App Store 提交用)。/ Published the bilingual **privacy policy** web page and the **App Store submission handbook** web page; the repo also gains `publishing/app-store-metadata.md` (the metadata copy pack) and `Whereabouts/Whereabouts-AppStore.entitlements` (macOS sandbox entitlements for App Store submission).

**🔧 改进 / Changed**

- **共享层重构**(Phase 111):FilterModel / SortMode、ExportSchema 与导出文档、录入决策结构(PendingDuplicate 等)、WrapLayout 与图像工具、AppearanceMode / AppLanguage、JSON 导入器(WhereaboutsImporter)从 macOS 大文件抽出,移入 `Whereabouts/Shared/` 供双端复用;macOS 行为完全不变。/ Shared-layer refactor (Phase 111): FilterModel / SortMode, ExportSchema + the export document, record-decision structures (PendingDuplicate etc.), WrapLayout + image utilities, AppearanceMode / AppLanguage, and the JSON importer (WhereaboutsImporter) were extracted from the big macOS files into `Whereabouts/Shared/` for reuse on both platforms. macOS behavior is completely unchanged.
- **MARKETING_VERSION 0.1.7 → 0.2.0。**/ MARKETING_VERSION bumped from 0.1.7 to 0.2.0.

**🐛 修复 / Fixed**

- **Opus 成本估算高估 3 倍**(Phase 112):用量估算表里 Opus 4.7 一直沿用 $15 / $75(每百万 token)的老价,官方现价是 **$5 / $25** —— 之前显示的估算是实际花费的 3 倍。Sonnet 5 按促销价 $2 / $10 计入(促销至 2026-08-31)。/ **Opus cost estimates were 3× too high** (Phase 112): the estimation table still used the old $15 / $75 per-million-token pricing for Opus 4.7, but the official current price is **$5 / $25** — the displayed estimate was triple your real spend. Sonnet 5 is priced at its promotional $2 / $10 rate (valid through 2026-08-31).
- **8 个带插值的文案 key 显示为原始 key**(Phase 112):重复检测弹窗的按钮和正文(`dup.alert.*`)、字段更新弹窗(`update.alert.*`)、详情页历史计数徽章(`detail.history.count`)、录入预览计数(`input.preview.willCreate`)在词条库里存的是不带格式后缀的 key,而运行时按 `"key %lld/%@"` 形态查找 → 查不到,界面直接显示原始 key。补齐带后缀的词条,macOS / iOS 双端修复。这是 macOS 上长期存在的隐性 bug。/ **8 interpolated strings were rendering as raw keys** (Phase 112): the duplicate-detection alert buttons and body (`dup.alert.*`), the field-update alert (`update.alert.*`), the detail-page history count badge (`detail.history.count`), and the record preview count (`input.preview.willCreate`) were stored in the catalog without format suffixes, while runtime looks them up in the `"key %lld/%@"` form — the lookup missed and the raw key showed on screen. Suffixed entries added; fixed on both macOS and iOS. This was a long-standing latent bug on macOS.
- **排布不均匀问题一揽子修复**(Phase 110):① 设置 → AI 用量的三列表从固定 70pt 列宽改为 Grid 自适应 + 数字右对齐,中英文标签宽度不同、金额位数多时不再截断挤歪;② 主窗口 facet 行的标签列从 36pt 加宽到 56pt 并限定单行,英文 "Location" 不再折行导致行高不齐;③ 火山引擎两个单价输入行改用 LabeledContent + 定宽输入框贴右,两行永远对齐;④ 通知内容模板行改为原生带 label 的 TextField。/ **A batch of uneven-layout fixes** (Phase 110): ① the three-column AI usage table in Settings switched from fixed 70pt columns to an adaptive Grid with right-aligned numbers — differing zh/en label widths and long amounts no longer truncate or skew the layout; ② the facet-row label column in the main window widened from 36pt to 56pt with single-line text, so the English "Location" label no longer wraps and unbalances row heights; ③ the two Volcengine unit-price rows now use LabeledContent with fixed-width right-aligned input fields, keeping both rows permanently aligned; ④ the notification body-template row switched to a native labeled TextField.

## v0.1.7 — 2026-05-29

### build 1 — 2026-05-29

0.1.7 是个"最后一公里"版本 —— 把 0.1.6 build 1 加的借出 / 通知 / AI 用量三个主题各自缺的一脚补上,加几个内部清理。无新功能,纯把已有功能磨到位。/ A "last-mile" release — 0.1.6's lent / notifications / AI-usage themes each had a missing edge; 0.1.7 patches them. No new features, just polish.

**🐛 修复 / Fixed**

- **借给谁、标签名搜索框搜不到**(Phase 103):0.1.6 把"借给"功能做好了 —— 详情时间线、列表 row、右键菜单全有 —— 但搜索框的 hay 数组只看 name / notes / 位置 / 型号 / 颜色 / 渠道 / 版本,**没看 `lentTo` 也没看 `tags`**。把 iPad 借给"妈妈"后,搜"妈妈"找不到;有"配件"tag 的 50 件物品,搜"配件"也搜不到。把两者加进 `FilterModel.matches(_:)` 的 hay。借出功能 + tag 系统至此都搜得到了。/ The search bar couldn't find items by who they were lent to, or by tag name (Phase 103). 0.1.6 added the lent-out feature with full UI (detail timeline, list row, right-click menu) but the search hay-stack in `FilterModel.matches(_:)` only included name / notes / location / model / color / source / version — `lentTo` and `tags` were missing. Now both are searchable: lending an iPad to "Mom" then searching "Mom" finds it; searching a tag name like "accessories" finds all items with that tag.

- **取消置顶 / 改提醒频率后旧通知留在系统里不清掉**(Phase 108):`NotificationScheduler.cancelAll()` 调的 `pendingIdentifiers()` 永远返回空数组(代码注释里就承认是 fallback),所以 `removePendingNotificationRequests(withIdentifiers: [])` 不删任何东西。用户取消置顶一件物品 → 它的 daily reminder **不会被清**,继续按老 schedule 触发,直到 app 重启 + 重调度才间接消失。同样改频率/时间/模板时 ALSO 会留旧 trigger。改:`rescheduleIfEnabled` 改调 async 版 `cancelAllCheckups()`(它用 prefix `"checkup-"` 精确清),同时删 `cancelAll()` + `pendingIdentifiers()` 两个 dead code。/ Unpinning an item or changing reminder frequency didn't actually cancel old notifications (Phase 108). `NotificationScheduler.cancelAll()` was calling a `pendingIdentifiers()` stub that always returned an empty array (the code comments admitted this was a placeholder), so `removePendingNotificationRequests(withIdentifiers: [])` was a no-op. Result: old reminders kept firing on the old schedule until the next app restart. `rescheduleIfEnabled` now calls the async `cancelAllCheckups()` which uses the `"checkup-"` prefix to precisely clear stale triggers.

**✨ 新增 / Added**

- **筛选面板加「借出」facet 行 + 跨 facet 兼容**(Phase 104):0.1.6 的借出功能没有 facet 入口,用户没法一键看「我现在在外的所有东西」。新加一行 facet「借出」,**仅在至少一件物品被借出时**才显示(零干扰),两个 chip:**借出去 N** / **在家 M**,跟其他 facet 完全相同的交互(点切换 nil ↔ 当前值,跟 room/source/brand 等可以 AND 组合 —— 例如"借给妈妈"+"卧室"组合筛"卧室借出去的"也行)。`FilterModel.lent: Bool?` 在 `matches(_:)` 里检查 `item.isLentOut == lent`。/ A new "Lent" facet row in the filter panel (Phase 104). Only appears when at least one item is currently lent out (zero clutter otherwise). Two chips: **Lent out N** / **At home M**. Same interactivity as other facet rows — toggles between nil and the chosen value, ANDs with other facets so you can pin to e.g. "lent out + bedroom" to see what's been borrowed from your bedroom.

- **通知 weekly 可选哪一天**(Phase 105):0.1.6 的"每周"频率硬编码周一(`weekday=2`),0.1.6 build 1 的代码注释里自己写了「后续可以加 weekday 自定义」。0.1.7 加上:偏好设置 → 通用 → 通知 区,频率选择「每周」时,**下方多一行 picker** 让用户从周一→周日选(英文版周一/Monday 起算)。读写 `@AppStorage("notificationWeekday")`,DateComponents 约定 1=周日 ... 7=周六。频率 picker 标签的「每周(周一)」改成单纯「每周」,跟 weekday 行解耦。/ Weekly notification frequency now lets you pick which day (Phase 105). 0.1.6 hardcoded Monday with a "TODO weekday customization" comment. 0.1.7 adds a weekday picker that appears below the frequency picker when you select "Weekly". Stored under `notificationWeekday` UserDefaults key (1=Sun ... 7=Sat per Apple's DateComponents convention). The frequency picker label changed from "Weekly (Mondays)" to plain "Weekly".

- **点击通知 banner → 自动跳到该物品**(Phase 106):0.1.6 的 `NotificationScheduler.schedule(for:)` 把 `content.userInfo = ["itemName": item.name]` 都写好了,但**没注册 UNUserNotificationCenterDelegate**,所以 tap banner 只激活 app,什么都不发生 —— 半成品。新加 `NotificationTapForwarder: NSObject, UNUserNotificationCenterDelegate`(单例),在 `WhereaboutsApp.init` 里赋给 `UNUserNotificationCenter.current().delegate`。`didReceive` 取出 `userInfo["itemName"]` 后广播 `.openItemByName` notification,ContentView 接住后调 `filter.clearAll()` + `filter.search = name`,顺手 `NSApp.activate(ignoringOtherApps: true)` 把窗口拽到前台。**额外效果**:app 在前台用时通知也会以 banner 形式出现(实现了 `willPresent` 回调返回 `[.banner, .sound]`),以前在前台时通知会"沉默"。/ Tapping a reminder notification now jumps to the item in the main window (Phase 106). 0.1.6 was writing `userInfo["itemName"]` but never registered a delegate to receive taps, so clicking a banner just activated the app and did nothing else — half-finished. A new `NotificationTapForwarder` (NSObject conforming to `UNUserNotificationCenterDelegate`) is wired up in `WhereaboutsApp.init`. On tap it broadcasts `.openItemByName`; ContentView clears the current filter, sets `filter.search` to the item name, and activates the main window. Side benefit: banners now also appear when the app is in the foreground (was previously silent in-app).

- **火山引擎用户也能看到 ¥ 估算**(Phase 107):0.1.6 的用量统计区只对 Claude provider 显示 $ 估算行(`if provider == .claude`),火山引擎用户只看到 calls / input / output tokens,没法估算花了多少钱。0.1.7 在偏好设置 → AI → 火山引擎 section 新加两个 TextField:**输入 ¥/百万 token** 和 **输出 ¥/百万 token**(都可选,空 / 0 = 不显示估算)。`AISettings.volcInputPricePerMillionCNY` / `volcOutputPricePerMillionCNY` 走 UserDefaults。`UsageSnapshot.estimatedCNYForVolcengine(inputPrice:outputPrice:)` 计算公式跟 Claude 同形 —— `(in*inPrice + out*outPrice) / 1_000_000`。任一价格 > 0 时,用量统计区显示一行 **¥** 估算,跟 Claude 的 $ 行并列。section footer 多了一句帮助:「火山方舟控制台 / model 详情页能查到单价」。/ Volcengine users now get ¥ cost estimates too (Phase 107). 0.1.6 only showed $ estimates for Claude. Two new fields in Settings → AI → Volcengine section: **Input ¥/M tokens** and **Output ¥/M tokens** (both optional — leave empty to hide the estimate row). Same formula as Claude: `(in_tokens × inPrice + out_tokens × outPrice) / 1_000_000`. Both prices stored under `ai.volc.{input,output}PricePerMillionCNY` UserDefaults keys.

**🔧 改进 / Changed**

- **清理 10 处过期 `// TODO: i18n - English parsing via LLM (planned post-Phase 7)`**(Phase 108):分布在 6 个文件(InputParser / ContentView / WhereaboutsApp / ItemDetailView / BatchEditSheets),Phase 7 早过了,英文 parser 在 0.1.5 build 3 Phase 92 已经落地。纯删,不替换。/ Removed 10 stale `// TODO: i18n - English parsing via LLM (planned post-Phase 7)` comments across 6 files (Phase 108). Phase 7 shipped long ago, English parsing landed in 0.1.5 build 3 (Phase 92). Pure deletion, no replacement.

## v0.1.6 — 2026-05-16

### build 1 — 2026-05-16

0.1.6 是个 "UX 精修 + 用户友好性" 版本 —— 把 0.1.5 build 3 加的 7 个功能挨个磨细,每一项都按用户的具体反馈打磨。/ A polish-and-friendliness release — every feature added in 0.1.5 build 3 got refined per user feedback.

**🐛 修复 / Fixed**

- **借出/归还的位置历史显示"未指定位置"**(Phase 95):0.1.5 build 3 借出时写了 `LocationLog(location: item.location)`(本来想表达"物品在原地、只是借出了"),但详情页 history 渲染时 location 字段在某些路径里被显示成了"未指定"。**重新审视**:LocationLog 是"物品在某地理位置"的记录,借出/归还**不是位置变化**,不该用 LocationLog;改为写 **EditLog** —— `field="lent"`/`source="lent_out"`,`newValue=借给的人名`;归还时 `field="returned"`/`source="returned"`,`oldValue=之前借给谁`。详情时间线现在会显示**紫色 "借出去 · 借给 XX"** 和 **橙色 "已归还 · ← XX"** 两条事件行,而不是无意义的位置 log。/ Lent / returned events were producing LocationLog rows that rendered as "Unspecified location" in detail timeline (Phase 95). Switched to EditLog rows with `field="lent"`/`source="lent_out"` (purple) and `field="returned"`/`source="returned"` (orange) so the timeline reads "Lent to XX" / "Returned from XX" — semantically what lending really is, not a location change.

**✨ 新增 / Added**

- **AI 用量统计加 day / week / month 三窗口**(Phase 96):0.1.5 build 3 只显示"本月"。现在偏好设置 → AI 用量 section 同时展示**今天 / 本周 / 本月**三列,每行(调用次数 / input token / output token / Claude USD 估算)横排对应。底部新加"口径说明":token 直接取自 API 响应的 `usage` 字段,跟 Anthropic / Volcengine 后台账单一致;调用次数 = 成功的 `understand` 调用。**实现层面**:UserDefaults 改存 daily bucket JSON dict,`{"YYYY-MM-DD": [calls, in, out], ...}`,在 getter 里按时间窗口聚合,超过 90 天的 bucket 自动 purge。/ AI usage tracking expanded from "this month" to **today / this week / this month** three columns (Phase 96). Each row (calls / input tokens / output tokens / Claude USD estimate) shows all three windows side-by-side. A new "metric calibration" footer clarifies that tokens are read directly from API response `usage` fields — same numbers the providers bill. Storage refactored to daily buckets with 90-day auto-purge.

- **底部状态栏显示 AI 就绪状态 + 实时用量**(Phase 97):配了 API key 的用户,app 启动会自动跑一次 `testConnection`,结果显示在底部状态栏:① **绿色「AI 已就绪 · 今 N · 周 M · 月 K」**(N/M/K 是调用次数);② **红色「AI 连接失败,请在何处设置中检查 API 设置是否连通」**(配上错误信息);③ 测试中 spinner。每行右侧有"重测"按钮,改了 key / endpoint 之后不用重启 app 也能立刻验。**没配 key 的用户状态栏不渲染 AI 行** —— 完全不知有这件事,零干扰。/ Status bar now shows AI readiness on launch (Phase 97). If you've configured an API key, the app pings `testConnection` at startup and shows ✅ "AI ready · Today N · Week M · Month K" or ⚠️ "AI connection failed — check Settings → AI" with the error message. A "Retest" button lets you re-check without restarting. If no key is configured, the AI row is hidden entirely.

- **全局快捷键自定义 + 双模式 QuickEntry(记一条 / 搜索)**(Phase 100):0.1.5 build 3 的 ⌥⌘N 现在可在偏好设置 → 通用里**改键位** —— 点按钮进入捕获模式(显示"按一下新键位…"),按下任意带 modifier 的组合键即可重新绑定,旁边还有"恢复默认"按钮。QuickEntry 弹窗顶部加了**双模式 segmented picker**:① **记一条**(原行为,parse + 入库);② **搜索**(关键词通过 NotificationCenter 喂给主窗口的 search field,自动展开 facet 区,聚焦主窗口)。模式会被记住下次召唤(@AppStorage)。「记一条」上方右侧加了快捷键提示「在任何地方按 ⌥⌘N」(随用户自定义同步)。/ Global hotkey is now customizable and the QuickEntry window has two modes (Phase 100). In Settings → General, click the hotkey button to capture a new shortcut (any modifier + key combination). The popup gets a segmented picker — **Record** (the original behavior) or **Search** (sends the query to the main window's search field and brings it to focus). The selected mode is remembered. A hint chip on the record bar shows the current binding.

- **通知调度完全可自定义(时间 / 频率 / 内容模板)**(Phase 99):偏好设置 → 通知 section 大改 —— 开启后多出三个控件:① **频率** picker:每天 / 每周(周一)/ 每月(1 号);② **时间** DatePicker(取 hour + minute);③ **通知内容**:多行 TextField,模板里写 `%@` 自动替换为物品名字。每次改任一字段都会自动调用 `NotificationScheduler.rescheduleIfEnabled()`,立即生效。默认值跟 0.1.5 build 3 之前的硬编码"每天 12 点 / 18 点"不同了 —— 改为更克制的"每天一次,中午 12 点",用户可自行调整。/ Notification scheduling is now fully customizable (Phase 99). Settings → Notifications expanded with: **Frequency** picker (Daily / Weekly Mondays / Monthly 1st), **Time** picker (hour + minute), and a multi-line **Body template** with `%@` substitution for the item name. Any change auto-reschedules; defaults are "once daily at 12:00" (replaces the previous hardcoded 12:00 + 18:00 twice-a-day).

**🔧 改进 / Changed**

- **位置树重构:房间 / 位置 语义分层 + 合并 + 批量操作**(Phase 101):0.1.5 build 3 的位置管理 tab 只是一个扁平的 List,所有位置无差别罗列。重构后:① **房间 section**:`parent==nil` 且名字命中房间词词典的根节点(玄关 / 卧室 / 客厅 / 书房 / 厨房 / 卫生间 / 阳台 等中英对应),用 🏠 图标;② **独立位置 section**:其它 root(没命中房间词,但用户没指定父级),提示"在 facet 里它们各自当作独立的房间"。每行新加:**合并到… Menu**(把当前节点的 items + 子节点 reparent 到选中的另一 root,然后删自己,递归处理同名冲突)+ **删除**(改为始终可用,删除前 items / children 提升到 parent,数据不丢)。顶部新增**批量操作 toolbar**:勾选多行后出现"批量删除"+"全部合并到…"按钮。Model 层加 `Location.mergeUserSelected(source:into:in:)`(防循环引用)。/ Locations management tab fully refactored (Phase 101). Roots are split into two sections by semantic: **Rooms** (matching a room-word dictionary like bedroom / kitchen / study / bathroom in zh + en) shown with a 🏠 icon, and **Independent locations** (everything else at root level). Every row gets a **Merge into…** menu (relocates items + children to another root, recursive merge of same-name conflicts) and **Delete** is now always enabled (items get promoted to parent instead of blocked). Multi-select checkboxes + batch toolbar for "Delete selected" and "Merge all into…". New `Location.mergeUserSelected` model helper with cycle prevention.

- **导入 / 导出加确认弹窗 + 强警示**(Phase 98):0.1.5 build 3 的导入 / 导出按钮点了直接弹文件对话框。现在两个按钮**点击后都先弹确认 dialog**:① 导出 → "将以 JSON 格式导出全部 N 件物品,包含名字、位置、标签、照片、购买元数据、位置历史、借出状态。不包含 API key 等敏感信息。" ② 导入 → 根据"导入时跳过重复项目"toggle 给不同信息:**开启时**"✓ 已开启 — 与本机现有物品 name + 位置完全相同的条目会被跳过,这是推荐设置";**关闭时强警告**"⚠️ 已关闭 — JSON 里的所有条目都会被追加,**包括与你现有重复的物品**,重复项目之后**难以批量删除**,建议先打开去重再导入"。toggle 也改名为更明确的「导入时跳过重复项目」。/ Import / Export buttons now show a confirmation dialog before opening the file picker (Phase 98). Export confirms what's included (and isn't) in the JSON; Import warns based on the dedup toggle: if ON, shows a reassuring message; if **OFF**, shows a stark warning that duplicates are hard to clean up afterward, suggesting users turn dedup back on. The toggle was also renamed for clarity to "Skip duplicates on import".

## v0.1.5 — 2026-05-16

### build 3 — 2026-05-16

这一版是 0.1.5 系列的"功能大补包",一次性补了 7 个 0.1.4 时代没排上的功能/改进。/ "Feature bundle" build — 7 features deferred from the 0.1.4 era, all in one release.

**✨ 新增 / Added**

- **位置管理 Settings tab**(Phase 87):偏好设置新加一栏「位置」,树状列出所有 Location,行内 TextField 可重命名,改名后整棵子树的 path 自动跟着变(`Location.path` 是计算属性,基于 parent 链)。每行右侧显示"子树物品数"统计;垃圾桶按钮**只对空叶子节点可用**(无物品 + 无子位置),非空节点的按钮 disabled 并 tooltip 提示"先把物品 / 子位置搬走"。**价值**:0.1.5 build 2 修了 AI 写脏数据的源,但**存量**脏 Location 之前没办法清理 —— 用户现在能直接看到所有位置层级,把不要的删掉、把错的改名,跟 `splitMalformedNames` 启动迁移配合起来手动清理任何遗漏的脏数据。/ New "Locations" tab in Settings (Phase 87): tree view of all Locations, inline rename via TextField, delete button enabled only on empty leaves to prevent accidentally orphaning items. Closes the gap left by build 2 — users can now manually clean any leftover dirty Locations the migration didn't catch.
- **AI 调用计数 + 估算成本显示**(Phase 88):偏好设置 → AI 顶部新加「本月用量」section,显示当月 API 调用次数 + 累计 input/output token + 估算 USD 成本(只在用 Claude 时显示,价格基于 Anthropic 公开单价:Haiku $1/$5、Sonnet $3/$15、Opus $15/$75 per M tokens)。月初自动归零(月份 key "YYYY-MM" rollover),也可以手动点"清零"按钮。Volcengine 价格因 model 而异(用户自填 model 名),只显示 calls + tokens,不估算金额。AIClient 的 Response struct 扩了 `usage` 字段解码 —— Claude 用 `input_tokens`/`output_tokens`,Volcengine(OpenAI 兼容)用 `prompt_tokens`/`completion_tokens`,每次 understand 成功后调 `AISettings.bumpUsage` 累加。/ AI usage tracking + cost estimation (Phase 88). New "Usage this month" section in Settings → AI shows call count, accumulated input/output tokens, and estimated USD cost (Claude only, based on Anthropic's public pricing). Auto-resets at month boundary. AIClient now decodes the `usage` field from each Response and bumps counters.
- **全局快捷键 ⌥⌘N 召唤"快速录入"窗口**(Phase 89):新加 `GlobalHotKey.swift`(Carbon `RegisterEventHotKey` API),系统级注册 Option+Command+N,在**任何 app 内**按下都会弹出一个独立 SwiftUI Window scene `quickEntry`(480×220),里面是一个 4 行 TextField + 提交按钮 + Esc 取消。单条提交 → 自动关闭窗口;多条提交 → 短暂 toast 后窗口保留让你再录。**不需要 Accessibility 权限**(跟 NSEvent.addGlobalMonitorForEvents 不同 —— Carbon HotKey 是注册"组合键 → app event"映射,不监听键盘事件)。可以在偏好设置 → 通用关掉,toggle 改变时立即 register/unregister。**实现细节**:Carbon 回调是 C 函数,通过 NotificationCenter post `.openQuickEntry` 通知,主 scene 上的 `QuickEntryHotKeyObserver` ViewModifier 收到后调 `openWindow(id: "quickEntry")` + `NSApp.activate`。/ Global hotkey ⌥⌘N to open a quick-record window from anywhere (Phase 89). Uses Carbon `RegisterEventHotKey` — no Accessibility permission needed. Toggle in Settings → General to enable/disable; takes effect immediately.
- **物品"借出去"状态**(Phase 91):Item 加 `lentTo`/`lentAt` 两个可选字段(SwiftData 轻量迁移,旧数据 nil),配两个新方法 `markLentOut(to:)` 和 `markReturned()`。**入口**:① 详情页"用过吗?" section 新加第 5 个紫色按钮「借给…」,点开 `LentOutSheet` 输入借给谁;② 右键菜单根据 `isLentOut` 动态显示"借给…"或"归还";③ 详情页 header 在 location 行下方多一行**橙色 capsule**「已借给 XX · X 天前」+ 行内"归还"按钮;④ 列表行在 location 下方多一行紫色「借给:XX」提示。归还时清两字段 + lastActionType="returned" + 写一条 LocationLog(标记物品又回来了)。位置本身**不动** —— 借出时 location 保留为"本来该在的地方",物理状态用 lentTo + lentAt 表达。/ Lent-out state for items (Phase 91). New `lentTo` / `lentAt` fields with full UI: detail-page badge, list-row hint, fifth action button, right-click context menu. Location is preserved when lent out (the item's "home"); returning it just clears the lent fields and writes a history log.
- **英文 parser 模式扩充**(Phase 92):InputParser 在中文 splitter 都没匹中时新增**英文 fallback**。支持的句式:`X is in Y` / `X at Y` / `X on Y` / `X is located in Y` / `X: Y`(name-first),以及 `Y has X` / `Y contains X` / `Y holds X`(location-first)。位置串拆段识别 `>` / `/` / `,` / `→`,剥英文冠词(`the kitchen` → `kitchen`),case-insensitive 匹配。**防误切**:`looksEnglish` 检查只在没有中文字符且有英文字母时启用 —— 中英混写或纯中文不进英文路径,中文用户行为完全不变。元数据抽取(model/color/version/date/source)继续靠中文词典(英文用户配 AI key 走 LLM 路径更准)。/ English parser fallback (Phase 92). When the Chinese splitters miss, try English patterns like `X is in Y` / `Y has X`. Guarded by `looksEnglish` so Chinese-only / mixed input stays on the Chinese path. Field extraction (model/color/version) still relies on the Chinese dictionaries — overseas users should configure an AI key for full coverage.

**🔧 改进 / Changed**

- **数据导出 schema bump v1 → v2 + 导入去重 toggle**(Phase 90):ExportSchema 加了 5 个新字段(`tags`/`lentTo`/`lentAt`/`isPinned`/`relatedGroupID`),都是 optional → 老 v1 文件读取**完全向后兼容**。导入路径加 `importDedupEnabled` toggle(@AppStorage,默认 ON):开启时按 `name + path` 签名去重,跳过已存在的条目;关闭时全部追加(可能产生重复)。导入完成后弹绿色 ack:「已导入 N 件,跳过 M 件」。Tag 按名字反查并复用本机已有 Tag,本机没有就 ensure 新建(色用默认 #5AC8FA)。RelatedGroup ID 直接复用 UUID 字符串。**注意**:`name+path` 比对是大小写敏感的,故意保留 "iphone" / "iPhone" 这种细粒度差异。/ Export schema v1 → v2 (Phase 90). Five new optional fields added (tags / lent / pin / related). Import gained a dedup toggle (default ON) — skips items whose name+path matches existing. Backward-compatible: v1 files read fine, just don't have the new fields.
- **PROJECT_CONTEXT.md 更新到 0.1.5**(Phase 93):内部技术备忘文档之前停在 0.1.1 时代(2026-05-11),跟现实差太远。更新:① 版本号 / 日期 / 总行数;② 仓库结构加新文件(LocationsSettingsTab、GlobalHotKey、AI/、EditLog、RelatedGroup、BatchEditSheets 等);③ Phase 列表从"0-11"重写为按版本归纳(0.1.0-0.1.5);④ §17 当前未做改成 0.1.5 视角的"已搁置 + 可能近期做的 + 结构性技术债"。**用户不可见**(纯内部 onboarding 文档),但对未来 session 启动后接手项目有用。/ Internal project-context doc refreshed to 0.1.5 state (was stuck at 0.1.1). Not user-visible.

### build 2 — 2026-05-16

**🐛 修复 / Fixed**

- **AI 把无标点的复合中文位置串当一段塞,污染"房间"facet**(Phase 86):用户输 "xxx 在门口电梯间鞋架上方",AI 输出 `locationPath: ["门口电梯间鞋架上方"]` 一整段。这条 path 数组第一段会被 facet 当成"房间"用于筛选,结果"房间"列表里出现一条 11 字超长项,而不是合理的"门口"。根因:0.1.4 build 4 (Phase 67) 加的 rule 8 子条款"完整不可分的描述就当一段"被 AI 错误推广到了所有无标点串。修法:default prompt rule 8 新加"**复合位置串拆段**"小节,明确**数组第一段会被视为房间用于筛选 facet**,并给出三类启发式 —— ① 开头的房间/区域词(玄关/门口/电梯间/卧室/客厅/书房/厨房/卫生间/阳台/储物间/衣帽间/办公室 等)**必须**独立成第一段;② 容器/家具词(鞋架/抽屉/柜子/书架/盒子/塑料盒 等)代表下一层,独立成段;③ 方位/序号词(上方/下方/里面/第一层/第二层 等)是修饰词,绑在前面的容器上。给了 4 个 ✓ 例子覆盖典型形态。`["门口", "电梯间", "鞋架上方"]` 是新规则下的正确输出。改的是 default —— 你在偏好设置 → AI 里改过的提示词不会被覆盖,改过的人想拿到新版要去 AI 设置点一下"恢复默认"。**注意**:已经存进库里的脏 Location(比如 "门口电梯间鞋架上方")**不会自动修**(房间词词典靠 app 端维护风险太高,容易误伤具体物品名),需要手动:① 进物品详情点"设置位置"chip 重输正确层级(app 的 sanitizePath 会处理 `>` 分隔),或 ② 重新让 AI 跑一遍(新 prompt 生效后)。/ AI was treating undelimited compound Chinese location strings as a single segment, polluting the "Room" facet (Phase 86). Input like "xxx at front-door elevator-lobby shoe-rack-top" produced `locationPath: ["门口电梯间鞋架上方"]` — one 11-character segment ended up in the Room facet instead of the correct "门口" (front door). Root cause: 0.1.4 build 4's rule 8 sub-clause "treat indivisible descriptions as one segment" got over-generalised. Fix: rule 8 gained a new **"compound-string segmentation"** subsection telling the model that **the first array element is treated as the Room facet**, with three heuristics — ① opening **room/area words** (entryway, front door, elevator lobby, bedroom, living room, study, kitchen, bathroom, balcony, etc.) **must** be split as the first segment; ② **container/furniture words** (shoe rack, drawer, cabinet, bookshelf, box, etc.) usually mean a level boundary and split too; ③ **position/ordinal words** (top, bottom, inside, layer 1/2/3, etc.) are **modifiers** that stick to the preceding container word. Four ✓ examples cover typical shapes. Only touches the *default* prompt; custom ones in Settings are preserved (use "Restore default" in Settings → AI to pick up the new wording). **Note**: existing dirty Locations already in the DB are **not** auto-fixed (a room-word dictionary on the app side is brittle and risks false splits on actual item names) — manually re-enter the location via the detail page chip, or re-run AI on that item.

## v0.1.4 — 2026-05-13

### build 10 — 2026-05-13

**🐛 修复 / Fixed**

- **重复"书房"根仍然存在**(Phase 82):build 7 的 dedup 迁移用 `@AppStorage("mergedDuplicateRoots_v1")` 只跑一次,但 build 7 之后用户继续添加物品时,**并发 AI 调用**(useAIOnInput 打开 + 用户快速录入多条 → 多个 Task 同时 `Location.ensure` → 各自 fetch 没看到对方的新 root → 各自创建)会产生新的同名根。改:去掉 once-only flag,**每次启动都跑** dedup —— 函数本身幂等且廉价(干净时一次 fetch 退出),没必要省。/ Duplicate "书房" roots still appearing (Phase 82): build 7's dedup migration was guarded by a one-shot `@AppStorage` flag, but new duplicates emerged afterward from **concurrent AI calls** (each `Location.ensure` fetched stale data and created its own copy). Removed the flag — dedup now runs on every launch (idempotent, no-op when clean).
- **Location.name 含 `>` 的脏节点**(Phase 81 + 82):用户筛选里看到 `房间` 行出现 `"书房 > 绿色随身无线充盒子"` 当根 —— AI 偶尔把多层路径塞进单段(`locationPath: ["书房 > X"]`),老 `ensure` 直接 create 名字带分隔符的 Location。修法两层:① 新加 `Location.sanitizePath([String])`:每段先按 `>` / `》` / `→` / `->` / `/` 内部拆分,`ensure` 和 `bestMatchOrEnsure` 入口都走它,**新数据不会再脏**。② 新加 `splitMalformedNames` 迁移:扫现有库里 name 含分隔符的 Location,展开成正常多层树,reparent items/children/LocationLog,删原脏节点。每次启动都跑(跟 dedup 一起,先拆后合)。/ Stale Locations whose names contain `>` (Phase 81 + 82): users saw entries like `"书房 > 绿色随身无线充盒子"` in the room facet — AI occasionally returned a multi-segment path as a single string with `>` separator, and the old `ensure` accepted it as a single segment name. Two-layer fix: ① new `Location.sanitizePath(_:)` splits each input segment on internal separators, applied at the `ensure`/`bestMatchOrEnsure` entry points — new writes are clean. ② new `splitMalformedNames` migration scans the existing DB, expands malformed names into proper tree levels, reparents items/children/logs, then deletes the dirty node. Runs on every launch alongside dedup (split first, then merge).
- **顶部和底部栏半透明、List 滚动时物品文字透过来**(Phase 84):`inputBar` 用 `Color.accentColor.opacity(0.06)`、`searchHeaderBar` 用 `Color.secondary.opacity(0.10)` —— 都是半透明,只在自己有内容时不透。Phase 79 用 `.safeAreaInset(edge: .top)` 钉死后,List 滚动会跑到顶栏背后,物品文字透过浅色覆盖层显出来。修:在 safeAreaInset 内容外层再加一层 `Color(nsColor: .windowBackgroundColor)` 不透明 base,inputBar / searchHeader 的 accent 浅色覆盖在它上面,List 永远透不过来。状态栏底栏同样处理。跨平台:macOS 用 `windowBackgroundColor`,iOS 用 `systemBackground`。/ Top + bottom bars were translucent — list items bled through the pinned chrome (Phase 84). `inputBar`'s `Color.accentColor.opacity(0.06)` and `searchHeaderBar`'s `Color.secondary.opacity(0.10)` are intentional accent tints, but the safeAreaInset wrapper had no opaque base — the list rendered behind. Added an opaque `Color(nsColor: .windowBackgroundColor)` (iOS: `.systemBackground`) layer beneath both top and bottom inset content. Tints now sit on top of opaque ground; list rows can never show through.

**🔧 改进 / Changed**

- **AI default prompt 强调 path 段是纯名字**(Phase 83):rule 8 加一段格式规范 —— `locationPath` 数组的**每一段必须是纯名字**,绝不能包含 `>` / `》` / `→` / `->` / `/`。层级关系只能通过数组本身表达。配上 ✓/✗ 例子:✓ `["书房", "绿色随身无线充盒子"]`;✗ `["书房 > 绿色随身无线充盒子"]`。配合 Phase 81 的应用层 sanitize 双重防御。改的是 default,不会覆盖你在偏好设置里自定义过的 prompt。/ AI default prompt explicitly forbids separators inside path segments (Phase 83): rule 8 was extended with a format-strictness clause — `locationPath`'s segments must be plain names, never containing `>` / `》` / `→` / `->` / `/`; hierarchy is encoded by the array itself. Includes ✓/✗ examples. Backs up the Phase 81 app-side sanitization. Only touches the *default* prompt; custom ones in Settings are preserved.

### build 9 — 2026-05-13

**🐛 修复 / Fixed**

- **筛选面板太高仍然挤走顶部 chrome**(Phase 80):build 8 用 `.safeAreaInset(edge: .top)` 钉死了 quote / inputBar / search field,但用户库里位置很多时 facet 面板会自然撑到 400+pt,加上顶部 chrome ~210pt + 标题栏 + 底部状态栏,总和超过窗口高度;SwiftUI 在这种过载情况下会反过来压缩顶部 inset,quote 和 inputBar 又被挤出可视区。新修法:`facetExpansionPanel` 内部包一层 `ScrollView` + `.frame(maxHeight: 280)`,把面板自身高度硬封顶。chip 行多就在面板内滚动,**绝不**侵占顶部固定区。280pt 大致够 3 行 chip 直接显示,多了内部滚动条出现。/ Filter panel was still squeezing the top chrome when facets were very tall (Phase 80). Build 8 pinned the quote/record bar/search via `.safeAreaInset(edge: .top)`, but with lots of locations the facet panel grew to 400+pt and the total exceeded the window height — SwiftUI then compressed the top inset back. New fix: `facetExpansionPanel` is now wrapped in a `ScrollView` with `.frame(maxHeight: 280)`. The panel hard-caps at 280pt and scrolls internally beyond that; the pinned top bar is never encroached upon.

### build 8 — 2026-05-13

**🐛 修复 / Fixed**

- **筛选展开会把名言/记一条/搜索框挤出视区**(Phase 79):build 5 把窗口尺寸钉住后,展开 facet 时整个 VStack 仍按"自上而下塞"布局 —— facet 行变高 → List 压缩不下 → SwiftUI 把顶部元素往上推出窗口。重构布局:把 `quoteBanner` / `inputBar` / `searchHeaderBar` 全部塞进 `.safeAreaInset(edge: .top)`(钉死,SwiftUI 当 chrome 处理),主 VStack 只剩 `facetExpansionPanel`(只在展开时出现)+ `content`。这样 facet 展开**只压 List**,顶部三件套永远不动。加了 `.transition(.move(edge: .top).combined(with: .opacity))` 让 facet 行像下拉菜单一样滑入。/ Filter expansion was pushing the quote / record bar / search field out of view (Phase 79). After build 5 locked the window size, expanding facets still pushed everything upward in the VStack. Refactored: `quoteBanner`, `inputBar`, and `searchHeaderBar` are now installed via `.safeAreaInset(edge: .top)` so SwiftUI treats them as pinned chrome; the main VStack contains only `facetExpansionPanel` (visible only when expanded) plus `content`. Facet expansion now compresses only the list area. Added a slide-from-top + opacity transition so it animates like a dropdown into the list region.

### build 7 — 2026-05-13

**🐛 修复 / Fixed**

- **重复"房间"位置合并迁移**(Phase 76):用户报告 facet 里出现两个独立的"书房"根(一个 100+ 项,一个 2 项)。根因是早期 Phase 60 还没生效时,case-sensitive 的 `ensure` 会把"书房" / "书房 "(尾空格)/ 不同 unicode 形态当作不同根,日积月累就有了双胞胎。新加 `Location.mergeDuplicateRoots(in:)`:按 `foldedForMatch` 分组、subtree item 数最多的当 survivor、把其它 dup 的 `items` / `LocationLog.location` / 子节点全 reparent 到 survivor、然后删 dup;子节点 reparent 时若 survivor 已有同名子,**递归合并**。`@AppStorage("mergedDuplicateRoots_v1")` 标记只跑一次;完成后弹底部 toast 告知数量。/ Duplicate-room merge migration (Phase 76): users reported the location facet showing two independent "Study" roots (100+ items in one, 2 in another). Caused by the legacy `ensure` running case-sensitively before Phase 60. New `Location.mergeDuplicateRoots(in:)` groups roots by `foldedForMatch`, picks the one with the largest subtree as the survivor, reparents items + children + LocationLogs from the duplicates, recursively merging deeper-level same-name children too, then deletes the duplicates. Guarded by a one-shot `@AppStorage` flag.

**🔧 改进 / Changed**

- **筛选行"位置"拆成"房间"+"位置"两行**(Phase 77):以前一行 facet 混了根节点("书房")、子节点("收纳抽屉")、完整路径("书房 > 收纳抽屉"),还把"任一祖先节点匹中即命中"作为筛选语义,既乱又模糊。现在:① **房间** 行:只列 `parent==nil` 的根 Location,计数为该房间整棵 subtree 的物品数;② **位置** 行:只列非根 Location(以及没指定房间的孤儿叶子),用 `Location.path` 完整路径显示,匹配 `item.location.path` 精确相等。`FilterModel` 加 `room: String?`,`matches(_:)` 同时检查 room(顶层祖先名 == 选中)和 location(完整 path == 选中);二者可同时设置(房间筛子树、位置精确钉)。/ Location facet split into "Room" + "Location" rows (Phase 77): the previous single row mixed root nodes ("Study"), inner nodes ("Storage drawer"), and full paths ("Study > Storage drawer") with "matches any ancestor name" semantics — both noisy and ambiguous. Now: ① **Room** row lists only roots (`parent==nil`), count = items in that room's entire subtree; ② **Location** row lists non-root Locations (plus orphan leaves without a room) by full `Location.path`, matching `item.location.path` exactly. `FilterModel` gained `room: String?`; `matches(_:)` checks both — room narrows by subtree, location pins by exact node. Both can be active simultaneously.

### build 6 — 2026-05-13

**🐛 修复 / Fixed**

- **详情页"位置变了"chip 改为替换而非追加**:点击自动完成 chip 时,以前是把 chip 的 path 追加到输入框末尾(`"AAA"` + 点击 `"BBB"` → `"AAABBB"`,然后保存就把位置错存成 `"AAABBB"`)。现在点 chip 直接**替换**整段。这跟"记一条"输入框的 chip 行为故意不同 —— 那边在组装 `"X 在 Y"` 句子,需要追加;**这里是只输位置的字段,应该替换**。/ Detail page "Location changed" autocomplete chips now **replace** instead of appending: clicking a chip while the input held `"AAA"` used to produce `"AAABBB"` and save the bogus combined location. The chip now replaces the input outright. (Different from the record-bar chips by design — that one composes an "X at Y" sentence so it must append; this is a location-only field so it must replace.)

**✨ 新增 / Added**

- **右键批量"设置位置" sheet 加自动完成 chip 行**:跟详情页 locationEditor 同款两行 chips —— 检测到房间名就显示「<房间> 内」chips,加上「最近用过」chips。点击 chip 同样**替换**输入(不追加)。批量 commit 走 `Location.bestMatchOrEnsure`(case-insensitive + 合并相邻段 + 全局兜底查),跟 AI 路径一致 —— 不会因为大小写/全半角误判建新位置。/ Right-click "Set Location" batch sheet gained autocomplete chips: same two rows as the detail-page editor ("Inside <room>" + "Recent locations"), clicking also replaces the input. Batch commit switched from `Location.ensure` to `Location.bestMatchOrEnsure`, so case-insensitive matches + adjacent-segment joins + global fallback all apply, matching the AI path.

### build 5 — 2026-05-13

**🐛 修复 / Fixed**

- **多物品输入时位置自动传染到 sibling**(Phase 72):"xx位置当中有 1、2、3" 以前只有第 1 个 item 挂上 xx 位置,2 和 3 都没有 location。`parseMultiple` 新加 `propagateSiblingLocations` 后处理:forward fill(空位继承最近前面的非空) + backward fill(开头空段继承第一个非空)。**不依赖 AI**,parser 层直接补。/ Sibling-location propagation in multi-item input (Phase 72): "items 1, 2, 3 at xx" used to only attach the first to xx. `parseMultiple` now post-processes with forward-fill + backward-fill so siblings inherit location. Works without AI.
- **窗口展开筛选时状态栏被挤出可视区**(Phase 74):主 `WindowGroup` 之前没设 `.defaultSize` / `.windowResizability`,SwiftUI 默认按内容自适应窗口高度,facet 行展开会让整个窗口长高,状态栏掉出底边。加 `.defaultSize(1024×720)` + `.windowResizability(.contentMinSize)` + ContentView 最小 720×540 约束。窗口现在初始 1024×720 稳定,用户可手动放大,但 SwiftUI 不再自动改高度。/ Filter dropdown was pushing the status bar out of view (Phase 74): the main `WindowGroup` had no `.defaultSize` or `.windowResizability`, so SwiftUI auto-sized the window to fit content — expanding facets grew the window vertically until the status bar fell off the bottom edge. Added `.defaultSize(1024×720)` + `.windowResizability(.contentMinSize)` + a min-size constraint. Window now stays put unless the user resizes it manually.

**✨ 新增 / Added**

- **AI typo 容错 — 传 available_locations 给模型**(Phase 73):AI payload 新加一段"用户本机现有位置列表"(按最近使用排序,上限 50 条 path)。default prompt rule 8 加 typo 容错条款:用户输 "塑料袋抽屉",列表里有 "塑料抽屉" → AI 输出 ["塑料抽屉"] 复用已有,不是凭空建新。匹配宽容到 1-2 字符差异、同音、繁简、大小写、全半角。/ AI typo correction via `available_locations` (Phase 73): AI payload now includes the user's full location list (sorted by recency, capped at 50). The default prompt's rule 8 was extended with a typo-tolerance clause: input "plastic bag drawer" while you already have "plastic drawer" → AI emits the existing path, not a new one. Tolerance includes 1-2 character diffs, homophones, traditional/simplified, case, full-width/half-width.

### build 4 — 2026-05-13

**🐛 修复 / Fixed**

- **AI 多物品混写时不再串改名字**(Phase 67):"各种国外银行卡、国外信用卡在抽屉第三层"以前会被 AI 错改成两个奇怪条目(name 互相串)。default prompt 加规则:rawInput 里有多件物品(顿号/逗号/`和`分隔)时,**只负责当前 fields 描述的那一件**,不要把别条的 name 抄过来。/ AI no longer cross-pollinates names when raw input contains multiple items (Phase 67). Previously, "various foreign bank cards, credit cards in the third drawer" could produce two entries whose names were swapped from each other. The default prompt now explicitly states: when raw input mentions several items, only refine the one described by current fields.
- **AI 保留 name 里的量词**(Phase 67):"3 个 Magic Keyboard 键盘"以前会被 AI 简化成 "Magic Keyboard 键盘",量词丢了。default prompt 加规则:`3 个 / 2 副 / N 张 / N 盒 / N 套 / N 件 / N 本 / N 瓶 / N 条 / N 把 / N 根` 等量词必须保留。/ AI now preserves quantity words in `name` (Phase 67): "3 个 Magic Keyboard keyboards" used to lose the count; the default prompt now lists the common quantity classifiers as mandatory-to-keep.
- **位置反查支持"合并相邻段"**(Phase 68):AI 把 "得力塑料抽屉第三层" 拆成 `["得力塑料抽屉","第三层"]` 时,`Location.bestMatchOrEnsure` 现在会尝试**把剩余段 join 起来**在当层 / 全库查 —— 命中已有单段叶子直接复用,不再凭空多建一层 location 树。/ Location lookup gained **adjacent-segment join** (Phase 68): when AI returns a path like `["MUJI box","Section 3"]` while you already have a single-leaf `"MUJI box Section 3"` somewhere, `bestMatchOrEnsure` now joins the remaining segments and searches at the current level + globally as fallback, finding the existing leaf instead of building a new two-level subtree.

**✨ 新增 / Added**

- **详情页 AI 改名旁有 ↩ 还原按钮**(Phase 69):EditLog 行 `field == name && source.hasPrefix("ai_")` 且当前 name 仍是 AI 设置的那个时,右侧显示橙色"还原"小按钮。点 → `item.name = log.oldValue` + 写一条 `source = "restore"` 的 EditLog,在时间线上以橙色色点 + "用户还原"出现。每条 AI 改名独立显示按钮,还原过的 / 已被覆盖的 AI 改名行不再显示。/ ↩ Restore button beside AI-modified name rows in the detail history timeline (Phase 69): EditLog rows where `field == "name"` and `source.hasPrefix("ai_")` and current `item.name` still equals the AI-set value get a small orange Restore pill. Clicking reverts the name to `log.oldValue` and writes a new `source = "restore"` EditLog (orange in the timeline). Already-restored or overridden rows hide the button.
- **AI prompt 加分类提示**(Phase 67):default prompt rule 9 多了一段示意 —— "信用卡/银行卡/身份证/护照/驾照 → 票据证件;化妆/护肤 → 化妆护肤;…" 等常见映射。AI 命中扩出的 14 个预设标签的几率显著提升。/ AI default prompt got category hints (Phase 67): rule 9 now includes a short mapping reference — "credit cards / IDs / passports → Documents; cosmetics / skincare → Beauty; …" etc. Helps the AI hit the right one of the 14 expanded preset tags.

**🔧 改进 / Changed**

- **AI prompt 整体迭代**(Phase 67):规则数从 7 条扩到 9 条,新加 ① 多物品 rawInput 上下文(不串改),② 数量量词保留,③ 位置消歧建议(完整位置描述就一段输出 ["xxx第三层"],别拆),④ 分类提示。改的是 default —— 你在偏好设置 → AI 里改过的提示词不会被覆盖。/ AI default prompt iterated (Phase 67): rules expanded from 7 to 9, adding multi-item rawInput discipline, quantity preservation, location-segment guidance ("treat indivisible location descriptions as a single segment"), and category hints. Only touches the *default* prompt — custom ones in Settings are preserved.
- **帮助文档(顶栏 → 帮助 → 何处帮助)同步到 0.1.4 build 4**(Phase 70):17 大节中英双语对称,覆盖 AI 理解、项目关联、品牌、三态批量标签、位置自动完成、扩充的标签集、还原按钮 等所有 0.1.4 新功能。文档此前停在 0.1.1,本次大补。/ Help docs (Help menu → Whereabouts Help) synced to 0.1.4 build 4 (Phase 70): 17 sections, fully bilingual and symmetric, covering AI understanding, related items, brand, tri-state batch tags, location autocomplete, expanded tag set, restore button, and every other 0.1.4 feature. Docs had been stuck at 0.1.1; this is a big catch-up.

### build 3 — 2026-05-13

**✨ 新增 / Added**

- **预设标签从 6 个扩到 14 个**(Phase 59):新增「化妆护肤 / 服饰鞋包 / 药品健康 / 食品干货 / 票据证件 / 玩具收藏 / 户外运动 / 宠物用品」8 个预设,覆盖收纳困难人群常见品类。升级机制是**版本化迁移**:`seededTagPresetVersion` 记当前已 seed 到哪版,本次升级到 v2 → 只补这 8 个新加的预设;**用户自建的、改过名的、删过的标签一律不动**。`tagKeywordHints` 同步加了几百个关键词,自动建议标签的命中率显著提升。/ Preset tag set expanded from 6 to 14 (Phase 59): added Beauty / Apparel / Health / Food / Documents / Hobby / Outdoor / Pets. Migration is version-tracked — only newly added presets are seeded; custom / renamed / deleted tags stay untouched. The keyword dictionary that powers auto-tag-suggest grew by hundreds of entries.
- **输入框自动完成上浮房间内位置**(Phase 62):「记一条」文本里检测到已存在的房间名(如「书房」)→ 在「最近用过」chips 上方再加一行「<房间> 内」chips,直接列出该房间的子位置。点击 chip 把完整路径追加到 draft。最长名命中(避免「床」抢「床头柜」)、case-insensitive。/ Smarter record-bar autocomplete (Phase 62): when the draft mentions an existing room, an "Inside <room>" chip row appears above the "Recent locations" row, listing the room's direct sub-locations. Longest-name match, case-insensitive.
- **详情页"位置变了"也加了自动完成**(Phase 63):跟输入框同款的「<房间> 内」+「最近用过」chip 提示。点击 chip 追加到位置文本框。/ "Location changed" editor in the detail page now has autocomplete chips (same logic as the record bar).
- **没配 AI key 时,输入框下方显示紫色强推荐胶囊**(Phase 65):点击直接打开偏好设置 AI tab(用 SettingsLink,跨进程都对)。配过 key 的用户不显示这行,免得占位。/ No AI key configured? A purple "set up AI" chip is shown under the record bar (Phase 65); clicking it opens Settings → AI directly via SettingsLink.

**🔧 改进 / Changed**

- **位置匹配现在不区分大小写 / 全半角 / 变音符**(Phase 60):新加 `String.foldedForMatch` 帮助函数 + `Location.bestMatchOrEnsure(path:)`。AI 返回粗略路径 `["书房","MUJI塑料盒"]` 时走"最长匹配"反查 —— 库里若有更深的 `["书房","MUJI塑料盒","HiFi零件"]`,自动用更深那个,不会丢层。直接修了你举的 MUJI 塑料盒 HiFi 零件 vs MUJI 塑料盒 误判 bug。/ Location matching is now case- / width- / diacritic-insensitive (Phase 60). New `String.foldedForMatch` + `Location.bestMatchOrEnsure(path:)`. AI-returned rough paths resolve via longest-match: a rough `["Study","MUJI box"]` correctly resolves to your existing deeper `["Study","MUJI box","HiFi parts"]` instead of creating a duplicate at the shallower level.
- **AI 默认 prompt 改进**(Phase 61,改的是 default,你在偏好设置里改过的不会被覆盖):①rule 1 合并 rule 6 的位置消歧,明确"匹配时忽略大小写/全/半角差异";②`purchaseSource` schema 注释扩到"任何来源描述都行:京东/闲鱼/线下/朋友送的/二手/公司发的...";③对位置路径强调"locationPath 数组从最外层到最里层,例 ['书房','MUJI塑料盒','HiFi零件']"。/ AI default prompt improved (Phase 61, only touches the *default* — custom prompts in Settings are preserved): rule 1 absorbed rule 6 and now explicitly says matching ignores case / full-width / half-width differences; the `purchaseSource` schema doc expanded to accept any acquisition wording (Taobao, secondhand, gifted, company-issued, etc.); locationPath emphasises outermost-to-innermost array order with concrete example.
- **本地 parser:无 AI 时也能识别"位置在前,物品在后"的口语**(Phase 64):"书房桌上有 AITO 专项游戏采集底座" / "床头柜上的钥匙" / "盒子里的电池" 这种 location-first 句式现在能切对。识别词:`有 / 里有 / 里的 / 上的 / 中的 / 下的 / 里面有 / 上面有 / ...`。**防误切**:左半部分必须含已知场所词,否则不切(避免"我有 iphone" 被切坏)。/ Local parser now recognises location-first phrasing without AI (Phase 64): "书房桌上有 AITO 底座" splits as loc="书房桌上" / name="AITO 底座". Triggered by `有 / 里有 / 里的 / 上的 / ...` only when the left-hand side contains a known place word — guards against false splits like "I have an iPhone".

### build 2 — 2026-05-13

**✨ 新增 / Added**

- **项目关联功能**(Phase 52-56):右键 → 「关联到…」、详情页和编辑页都能加。详情页里列出当前组的其它物品,每件用蓝色超链接渲染 —— 点一下 inspector 立即切到对方的详情。一组关联最多 8 件物品,可以有无数组。关联是**双向 + 传递闭包**:A 关联 B,二者同组;再让 C 关联 A 或 B,三者同组(C 加入已有的组,不会另起新组);两个已存在的组合并,只要总数 ≤ 8 就能合到一起。每行右侧 × 单独移除一件;移除后若组里只剩 1 件,那一件也自动出组(不留 1 件孤儿组)。/ Related items feature (Phase 52-56): right-click → "Link to…", plus entries on the detail and edit pages. The detail page lists the other items in your group as link-styled buttons — clicking one instantly swaps the inspector to that item's detail. Each group caps at 8 items; unlimited groups; **bidirectional + transitive**: A↔B and then C links A makes A↔B↔C (C joins the existing group rather than starting a new one); merging two existing groups works as long as the combined size ≤ 8. The × on each row removes just that peer; if the group is reduced to a single item it dissolves automatically (no orphan 1-item groups).
- **编辑页显示品牌**(Phase 51):「可选信息」section 里现在多一行只读品牌,从物品名实时推断 —— 跟列表行 chip / 详情页 chip 三处统一。改名字时这一行自动跟着变,不需要手动维护。/ Brand row in the edit form (Phase 51): the "Optional info" section now shows a read-only Brand row derived live from the item name, matching the brand chip on rows and the detail page. Changing the name updates the displayed brand automatically.

### build 1 — 2026-05-13

#### ✨ 新增 / Added

- **物品保留原文**(Phase 43):「记一条」里写的整段话现在会存到每条物品的 `rawInput` 字段。AI 再理解某条时,会把这段原文作为「最高解释依据」一并发给模型 —— 用户罗里吧嗦把好几件东西混着写、地点说得含糊时,AI 能从相邻提到的房间/别称里补齐推理。/ Items now store the original raw input: the full text you typed in the record bar is saved on every item created from that turn. When AI re-understands an item, the raw text is forwarded as the highest-priority context — so multi-item paragraphs and vague location references can be disambiguated using nearby phrasing.
- **品牌 chip 出现在详情和列表行**(Phase 45):以前只在筛选行有「品牌」facet,现在每条物品的列表行和详情页字段 chip 里都会显示品牌(从 `name` 即时识别,不入库),跟筛选行保持一致。/ Brand chip on rows + detail (Phase 45): previously only the filter row exposed brand; now the inline chip strip in both the list row and the detail page also shows the brand (derived on-the-fly from `name`, never persisted), matching the filter facet.
- **「记一条」下方使用提示**(Phase 48):空状态下输入框下方加了两行 footnote 教程 —— 说明可以连续记多条(换行/分号/逗号分隔)、位置可省略可自然语言写、输入同名会问要不要更新已有物品。/ Empty-state hint under the record bar (Phase 48): a tiny two-line footnote in the input area explains the multi-record syntax (newline / semicolon / comma), the free-form location, and the same-name update prompt.

#### 🔧 改进 / Changed

- **搜索框常驻 + 筛选行折叠**(Phase 46):以前一个 chevron 同时收起搜索框和 4 行 facet。现在搜索框始终可见,旁边一个小 chevron 按钮单独控制 facet 行(位置/渠道/年份/品牌)的展开。已选中的筛选 chip 在折叠状态下也会显示,免得用户不知道当前有什么 filter 生效。/ Search field always-on, filter rows collapsible (Phase 46): the chevron used to fold the search field and 4 facet rows together; now the search box is permanently visible and a dedicated chevron next to it expands/collapses the facets (location · source · year · brand). Active filter chips remain visible in either state so applied filters never go hidden.
- **批量标签编辑改为三态**(Phase 47):以前右键多选 → 设置标签 sheet 只能加不能减。现在每行 tag 显示三态 —— ✓(全部挂上)/ —(部分挂着,显示 K/N)/ ○(全不挂)—— 点击在三态间循环。提交时:用户没动过的「部分」状态保持现状;改成 ✓ 则在所有未挂的物品上加,改成 ○ 则从所有挂着的物品上撤。单条选中也走同一张表,语义退化为普通的勾/不勾。/ Tri-state batch tag editor (Phase 47): the multi-select "Set Tags" sheet now supports both adding and removing. Each tag row shows ✓ (on all) · — (mixed, with a K/N badge) · ○ (on none); clicking cycles. On commit, untouched "mixed" rows are left alone; toggling to ✓ attaches the tag to every item that didn't have it, toggling to ○ removes it from every item that did. Single-item selection uses the same sheet, falling back to plain checkbox semantics.
- **详情页 AI 按钮去重**(Phase 49):删掉旧的本地「重新解析」按钮(它跟 AI 理解功能重复了 —— AI 能做它能做的事且更准),只保留「用 AI 理解」一个按钮。同时给按钮加了 `.fixedSize` + `.lineLimit(1)` 修复了窄窗口下中文「用AI理解」被腰斩成两行的问题。/ Detail page: dropped the legacy local "Re-parse" button (subsumed by "Understand with AI"), leaving a single AI button. Added `.fixedSize` + `.lineLimit(1)` to fix the Chinese label wrapping mid-character in narrow windows.

#### 🐛 修复 / Fixed

- **AI 理解不再叠加标签**(Phase 44):以前一件物品先被规则解析挂了 tag,再被 AI 理解又挂一个 → 末尾出现两个圆点。现在 AI 是权威分类器,它的标签**替换**当前所有 tag,而不是 append。能用一个圆点就只显示一个。/ AI no longer stacks tags (Phase 44): previously an item could end up with both a parser-auto tag and an AI-classified tag (two dots). AI is now the authoritative classifier and **replaces** the item's tag set with its single pick, rather than appending. One dot whenever possible.

## v0.1.3 — 2026-05-13

### ✨ 新增 / Added

- **多选批量编辑**:Cmd / Shift 多选后,右键菜单 + 工具栏「批量编辑」下拉出现 5 个动作 —— 批量加标签、批量设置位置、批量设置购买渠道、都标记为「最近见过」、都标记为「找不到了」。批量动作执行完底部会闪一条绿色回执,告诉你影响了几件物品。/ Multi-select batch editing: ⌘/⇧-multi-select then right-click or open the toolbar's "Batch Edit" menu to add tags, set a location, set a source, mark all as just seen, or mark all as can't find. A green confirmation flashes at the bottom after each batch op.
- **位置自动完成**:输入完物品名但还没说位置时,「记一条」框下方会蹦出最近用过的 5 个位置 chip,点一下就把位置追加到输入框。/ Location autocomplete: while typing an item name with no location yet, up to 5 chips of recently-used locations appear under the input. Tap one to append it to the draft.
- **自动彩色圆点标签建议**:录入完一条物品后,如果物品名命中关键词字典(如「手机」→ 3C 电子、「锅」→ 厨具),自动给挂一个匹配色的预设标签。底部弹出 toast「已自动加标签:XX  [撤销]」,点撤销即可移除;偏好设置里可整体关闭。/ Auto colored-dot tag: after recording an item, the app matches its name against a keyword dictionary (e.g. "手机/phone" → Tech, "锅/pan" → Kitchen) and auto-attaches the corresponding preset tag. An "Auto-applied tag: XX [Undo]" toast appears at the bottom — tap Undo to revert; or turn the whole feature off in Settings.

### 🔧 改进 / Changed

- 右键菜单里「编辑…」改成「编辑详情…」,跟批量动作菜单的语义区分开。/ The right-click "Edit…" item is renamed to "Edit Details…" so it doesn't blur with the new batch menu.

### 🐛 修复 / Fixed

- **解析器型号+颜色语序**:输入「iPhone 7 Plus 玫瑰金」不再把「玫瑰金」当成物品名主标题,而是 name = "iPhone 7 Plus" / color = "玫瑰金"。同时颜色词典扩了 Apple 当代色(午夜色 / 星光色 / 远峰蓝 / 暗夜紫 / 深空黑)。/ Parser fix for "model + color" word order: typing "iPhone 7 Plus 玫瑰金" now puts iPhone 7 Plus into name and 玫瑰金 into color (previously the color was promoted to the title). The color dictionary also picked up current Apple lineup colors (午夜色 / 星光色 / 远峰蓝 / 暗夜紫 / 深空黑).
- **型号抽取启发式收紧**(build 5):
  - 配件场景不再误抽。「Apple Watch 备用表带」、「iPhone 15 Pro 保护壳」整句留在物品名,不把品牌+产品线抽成 model。识别词:表带 / 保护壳 / 保护套 / 充电线 / 数据线 / 转接头 / 适配器 / 收纳袋 / 备用 / 替换 / 套装 / 配件 等。
  - 接口/标准词不再被当 model。「贝尔金 Type-C 转以太网口」、「索尼 CFA 卡读卡器」整句留在物品名。识别:Type-C / USB / USB-C / HDMI / DP / Thunderbolt / Lightning / PD / Wi-Fi / NVMe / SATA / CFA / TF / SD / 4K / 120Hz 等。
  - 多 Latin 候选时优先挑"真正的型号" token(字母+数字混合、3-14 字符、无内部空格,例 KM003C / U60Pro / GT6)。「Power-Z USB 线缆测试仪 KM003C」现在正确得到 name = "Power-Z USB 线缆测试仪" / model = "KM003C"(以前误抽 "Power-Z USB" 当 model)。
  / Model-extraction heuristic tightened (build 5):
  - Accessory scenarios no longer mis-extract. "Apple Watch 备用表带 (backup band)" and "iPhone 15 Pro 保护壳 (case)" keep the whole phrase as the item name instead of turning the brand+line into a model. Triggered by words like 表带 / 保护壳 / 充电线 / 转接头 / 适配器 / 备用 / 配件.
  - Interface / standard words are no longer treated as models. "贝尔金 Type-C 转以太网口", "索尼 CFA 卡读卡器" keep the entire string as the item name. Now-recognised specs: Type-C / USB / USB-C / HDMI / DP / Thunderbolt / Lightning / PD / Wi-Fi / NVMe / SATA / CFA / TF / SD / 4K / 120Hz, etc.
  - When several Latin runs appear, prefer the one that "looks like a real model" (letter+digit mixed, 3-14 chars, no internal space, e.g. KM003C / U60Pro / GT6). "Power-Z USB 线缆测试仪 KM003C" now correctly resolves to name = "Power-Z USB 线缆测试仪" / model = "KM003C" (previously it mis-extracted "Power-Z USB").
- **歧义位置消歧弹窗**(build 5):输入「iphone 在 抽屉第一层」时,如果库里已有「卧室 → 抽屉第一层」「书房 → 抽屉第一层」两个同名叶子,会弹一个 dialog 让你挑要复用哪一个,或选「新建顶层」。库里只有一个同名时静默复用,没匹中时跟以前一样建新顶层。/ Ambiguous-location prompt (build 5): typing "iphone 在 抽屉第一层" when the library already contains both "卧室 → 抽屉第一层" and "书房 → 抽屉第一层" pops a dialog asking which one you meant, with an option to "create new top-level". One existing match is reused silently; no match still creates a new top-level as before.
- **Delete / Backspace 键删除选中项**(build 5):macOS 上多选(或单选)后按退格键 / 正向 Delete 键都会触发删除确认 dialog。/ Delete / Backspace key now deletes the selection on macOS — both Backspace and the forward-Delete (fn+Delete) trigger the existing confirmation dialog.
- **标签颜色轮换**(build 6):连续添加多个新标签时,默认色会按 9 色调色板顺序自动跳到下一个未占用的色 —— 不再每个新标签都是清一色灰。新标签输入区色点旁边加了 ↓ 提示这是个可点的菜单。/ Tag color rotation (build 6): consecutively adding tags now picks the next unused color from the 9-slot palette instead of always defaulting to gray. A small ↓ next to the new-tag color dot makes it clearer it's a tappable menu.
- **偏好设置 → 标签 管理 tab**(build 6):新增第 3 个 tab,行内可改色、改名、删除每个标签;每行右侧显示挂在几件物品上。在物品编辑表单的标签区底部加了小字提示去这里管理。/ Settings → Tags tab (build 6): a new third tab listing every tag with inline color picker, name field, item count, and delete button. The tag section in the item edit form points users to this tab for bulk management.
- **macOS 上现在可以删标签**(build 6):标签行加了右键 → 删除菜单。删 tag 走 SwiftData 的 nullify 规则,只断挂载,不影响物品本身。/ Tag deletion on macOS (build 6): right-click a tag row → Delete. Backed by SwiftData's nullify rule, which only unlinks the tag from items without deleting the items themselves.
- **单选右键菜单加 3 个快捷动作**(build 6):右键单条物品,菜单里除了「编辑详情…/置顶/删除」之外,新增「设置标签…/设置房间…/设置购买渠道…」—— 改一个字段不用再打开完整的编辑表单。/ Single-select right-click adds 3 quick actions (build 6): besides Edit Details / Pin / Delete, the menu now includes Set Tags / Set Location / Set Source, so changing one field doesn't require opening the full edit sheet.
- **存量物品标签自动回填**(build 6):升级到 build 6 后首次打开 app,会自动把过去没挂任何标签、但物品名能匹中关键词字典的物品补上对应预设标签。底部 toast 告知影响数量,只跑一次,可在「偏好设置 → 通用」里关掉「自动建议标签」让迁移不生效。/ Auto-tag back-fill (build 6): the first time you open build 6, every previously untagged item whose name matches the keyword dictionary gets the corresponding preset tag automatically. A bottom toast reports the count; runs once only, and respects the existing "Auto-suggest tag" Settings toggle.
- **关键词字典扩充**(build 6):「读卡器 / AirTag / 蓝牙音箱 / 移动电源 / 无线充电板 / 蓝牙耳机 / 网线 / 三脚架 / 显示屏 / U盾」现在都能正确触发自动建议。同时修了"螺丝刀"被识别成厨具("刀")的旧 bug。/ Keyword dictionary expanded (build 6): "card reader / AirTag / Bluetooth speaker / power bank / wireless charging pad / Bluetooth earphone / network cable / tripod / display / USB security key" now all trigger auto-suggest correctly. Also fixed a long-standing bug where "screwdriver" was lumped under Kitchen because of the bare "刀" (knife) keyword.

### ✨ 大版本变化 / Major addition

- **AI 理解**(build 7):本地字典+正则覆盖不到的奇怪输入,现在可以让 Claude API 兜底重新解析。/ AI Re-understand (build 7): the local dictionary + regex can't catch every quirky brand or layout — now Claude API can fall back and re-parse the fields.
  - **设置入口**:偏好设置多了第 3 个 tab「AI」—— 选模型(Haiku 4.5 / Sonnet 4.6 / Opus 4.7,默认 Haiku 4.5)、填 Anthropic API key(存系统 Keychain,不是 UserDefaults 明文)、自定义 system prompt(预置 schema,可重置默认),底部一个「测试连接」按钮 1 秒内验证 key 有效性。/ Settings → AI tab: pick model (Haiku 4.5 / Sonnet 4.6 / Opus 4.7, default Haiku 4.5), enter Anthropic API key (stored in macOS Keychain, not plaintext UserDefaults), customize the system prompt with a preset schema and reset-to-default button, plus a "Test connection" button.
  - **使用入口**:右键单条 → ✨用 AI 理解;多选 → 同款菜单项,顺序遍历,每条调一次 Claude。进度 sheet 实时显示「X / N · 正在处理:[物品名]」,可中途取消。完成后底部 toast 报「成功 X / 失败 Y」。/ Invocation: right-click a single row → ✨ Re-understand with AI; or multi-select → same menu item, processes items sequentially with a live progress sheet ("X / N · Processing: [name]") that supports cancel mid-batch. A bottom toast reports "succeeded X / failed Y".
  - **回写策略**:AI 返回 null 的字段保持原值(不抹掉用户数据);返回 locationPath 时同步写一条 LocationLog 历史。/ Write-back: fields that AI returns as null keep the user's existing value (no accidental data wipe). When AI returns a new locationPath, a LocationLog history entry is added.
  - **隐私**:仅在你点 ✨ 按钮时才发起请求,主流程录入照旧 100% 本地。不发送照片、不发送历史 log,只发当前物品的文本字段(name / model / version / color / source / date / location / notes)。/ Privacy: requests are only made when you click ✨; the main entry flow stays 100% local. Photos and history logs are never sent — only the current item's text fields (name / model / version / color / source / date / location / notes).

### 🐛 修复 / Fixed (build 7)

- **偏好设置 → 标签 看不到任何标签**:macOS 上 Settings 是独立 Scene,默认不跟主窗口共享 SwiftData modelContainer,导致 @Query 永远是空数组。给 Settings scene 加上 .modelContainer 注入,现在能看到所有预设标签 + 用户新建的标签,也能改色/重命名/删除。/ Settings → Tags showed an empty list: macOS's `Settings` scene runs in its own scene without the main window's SwiftData modelContainer, so its `@Query` saw zero tags. Added the missing `.modelContainer(...)` modifier to Settings — preset tags and any user-created tags now show up and can be color-edited, renamed, or deleted.

### ✨ 增强 / Enhanced (build 8)

- **AI 加入火山引擎(Volcengine)支持**:偏好设置 → AI 顶部多了 Provider 切换 ——「Claude」/「火山引擎」二选一。两家可以预先把 endpoint + API key + 模型都填好,然后按需切换 active provider。每家都有独立的「测试连接」按钮验证联通性。/ Multi-provider AI (build 8): Settings → AI now starts with a provider switch — Claude or Volcengine (火山引擎). Both providers can be pre-configured with their own endpoint, API key, and model, then activated on demand. Each has its own "Test connection" button.
  - **支持中转站**:每家的 API Endpoint 都是 TextField,默认是官方域名,你可以改成 OpenAI 兼容中转站 / 代理服务的 URL —— 适用于不能直连 Anthropic 或火山方舟官方的网络环境。/ Custom endpoints / relays: both providers expose an editable endpoint, defaulting to the official URLs. Set it to any OpenAI-compatible relay or proxy when direct access isn't available.
  - **底部分别附了详细文档**:Claude 这边告诉你怎么去 Anthropic console 注册;火山引擎这边告诉你怎么去火山方舟控制台拿 API Key,以及 model 字段填什么(model 名 / endpoint ID 都行)。/ Each provider section has detailed help text underneath: how to sign up at the Anthropic console for Claude; how to grab a key at the Volcengine Ark console and what to put in the model field (model name like `doubao-seed-1-6-250615` or endpoint ID like `ep-xxxxx`) for Volcengine.
- **偏好设置 → 标签 色板换成实色圆点**:旧版用了 macOS NSMenu,它把彩色 systemImage 渲染成单色 template —— 用户看到的只是一排灰圆点 + 颜色名,完全失去"选色"的视觉。现在每个 tag 行直接显示 9 个真实彩色的圆点,选中那个有粗描边 + 内部对勾,1 次点击直接换色,不再需要 menu 二段操作。/ Tag color palette now shows real colored swatches (build 8): the old picker used NSMenu, which renders SwiftUI's colored systemImages as a monochrome template — you saw rows of gray circles labelled "gray / red / blue", defeating the purpose. Now each tag row inlines all 9 actual colored swatches; the selected one has a thick stroke + a white check, and a single click switches color (no two-step menu open).

### ✨ AI 体验 + 历史 (build 9)

- **录入框下方加「使用 AI 理解」勾选项**:勾上之后,每条录入仍然先走本地解析瞬间落库(不卡用户),然后在后台异步调一次 AI 重新拆字段。处理期间该项右侧显示 ✨ + 旋转图标 +「正在用 AI 理解…」灰字;完成时变成 ✅ +「AI 已理解 ✓」绿字,4 秒后自动消失。没填 API key 时这个勾选自动 disabled,有 tooltip 提示。/ "Use AI to re-understand" checkbox under the input (build 9): when checked, each entry still runs the local parser first (instant save) and then a background AI re-parse refines the fields. The item's row shows ✨ + spinner + "AI is re-understanding…" while processing, then ✅ + "AI re-understood ✓" green for 4 s. The toggle is auto-disabled if no API key is configured.
- **详情页加 AI 理解按钮**:之前只有「✨ 重新解析」(本地),现在并排多了「✨ 用 AI 理解」(云端)。两个按钮职责清晰 —— 本地用关键词字典补字段,AI 调 Claude / 火山引擎对怪命名做语义级修正。/ Detail view AI button (build 9): next to the existing local "Re-parse" button, the detail header now has a "Re-understand with AI" button. Local re-parse fills fields from the keyword dictionary; AI re-parse calls Claude/Volcengine for semantic-level corrections of edge cases.
- **批量 AI 理解不再阻塞**:之前批量选中物品 → AI 理解会弹一个 modal sheet,用户必须等所有项处理完才能继续操作。现在改成 100% 后台 —— 选中的每一项右侧 inline 显示 ✨ 正在理解,顺序处理,完成的项显示 ✅。处理期间你可以继续录入、删除、切换其他项,完全不卡 UI。/ Non-blocking batch AI (build 9): the modal progress sheet is gone. Each selected item shows its own inline ✨ Processing / ✅ Done state on the row; you can keep typing, deleting, switching items while the queue runs in the background.
- **每个物品多了字段编辑历史**:除了原有的"位置历史"时间线,详情页现在合并显示「字段被改过的历史」—— 谁(AI Claude / AI 火山引擎 / 本地解析 / 更新意图 / 手工编辑)在什么时间把哪个字段从什么值改成了什么值。AI 改错可一目了然看到旧值。来源用色点和文字标识区分(AI=紫色,本地=蓝色,手工=绿色)。/ Per-item field edit history (build 9): on top of the existing location history, the timeline now shows every field change — who (AI Claude / AI Volcengine / local parser / update intent / manual edit) changed what field from what to what, when. AI mistakes are easy to inspect; sources are color-coded (AI=purple, parser=blue, manual=green).

### 🐛 修复 / Fixed (build 10)

- **每次打开新 build 都弹「想要使用钥匙串中的机密信息」的系统提示** —— 改成 UserDefaults 存储。根因:ad-hoc 签名的 app 每次 rebuild 都有不同的 code signature,而 Keychain item 的 ACL 锁死了创建它时那个签名 —— 新 build 读 → macOS 提示用户授权。对个人 dev app 来说,每出 build 一次提示完全不可接受;改成 UserDefaults plaintext 存,key 路径 `~/Library/Containers/.../Preferences/<bundleID>.plist`,以后任何 rebuild 都不再弹窗。**升级到 build 10 后需要在 偏好设置 → AI 里重新填一次 API key**(旧的 Keychain 残留无害,自然过期)。/ "Want to use confidential information in keychain" prompt on every fresh build is gone — moved to UserDefaults. Root cause: ad-hoc signing produces a fresh code identity per rebuild, the Keychain ACL is bound to the original signature, so each new build asks for user authorization. For a single-user dev build, that's a non-starter. Now stored as plaintext in the prefs plist; trade-off documented in Settings → AI help text. After upgrading to build 10, **re-enter the API key once in Settings → AI** (the orphaned Keychain entries are harmless).

### ✨ 增强 / Enhanced (build 11)

- **AI 理解会自动挂上一个合适的标签**:AI 结果新增 `tag` 字段;调用 AI 时把本机当前所有标签 name 传给模型,要求它**必须**从中选一个 —— AI 永远不会自己造新标签。命中后 app 按 name 反查 Tag 对象挂上;一个都不合适时 AI 输出 `"其他"`,如果本机还没"其他"这个标签,会在那一刻 ensure 一个(色用 teal,跟 6 个预设色不撞)。**结果:AI 理解一次,自动归类一次,完全不会污染你的标签库**。/ AI re-understand now auto-tags into one of your existing tags (build 11): AI returns a `tag` field that **must** come from the local tag list passed in the user message; AI never invents new tags. If nothing fits, AI returns `"其他"` (Other), and the app ensures that tag exists (teal color, distinct from the 6 presets) and attaches it. Net effect: every AI re-understand also categorises the item without ever polluting your tag set.

## v0.1.2 — 2026-05-11

### ✨ 新增 / Added

- 列表行新增标签色点:详情页里每个标签都有的彩色小圆点,现在列表行物品名前面也会同步显示,一眼就能扫到这件物品属于哪几类。/ The list rows now show the same tag color dots that the detail page uses — small colored circles in front of each item's name make it easy to scan which categories an item belongs to.
- "用过吗?" 多了一句更柔和的措辞:第一颗按钮从「他还在原位」改成「ta 还在原位」,不再带性别色彩。/ The first "Did you use this?" button has been softened from「他还在原位」("he is still in place") to「ta 还在原位」, dropping the gendered pronoun.

### 🔧 改进 / Changed

- 鸡汤金句从底部状态栏挪到顶部「记一条」上方,打开 app 第一眼就能看见;条目从 15 句扩到 35 句,以"名人名言"格式显示,尾巴署名「—— claude code」。/ The aphorism shown each launch has moved from the bottom status bar to above the "Add one" input — visible the moment the app opens. The pool grew from 15 to 35 lines, displayed in a "famous quote" style and signed "—— claude code".
- 底部状态栏因此只剩统计行(X 样物品 · Y 个房间 · Z 天),视觉更安静。/ The bottom status bar is now just the stats line (N items · M rooms · K days), which makes it calmer.

## v0.1.1 — 2026-05-11

### ✨ 新增 / Added

- 句首语气词自动剥离:输入"但荣耀手机在桌子"、"可是苹果手机…"不再把"但 / 可是"留进物品名;覆盖 但是 / 可是 / 然而 / 不过 / 对了 / 但 / 可 / 嗯 / 哦 / 啊 / 诶。/ Leading filler words are stripped automatically: phrases like "但荣耀手机在桌子" or "可是苹果手机…" no longer keep "但 / 可是" inside the item name. Covers 但是 / 可是 / 然而 / 不过 / 对了 / 但 / 可 / 嗯 / 哦 / 啊 / 诶.
- 容量与规格自动抽取:"512g 苹果手机"、"1TB 硬盘"、"iPad 11寸"会把 512g / 1TB / 11寸 自动放进"版本 / 规格"字段,物品名保持干净。/ Capacity and size tokens are pulled out automatically — "512g 苹果手机", "1TB 硬盘" or "iPad 11寸" send 512g / 1TB / 11寸 into the Version / Spec field and leave the name clean.
- 偏好设置 → 数据:新增"批量导出到 JSON…"和"批量从 JSON 导入…"两个明显的按钮,每个下方附一行说明。/ Settings → Data now has two clear buttons — "Bulk export to JSON…" and "Bulk import from JSON…" — each with a one-line explanation underneath.

### 🔧 改进 / Changed

- 右侧详情区(Inspector)默认始终打开:没选物品时显示"选一条看详情",多选时显示"已选 N 条",不再随选择折叠开合。/ The right-side detail inspector now stays open at all times — it shows "Select an item to see details" when nothing is selected and "N selected" in multi-select mode, instead of collapsing.
- 搜索区默认收起:顶部只显示"搜索 / 筛选"标题加一个 chevron,点击展开;展开后底色加深,与上方"记一条"录入区视觉上分明。/ The search area is collapsed by default — only a "Search / Filter" header and chevron show until you click to expand. When open, its background is darker so it stands out clearly from the "Add one" input area above.
- 工具栏新增 ✏️ 录入和 🔍 搜索两个图标按钮:点 ✏️(⌘N)光标直接跳到顶部输入框,点 🔍(⌘F)展开搜索区并把焦点送进搜索框。/ Two new toolbar icons — ✏️ for input (⌘N) jumps the cursor straight to the top input field, and 🔍 for search (⌘F) expands the search area and focuses the search field.
- 编辑表单的 section 顺序调整为 基本 → 可选信息(型号 / 版本 / 颜色 / 购买日期 / 渠道)→ 照片 → 标签,把可选信息提到表单上半部分。/ The edit form sections were reordered to Basic → Optional info (model / version / color / purchase date / source) → Photo → Tags, so optional info sits in the upper half of the form.

### 🐛 修复 / Fixed

- 修正"关于"面板里作者邮箱的拼写:`plunginexpert2@gmail.com` → `pluginexpert2@gmail.com`(去掉多余的 n)。/ Fixed a typo in the author email on the About panel: `plunginexpert2@gmail.com` → `pluginexpert2@gmail.com` (removed the extra "n").

## v0.1.0 — 2026-05-11

何处 (Whereabouts) 的第一个版本。/ The first release of Whereabouts (何处).

### 🎯 亮点 / Highlights

- 一句话录入,自动识别物品名、嵌套位置、型号、颜色、购买日期与渠道。/ Type one sentence to record an item — the name, nested location, model, color, purchase date and source are extracted automatically.
- 每件物品都有"用过吗?"提醒(放回原位 / 位置变了 / 不知道在哪)和位置历史时间线,记录它去过哪。/ Every item has a "Did you use this?" prompt (put back / moved / can't find) and a location history timeline showing where it has been.
- 完整中英双语,可在偏好设置里随时切换。/ Full Chinese and English interface, switchable any time in Settings.

### ✨ 新增 / Added

- 中文自然语言录入:支持"充电宝在卧室抽屉第二格"、"护照:保险箱"、"钥匙 → 玄关 / 钩子"等多种写法。/ Chinese natural-language input supports phrases like "充电宝在卧室抽屉第二格", "护照:保险箱", "钥匙 → 玄关 / 钩子" and many more.
- 一次写多条:用逗号、顿号、分号或"然后 / 还有 / 接着"分隔,一行可录入多件物品。/ Record multiple items in one line by separating with commas, semicolons or words like "然后 / and / 还有".
- 重复检测:录入时若撞到同名或包含关系的旧物品,弹窗询问是更新位置 / 补充信息,还是另起一条。/ When you record something that looks like an existing item, a prompt asks whether to update the location, fill in missing details, or create a new entry.
- 字段更新意图识别:"华为手表的型号是 GT6"、"扫地机是 2024 年 5 月在京东买的" 之类的句子会直接更新已有物品的对应字段。/ Sentences like "华为手表的型号是 GT6" or "扫地机是 2024 年 5 月在京东买的" are recognised as field updates to an existing item.
- 树状位置:层级用 ` > ` / `/` / "的" 等符号表达,同名同层自动复用,改一处整棵子树跟随。/ Hierarchical locations expressed with ` > `, `/`, "的" and similar separators; same name at the same level is reused, so renaming flows through the whole subtree.
- 位置历史时间线:每次"放回 / 位置变了 / 不知道在哪 / 重复→更新"都会写一条记录,详情页倒序展示物品的轨迹。/ A timeline records every "put back / moved / can't find / dedup-update" event and shows the item's path in reverse chronological order in the detail panel.
- "不知道在哪"按钮:清空当前位置但保留全部历史,以后想起再设回去。/ A "Can't find it" action clears the current location while keeping the full history, so you can set it again later when it turns up.
- ✨「理解」按钮:对早期录入的脏数据再跑一遍解析,从名字里补出型号 / 颜色 / 购买信息。/ A "Re-understand" button re-parses an existing name and fills in model, color and purchase info that earlier rounds missed.
- 编辑表单:可改名称、备注、型号、版本、颜色、购买日期、渠道、标签和照片。/ Edit form supports name, notes, model, version, color, purchase date, source, tags and photo.
- 标签系统:Finder 风 9 色调色板,首次启动自动生成"生活用品 / 3C 电子 / 厨具 / 小工具 / 办公用品 / 文具"6 个预设标签。/ Tag system with a 9-color Finder-style palette; first launch seeds six presets: 生活用品 / 3C 电子 / 厨具 / 小工具 / 办公用品 / 文具.
- 照片:支持从系统 Photos 库选择,或在 macOS 上从 Finder 直接拖入图片文件;点击缩略图可放大查看。/ Photos can be picked from the system Photos library or, on macOS, imported as files from Finder; tap the thumbnail to view full size.
- 顶部搜索 + 四行 facet 筛选:位置 / 渠道 / 年份 / 品牌,每个 chip 带数量;位置 facet 会展开整条层级链。/ Top search field plus four facet rows — location, source, year, brand — each chip showing a count; the location facet expands the full parent chain.
- macOS 多选与批量删除:⌘ / ⇧ 多选行,工具栏一键把选中物品移入回收站。/ macOS multi-select with ⌘ / ⇧ click; the toolbar's bulk-delete action moves the selection into the trash.
- 软删除回收站:删除的物品进入回收站,右键可还原 / 彻底删除,工具栏可一键清空。/ Soft-delete trash: deleted items go to the trash where you can right-click to restore or purge, or empty it from the toolbar.
- 五种排序方式:最近修改 / 最近见到 / 最近创建 / 按名字 / 按位置。/ Five sort orders: recently modified, recently seen, recently created, by name, by location.
- 底部状态栏:统计物品数 / 房间数 / 已使用天数,下方随机显示 15 条 J 人金句,每次打开换一句。/ Bottom status bar shows item count, room count and days-in-use, with a random pick from 15 J-type quotes that rotates each launch.
- 偏好设置:语言(跟随系统 / 中文 / 英文)、外观(跟随系统 / 浅色 / 深色)、菜单栏图标开关、重复检测开关、字段更新检测开关。/ Settings let you choose language (system / Chinese / English), appearance (system / light / dark), and toggle the menu bar icon, duplicate detection and field-update detection.
- macOS 菜单栏快速录入:点击菜单栏图标弹出 popover,一行输入框 + 最近 5 条物品,不打扰当前窗口。/ macOS menu-bar quick entry: a popover with one input field and the five most recent items, without disturbing the active window.
- 数据导出:整库导出为带照片(base64)的 JSON 文件,文件名带 ISO 日期。/ Export the whole library to a JSON file (with photos embedded as base64), filename stamped with an ISO date.
- 数据导入:从偏好设置选 JSON 文件,所有物品、位置、历史、照片一并恢复。/ Import a JSON file from Settings to restore all items, locations, history and photos.
- 清空所有数据:偏好设置里的破坏性按钮,带二次确认。/ "Erase all data" button in Settings, behind a confirmation dialog.
- Help 帮助窗口:⌘? 打开,渲染本地化的 Markdown 帮助文档。/ Help window opens with ⌘? and renders the localized Markdown help document.
- About 关于面板:标准 about 面板显示作者 Bam Cope、可点击邮箱 (pluginexpert2@gmail.com),以及"Built with Claude Code"署名。/ The About panel shows author Bam Cope, a clickable email (pluginexpert2@gmail.com), and a "Built with Claude Code" credit.
- DMG 发布包:macOS 安装镜像,内附中英文安装指南。/ macOS DMG installer with bilingual installation instructions inside.
