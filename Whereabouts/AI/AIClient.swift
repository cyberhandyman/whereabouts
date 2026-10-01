import Foundation
import SwiftData

// MARK: - 服务商

/// 用户可选的 AI 服务商。
/// Phase 32 起从单一 Claude 扩到 Claude + 火山引擎。
/// 同时支持中转站(custom endpoint),所以非官方域名也能跑。
/// Phase 118:火山引擎排前面(国内用户主力路线;case 顺序即 UI picker 顺序,rawValue 不变)。
enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case volcengine = "volcengine"
    case claude     = "claude"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:     return "Claude"
        case .volcengine: return "火山引擎 / Volcengine"
        }
    }

    /// 默认 endpoint —— 官方域名。用户可以在 Settings 里改成中转站。
    var defaultEndpoint: String {
        switch self {
        case .claude:     return "https://api.anthropic.com/v1/messages"
        case .volcengine: return "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
        }
    }
}

/// 火山引擎(豆包)推荐模型预设(Phase 118)。
/// model 字段本质是自由字符串(也可填 ep- 接入点),这里只是常用档位的下拉快捷项;
/// 列表首项 = 推荐默认。版本号跟着火山方舟控制台更新(2026-07 核对)。
enum VolcModelPreset {
    static let all: [(id: String, label: String)] = [
        ("doubao-seed-2-0-lite-260428", "Doubao Seed 2.0 Lite · 推荐:快又便宜 / recommended"),
        ("doubao-seed-2-1-pro-260628",  "Doubao Seed 2.1 Pro · 更强更准,略贵 / strongest"),
        ("doubao-seed-1-6-250615",      "Doubao Seed 1.6 · 旧版 / legacy"),
    ]
    /// 推荐默认(用户没填过时的占位与一键选择)。
    static var recommended: String { all[0].id }
}

/// Claude 模型档位。用户在 Settings 里 picker 选,值是 Anthropic 真实 model ID。
/// Phase 112:补 2026 年新模型 Sonnet 5 / Opus 4.8;旧档位保留(用户存过的选择不失效)。
enum ClaudeModel: String, CaseIterable, Identifiable, Codable {
    case haiku45  = "claude-haiku-4-5-20251001"
    case sonnet46 = "claude-sonnet-4-6"
    case sonnet5  = "claude-sonnet-5"
    case opus47   = "claude-opus-4-7"
    case opus48   = "claude-opus-4-8"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .haiku45:  return "Haiku 4.5"
        case .sonnet46: return "Sonnet 4.6"
        case .sonnet5:  return "Sonnet 5"
        case .opus47:   return "Opus 4.7"
        case .opus48:   return "Opus 4.8"
        }
    }

    var tagline: String {
        switch self {
        case .haiku45:  return "快、便宜(推荐)/ fast & cheap"
        case .sonnet46: return "均衡 / balanced"
        case .sonnet5:  return "新一代均衡旗舰 / newest balanced flagship"
        case .opus47:   return "准,略贵 / accurate, pricier"
        case .opus48:   return "最强推理 / strongest reasoning"
        }
    }
}

// MARK: - AI 返回 schema(provider 共用)

struct AIResult: Decodable {
    let name: String?
    let model: String?
    let version: String?
    let color: String?
    let purchaseDate: String?
    let purchaseSource: String?
    let locationPath: [String]?
    /// Phase 42:分类标签。**必须**从 user message 给的 available_tags 列表里选一个;
    /// 都不合适就输出 "其他"。AI 不会创建新标签;app 这边按 name 在已有 Tag 表里反查,
    /// 找不到时把"其他"建出来挂上。
    let tag: String?

    private enum CodingKeys: String, CodingKey {
        case name, model, version, color, purchaseDate, purchaseSource, locationPath, tag
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name           = try c.decodeIfPresent(String.self,   forKey: .name)
        model          = try c.decodeIfPresent(String.self,   forKey: .model)
        version        = try c.decodeIfPresent(String.self,   forKey: .version)
        color          = try c.decodeIfPresent(String.self,   forKey: .color)
        purchaseSource = try c.decodeIfPresent(String.self,   forKey: .purchaseSource)
        locationPath   = try c.decodeIfPresent([String].self, forKey: .locationPath)
        tag            = try c.decodeIfPresent(String.self,   forKey: .tag)
        // Phase 122:允许 "YYYY" 之后,模型偶尔会输出裸数字 2024 —— 兜底转字符串,别让整条结果解析失败。
        if let s = try? c.decodeIfPresent(String.self, forKey: .purchaseDate) {
            purchaseDate = s
        } else if let n = try? c.decodeIfPresent(Int.self, forKey: .purchaseDate) {
            purchaseDate = String(n)
        } else {
            purchaseDate = nil
        }
    }
}

