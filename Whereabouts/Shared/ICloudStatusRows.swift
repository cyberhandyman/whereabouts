import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

// Phase 122:设置页 iCloud 区块里的"账号 + 同步状态 + 立即同步"几行 —— 双端共用,
// 放进各自设置页的 iCloud Section 里(macOS GeneralSettingsTab / iOS IOSSettingsView)。

struct ICloudStatusRows: View {
    @Environment(\.modelContext) private var modelContext
    /// @Observable 单例:body 里读到的属性会被自动追踪,变了就重绘。
    private let monitor = CloudSyncMonitor.shared

    @State private var syncing = false
    @State private var outcome: CloudSyncMonitor.SyncOutcome?

    var body: some View {
        if AppContainer.usingInMemoryFallback {
            Label("settings.store.memoryFallback", systemImage: "exclamationmark.octagon.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }

        LabeledContent {
            HStack(spacing: 6) {
                Circle()
                    .fill(accountDotColor)
                    .frame(width: 8, height: 8)
                accountText
            }
        } label: {
            Text("settings.icloud.account")
        }

        if let fp = monitor.accountFingerprint {
            LabeledContent {
                Text(verbatim: fp)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.icloud.accountID")
                    Text("settings.icloud.accountID.hint")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        if AppContainer.cloudKitActive {
            // 相对时间("2 分钟前")每 30 秒刷新一次。
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                VStack(spacing: 8) {
                    LabeledContent {
                        dateText(monitor.lastImportAt)
                    } label: {
                        Text("settings.icloud.lastImport")
                    }
                    LabeledContent {
                        dateText(monitor.lastExportAt)
                    } label: {
                        Text("settings.icloud.lastExport")
                    }
                }
            }

            // 账号不可用时错误多半就是"没登录",账号行已经说明,不再重复一行报错。
            if monitor.account == .available, let err = monitor.lastError {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: err)
                        // Phase 123:这类错误之后 CoreData 本次运行内不再重试,重开 app 才会再试。
                        Text("settings.icloud.retryHint")
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }

            HStack {
                Button {
                    syncing = true
                    outcome = nil
                    Task {
                        let r = await monitor.syncNow(context: modelContext)
                        syncing = false
                        withAnimation { outcome = r }
                    }
                } label: {
                    Label("settings.icloud.syncNow", systemImage: "arrow.triangle.2.circlepath.icloud")
                }
                .disabled(syncing)
                #if os(iOS)
                .buttonStyle(.borderless)
                #endif
                Spacer()
                if syncing || monitor.isSyncing {
                    ProgressView().controlSize(.small)
                    Text("settings.icloud.syncing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let outcome {
                    outcomeLabel(outcome)
                }
            }
        }
    }

    // MARK: - 子视图

    @ViewBuilder
    private var accountText: some View {
        switch monitor.account {
        case .checking:
            Text("settings.icloud.account.checking").foregroundStyle(.secondary)
        case .available:
            if let name = monitor.accountName {
                Text(verbatim: name)
            } else {
                Text("settings.icloud.account.signedIn")
            }
        case .noAccount:
            Text("settings.icloud.account.none").foregroundStyle(.orange)
        case .restricted:
            Text("settings.icloud.account.restricted").foregroundStyle(.orange)
        case .temporarilyUnavailable:
            Text("settings.icloud.account.unavailable").foregroundStyle(.orange)
        case .couldNotDetermine:
            Text("settings.icloud.account.unknown").foregroundStyle(.secondary)
        }
    }

    private var accountDotColor: Color {
        switch monitor.account {
        case .available: return .green
        case .checking, .couldNotDetermine: return .secondary
        default: return .orange
        }
    }

    @ViewBuilder
    private func dateText(_ date: Date?) -> some View {
        if let date {
            Text(date, format: .relative(presentation: .named))
                .foregroundStyle(.secondary)
        } else {
            Text("settings.icloud.never").foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func outcomeLabel(_ outcome: CloudSyncMonitor.SyncOutcome) -> some View {
        switch outcome {
        case .cloudKitIdle:
            Label("settings.icloud.syncDone", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .accountUnavailable:
            Label("settings.icloud.syncNoAccount", systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.orange)
        case .failed:
            Label("settings.icloud.syncFailed", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Phase 122:本地库打不开时的阻断页

/// AppContainer 退到内存库(本地库文件这次没能打开)时,主界面换成这一页 ——
/// 不让用户往一个下次启动就消失的临时库里录东西。数据文件本身原封不动留在磁盘上。
struct StoreUnavailableView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("store.unavailable.title")
                .font(.title2.bold())
            Text("store.unavailable.body")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            #if os(macOS)
            Button("store.unavailable.quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut(.defaultAction)
            #endif
        }
        .padding(32)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
