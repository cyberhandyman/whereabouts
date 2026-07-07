import Foundation

//       下面所有词典(渠道/品牌/颜色/场所)与分隔符规则都是中文 NLP 数据,不参与 String Catalog。
//       面向用户的 summary 字符串(buildFieldUpdate / makeBuySummary)已走 String(localized:)。
//
/// 把一行自然语言切成"物品名 + 嵌套位置"两部分。
///
/// 支持的输入形态:
///   "充电宝 在 卧室抽屉第二格"        → name=充电宝, path=[卧室抽屉第二格]
///   "充电宝 在 家 > 卧室 > 抽屉"       → name=充电宝, path=[家, 卧室, 抽屉]
///   "护照: 保险箱"                      → name=护照, path=[保险箱]
///   "钥匙 → 玄关 / 钩子"                → name=钥匙, path=[玄关, 钩子]
///   "充电宝在卧室里"                    → name=充电宝, path=[卧室]   (剥末尾"里")
///   "护照"                              → name=护照, path=[]
enum InputParser {

    struct Parsed: Equatable {
        let name: String
        /// 顶 → 下的位置层级,可能为空。
        /// `var` 而非 let:Phase 72 多 sibling 间位置传染需要后处理改写。
        var locationPath: [String]
        // 自动从原句抽出的可选元数据 —— 抽不到就是 nil。
        let purchaseDate: Date?
        /// 配套 purchaseDate 的精度。"year" / "month" / "day" / nil。
        let purchaseDatePrecision: String?
        let purchaseSource: String?
        let model: String?
        let color: String?
        let version: String?

        init(name: String, locationPath: [String],
             purchaseDate: Date? = nil,
             purchaseDatePrecision: String? = nil,
             purchaseSource: String? = nil,
             model: String? = nil,
             color: String? = nil,
             version: String? = nil) {
            self.name = name
            self.locationPath = locationPath
            self.purchaseDate = purchaseDate
            self.purchaseDatePrecision = purchaseDatePrecision
            self.purchaseSource = purchaseSource
            self.model = model
            self.color = color
            self.version = version
        }
    }

    /// 常见购买渠道。识别顺序很关键 —— 较长的先识别("Apple Store"先于"Apple")。
    /// 这是给"创建新物品"流程里的渠道抽取兜底用的。
    /// 在"更新已有物品"流程里(matchUpdateIntent Pattern B)是放宽的 —— 任何 X 都行,因为句式本身已经确认了。
    static let knownPurchaseSources: [String] = [
        "Apple Store", "苹果商店", "天猫超市", "山姆会员店", "Amazon",
        "闲鱼", "淘宝", "京东", "拼多多", "天猫", "亚马逊",
        "得物", "唯品会", "苏宁", "国美", "顺丰", "屈臣氏",
        "山姆", "沃尔玛", "盒马", "美团", "抖音", "Costco", "永辉", "物美", "大润发",
        "实体店", "线下",
    ]

    /// 常见品牌词典:`(出现在 name 里的 token, 归一化后的品牌名)`。
    /// 同一个品牌允许多个 alias("Apple" / "苹果" 都归到 "Apple")。
    /// 长 token 优先匹配("OnePlus" 优于 "One")。
    /// brand(for:) 用 contains 而非 hasPrefix —— "iPhone Apple 保护壳" 也算苹果。
    static let brandAliases: [(token: String, canonical: String)] = [
        // 数码 / 电子
        ("Apple", "Apple"), ("苹果", "Apple"),
        ("华为", "华为"), ("Huawei", "华为"),
        ("小米", "小米"), ("Xiaomi", "小米"), ("Redmi", "小米"),
        ("Pixel", "Google"), ("Google", "Google"),
        ("OPPO", "OPPO"),
        ("vivo", "vivo"),
        ("一加", "一加"), ("OnePlus", "一加"),
        ("荣耀", "荣耀"), ("Honor", "荣耀"),
        ("魅族", "魅族"),
        ("三星", "三星"), ("Samsung", "三星"),
        ("索尼", "索尼"), ("Sony", "索尼"),
        ("Bose", "Bose"),
        ("JBL", "JBL"),
        ("森海塞尔", "森海塞尔"), ("Sennheiser", "森海塞尔"),
        ("AKG", "AKG"),
        ("罗技", "罗技"), ("Logitech", "罗技"),
        ("微软", "微软"), ("Microsoft", "微软"),
        ("联想", "联想"), ("Lenovo", "联想"), ("ThinkPad", "联想"),
        ("戴尔", "戴尔"), ("Dell", "戴尔"),
        ("惠普", "惠普"), ("HP", "惠普"),
        ("Anker", "Anker"),
        ("倍思", "倍思"), ("Baseus", "倍思"),
        ("公牛", "公牛"),
        ("中兴", "中兴"), ("ZTE", "中兴"),
        // 家电
        ("戴森", "戴森"), ("Dyson", "戴森"),
        ("美的", "美的"), ("Midea", "美的"),
        ("格力", "格力"),
        ("海尔", "海尔"), ("Haier", "海尔"),
        ("科沃斯", "科沃斯"), ("Ecovacs", "科沃斯"),
        ("石头", "石头"), ("Roborock", "石头"),
        ("云鲸", "云鲸"),
        ("西门子", "西门子"), ("Siemens", "西门子"),
        ("博世", "博世"), ("Bosch", "博世"),
        // 厨具
        ("双立人", "双立人"), ("Zwilling", "双立人"),
        ("WMF", "WMF"),
        ("膳魔师", "膳魔师"), ("Thermos", "膳魔师"),
        ("苏泊尔", "苏泊尔"),
        ("九阳", "九阳"),
        // 家居
        ("宜家", "宜家"), ("IKEA", "宜家"),
        ("无印良品", "无印良品"), ("MUJI", "无印良品"),
        // 户外
        ("始祖鸟", "始祖鸟"), ("Arc'teryx", "始祖鸟"),
        ("迪卡侬", "迪卡侬"), ("Decathlon", "迪卡侬"),
    ]

    // MARK: - Phase 14: 关键词 → 预设 tag 建议
    //
    // 录入完一条物品后,可选地按物品名自动给它挂一个最匹配的预设 tag。
    // 这里的映射不入库,只在录入时算 —— 沿用 brand(for:) 的思路:
    //   - 字典 key 是关键词(中英文都列);
    //   - 字典 value 是预设 tag 的 colorHex(稳定,不随 locale / 重命名变化)。
    // 调用方拿到 hex 后,在 allTags 里按 colorHex 反查实际 Tag 对象。
    //
    // 选 colorHex 而非 tag 名作为锚:
    //   - 用户切换语言后 tag.name 仍是当初 seed 时的语言;按 name 反查会 miss。
    //   - 颜色一旦 seed 就稳定,即便用户重命名 tag,只要颜色没改就还能匹中。
    //   - 用户把 preset 删掉、又新建了同色 tag,也能复用 —— 这是想要的行为。