// MARK: - 连接状态(Phase 97)

/// 主窗口启动时跑一次 testConnection,结果存到 ContentView 的 @State。
/// 状态栏据此显示:① 无 key → 不渲染;② 测试中 → spinner;③ 就绪 → 绿色 ✓ + 用量;④ 失败 → 红色 ⚠️。
enum AIConnectionStatus: Equatable {
    case notConfigured     // 没填 API key
    case testing           // 正在 testConnection
    case ready             // 通了
    case failed(String)    // 失败 + 错误信息(截短)
}

// MARK: - 错误

enum AIError: LocalizedError {
    case missingAPIKey
    case invalidEndpoint
    case invalidResponse
    case apiError(String, Int?)
    case invalidJSON(raw: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return String(localized: "ai.error.missingKey")
        case .invalidEndpoint:
            return String(localized: "ai.error.invalidEndpoint")
        case .invalidResponse:
            return String(localized: "ai.error.invalidResponse")
        case .apiError(let msg, let code):
            if let c = code { return String(localized: "ai.error.api \(c) \(msg)") }
            return msg
        case .invalidJSON(let raw):
            let snippet = raw.count > 200 ? String(raw.prefix(200)) + "…" : raw
            return String(localized: "ai.error.invalidJSON \(snippet)")
        }
    }
}

// MARK: - 协议

/// 所有 AI 服务商共用的接口。
/// `understand` 拿一份 Item 现状快照(含可用标签集 / 位置集),返回结构化结果。
/// `availableTags` 在 user message 里展开给模型,让它从中挑一个。
protocol AIChatClient {
    /// Phase 122:入参从 `Item` 改成 Sendable 快照 —— 调用方在 MainActor 上拍好再 await,
    /// 网络层(后台 executor)不再读任何 @Model 属性。
    func understand(_ snapshot: AIItemSnapshot) async throws -> AIResult
    func testConnection() async throws
}

// MARK: - Phase 122:AI 请求快照(Sendable)

/// Phase 122:`understand` 以前直接收 `Item`,在后台 executor 上读 @Model 属性(name / rawInput /
/// location.path 逐级走 parent…)—— 批量 AI 或 CloudKit 合并时偶发崩溃。
/// 现在调用方必须在 MainActor 上先拍好这份纯值快照,网络调用只拿 Sendable 值。
struct AIItemSnapshot: Sendable {
    let name: String
    let model: String?
    let version: String?
    let color: String?
    let purchaseSource: String?
    let purchaseDate: Date?
    let purchaseDatePrecision: String?
    /// 父 → 子;nil = 没位置
    let locationPath: [String]?
    let notes: String
    let rawInput: String?
    /// 用户本机已有的所有 Tag.name;AI 只能从中挑一个填到 `tag` 字段。
    let availableTags: [String]
    /// Phase 73:用户本机所有现存 `Location.path`(`"书房 > 抽屉"` 形式)。
    /// AI 看到它们后可以:① 修 typo("塑料袋抽屉" → 命中"塑料抽屉");② 用更准的现存写法(大小写
    /// /全半角);③ 知道哪些位置已经"存在"。空数组表示用户还没建任何位置。
    let availableLocations: [String]

    @MainActor
    init(item: Item, availableTags: [String], availableLocations: [String]) {
        name = item.name
        model = item.model
        version = item.version
        color = item.color
        purchaseSource = item.purchaseSource
        purchaseDate = item.purchaseDate
        purchaseDatePrecision = item.purchaseDatePrecision
        locationPath = item.location.map { $0.path.components(separatedBy: " > ") }
        notes = item.notes
        rawInput = item.rawInput
        self.availableTags = availableTags
        self.availableLocations = availableLocations
    }
}

// MARK: - 共用 payload 辅助

/// 跟具体 provider 无关的两段:
///   - userMessage(for:) —— 把 Item 快照打包成 user message 字符串
///   - parseResult(text:) —— 从模型回的文本里抠出 JSON 解析成 AIResult
enum AIPayload {

