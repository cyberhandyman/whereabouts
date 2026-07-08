# 何处 Whereabouts · App Store 元数据文案包

> 配套操作手册(网页):https://whereabouts.top/appstore.html
> 直接复制粘贴进 App Store Connect。zh-Hans 为主语言,en 为附加本地化。

## 基本信息

| 字段 | 值 |
| --- | --- |
| Bundle ID | com.bamcope.whereabouts(iOS + macOS 同一个,universal purchase) |
| SKU | whereabouts-001 |
| 主语言 | 简体中文 |
| 价格 | 免费 |
| 类别 | 主:效率(Productivity);副:生活(Lifestyle) |
| 年龄分级 | 4+(问卷全答"无") |
| 版权 | © 2026 Bam Cope |
| 隐私政策 URL | https://whereabouts.top/privacy.html |
| 支持 URL | https://whereabouts.top/guide.html |
| App 隐私问卷 | Data Not Collected(不收集数据)—— 全部类别选否 |
| 出口合规 | Info.plist 已含 ITSAppUsesNonExemptEncryption=false,提交时不再询问 |

## 名称 / 副标题

| | zh-Hans | en |
| --- | --- | --- |
| 名称(30 字内) | 何处 - 东西放哪了 | Whereabouts - Where I Put It |
| 备选名称 | 何处 Whereabouts / 何处·物品管家 | — |
| 副标题(30 字内) | 一句话记下物品位置,AI 帮你归档 | Remember where things are, in one sentence |

## 关键词(100 字符,半角逗号分隔)

**zh-Hans:**
```
物品管理,收纳,找东西,位置记录,家庭整理,断舍离,库存,储物,标签,物品清单,GTD,记性
```

**en:**
```
inventory,organizer,storage,where,find things,home,declutter,label,belongings,tracker
```

## 描述(zh-Hans)

```
「充电宝在卧室五斗柜第二格抽屉」—— 打完这句话,就记完了。

何处 Whereabouts 是一个极简的物品位置记事本:用自然语言一句话录入,自动拆出物品名、层级位置、型号、颜色、购买信息,再也不用翻箱倒柜找东西。

一句话录入
• 中文自然语言直接写:"护照在书房保险箱""3 个 Magic Keyboard 在电视柜"
• 一次记多条:换行、逗号、分号分隔即可
• 智能识别型号 / 颜色 / 容量 / 购买渠道和日期

树状位置 + 位置历史
• 位置按"房间 > 家具 > 格子"分层,搜索、筛选一目了然
• 每次移动都有时间线记录,还能一键"放回原位了"

AI 智能理解(可选)
• 接入你自己的 AI 服务(支持 Anthropic Claude 与火山引擎豆包)
• 写得再随意也能拆得干干净净,还会自动挑一个分类标签
• 完全可选:不配置也是全功能,app 内置图文配置教程

管好每一件东西
• 标签、照片、置顶、关联物品(配件跟主机连起来)
• 借出去登记:iPad 借给了谁、几天了,一眼看到
• 定期提醒:置顶的重要物品,定时问你"还在原位吗?"
• JSON 全量导出 / 导入,数据永远是你的

隐私至上
• 所有数据只存在你的设备本地,没有服务器、没有账号、没有统计
• AI 功能仅在你主动触发时,把该条文字发给你自己选择的服务商

macOS 版与 iOS 版一次获取、两端可用(Universal Purchase)。
```

## Description (en)

```
"Power bank — bedroom dresser, second drawer." Type that one sentence, and it's saved.

Whereabouts is a minimal notebook for where your things are: natural-language input automatically splits item name, nested location, model, color, and purchase info — so you never rummage through boxes again.

ONE-SENTENCE CAPTURE
• Write naturally: "passport in the study safe", "3 Magic Keyboards on the TV stand"
• Batch capture with newlines or commas
• Auto-extracts model / color / capacity / purchase source & date

NESTED LOCATIONS + HISTORY
• Locations form a tree: room > furniture > drawer
• Every move is on a timeline; one tap for "put it back"

OPTIONAL AI UNDERSTANDING
• Bring your own AI (Anthropic Claude or Volcengine Doubao)
• Messy input, clean fields — plus an automatic category tag
• Fully optional; the app is complete without it. Illustrated setup guide built in.

EVERYTHING ELSE
• Tags, photos, pinning, related items, lend-out tracking
• Periodic "is it still there?" reminders for pinned items
• Full JSON export / import — your data stays yours

PRIVACY FIRST
• Everything lives on your device. No servers, no accounts, no analytics.
• AI requests happen only when you trigger them, straight to your own provider.

One purchase covers both iOS and macOS (Universal Purchase).
```

