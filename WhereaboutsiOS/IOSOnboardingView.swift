import SwiftUI

// Phase 115:首次启动引导 —— 全屏分页(TabView page 风格),
// 每页一个大渐变图标 + 标题 + 三行"手势→结果"式要点。
// 最后一页给「配置 AI(可选)」和「开始使用」。
// @AppStorage("onboardingShown") 只出一次;设置 → 关于 里可重看。

struct IOSOnboardingView: View {
    /// 完成回调(点"开始使用"或右上角跳过)。
    var done: () -> Void

    @State private var page = 0

    var body: some View {
        ZStack {
            IOSTheme.pageBackground
            VStack(spacing: 0) {
                // 顶部:跳过
                HStack {
                    Spacer()
                    Button("onboarding.skip") { done() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 20)
                        .padding(.top, 8)
                }
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    recordPage.tag(1)
                    gesturesPage.tag(2)
                    detailPage.tag(3)
                    aiPage.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                // 底部主按钮:非末页 = 继续;末页 = 开始使用
                Button {
                    if page < 4 {
                        withAnimation(.snappy) { page += 1 }
                    } else {
                        Haptics.success()
                        done()
                    }
                } label: {
                    Text(page < 4 ? "onboarding.next" : "onboarding.start")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(IOSTheme.gradient,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }
        }
    }

    // MARK: - 五页

    private var welcomePage: some View {
        pageScaffold(
            icon: "shippingbox.fill", tint: IOSTheme.accent,
            titleKey: "onboarding.welcome.title",
            subtitleKey: "onboarding.welcome.subtitle"
        ) {
            bullet("quote.bubble.fill", .blue, "onboarding.welcome.point1")
            bullet("square.stack.3d.up.fill", .indigo, "onboarding.welcome.point2")
            bullet("lock.shield.fill", .green, "onboarding.welcome.point3")
        }
    }

    private var recordPage: some View {
        pageScaffold(
            icon: "square.and.pencil", tint: .blue,
            titleKey: "onboarding.record.title",
            subtitleKey: "onboarding.record.subtitle"
        ) {
            bullet("text.cursor", .blue, "onboarding.record.point1")
            bullet("list.bullet", .cyan, "onboarding.record.point2")
            bullet("wand.and.stars", .purple, "onboarding.record.point3")
        }
    }

    private var gesturesPage: some View {
        pageScaffold(
            icon: "hand.draw.fill", tint: .orange,
            titleKey: "onboarding.gestures.title",
            subtitleKey: "onboarding.gestures.subtitle"
        ) {
            bullet("arrow.right.circle.fill", .orange, "onboarding.gestures.point1")
            bullet("arrow.left.circle.fill", .red, "onboarding.gestures.point2")
            bullet("hand.tap.fill", .indigo, "onboarding.gestures.point3")
        }
    }

    private var detailPage: some View {
        pageScaffold(
            icon: "clock.arrow.circlepath", tint: .mint,
            titleKey: "onboarding.detail.title",
            subtitleKey: "onboarding.detail.subtitle"
        ) {
            bullet("mappin.and.ellipse", .mint, "onboarding.detail.point1")
            bullet("person.fill.checkmark", .purple, "onboarding.detail.point2")
            bullet("archivebox.fill", .gray, "onboarding.detail.point3")
        }
    }

    private var aiPage: some View {
        pageScaffold(
            icon: "sparkles", tint: .purple,
            titleKey: "onboarding.ai.title",
            subtitleKey: "onboarding.ai.subtitle"
        ) {
            bullet("key.fill", .purple, "onboarding.ai.point1")
            bullet("yensign.circle.fill", .orange, "onboarding.ai.point2")
            bullet("book.fill", .blue, "onboarding.ai.point3")
        }
    }

    // MARK: - 骨架

    /// 单页骨架:大图标 + 标题 + 副标题 + 要点卡。
    @ViewBuilder
    private func pageScaffold<Points: View>(
        icon: String, tint: Color,
        titleKey: LocalizedStringKey, subtitleKey: LocalizedStringKey,
        @ViewBuilder points: () -> Points
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            GradientIconTile(
                systemName: icon, size: 92, cornerRadius: 24,
                gradient: LinearGradient(colors: [tint, tint.opacity(0.55)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .shadow(color: tint.opacity(0.32), radius: 18, x: 0, y: 8)
            .padding(.bottom, 26)

            Text(titleKey)
                .font(.system(.title, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
            Text(subtitleKey)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .padding(.horizontal, 36)

            VStack(alignment: .leading, spacing: 14) {
                points()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .iosCard(padding: 18, cornerRadius: 20)
            .padding(.horizontal, 24)
            .padding(.top, 28)

            Spacer(minLength: 30)
        }
    }

    /// 一条要点:彩色小图标 + 文本(文本里手势名加粗由 catalog 的 markdown 承担)。
    @ViewBuilder
    private func bullet(_ icon: String, _ tint: Color, _ key: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(key)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
