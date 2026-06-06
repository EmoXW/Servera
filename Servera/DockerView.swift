import SwiftUI
import UIKit

// MARK: - Docker 页
// Docker 页只作为服务器 Docker 索引。NAS 容器刻意留在 NAS 页，
// 因为 NAS Docker 管理是独立的免费功能面。

enum EntitlementStore {
    static var isPro: Bool { false }
}

enum ServerDockerFeatureGate {
    static var canUseContainerActions: Bool {
        // 服务器 Docker 操作当前为开发/测试放开。
        // 如果后续恢复正式版 Pro 边界，应在这里集中加回，不要把付费判断散进各个视图。
        return true
    }
}

enum ServerDockerContainerAction: CaseIterable, Identifiable {
    case start
    case stop
    case restart
    case logs
    case refresh

    var id: String { title }

    var title: String {
        switch self {
        case .start: "启动"
        case .stop: "停止"
        case .restart: "重启"
        case .logs: "日志"
        case .refresh: "刷新"
        }
    }

    var systemImage: String {
        switch self {
        case .start: "play.fill"
        case .stop: "stop.fill"
        case .restart: "arrow.clockwise"
        case .logs: "doc.text.magnifyingglass"
        case .refresh: "arrow.triangle.2.circlepath"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .stop, .restart:
            return true
        case .start, .logs, .refresh:
            return false
        }
    }

    func confirmationMessage(containerName: String) -> String {
        switch self {
        case .stop:
            return "将停止服务器上的容器「\(containerName)」，正在运行的服务会真实中断。"
        case .restart:
            return "将重启服务器上的容器「\(containerName)」，服务会短暂中断。"
        case .start, .logs, .refresh:
            return ""
        }
    }
}

struct ServerDockerActionResult {
    var containers: [DockerContainerSummary]
    var logText: String?
}

typealias ServerDockerActionHandler = (DashboardDevice, DockerContainerSummary, ServerDockerContainerAction, Int) async throws -> ServerDockerActionResult

struct DockerView: View {
    let devices: [DashboardDevice]
    var onSelectServer: (DashboardDevice) -> Void = { _ in }

    private var dockerDevices: [DashboardDevice] {
        // Docker 页只索引 SSH 服务器。NAS Docker 出现在 NAS 视图里，
        // 因为它使用 DSM 凭据，并且免费操作规则不同。
        devices.filter { $0.kind == .server && ($0.docker > 0 || !$0.dockerContainers.isEmpty) }
    }

    private var runningCount: Int {
        dockerDevices.reduce(0) { $0 + $1.dockerRunningCount }
    }

    private var totalCount: Int {
        dockerDevices.reduce(0) { $0 + max($1.docker, $1.dockerContainers.count) }
    }

    private var attentionCount: Int {
        max(totalCount - runningCount, 0)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                HeaderBar(title: "Docker", trailing: "arrow.clockwise")

                if dockerDevices.isEmpty {
                    DockerEmptyStateCard()
                } else {
                    DockerSummaryStrip(
                        serverCount: dockerDevices.count,
                        runningCount: runningCount,
                        totalCount: totalCount,
                        attentionCount: attentionCount
                    )

                    VStack(spacing: 10) {
                        ForEach(dockerDevices) { device in
                            Button {
                                onSelectServer(device)
                            } label: {
                                ServerDockerEntryRow(device: device)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
        }
    }
}

private struct DockerEmptyStateCard: View {
    var body: some View {
        ServeraCard {
            VStack(spacing: 10) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 42, weight: .heavy))
                    .foregroundStyle(Color.serveraAccentDeep)
                Text("还没有检测到服务器 Docker")
                    .font(.system(size: 21, weight: .heavy))
                Text("添加 SSH 服务器后，Servera 会在后台识别服务器容器状态。NAS Docker 只在 NAS 栏展示。")
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.serveraTextSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct DockerSummaryStrip: View {
    let serverCount: Int
    let runningCount: Int
    let totalCount: Int
    let attentionCount: Int

    var body: some View {
        HStack(spacing: 8) {
            DockerSummaryMetric(title: "服务器", value: "\(serverCount)", tint: .serveraAccentDeep)
            DockerSummaryMetric(title: "运行中", value: "\(runningCount)", tint: .serveraLeaf)
            DockerSummaryMetric(title: "总容器", value: "\(totalCount)", tint: .serveraSky)
            DockerSummaryMetric(title: "需关注", value: "\(attentionCount)", tint: attentionCount > 0 ? .serveraAmber : .serveraTextSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.78))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.serveraBorder.opacity(0.42), lineWidth: 1)
                )
                .shadow(color: Color.serveraAccent.opacity(0.08), radius: 16, y: 8)
        }
    }
}

private struct DockerSummaryMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(title)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.serveraTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

private struct ServerDockerEntryRow: View {
    let device: DashboardDevice