    /// (关键词列表, 对应预设 tag 颜色)。
    /// **顺序**:更"窄"的类目排前面。"手机"出现时既属于 3C,也含"机"字可能撞别的;
    /// 这里 3C 在最前,确保它优先命中。
    /// 一个关键词撞两个类目时,**先扫到的胜出**(短路返回)。
    static let tagKeywordHints: [(keywords: [String], hex: String)] = [
        // 3C 电子 → 蓝色 #007AFF
        ([
            "手机", "iphone", "samsung", "三星手机", "华为手机", "小米手机",
            "手表", "watch", "智能手表", "手环", "airtag",
            "平板", "ipad", "tablet",
            "电脑", "笔记本", "macbook", "imac", "pc", "主机",
            "耳机", "earphone", "headphone", "airpods", "耳塞", "蓝牙耳机",
            // 充电类
            "充电宝", "移动电源", "充电器", "充电头", "充电板", "无线充", "数据线", "线材", "充电线",
            // 输入设备
            "鼠标", "键盘", "trackpad", "触控板",
            // 存储
            "硬盘", "u盘", "ssd", "移动硬盘", "固态硬盘",
            "读卡器", "存储卡", "memory card", "sd卡", "tf卡",
            // 音频
            "音箱", "音响", "speaker", "蓝牙音箱",
            // 游戏
            "switch", "ps5", "ps4", "xbox", "游戏机", "手柄",
            // 显示
            "投影", "显示器", "屏幕", "显示屏",
            // 影像
            "摄像头", "相机", "camera", "云台", "三脚架",
            // 网络
            "路由器", "router", "网卡", "网线", "随身wifi", "调制解调器",
            // 阅读
            "kindle", "电子书", "电纸书",
            // 数字 token / 身份
            "u盾", "ukey",
        ], "#007AFF"),
        // 厨具 → 橙色 #FF9500
        ([
            "锅", "炒锅", "汤锅", "煎锅", "蒸锅", "压力锅", "电饭煲",
            "碗", "盘", "餐盘", "盘子", "餐具",
            // 注意:这里不放单字 "刀" —— 会撞到 "螺丝刀"(工具)。具体刀型列出来即可。
            "菜刀", "水果刀", "西餐刀", "切肉刀",
            "铲", "锅铲", "勺", "汤勺", "饭勺", "筷子",
            "杯子", "水杯", "保温杯", "马克杯", "玻璃杯", "酒杯",
            "水壶", "茶壶", "茶具", "茶杯",
            "砧板", "案板",
            "烤箱", "微波炉", "搅拌", "搅拌机", "破壁机",
            "蒸笼", "蒸格", "炊具",
        ], "#FF9500"),
        // 文具 → 绿色 #34C759
        ([
            "笔", "圆珠笔", "钢笔", "铅笔", "记号笔", "马克笔", "荧光笔",
            "本", "本子", "笔记本", "记事本", "日记本", "活页", "便签", "便利贴",
            "纸", "打印纸", "信纸",
            "书", "书本", "教材", "字典", "词典",
            "墨水", "胶水", "胶带", "双面胶",
            "尺", "尺子", "三角板", "圆规",
            "橡皮", "修正带", "夹子", "回形针", "订书机", "订书针",
        ], "#34C759"),
        // 办公用品 → 紫色 #AF52DE
        ([
            "文件", "文件夹", "档案袋", "档案盒", "活页夹",
            "印章", "印泥", "印台", "名片", "名片夹",
            "票据", "发票", "收据",
            "工牌", "胸牌", "工卡", "门禁卡",
            "公文", "公文包",
        ], "#AF52DE"),
        // 小工具 → 黄色 #FFCC00
        ([
            "螺丝刀", "改锥", "钳子", "扳手", "锤子", "榔头",
            "电钻", "冲击钻", "美工刀", "壁纸刀", "胶枪", "卷尺", "皮尺",
            "万用表", "测电笔", "水平仪",
            "锯", "刨", "凿", "工具箱", "工具袋",
            "螺丝", "螺帽", "钉子",
        ], "#FFCC00"),
        // Phase 59 新增类目 —— 顺序很关键(更窄的类目排前面;一个 kw 命中即短路返回)。

        // 化妆护肤 → 粉色 #FF2D55
        // 必须排在"生活用品"前 —— 否则 "口红/面霜" 会被生活用品兜底吃掉。
        ([
            "化妆", "化妆品", "口红", "唇釉", "粉底", "粉饼", "眼影", "腮红",
            "眉笔", "眉粉", "睫毛膏", "睫毛", "眼线", "卸妆", "化妆棉",
            "护肤", "面霜", "乳液", "面膜", "爽肤水", "化妆水", "精华", "精华液",
            "防晒", "防晒霜", "隔离", "BB霜", "粉底液",
            "香水", "古龙水", "身体乳", "护手霜", "唇膏",
        ], "#FF2D55"),

        // 药品健康 → 红色 #FF3B30
        // "药" 单字命中常见品类 —— 跟"刀"那次的坑不一样,这里 "药" 不容易撞别的物品名。
        ([
            "药", "药品", "感冒药", "退烧药", "止痛", "止咳", "维生素", "钙片",
            "鱼油", "蛋白粉", "维C", "保健品", "营养品",
            "创可贴", "纱布", "棉签", "酒精", "碘伏", "消毒",
            "体温计", "血压计", "血糖", "血氧",
            "口罩", "护理", "护腰", "护膝", "膏药", "贴",
        ], "#FF3B30"),

        // 食品干货 → 浅橙 #FFB05A(跟厨具橙错开)
        // 厨具 #FF9500 已处理"锅碗瓢盆";这里处理"吃的东西"。
        ([
            "茶叶", "咖啡", "咖啡豆", "咖啡粉", "挂耳",
            "巧克力", "饼干", "糖果", "糖", "蜂蜜",
            "米", "大米", "面", "面粉", "面条", "挂面", "粉丝", "粉条",
            "油", "酱油", "醋", "盐", "味精", "鸡精",
            "酒", "白酒", "红酒", "啤酒", "饮料", "汽水",
            "坚果", "瓜子", "花生", "杏仁", "腰果",
            "罐头", "麦片", "燕麦", "奶粉",
        ], "#FFB05A"),

        // 玩具收藏 → 深绿 #30D158(跟文具绿 #34C759 错开)
        ([
            "手办", "模型", "积木", "乐高", "lego", "拼图",
            "玩具", "毛绒", "公仔", "娃娃", "玩偶",
            "棋", "象棋", "围棋", "扑克", "桌游",
            "卡牌", "宝可梦", "万智牌", "yu-gi-oh",
            "盲盒", "盲袋",
            "手账", "贴纸",  // 跟文具区分:手账偏收藏向
        ], "#30D158"),

        // 服饰鞋包 → 靛色 #5856D6
        ([
            "衣", "衣服", "上衣", "外套", "夹克", "西装", "T恤", "t恤",
            "衬衫", "毛衣", "卫衣", "羽绒", "大衣", "风衣", "马甲",
            "裤", "牛仔裤", "运动裤", "短裤", "西裤",
            "裙", "连衣裙", "半身裙",
            "鞋", "皮鞋", "运动鞋", "凉鞋", "靴子", "高跟鞋", "拖鞋", "袜子",
            "包", "背包", "手提包", "斜挎包", "双肩包", "钱包", "皮包",
            "帽子", "围巾", "手套", "腰带", "皮带",
            "首饰", "饰品", "戒指", "项链", "手链", "手镯", "耳环", "耳钉",
            "眼镜", "墨镜", "太阳镜",
        ], "#5856D6"),

        // 票据证件 → 棕色 #A2845E(跟办公紫错开;办公=印章/文件夹这类工具)
        ([
            "证", "证件", "身份证", "户口本", "护照", "签证", "驾照", "驾驶证",
            "行驶证", "结婚证", "学位证", "毕业证", "学生证", "工作证", "工牌",
            "银行卡", "信用卡", "社保卡", "医保卡", "公交卡",
            "票", "发票", "收据", "门票", "机票", "车票",
            "合同", "保单", "保险单", "病历",
            "钥匙", "钥匙扣", "卡包", "证件包",
        ], "#A2845E"),

        // 户外运动 → 湖蓝 #64D2FF
        ([
            "运动", "健身", "瑜伽", "瑜伽垫", "哑铃", "杠铃", "弹力带", "跳绳",
            "球", "篮球", "足球", "排球", "网球", "羽毛球", "乒乓球", "高尔夫", "高尔夫球",
            "球拍", "球杆",
            "登山", "徒步", "户外", "露营", "帐篷", "睡袋", "防潮垫",
            "登山杖", "登山鞋", "冲锋衣",
            "自行车", "山地车", "公路车", "骑行",
            "滑板", "滑雪", "滑雪板", "雪板",
            "钓鱼", "钓竿", "鱼竿", "渔具",
            "泳衣", "泳镜", "泳帽",
            "护具", "头盔",  // 跟健康类的"护膝"区分:头盔/护具偏运动场景
        ], "#64D2FF"),

        // 宠物用品 → 紫色 #BF5AF2
        ([
            "宠物", "猫", "狗", "鸟", "鱼缸", "金鱼", "仓鼠", "兔子",
            "猫粮", "狗粮", "鸟食", "宠物粮",
            "猫砂", "猫砂盆", "猫窝", "狗窝", "宠物床",
            "牵引绳", "项圈", "胸背带",
            "猫抓板", "猫爬架", "逗猫棒", "玩具球",
            "宠物用品", "宠物玩具",
            "驱虫", "宠物药",  // 跟药品红错开:宠物专属
        ], "#BF5AF2"),

        // 生活用品 → 灰色 #8E8E93 (兜底类,放最后 —— 上面没命中才走这里)
        ([
            "雨伞", "伞",
            "纸巾", "抽纸", "卷纸",
            "毛巾", "浴巾", "睡衣",
            "洗发水", "护发素", "沐浴露", "肥皂", "洗手液",
            "牙膏", "牙刷", "牙线",
            "洗衣液", "洗衣粉", "柔顺剂",
            "湿巾", "棉签",
            "镜子", "梳子", "吹风机", "卷发棒",
        ], "#8E8E93"),
    ]

