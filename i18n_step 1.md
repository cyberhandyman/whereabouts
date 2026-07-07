Step 1 审完，确认以下决策，进 Step 2：

## 决策

1. **key 命名规则**：采用你提的 `<feature>.<component>.<element>` dot.notation，不改。

2. **TBD-1 ~ TBD-5（placeholder / 示例）**：按以下英文：
   - input.textField.placeholder: "AirPods in the bedroom drawer"
   - empty.list.example1: "• AirPods in the bedroom drawer"
   - empty.list.example2: "• Passport on the bookshelf"
   - empty.list.example3: "• Keys → entryway hook"
   - detail.used.location.placeholder: "New location: kitchen cabinet, dining table, bedroom drawer…"

3. **TBD-6 ~ TBD-10（口语长句）**：按以下英文：
   - detail.used.title: "Looking for this?"
   - detail.used.description: "If you just used it, let me know where it ended up:"
   - dup.alert.message.noLocation: `"%@" is already at %@. You didn't say where it is now — want to add %@ to it, or create a new one?`
   - dup.alert.message.withLocation: `"%@" is already at %@. You're now saying "%@" is at %@ — is this the same item?`
   - update.alert.message: `Update "%@" with %@?`

4. **InputParser 英文支持**：现阶段**不**写英文 parser。当前 InputParser 保持中文专用，英文用户输入若 parser 抽不出，整句进 name 字段即可。在 InputParser 主入口和 ContentView 的调用点各加一行 `// TODO: i18n - English parsing via LLM (planned post-Phase 7)` 注释。

5. **预留的 key 命名空间**：在 String Catalog 里建好这些命名空间分组（即使现在没字符串）：
   - `error.*` — 用于未来 Phase 5 iCloud / 照片等错误文案
   - `menu.*` — 用于 Phase 6 macOS 菜单栏
   
6. **Accessibility**：本次不做 VoiceOver labels 迁移，但在 Step 6 的 README 里加一条规范——"新增交互式 View 必须加 `.accessibilityLabel()`，文本走 String Catalog"。

## 现在执行

进 Step 2：创建 String Catalog + 配置项目。完成后停下来给我看 diff。