    private var totalCount: Int {
        max(device.docker, device.dockerContainers.count)
    }

    private var stoppedCount: Int {
        max(totalCount - device.dockerRunningCount, 0)
    }

    private var statusColor: Color {
        guard device.dockerDataAvailable else { return .serveraAmber }
        return stoppedCount > 0 || device.warning ? .serveraAmber : .serveraLeaf
    }

    private var subtitle: String {
        if !device.primaryIPText.isEmpty, device.primaryIPText != "-" {
            return device.primaryIPText
        }
        if !device.systemVersion.isEmpty {
            return device.systemVersion
        }
        return device.subtitle
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(colors: [.serveraSky.opacity(0.95), .serveraLeaf.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(.white)
                    )
                Circle()
                    .fill(statusColor)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .offset(x: 2, y: 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text("运行中 \(device.dockerRunningCount)")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Color.serveraLeaf)
                    .monospacedDigit()
                Text("共 \(totalCount)")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .monospacedDigit()
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color.serveraTextSecondary.opacity(0.72))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.serveraBorder.opacity(0.45), lineWidth: 1)
                )
        )
    }
}

struct ServerDockerContainerListView: View {
    @Environment(\.dismiss) private var dismiss
    let device: DashboardDevice
    var onExecuteAction: ServerDockerActionHandler = { _, _, _, _ in
        throw ServeraSSHError.commandFailed("Server Docker 操作未接入。")
    }
    @State private var selectedContainer: DockerContainerSummary?

    private var totalCount: Int {
        max(device.docker, device.dockerContainers.count)
    }

    private var stoppedCount: Int {
        max(totalCount - device.dockerRunningCount, 0)
    }

    var body: some View {
        // Docker 首屏刻意保持紧凑。用户选择具体服务器后，才展示完整容器行和操作入口。
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                DetailTopBar(
                    title: "容器管理",
                    subtitle: device.name,
                    onBack: { dismiss() }
                )

                ServerDockerDetailSummaryCard(
                    device: device,
                    totalCount: totalCount,
                    stoppedCount: stoppedCount
                )

            ServerDockerContainerListCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("容器列表")
                                .font(.system(size: 18, weight: .heavy))
                            Spacer()
                            StatusPill(text: "\(device.dockerRunningCount)/\(totalCount) 运行")
                        }

                        if device.dockerContainers.isEmpty {
                            DockerContainerEmptyState(device: device)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(device.dockerContainers) { container in
                                    Button {
                                        selectedContainer = container
                                    } label: {
                                        DockerResourceRow(
                                            container: container,
                                            showsDivider: container.id != device.dockerContainers.last?.id
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .background(ServeraBackground().ignoresSafeArea())
        .sheet(item: $selectedContainer) { container in
            ServerDockerContainerDetailSheet(
                device: device,
                initialContainer: container,
                onExecuteAction: onExecuteAction
            )
                .presentationDetents([.large])
        }
    }
}

private struct ServerDockerContainerListCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.74))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.serveraBorder.opacity(0.42), lineWidth: 1)
                )
                .shadow(color: Color.serveraAccent.opacity(0.08), radius: 16, y: 8)
        }
    }
}

private struct ServerDockerDetailSummaryCard: View {
    let device: DashboardDevice
    let totalCount: Int
    let stoppedCount: Int

    var body: some View {
        ServeraCard(cornerRadius: 28) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [.serveraSky, .serveraLeaf], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 54, height: 54)
                        .overlay(
                            Image(systemName: "shippingbox")
                                .font(.system(size: 20, weight: .black))
                                .foregroundStyle(.white)
                        )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name)
                            .font(.system(size: 22, weight: .black))
                            .lineLimit(1)
                        Text(device.dockerDataAvailable ? "Server Docker 已连接" : device.dockerErrorMessage.dockerNonEmptyOr("等待 Docker 刷新"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.serveraTextSecondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    DockerSummaryMetric(title: "运行中", value: "\(device.dockerRunningCount)", tint: .serveraLeaf)
                    DockerSummaryMetric(title: "总容器", value: "\(totalCount)", tint: .serveraSky)
                    DockerSummaryMetric(title: "需关注", value: "\(stoppedCount)", tint: stoppedCount > 0 ? .serveraAmber : .serveraTextSecondary)
                }
            }
        }
    }
}