    /// 按物品名建议一个预设 tag 的颜色码;扫到第一个关键词就短路返回。
    /// 抽不到返回 nil(调用方可以选择不挂)。
    /// 匹配方式:全转小写后 contains —— 大小写不敏感,但子串敏感("手机壳" 也算"手机")。
    static func suggestTagColorHex(forName name: String) -> String? {
        let lower = name.lowercased()
        for (keywords, hex) in tagKeywordHints {
            for kw in keywords where lower.contains(kw.lowercased()) {
                return hex
            }
        }
        return nil
    }

    /// 从 name 推断品牌。零成本:不入库,只在显示/筛选时算。
    static func brand(for name: String) -> String? {
        let lower = name.lowercased()
        let sorted = brandAliases.sorted { $0.token.count > $1.token.count }
        for (token, canonical) in sorted {
            if lower.contains(token.lowercased()) { return canonical }
        }
        return nil
    }

    /// 常见颜色词。按长度降序排,匹"深空灰色"优先于"灰色"。
    /// 只列"含'色/金'结尾"的形式,避免单字误切("红"也可能是名字一部分)。
    /// 写入用户的 color 字段时也用这里的原词,便于将来归一化。
    static let knownColors: [String] = [
        // 复合长词
        "玫瑰金色", "玫瑰金", "深空灰色", "深空灰", "深空黑色", "深空黑",
        "香槟金色", "香槟金", "钛金色", "原色钛金属", "沙漠色钛金属",
        // Apple 当代色(iPhone / Mac 当前几代)
        "午夜色", "午夜黑", "星光色", "星光",
        "远峰蓝", "山岳蓝", "海蓝色", "天峰蓝",
        "暗夜紫", "暮光紫",
        "暗紫色", "亮紫色", "深紫色", "浅紫色", "紫罗兰色",
        "深蓝色", "浅蓝色", "天蓝色", "藏蓝色", "宝蓝色", "孔雀蓝",
        "深红色", "浅红色", "酒红色", "玫红色", "枣红色", "砖红色", "中国红",
        "深绿色", "浅绿色", "墨绿色", "草绿色", "军绿色", "薄荷绿",
        "象牙白", "纯白色", "米白色", "雪白色", "亚光白",
        "炭黑色", "亮黑色", "亚光黑", "墨黑色",
        "鎏金色",
        // 单字 + "色"
        "灰色", "黑色", "白色", "红色", "蓝色", "绿色",
        "黄色", "紫色", "粉色", "棕色", "橙色", "银色", "金色",
        "米色", "驼色", "卡其色", "咖啡色", "巧克力色",
    ]

    // MARK: - 配置(改这里就能扩展同义词)

    /// 名字和位置之间的"动词式"分隔符,按优先级排列(带空格优先 → 无空格)。
    private static let nameLocationSeparators: [String] = [
        " 在 ", " 位于 ", " → ", " -> ", "：", ":", "→", "->", "在", "位于"
    ]

    /// 位置内部的层级符号(展开 path)。
    /// "的" 是中文天然的从属关系:"书房的白色桌子" = 书房 → 白色桌子。
    /// 注:这只作用在"位置"那一侧;物品名里的"的"不会被切(如"我的钱包"作为名字保留)。
    private static let pathSeparators: [String] = [">", "》", "/", "→", "->", " - ", " · ", "的"]

    /// 位置末尾常见冗余后缀,会被剥掉:"卧室里" → "卧室"。
    /// 注意:只剥末尾,且剥完得有剩余。
    private static let trailingNoise: [String] = ["里", "中", "内", "上面", "上", "下面"]

    /// 常见中文场所词典 —— 用户即使没在中间打空格/`的`/`>`,
    /// 我们也能从这个串里识别出最长的场所前缀,自动切层。
    /// 例:"书房白色桌子" → ["书房", "白色桌子"]
    /// 增添新词时尽量保留 2 字以上,避免单字误切。
    static var knownPlaces: Set<String> = [
        // 居住空间
        "客厅", "餐厅", "卧室", "主卧", "次卧", "儿童房", "老人房",
        "书房", "厨房", "卫生间", "浴室", "厕所", "洗手间", "卫浴",
        "玄关", "走廊", "过道", "阳台", "露台", "天台", "楼梯", "地下室",
        "储物间", "储藏室", "衣帽间", "工具间", "杂物间",
        "办公室", "工作室", "健身房", "茶室", "影音室", "游戏房",
        "车库", "院子", "花园",
        // 大型家具/区域
        "鞋柜", "衣柜", "书柜", "书架", "酒柜", "电视柜", "床头柜",
        "餐桌", "书桌", "茶几", "梳妆台", "五斗柜", "沙发", "床",
        "冰箱", "微波炉", "烤箱", "灶台", "水槽", "橱柜", "吊柜",
        "保险箱", "首饰盒", "工具箱",
    ]

    // MARK: - 入口

