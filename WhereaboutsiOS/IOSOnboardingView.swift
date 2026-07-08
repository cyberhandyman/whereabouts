import SwiftUI

// Phase 115:首次启动引导 —— 全屏分页(TabView page 风格),
// 每页一个大渐变图标 + 标题 + 三行"手势→结果"式要点。
// 最后一页给「配置 AI(可选)」和「开始使用」。
// @AppStorage("onboardingShown") 只出一次;设置 → 关于 里可重看。

struct IOSOnboardingView: View {
    /// 完成回调(点"开始使用"或右上角跳过)。
    var done: () -> Void

    @State private var page = 0

    #if DEBUG
    /// 截图验收用:--gestures-page 直接落到手势演示页。
    private var initialPage: Int {
        CommandLine.arguments.contains("--gestures-page") ? 2 : 0
    }
    #endif

    var body: some View {
        ZStack {
            IOSTheme.pageBackground
            VStack(spacing: 0) {
                Color.clear.frame(height: 0)
                    .onAppear {
                        #if DEBUG
                        page = initialPage
                        #endif
                    }
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
            // Phase 117:每条手势配一个循环动画演示(SwiftUI 自绘"动图")。
            VStack(alignment: .leading, spacing: 6) {
                GestureDemoRow(kind: .swipeRight)
                bullet("arrow.right.circle.fill", .orange, "onboarding.gestures.point1")
            }
            VStack(alignment: .leading, spacing: 6) {
                GestureDemoRow(kind: .swipeLeft)
                bullet("arrow.left.circle.fill", .red, "onboarding.gestures.point2")
            }
            VStack(alignment: .leading, spacing: 6) {
                GestureDemoRow(kind: .longPress)
                bullet("hand.tap.fill", .indigo, "onboarding.gestures.point3")
            }
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

// MARK: - 手势循环动画演示(Phase 117)

/// 一条"假列表行"上循环播放手势示意:
///   - swipeRight:行向右滑,左侧露出橙色置顶按钮,指尖跟随
///   - swipeLeft :行向左滑,右侧露出红色删除按钮,指尖跟随
///   - longPress :指尖按住,行轻缩,弹出一个小菜单气泡
/// 纯 SwiftUI 关键帧动画(KeyframeAnimator),4 秒一循环,无外部资源。
struct GestureDemoRow: View {
    enum Kind { case swipeRight, swipeLeft, longPress }
    let kind: Kind

    /// 关键帧驱动的值:行位移 x / 行缩放 / 指尖透明度 / 菜单透明度。
    struct Values {
        var offset: CGFloat = 0
        var scale: CGFloat = 1
        var finger: CGFloat = 0
        var menu: CGFloat = 0
    }

    var body: some View {
        KeyframeAnimator(initialValue: Values(), repeating: true) { v in
            ZStack {
                // 底层:滑动露出的动作色块
                if kind != .longPress {
                    HStack {
                        if kind == .swipeRight {
                            actionChip(color: .orange, icon: "pin.fill")
                            Spacer()
                        } else {
                            Spacer()
                            actionChip(color: .red, icon: "trash.fill")
                        }
                    }
                }
                // 中层:假物品行
                fakeRow
                    .offset(x: v.offset)
                    .scaleEffect(v.scale)
                // 长按的菜单气泡
                if kind == .longPress {
                    menuBubble
                        .opacity(v.menu)
                        .offset(y: -34)
                }
                // 指尖
                Circle()
                    .fill(.white.opacity(0.85))
                    .stroke(.black.opacity(0.15), lineWidth: 1)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.2), radius: 3)
                    .offset(x: fingerX(v), y: 12)
                    .opacity(v.finger)
            }
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        } keyframes: { _ in
            KeyframeTrack(\.offset) {
                switch kind {
                case .swipeRight:
                    CubicKeyframe(0, duration: 0.8)
                    CubicKeyframe(64, duration: 0.7)
                    CubicKeyframe(64, duration: 1.2)
                    CubicKeyframe(0, duration: 0.5)
                    CubicKeyframe(0, duration: 0.8)
                case .swipeLeft:
                    CubicKeyframe(0, duration: 0.8)
                    CubicKeyframe(-64, duration: 0.7)
                    CubicKeyframe(-64, duration: 1.2)
                    CubicKeyframe(0, duration: 0.5)
                    CubicKeyframe(0, duration: 0.8)
                case .longPress:
                    CubicKeyframe(0, duration: 4.0)
                }
            }
            KeyframeTrack(\.scale) {
                switch kind {
                case .longPress:
                    CubicKeyframe(1, duration: 0.8)
                    CubicKeyframe(0.96, duration: 0.4)
                    CubicKeyframe(0.96, duration: 1.6)
                    CubicKeyframe(1, duration: 0.4)
                    CubicKeyframe(1, duration: 0.8)
                default:
                    CubicKeyframe(1, duration: 4.0)
                }
            }
            KeyframeTrack(\.finger) {
                LinearKeyframe(0, duration: 0.5)
                LinearKeyframe(1, duration: 0.3)
                LinearKeyframe(1, duration: 2.0)
                LinearKeyframe(0, duration: 0.4)
                LinearKeyframe(0, duration: 0.8)
            }
            KeyframeTrack(\.menu) {
                switch kind {
                case .longPress:
                    LinearKeyframe(0, duration: 1.4)
                    LinearKeyframe(1, duration: 0.3)
                    LinearKeyframe(1, duration: 1.5)
                    LinearKeyframe(0, duration: 0.3)
                    LinearKeyframe(0, duration: 0.5)
                default:
                    LinearKeyframe(0, duration: 4.0)
                }
            }
        }
    }

    /// 指尖横向位置:滑动手势跟着行走,长按固定在行中央偏右。
    private func fingerX(_ v: Values) -> CGFloat {
        switch kind {
        case .swipeRight: return -40 + v.offset
        case .swipeLeft:  return 40 + v.offset
        case .longPress:  return 20
        }
    }

    private var fakeRow: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(IOSTheme.gradient.opacity(0.8))
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(.tertiary).frame(width: 90, height: 9)
                RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 130, height: 7)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }

    private func actionChip(color: Color, icon: String) -> some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(color)
            .frame(width: 56, height: 52)
            .overlay(
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
            )
    }

    private var menuBubble: some View {
        HStack(spacing: 10) {
            Image(systemName: "pin")
            Image(systemName: "pencil")
            Image(systemName: "person.crop.circle.badge.plus")
            Image(systemName: "trash")
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}