private struct DockerContainerEmptyState: View {
    let device: DashboardDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(emptyTitle)
                .font(.system(size: 17, weight: .heavy))
            Text(emptyMessage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.serveraTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var emptyTitle: String {
        guard device.dockerDataAvailable else { return "Docker 状态不可用" }
        if device.docker > 0 { return "等待容器详情" }
        return "暂无容器"
    }

    private var emptyMessage: String {
        guard device.dockerDataAvailable else {
            return device.dockerErrorMessage.dockerNonEmptyOr("可能是 Docker 权限不足、服务不可用，或等待下一次刷新。")
        }
        if device.docker > 0 {
            return "已检测到 \(device.docker) 个容器，等待下一次服务器刷新读取容器资源。"
        }
        return "当前服务器没有检测到 Docker 容器。"
    }
}

private struct ServerDockerContainerDetailSheet: View {
    let device: DashboardDevice
    let initialContainer: DockerContainerSummary
    let onExecuteAction: ServerDockerActionHandler
    private let canUseContainerActions = ServerDockerFeatureGate.canUseContainerActions
    @Environment(\.dismiss) private var dismiss
    @State private var container: DockerContainerSummary
    @State private var containers: [DockerContainerSummary]
    @State private var activeAction: ServerDockerContainerAction?
    @State private var pendingAction: ServerDockerContainerAction?
    @State private var localError: String?
    @State private var localSuccess: ServerDockerToastMessage?
    @State private var logText = ""
    @State private var isLoadingLogs = false
    @State private var selectedLogLines = 100

    init(
        device: DashboardDevice,
        initialContainer: DockerContainerSummary,
        onExecuteAction: @escaping ServerDockerActionHandler
    ) {
        self.device = device
        self.initialContainer = initialContainer
        self.onExecuteAction = onExecuteAction
        _container = State(initialValue: initialContainer)
        _containers = State(initialValue: device.dockerContainers)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    Capsule()
                        .fill(Color.serveraBorder)
                        .frame(width: 42, height: 5)
                        .padding(.top, 8)

                    header
                    actionCard
                    logCard
                }
                .padding(22)
            }

            if let localSuccess {
                ServerDockerToast(message: localSuccess.text, systemImage: localSuccess.systemImage, tint: localSuccess.tint)
                    .padding(.top, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .background(ServeraBackground().ignoresSafeArea())
        .task {
            await loadLogs(showFeedback: false)
        }
        .alert("确认操作", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })) {
            Button(pendingAction?.title ?? "确认", role: pendingAction?.isDestructive == true ? .destructive : nil) {
                if let pendingAction {
                    Task { await perform(pendingAction) }
                }
                pendingAction = nil
            }
            Button("取消", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text(pendingAction?.confirmationMessage(containerName: container.name) ?? "")
        }
        .alert("操作失败", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) {
            Button("知道了", role: .cancel) { localError = nil }
        } message: {
            Text(localError ?? "")
        }
    }

    private var header: some View {
        ServeraCard(cornerRadius: 28) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(container.isRunning ? Color.serveraLeaf : Color.gray.opacity(0.46))
                        .frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(container.name)
                            .font(.system(size: 24, weight: .black))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(container.image.isEmpty ? device.name : container.image)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.serveraTextSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    StatusPill(text: container.isRunning ? "运行中" : "已停止", color: container.isRunning ? .serveraLeaf : .serveraTextSecondary)
                }

                DockerResourceRow(container: container)