    /// 把一串文字当成"纯位置串"解析,不试图切名字。
    /// 用在"修改位置"对话框 —— 此时已知整个串都是位置。
    static func parseLocationOnly(_ raw: String) -> [String] {
        parseLocationPath(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - 字段更新意图("X 的 型号是 Y" / "X 在 京东 买的" / "X 是 DATE 买的")

    /// 一次字段更新里要写什么。caller 用这个直接给 Item 赋值。
    struct ItemChanges: Equatable {
        var model: String?
        var version: String?
        var color: String?
        var notes: String?
        var purchaseDate: Date?
        var purchaseDatePrecision: String?
        var purchaseSource: String?

        var isEmpty: Bool {
            model == nil && version == nil && color == nil && notes == nil
                && purchaseDate == nil && purchaseSource == nil
        }
    }

    struct UpdateIntent: Equatable {
        /// 输入串里匹配到的已存在物品名(大小写按原始 candidate 给的)
        let matchedName: String
        let changes: ItemChanges
        /// 给用户看的可读总结("型号 → 「U60Pro」")
        let summary: String
    }

    /// 输入是不是对某个 candidateNames 里物品的"字段更新"。
    /// 不是的话返回 nil,让 caller 回到正常录入流。
    ///
    /// 识别两类:
    ///   A. "X 的? FIELD 是/为 VALUE"  —— FIELD ∈ {型号,版本,规格,颜色,备注,渠道,购买渠道,日期,购买日期}
    ///   B. "X (是|在)? ... 买的"        —— 利用现有 date/source 抽取,残余应只剩连接词
    static func matchUpdateIntent(_ raw: String, candidateNames: [String]) -> UpdateIntent? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let trimmedLower = trimmed.lowercased()

        // 候选 = 全名 + 全名的空格分词("华为手表 灰色" 也允许只输入"华为手表"匹中)。
        // 用 (匹配键, 真正的 name) 关联,这样 hasPrefix 命中后还能找回原 item。
        // 最长前缀优先:避免短 token 抢了长全名("中兴" 抢"中兴随身WiFi")。
        var candidates: [(key: String, name: String)] = []
        for name in candidateNames {
            candidates.append((name, name))
            for token in name.split(separator: " ") where token.count >= 2 {
                let t = String(token)
                if t != name { candidates.append((t, name)) }
            }
        }
        let sorted = candidates.sorted { $0.key.count > $1.key.count }
        var seenKeys: Set<String> = []
        for (key, name) in sorted {
            // 同一 key 只试一次(多个 item 同名空格分词可能撞)。第一个命中即返回,后面跳过。
            if !seenKeys.insert(key).inserted { continue }
            let keyLower = key.lowercased()
            guard trimmedLower.hasPrefix(keyLower) else { continue }
            let rest = String(trimmed.dropFirst(key.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rest.isEmpty else { continue }

            // ── Pattern A: 的FIELD是VALUE / FIELD是VALUE
            let fields: [(String, FieldKind)] = [
                ("购买渠道", .source), ("购买日期", .date),
                ("型号", .model), ("版本", .version), ("规格", .version),
                ("颜色", .color), ("备注", .notes),
                ("渠道", .source), ("日期", .date), ("来源", .source),
            ]
            for (field, kind) in fields {
                for connector in ["是", "为"] {
                    for prefixDe in ["的", ""] {
                        let prefix = "\(prefixDe)\(field)\(connector)"
                        if rest.hasPrefix(prefix) {
                            let value = String(rest.dropFirst(prefix.count))
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if !value.isEmpty {
                                return buildFieldUpdate(matchedName: name, kind: kind, value: value)
                            }
                        }
                    }
                }
            }

            // ── Pattern B: 以"买的/购买的"结尾,中间是日期/渠道/两者
            // 这里渠道不限于 knownPurchaseSources —— 句式已经明确是"X买的",
            // 中间任何非空字符串就当渠道。
            let trailingBuy = ["买的", "购买的", "购入的"]
            if trailingBuy.contains(where: { rest.hasSuffix($0) }) {
                let (date, precision, source) = parseUpdateBuyPhrase(rest)
                if date != nil || source != nil {
                    var changes = ItemChanges()
                    changes.purchaseDate = date
                    changes.purchaseDatePrecision = precision
                    changes.purchaseSource = source
                    return UpdateIntent(
                        matchedName: name,
                        changes: changes,
                        summary: makeBuySummary(source: source, date: date, precision: precision)
                    )
                }
            }
        }
        return nil
    }

    private enum FieldKind { case model, version, color, notes, source, date }

    private static func buildFieldUpdate(matchedName: String, kind: FieldKind, value: String) -> UpdateIntent {
        var c = ItemChanges()
        var summary = ""
        switch kind {
        case .model:
            c.model = value
            summary = String(localized: "update.summary.model \(value)")
        case .version:
            c.version = value
            summary = String(localized: "update.summary.version \(value)")
        case .color:
            c.color = value
            summary = String(localized: "update.summary.color \(value)")
        case .notes:
            c.notes = value
            summary = String(localized: "update.summary.notes \(value)")
        case .source:
            c.purchaseSource = value
            summary = String(localized: "update.summary.source \(value)")
        case .date:
            let (parsed, precision, _) = extractPurchaseDate(value)
            c.purchaseDate = parsed
            c.purchaseDatePrecision = precision
            if let d = parsed, let label = formatPurchaseDate(d, precision: precision) {
                summary = String(localized: "update.summary.date \(label)")
            } else {
                summary = String(localized: "update.summary.dateUnparseable \(value)")
            }
        }
        return UpdateIntent(matchedName: matchedName, changes: c, summary: summary)
    }

    private static func makeBuySummary(source: String?, date: Date?, precision: String? = nil) -> String {
        var parts: [String] = []
        if let s = source { parts.append(String(localized: "update.summary.source \(s)")) }
        if let d = date, let label = formatPurchaseDate(d, precision: precision) {
            parts.append(String(localized: "update.summary.date \(label)"))
        }
        // 拼接走 ListFormatter:中文 "X、Y",英文 "X and Y" — locale-aware。
        return ListFormatter.localizedString(byJoining: parts)
    }

    /// "买的句式" 残留的连接词清空:是/在/于/从/买/的
    private static func stripBuyConnectives(_ s: String) -> String {
        var x = s
        for w in ["是", "在", "于", "从", "买", "的"] {
            x = x.replacingOccurrences(of: w, with: "")
        }
        return x.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 在 update-intent 已经确认句尾是"买的"的上下文里,
    /// 尽量从 rest 里挖出 (购买日期, 购买渠道)。
    /// 渠道不限于 knownPurchaseSources —— "X是Y买的"句式本身就明确了 Y 是渠道,Y 可以是任何内容。
    ///
    /// 处理顺序:
    ///   1. 抽日期(2025年5月8日 / 2025/5/8 …)
    ///   2. 剥末尾"买的/购买的/购入的"
    ///   3. 反复剥前缀连接词(是/在/是在/是从/购买于/购于/买于/从/于)
    ///   4. 剥末尾"的"
    ///   5. 剩下的就是渠道
    private static func parseUpdateBuyPhrase(_ rest: String) -> (Date?, String?, String?) {
        var s = rest
        let (date, precision, afterDate) = extractPurchaseDate(s)
        s = afterDate

        for tail in ["购买的", "购入的", "买的"] {
            if s.hasSuffix(tail) {
                s = String(s.dropLast(tail.count))
                break
            }
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // "是在" 比 "是" 长,先匹长的避免被吞错。
        let leadingConnectives = [
            "是在", "是从", "是于",
            "购买于", "购于", "买于",
            "在", "是", "从", "于",
        ]
        var prev = ""
        while s != prev {
            prev = s
            for c in leadingConnectives where s.hasPrefix(c) {
                s = String(s.dropFirst(c.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        if s.hasSuffix("的") {
            s = String(s.dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return (date, precision, s.isEmpty ? nil : s)
    }

    /// 一行可能写多条物品(用逗号/分号/和/然后...分隔)。返回切好的每一条解析结果。
    ///
    /// Phase 72:多 sibling 之间做**位置传染**(forward + backward fill)。
    /// 触发场景:"xx位置中有 1、2、3" 切出来后只有第 1 段有 location,2/3 段没有 ——
    /// 自然语言隐含"都在 xx 位置"。规则:
    ///   1. 先 forward fill —— 每个空 location 段继承"最近的、前面的非空 location"
    ///   2. 再 backward fill —— 仍空的(开头那几段)继承"第一个非空 location"
    /// 这样不依赖 AI 勾选,parser 层就把意图补齐。
    static func parseMultiple(_ raw: String) -> [Parsed] {
        let parsedList = splitMultipleEntries(raw)
            .map(parse)
            .filter { !$0.name.isEmpty }
        return propagateSiblingLocations(parsedList)
    }

    /// Phase 72:在同一次输入产生的多条 Parsed 间传染 locationPath。
    /// **只**动 locationPath,其它字段(name/model/color/...)各自独立。
    /// 如果列表里所有段都有 location,或所有段都没有,直接原样返回(没传染必要)。
    private static func propagateSiblingLocations(_ list: [Parsed]) -> [Parsed] {
        guard list.count >= 2 else { return list }
        // 找到所有"有 location 的"段。一个都没有就不动。
        let nonEmptyIndices = list.indices.filter { !list[$0].locationPath.isEmpty }
        guard !nonEmptyIndices.isEmpty else { return list }
        // 全都有就不动 —— 用户给每条都写了位置,respect 他们的意图。
        if nonEmptyIndices.count == list.count { return list }

        var result = list
        // Step 1:forward fill —— 空位继承"最近的前面的非空"
        var lastSeen: [String] = []
        for i in 0..<result.count {
            if result[i].locationPath.isEmpty {
                if !lastSeen.isEmpty {
                    result[i].locationPath = lastSeen
                }
            } else {
                lastSeen = result[i].locationPath
            }
        }
        // Step 2:backward fill —— 开头那几段(forward 没补到)继承"第一个非空"
        if result[0].locationPath.isEmpty,
           let firstNonEmpty = result.first(where: { !$0.locationPath.isEmpty })?.locationPath {
            for i in 0..<result.count where result[i].locationPath.isEmpty {
                result[i].locationPath = firstNonEmpty
            }
        }
        return result
    }

    // MARK: - 多条输入切分

    /// 硬分隔符:出现就切。
    /// 注:用 Unicode 转义写中文标点,避免编辑器把 U+FF0C 静默转成 U+002C。
    private static let hardMultiSeparators: [String] = [
        ",",                       // ASCII comma U+002C
        "\u{FF0C}",                // 中文全角逗号 ,
        ";",                       // ASCII semicolon U+003B
        "\u{FF1B}",                // 中文全角分号 ;
        "|",                       // ASCII pipe
        "\u{FF5C}",                // 中文全角竖线 ｜
        "\\", "\u{3001}",          // 反斜杠、中文顿号 、
        // 带空格的连词更明确,先匹配
        " 然后 ", " 以及 ", " 还有 ", " 接着 ", " 再加 ",
        // 不带空格的也切(这些词几乎不出现在物品名/位置名里)
        "然后", "以及", "还有", "接着",
    ]

    /// "过渡性副词":句中表示"接下来/现在/目前"的转折语,**不是多物品分隔**。
    /// 出现在逗号后会被替换成单个空格,这样多物品分隔就不会误伤。
    /// "X 是 2024 买的,现在在 Y" —— 同一件物品,不该被切两条。
    private static let transitionalPhrases: [String] = [
        "\u{FF0C}现在", "\u{FF0C}目前", "\u{FF0C}如今", "\u{FF0C}此刻", "\u{FF0C}此时", "\u{FF0C}眼下",
        ",现在", ",目前", ",如今",
        "\u{3002}现在", "\u{3002}目前",   // 句号 。
        ";现在", "\u{FF1B}现在",
    ]

    /// 软分隔符:可能是连词,也可能是物品名/位置的一部分。
    /// 只有两侧都有"在/位于/:" 这种 name-location 分隔符时才切,
    /// 避免把"充电宝和眼镜在书房"切成两条独立物品。
    private static let softMultiSeparators: [String] = ["和", "跟", "与"]

    static func splitMultipleEntries(_ raw: String) -> [String] {
        // 1. 先把"过渡性副词"换成空格 —— 这是同一物品的延续描述,不切。
        //    "...买的,现在在卧室..." → "...买的  在卧室..." → 不会被逗号切走。
        var s = raw
        for phrase in transitionalPhrases {
            s = s.replacingOccurrences(of: phrase, with: " ")
        }

        // 2. 硬分隔切
        var pieces: [String] = [s]
        for sep in hardMultiSeparators {
            pieces = pieces.flatMap { $0.components(separatedBy: sep) }
        }
        pieces = pieces.flatMap(softSplitIfStructured)
        return pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func softSplitIfStructured(_ piece: String) -> [String] {
        for sep in softMultiSeparators {
            guard let r = piece.range(of: sep) else { continue }
            let left  = String(piece[..<r.lowerBound])
            let right = String(piece[r.upperBound...])
            if hasNameLocSep(left) && hasNameLocSep(right) {
                return softSplitIfStructured(left) + softSplitIfStructured(right)
            }
        }
        return [piece]
    }

    private static func hasNameLocSep(_ s: String) -> Bool {
        nameLocationSeparators.contains { s.contains($0) }
    }

    static func parse(_ raw: String) -> Parsed {
        var rest = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return Parsed(name: "", locationPath: []) }

        // 0. 剥句首语气连词("但是 / 可是 / 但 / 嗯 / 对了" 等),防止它们粘进 name。
        //    例:"但荣耀手机在桌子" → 剥掉 "但" → "荣耀手机在桌子"
        rest = stripLeadingFiller(rest)
        guard !rest.isEmpty else { return Parsed(name: "", locationPath: []) }

        // 1. 抽日期(支持模糊精度:年/月/日)
        let (purchaseDate, datePrecision, afterDate) = extractPurchaseDate(rest)
        rest = afterDate

        // 2. 抽购买渠道("购买于京东的" / "京东买的"…)
        let (purchaseSource, afterSource) = extractPurchaseSource(rest)
        rest = afterSource

        // 3. 把抽渠道后留下的连接词碎片("购买"/"买的"/"于"…)收一下
        rest = cleanupPurchasePhraseFragments(rest)

        // 4. 走原 parser 切名字 + 位置 —— 按优先级试:
        //    a. "<物品> 在 / 位于 <位置>"(name-first,主流)
        //    b. "<位置> 有 / 上的 / 里的 <物品>"(location-first,口语化)Phase 64
        //    c. Phase 92:英文模式 "X is in Y" / "X at Y" / "Y has X"
        //    d. 都没匹中 → 全句当 name(老行为)
        let basicName: String
        let path: [String]
        if let (n, locRaw) = splitNameAndLocation(rest) {
            basicName = n
            path = parseLocationPath(locRaw)
        } else if let (locRaw, n) = splitLocationAndName(rest) {
            // Phase 64:反向句式。loc 必须是"像位置"才生效(避免误切普通陈述)。
            basicName = n
            path = parseLocationPath(locRaw)
        } else if let (n, locRaw) = splitEnglishNameAndLocation(rest) {
            // Phase 92:英文句式。"X is in Y" / "X at Y" / "X on Y"
            basicName = n
            path = parseEnglishLocationPath(locRaw)
        } else if let (locRaw, n) = splitEnglishLocationAndName(rest) {
            // Phase 92:英文反向。"Y has X" / "Y contains X"
            basicName = n
            path = parseEnglishLocationPath(locRaw)
        } else {
            // 没分隔符也得剥末尾连接词,防止 "华为手表是" 整体落库。
            basicName = stripTrailingConnectives(rest)
            path = []
        }

        // 顺序很关键(Phase 15):Color → Model → Version。
        //   - Color 必须先于 Model:否则 "iPhone 7 Plus玫瑰金" 会被 model 先吃走前半,
        //     剩 "玫瑰金" 当物品名(主次颠倒,Phase 15 修的就是这个 bug)。
        //   - Model 必须先于 Version:否则 "华为手表 GT6 46MM" 会被 version 把 "46MM"
        //     抽走,model 只剩 "GT6";应作为整段表盘型号 "GT6 46MM" 留在 model。

        // 5. 抽颜色("华为手表 灰色" → name=华为手表, color=灰色)
        let (afterColor, color) = extractColor(from: basicName)

        // 6. 抽型号("中兴U60Pro" → name=中兴, model=U60Pro)
        let (afterModel, model) = extractModel(from: afterColor)

        // 7. 抽容量/规格("512g 苹果手机" → name=苹果手机, version=512g)
        let (cleanedName, version) = extractVersion(from: afterModel)

        return Parsed(name: cleanedName, locationPath: path,
                      purchaseDate: purchaseDate,
                      purchaseDatePrecision: datePrecision,
                      purchaseSource: purchaseSource,
                      model: model,
                      color: color,
                      version: version)
    }

    // MARK: - 日期抽取

    /// 返回 (date, precision, remainder)。
    /// precision 可能是 "year" / "month" / "day"。匹不上返回 (nil, nil, raw)。
    /// 模糊精度:月日缺省补 1,展示时按 precision 控制(老数据 nil 当 day 处理)。
    private static func extractPurchaseDate(_ raw: String) -> (Date?, String?, String) {
        // 从最具体到最宽泛尝试;首个命中即返回。
        struct Spec {
            let pattern: String
            let precision: String
            let groupCount: Int  // Y=1, Y+M=2, Y+M+D=3
        }
        let specs: [Spec] = [
            Spec(pattern: #"(\d{4})年(\d{1,2})月(\d{1,2})日?"#,        precision: "day",   groupCount: 3),
            Spec(pattern: #"(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})"#, precision: "day",   groupCount: 3),
            Spec(pattern: #"(\d{4})年(\d{1,2})月"#,                    precision: "month", groupCount: 2),
            Spec(pattern: #"(\d{4})[/\-.](\d{1,2})(?![/\-.]?\d)"#,    precision: "month", groupCount: 2),
            Spec(pattern: #"(\d{4})年"#,                                precision: "year",  groupCount: 1),
        ]

        for spec in specs {
            guard let regex = try? NSRegularExpression(pattern: spec.pattern) else { continue }
            let nsRange = NSRange(raw.startIndex..., in: raw)
            guard let match = regex.firstMatch(in: raw, range: nsRange),
                  match.numberOfRanges >= spec.groupCount + 1 else { continue }
            let ns = raw as NSString
            guard let y = Int(ns.substring(with: match.range(at: 1))) else { continue }
            let m: Int = spec.groupCount >= 2 ? (Int(ns.substring(with: match.range(at: 2))) ?? 1) : 1
            let d: Int = spec.groupCount >= 3 ? (Int(ns.substring(with: match.range(at: 3))) ?? 1) : 1
            var comps = DateComponents()
            comps.year = y; comps.month = m; comps.day = d
            guard let date = Calendar.current.date(from: comps) else { continue }
            var stripped = raw
            if let r = Range(match.range, in: stripped) {
                stripped.removeSubrange(r)
            }
            return (date, spec.precision, stripped)
        }
        return (nil, nil, raw)
    }

    // MARK: - 渠道抽取

    private static func extractPurchaseSource(_ raw: String) -> (String?, String) {
        // 列表已按"较长在前"排过。每个 source 再按"上下文最完整"的模式优先匹配。
        // 关键:把 source 前可能挂着的连接词("是在"/"是"/"在") 也吃掉,
        // 避免抽完之后残留 "是在" 干扰后面 splitNameAndLocation。
        for source in knownPurchaseSources {
            let esc = NSRegularExpression.escapedPattern(for: source)
            // 顺序按"上下文最完整 → 最简单"排,最长的先匹配。
            let patterns = [
                #"是在\#(esc)买的"#,        // 是在山姆买的(关键)
                #"是从\#(esc)买的"#,
                #"是\#(esc)买的"#,           // 是山姆买的
                #"购买于\#(esc)的"#,
                #"购买于\#(esc)"#,
                #"购于\#(esc)的"#,
                #"购于\#(esc)"#,
                #"买于\#(esc)的"#,
                #"买于\#(esc)"#,
                #"在\#(esc)买的"#,           // 在山姆买的
                #"从\#(esc)买的"#,
                #"\#(esc)购买的"#,
                #"\#(esc)买的"#,             // 兜底:无前缀的 山姆买的
            ]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let nsRange = NSRange(raw.startIndex..., in: raw)
                guard let match = regex.firstMatch(in: raw, range: nsRange),
                      let r = Range(match.range, in: raw) else { continue }
                var stripped = raw
                stripped.removeSubrange(r)
                return (source, stripped)
            }
        }
        return (nil, raw)
    }

    /// 在 source 抽取之后,可能还残留"购买"/"于"/"买的" 之类的连接词。一并扫一遍删干净。
    private static func cleanupPurchasePhraseFragments(_ raw: String) -> String {
        var s = raw
        let fragments = ["购买的", "购入的", "买来的", "购买", "购入", "买的"]
        for f in fragments {
            s = s.replacingOccurrences(of: f, with: " ")
        }
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 型号抽取

    /// Phase 16:接口/标准类 Latin 词典。
    /// "Type-C" / "USB" / "CFA" / "HDMI" 这种是描述类别 / 接口,不是 product model。
    /// 用户输入 "贝尔金Type-C转以太网口" 时,Type-C 应该留在物品名,不应被当 model 抽走。
    /// 大小写不敏感比较 —— 这里全部 lowercased 存。
    private static let nonProductLatinTokens: Set<String> = Set([
        // 接口标准
        "type-c", "type c", "typec", "usb-c", "usb-a", "usb-b",
        "usb", "usb2", "usb3", "usb 2", "usb 3", "usb-2", "usb-3",
        "hdmi", "dp", "displayport", "vga", "dvi",
        "thunderbolt", "tb3", "tb4",
        "lightning",
        "rj45", "rj11",
        // 协议
        "pd", "pps", "qc", "qc2", "qc3", "qc4",
        "wi-fi", "wifi", "wlan", "bt", "bluetooth", "ble",
        "5g", "4g", "lte", "nfc",
        "ac", "dc",
        // 存储类型
        "pcie", "sata", "nvme", "m.2",
        "sd", "microsd", "tf", "cf", "cfa", "cfexpress", "xqd", "mmc",
        // 视频规格
        "hdr", "sdr", "hdr10", "hdr400", "hdr600", "hdr1000",
        "4k", "8k", "2k", "1080p", "720p", "60hz", "120hz", "144hz", "240hz",
        // 充电规格
        "usb-pd", "usb pd", "gan",
    ])

    /// Phase 16:配件 / 衍生品 提示词。
    /// 物品名里如果有这些词(表带 / 保护壳 / 线缆 / 转接头 …),
    /// 那 Latin 前缀更可能是品牌/产品线,**而不是型号** —— 整个串应当留在物品名里。
    /// 例:"Apple Watch备用表带" 整体是物品名,Apple Watch 不抽出来当 model。
    private static let accessoryHints: [String] = [
        "表带", "表盘",
        "保护壳", "保护套", "保护膜", "保护贴", "钢化膜", "贴膜",
        "手机壳", "壳子", "外壳",
        "充电线", "数据线", "信号线", "线缆", "电源线",
        "转接头", "转接器", "转换头", "转换器", "适配器",
        "充电器", "充电头",
        "收纳袋", "收纳盒", "收纳包",
        "备用", "替换", "备件",
        "套装", "套件", "配件",
        "卡套", "卡包",
    ]

    /// 看起来"像一个真实型号":3-14 字符,letter+digit 混合,内部无空格。
    /// 典型例子:KM003C / U60Pro / GT6 / S23U / AC2300。
    /// 用来在多个 Latin 候选里挑出真正的 model token —— "Power-Z USB" 是品牌+类别,
    /// "KM003C" 才是型号。
    private static func isLikelyModel(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3, trimmed.count <= 14 else { return false }
        let hasLetter = trimmed.contains { $0.isLetter }
        let hasDigit  = trimmed.contains { $0.isNumber }
        guard hasLetter && hasDigit else { return false }
        // 内部空格 / 多 token 不算 model —— 真型号通常是 single token
        if trimmed.contains(" ") { return false }
        return true
    }

    private static func isNonProductLatin(_ s: String) -> Bool {
        nonProductLatinTokens.contains(s.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// 从 name 里切出型号。Phase 16 重写:
    ///   1. 先列出所有 Latin 候选(`[A-Za-z][A-Za-z0-9\- ]*[A-Za-z0-9]`)。
    ///   2. 优先挑"看起来像型号"(letter+digit、3-14 字符、无空格)的那一个 —— 例:KM003C / U60Pro。
    ///   3. 没有 likely-model 候选时:
    ///      - 若最长候选是 spec/标准词(Type-C / USB / CFA …)→ 不抽 model,返回原名。
    ///      - 若剥掉最长后剩下的 CJK 含配件提示词(表带 / 保护壳 / 线缆 …)→ 也不抽,
    ///        整个 Latin 部分是品牌+产品线名,留在 name 里。
    ///      - 否则用最长候选当 model(legacy:iPhone 7 Plus + 中兴U60Pro 等)。
    ///   4. 抽完得有 CJK 剩余且至少 2 字符,否则放弃。
    ///
    /// 测试:
    ///   "中兴U60Pro"               → ("中兴", "U60Pro")           likely-model 命中
    ///   "Power-Z USB线缆测试仪 KM003C" → ("Power-Z USB线缆测试仪", "KM003C")  likely-model 优先于最长
    ///   "iPhone 7 Plus"            → ("iPhone 7 Plus", nil)        无 CJK 剩,不抽
    ///   "Apple Watch备用表带"      → ("Apple Watch备用表带", nil) 配件词命中
    ///   "贝尔金Type-C转以太网口"   → 原样,Type-C 是 spec 词
    ///   "索尼CFA卡读卡器"          → 原样,CFA 是 spec 词
    ///   "华为手表 GT6 46MM灰色"    → ("华为手表", "GT6 46MM")     legacy 路径
    private static func extractModel(from name: String) -> (String, String?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let regex = try? NSRegularExpression(pattern: #"[A-Za-z][A-Za-z0-9\- ]*[A-Za-z0-9]"#)
        else { return (trimmed, nil) }

        let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = regex.matches(in: trimmed, range: nsRange)
        guard !matches.isEmpty else { return (trimmed, nil) }

        let ns = trimmed as NSString
        let candidates: [(range: NSRange, text: String)] = matches.map {
            ($0.range, ns.substring(with: $0.range).trimmingCharacters(in: .whitespaces))
        }

        // 1. likely-model 优先:letter+digit 混合,无内部空格,3-14 字符。
        //    扫描顺序按原串里的出现顺序(matches 已是);第一个命中的就是。
        if let liked = candidates.first(where: { isLikelyModel($0.text) }) {
            return pullModel(liked, from: trimmed)
        }

        // 2. 没有 likely-model 候选 —— 退到"最长 Latin"启发式。
        guard let longest = candidates.max(by: { $0.text.count < $1.text.count }) else {
            return (trimmed, nil)
        }

        // 2a. 最长候选若是 spec/标准词 → 不抽。
        if isNonProductLatin(longest.text) {
            return (trimmed, nil)
        }

        // 2b. 试拉一下,看剩下的 CJK 是不是包含配件提示词 → 是的话也不抽。
        let (tentativeName, tentativeModel) = pullModel(longest, from: trimmed)
        if tentativeModel != nil,
           accessoryHints.contains(where: { tentativeName.contains($0) }) {
            return (trimmed, nil)
        }

        return (tentativeName, tentativeModel)
    }

    /// 从 src 里把 candidate 那段移除,返回 (剩下的 name, 抽出的 model)。
    /// 校验:抽出至少 2 字符 / 剩下含 CJK 且 ≥ 2 字符 / 否则放弃。
    private static func pullModel(_ candidate: (range: NSRange, text: String), from src: String) -> (String, String?) {
        let model = candidate.text
        guard model.count >= 2 else { return (src, nil) }
        var remaining = src
        guard let r = Range(candidate.range, in: remaining) else { return (src, nil) }
        remaining.removeSubrange(r)
        remaining = remaining
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCJK = remaining.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        guard hasCJK, remaining.count >= 2 else { return (src, nil) }
        return (remaining, model)
    }

    // MARK: - 容量 / 规格抽取

    /// 从 name 任意位置抽容量 / 尺寸 / 重量 token,放到 version 字段。
    /// 例:"512g 苹果手机" → ("苹果手机", "512g")
    ///     "iPad Pro 11寸" → ("iPad Pro", "11寸")
    ///     "三星硬盘 1TB"  → ("三星硬盘", "1TB")
    /// 跳过日期格式("2026年" 不会被误抽 —— 单位列表里没有"年")。
    /// 抽完得有剩余 name,否则放弃。
    private static func extractVersion(from name: String) -> (String, String?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (trimmed, nil) }
        // 数字(可带小数) + 容量/尺寸/重量单位。注意 "年" 不在列表里,避免误抽日期。
        let pattern = #"\b\d+(?:\.\d+)?(?:GB|TB|MB|KB|g|kg|斤|ml|l|L|寸|英寸|cm|mm|英尺|盎司|oz)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return (trimmed, nil) }
        let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: nsRange),
              let r = Range(match.range, in: trimmed) else {
            return (trimmed, nil)
        }
        let version = String(trimmed[r]).trimmingCharacters(in: .whitespaces)
        var remaining = trimmed
        remaining.removeSubrange(r)
        remaining = remaining
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 抽完得有剩余物品名,否则保留原句不动
        guard !remaining.isEmpty else { return (trimmed, nil) }
        return (remaining, version)
    }

    // MARK: - 颜色抽取

    /// 从 name 任意位置抽出最长的已知颜色词。
    ///   "华为手表 灰色" → ("华为手表", "灰色")
    ///   "黑色雨伞"      → ("雨伞", "黑色")
    ///   "灰色"          → ("灰色", nil)  ← 抽完会空,保留原 name
    /// 必须满足:抽完后名字至少剩 2 个字(或剩 1 个汉字)。否则放弃,免得把"灰色记号笔"切成"记号"。
    private static func extractColor(from name: String) -> (String, String?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (trimmed, nil) }

        // 按长度降序,确保"深空灰色"先于"灰色"匹配
        let sorted = knownColors.sorted { $0.count > $1.count }
        for color in sorted {
            guard let range = trimmed.range(of: color) else { continue }
            var remaining = trimmed
            remaining.removeSubrange(range)
            remaining = remaining
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // 抽完得有剩余物品名,否则保留原句不动
            guard !remaining.isEmpty, remaining.count >= 1 else { continue }
            return (remaining, color)
        }
        return (trimmed, nil)
    }

    // MARK: - 步骤

    /// 找第一个匹配的"名字/位置"分隔符,返回 (name, locationRaw)。
    /// 若找不到 / 切完名字为空,返回 nil(交给上层 fallback)。
    ///
    /// 切完后还会剥 name 末尾的"动词式连接词"。
    /// 这是为了处理"X 是在 Y" / "X 是位于 Y" / "X 放在 Y" 这类
    /// 无法靠单一分隔符切干净的句式 —— "在" 单独匹时只能切走 "在",
    /// "是" 会粘在 name 末尾形成 "X是"。
    private static func splitNameAndLocation(_ s: String) -> (String, String)? {
        for sep in nameLocationSeparators {
            guard let range = s.range(of: sep) else { continue }
            var name = s[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let rest = s[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            name = stripTrailingConnectives(name)
            // 名字和位置都得非空才算成功;否则继续尝试下一个分隔符。
            if !name.isEmpty && !rest.isEmpty {
                return (name, rest)
            }
        }
        return nil
    }

    /// Phase 64:**反向**句式 —— 位置在前,物品在后。
    /// 例:"书房桌上有 AITO 专项游戏采集底座" → loc="书房桌上",name="AITO 专项游戏采集底座"
    /// 例:"床头柜上的钥匙" → loc="床头柜",name="钥匙"
    ///
    /// 防误切策略:左半部分必须**像位置** —— 包含 `knownPlaces` 字典里的任一场所词。
    /// 否则 "我有 iphone" 这种口语会被错误地把"我"切走当位置。
    ///
    /// 返回 (loc 原文, name 原文);左/右任一为空 → 该分隔符跳过继续试下一个。
    private static func splitLocationAndName(_ s: String) -> (String, String)? {
        for sep in reverseLocationNameSeparators {
            guard let range = s.range(of: sep) else { continue }
            let loc = s[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let name = s[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !loc.isEmpty, !name.isEmpty else { continue }
            // 防误切:loc 得含至少一个已知场所词
            guard locationLooksReal(loc) else { continue }
            return (loc, name)
        }
        return nil
    }

    /// Phase 64:反向句式的分隔符。**长的先试**(防止 "里的" 被 "有" 抢先匹中)。
    /// 这些组合都表示"位置在前,物品在后"。
    private static let reverseLocationNameSeparators: [String] = [
        // 多字组合(更准确,优先匹)
        "里面有", "里面的", "上面有", "上面的", "下面有", "下面的",
        "里有", "中有", "上有", "下有",
        "里的", "中的", "上的", "下的",
        // 单字兜底("X 有 Y" 是最口语的 location-first 句式)
        "有",
    ]

    /// Phase 64:启发式 — "loc 候选"看起来是不是真的像位置?
    /// 标准:contains 任一 `knownPlaces` 字典词,或末尾是 trailingNoise 词("桌上"、"柜里")。
    /// 后者捕获用户自创的位置名(虽然没在字典里,但"X 上"形式很可能是位置)。
    private static func locationLooksReal(_ s: String) -> Bool {
        for place in knownPlaces where s.contains(place) {
            return true
        }
        // "桌上" / "柜里" / "盒中" 这种由 trailingNoise 后缀拼成的小段也算位置
        for noise in trailingNoise where s.hasSuffix(noise) && s.count >= noise.count + 1 {
            return true
        }
        return false
    }

    /// 句首语气连词 —— 转折 / 口语虚词。按长度降序匹("但是" 先于 "但")。
    /// 反复剥直到没有剥的为止("嗯但是充电宝..." → "嗯" → "但是" → "充电宝...")。
    private static let leadingFillerWords: [String] = [
        "但是", "可是", "然而", "不过", "对了",
        "但", "可",                                  // 单字版
        "嗯嗯", "嗯", "哦", "啊", "诶",              // 语气助词
    ]

    /// 反复剥句首语气词,直到无法再剥。
    /// "但荣耀手机在桌子" → "荣耀手机在桌子"
    /// "嗯但是充电宝..." → "充电宝..."
    /// 防退化:剥完得有剩余;若剥光,放弃这次剥(返回上一态)。
    private static func stripLeadingFiller(_ s: String) -> String {
        var result = s
        let sorted = leadingFillerWords.sorted { $0.count > $1.count }
        var prev = ""
        while result != prev {
            prev = result
            for word in sorted where result.hasPrefix(word) {
                let after = String(result.dropFirst(word.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // 剥完不能为空 —— 否则用户输入就是 "但是" 这种 single token,保留原样
                if !after.isEmpty {
                    result = after
                }
                break
            }
        }
        return result
    }

    /// name 末尾常见的连接词("是"/"为"/"放"/"搁"),最多剥 1 个,且剥完得至少剩 2 字。
    /// "华为手表是" → "华为手表" ✓
    /// "锅是"      → "锅是"(剩 1 字,不剥)
    private static let nameTrailingConnectives = ["是", "为", "放", "搁", "现"]
    private static func stripTrailingConnectives(_ name: String) -> String {
        for c in nameTrailingConnectives where name.hasSuffix(c) && name.count >= c.count + 2 {
            return String(name.dropLast(c.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return name
    }

    /// 把位置串切成层级数组,清理空白和末尾噪声词。
    private static func parseLocationPath(_ raw: String) -> [String] {
        var pieces: [String] = [raw]
        for psep in pathSeparators {
            pieces = pieces.flatMap { $0.components(separatedBy: psep) }
        }
        return pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .flatMap(splitByKnownPlace)         // 再从无分隔符的整块里抽场所前缀
            .map(stripTrailingNoise)
            .filter { !$0.isEmpty }
    }

    /// 递归把 piece 里最长的"已知场所"作为前缀切出来。
    /// "书房白色桌子" → ["书房", "白色桌子"]
    /// "客厅沙发后面" → ["客厅", "沙发", "后面"]
    /// 整段就是一个场所词("卧室"、"床头柜")→ 不切,原样返回。
    private static func splitByKnownPlace(_ piece: String) -> [String] {
        // 1. 整 piece 已经命中字典 → 直接返回,避免把 "床头柜" 错切成 "床" + "头柜"。
        if knownPlaces.contains(piece) { return [piece] }
        // 2. 否则按长度从长到短匹配,优先认更长的场所("主卧" 优于 "卧")。
        let sorted = knownPlaces.sorted { $0.count > $1.count }
        for place in sorted where piece.hasPrefix(place) && piece.count > place.count {
            let rest = String(piece.dropFirst(place.count))
            return [place] + splitByKnownPlace(rest)
        }
        return [piece]
    }

    private static func stripTrailingNoise(_ piece: String) -> String {
        // piece 本身就是噪声词(切到最后只剩 "里"/"上")→ 返回空,让 filter 去掉。
        if trailingNoise.contains(piece) { return "" }
        for suffix in trailingNoise {
            // 关键约束:剥完得至少剩 2 个字。
            // 避免 "地上" → "地" / "桌上" → "桌" / "包里" → "包" 这种把意思剥没了的退化。
            // "餐桌上"(3) - "上"(1) = 2 ✓ 可以剥
            // "地上"(2) - "上"(1) = 1 ✗ 保留
            if piece.hasSuffix(suffix) && piece.count >= suffix.count + 2 {
                return String(piece.dropLast(suffix.count))
            }
        }
        return piece
    }

    // MARK: - 英文 parser(Phase 92)
    //
    // 中文 splitter 没匹中时的 fallback。只解 name + location;字段抽取(model/color/version/
    // source/date)继续靠中文词典(覆盖不到的英文用户应该配 AI key 走 LLM 路径)。

    /// 英文 name-first 分隔符:"X is in Y" / "X at Y" / "X on Y"。
    /// 顺序:更长 / 更明确的优先匹配。前后必须是 word boundary,避免 "Phoenix" 误中 "in"。
    private static let englishNameLocationSeparators: [String] = [
        " is located in ", " is located at ", " is located on ",
        " is in ", " is at ", " is on ", " is inside ", " is under ",
        " in the ", " at the ", " on the ", " inside the ", " under the ",
        " — in ", " — at ", " — on ",          // em dash 英文用户也常用
        " - in ", " - at ", " - on ",
        ": ",                                   // "Passport: safe box"
        " in ", " at ", " on ", " inside ", " under ",
    ]

    /// 英文 location-first 分隔符:"Y has X" / "Y contains X" / "In Y, X"。
    /// 同样长的优先。
    private static let englishLocationNameSeparators: [String] = [
        " contains ", " has a ", " has an ", " holds ",
        " has ",     // "Drawer has passport"
    ]

    /// 检测字符串"主要是英文"—— 有英文字母且没有中文字符。
    /// 主要用作 fast-fail 优化(整段中文跳过英文 split)+ 防止"中英混写"被强切。
    private static func looksEnglish(_ s: String) -> Bool {
        var hasLatin = false
        for ch in s.unicodeScalars {
            // CJK Unified Ideographs 基本块 + 扩展 A 简单覆盖
            if (0x4E00...0x9FFF).contains(ch.value) || (0x3400...0x4DBF).contains(ch.value) {
                return false
            }
            if (0x41...0x5A).contains(ch.value) || (0x61...0x7A).contains(ch.value) {
                hasLatin = true
            }
        }
        return hasLatin
    }

    /// "iPhone is in the drawer" → ("iPhone", "the drawer")。case-insensitive。
    /// 不命中(或非英文)返回 nil,让外层走 fallback。
    private static func splitEnglishNameAndLocation(_ s: String) -> (String, String)? {
        guard looksEnglish(s) else { return nil }
        let lower = s.lowercased()
        for sep in englishNameLocationSeparators {
            guard let r = lower.range(of: sep) else { continue }
            // 用原串切回去,保留大小写
            let nameStart = s.startIndex
            let lowerNameRange = lower.startIndex..<r.lowerBound
            let nameLen = lower.distance(from: lowerNameRange.lowerBound, to: lowerNameRange.upperBound)
            let lowerLocRange = r.upperBound..<lower.endIndex
            let locLen = lower.distance(from: lowerLocRange.lowerBound, to: lowerLocRange.upperBound)
            let nameEnd = s.index(nameStart, offsetBy: nameLen)
            let locStart = s.index(nameEnd, offsetBy: lower.distance(from: r.lowerBound, to: r.upperBound))
            let locEnd = s.index(locStart, offsetBy: locLen)
            let name = String(s[nameStart..<nameEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            let loc  = String(s[locStart..<locEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty && !loc.isEmpty {
                return (name, loc)
            }
        }
        return nil
    }

    /// "drawer has the passport" → ("drawer", "the passport")。
    /// 区别于 name-first 的是 location 在前 —— 不命中返回 nil。
    private static func splitEnglishLocationAndName(_ s: String) -> (String, String)? {
        guard looksEnglish(s) else { return nil }
        let lower = s.lowercased()
        for sep in englishLocationNameSeparators {
            guard let r = lower.range(of: sep) else { continue }
            let nameStart = s.startIndex
            let lowerLocRange = lower.startIndex..<r.lowerBound
            let locLen = lower.distance(from: lowerLocRange.lowerBound, to: lowerLocRange.upperBound)
            let lowerNameRange = r.upperBound..<lower.endIndex
            let nameLen = lower.distance(from: lowerNameRange.lowerBound, to: lowerNameRange.upperBound)
            let locEnd = s.index(nameStart, offsetBy: locLen)
            let nameStartIdx = s.index(locEnd, offsetBy: lower.distance(from: r.lowerBound, to: r.upperBound))
            let nameEndIdx = s.index(nameStartIdx, offsetBy: nameLen)
            let loc = String(s[nameStart..<locEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            let name = String(s[nameStartIdx..<nameEndIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty && !loc.isEmpty {
                return (loc, name)
            }
        }
        return nil
    }

    /// 英文位置串拆段。识别 ">" / "/" / "->" / "," 等显式分隔,也剥常见冠词。
    /// "the kitchen > the second drawer" → ["kitchen", "second drawer"]
    /// "kitchen, second drawer" → ["kitchen", "second drawer"]
    /// 没显式分隔符就一段返回。
    private static func parseEnglishLocationPath(_ raw: String) -> [String] {
        var pieces: [String] = [raw]
        // 英文常见分隔符 + 中文的也兼容(用户可能 ">" 习惯一致)
        let seps = [">", "/", "->", "→", "》", ","]
        for sep in seps {
            pieces = pieces.flatMap { $0.components(separatedBy: sep) }
        }
        return pieces
            .map { stripEnglishArticles($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
    }

    /// 剥英文冠词:"the kitchen" → "kitchen";"a bedroom" → "bedroom";"an attic" → "attic"。
    /// 只剥开头,case-insensitive。冠词后必须有空格 + 至少 2 个字符。
    private static func stripEnglishArticles(_ s: String) -> String {
        let lower = s.lowercased()
        for art in ["the ", "a ", "an "] {
            if lower.hasPrefix(art) && s.count > art.count + 1 {
                return String(s.dropFirst(art.count))
            }
        }
        return s
    }
}
