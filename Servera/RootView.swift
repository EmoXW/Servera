import SwiftUI
import SwiftData

// MARK: - 应用组合根视图
// 根视图负责导航、SwiftData 写入、刷新编排，并把服务层结果写回
// 设备持久化记录。各功能页尽量保持轻状态，只调用这里定义的闭包。

enum AppTab: String, CaseIterable, Identifiable {
    case dashboard = "Server"
    case nas = "NAS"
    case devices = "设备"
    case docker = "Docker"
    case settings = "设置"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: "server.rack"
        case .nas: "externaldrive.connected.to.line.below"
        case .devices: "plus.rectangle.on.folder"
        case .docker: "shippingbox"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("servera.theme.id") private var selectedThemeID = ServeraThemePreset.fallback.id
    @AppStorage("servera.appearance.mode") private var appearanceModeRawValue = ServeraAppearanceMode.system.rawValue
    @Query(sort: [SortDescriptor(\ManagedDeviceRecord.orderIndex), SortDescriptor(\ManagedDeviceRecord.createdAt)])
    private var deviceRecords: [ManagedDeviceRecord]
    @State private var selectedTab: AppTab = .dashboard
    @State private var navigationPath: [RootRoute] = []
    @State private var recentlyAddedDevices: [DashboardDevice] = []
    @State private var refreshingDeviceIDs: Set<UUID> = []
    @State private var editingServer: ServerEditSelection?
    @State private var editingNAS: NASEditSelection?
    @State private var fileBrowserSelection: NASFileBrowserSelection?
    @State private var dockerContainerSelection: NASDockerContainerSelection?
    @State private var pendingDeleteDevice: DashboardDevice?
    @State private var actionError: String?
    @State private var preferredDeviceKind: ManagedDeviceKind = .server
    @State private var addDeviceRequestID = 0
    @Namespace private var tabNamespace