    /// 用户 message 内容:把 item 当前字段塞成简短 JSON 给模型,加上"可用标签列表 + 可用位置列表",
    /// 叠上一句"请重新解析"。
    /// - `snapshot.availableTags` —— 用户本机已有的所有 Tag.name;AI 只能从中挑一个填到 `tag` 字段。
    /// - `snapshot.availableLocations` —— 用户本机已有的所有 Location.path("书房 > 抽屉");用于 typo 容错
    ///   和"找最相似已存在位置"。
    /// Phase 122:入参改为 Sendable 快照,纯值计算,可在任意线程调用。
    static func userMessage(for item: AIItemSnapshot) -> String {
        let availableTags = item.availableTags
        let availableLocations = item.availableLocations
        var dict: [String: Any] = ["name": item.name]
        if let v = item.model         { dict["model"]          = v }
        if let v = item.version       { dict["version"]        = v }
        if let v = item.color         { dict["color"]          = v }
        if let v = item.purchaseSource { dict["purchaseSource"] = v }
        if let d = item.purchaseDate {
            // Phase 122:按现有精度输出("2024" / "2024-05" / "2024-05-08"),别让模型看到补出来的 -01-01 再原样抄回。
            dict["purchaseDate"] = purchaseDateString(d, precision: item.purchaseDatePrecision)
        }
        if let path = item.locationPath {
            dict["locationPath"] = path
        }
        if !item.notes.isEmpty { dict["notes"] = item.notes }
        let data = (try? JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        )) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? "{}"

        // 把"可用标签 + 其他"也告诉模型;放在 prompt 末尾比 JSON 里更醒目。
        // 即使 user 一个 tag 都没建,也带上 "其他",这样 AI 至少能 fallback。
        var tagOptions = availableTags
        let otherKey = String(localized: "tag.preset.other")
        if !tagOptions.contains(where: { $0 == otherKey }) {
            tagOptions.append(otherKey)
        }
        let tagsJSON = (try? JSONSerialization.data(withJSONObject: tagOptions))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "[]"

        // Phase 43:用户当时在"记一条"里写的整段原文 —— 模型的最高解释依据。
        // 用户可能罗里吧嗦把好几件东西混着写,parser 拆条时若搞不清某条的位置/上下文,
        // AI 看到整段原文后能从相邻提到的房间、习惯叫法里补齐推理。
        let rawSection: String = {
            guard let r = item.rawInput?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !r.isEmpty else { return "" }
            return """

用户原始输入(最高优先级参考 —— 解释字段、消歧地点别称时以此为准):
\"\"\"
\(r)
\"\"\"
"""
        }()

        // Phase 73:把用户已有位置列表传给 AI —— 用于 typo 容错和"找最相似已存在位置"。
        // 列表可能很长(几十~上百条),所以放在 prompt 末尾 + 加截断保护(50 条上限)。
        // 超过 50 条时只取最近用过的 50 个;调用方传进来时应该已经按使用频率/时间排过序了。
        let locOptions = Array(availableLocations.prefix(50))
        let locSection: String = {
            guard !locOptions.isEmpty else { return "" }
            let locJSON = (try? JSONSerialization.data(withJSONObject: locOptions))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            return """

用户本机现有位置列表(typo 容错的最高依据 —— 用户输入"塑料袋抽屉"若列表里有"塑料抽屉"这条接近的,
locationPath 就输出 ["塑料抽屉"] 这种已存在的写法,不要凭空建新):
\(locJSON)
"""
        }()

