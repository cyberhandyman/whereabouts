import Foundation
import SwiftUI

/// AI 配置门面 —— 把 active provider / 每家的 key+endpoint+model / 共用 system prompt
/// 都装在一个静态命名空间里。UI 直接调,不用关心 Keychain / UserDefaults 的存储细节。
///
/// 存储拆分:
///   - 敏感的 API key  → Keychain(每家一个 account)
///   - 其余偏好         → UserDefaults
///   - system prompt   → UserDefaults(默认值见 defaultSystemPrompt)
enum AISettings {

    // MARK: - Storage keys

    private static let providerKey         = "ai.provider"
    private static let promptKey           = "ai.systemPrompt"

    // Phase 88 / 96:用量统计。
    //
    // 0.1.5 build 3(Phase 88)只记"本月" —— 月初自动归零。
    // 0.1.6 build 1(Phase 96)改为**按天 bucket**,Date 维度细化到 day,
    // 然后在 getter 里聚合成 today / thisWeek / thisMonth 三个窗口,
    // 跟 Claude / Volcengine 后台账单口径一致(token 直接累加,call = 1 次 understand)。
    //
    // 存储:UserDefaults 一个 JSON dict,key="ai.usage.daily",
    //       value=`{"2026-05-16": [calls, input_tokens, output_tokens], ...}`。
    //       自动清理 90 天前的 buckets,避免无限增长。
    private static let dailyUsageKey  = "ai.usage.daily"
    // 旧 keys 已不用,留这些常量纯历史参考:
    //   "ai.usage.month" / "ai.usage.calls" / "ai.usage.inputTokens" / "ai.usage.outputTokens"

    // Claude
    private static let claudeKeychain      = "anthropicAPIKey"
    private static let claudeEndpointKey   = "ai.claude.endpoint"
    private static let claudeModelKey      = "ai.claude.model"   // 旧 key 是 "ai.model",迁移见 init()

    // Volcengine
    private static let volcKeychain        = "volcengineAPIKey"
    private static let volcEndpointKey     = "ai.volc.endpoint"
    private static let volcModelKey        = "ai.volc.model"
    // Phase 107:火山引擎用户自填价格(¥ / 百万 token)。0 = 不显示估算行。
    private static let volcInPriceKey      = "ai.volc.inputPricePerMillionCNY"
    private static let volcOutPriceKey     = "ai.volc.outputPricePerMillionCNY"

    // MARK: - Active provider

    static var activeProvider: AIProvider {
        get {
            if let raw = UserDefaults.standard.string(forKey: providerKey),
               let p = AIProvider(rawValue: raw) {
                return p
            }
            return .claude
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    // MARK: - Claude

    static var claudeAPIKey: String {
        get { Keychain.get(account: claudeKeychain) ?? "" }
        set { Keychain.set(newValue, account: claudeKeychain) }
    }

    static var claudeEndpoint: String {
        get { UserDefaults.standard.string(forKey: claudeEndpointKey) ?? AIProvider.claude.defaultEndpoint }
        set {
            // 空串视为"恢复默认",写默认 URL 进去,免得 client 拿空串报 invalidEndpoint。
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            UserDefaults.standard.set(
                trimmed.isEmpty ? AIProvider.claude.defaultEndpoint : trimmed,
                forKey: claudeEndpointKey
            )
        }
    }

    static var claudeModel: ClaudeModel {
        get {
            // 优先读新 key;没有就 fallback 旧 key("ai.model")—— Phase 32 之前是这么存的。
            let raw = UserDefaults.standard.string(forKey: claudeModelKey)
                ?? UserDefaults.standard.string(forKey: "ai.model")
            return raw.flatMap(ClaudeModel.init(rawValue:)) ?? .haiku45
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: claudeModelKey) }
    }

    // MARK: - Volcengine

    static var volcAPIKey: String {
        get { Keychain.get(account: volcKeychain) ?? "" }
        set { Keychain.set(newValue, account: volcKeychain) }
    }

    static var volcEndpoint: String {
        get { UserDefaults.standard.string(forKey: volcEndpointKey) ?? AIProvider.volcengine.defaultEndpoint }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            UserDefaults.standard.set(
                trimmed.isEmpty ? AIProvider.volcengine.defaultEndpoint : trimmed,
                forKey: volcEndpointKey
            )
        }
    }