## 审核备注(App Review Notes,提交时贴)

```
This app is completely free with all features fully functional offline.
The optional "AI understanding" feature lets users bring their own API key
(Anthropic or Volcengine) purchased directly from those providers for their
own use. The key unlocks nothing in this app — it only lets the app send the
user's own item text to the user's own AI account for parsing. No purchase
is required or offered anywhere in the app. All data is stored locally;
see the privacy policy. A demo requires no account: just type e.g.
"充电宝在卧室抽屉" (power bank in bedroom drawer) on the Record tab.
```

## 截图规格备忘(2026-07 官方)

- iPhone 6.9"(必传):1320×2868 或 1290×2796(竖)
- iPad 13"(支持 iPad 必传):2064×2752 或 2048×2732
- macOS:2880×1800 / 2560×1600 / 1440×900 / 1280×800(16:10)
- 每平台 1–10 张;建议 4–6 张:首页(有数据)/ 记一条 / 详情 / AI 设置 / 深色模式
- iOS 模拟器拍图:DEBUG 构建支持 `--demo-data`、`--open-first`、`--tab-record`、`--tab-settings` 启动参数

## 上架前 checklist(2026-07-08 体检后更新)

**工程侧已全部就绪(Claude 已做):**
- [x] Team 6893263DW5 已配,本机已注册开发设备
- [x] API key 存储换回真 Keychain(数据保护钥匙串,旧明文自动迁移)
- [x] PrivacyInfo.xcprivacy 隐私清单(双 target;零收集,UserDefaults CA92.1)
- [x] ITSAppUsesNonExemptEncryption=false(双平台 Info.plist)
- [x] macOS 图标进资产目录(全尺寸,App Store 校验需要)
- [x] AppStore 构建配置(macOS 带沙箱 entitlements);Xcode Product→Archive 默认即 AppStore 配置
- [x] 双平台 archive 冒烟通过(沙箱/iCloud/aps entitlements + 隐私清单已验证在包内)
- [x] 截图:iPhone 6.9"(1320×2868)5 张 + iPad 13"(2064×2752)3 张 → publishing/screenshots/

**你要做的(按顺序):**
- [ ] ①(关键)CloudKit schema 部署到生产:icloud.developer.apple.com → 容器 iCloud.com.bamcope.whereabouts → 左下 Deploy Schema Changes → 确认。不做这步,商店版用户同步会静默失败!
- [ ] ② App Store Connect 建 App(iOS)→ 左侧 Add Platform 加 macOS(同一条 record = universal purchase)
- [ ] ③ 贴元数据(本文件上方)+ 上传截图;macOS 截图手动拍:app 里记几条数据 → ⇧⌘4+空格 拍窗口 → `sips -z 1800 2880 截图.png` 缩放到 2880×1800
- [ ] ④ App 隐私问卷全选「不收集数据」;年龄分级问卷全答"无"→ 4+
- [ ] ⑤ 首发销售范围去掉中国大陆(ICP 备案后再加)
- [ ] ⑥ Xcode 里 scheme 选 WhereaboutsiOS → Any iOS Device → Product→Archive → Organizer 弹出 → Distribute App → App Store Connect → Upload(全默认;首次会自动建 Distribution 证书)。scheme 切 Whereabouts → Any Mac → 同样操作
- [ ] ⑦ TestFlight 真机自测(重点:两台设备 iCloud 同步、AI 配置、导入导出)
- [ ] ⑧ 两个平台各自版本页:选构建 → 贴审核备注(上方 App Review Notes)→ Submit for Review

**注意事项:**
- 商店沙箱版数据目录与你本机开发版不同 —— 你自己装商店版后,数据靠 iCloud 同步自动回来(或云盘 JSON 导入),新用户无感
- iOS entitlements 里 aps-environment=development 无需手改,Archive 导出时 Xcode 自动换 production
- 上传后处理需 10-30 分钟才出现在 TestFlight