        // Phase 122:purchaseDate 精度说明也放 user message —— 用户若自定义过 / 点过"恢复默认"
        // 把旧版 system prompt 存进了 UserDefaults,那份里还写着只能 "YYYY-MM-DD"。
        return """
请重新解析以下物品,按 system prompt 的 schema 输出 JSON。

`tag` 字段:只能从这个列表里选 1 个,都不合适就选 "\(otherKey)":
\(tagsJSON)

`purchaseDate` 字段:按原文实际精度输出 "YYYY" / "YYYY-MM" / "YYYY-MM-DD"(例:只说"2024年买的" → "2024"),不要把没说的月、日补成 01。
\(locSection)
\(rawSection)
当前已存字段(可能来自规则解析,需要你校正):
\(json)
"""
    }

    // MARK: Phase 122:购买日期 ⇄ 字符串

    /// 购买日期统一口径:公历 + en_US_POSIX + 当前时区 —— 跟 InputParser 一致(存"本地零点",
    /// 年/月精度时缺省月日补 1)。不用 Calendar.current,免得佛历 / 和历设备把 "2024" 当纪年。
    static var purchaseDateCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.timeZone = .current
        return cal
    }

    /// 精度 → 粗细等级:year=0 < month=1 < day=2(nil = 老数据,按 day)。
    static func purchaseDatePrecisionRank(_ precision: String?) -> Int {
        switch precision {
        case "year":  return 0
        case "month": return 1
        default:      return 2
        }
    }

    /// 按精度输出 "YYYY" / "YYYY-MM" / "YYYY-MM-DD"(ASCII 数字,不受系统日历 / locale 影响)。
    static func purchaseDateString(_ date: Date, precision: String?) -> String {
        let c = purchaseDateCalendar.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 0, m = c.month ?? 1, d = c.day ?? 1
        switch purchaseDatePrecisionRank(precision) {
        case 0:  return String(format: "%04d", y)
        case 1:  return String(format: "%04d-%02d", y, m)
        default: return String(format: "%04d-%02d-%02d", y, m, d)
        }
    }

    /// 解析 AI 回的 "YYYY" / "YYYY-MM" / "YYYY-MM-DD" → (date, precision "year"/"month"/"day")。
    /// 格式不对或日期不合法("2024-02-30" / "2024-13")返回 nil。
    static func parsePurchaseDate(_ raw: String) -> (date: Date, precision: String)? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = s.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(parts.count),
              parts[0].count == 4,
              parts.dropFirst().allSatisfy({ (1...2).contains($0.count) }),
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let y = Int(parts[0]),
              let m = parts.count >= 2 ? Int(parts[1]) : 1,
              let d = parts.count >= 3 ? Int(parts[2]) : 1
        else { return nil }
        let cal = purchaseDateCalendar
        guard let date = cal.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
        // 回读校验:挡掉被 Calendar 自动进位的非法日期
        let back = cal.dateComponents([.year, .month, .day], from: date)
        guard back.year == y, back.month == m, back.day == d else { return nil }
        let precision = ["year", "month", "day"][parts.count - 1]
        return (date, precision)
    }

    /// 从模型回复正文里抠 JSON。Claude / Volcengine 两边都用得上 —— 模型偶尔会包 ```json ``` ,这里兜底剥掉。
    /// Phase 122:再截取第一个 "{" 到最后一个 "}" —— 模型偶尔在 JSON 前后加一句话。
    static func parseResult(text: String) throws -> AIResult {
        var stripped = stripCodeFences(text)
        if let open = stripped.firstIndex(of: "{"),
           let close = stripped.lastIndex(of: "}"),
           open < close {
            stripped = String(stripped[open...close])
        }
        guard let data = stripped.data(using: .utf8) else {
            throw AIError.invalidJSON(raw: text)
        }
        do {
            return try JSONDecoder().decode(AIResult.self, from: data)
        } catch {
            throw AIError.invalidJSON(raw: text)
        }
    }

    private static func stripCodeFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```json")      { s = String(s.dropFirst("```json".count)) }
        else if s.hasPrefix("```")     { s = String(s.dropFirst(3)) }
        if s.hasSuffix("```")          { s = String(s.dropLast(3)) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Claude 客户端(Anthropic Messages API)

struct ClaudeClient: AIChatClient {
    /// Anthropic 公开 API 版本号。出新版才需要改。
    static let apiVersion = "2023-06-01"

    let apiKey: String
    let endpoint: String        // 用户可在 Settings 改成中转站
    let model: ClaudeModel
    let systemPrompt: String

    private struct Request: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Msg]
        struct Msg: Encodable { let role: String; let content: String }
    }
    private struct Response: Decodable {
        let content: [Block]
        /// Phase 88:Anthropic Messages API 在 response 里返了用量。
        let usage: Usage?
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
        }
    }
    private struct ErrorBody: Decodable {
        struct E: Decodable { let message: String? }
        let error: E?
    }

    func understand(_ snapshot: AIItemSnapshot) async throws -> AIResult {
        let req = try makeRequest(body: Request(
            model: model.rawValue,
            max_tokens: 1024,
            system: systemPrompt,
            messages: [.init(role: "user", content: AIPayload.userMessage(for: snapshot))]
        ))
        let (data, response) = try await URLSession.shared.data(for: req)
        try checkStatus(data: data, response: response)
        // Phase 122:响应体结构不符(中转站 / 异常回包)→ 统一报 invalidResponse,不抛裸 DecodingError。
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AIError.invalidResponse
        }
        let text = decoded.content.compactMap(\.text).joined()
        // Phase 88:累加用量(成功一次 = 1 call;token 拿到多少加多少)
        AISettings.bumpUsage(
            inputTokens:  decoded.usage?.input_tokens  ?? 0,
            outputTokens: decoded.usage?.output_tokens ?? 0
        )
        return try AIPayload.parseResult(text: text)
    }

    func testConnection() async throws {
        let req = try makeRequest(body: Request(
            model: model.rawValue,
            max_tokens: 16,
            system: "Reply with just the word OK.",
            messages: [.init(role: "user", content: "ping")]
        ))
        let (data, response) = try await URLSession.shared.data(for: req)
        try checkStatus(data: data, response: response)
    }

    private func makeRequest(body: Request) throws -> URLRequest {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else { throw AIError.missingAPIKey }
        guard let url = URL(string: endpoint) else { throw AIError.invalidEndpoint }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 30
        req.httpBody = try JSONEncoder().encode(body)
        return req
    }

    private func checkStatus(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error?.message
                ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.apiError(msg, http.statusCode)
        }
    }
}