    /// Volc 的 model 字段是用户自填字符串(可以是 model 名 "doubao-seed-1-6-250615",
    /// 也可以是 endpoint id "ep-2025xxxxx-xxxxx"),没默认值。
    static var volcModel: String {
        get { UserDefaults.standard.string(forKey: volcModelKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespaces), forKey: volcModelKey) }
    }

    /// Phase 107:火山引擎输入价格(¥ / 百万 token),用户自填。默认 0 = 不显示 ¥ 估算。
    static var volcInputPricePerMillionCNY: Double {
        get { UserDefaults.standard.double(forKey: volcInPriceKey) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: volcInPriceKey) }
    }

    /// Phase 107:火山引擎输出价格(¥ / 百万 token),用户自填。默认 0 = 不显示 ¥ 估算。
    static var volcOutputPricePerMillionCNY: Double {
        get { UserDefaults.standard.double(forKey: volcOutPriceKey) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: volcOutPriceKey) }
    }

    // MARK: - 共用 prompt

    static var systemPrompt: String {
        get { UserDefaults.standard.string(forKey: promptKey) ?? defaultSystemPrompt }
        set { UserDefaults.standard.set(newValue, forKey: promptKey) }
    }

    // MARK: - 派生

    /// 当前 active provider 是否配齐了凭据(够发请求)?
    /// AI 入口在 UI 里靠它来 enable/disable。
    static var hasActiveKey: Bool { currentClient() != nil }

    /// 按 activeProvider 构造一个就绪的 client;凭据不全返回 nil。
    /// 调用方:`if let c = AISettings.currentClient() { ... try await c.understand(item: item) }`
    static func currentClient() -> AIChatClient? {
        switch activeProvider {
        case .claude:
            let key = claudeAPIKey.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return nil }
            return ClaudeClient(
                apiKey: key,
                endpoint: claudeEndpoint,
                model: claudeModel,
                systemPrompt: systemPrompt
            )
        case .volcengine:
            let key = volcAPIKey.trimmingCharacters(in: .whitespaces)
            let mdl = volcModel.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !mdl.isEmpty else { return nil }
            return VolcengineClient(
                apiKey: key,
                endpoint: volcEndpoint,
                model: mdl,
                systemPrompt: systemPrompt
            )
        }
    }

    // MARK: - 用量统计(Phase 88 + Phase 96)

    /// 一个用量快照,跟服务商账单口径一致:
    ///   - `calls`        = 成功的 `understand` 调用次数(失败不计)
    ///   - `inputTokens`  = API 响应里 `input_tokens` / `prompt_tokens` 累加
    ///   - `outputTokens` = API 响应里 `output_tokens` / `completion_tokens` 累加
    /// 三个窗口共用同一个结构,不带月份字段(窗口边界由 getter 决定)。
    struct UsageSnapshot {
        let calls: Int
        let inputTokens: Int
        let outputTokens: Int

        /// 估算美元成本 —— 给 Claude 用,按当前 model 单价算。
        /// Volcengine 价格因 model 而异(用户自填 model 名),不展示估算。
        func estimatedUSDForClaude(model: ClaudeModel) -> Double {
            // Anthropic 公开单价(per 1M tokens)。改这里时同步看官方定价页
            // https://platform.claude.com/docs/en/about-claude/pricing(2026-07 核对)。
            let (inPrice, outPrice): (Double, Double)
            switch model {
            case .haiku45:  (inPrice, outPrice) = (1.0, 5.0)
            case .sonnet46: (inPrice, outPrice) = (3.0, 15.0)
            // Sonnet 5 促销价 $2/$10 至 2026-08-31,之后 $3/$15 —— 估算按促销价,
            // 到期后这里改回 (3.0, 15.0)。
            case .sonnet5:  (inPrice, outPrice) = (2.0, 10.0)
            // Phase 112 修正:旧表写的 (15, 75) 是 Opus 4.1 时代的老价,
            // Opus 4.7 / 4.8 官方现价都是 $5/$25 —— 之前会把成本高估 3 倍。
            case .opus47:   (inPrice, outPrice) = (5.0, 25.0)
            case .opus48:   (inPrice, outPrice) = (5.0, 25.0)
            }
            return (Double(inputTokens) * inPrice + Double(outputTokens) * outPrice) / 1_000_000
        }

        /// Phase 107:火山引擎人民币估算 —— 用户在 Settings 里自填的 ¥/百万 token 单价。
        /// 任一价格 > 0 就计算;两个都是 0 视为未填,不显示估算行。
        func estimatedCNYForVolcengine(inputPricePerMillion: Double,
                                       outputPricePerMillion: Double) -> Double {
            (Double(inputTokens) * inputPricePerMillion
             + Double(outputTokens) * outputPricePerMillion) / 1_000_000
        }

        static let zero = UsageSnapshot(calls: 0, inputTokens: 0, outputTokens: 0)
    }

    /// 今天(从凌晨 00:00 起)。
    static var usageToday: UsageSnapshot {
        aggregate(from: Calendar.current.startOfDay(for: .now))
    }

    /// 本周(以系统 locale 的"周首日" — 中国 zh-Hans locale 是周一)。
    static var usageThisWeek: UsageSnapshot {
        let cal = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
        let start = cal.date(from: comps) ?? .now
        return aggregate(from: start)
    }

    /// 本月(1 号 00:00 起)。
    static var usageThisMonth: UsageSnapshot {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: .now)
        let start = cal.date(from: comps) ?? .now
        return aggregate(from: start)
    }

    /// 每次 API 调用成功后调:累加 1 次 + token 数到今天的 bucket。
    /// 顺便清理 90 天前的旧 buckets,避免无限增长。
    static func bumpUsage(inputTokens: Int, outputTokens: Int) {
        var d = loadDailyUsage()
        let key = dateKey(for: .now)
        let cur = d[key] ?? [0, 0, 0]
        d[key] = [cur[0] + 1, cur[1] + max(0, inputTokens), cur[2] + max(0, outputTokens)]
        // 清理 90 天前的 buckets
        if let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: .now) {
            let cutKey = dateKey(for: cutoff)
            d = d.filter { $0.key >= cutKey }
        }
        saveDailyUsage(d)
    }

    /// 用户在 Settings 里点"清零"按钮时调,清掉所有 buckets。
    static func resetUsage() {
        UserDefaults.standard.removeObject(forKey: dailyUsageKey)
    }

    /// 加总 `from..<now` 区间内的所有 daily buckets。
    private static func aggregate(from startDate: Date) -> UsageSnapshot {
        let d = loadDailyUsage()
        var calls = 0, input = 0, output = 0
        let startKey = dateKey(for: startDate)
        for (k, vals) in d {
            guard k >= startKey, vals.count >= 3 else { continue }
            calls  += vals[0]
            input  += vals[1]
            output += vals[2]
        }
        return UsageSnapshot(calls: calls, inputTokens: input, outputTokens: output)
    }

    private static func loadDailyUsage() -> [String: [Int]] {
        guard let raw = UserDefaults.standard.data(forKey: dailyUsageKey),
              let dict = try? JSONDecoder().decode([String: [Int]].self, from: raw)
        else { return [:] }
        return dict
    }

    private static func saveDailyUsage(_ d: [String: [Int]]) {
        guard let data = try? JSONEncoder().encode(d) else { return }
        UserDefaults.standard.set(data, forKey: dailyUsageKey)
    }

    private static func dateKey(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f.string(from: date)
    }

    // MARK: - 默认 prompt

    /// 默认 prompt —— 跟解析器的本地行为对齐:配件不抽 model、spec 词留 name、likely-model 才当 model。
    /// 改这个时同步检查 AIPayload.userMessage(for:availableTags:) 的 JSON 字段。
    static let defaultSystemPrompt: String = """
你是一个专门帮中文物品记录 app(何处 / Whereabouts)做字段解析的助手。

任务:给你一个物品的现有字段(name / model / version / color / purchaseSource / purchaseDate / locationPath / notes)+ **用户原始输入(整段原文)** + 一份本机已有标签列表,你需要重新分析、修正字段拆分错误,并从标签列表里挑一个分类。

**只**输出一个严格的 JSON 对象,不要任何额外文字、不要 markdown 代码块包裹、不要解释。

JSON Schema:
{
  "name": string,                   // 物品主标题,不含规格/颜色/位置;一般是"品牌 + 产品线",例:"iPhone 15 Pro"、"Power-Z USB线缆测试仪"、"Apple Watch备用表带"
  "model": string | null,           // 真正的型号 token(字母数字混合的代号),例:"KM003C"、"U60Pro"、"GT6";没有就 null
  "version": string | null,         // 容量/尺寸/规格,例:"512GB"、"11寸";没有就 null
  "color": string | null,           // 颜色词,例:"玫瑰金"、"黑色";没有就 null
  "purchaseDate": string | null,    // ISO 日期 "YYYY-MM-DD";不确定就 null
  "purchaseSource": string | null,  // 购买/获得渠道,任何来源描述都行:"京东"/"闲鱼"/"线下"/"朋友送的"/"二手"/"公司发的"...;不确定就 null
  "locationPath": [string] | null,  // 嵌套位置,父 → 子,例:["卧室","抽屉"];位置没变就 null,不要瞎改
  "tag": string                     // **必选**字段;**必须**是 user message 给的 available_tags 列表里的一个 name;都不合适就输出 "其他";不要自己造新标签名
}

判断规则:
1. **用户原始输入 = 最高解释依据,匹配时忽略大小写和全/半角差异**。user message 的"用户原始输入"段是用户在"记一条"框里写下的完整原文。规则解析有可能拆错字段、漏抓上下文 —— 以原文为准重新分析。比较名字 / 位置 / 标签时,`Hifi` 与 `HiFi`、`iphone` 与 `iPhone`、`Ｉ` 与 `I` 都算同一个;若原文里的位置只是大小写或全/半角与现有不同,**locationPath 就照搬现有的写法,不要因这种差异输出新路径**。
2. **rawInput 里有多件物品(顿号/逗号/分号/`和`等分隔)时,你只负责"当前已存字段"描述的那一件**。例:rawInput="各种国外银行卡、国外信用卡在抽屉",当前 name="国外信用卡" → 你的输出 name 也应该是"国外信用卡"(可微调,但**不要**把"国外银行卡"塞进 name);反过来当前 name="各种国外银行卡" → 不要改成"国外信用卡"。别人那条会被另一次 AI 调用单独处理。
3. **数量量词必须保留**:name 里出现的"3 个 / 2 副 / N 张 / N 盒 / N 套 / N 件 / N 本 / N 瓶 / N 条 / N 把 / N 根"等量词,**不要删**。"3个Magic Keyboard键盘" → name 保持 "3个Magic Keyboard键盘";不要简化成 "Magic Keyboard 键盘"。这些量词是用户记账的语义。
4. **配件 ≠ 型号**:用户名字里有"表带 / 保护壳 / 充电线 / 转接头 / 适配器"等词,Latin 前缀是品牌+品类整段留在 name 里,model 留 null
5. **接口/标准 ≠ 型号**:Type-C / USB / USB-C / HDMI / DP / Thunderbolt / Lightning / CFA / SD / TF / PCIe / NVMe 是接口规格,留在 name 里,model 留 null
6. **真正的型号是产品代号**:KM003C / U60Pro / GT6 / S23U 这种字母数字混合 + 无内部空格 + 3-14 字符 才是 model
7. **用户没说的字段一律 null**,不要凭空编造日期、渠道、规格
8. **位置**:能从原文 + 已有字段上下文里推出来就给完整 locationPath(数组从最外层到最里层,例 ["书房","MUJI塑料盒","HiFi零件"]);原文里完全没提新位置 → locationPath 输出 null。**位置匹配大小写/全半角不敏感**(见规则 1)。
   **复合位置串拆段(关键)**:用户经常把整条嵌套路径写成**无标点中文串**(例:"门口电梯间鞋架上方"、"卧室抽屉第二层"),你必须主动按层级拆段 —— **不要**把一长串复合位置塞成一段,因为数组第一段会被视为"房间"用于筛选 facet,塞成一段会污染房间列表。拆段启发式:
     - **开头的房间/区域词**(玄关、门口、电梯间、楼梯间、走廊、过道、卧室、主卧、次卧、儿童房、客厅、餐厅、书房、厨房、卫生间、洗手间、浴室、阳台、储物间、衣帽间、车库、办公室、地下室、阁楼、洗衣房 等)**必须**独立成数组第一段。
     - **容器/家具词**(鞋架、抽屉、柜子、书架、桌子、衣柜、床头柜、盒子、箱子、塑料盒、收纳盒、抽屉柜、储物柜 等)通常代表下一层,独立成段。
     - **方位/序号词**(上方、下方、里面、上面、旁边、后面、左侧、右侧、最里面、第一层、第二层、第三层 等)是**修饰词**,**绑在前面**的容器词上,不要单独拆。
     - 例 1:"门口电梯间鞋架上方" → `["门口", "电梯间", "鞋架上方"]`(开头是房间词"门口",拆出;中间"电梯间"是区域词,独立;"鞋架上方" = 容器+方位词,绑在一起。)
     - 例 2:"卧室抽屉第二层" → `["卧室", "抽屉第二层"]`(开头房间词拆出,容器+序号绑一起。)
     - 例 3:"书房MUJI塑料盒HiFi零件" → `["书房", "MUJI塑料盒", "HiFi零件"]`
     - 例 4:"得力塑料抽屉第三层"(整个串是一个具体物理实体,**没有房间词开头**)→ `["得力塑料抽屉第三层"]` 保留一段 OK。
   **格式严格**(关键):`locationPath` 数组的**每一段必须是纯名字**,**绝不可包含** `>`、`》`、`→`、`->`、`/` 之类的分隔符。层级关系**只能通过数组本身表达**。
     - ✓ 正确:`["书房", "绿色随身无线充盒子"]`
     - ✗ 错误:`["书房 > 绿色随身无线充盒子"]`(单段含 `>`)
     - ✗ 错误:`["书房/抽屉"]`(单段含 `/`)
   **typo 容错(关键)**:user message 末尾会给你"用户本机现有位置列表"。**优先**从该列表里挑最相似的一条作为 locationPath ——
     - 用户输 "塑料袋抽屉",列表里有 "塑料抽屉" → locationPath = ["塑料抽屉"](修正 typo,而不是新建)
     - 用户输 "卧室抽屉第二层",列表里有 "卧室 > 抽屉第二层" → locationPath = ["卧室", "抽屉第二层"]
     - 列表里完全没有相似的 → 输出新写法 OK
   匹配标准:字符差异 ≤ 1-2 个、同音字、繁简、大小写、全半角差异 —— 都视为同一位置。
9. **标签从列表里挑**:user message 末尾给的 available_tags 列表,你只能选其中一个 name 填到 tag 字段;一个都不合适就选 "其他"(它已经在列表里);名字比较同样忽略大小写差异。
   分类提示(供参考,不是穷举):银行卡/信用卡/身份证/护照/驾照/票据 → 票据证件;口红/面霜/化妆品/护肤 → 化妆护肤;衣服/鞋/包/眼镜/首饰 → 服饰鞋包;药品/维生素/创可贴 → 药品健康;茶叶/咖啡/食材/调味 → 食品干货;手办/玩具/桌游/卡牌 → 玩具收藏;运动/健身/户外/球类 → 户外运动;猫粮/狗粮/宠物玩具 → 宠物用品。

只输出 JSON 对象,不要任何前后文字。
"""
}