                HStack(spacing: 10) {
                    ServerDockerInfoPill(title: "状态", value: container.status.isEmpty ? container.state : container.status)
                    ServerDockerInfoPill(title: "运行", value: container.uptimeText.isEmpty ? "-" : container.uptimeText)
                }
            }
        }
    }

    private var actionCard: some View {
        ServeraCard(cornerRadius: 28) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Docker 管理")
                        .font(.system(size: 17, weight: .black))
                    Spacer()
                    if let activeAction {
                        Text("正在\(activeAction.title)")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Color.serveraAccentDeep)
                    }
                }

                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                    ForEach(availableActions) { action in
                        DockerActionButton(
                            title: action.title,
                            icon: action.systemImage,
                            isLoading: activeAction == action,
                            isDisabled: activeAction != nil || isLoadingLogs || !canUseContainerActions
                        ) {
                            request(action)
                        }
                    }
                }
            }
        }
    }

    private var logCard: some View {
        ServeraCard(cornerRadius: 28) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("最近日志")
                        .font(.system(size: 17, weight: .black))
                    Spacer()
                    if isLoadingLogs {
                        ProgressView()
                            .scaleEffect(0.76)
                    } else {
                        Text("\(selectedLogLines) 行")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Color.serveraTextSecondary)
                    }
                }

                Picker("日志行数", selection: $selectedLogLines) {
                    Text("100").tag(100)
                    Text("300").tag(300)
                    Text("1000").tag(1000)
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedLogLines) { _, _ in
                    Task { await loadLogs() }
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(logDisplayText)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(logText.isEmpty ? 0.58 : 0.92))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)

                            Color.clear
                                .frame(height: 1)
                                .id("serverDockerLogBottom")
                        }
                        .padding(14)
                    }
                    .frame(minHeight: 210, maxHeight: 320)
                    .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .onChange(of: logText) { _, _ in
                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo("serverDockerLogBottom", anchor: .bottom)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await loadLogs() }
                    } label: {
                        Label("刷新日志", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(ServerDockerSecondaryButtonStyle())
                    .disabled(activeAction != nil || isLoadingLogs)

                    Button {
                        UIPasteboard.general.string = logText
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(ServerDockerSecondaryButtonStyle())
                    .disabled(logText.isEmpty)
                }
            }
        }
    }

    private var availableActions: [ServerDockerContainerAction] {
        if container.isRunning {
            return [.stop, .restart, .logs, .refresh]
        }
        return [.start, .logs, .refresh]
    }

    private var logDisplayText: String {
        if !logText.isEmpty { return logText }
        if isLoadingLogs { return "正在读取容器日志..." }
        return "暂无容器日志。"
    }

    private func request(_ action: ServerDockerContainerAction) {
        guard canUseContainerActions else { return }
        if action.isDestructive {
            pendingAction = action
        } else {
            Task { await perform(action) }
        }
    }

    private func loadLogs(showFeedback: Bool = true) async {
        guard activeAction == nil else { return }
        isLoadingLogs = true
        defer { isLoadingLogs = false }
        do {
            let result = try await onExecuteAction(device, container, .logs, selectedLogLines)
            if let logText = result.logText {
                self.logText = sanitizedLogText(logText)
            }
            applyContainers(result.containers)
            if showFeedback {
                showSuccess("日志已刷新")
            }
        } catch {
            localError = error.localizedDescription
        }
    }

    private func perform(_ action: ServerDockerContainerAction) async {
        guard activeAction == nil else { return }
        if action == .logs {
            await loadLogs()
            return
        }
        let previousContainer = container
        activeAction = action
        do {
            let result = try await onExecuteAction(device, container, action, selectedLogLines)
            let updatedContainer = applyContainers(result.containers)
            if let logText = result.logText {
                self.logText = sanitizedLogText(logText)
            }
            activeAction = nil
            // 操作处理器返回命令执行后重新采集的容器列表。用读回状态判断是否真正成功，
            // 或提示“命令已执行但服务器状态未变化”。
            showCompletionFeedback(for: action, previous: previousContainer, updated: updatedContainer)
            if action == .start || action == .stop || action == .restart || action == .refresh {
                await loadLogs(showFeedback: false)
            }
        } catch {
            activeAction = nil
            localError = error.localizedDescription
        }
    }

    @discardableResult
    private func applyContainers(_ refreshed: [DockerContainerSummary]) -> DockerContainerSummary? {
        guard !refreshed.isEmpty else { return nil }
        containers = refreshed
        if let updated = refreshed.first(where: { $0.id == container.id || $0.name == container.name }) {
            container = updated
            return updated
        }
        return nil
    }

    private func showCompletionFeedback(for action: ServerDockerContainerAction, previous: DockerContainerSummary, updated: DockerContainerSummary?) {
        if let warning = unchangedWarning(for: action, previous: previous, updated: updated) {
            showWarning(warning)
            return
        }
        showSuccess(action.successMessage)
    }

    private func unchangedWarning(for action: ServerDockerContainerAction, previous: DockerContainerSummary, updated: DockerContainerSummary?) -> String? {
        guard let updated else {
            return action == .refresh ? nil : "Docker 命令已执行，但刷新后未找到该容器，请返回列表确认。"
        }
        switch action {
        case .start:
            return updated.isRunning ? nil : "Docker 命令已执行，但服务器状态未变化，请刷新后确认。"
        case .stop:
            return updated.isRunning ? "Docker 命令已执行，但服务器状态未变化，请刷新后确认。" : nil
        case .restart:
            return updated.isRunning ? nil : "Docker 命令已执行，但容器未保持运行，请刷新后确认。"
        case .refresh, .logs:
            return nil
        }
    }

    private func sanitizedLogText(_ text: String) -> String {
        // 日志窗口只保留容器输出。SSH/sudo 包装层可能输出提示或 Servera 标记，
        // 尤其是在权限兜底路径上。
        let blockedFragments = [
            "__SERVERA_LOG_BEGIN__",
            "__SERVERA_LOG_END__",
            "[sudo]",
            "password for",
            "sudo:"
        ]
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !blockedFragments.contains { trimmed.localizedCaseInsensitiveContains($0) }
            }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func showSuccess(_ message: String) {
        showToast(ServerDockerToastMessage(text: message, systemImage: "checkmark.circle.fill", tint: .serveraLeaf))
    }

    private func showWarning(_ message: String) {
        showToast(ServerDockerToastMessage(text: message, systemImage: "exclamationmark.triangle.fill", tint: .serveraAmber))
    }

    private func showToast(_ message: ServerDockerToastMessage) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            localSuccess = message
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                if localSuccess?.id == message.id {
                    withAnimation(.easeOut(duration: 0.22)) {
                        localSuccess = nil
                    }
                }
            }
        }
    }
}