// MARK: - 火山引擎客户端(OpenAI 兼容 Chat Completions API)

/// 火山引擎(火山方舟)的推理 API 是 OpenAI 兼容格式:
///   POST {endpoint}
///   Authorization: Bearer {api-key}
///   Body: { model, messages, max_tokens }
/// model 字段可以是 model 名(如 "doubao-seed-1-6-250615")
/// 也可以是 endpoint ID(如 "ep-2024xxxxxx-xxxxx"),Volcengine 控制台两种都给。
struct VolcengineClient: AIChatClient {

    let apiKey: String
    let endpoint: String        // 默认 https://ark.cn-beijing.volces.com/api/v3/chat/completions
    let model: String           // 用户自填(model 名或 endpoint id)
    let systemPrompt: String

    private struct Request: Encodable {
        let model: String
        let messages: [Msg]
        let max_tokens: Int
        struct Msg: Encodable { let role: String; let content: String }
    }
    private struct Response: Decodable {
        let choices: [Choice]
        /// Phase 88:OpenAI 兼容 schema 里 usage 在顶层。Volcengine 同样遵守。
        let usage: Usage?
        struct Choice: Decodable {
            let message: M
            /// Phase 122:拒答 / 内容审核拦截时 content 是 null —— 必须可选,否则整包解码失败。
            struct M: Decodable { let content: String? }
        }
        struct Usage: Decodable {
            let prompt_tokens: Int?
            let completion_tokens: Int?
        }
    }

    func understand(_ snapshot: AIItemSnapshot) async throws -> AIResult {
        let req = try makeRequest(body: Request(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: AIPayload.userMessage(for: snapshot)),
            ],
            max_tokens: 1024
        ))
        let (data, response) = try await URLSession.shared.data(for: req)
        try checkStatus(data: data, response: response)
        // Phase 122:响应体结构不符 → 统一报 invalidResponse,不抛裸 DecodingError。
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AIError.invalidResponse
        }
        // Phase 88:累加用量(拒答也已计费,照样记)
        AISettings.bumpUsage(
            inputTokens:  decoded.usage?.prompt_tokens     ?? 0,
            outputTokens: decoded.usage?.completion_tokens ?? 0
        )
        // Phase 122:content 为 null / 空(拒答、内容审核拦截)→ invalidResponse,而不是拿空串去解析 JSON。
        guard let text = decoded.choices.first?.message.content,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.invalidResponse
        }
        return try AIPayload.parseResult(text: text)
    }

    func testConnection() async throws {
        let req = try makeRequest(body: Request(
            model: model,
            messages: [.init(role: "user", content: "ping")],
            max_tokens: 16
        ))
        let (data, response) = try await URLSession.shared.data(for: req)
        try checkStatus(data: data, response: response)
    }

    private func makeRequest(body: Request) throws -> URLRequest {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else { throw AIError.missingAPIKey }
        guard !model.trimmingCharacters(in: .whitespaces).isEmpty else {
            // model 空跟 key 空一样,提示用户去填
            throw AIError.missingAPIKey
        }
        guard let url = URL(string: endpoint) else { throw AIError.invalidEndpoint }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try JSONEncoder().encode(body)
        return req
    }

    private func checkStatus(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            // OpenAI 风格错误体:{"error": {"message": "..."}}
            let msg: String = {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let err = json["error"] as? [String: Any],
                   let m = err["message"] as? String {
                    return m
                }
                return String(data: data, encoding: .utf8) ?? "Unknown error"
            }()
            throw AIError.apiError(msg, http.statusCode)
        }
    }
}