    private var visibleDevices: [DashboardDevice] {
        let savedDevices = deviceRecords
            .filter { $0.isVisible && !$0.isDocumentationPlaceholder }
            .map(\.dashboardDevice)
        let savedIDs = Set(savedDevices.map(\.id))
        let pendingDevices = recentlyAddedDevices.filter { !savedIDs.contains($0.id) }
        return (savedDevices + pendingDevices).sorted { lhs, rhs in
            guard let lhsIndex = orderedIndex(for: lhs.id), let rhsIndex = orderedIndex(for: rhs.id) else {
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
            return lhsIndex < rhsIndex
        }
    }

    private var serverDevices: [DashboardDevice] {
        visibleDevices.filter { $0.kind == .server }
    }

    private var currentTheme: ServeraThemePreset {
        ServeraThemePreset.preset(for: selectedThemeID)
    }

    private var preferredColorScheme: ColorScheme? {
        ServeraAppearanceMode.mode(for: appearanceModeRawValue).colorScheme
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .bottom) {
                ServeraBackground()
                    .ignoresSafeArea()

                Group {
                    switch selectedTab {
                    case .dashboard:
                        DashboardView(
                            devices: serverDevices,
                            autoRefreshEnabled: navigationPath.isEmpty,
                            onReorder: persistOrder,
                            refreshingDeviceIDs: refreshingDeviceIDs,
                            onSelect: { device in
                                navigationPath.append(.device(device))
                            },
                            onRefresh: refreshServer,
                            onRefreshAll: refreshAllServers,
                            onAutoRefresh: { device in
                                refreshServerLiveMetrics(device)
                            },
                            onAddServer: openAddServer,
                            onEdit: { device in
                                editingServer = ServerEditSelection(id: device.id)
                            },
                            onDelete: { device in
                                pendingDeleteDevice = device
                            }
                        )
                    case .nas:
                        NASView(
                            devices: visibleDevices,
                            refreshingDeviceIDs: refreshingDeviceIDs,
                            onRefresh: refreshNAS,
                            onEdit: { device in
                                editingNAS = NASEditSelection(id: device.id)
                            },
                            onDelete: { device in
                                pendingDeleteDevice = device
                            },
                            onOpenFiles: { device, volume in
                                openNASFiles(device: device, volume: volume)
                            },
                            onOpenControlPanel: { device, module in
                                openNASControlPanel(device: device, module: module)
                            },
                            onOpenDockerContainer: { device, container in
                                openNASDockerContainer(device: device, container: container)
                            }
                        ) { device in
                            navigationPath.append(.device(device))
                        } onAddNAS: {
                            openAddNAS()
                        }
                    case .devices:
                        DevicesView(preferredKind: preferredDeviceKind, requestID: addDeviceRequestID) { addedDevice in
                            handleDeviceAdded(addedDevice)
                        }
                    case .docker:
                        DockerView(devices: visibleDevices) { device in
                            navigationPath.append(.serverDocker(device))
                        }
                    case .settings:
                        SettingsView()
                    }
                }
                .safeAreaPadding(.bottom, navigationPath.isEmpty ? 92 : 0)

                if navigationPath.isEmpty {
                    TopSafeAreaMist()
                        .zIndex(1)

                    BottomSafeAreaMist()
                        .allowsHitTesting(false)
                        .zIndex(1)

                    ServeraTabBar(selectedTab: $selectedTab, namespace: tabNamespace)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(2)
                }
            }
            .navigationDestination(for: RootRoute.self) { route in
                switch route {
                case .device(let device):
                    if device.kind == .nas {
                        NASDetailView(
                            device: device,
                            onRefresh: refreshNAS,
                            onEdit: {
                                editingNAS = NASEditSelection(id: device.id)
                            },
                            onDelete: {
                                pendingDeleteDevice = device
                            },
                            onOpenFiles: { volume in
                                openNASFiles(device: device, volume: volume)
                            },
                            onOpenControlPanel: { module in
                                openNASControlPanel(device: device, module: module)
                            },
                            onOpenDockerContainer: { container in
                                openNASDockerContainer(device: device, container: container)
                            }
                        )
                            .navigationBarBackButtonHidden()
                            .toolbar(.hidden, for: .navigationBar)
                    } else {
                        ServerDetailView(
                            device: device,
                            onEdit: {
                                editingServer = ServerEditSelection(id: device.id)
                            },
                            onDelete: {
                                pendingDeleteDevice = device
                            }
                        )
                            .navigationBarBackButtonHidden()
                            .toolbar(.hidden, for: .navigationBar)
                    }
                case .nasControlPanel(let route):
                    NASControlPanelDetailView(
                        device: route.device,
                        initialModule: route.module,
                        connection: route.connection,
                        onSnapshotUpdated: { snapshot in
                            updateNASControlPanelSnapshot(deviceID: route.device.id, snapshot: snapshot)
                        },
                        onAccountRenamed: { oldName, newName in
                            updateNASAccountIfNeeded(deviceID: route.device.id, oldName: oldName, newName: newName)
                        },
                        onError: { message in
                            actionError = message
                        }
                    )
                case .serverDocker(let device):
                    ServerDockerContainerListView(
                        device: device,
                        onExecuteAction: performServerDockerAction
                    )
                        .navigationBarBackButtonHidden()
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .environment(\.serveraTheme, currentTheme)
        .sheet(item: $editingServer) { selection in
            ServerEditSheet(deviceID: selection.id) { updatedDevice in
                handleDeviceUpdated(updatedDevice)
            }
        }
        .sheet(item: $editingNAS) { selection in
            NASEditSheet(deviceID: selection.id) { updatedDevice in
                handleDeviceUpdated(updatedDevice)
            }
        }
        .fullScreenCover(item: $fileBrowserSelection) { selection in
            NASFileBrowserView(
                device: selection.device,
                volume: selection.volume,
                connection: selection.connection
            )
        }
        .sheet(item: $dockerContainerSelection) { selection in
            NASDockerContainerDetailView(
                device: selection.device,
                initialContainer: selection.container,
                connection: selection.connection,
                onContainersUpdated: { containers in
                    updateNASDockerContainers(deviceID: selection.device.id, containers: containers)
                },
                onError: { message in
                    actionError = message
                }
            )
        }
        .alert("操作失败", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("知道了", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .alert(deleteTitle, isPresented: Binding(get: { pendingDeleteDevice != nil }, set: { if !$0 { pendingDeleteDevice = nil } })) {
            Button("删除", role: .destructive) {
                if let pendingDeleteDevice {
                    deleteDevice(pendingDeleteDevice)
                }
                pendingDeleteDevice = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteDevice = nil
            }
        } message: {
            Text("删除后会移除本机配置和 Keychain 凭据。")
        }
        .preferredColorScheme(preferredColorScheme)
    }

    private var deleteTitle: String {
        pendingDeleteDevice?.kind == .nas ? "删除 NAS？" : "删除服务器？"
    }

    private func persistOrder(_ orderedIDs: [UUID]) {
        // 排序只作用于服务器。这里防御性补齐缺失 id，
        // 避免一次不完整拖拽结果让可见服务器丢失 orderIndex。
        let serverRecords = orderedServerRecords()
        let orderedIDSet = Set(orderedIDs)
        let missingIDs = serverRecords
            .map(\.deviceID)
            .filter { !orderedIDSet.contains($0) }
        let finalIDs = orderedIDs + missingIDs

        for (index, id) in finalIDs.enumerated() {
            guard let record = serverRecords.first(where: { $0.deviceID == id }) else { continue }
            record.orderIndex = index
            record.updatedAt = .now
        }
        try? modelContext.save()
    }

    private func handleDeviceAdded(_ device: DashboardDevice) {
        // 保存后立即镜像到本地数组，让 UI 先响应，等待 SwiftData @Query 追上。
        recentlyAddedDevices.removeAll { $0.id == device.id }
        recentlyAddedDevices.append(device)

        withAnimation(.spring(response: 0.44, dampingFraction: 0.84)) {
            selectedTab = device.kind == .nas ? .nas : .dashboard
        }
    }

    private func handleDeviceUpdated(_ device: DashboardDevice) {
        // 后台刷新或 Docker 操作更新底层记录后，同步刷新已经 push 出去的详情路由。
        recentlyAddedDevices.removeAll { $0.id == device.id }
        recentlyAddedDevices.append(device)

        if let index = navigationPath.firstIndex(where: { $0.deviceID == device.id }) {
            switch navigationPath[index] {
            case .device:
                navigationPath[index] = .device(device)
            case .nasControlPanel(let route):
                navigationPath[index] = .nasControlPanel(route.updatingDevice(device))
            case .serverDocker:
                navigationPath[index] = .serverDocker(device)
            }
        }
    }

    private func refreshServer(_ device: DashboardDevice) {
        Task {
            await refreshServerNow(device, showErrors: true)
        }
    }

    @MainActor
    private func refreshAllServers() async {
        guard !serverDevices.isEmpty else {
            try? await Task.sleep(for: .milliseconds(220))
            return
        }

        for device in serverDevices {
            await refreshServerNow(device, showErrors: false)
        }
    }

    @MainActor
    private func refreshServerNow(_ device: DashboardDevice, showErrors: Bool) async {
        // 同一主机避免并发刷新。CPU/网络采集依赖短时间差值，
        // 重叠脚本会让数值失真。
        guard !refreshingDeviceIDs.contains(device.id) else { return }
        refreshingDeviceIDs.insert(device.id)

        defer {
            refreshingDeviceIDs.remove(device.id)
        }

        do {
            guard let record = try fetchRecord(id: device.id) else {
                throw ServeraSSHError.connectionFailed("未找到本地设备记录。")
            }
            guard let credentialIdentifier = record.credentialIdentifier,
                  let credential = try KeychainService.loadCredentialBundle(id: credentialIdentifier) else {
                record.connectionStatus = .needsVerification
                record.credentialNeedsVerification = true
                try modelContext.save()
                throw ServeraSSHError.connectionFailed("凭据不存在，请编辑连接后重新验证。")
            }

            let request = SSHConnectionRequest(
                host: record.host,
                port: record.port,
                username: record.account,
                authenticationKind: record.authenticationKind,
                credential: credential,
                acceptUnknownHostKey: false
            )
            let outcome = try await SSHConnectionService.shared.validateAndCollect(request: request)
            record.applyServerSnapshot(outcome)
            try modelContext.save()
            handleDeviceUpdated(record.dashboardDevice)
        } catch {
            if showErrors, !error.isRefreshCancellation {
                actionError = error.localizedDescription
            }
        }
    }

    private func refreshServerLiveMetrics(_ device: DashboardDevice) {
        // 自动刷新按设计保持静默；用户手动刷新时才展示可见失败反馈。
        guard !refreshingDeviceIDs.contains(device.id) else { return }
        refreshingDeviceIDs.insert(device.id)

        Task { @MainActor in
            defer {
                refreshingDeviceIDs.remove(device.id)
            }

            do {
                guard let record = try fetchRecord(id: device.id), record.kind == .server else { return }
                guard let credentialIdentifier = record.credentialIdentifier,
                      let credential = try KeychainService.loadCredentialBundle(id: credentialIdentifier) else {
                    record.connectionStatus = .needsVerification
                    record.credentialNeedsVerification = true
                    try modelContext.save()
                    return
                }

                let request = SSHConnectionRequest(
                    host: record.host,
                    port: record.port,
                    username: record.account,
                    authenticationKind: record.authenticationKind,
                    credential: credential,
                    acceptUnknownHostKey: false
                )
                let outcome = try await SSHConnectionService.shared.collectLiveMetrics(request: request)
                record.applyLiveMetricsSnapshot(outcome)
                try modelContext.save()
                handleDeviceUpdated(record.dashboardDevice)
            } catch {
                // 首页实时刷新保持静默，避免网络抖动时反复弹窗打断用户。
            }
        }
    }

    private func openAddServer() {
        // 共用的 DevicesView 根据这个偏好直接展示 SSH 表单。
        preferredDeviceKind = .server
        addDeviceRequestID += 1
        withAnimation(.spring(response: 0.44, dampingFraction: 0.84)) {
            selectedTab = .devices
        }
    }

    private func openAddNAS() {
        // 共用的 DevicesView 根据这个偏好展示群晖表单，并套用 HTTP/5000 等 NAS 默认值。
        preferredDeviceKind = .nas
        addDeviceRequestID += 1
        withAnimation(.spring(response: 0.44, dampingFraction: 0.84)) {
            selectedTab = .devices
        }
    }

    @MainActor
    private func openNASFiles(device: DashboardDevice, volume: SynologyStorageVolume) {
        // 只有真实卷路径才能进入这里。无路径存储池只展示容量，在存储卡里保持禁用。
        do {
            guard let record = try fetchRecord(id: device.id), record.kind == .nas else {
                throw SynologyClientError.connectionFailed("未找到本地 NAS 记录。")
            }
            guard let credentialIdentifier = record.credentialIdentifier,
                  let password = try KeychainService.loadSecret(id: credentialIdentifier),
                  !password.isEmpty else {
                record.connectionStatus = .needsVerification
                record.credentialNeedsVerification = true
                try modelContext.save()
                throw SynologyClientError.authenticationFailed("DSM 凭据不存在，请编辑 NAS 后重新验证。")
            }
            fileBrowserSelection = NASFileBrowserSelection(
                device: device,
                volume: volume,
                connection: SynologyFileConnection(
                    host: record.host,
                    port: record.port,
                    scheme: record.nasProtocol,
                    account: record.account,
                    password: password,
                    verifySSLCertificate: record.nasVerifySSLCertificate
                )
            )
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func openNASDockerContainer(device: DashboardDevice, container: DockerContainerSummary) {
        do {
            let connection = try nasDockerConnection(for: device.id)
            dockerContainerSelection = NASDockerContainerSelection(
                device: device,
                container: container,
                connection: connection
            )
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func openNASControlPanel(device: DashboardDevice, module: NASControlPanelModule) {
        do {
            let connection = try nasControlPanelConnection(for: device.id)
            navigationPath.append(.nasControlPanel(NASControlPanelRoute(
                device: device,
                module: module,
                connection: connection
            )))
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func nasDockerConnection(for deviceID: UUID) throws -> SynologyDockerConnection {
        guard let record = try fetchRecord(id: deviceID), record.kind == .nas else {
            throw SynologyClientError.connectionFailed("未找到本地 NAS 记录。")
        }
        guard let credentialIdentifier = record.credentialIdentifier,
              let password = try KeychainService.loadSecret(id: credentialIdentifier),
              !password.isEmpty else {
            record.connectionStatus = .needsVerification
            record.credentialNeedsVerification = true
            try modelContext.save()
            throw SynologyClientError.authenticationFailed("DSM 凭据不存在，请编辑 NAS 后重新验证。")
        }
        return SynologyDockerConnection(
            host: record.host,
            port: record.port,
            scheme: record.nasProtocol,
            account: record.account,
            password: password,
            verifySSLCertificate: record.nasVerifySSLCertificate
        )
    }

    @MainActor
    private func nasControlPanelConnection(for deviceID: UUID) throws -> SynologyControlPanelConnection {
        guard let record = try fetchRecord(id: deviceID), record.kind == .nas else {
            throw SynologyClientError.connectionFailed("未找到本地 NAS 记录。")
        }
        guard let credentialIdentifier = record.credentialIdentifier,
              let password = try KeychainService.loadSecret(id: credentialIdentifier),
              !password.isEmpty else {
            record.connectionStatus = .needsVerification
            record.credentialNeedsVerification = true
            try modelContext.save()
            throw SynologyClientError.authenticationFailed("DSM 凭据不存在，请编辑 NAS 后重新验证。")
        }
        return SynologyControlPanelConnection(
            deviceID: record.deviceID,
            host: record.host,
            port: record.port,
            scheme: record.nasProtocol,
            account: record.account,
            password: password,
            verifySSLCertificate: record.nasVerifySSLCertificate
        )
    }

    @MainActor
    private func updateNASDockerContainers(deviceID: UUID, containers: [DockerContainerSummary]) {
        do {
            guard let record = try fetchRecord(id: deviceID), record.kind == .nas else { return }
            record.applyNASDockerContainers(containers)
            try modelContext.save()
            handleDeviceUpdated(record.dashboardDevice)
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func performServerDockerAction(
        device: DashboardDevice,
        container: DockerContainerSummary,
        action: ServerDockerContainerAction,
        lines: Int
    ) async throws -> ServerDockerActionResult {
        guard let record = try fetchRecord(id: device.id), record.kind == .server else {
            throw ServeraSSHError.connectionFailed("未找到本地服务器记录。")
        }
        guard let credentialIdentifier = record.credentialIdentifier,
              let credential = try KeychainService.loadCredentialBundle(id: credentialIdentifier) else {
            record.connectionStatus = .needsVerification
            record.credentialNeedsVerification = true
            try modelContext.save()
            throw ServeraSSHError.connectionFailed("服务器凭据不存在，请编辑连接后重新验证。")
        }

        let request = SSHConnectionRequest(
            host: record.host,
            port: record.port,
            username: record.account,
            authenticationKind: record.authenticationKind,
            credential: credential,
            acceptUnknownHostKey: false,
            networkMode: .direct
        )
        let target = serverDockerTarget(for: container)
        guard !target.isEmpty else {
            throw ServeraSSHError.commandFailed("容器标识为空，请刷新后重试。")
        }

        // 服务器 Docker 使用 SSH，不走 Docker HTTP API。每个修改动作后都会重新采集，
        // UI 展示服务器读回状态，而不是本地乐观切换。
        if action == .refresh {
            let containers = try await refreshServerDockerContainers(record: record, request: request)
            return ServerDockerActionResult(containers: containers, logText: nil)
        }

        let command = serverDockerCommand(action: action, target: target, lines: lines, canUseSudoPassword: record.authenticationKind == .password && credential.password?.isEmpty == false)
        let standardInput = serverDockerStandardInput(for: record.authenticationKind, credential: credential)
        let result = try await SSHConnectionService.shared.executeCommand(
            request: request,
            command: command,
            standardInput: standardInput
        )
        guard result.succeeded else {
            throw ServeraSSHError.commandFailed(serverDockerErrorMessage(from: result))
        }

        if action == .logs {
            return ServerDockerActionResult(
                containers: record.dashboardDevice.dockerContainers,
                logText: serverDockerLogText(from: result.standardOutput)
            )
        }

        let containers = try await refreshServerDockerContainers(record: record, request: request)
        return ServerDockerActionResult(containers: containers, logText: nil)
    }

    @MainActor
    private func refreshServerDockerContainers(
        record: ManagedDeviceRecord,
        request: SSHConnectionRequest
    ) async throws -> [DockerContainerSummary] {
        let outcome = try await SSHConnectionService.shared.collectLiveMetrics(request: request)
        record.applyLiveMetricsSnapshot(outcome)
        try modelContext.save()
        let updatedDevice = record.dashboardDevice
        handleDeviceUpdated(updatedDevice)
        if !updatedDevice.dockerDataAvailable {
            throw ServeraSSHError.commandFailed(nonEmptyDockerText(updatedDevice.dockerErrorMessage, fallback: "Docker 权限不足或服务不可用。"))
        }
        return updatedDevice.dockerContainers
    }

    private func serverDockerTarget(for container: DockerContainerSummary) -> String {
        let containerID = container.containerID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !containerID.isEmpty { return containerID }
        return container.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func serverDockerStandardInput(
        for authenticationKind: ServerAuthenticationKind,
        credential: DeviceCredentialBundle
    ) -> String {
        guard authenticationKind == .password,
              let password = credential.password,
              !password.isEmpty else {
            return ""
        }
        // 只通过 stdin 传给 sudo，绝不能拼进 command，
        // 因为命令字符串可能进入诊断信息或崩溃日志。
        return "\(password)\n"
    }

    private func serverDockerCommand(
        action: ServerDockerContainerAction,
        target: String,
        lines: Int,
        canUseSudoPassword: Bool
    ) -> String {
        let target = shellQuoted(target)
        let safeLines = max(20, min(lines, 1000))
        let sudoMode = canUseSudoPassword ? "password" : "noninteractive"

        switch action {
        case .start, .stop, .restart:
            let dockerAction: String
            switch action {
            case .start: dockerAction = "start"
            case .stop: dockerAction = "stop"
            case .restart: dockerAction = "restart"
            case .logs, .refresh: dockerAction = ""
            }
            return """
            target=\(target)
            action=\(shellQuoted(dockerAction))
            sudo_mode=\(shellQuoted(sudoMode))
            err=$(mktemp 2>/dev/null || echo /tmp/servera_server_docker_err_$$)
            if docker "$action" "$target" >/dev/null 2>"$err"; then
              rm -f "$err"
              exit 0
            fi
            if command -v sudo >/dev/null 2>&1; then
              if [ "$sudo_mode" = "password" ]; then
                if sudo -S -p '' docker "$action" "$target" >/dev/null 2>>"$err"; then
                  rm -f "$err"
                  exit 0
                fi
              else
                if sudo -n docker "$action" "$target" >/dev/null 2>>"$err"; then
                  rm -f "$err"
                  exit 0
                fi
              fi
            fi
            cat "$err" >&2
            rm -f "$err"
            exit 1
            """
        case .logs:
            // 标记用于只提取 docker logs 输出，即使 sudo 或 shell 错误在前后写入额外文本。
            return """
            target=\(target)
            lines=\(safeLines)
            sudo_mode=\(shellQuoted(sudoMode))
            out=$(mktemp 2>/dev/null || echo /tmp/servera_server_docker_log_$$)
            err=$(mktemp 2>/dev/null || echo /tmp/servera_server_docker_log_err_$$)
            if docker logs --tail "$lines" --timestamps "$target" >"$out" 2>"$err"; then
              printf '__SERVERA_LOG_BEGIN__\\n'
              cat "$out"
              printf '\\n__SERVERA_LOG_END__\\n'
              rm -f "$out" "$err"
              exit 0
            fi
            if command -v sudo >/dev/null 2>&1; then
              if [ "$sudo_mode" = "password" ]; then
                if sudo -S -p '' docker logs --tail "$lines" --timestamps "$target" >"$out" 2>>"$err"; then
                  printf '__SERVERA_LOG_BEGIN__\\n'
                  cat "$out"
                  printf '\\n__SERVERA_LOG_END__\\n'
                  rm -f "$out" "$err"
                  exit 0
                fi
              else
                if sudo -n docker logs --tail "$lines" --timestamps "$target" >"$out" 2>>"$err"; then
                  printf '__SERVERA_LOG_BEGIN__\\n'
                  cat "$out"
                  printf '\\n__SERVERA_LOG_END__\\n'
                  rm -f "$out" "$err"
                  exit 0
                fi
              fi
            fi
            cat "$err" >&2
            rm -f "$out" "$err"
            exit 1
            """
        case .refresh:
            return ""
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private func serverDockerLogText(from output: String) -> String {
        guard let begin = output.range(of: "__SERVERA_LOG_BEGIN__"),
              let end = output.range(of: "__SERVERA_LOG_END__", range: begin.upperBound..<output.endIndex) else {
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(output[begin.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func serverDockerErrorMessage(from result: SSHCommandExecutionResult) -> String {
        let raw = [result.standardError, result.standardOutput]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = raw.lowercased()
        if lowered.contains("permission denied")
            || lowered.contains("docker.sock")
            || lowered.contains("sudo")
            || lowered.contains("not in the sudoers") {
            return "Docker 权限不足或 sudo 不可用，请检查用户是否在 docker 组，或确认保存的 SSH 密码可用于 sudo。"
        }
        if lowered.contains("no such container") || lowered.contains("not found") {
            return "容器不存在，请刷新后重试。"
        }
        if lowered.contains("cannot connect to the docker daemon") {
            return "Docker 服务不可用，请检查服务器 Docker 是否正在运行。"
        }
        return nonEmptyDockerText(raw, fallback: "Docker 操作失败，请刷新后重试。")
    }

    private func nonEmptyDockerText(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    @MainActor
    private func updateNASControlPanelSnapshot(deviceID: UUID, snapshot: NASControlPanelSnapshot) {
        do {
            guard let record = try fetchRecord(id: deviceID), record.kind == .nas else { return }
            record.synologyControlPanelSnapshot = snapshot
            record.updatedAt = .now
            try modelContext.save()
            handleDeviceUpdated(record.dashboardDevice)
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func updateNASAccountIfNeeded(deviceID: UUID, oldName: String, newName: String) {
        do {
            guard let record = try fetchRecord(id: deviceID), record.kind == .nas else { return }
            guard record.account == oldName, oldName != newName else { return }
            record.account = newName
            record.updatedAt = .now
            try modelContext.save()
            handleDeviceUpdated(record.dashboardDevice)
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func refreshNAS(_ device: DashboardDevice) async {
        guard !refreshingDeviceIDs.contains(device.id) else { return }
        refreshingDeviceIDs.insert(device.id)
        defer {
            refreshingDeviceIDs.remove(device.id)
        }

        do {
            guard let record = try fetchRecord(id: device.id), record.kind == .nas else { return }
            guard let credentialIdentifier = record.credentialIdentifier,
                  let password = try KeychainService.loadSecret(id: credentialIdentifier),
                  !password.isEmpty else {
                record.connectionStatus = .needsVerification
                record.credentialNeedsVerification = true
                try modelContext.save()
                throw SynologyClientError.authenticationFailed("DSM 凭据不存在，请重新添加或恢复账号。")
            }

            let request = SynologyConnectionRequest(
                host: record.host,
                port: record.port,
                scheme: record.nasProtocol,
                account: record.account,
                password: password,
                verifySSLCertificate: record.nasVerifySSLCertificate
            )
            let outcome = try await SynologyClient.shared.validateAndCollect(request: request)
            record.applySynologySnapshot(outcome)
            if let snapshot = try? await SynologyControlPanelService(
                connection: SynologyControlPanelConnection(
                    deviceID: record.deviceID,
                    host: record.host,
                    port: record.port,
                    scheme: record.nasProtocol,
                    account: record.account,
                    password: password,
                    verifySSLCertificate: record.nasVerifySSLCertificate
                )
            ).collectSnapshot() {
                record.synologyControlPanelSnapshot = snapshot
            }
            try modelContext.save()
            handleDeviceUpdated(record.dashboardDevice)
        } catch let error where error.isRefreshCancellation {
            return
        } catch SynologyClientError.sessionExpired {
            if let record = try? fetchRecord(id: device.id) {
                record.connectionStatus = .needsVerification
                record.credentialNeedsVerification = true
                try? modelContext.save()
            }
            actionError = SynologyClientError.sessionExpired.localizedDescription
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func deleteDevice(_ device: DashboardDevice) {
        do {
            guard let record = try fetchRecord(id: device.id) else { return }
            let wasServer = record.kind == .server
            let remainingSingleNAS = remainingSingleNASDevice(afterDeleting: device)
            // 删除记录时一并删除 Keychain 内容，避免留下孤立密钥。
            if let credentialIdentifier = record.credentialIdentifier {
                KeychainService.deleteSecret(id: credentialIdentifier)
            }
            modelContext.delete(record)
            if wasServer {
                normalizeServerOrder(excluding: device.id)
            }
            try modelContext.save()
            recentlyAddedDevices.removeAll { $0.id == device.id }
            navigationPath.removeAll { $0.deviceID == device.id }
            refreshRemainingSingleNASIfNeeded(remainingSingleNAS)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func remainingSingleNASDevice(afterDeleting deletedDevice: DashboardDevice) -> DashboardDevice? {
        let remainingNAS = visibleDevices.filter { $0.kind == .nas && $0.id != deletedDevice.id }
        guard remainingNAS.count == 1 else { return nil }
        return remainingNAS.first
    }

    private func refreshRemainingSingleNASIfNeeded(_ device: DashboardDevice?) {
        guard let device else { return }
        normalizeLegacyNASDockerErrorIfNeeded(deviceID: device.id)
        Task {
            await refreshNAS(device)
        }
    }

    private func normalizeLegacyNASDockerErrorIfNeeded(deviceID: UUID) {
        // 旧版本可能持久化了原始 DSM Docker 114 错误。
        // 刷新剩余单台 NAS 前先归一化，避免页面闪出过期技术错误。
        guard let record = try? fetchRecord(id: deviceID), record.kind == .nas else { return }
        let error = record.dockerErrorMessage
        guard error.localizedCaseInsensitiveContains("SYNO.Docker.Container"), error.contains("114") else { return }
        record.dockerDataAvailable = false
        record.dockerErrorMessage = "Container Manager 状态正在重新读取，请下拉刷新后查看。"
        record.updatedAt = .now
        try? modelContext.save()
        handleDeviceUpdated(record.dashboardDevice)
    }

    private func fetchRecord(id: UUID) throws -> ManagedDeviceRecord? {
        let descriptor = FetchDescriptor<ManagedDeviceRecord>(
            predicate: #Predicate { $0.deviceID == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func orderedIndex(for id: UUID) -> Int? {
        if let record = deviceRecords.first(where: { $0.deviceID == id }) {
            return record.orderIndex
        }
        return recentlyAddedDevices.firstIndex(where: { $0.id == id }).map { deviceRecords.count + $0 }
    }

    private func orderedServerRecords() -> [ManagedDeviceRecord] {
        deviceRecords
            .filter { $0.kind == .server && $0.isVisible && !$0.isDocumentationPlaceholder }
            .sorted {
                if $0.orderIndex == $1.orderIndex {
                    return $0.createdAt < $1.createdAt
                }
                return $0.orderIndex < $1.orderIndex
            }
    }

    private func normalizeServerOrder(excluding deletedID: UUID? = nil) {
        // 删除后保持 orderIndex 连续。早期稀疏排序会让列表和星群顺序不一致。
        let records = orderedServerRecords().filter { $0.deviceID != deletedID }
        for (index, record) in records.enumerated() {
            record.orderIndex = index
            record.updatedAt = .now
        }
    }
}

private extension Error {
    var isRefreshCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        if let sshError = self as? ServeraSSHError { return sshError.isCancellation }
        return localizedDescription.localizedCaseInsensitiveContains("cancel")
            || localizedDescription.contains("取消")
    }
}

struct ServerEditSelection: Identifiable {
    let id: UUID
}

struct NASEditSelection: Identifiable {
    let id: UUID
}

struct NASFileBrowserSelection: Identifiable {
    let id = UUID()
    let device: DashboardDevice
    let volume: SynologyStorageVolume
    let connection: SynologyFileConnection
}

struct NASDockerContainerSelection: Identifiable {
    let id = UUID()
    let device: DashboardDevice
    let container: DockerContainerSummary
    let connection: SynologyDockerConnection
}

enum RootRoute: Hashable {
    case device(DashboardDevice)
    case nasControlPanel(NASControlPanelRoute)
    case serverDocker(DashboardDevice)

    var deviceID: UUID {
        switch self {
        case .device(let device):
            return device.id
        case .nasControlPanel(let route):
            return route.device.id
        case .serverDocker(let device):
            return device.id
        }
    }

    static func == (lhs: RootRoute, rhs: RootRoute) -> Bool {
        switch (lhs, rhs) {
        case (.device(let lhsDevice), .device(let rhsDevice)):
            return lhsDevice.id == rhsDevice.id
        case (.nasControlPanel(let lhsRoute), .nasControlPanel(let rhsRoute)):
            return lhsRoute == rhsRoute
        case (.serverDocker(let lhsDevice), .serverDocker(let rhsDevice)):
            return lhsDevice.id == rhsDevice.id
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .device(let device):
            hasher.combine("device")
            hasher.combine(device.id)
        case .nasControlPanel(let route):
            hasher.combine("nasControlPanel")
            route.hash(into: &hasher)
        case .serverDocker(let device):
            hasher.combine("serverDocker")
            hasher.combine(device.id)
        }
    }
}

struct NASControlPanelRoute: Hashable {
    let device: DashboardDevice
    let module: NASControlPanelModule
    let connection: SynologyControlPanelConnection

    func updatingDevice(_ device: DashboardDevice) -> NASControlPanelRoute {
        NASControlPanelRoute(device: device, module: module, connection: connection)
    }

    static func == (lhs: NASControlPanelRoute, rhs: NASControlPanelRoute) -> Bool {
        lhs.device.id == rhs.device.id && lhs.module == rhs.module
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(device.id)
        hasher.combine(module)
    }
}

struct ServeraBackground: View {
    @Environment(\.serveraTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: backgroundColors,
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(theme.tint.opacity(colorScheme == .dark ? 0.22 : 0.42))
                .frame(width: 260, height: 260)
                .blur(radius: 52)
                .offset(x: -90, y: -70)
        }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill((colorScheme == .dark ? theme.sky : theme.leafSoft).opacity(colorScheme == .dark ? 0.16 : 0.76))
                .frame(width: 220, height: 220)
                .blur(radius: 54)
                .offset(x: 80, y: -50)
        }
    }

    private var backgroundColors: [Color] {
        if colorScheme == .dark {
            [
                Color(red: 0.055, green: 0.050, blue: 0.065),
                theme.accentDeep.opacity(0.24),
                Color(red: 0.020, green: 0.022, blue: 0.030)
            ]
        } else {
            [theme.background, theme.tintSoft, .white]
        }
    }
}

struct ServeraTabBar: View {
    @Environment(\.serveraTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedTab: AppTab
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                ServeraTabButton(tab: tab, selectedTab: $selectedTab, namespace: namespace)
            }
        }
        .padding(7)
        .background {
            Capsule()
                .fill(.white.opacity(colorScheme == .dark ? 0.10 : 0.62))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.72), lineWidth: 1))
                .shadow(color: theme.accent.opacity(0.24), radius: 28, y: 12)
        }
    }
}

struct BottomSafeAreaMist: View {
    @Environment(\.serveraTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.safeAreaInsets.bottom + 150

            VStack(spacing: 0) {
                Spacer()
                ZStack {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: mistMidColor, location: 0.25),
                            .init(color: mistBaseColor.opacity(0.94), location: 0.64),
                            .init(color: mistBaseColor.opacity(0.98), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .blur(radius: 0.5)

                    Rectangle()
                        .fill(.ultraThinMaterial.opacity(0.62))
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black.opacity(0.55), location: 0.42),
                                    .init(color: .black, location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .frame(height: height)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var mistMidColor: Color {
        colorScheme == .dark ? theme.accentDeep.opacity(0.18) : theme.tintSoft.opacity(0.62)
    }

    private var mistBaseColor: Color {
        colorScheme == .dark ? Color(red: 0.020, green: 0.022, blue: 0.030) : .white
    }
}

struct ServeraTabButton: View {
    @Environment(\.serveraTheme) private var theme
    let tab: AppTab
    @Binding var selectedTab: AppTab
    let namespace: Namespace.ID

    private var isSelected: Bool {
        selectedTab == tab
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(tab.rawValue)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(isSelected ? theme.accentDeep : Color.primary.opacity(0.72))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                if isSelected {
                    LiquidGlassCapsule(namespace: namespace)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct LiquidGlassCapsule: View {
    @Environment(\.serveraTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    let namespace: Namespace.ID

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [.white.opacity(colorScheme == .dark ? 0.18 : 0.92), theme.tintSoft.opacity(colorScheme == .dark ? 0.18 : 0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(Capsule().stroke(.white.opacity(colorScheme == .dark ? 0.22 : 0.86), lineWidth: 1))
            .shadow(color: theme.accent.opacity(0.22), radius: 16, y: 8)
            .matchedGeometryEffect(id: "selected-tab-glass", in: namespace)
            .modifier(LiquidGlassIfAvailable())
    }
}

struct LiquidGlassIfAvailable: ViewModifier {
    @Environment(\.serveraTheme) private var theme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(theme.tint.opacity(0.24)).interactive(), in: .capsule)
        } else {
            content
        }
    }
}