private extension ServerDockerContainerAction {
    var successMessage: String {
        switch self {
        case .start: "容器已启动"
        case .stop: "容器已停止"
        case .restart: "容器已重启"
        case .logs: "日志已刷新"
        case .refresh: "状态已刷新"
        }
    }
}

private struct ServerDockerToastMessage: Identifiable {
    let id = UUID()
    let text: String
    let systemImage: String
    let tint: Color
}

private struct ServerDockerToast: View {
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(tint)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(.white.opacity(0.92))
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(tint.opacity(0.28), lineWidth: 1))
                    .shadow(color: tint.opacity(0.16), radius: 16, y: 8)
            }
            .padding(.horizontal, 24)
    }
}

struct DockerDetailSheet: View {
    let device: DashboardDevice
    @State private var selectedContainer: DockerContainerSummary?

    private var totalCount: Int {
        max(device.docker, device.dockerContainers.count)
    }

    private var stoppedCount: Int {
        max(totalCount - device.dockerRunningCount, 0)
    }

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color.serveraBorder)
                .frame(width: 42, height: 5)
                .padding(.top, 8)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.system(size: 26, weight: .black))
                        .lineLimit(1)
                    Text("\(device.dockerRunningCount) running · \(totalCount) total")
                        .foregroundStyle(Color.serveraTextSecondary)
                }
                Spacer()
                StatusPill(text: "\(device.dockerRunningCount) 运行中")
            }

            ServerDockerDetailSummaryCard(
                device: device,
                totalCount: totalCount,
                stoppedCount: stoppedCount
            )

            ServeraCard(cornerRadius: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("容器列表")
                        .font(.system(size: 18, weight: .heavy))

                    if device.dockerContainers.isEmpty {
                        DockerContainerEmptyState(device: device)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(device.dockerContainers) { container in
                                Button {
                                    selectedContainer = container
                                } label: {
                                    DockerResourceRow(container: container)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(22)
        .background(ServeraBackground().ignoresSafeArea())
        .sheet(item: $selectedContainer) { container in
            ServerDockerContainerDetailSheet(device: device, initialContainer: container) { _, _, _, _ in
                throw ServeraSSHError.commandFailed("请从 Docker Tab 的容器管理页执行 Server Docker 操作。")
            }
                .presentationDetents([.large])
        }
    }
}

struct DockerResourceRow: View {
    let container: DockerContainerSummary
    var showsDivider = true

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(container.isRunning ? Color.serveraLeaf : Color.gray.opacity(0.46))
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 3) {
                Text(container.name)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(container.status.isEmpty ? container.image : container.status)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(container.isRunning ? formatDockerCPUText(container.cpuPercent) : "停止")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(container.isRunning ? Color.serveraAccentDeep : Color.serveraTextSecondary)
                    .lineLimit(1)
                Text(container.isRunning ? dockerMemoryText(container) : "-")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(container.isRunning ? Color.serveraSky : Color.serveraTextSecondary.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 74, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Color.serveraTextSecondary.opacity(0.68))
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(Color.serveraBorder.opacity(0.5)).frame(height: 1)
            }
        }
    }
}

private struct ServerDockerInfoPill: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.serveraTextSecondary)
            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct DockerActionButton: View {
    let title: String
    let icon: String
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 7) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .black))
                }
                Text(title)
                    .font(.system(size: 12, weight: .heavy))
            }
            .foregroundStyle(isDisabled ? Color.serveraTextSecondary.opacity(0.72) : Color.serveraAccentDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct ServerDockerSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Color.serveraAccentDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Color.white.opacity(configuration.isPressed ? 0.42 : 0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension String {
    func dockerNonEmptyOr(_ fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