// MARK: - Phase 122:AI 回来后确认目标还在

/// AI 网络调用回来后(MainActor 上)确认目标 item 还在 —— await 期间可能被用户彻底删除,
/// 或被 CloudKit 合并删掉;不在了就丢弃结果,别往已删对象上写。
/// 注意:Item 自带的 `isDeleted` 是回收站软删除标记,遮蔽了 PersistentModel.isDeleted,
/// 不能用它判断"真删"。
@MainActor
func aiTargetStillExists(_ item: Item, in context: ModelContext) -> Bool {
    // 删除已保存 / 合并进来 → 脱离 context
    guard item.modelContext != nil else { return false }
    let id = item.persistentModelID
    // 删除还没保存
    if context.deletedModelsArray.contains(where: { $0.persistentModelID == id }) { return false }
    // 按 ID 还能从 store 取回
    var fd = FetchDescriptor<Item>(predicate: #Predicate { $0.persistentModelID == id })
    fd.fetchLimit = 1
    if let n = try? context.fetchCount(fd), n > 0 { return true }
    // 新建后尚未保存(临时 ID)的 item 按 ID 谓词未必取得回 —— 还在待插入列表里就算存在。
    return context.insertedModelsArray.contains(where: { $0.persistentModelID == id })
}

// MARK: - 把 AI 结果安全合并回 Item

/// AI 返回 null 的字段保持原值(不抹掉用户原有数据)。
/// 返回 locationPath 时同步写一条 LocationLog 历史。
/// Phase 39:同时把每个变化的字段写一条 EditLog,来源标识为 "ai_<provider>"。
@MainActor
func applyAIResult(_ result: AIResult, to item: Item, in context: ModelContext) {
    // diff 来源:用当前 active provider 标识(claude / volcengine)
    let source = "ai_\(AISettings.activeProvider.rawValue)"
    let snap = ItemFieldSnapshot(item)

    if let n = result.name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
        item.name = n
    }
    if let m = result.model     { item.model   = m.isEmpty ? nil : m }
    if let v = result.version   { item.version = v.isEmpty ? nil : v }
    if let c = result.color     { item.color   = c.isEmpty ? nil : c }
    if let s = result.purchaseSource { item.purchaseSource = s.isEmpty ? nil : s }
    // Phase 122:AI 可按实际精度回 "YYYY" / "YYYY-MM" / "YYYY-MM-DD",精度跟着走
    // (以前一律写 "day","2024年买的" 被存成 2024-01-01 精确到日)。
    // 现有精度更粗、且 AI 日期落在现有那一年 / 那一月内 → 视为 AI 把月日补全了,保留现有值。
    // 现有精度更细(用户手动定到了某天)、AI 只回了同一年 / 同一月 → 也保留现有值,
    // 不把精确日期降级;除非现有值的月日正好是补位值(1 月 1 日 / 1 日)—— 那多半是旧版
    // 把"2024年买的"硬存成了 2024-01-01,这时按 AI 的粗精度纠正。
    if let dateStr = result.purchaseDate, !dateStr.isEmpty,
       let parsed = AIPayload.parsePurchaseDate(dateStr) {
        let keepExisting: Bool = {
            guard let existing = item.purchaseDate else { return false }
            let existingRank = AIPayload.purchaseDatePrecisionRank(item.purchaseDatePrecision)
            let parsedRank = AIPayload.purchaseDatePrecisionRank(parsed.precision)
            guard existingRank != parsedRank else { return false }
            let cal = AIPayload.purchaseDateCalendar
            let a = cal.dateComponents([.year, .month, .day], from: existing)
            let b = cal.dateComponents([.year, .month], from: parsed.date)
            let coarser = min(existingRank, parsedRank)
            let agree = a.year == b.year && (coarser == 0 || a.month == b.month)
            guard agree else { return false }
            if existingRank < parsedRank { return true }
            // 现有更细:是补位值就允许降级纠正,否则保留
            let isPadding = parsedRank == 0 ? (a.month == 1 && a.day == 1) : (a.day == 1)
            return !isPadding
        }()
        if !keepExisting {
            item.purchaseDate = parsed.date
            item.purchaseDatePrecision = parsed.precision
        }
    }
    if let path = result.locationPath, !path.isEmpty {
        let currentPath = item.location?.path.components(separatedBy: " > ") ?? []
        // Phase 60:case-insensitive 比较当前路径,不然 "MUJI塑料盒HiFi零件" vs "MUJI塑料盒Hifi零件"
        // 会因为大小写不同被判为"变动",反复写同一条 LocationLog。
        let same = currentPath.count == path.count &&
            zip(currentPath, path).allSatisfy { $0.foldedForMatch == $1.foldedForMatch }
        if !same {
            // Phase 60:走 bestMatchOrEnsure —— 对 AI 给的(可能不精确的)path 做
            // case-insensitive + 最长匹配反查。直接修 MUJI bug:
            //   AI 给 ["书房","MUJI塑料盒"],而库里有 ["书房","MUJI塑料盒","HiFi零件"]
            //   → 返回更深的那个,不会丢"HiFi零件"层。
            let newLoc = Location.bestMatchOrEnsure(path: path, in: context)
            item.location = newLoc
            let log = LocationLog(recordedAt: .now, location: newLoc, item: item)
            context.insert(log)
            item.lastSeenAt = .now
            item.lastActionType = "moved"
        }
    }
    // Phase 42:把 AI 选的标签挂到 item 上 —— 从本机已有 Tag 反查;无匹配时确保"其他"存在并用它。
    // AI 永远不会创建新 tag;创建权一直在 app 这边,只有"其他"是兜底自动建。
    applyAITagSuggestion(result.tag, to: item, in: context)

    item.updatedAt = .now
    // 这一步必须在所有字段写完之后调,snap 已经在最前面拍过快照。
    snap.recordEdits(against: item, source: source, in: context)
}

/// AI 返回的 tag 字符串 → 找本地匹配 Tag → 挂上;找不到就 ensure 一个"其他"再挂。
/// 大小写不敏感比较。
///
/// Phase 44:AI 是权威分类器 —— **替换** 当前 tag 集合,而不是 append。
/// 否则被 parser 自动挂过一个 tag + AI 又挂一个,详情会出现两个圆点。
/// 用户若想保留自己手动加的 tag,在 AI 跑完后手动重挂即可。
@MainActor
private func applyAITagSuggestion(_ rawTagName: String?, to item: Item, in context: ModelContext) {
    let all = (try? context.fetch(FetchDescriptor<Tag>())) ?? []

    // 先尝试精确 / 大小写不敏感地匹中用户已有 tag
    if let n = rawTagName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
        if let exact = all.first(where: { $0.name == n }) {
            setAITag(exact, on: item); return
        }
        if let ci = all.first(where: { $0.name.lowercased() == n.lowercased() }) {
            setAITag(ci, on: item); return
        }
    }
    // 没匹中 → 兜底"其他"。已存在直接复用;没存在就 ensure 一个出来。
    let otherName = String(localized: "tag.preset.other")
    if let existing = all.first(where: { $0.name == otherName }) {
        setAITag(existing, on: item)
        return
    }
    // 用一个跟现有 6 个预设色不重叠的色(teal),让"其他"在标签 chip 行视觉独立。
    let other = Tag(name: otherName, colorHex: "#5AC8FA")
    context.insert(other)
    setAITag(other, on: item)
}

/// 把 item 的 tag 集合**重置**成只有这一个 tag(Phase 44)。
/// 已经是这个 tag 就 noop;否则清空再挂上唯一一个。
private func setAITag(_ tag: Tag, on item: Item) {
    if item.tags.count == 1,
       item.tags[0].persistentModelID == tag.persistentModelID {
        return  // 已经是正确状态
    }
    item.tags.removeAll()
    item.tags.append(tag)
}
