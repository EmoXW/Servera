import SwiftUI

// MARK: - NAS 首页与详情
// NAS 页有两种模式：只有一台 NAS 时直接展示仪表盘，多台 NAS 时展示列表。
// 控制面板、存储、文件和 NAS Docker 都只属于 NAS，不进入 Server/Docker 页。

struct NASView: View {
    let devices: [DashboardDevice]
    let refreshingDeviceIDs: Set<UUID>
    let onRefresh: (DashboardDevice) async -> Void
    let onEdit: (DashboardDevice) -> Void
    let onDelete: (DashboardDevice) -> Void
    let onOpenFiles: (DashboardDevice, SynologyStorageVolume) -> Void
    let onOpenControlPanel: (DashboardDevice, NASControlPanelModule) -> Void
    let onOpenDockerContainer: (DashboardDevice, DockerContainerSummary) -> Void
    let onSelect: (DashboardDevice) -> Void
    let onAddNAS: () -> Void
    @State private var showAllDockerContainersForSingleNAS = false

    private var nasDevices: [DashboardDevice] {
        devices.filter { $0.kind == .nas }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                HeaderBar(title: "NAS", trailing: "plus", trailingAction: onAddNAS)

                if nasDevices.count == 1, let primaryNAS = nasDevices.first {
                    NASHeaderCard(
                        device: primaryNAS,
                        isRefreshing: refreshingDeviceIDs.contains(primaryNAS.id),
                        onRefresh: {
                            Task { await onRefresh(primaryNAS) }
                        },
                        onEdit: {
                            onEdit(primaryNAS)
                        },
                        onDelete: {
                            onDelete(primaryNAS)
                        }
                    )
                    NASStatusSections(device: primaryNAS) { volume in
                        onOpenFiles(primaryNAS, volume)
                    } onOpenControlPanel: { module in
                        onOpenControlPanel(primaryNAS, module)
                    }
                    NASDockerOverviewCard(
                        device: primaryNAS,
                        showsAllContainers: showAllDockerContainersForSingleNAS,
                        onShowAll: {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                                showAllDockerContainersForSingleNAS = true
                            }
                        },
                        onSelectContainer: { container in
                            onOpenDockerContainer(primaryNAS, container)
                        }
                    )
                } else if nasDevices.count > 1 {
                    NASDeviceList(
                        devices: nasDevices,
                        refreshingDeviceIDs: refreshingDeviceIDs,
                        onRefresh: onRefresh,
                        onEdit: onEdit,
                        onDelete: onDelete,
                        onSelect: onSelect
                    )
                } else {
                    ServeraCard(cornerRadius: 30) {
                        VStack(spacing: 12) {
                            NASIcon()
                                .scaleEffect(0.82)
                            Text("还没有 NAS")
                                .font(.system(size: 24, weight: .black))
                            Text("添加群晖 NAS 后，这里会显示 DSM 状态、存储抽屉和基础资源。")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.serveraTextSecondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
        .refreshable {
            if let primaryNAS = nasDevices.first {
                await onRefresh(primaryNAS)
            } else {
                try? await Task.sleep(for: .milliseconds(220))
            }
        }
    }
}

struct NASHeaderCard: View {
    let device: DashboardDevice
    var isRefreshing = false
    var onRefresh: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        ServeraCard {
            HStack(spacing: 16) {
                NASIcon()
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayName)
                        .foregroundStyle(Color.serveraTextSecondary)
                    Text(statusTitle)
                        .font(.system(size: 22, weight: .heavy))
                    HStack(spacing: 7) {
                        NASInfoBadge(
                            text: device.credentialNeedsVerification ? "待验证" : "免费 NAS 管理",
                            color: device.credentialNeedsVerification ? .serveraAmber : .serveraLeaf
                        )
                        if !device.systemVersion.isEmpty {
                            NASInfoBadge(text: compactSystemVersion, color: .serveraAccentDeep)
                        }
                    }
                    .frame(height: 32)
                }
                .layoutPriority(1)
                Spacer()
                if onRefresh != nil || onEdit != nil || onDelete != nil {
                    NASActionMenu(
                        isRefreshing: isRefreshing,
                        onRefresh: onRefresh,
                        onEdit: onEdit,
                        onDelete: onDelete
                    )
                }
            }
        }
    }

    private var displayName: String {
        device.systemName.isEmpty ? device.name : device.systemName
    }

    private var statusTitle: String {
        if device.credentialNeedsVerification { return "恢复后需要重新验证" }
        if device.diskDataAvailable || device.cpuDataAvailable { return "存储与服务正常" }
        return "等待 DSM 刷新"
    }

    private var compactSystemVersion: String {
        device.systemVersion
            .replacingOccurrences(of: " Update ", with: "-u")
            .replacingOccurrences(of: " update ", with: "-u")
    }
}

struct NASStatusSections: View {
    let device: DashboardDevice
    var onOpenVolume: ((SynologyStorageVolume) -> Void)?
    var onOpenControlPanel: ((NASControlPanelModule) -> Void)?

    var body: some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 14) {
            NASMetric(icon: "cpu", title: "CPU", value: device.cpuDataAvailable ? "\(device.cpu)%" : "-", tint: .white.opacity(0.66), accent: .serveraAccentDeep)
            NASMetric(icon: "memorychip", title: "内存", value: device.memoryDataAvailable ? "\(device.ram)%" : "-", tint: .serveraLeafSoft, accent: .serveraLeaf)
            NASMetric(icon: "arrow.up.arrow.down", title: "网络", value: networkText, tint: .serveraSky.opacity(0.18), accent: .serveraSky)
            NASMetric(icon: "thermometer.medium", title: "温度", value: temperatureText, tint: .serveraAmber.opacity(0.18), accent: .serveraAmber)
        }
        .frame(minHeight: 236)

        NASControlPanelCard(snapshot: device.nasControlPanelSnapshot) { module in
            onOpenControlPanel?(module)
        }

        if device.diskDataAvailable, !device.nasStorageVolumes.isEmpty {
            StorageSummaryCard(volumes: device.nasStorageVolumes, onOpenVolume: onOpenVolume)
        } else {
            ServeraCard(cornerRadius: 30) {
                VStack(alignment: .leading, spacing: 8) {
                    CardHeader(icon: "internaldrive", title: "存储", color: .serveraLeaf, trailing: "等待刷新")
                    Text(device.diskErrorMessage.nasVisibleError(fallback: "暂无存储数据"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.serveraTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var networkText: String {
        guard device.networkDataAvailable else { return "-" }
        let receive = device.networkReceiveText.replacingOccurrences(of: "/s", with: "")
        return "↓\(receive) ↑\(device.networkTransmitText)"
    }

    private var temperatureText: String {
        guard let temperature = device.cpuTemperatureCelsius else { return "-" }
        return "\(temperature)°C"
    }
}

private struct NASControlPanelCard: View {
    let snapshot: NASControlPanelSnapshot
    let onOpen: (NASControlPanelModule) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 18, weight: .black))
                Text("控制面板")
                    .font(.system(size: 20, weight: .black))
                    .lineLimit(1)
                Spacer()
                Text(freshnessText)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(Color.serveraAccentDeep)
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(NASControlPanelModule.visibleCases) { module in
                        NASControlPanelRowButton(
                            module: module,
                            snapshot: snapshot.module(module)
                        ) {
                            onOpen(module)
                        }
                        if module.id != NASControlPanelModule.visibleCases.last?.id {
                            Divider()
                                .overlay(Color.serveraBorder.opacity(0.46))
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white.opacity(0.76))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.serveraBorder.opacity(0.64), lineWidth: 1)
                )
                .shadow(color: Color.serveraAccent.opacity(0.10), radius: 18, y: 10)
        }
    }

    private var freshnessText: String {
        guard snapshot.collectedAt > .distantPast else { return "等待刷新" }
        let seconds = max(0, Int(Date().timeIntervalSince(snapshot.collectedAt)))
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(seconds / 60) 分钟前" }

        // 这里表示数据新鲜度，不是 NAS 运行时间。用持续时长展示，
        // 避免用户再把“今天 HH:mm”换算成多久前。
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return "\(days) 天 \(hours) 小时 \(minutes) 分前"
        }
        return "\(hours) 小时 \(minutes) 分前"
    }
}

private struct NASControlPanelRowButton: View {
    let module: NASControlPanelModule
    let snapshot: NASControlPanelModuleSnapshot
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(module.accentColor.opacity(0.14))
                    Image(systemName: module.systemImage)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(module.accentColor)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(module.title)
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Circle()
                            .fill(snapshot.available ? Color.serveraLeaf : Color.serveraAmber)
                            .frame(width: 6, height: 6)
                    }
                    Text(subtitle)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.serveraTextSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Color.serveraTextSecondary.opacity(0.58))
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        guard module == .terminalSNMP else {
            return snapshot.available ? snapshot.summary : snapshot.statusText
        }
        let ssh = snapshot.rows.first(where: { $0.title == "SSH" })?.value
        let telnet = snapshot.rows.first(where: { $0.title == "Telnet" })?.value
        let port = snapshot.rows.first(where: { $0.title == "SSH 端口" })?.value
        if let ssh, let telnet, let port {
            return "SSH \(ssh) · Telnet \(telnet) · 端口 \(port)"
        }
        return snapshot.available ? "终端机状态待刷新" : snapshot.statusText
    }
}

struct NASControlPanelDetailView: View {
    let device: DashboardDevice
    let initialModule: NASControlPanelModule
    let connection: SynologyControlPanelConnection
    let onSnapshotUpdated: (NASControlPanelSnapshot) -> Void
    let onAccountRenamed: (String, String) -> Void
    let onError: (String) -> Void

    @Environment(\.openURL) private var openURL
    @State private var selectedModule: NASControlPanelModule
    @State private var snapshot: NASControlPanelSnapshot
    @State private var isRefreshing = false
    @State private var isLoadingExternalAccess = false
    @State private var isLoadingUsersGroups = false
    @State private var isLoadingNetwork = false
    @State private var isLoadingTerminal = false
    @State private var savingExternalSection: String?
    @State private var savingNetworkSection: NASNetworkSaveSection?
    @State private var isSavingTerminal = false
    @State private var externalAccess: SynologyExternalAccessSnapshot?
    @State private var usersGroups: SynologyUsersGroupsSnapshot?
    @State private var networkSettings: SynologyNetworkSettingsSnapshot?
    @State private var terminalSettings: SynologyTerminalSettingsSnapshot?
    @State private var dsmExternalHostnameDraft = ""
    @State private var ddnsDrafts: [SynologyDDNSRecord] = []
    @State private var networkHostnameDraft = ""
    @State private var networkDNSDraft = ""
    @State private var proxyEnabledDraft = false
    @State private var proxyHostDraft = ""
    @State private var proxyPortDraft = ""
    @State private var proxyBypassLocalDraft = false
    @State private var terminalSSHDraft = false
    @State private var terminalTelnetDraft = false
    @State private var terminalPortDraft = ""
    @State private var pendingNetworkConfirmation: NASNetworkConfirmation?
    @State private var pendingTerminalConfirmation: NASTerminalConfirmation?
    @State private var localError: String?
    @State private var localSuccess: String?

    init(
        device: DashboardDevice,
        initialModule: NASControlPanelModule,
        connection: SynologyControlPanelConnection,
        onSnapshotUpdated: @escaping (NASControlPanelSnapshot) -> Void,
        onAccountRenamed: @escaping (String, String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.device = device
        self.initialModule = initialModule
        self.connection = connection
        self.onSnapshotUpdated = onSnapshotUpdated
        self.onAccountRenamed = onAccountRenamed
        self.onError = onError
        _selectedModule = State(initialValue: initialModule)
        _snapshot = State(initialValue: device.nasControlPanelSnapshot)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if selectedModule == .users {
                    usersDetailPage
                } else if selectedModule == .network {
                    networkDetailPage
                } else if selectedModule == .terminalSNMP {
                    terminalDetailPage
                } else {
                    detailCard
                }
                safetyCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 26)
        }
        .background(ServeraBackground().ignoresSafeArea())
        .overlay {
            ZStack {
                if let localSuccess {
                    NASControlPanelToast(message: localSuccess)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let confirmation = pendingNetworkConfirmation {
                    NASControlPanelConfirmOverlay(
                        title: confirmation.title,
                        message: confirmation.message,
                        confirmTitle: "确认保存",
                        onCancel: { pendingNetworkConfirmation = nil },
                        onConfirm: {
                            pendingNetworkConfirmation = nil
                            Task {
                                switch confirmation.kind {
                                case .network:
                                    await saveNetworkSettings()
                                case .proxy:
                                    await saveProxySettings()
                                }
                            }
                        }
                    )
                } else if let confirmation = pendingTerminalConfirmation {
                    NASControlPanelConfirmOverlay(
                        title: confirmation.title,
                        message: confirmation.message,
                        confirmTitle: "确认保存",
                        onCancel: { pendingTerminalConfirmation = nil },
                        onConfirm: {
                            pendingTerminalConfirmation = nil
                            Task { await saveTerminalSettings() }
                        }
                    )
                }
            }
        }
        .navigationTitle(selectedModule.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
            }
        }
        .task {
            if snapshot.collectedAt == .distantPast {
                await refresh()
            }
            if selectedModule == .externalAccess {
                await loadExternalAccessDetails()
            } else if selectedModule == .users {
                await loadUsersGroupsDetails()
            } else if selectedModule == .network {
                await loadNetworkDetails()
            } else if selectedModule == .terminalSNMP {
                await loadTerminalSettings()
            }
        }
        .alert("操作失败", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) {
            Button("知道了", role: .cancel) { localError = nil }
        } message: {
            Text(localError ?? "")
        }
    }

    private var networkDetailPage: some View {
        let moduleSnapshot = snapshot.module(.network)
        return VStack(alignment: .leading, spacing: 14) {
            NASNetworkHeroCard(
                title: selectedModule.title,
                subtitle: moduleSnapshot.available ? moduleSnapshot.summary : moduleSnapshot.errorMessage,
                icon: selectedModule.systemImage,
                color: selectedModule.accentColor,
                status: moduleSnapshot.available ? "可读取" : "不可用",
                isAvailable: moduleSnapshot.available
            )
            networkEditor(moduleSnapshot: moduleSnapshot)
            HStack(spacing: 10) {
                Button {
                    copyCurrentModule()
                } label: {
                    Label("复制信息", systemImage: "doc.on.doc")
                }
                .buttonStyle(NASControlPanelButtonStyle(color: .serveraLeaf))
                .disabled(moduleSnapshot.rows.isEmpty)

                Button {
                    openDSM()
                } label: {
                    Label("打开 DSM", systemImage: "safari")
                }
                .buttonStyle(NASControlPanelButtonStyle(color: .serveraAccentDeep))
            }
        }
    }

    private var usersDetailPage: some View {
        let moduleSnapshot = snapshot.module(.users)
        return VStack(alignment: .leading, spacing: 14) {
            NASNetworkHeroCard(
                title: "用户账号",
                subtitle: moduleSnapshot.available ? moduleSnapshot.summary : moduleSnapshot.errorMessage,
                icon: selectedModule.systemImage,
                color: selectedModule.accentColor,
                status: moduleSnapshot.available ? "可管理" : "不可用",
                isAvailable: moduleSnapshot.available
            )
            usersGroupsPanel
        }
    }

    private var terminalDetailPage: some View {
        let moduleSnapshot = snapshot.module(.terminalSNMP)
        return VStack(alignment: .leading, spacing: 14) {
            NASNetworkHeroCard(
                title: selectedModule.title,
                subtitle: terminalSummary(fallback: moduleSnapshot),
                icon: selectedModule.systemImage,
                color: selectedModule.accentColor,
                status: moduleSnapshot.available ? "可读取" : "不可用",
                isAvailable: moduleSnapshot.available
            )
            terminalEditor(moduleSnapshot: moduleSnapshot)
            HStack(spacing: 10) {
                Button {
                    copyCurrentModule()
                } label: {
                    Label("复制信息", systemImage: "doc.on.doc")
                }
                .buttonStyle(NASControlPanelButtonStyle(color: .serveraLeaf))
                .disabled(moduleSnapshot.rows.isEmpty)

                Button {
                    openDSM()
                } label: {
                    Label("打开 DSM", systemImage: "safari")
                }
                .buttonStyle(NASControlPanelButtonStyle(color: .serveraAccentDeep))
            }
        }
    }

    private var detailCard: some View {
        let moduleSnapshot = snapshot.module(selectedModule)
        return ServeraCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(selectedModule.accentColor.opacity(0.16))
                        Image(systemName: selectedModule.systemImage)
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(selectedModule.accentColor)
                    }
                    .frame(width: 54, height: 54)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(selectedModule.title)
                            .font(.system(size: 24, weight: .black))
                        Text(moduleSnapshot.available ? moduleSnapshot.summary : moduleSnapshot.errorMessage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.serveraTextSecondary)
                            .lineSpacing(3)
                    }
                    Spacer()
                    StatusPill(text: moduleSnapshot.available ? "可读取" : "不可用", color: moduleSnapshot.available ? .serveraLeaf : .serveraAmber)
                }

                if selectedModule == .users {
                    usersGroupsPanel
                } else if selectedModule == .externalAccess {
                    externalAccessEditor
                } else if selectedModule == .network {
                    networkEditor(moduleSnapshot: moduleSnapshot)
                } else if selectedModule == .terminalSNMP {
                    terminalEditor(moduleSnapshot: moduleSnapshot)
                } else if moduleSnapshot.rows.isEmpty {
                    Text(moduleSnapshot.errorMessage.isEmpty ? "等待 DSM 刷新" : moduleSnapshot.errorMessage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.serveraTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    VStack(spacing: 10) {
                        ForEach(supportedTerminalRows(in: moduleSnapshot)) { row in
                            NASControlPanelRowView(row: row)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        copyCurrentModule()
                    } label: {
                        Label("复制信息", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(NASControlPanelButtonStyle(color: .serveraLeaf))
                    .disabled(moduleSnapshot.rows.isEmpty)

                    Button {
                        openDSM()
                    } label: {
                        Label("打开 DSM", systemImage: "safari")
                    }
                    .buttonStyle(NASControlPanelButtonStyle(color: .serveraAccentDeep))
                }
            }
        }
    }

    private var usersGroupsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isLoadingUsersGroups {
                NASInlineLoadingRow(text: "正在读取用户与群组...")
            }

            if let usersGroups {
                NASControlListCard {
                    VStack(spacing: 0) {
                    if usersGroups.users.isEmpty {
                        NASControlEmptyLine(text: "没有读取到用户。")
                    } else {
                        ForEach(usersGroups.users) { user in
                            NavigationLink {
                                NASUserDetailView(
                                    user: user,
                                    snapshot: usersGroups,
                                    connection: connection,
                                    onSaved: { updated in
                                        self.usersGroups = updated
                                        await refresh()
                                    },
                                    onAccountRenamed: onAccountRenamed,
                                    onError: { message in
                                        localError = message
                                        onError(message)
                                    }
                                )
                            } label: {
                                NASUserListRow(user: user, currentAccount: connection.account)
                            }
                            .buttonStyle(.plain)
                            if user.id != usersGroups.users.last?.id {
                                Divider()
                                    .overlay(Color.serveraBorder.opacity(0.45))
                                    .padding(.leading, 72)
                            }
                        }
                    }
                }
                }
            } else if !isLoadingUsersGroups {
                NASControlEmptyLine(text: "等待读取用户与群组。")
            }
        }
    }

    private var externalAccessEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isLoadingExternalAccess {
                NASInlineLoadingRow(text: "正在读取外部访问设置...")
            }

            NASExternalAccessSection(title: "DSM 外部地址", icon: "link") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("例如 nas.example.com", text: $dsmExternalHostnameDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, weight: .bold))
                        .padding(12)
                        .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Button {
                        Task { await saveDSMExternalHostname() }
                    } label: {
                        Label(savingExternalSection == "dsm" ? "保存中" : "保存外部地址", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(NASControlPanelButtonStyle(color: .serveraAccentDeep))
                    .disabled(savingExternalSection != nil)
                }
            }

            NASExternalAccessSection(title: "DDNS", icon: "globe.asia.australia.fill") {
                VStack(spacing: 12) {
                    if ddnsDrafts.isEmpty {
                        Text("没有读取到 DDNS 记录。")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.serveraTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach($ddnsDrafts) { $record in
                            NASDDNSRecordEditor(
                                record: $record,
                                isSaving: savingExternalSection == record.id
                            ) {
                                Task { await saveDDNSRecord(record) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func networkEditor(moduleSnapshot: NASControlPanelModuleSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if isLoadingNetwork {
                NASInlineLoadingRow(text: "正在读取网络设置...")
            }

            if networkSettings == nil, !isLoadingNetwork {
                if moduleSnapshot.rows.isEmpty {
                    NASControlEmptyLine(text: moduleSnapshot.errorMessage.isEmpty ? "等待读取网络设置。" : moduleSnapshot.errorMessage)
                } else {
                    VStack(spacing: 10) {
                        ForEach(moduleSnapshot.rows) { row in
                            NASControlPanelRowView(row: row)
                        }
                    }
                }
            }

            NASNetworkSettingsSection(
                hostname: $networkHostnameDraft,
                dns: $networkDNSDraft,
                ip: networkSettings?.primaryIP ?? rowValue("IP", in: moduleSnapshot),
                gateway: networkSettings?.gateway ?? rowValue("网关", in: moduleSnapshot),
                interfaces: networkSettings?.interfaces ?? [],
                isSaving: savingNetworkSection == .network,
                canSave: hasNetworkChanges && savingNetworkSection == nil,
                onSave: confirmNetworkSave
            )

            NASProxySettingsSection(
                enabled: $proxyEnabledDraft,
                host: $proxyHostDraft,
                port: $proxyPortDraft,
                bypassLocal: $proxyBypassLocalDraft,
                isSaving: savingNetworkSection == .proxy,
                canSave: canSaveProxySettings && savingNetworkSection == nil,
                onSave: confirmProxySave
            )
        }
    }

    private func terminalEditor(moduleSnapshot: NASControlPanelModuleSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if isLoadingTerminal {
                NASInlineLoadingRow(text: "正在读取终端机设置...")
            }

            if terminalSettings == nil, !isLoadingTerminal {
                if moduleSnapshot.rows.isEmpty {
                    NASControlEmptyLine(text: moduleSnapshot.errorMessage.isEmpty ? "等待读取终端机设置。" : moduleSnapshot.errorMessage)
                } else {
                    VStack(spacing: 10) {
                        ForEach(moduleSnapshot.rows) { row in
                            NASControlPanelRowView(row: row)
                        }
                    }
                }
            }

            if terminalSettings != nil {
                NASTerminalSettingsSection(
                    sshEnabled: $terminalSSHDraft,
                    telnetEnabled: $terminalTelnetDraft,
                    sshPort: $terminalPortDraft,
                    isSaving: isSavingTerminal,
                    canSave: hasTerminalChanges && !isSavingTerminal,
                    onSave: confirmTerminalSave
                )
            }
        }
    }

    private var safetyCard: some View {
        ServeraCard(cornerRadius: 26) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(Color.serveraAmber)
                Text(safetyText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var safetyText: String {
        if selectedModule == .externalAccess {
            return "外部访问设置会真实写入 DSM。保存 DDNS 或 DSM 外部地址前，请确认域名、账号和 Token 正确。"
        }
        if selectedModule == .network {
            return "网络和代理设置会真实写入 DSM。错误的 DNS、网关、代理地址可能影响 NAS 联网或让 App 暂时断开，请确认后再保存。"
        }
        if selectedModule == .terminalSNMP {
            return "终端机设置会真实写入 DSM。修改 SSH、Telnet 或端口前，请确认不会影响当前 NAS 的远程管理。"
        }
        if selectedModule == .users {
            return "用户详情页支持真实修改登录账号、密码和用户群组。保存前会弹出确认，请谨慎操作内置账号和管理员账号。"
        }
        return "当前只读取状态，不会修改 DSM 系统设置。"
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let service = SynologyControlPanelService(connection: connection)
            let refreshed = try await service.collectSnapshot()
            snapshot = refreshed
            onSnapshotUpdated(refreshed)
        } catch let error where error.isNASControlPanelCancellation {
            return
        } catch {
            localError = error.localizedDescription
            onError(error.localizedDescription)
        }
    }

    private func loadExternalAccessDetails() async {
        guard !isLoadingExternalAccess else { return }
        isLoadingExternalAccess = true
        defer { isLoadingExternalAccess = false }
        do {
            let service = SynologyControlPanelService(connection: connection)
            let details = try await service.fetchExternalAccessDetails()
            applyExternalAccess(details)
        } catch let error where error.isNASControlPanelCancellation {
            return
        } catch {
            localError = error.localizedDescription
            onError(error.localizedDescription)
        }
    }

    private func loadUsersGroupsDetails() async {
        guard !isLoadingUsersGroups else { return }
        isLoadingUsersGroups = true
        defer { isLoadingUsersGroups = false }
        do {
            let service = SynologyControlPanelService(connection: connection)
            usersGroups = try await service.fetchUsersGroupsDetails()
        } catch let error where error.isNASControlPanelCancellation {
            return
        } catch {
            localError = error.localizedDescription
            onError(error.localizedDescription)
        }
    }

    private func loadNetworkDetails() async {
        guard !isLoadingNetwork else { return }
        isLoadingNetwork = true
        defer { isLoadingNetwork = false }
        do {
            let service = SynologyControlPanelService(connection: connection)
            let details = try await service.fetchNetworkDetails()
            applyNetworkSettings(details)
        } catch let error where error.isNASControlPanelCancellation {
            return
        } catch {
            localError = error.localizedDescription
            onError(error.localizedDescription)
        }
    }

    private func loadTerminalSettings() async {
        guard !isLoadingTerminal else { return }
        isLoadingTerminal = true
        defer { isLoadingTerminal = false }
        do {
            let details = try await SynologyControlPanelService(connection: connection)
                .fetchTerminalSettings()
            applyTerminalSettings(details)
        } catch let error where error.isNASControlPanelCancellation {
            return
        } catch {
            localError = error.localizedDescription
            onError(error.localizedDescription)
        }
    }

    private func saveDSMExternalHostname() async {
        savingExternalSection = "dsm"
        defer { savingExternalSection = nil }
        do {
            let details = try await SynologyControlPanelService(connection: connection)
                .saveDSMExternalHostname(dsmExternalHostnameDraft.trimmingCharacters(in: .whitespacesAndNewlines))
            applyExternalAccess(details)
            await refresh()
        } catch {
            localError = error.localizedDescription
        }
    }

    private func saveDDNSRecord(_ record: SynologyDDNSRecord) async {
        savingExternalSection = record.id
        defer { savingExternalSection = nil }
        do {
            let details = try await SynologyControlPanelService(connection: connection)
                .saveDDNSRecord(record)
            applyExternalAccess(details)
            await refresh()
        } catch {
            localError = error.localizedDescription
        }
    }

    private func confirmNetworkSave() {
        pendingNetworkConfirmation = NASNetworkConfirmation(
            kind: .network,
            title: "保存网络设置？",
            message: "这会真实修改 NAS 的主机名或 DNS。错误的网络设置可能影响 NAS 联网，甚至让 Servera 暂时无法连接当前 NAS。"
        )
    }

    private func confirmProxySave() {
        if proxyEnabledDraft {
            let host = proxyHostDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let port = proxyPortDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else {
                localError = "代理服务器地址不能为空。"
                return
            }
            guard let portNumber = Int(port), (1...65535).contains(portNumber) else {
                localError = "代理服务器端口必须是 1-65535。"
                return
            }
        }
        pendingNetworkConfirmation = NASNetworkConfirmation(
            kind: .proxy,
            title: "保存代理设置？",
            message: "这会真实修改 NAS 系统代理。代理地址或端口错误可能导致 DSM 套件、更新、外部访问等无法正常联网。"
        )
    }

    private func confirmTerminalSave() {
        let port = terminalPortDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let portNumber = Int(port), (1...65_535).contains(portNumber) else {
            localError = "SSH 端口必须是 1-65535。"
            return
        }
        let telnetWarning = terminalTelnetDraft
            ? "\n\nTelnet 是明文传输，建议只在可信内网临时使用。"
            : ""
        pendingTerminalConfirmation = NASTerminalConfirmation(
            title: "保存终端机设置？",
            message: "这会真实修改 NAS 的 SSH、Telnet 或 SSH 端口。错误端口可能导致 Servera 或管理员暂时无法远程连接当前 NAS。\(telnetWarning)"
        )
    }

    private func saveNetworkSettings() async {
        savingNetworkSection = .network
        defer { savingNetworkSection = nil }
        do {
            let updated = try await SynologyControlPanelService(connection: connection)
                .saveNetworkSettings(
                    hostname: networkHostnameDraft,
                    dnsServers: splitDNSDraft(networkDNSDraft)
            )
            applyNetworkSettings(updated)
            showSuccess("网络设置已保存")
            await refresh()
        } catch {
            localError = error.localizedDescription
            onError(error.localizedDescription)
        }
    }

    private func saveProxySettings() async {
        savingNetworkSection = .proxy
        defer { savingNetworkSection = nil }
        let submittedEnabled = proxyEnabledDraft
        let submittedHost = proxyHostDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedPort = proxyPortDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedBypassLocal = proxyBypassLocalDraft
        do {
            let updated = try await SynologyControlPanelService(connection: connection)
                .saveProxySettings(
                    enabled: submittedEnabled,
                    host: submittedHost,
                    port: submittedPort,
                    bypassLocal: submittedBypassLocal
                )
            applyNetworkSettings(updated)
            if !submittedEnabled {
                proxyEnabledDraft = false
                proxyHostDraft = submittedHost
                proxyPortDraft = submittedPort
                proxyBypassLocalDraft = submittedBypassLocal
            }
            showSuccess("代理设置已保存")
            if submittedEnabled {
                await refresh()
            }
        } catch {
            localError = error.localizedDescription
            onError(error.localizedDescription)
        }
    }

    private func saveTerminalSettings() async {
        let port = terminalPortDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let portNumber = Int(port), (1...65_535).contains(portNumber) else {
            localError = "SSH 端口必须是 1-65535。"
            return
        }
        isSavingTerminal = true
        defer { isSavingTerminal = false }
        do {
            let updated = try await SynologyControlPanelService(connection: connection)
                .saveTerminalSettings(
                    sshEnabled: terminalSSHDraft,
                    telnetEnabled: terminalTelnetDraft,
                    sshPort: portNumber
            )
            applyTerminalSettings(updated)
            showSuccess("终端机设置已保存")
            await refresh()
        } catch {
            localError = error.localizedDescription
            onError(error.localizedDescription)
        }
    }

    private func applyExternalAccess(_ details: SynologyExternalAccessSnapshot) {
        externalAccess = details
        dsmExternalHostnameDraft = details.dsmExternalHostname
        ddnsDrafts = details.ddnsRecords
    }

    private func applyNetworkSettings(_ details: SynologyNetworkSettingsSnapshot) {
        networkSettings = details
        networkHostnameDraft = details.hostname
        networkDNSDraft = details.dnsServers.joined(separator: ", ")
        proxyEnabledDraft = details.proxyEnabled
        proxyHostDraft = details.proxyHost
        proxyPortDraft = details.proxyPort
        proxyBypassLocalDraft = details.proxyBypassLocal
    }

    private func showSuccess(_ message: String) {
        localSuccess = message
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            await MainActor.run {
                if localSuccess == message {
                    localSuccess = nil
                }
            }
        }
    }

    private func applyTerminalSettings(_ details: SynologyTerminalSettingsSnapshot) {
        terminalSettings = details
        terminalSSHDraft = details.sshEnabled
        terminalTelnetDraft = details.telnetEnabled
        terminalPortDraft = "\(details.sshPort)"
    }

    private var hasNetworkChanges: Bool {
        guard let networkSettings else { return !networkHostnameDraft.isEmpty || !networkDNSDraft.isEmpty }
        return networkHostnameDraft.trimmingCharacters(in: .whitespacesAndNewlines) != networkSettings.hostname
            || splitDNSDraft(networkDNSDraft) != networkSettings.dnsServers
    }

    private var hasProxyChanges: Bool {
        guard let networkSettings else {
            return proxyEnabledDraft || !proxyHostDraft.isEmpty || !proxyPortDraft.isEmpty || proxyBypassLocalDraft
        }
        return proxyEnabledDraft != networkSettings.proxyEnabled
            || proxyHostDraft.trimmingCharacters(in: .whitespacesAndNewlines) != networkSettings.proxyHost
            || proxyPortDraft.trimmingCharacters(in: .whitespacesAndNewlines) != networkSettings.proxyPort
            || proxyBypassLocalDraft != networkSettings.proxyBypassLocal
    }

    private var canSaveProxySettings: Bool {
        if hasProxyChanges { return true }
        return !proxyHostDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !proxyPortDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || proxyBypassLocalDraft
    }

    private var hasTerminalChanges: Bool {
        guard let terminalSettings else { return terminalSSHDraft || terminalTelnetDraft || !terminalPortDraft.isEmpty }
        return terminalSSHDraft != terminalSettings.sshEnabled
            || terminalTelnetDraft != terminalSettings.telnetEnabled
            || terminalPortDraft.trimmingCharacters(in: .whitespacesAndNewlines) != "\(terminalSettings.sshPort)"
    }

    private func terminalSummary(fallback moduleSnapshot: NASControlPanelModuleSnapshot) -> String {
        guard let terminalSettings else {
            let ssh = moduleSnapshot.rows.first(where: { $0.title == "SSH" })?.value
            let telnet = moduleSnapshot.rows.first(where: { $0.title == "Telnet" })?.value
            let port = moduleSnapshot.rows.first(where: { $0.title == "SSH 端口" })?.value
            if let ssh, let telnet, let port {
                return "SSH \(ssh) · Telnet \(telnet) · 端口 \(port)"
            }
            return moduleSnapshot.available ? "终端机状态待刷新" : moduleSnapshot.errorMessage
        }
        return "SSH \(terminalSettings.sshEnabled ? "已开启" : "未开启") · Telnet \(terminalSettings.telnetEnabled ? "已开启" : "未开启") · 端口 \(terminalSettings.sshPort)"
    }

    private func supportedTerminalRows(in snapshot: NASControlPanelModuleSnapshot) -> [NASControlPanelRow] {
        snapshot.rows.filter { row in
            row.title == "SSH" || row.title == "Telnet" || row.title == "SSH 端口"
        }
    }

    private func splitDNSDraft(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",; \n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func rowValue(_ title: String, in snapshot: NASControlPanelModuleSnapshot) -> String {
        snapshot.rows.first(where: { $0.title == title })?.value ?? "-"
    }

    private func copyCurrentModule() {
        let moduleSnapshot = snapshot.module(selectedModule)
        let rows = moduleSnapshot.rows.map { "\($0.title)：\($0.value)" }.joined(separator: "\n")
        UIPasteboard.general.string = "\(selectedModule.title)\n\(rows)"
    }

    private func openDSM() {
        var components = URLComponents()
        components.scheme = connection.scheme.rawValue
        components.host = connection.host
        components.port = connection.port
        if let url = components.url {
            openURL(url)
        }
    }
}

private struct NASControlPanelRowView: View {
    let row: NASControlPanelRow

    var body: some View {
        HStack(spacing: 12) {
            Text(row.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.serveraTextSecondary)
                .frame(width: 74, alignment: .leading)
            Text(row.value)
                .font(.system(size: 14, weight: .heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.serveraBorder.opacity(0.45), lineWidth: 1)
        )
    }
}

private struct NASInlineLoadingRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.serveraTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct NASControlEmptyLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.serveraTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct NASUserListRow: View {
    let user: SynologyNASUser
    let currentAccount: String

    var body: some View {
        HStack(spacing: 12) {
            StatusPill(text: isEnabled ? "正常" : "停用", color: isEnabled ? .serveraLeaf : .red)
                .frame(width: 54, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(user.name)
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    if user.name == currentAccount {
                        StatusPill(text: "当前", color: .serveraAccentDeep)
                    }
                    if user.groupNames.contains("administrators") {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Color.serveraAmber)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .lineLimit(1)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color.serveraTextSecondary.opacity(0.72))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 70)
        .contentShape(Rectangle())
    }

    private var isEnabled: Bool {
        user.isEnabled ?? !["admin", "guest"].contains(user.name.lowercased())
    }

    private var subtitle: String {
        if !user.fullName.isEmpty { return user.fullName }
        if !user.description.isEmpty { return user.description }
        return user.groupNames.isEmpty ? "DSM 用户" : user.groupNames.joined(separator: " / ")
    }
}

private struct NASControlListCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white.opacity(0.78))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.62), lineWidth: 1)
                )
                .shadow(color: Color.serveraAccent.opacity(0.08), radius: 16, y: 8)
        }
    }
}

private struct NASGroupListRow: View {
    let group: SynologyNASGroup

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(iconColor.opacity(0.14))
                Image(systemName: group.name == "administrators" ? "person.3.fill" : "person.2.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 5) {
                Text(group.name)
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text(group.description.isEmpty ? "DSM 群组" : group.description)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .lineLimit(1)
            }

            Spacer()
            StatusPill(text: "\(group.memberNames.count) 人", color: .serveraLeaf)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 74)
        .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.serveraBorder.opacity(0.42), lineWidth: 1)
        )
    }

    private var iconColor: Color {
        group.name == "administrators" ? .serveraAccentDeep : .serveraSky
    }
}

private enum NASUserEditorTab: String, CaseIterable, Identifiable {
    case account
    case password
    case groups

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: "账号名"
        case .password: "密码"
        case .groups: "用户群组"
        }
    }
}

private enum NASNetworkSaveSection: String {
    case network
    case proxy
}

private struct NASNetworkConfirmation: Identifiable {
    let id = UUID()
    let kind: NASNetworkSaveSection
    let title: String
    let message: String
}

private struct NASTerminalConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct NASControlPanelToast: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(Color.serveraLeaf)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(.white.opacity(0.92))
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.serveraLeaf.opacity(0.28), lineWidth: 1))
                    .shadow(color: Color.serveraLeaf.opacity(0.16), radius: 16, y: 8)
            }
            .padding(.horizontal, 24)
    }
}

private struct NASControlPanelConfirmOverlay: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(Color.serveraAmber)
                        .frame(width: 34, height: 34)
                        .background(Color.serveraAmber.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(title)
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(Color.primary)
                    Spacer()
                }

                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text("取消")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NASConfirmOverlayButtonStyle(color: Color.serveraTextSecondary, isDestructive: false))

                    Button(action: onConfirm) {
                        Text(confirmTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NASConfirmOverlayButtonStyle(color: Color.serveraAccentDeep, isDestructive: true))
                }
                .padding(.top, 2)
            }
            .padding(18)
            .frame(maxWidth: 318)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.white.opacity(0.94))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.70), lineWidth: 1)
                    )
                    .shadow(color: Color.serveraAccent.opacity(0.18), radius: 24, y: 12)
            }
            .padding(.horizontal, 24)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: title)
    }
}

private struct NASConfirmOverlayButtonStyle: ButtonStyle {
    let color: Color
    let isDestructive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(isDestructive ? .white : color)
            .padding(.vertical, 12)
            .background(
                isDestructive
                    ? color.opacity(configuration.isPressed ? 0.82 : 0.94)
                    : color.opacity(configuration.isPressed ? 0.16 : 0.10),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
    }
}

private struct NASUserDetailView: View {
    let user: SynologyNASUser
    let snapshot: SynologyUsersGroupsSnapshot?
    let connection: SynologyControlPanelConnection
    let onSaved: (SynologyUsersGroupsSnapshot) async -> Void
    let onAccountRenamed: (String, String) -> Void
    let onError: (String) -> Void

    @State private var details: SynologyUsersGroupsSnapshot?
    @State private var isLoading = false
    @State private var savingTab: NASUserEditorTab?
    @State private var localError: String?
    @State private var pendingRenameConfirmation: NASUserRenameConfirmation?
    @State private var pendingPasswordConfirmation: NASUserPasswordConfirmation?

    @State private var accountName = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var selectedGroups: Set<String> = []
    @State private var baselineAccountName = ""
    @State private var baselineGroups: Set<String> = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                if isLoading {
                    NASInlineLoadingRow(text: "正在读取 \(user.name) 的设置...")
                }
                accountPasswordSection
                groupsTab
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 30)
        }
        .background(ServeraBackground().ignoresSafeArea())
        .navigationTitle(user.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadDetails() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoading || savingTab != nil)
            }
        }
        .task {
            apply(snapshot ?? SynologyUsersGroupsSnapshot(
                users: [user],
                groups: [],
                sharedFolders: [],
                quotas: [],
                home: SynologyUserHomeSettings(enabled: nil, location: "", recycleBinEnabled: nil, encryption: nil),
                passwordPolicy: SynologyPasswordPolicySettings(),
                collectedAt: .now
            ))
            await loadDetails()
        }
        .alert("操作失败", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) {
            Button("知道了", role: .cancel) { localError = nil }
        } message: {
            Text(localError ?? "")
        }
        .alert(item: $pendingRenameConfirmation) { confirmation in
            Alert(
                title: Text("修改 DSM 登录账号？"),
                message: Text("这会真实修改 NAS 上的登录账号名：\(confirmation.oldName) → \(confirmation.newName)。如果这是当前 App 使用的 DSM 账号，保存成功后本地也会同步为新账号。"),
                primaryButton: .destructive(Text("确认修改")) {
                    Task { await saveAccountName(oldName: confirmation.oldName, newName: confirmation.newName) }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .alert(item: $pendingPasswordConfirmation) { confirmation in
            Alert(
                title: Text("修改 DSM 登录密码？"),
                message: Text("这会真实修改 \(confirmation.username) 在 NAS 上的登录密码。修改后旧密码会立即失效，请确认新密码已经记录。"),
                primaryButton: .destructive(Text("确认修改")) {
                    Task { await savePassword(username: confirmation.username) }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private var currentUser: SynologyNASUser {
        if let matched = details?.users.first(where: { $0.name == accountName }) {
            return matched
        }
        return details?.users.first(where: { $0.name == user.name }) ?? user
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text((currentUser.isEnabled ?? true) ? "正常" : "停用")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle((currentUser.isEnabled ?? true) ? Color.serveraLeaf : Color.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(((currentUser.isEnabled ?? true) ? Color.serveraLeaf : Color.red).opacity(0.12), in: Capsule())

            VStack(alignment: .leading, spacing: 7) {
                Text(currentUser.name)
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(headerSubtitle)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white.opacity(0.78))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.62), lineWidth: 1)
                )
                .shadow(color: Color.serveraAccent.opacity(0.08), radius: 16, y: 8)
        }
    }

    private var headerSubtitle: String {
        var parts: [String] = []
        if currentUser.name == connection.account {
            parts.append("当前账号")
        }
        if currentUser.groupNames.contains("administrators") {
            parts.append("管理员")
        }
        return parts.isEmpty ? "DSM 用户" : parts.joined(separator: " · ")
    }

    private var accountPasswordSection: some View {
        editorSection(title: "账号与密码", icon: "person.text.rectangle") {
            VStack(spacing: 12) {
                if canRenameAccount {
                    NASEditorField(title: "登录账号名", text: $accountName)
                    if hasAccountNameChanges {
                        saveButton(title: "保存账号名", tab: .account, isEnabled: true) {
                            await confirmRenameAccount()
                        }
                    }
                } else {
                    NASReadOnlyField(title: "登录账号名", value: currentUser.name)
                    Text("内置账号不支持在 Servera 中修改账号名。")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.serveraTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                SecureField("修改密码", text: $password)
                    .textContentType(.newPassword)
                    .font(.system(size: 15, weight: .bold))
                    .padding(14)
                    .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                SecureField("确认密码", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .font(.system(size: 15, weight: .bold))
                    .padding(14)
                    .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if hasPasswordChanges {
                    saveButton(title: "保存密码", tab: .password, isEnabled: true) {
                        await confirmSavePassword()
                    }
                }
            }
        }
    }

    private var groupsTab: some View {
        editorSection(title: "用户群组", icon: "person.3.sequence.fill") {
            VStack(spacing: 10) {
                let groups = details?.groups ?? []
                if groups.isEmpty {
                    NASControlEmptyLine(text: "没有读取到群组。")
                } else {
                    NASControlListCard {
                        VStack(spacing: 0) {
                            ForEach(groups) { group in
                        Toggle(isOn: Binding(
                            get: { selectedGroups.contains(group.name) },
                            set: { isOn in
                                if isOn {
                                    selectedGroups.insert(group.name)
                                } else {
                                    selectedGroups.remove(group.name)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name)
                                    .font(.system(size: 15, weight: .black))
                                Text(group.description.isEmpty ? "\(group.memberNames.count) 个成员" : group.description)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.serveraTextSecondary)
                            }
                        }
                        .tint(Color.serveraAccentDeep)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 64)
                        if group.id != groups.last?.id {
                            Divider()
                                .overlay(Color.serveraBorder.opacity(0.45))
                                .padding(.leading, 14)
                        }
                            }
                        }
                    }
                    if hasGroupChanges {
                        saveButton(title: "保存群组", tab: .groups, isEnabled: true) {
                            await saveGroups()
                        }
                    }
                }
            }
        }
    }

    private func editorSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        NASNetworkFlatSection(title: title, icon: icon, color: .serveraAccentDeep) {
            content()
        }
    }

    private func saveButton(title: String, tab: NASUserEditorTab, isEnabled: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Label(savingTab == tab ? "保存中" : title, systemImage: "checkmark.circle.fill")
        }
        .buttonStyle(NASControlPanelButtonStyle(color: .serveraAccentDeep))
        .disabled(savingTab != nil || !isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
    }

    private func loadDetails() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await SynologyControlPanelService(connection: connection)
                .fetchUserManagementDetails(for: user.name)
            apply(loaded)
        } catch let error where error.isNASControlPanelCancellation {
            return
        } catch {
            localError = error.localizedDescription
            onError(error.localizedDescription)
        }
    }

    private func apply(_ snapshot: SynologyUsersGroupsSnapshot) {
        details = snapshot
        let current = snapshot.users.first(where: { $0.name == accountName })
            ?? snapshot.users.first(where: { $0.name == user.name })
            ?? user
        accountName = current.name
        selectedGroups = Set(current.groupNames)
        baselineAccountName = accountName
        baselineGroups = selectedGroups
    }

    private var hasAccountNameChanges: Bool {
        normalizedAccountName != baselineAccountName
    }

    private var hasPasswordChanges: Bool {
        !password.isEmpty || !confirmPassword.isEmpty
    }

    private var hasGroupChanges: Bool {
        selectedGroups != baselineGroups
    }

    private var normalizedAccountName: String {
        accountName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canRenameAccount: Bool {
        !["admin", "guest"].contains(currentUser.name.lowercased())
    }

    private func confirmRenameAccount() async {
        let newName = normalizedAccountName
        guard !newName.isEmpty else {
            localError = "用户名称不能为空。"
            return
        }
        guard newName != baselineAccountName else { return }
        pendingRenameConfirmation = NASUserRenameConfirmation(oldName: baselineAccountName, newName: newName)
    }

    private func saveAccountName(oldName: String, newName: String) async {
        savingTab = .account
        defer { savingTab = nil }
        do {
            // 账号改名在 service 里做读回校验。失败时恢复草稿，
            // 避免 UI 暗示 DSM 登录账号已经改变。
            let updated = try await SynologyControlPanelService(connection: connection)
                .renameUserAccount(oldName: oldName, newName: newName)
            apply(updated)
            onAccountRenamed(oldName, newName)
            await onSaved(updated)
        } catch {
            accountName = baselineAccountName
            localError = error.localizedDescription
            onError(error.localizedDescription)
        }
    }

    private func confirmSavePassword() async {
        guard password == confirmPassword else {
            localError = "两次输入的密码不一致。"
            return
        }
        guard !password.isEmpty else { return }
        pendingPasswordConfirmation = NASUserPasswordConfirmation(username: baselineAccountName)
    }

    private func savePassword(username: String) async {
        savingTab = .password
        defer { savingTab = nil }
        do {
            // 密码修改刻意和账号改名拆开，让用户分别确认每个高风险操作。
            let updated = try await SynologyControlPanelService(connection: connection)
                .changeUserPassword(username: username, password: password)
            password = ""
            confirmPassword = ""
            apply(updated)
            await onSaved(updated)
        } catch {
            localError = error.localizedDescription
            onError(error.localizedDescription)
        }
    }

    private func saveGroups() async {
        guard !selectedGroups.isEmpty else {
            localError = "用户至少需要保留一个群组。"
            return
        }
        // 除账号/密码外，用户管理只保留群组成员关系编辑。
        // 共享文件夹权限和配额已移除，保持页面聚焦。
        savingTab = .groups
        defer { savingTab = nil }
        do {
            let updated = try await SynologyControlPanelService(connection: connection)
                .saveUserGroups(username: baselineAccountName, groupNames: Array(selectedGroups).sorted())
            apply(updated)
            await onSaved(updated)
        } catch {
            localError = error.localizedDescription
            onError(error.localizedDescription)
        }
    }
}

private struct NASUserRenameConfirmation: Identifiable {
    let id = UUID()
    let oldName: String
    let newName: String
}

private struct NASUserPasswordConfirmation: Identifiable {
    let id = UUID()
    let username: String
}

private struct NASReadOnlyField: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.serveraTextSecondary)
            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 15, weight: .black))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct NASEditorField: View {
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.serveraTextSecondary)
            TextField("", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15, weight: .bold))
                .keyboardType(keyboardType)
                .padding(14)
                .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct NASUserRow: View {
    let user: SynologyNASUser
    let currentAccount: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(iconColor.opacity(0.14))
                    Image(systemName: user.groupNames.contains("administrators") ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(iconColor)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(user.name)
                            .font(.system(size: 15, weight: .black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        if user.name == currentAccount {
                            StatusPill(text: "当前", color: .serveraAccentDeep)
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.serveraTextSecondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                NASControlMiniInfo(title: "UID", value: user.uid.map(String.init) ?? "-")
                NASControlMiniInfo(title: "群组", value: user.groupNames.isEmpty ? "未返回" : user.groupNames.joined(separator: " / "))
            }
            HStack(spacing: 8) {
                NASControlMiniInfo(title: "邮箱", value: user.email.isEmpty ? "-" : user.email)
                NASControlMiniInfo(title: "OTP", value: boolText(user.otpEnabled, trueText: "已开启", falseText: "未开启"))
            }
            HStack(spacing: 8) {
                NASControlMiniInfo(title: "可编辑", value: boolText(user.isEditable, trueText: "是", falseText: "否"))
                NASControlMiniInfo(title: "上次改密", value: passwordLastChangeText)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.serveraBorder.opacity(0.42), lineWidth: 1)
        )
    }

    private var iconColor: Color {
        user.groupNames.contains("administrators") ? .serveraAccentDeep : .serveraLeaf
    }

    private var subtitle: String {
        if !user.fullName.isEmpty { return user.fullName }
        if !user.description.isEmpty { return user.description }
        if user.disallowPasswordChange == true { return "不可自行修改密码" }
        return "DSM 用户"
    }

    private var passwordLastChangeText: String {
        guard let day = user.passwordLastChangeDay, day > 0 else { return "-" }
        let date = Date(timeIntervalSince1970: TimeInterval(day) * 86_400)
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct NASGroupRow: View {
    let group: SynologyNASGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.serveraSky.opacity(0.16))
                    Image(systemName: group.name == "administrators" ? "person.3.fill" : "person.2.fill")
                        .font(.system(size: 19, weight: .black))
                        .foregroundStyle(group.name == "administrators" ? Color.serveraAccentDeep : Color.serveraSky)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 5) {
                    Text(group.name)
                        .font(.system(size: 15, weight: .black))
                        .lineLimit(1)
                    Text(group.description.isEmpty ? "DSM 群组" : group.description)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.serveraTextSecondary)
                        .lineLimit(2)
                }
                Spacer()
                StatusPill(text: "\(group.memberNames.count) 人", color: .serveraLeaf)
            }

            HStack(spacing: 8) {
                NASControlMiniInfo(title: "GID", value: group.gid.map(String.init) ?? "-")
                NASControlMiniInfo(title: "成员", value: group.memberNames.isEmpty ? "未返回" : group.memberNames.joined(separator: " / "))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.serveraBorder.opacity(0.42), lineWidth: 1)
        )
    }
}

private struct NASUserPolicyPanel: View {
    let home: SynologyUserHomeSettings
    let passwordPolicy: SynologyPasswordPolicySettings

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                NASControlMiniInfo(title: "家目录", value: boolText(home.enabled, trueText: "已开启", falseText: "未开启"))
                NASControlMiniInfo(title: "位置", value: home.location.isEmpty ? "-" : home.location)
            }
            HStack(spacing: 8) {
                NASControlMiniInfo(title: "回收站", value: boolText(home.recycleBinEnabled, trueText: "已开启", falseText: "未开启"))
                NASControlMiniInfo(title: "加密", value: home.encryption.map { $0 == 0 ? "未开启" : "已开启" } ?? "-")
            }
            HStack(spacing: 8) {
                NASControlMiniInfo(title: "最小长度", value: passwordPolicy.minLengthEnabled == true ? "\(passwordPolicy.minLength ?? 0) 位" : "未强制")
                NASControlMiniInfo(title: "大小写", value: boolText(passwordPolicy.mixedCase, trueText: "要求", falseText: "不要求"))
            }
            HStack(spacing: 8) {
                NASControlMiniInfo(title: "数字", value: boolText(passwordPolicy.numeric, trueText: "要求", falseText: "不要求"))
                NASControlMiniInfo(title: "特殊字符", value: boolText(passwordPolicy.specialCharacter, trueText: "要求", falseText: "不要求"))
            }
            HStack(spacing: 8) {
                NASControlMiniInfo(title: "排除用户名", value: boolText(passwordPolicy.excludeUsername, trueText: "是", falseText: "否"))
                NASControlMiniInfo(title: "邮件重置", value: boolText(passwordPolicy.resetByEmailEnabled, trueText: "允许", falseText: "不允许"))
            }
        }
    }
}

private struct NASControlMiniInfo: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.serveraTextSecondary)
            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.serveraBorder.opacity(0.32), lineWidth: 1)
        )
    }
}

private func boolText(_ value: Bool?, trueText: String, falseText: String) -> String {
    guard let value else { return "-" }
    return value ? trueText : falseText
}

private struct NASExternalAccessSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Color.serveraAccentDeep)
                    .frame(width: 30, height: 30)
                    .background(Color.serveraTintSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Text(title)
                    .font(.system(size: 16, weight: .black))
                Spacer()
            }
            content
        }
        .padding(14)
        .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.serveraBorder.opacity(0.48), lineWidth: 1)
        )
    }
}

private struct NASNetworkHeroCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let status: String
    let isAvailable: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(color.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .black))
                    .foregroundStyle(color)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 23, weight: .black))
                Text(subtitle.isEmpty ? "等待 DSM 刷新" : subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 8)

            StatusPill(text: status, color: isAvailable ? .serveraLeaf : .serveraAmber)
        }
        .padding(15)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white.opacity(0.78))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.58), lineWidth: 1)
                )
                .shadow(color: Color.serveraAccent.opacity(0.10), radius: 18, y: 10)
        }
    }
}

private struct NASNetworkSettingsSection: View {
    @Binding var hostname: String
    @Binding var dns: String
    let ip: String
    let gateway: String
    let interfaces: [String]
    let isSaving: Bool
    let canSave: Bool
    let onSave: () -> Void

    var body: some View {
        NASNetworkFlatSection(title: "网络设置", icon: "network", color: .serveraAccentDeep) {
            VStack(spacing: 0) {
                NASNetworkTextRow(title: "主机名", placeholder: "NAS 主机名", text: $hostname)
                NASNetworkValueRow(title: "IP", value: ip)
                NASNetworkValueRow(title: "网关", value: gateway)
                NASNetworkTextRow(title: "DNS", placeholder: "例如 223.5.5.5, 8.8.8.8", text: $dns, isMultiline: true)
            }

            if !interfaces.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("网卡")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Color.serveraTextSecondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(interfaces, id: \.self) { item in
                            NASNetworkInterfaceChip(text: item)
                        }
                    }
                }
                .padding(.top, 4)
            }

            Button(action: onSave) {
                Label(isSaving ? "保存中" : "保存网络设置", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(NASControlPanelButtonStyle(color: .serveraAccentDeep))
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.45)
        }
    }
}

private struct NASProxySettingsSection: View {
    @Binding var enabled: Bool
    @Binding var host: String
    @Binding var port: String
    @Binding var bypassLocal: Bool
    let isSaving: Bool
    let canSave: Bool
    let onSave: () -> Void

    var body: some View {
        NASNetworkFlatSection(title: "代理服务器", icon: "point.3.connected.trianglepath.dotted", color: .serveraLeaf) {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("通过代理服务器连接")
                        .font(.system(size: 15, weight: .black))
                    Text(enabled ? "NAS 系统流量将使用下面的代理" : "未启用系统代理")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.serveraTextSecondary)
                }
            }
            .tint(Color.serveraAccentDeep)
            .padding(.vertical, 4)

            VStack(spacing: 0) {
                NASNetworkTextRow(title: "地址", placeholder: "proxy.example.com", text: $host)
                NASNetworkTextRow(title: "端口", placeholder: "7890", text: $port, keyboardType: .numberPad)
            }

            Toggle("对本地地址不使用代理服务器", isOn: $bypassLocal)
                .font(.system(size: 14, weight: .heavy))
                .tint(Color.serveraAccentDeep)

            Text(enabled ? "保存后 NAS 会通过该代理访问外网服务。" : "关闭代理时保存会停用系统代理；地址和端口会保留，方便下次启用。")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.serveraTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onSave) {
                Label(isSaving ? "保存中" : "保存代理设置", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(NASControlPanelButtonStyle(color: .serveraLeaf))
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.45)
        }
    }
}

private struct NASTerminalSettingsSection: View {
    @Binding var sshEnabled: Bool
    @Binding var telnetEnabled: Bool
    @Binding var sshPort: String
    let isSaving: Bool
    let canSave: Bool
    let onSave: () -> Void

    var body: some View {
        NASNetworkFlatSection(title: "终端机设置", icon: "terminal.fill", color: .serveraTextSecondary) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $sshEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("启动 SSH 功能")
                            .font(.system(size: 15, weight: .black))
                        Text(sshEnabled ? "允许通过 SSH 登录 NAS" : "SSH 当前关闭")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.serveraTextSecondary)
                    }
                }
                .tint(Color.serveraAccentDeep)

                Toggle(isOn: $telnetEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("启动 Telnet 功能")
                            .font(.system(size: 15, weight: .black))
                        Text(telnetEnabled ? "仅建议在可信内网临时使用" : "Telnet 当前关闭")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.serveraTextSecondary)
                    }
                }
                .tint(Color.serveraAmber)

                VStack(spacing: 0) {
                    NASNetworkTextRow(title: "SSH 端口", placeholder: "22", text: $sshPort, keyboardType: .numberPad)
                }
            }

            Button(action: onSave) {
                Label(isSaving ? "保存中" : "保存终端机设置", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(NASControlPanelButtonStyle(color: .serveraAccentDeep))
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.45)
        }
    }
}

private struct NASNetworkFlatSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title)
                    .font(.system(size: 17, weight: .black))
                Spacer()
            }

            content
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.white.opacity(0.74))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.54), lineWidth: 1)
                )
                .shadow(color: Color.serveraAccent.opacity(0.07), radius: 14, y: 7)
        }
    }
}

private struct NASNetworkTextRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isMultiline = false
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(alignment: isMultiline ? .top : .center, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Color.serveraTextSecondary)
                .frame(width: 54, alignment: .leading)
                .padding(.top, isMultiline ? 12 : 0)

            TextField(placeholder, text: $text, axis: isMultiline ? .vertical : .horizontal)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 16, weight: .black))
                .lineLimit(isMultiline ? 3 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(Color.serveraBorder.opacity(0.46))
        }
    }
}

private struct NASNetworkValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Color.serveraTextSecondary)
                .frame(width: 54, alignment: .leading)
            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 16, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(Color.serveraBorder.opacity(0.46))
        }
    }
}

private struct NASNetworkInterfaceChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.62), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.serveraBorder.opacity(0.36), lineWidth: 1)
            )
    }
}

private struct NASDDNSRecordEditor: View {
    @Binding var record: SynologyDDNSRecord
    let isSaving: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("启用 \(record.hostname.isEmpty ? "DDNS" : record.hostname)", isOn: $record.enabled)
                .font(.system(size: 14, weight: .heavy))
                .tint(Color.serveraAccentDeep)

            HStack(spacing: 10) {
                externalField("主机名", text: $record.hostname)
                externalField("服务商", text: $record.provider)
            }
            HStack(spacing: 10) {
                externalField("账号", text: $record.username)
                externalField("密码/Token", text: $record.password, isSecure: true)
            }
            Text("DSM 不会返回已保存的密码/Token；不修改可留空，修改服务商、主机名或账号时建议重新输入。")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.serveraTextSecondary)
                .lineSpacing(2)
            HStack(spacing: 10) {
                DDNSMiniInfo(title: "当前 IP", value: record.ip)
                DDNSMiniInfo(title: "状态", value: ddnsStatusText)
            }
            Button(action: onSave) {
                Label(isSaving ? "保存中" : "保存 DDNS", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(NASControlPanelButtonStyle(color: .serveraLeaf))
            .disabled(isSaving)
        }
        .padding(12)
        .background(Color.serveraLeafSoft.opacity(0.42), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var ddnsStatusText: String {
        if record.status == "check_network" { return "检查网络" }
        if record.status == "normal" { return "正常" }
        return record.status.isEmpty ? "-" : record.status
    }

    private func externalField(_ title: String, text: Binding<String>, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.serveraTextSecondary)
            Group {
                if isSecure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(size: 13, weight: .bold))
            .padding(10)
            .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct DDNSMiniInfo: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.serveraTextSecondary)
            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.serveraBorder.opacity(0.36), lineWidth: 1)
        )
    }
}

private struct NASControlPanelButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(configuration.isPressed ? 0.19 : 0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct NASInfoBadge: View {
    let text: String
    var color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color.opacity(0.76))
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .frame(height: 32)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct NASDeviceList: View {
    let devices: [DashboardDevice]
    let refreshingDeviceIDs: Set<UUID>
    let onRefresh: (DashboardDevice) async -> Void
    let onEdit: (DashboardDevice) -> Void
    let onDelete: (DashboardDevice) -> Void
    let onSelect: (DashboardDevice) -> Void

    var body: some View {
        ServeraCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 8) {
                Text("NAS 设备")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.serveraTextSecondary)
                Text("\(devices.count) 台 NAS 已添加")
                    .font(.system(size: 26, weight: .black))
                Text("选择一台 NAS 进入详情，查看存储、资源和服务状态。")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        VStack(alignment: .leading, spacing: 12) {
            Text("设备列表")
                .font(.system(size: 18, weight: .heavy))
                .padding(.horizontal, 6)
            ForEach(devices) { device in
                SwipeableNASRow(
                    device: device,
                    isRefreshing: refreshingDeviceIDs.contains(device.id),
                    onSelect: {
                        onSelect(device)
                    },
                    onRefresh: {
                        Task { await onRefresh(device) }
                    },
                    onEdit: {
                        onEdit(device)
                    },
                    onDelete: {
                        onDelete(device)
                    }
                )
            }
        }
    }
}

private struct SwipeableNASRow: View {
    let device: DashboardDevice
    var isRefreshing = false
    var onSelect: () -> Void
    var onRefresh: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    @State private var committedOffset: CGFloat = 0
    @GestureState private var dragTranslation: CGFloat = 0

    private let actionWidth: CGFloat = 150

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 8) {
                swipeButton(title: "编辑", icon: "pencil", color: Color.serveraAccentDeep) {
                    closeActions()
                    onEdit()
                }
                swipeButton(title: "删除", icon: "trash", color: .red) {
                    closeActions()
                    onDelete()
                }
            }
            .padding(.trailing, 10)

            CompactNASRow(
                device: device,
                isRefreshing: isRefreshing,
                onSelect: {
                    if currentOffset < -18 {
                        closeActions()
                    } else {
                        onSelect()
                    }
                },
                onRefresh: {
                    closeActions()
                    onRefresh()
                },
                onEdit: {
                    closeActions()
                    onEdit()
                },
                onDelete: {
                    closeActions()
                    onDelete()
                }
            )
            .offset(x: currentOffset)
            .highPriorityGesture(rowDragGesture)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: currentOffset)
    }

    private var currentOffset: CGFloat {
        min(0, max(-actionWidth, committedOffset + dragTranslation))
    }

    private var rowDragGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .updating($dragTranslation) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let proposed = committedOffset + value.translation.width
                let projected = committedOffset + value.predictedEndTranslation.width
                committedOffset = proposed < -actionWidth * 0.42 || projected < -actionWidth * 0.7 ? -actionWidth : 0
            }
    }

    @ViewBuilder
    private func swipeButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .black))
                Text(title)
                    .font(.system(size: 12, weight: .heavy))
            }
            .foregroundStyle(.white)
            .frame(width: 64, height: 72)
            .background(color.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func closeActions() {
        committedOffset = 0
    }
}

struct CompactNASRow: View {
    let device: DashboardDevice
    var isRefreshing = false
    var onSelect: () -> Void
    var onRefresh: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        ServeraCard(cornerRadius: 26) {
            HStack(spacing: 14) {
                NASIcon()
                    .scaleEffect(0.56)
                    .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.system(size: 18, weight: .heavy))
                    Text(device.subtitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.serveraTextSecondary)
                }
                Spacer()
                StatusPill(text: device.credentialNeedsVerification ? "待验证" : device.latency)
                NASActionMenu(
                    isRefreshing: isRefreshing,
                    onRefresh: onRefresh,
                    onEdit: onEdit,
                    onDelete: onDelete
                )
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture {
            onSelect()
        }
    }
}

struct NASDetailView: View {
    let device: DashboardDevice
    let onRefresh: (DashboardDevice) async -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onOpenFiles: (SynologyStorageVolume) -> Void
    let onOpenControlPanel: (NASControlPanelModule) -> Void
    let onOpenDockerContainer: (DockerContainerSummary) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                DetailTopBar(title: device.name) {
                    dismiss()
                }

                NASHeaderCard(
                    device: device,
                    onRefresh: {
                        Task { await onRefresh(device) }
                    },
                    onEdit: onEdit,
                    onDelete: onDelete
                )

                NASStatusSections(
                    device: device,
                    onOpenVolume: onOpenFiles,
                    onOpenControlPanel: onOpenControlPanel
                )
                NASDockerOverviewCard(
                    device: device,
                    showsAllContainers: true,
                    onSelectContainer: onOpenDockerContainer
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .background(ServeraBackground().ignoresSafeArea())
        .task {
            await onRefresh(device)
        }
        .refreshable {
            await onRefresh(device)
        }
        .edgeSwipeBack {
            dismiss()
        }
    }
}

private struct NASDockerOverviewCard: View {
    let device: DashboardDevice
    var showsAllContainers: Bool = false
    var onShowAll: (() -> Void)?
    var onSelectContainer: ((DockerContainerSummary) -> Void)?

    private var sortedContainers: [DockerContainerSummary] {
        device.dockerContainers.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isRunning != rhs.element.isRunning {
                    return lhs.element.isRunning && !rhs.element.isRunning
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private var visibleContainers: [DockerContainerSummary] {
        // 首页保持轻量；用户明确进入 NAS Docker 管理时，详情页才传入 showsAllContainers。
        showsAllContainers ? sortedContainers : Array(sortedContainers.prefix(4))
    }

    var body: some View {
        ServeraCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(
                    icon: "shippingbox",
                    title: "NAS Docker",
                    color: .serveraLeaf,
                    trailing: dockerTrailing
                )

                if !device.dockerDataAvailable {
                    dockerEmptyState(device.dockerErrorMessage.nasVisibleError(fallback: "未检测到 Container Manager / Docker。"))
                } else if device.docker == 0 {
                    dockerEmptyState("Container Manager 已连接，暂未发现容器。")
                } else if device.dockerContainers.isEmpty {
                    dockerEmptyState("已检测到 \(device.docker) 个容器，等待下一次刷新读取容器资源。")
                } else {
                    VStack(spacing: 0) {
                        ForEach(visibleContainers) { container in
                            Button {
                                onSelectContainer?(container)
                            } label: {
                                DockerCompactRow(container: container)
                            }
                            .buttonStyle(.plain)
                            .disabled(onSelectContainer == nil)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    if !showsAllContainers, device.dockerContainers.count > 4 {
                        Button {
                            onShowAll?()
                        } label: {
                            HStack {
                                Text("还有 \(device.dockerContainers.count - 4) 个容器")
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text("查看完整列表")
                                    .font(.system(size: 13, weight: .heavy))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .black))
                            }
                            .foregroundStyle(Color.serveraLeaf)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.serveraLeaf.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var dockerTrailing: String {
        guard device.dockerDataAvailable else { return "等待刷新" }
        return "\(device.dockerRunningCount)/\(max(device.docker, device.dockerContainers.count)) 运行"
    }

    private func dockerEmptyState(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(Color.serveraLeaf)
                .frame(width: 34, height: 34)
                .background(Color.serveraLeafSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.serveraTextSecondary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(15)
        .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct NASActionMenu: View {
    var isRefreshing = false
    var onRefresh: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        Menu {
            if let onRefresh {
                Button {
                    onRefresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
            }
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.68))
                    .frame(width: 38, height: 38)
                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.72)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(Color.serveraTextSecondary)
                }
            }
        }
        .menuStyle(.button)
    }
}

struct NASDockerContainerDetailView: View {
    let device: DashboardDevice
    let initialContainer: DockerContainerSummary
    let connection: SynologyDockerConnection
    let onContainersUpdated: ([DockerContainerSummary]) -> Void
    let onError: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var container: DockerContainerSummary
    @State private var containers: [DockerContainerSummary]
    @State private var service: SynologyDockerService?
    @State private var isConnecting = true
    @State private var isLoadingLogs = false
    @State private var activeAction: NASDockerAction?
    @State private var logText = ""
    @State private var logStatusText = ""
    @State private var logSource: NASDockerLogSource?
    @State private var selectedLogLines = 100
    @State private var pendingAction: NASDockerAction?
    @State private var pendingHostKeyPrompt: NASDockerSSHHostKeyPrompt?
    @State private var localError: String?

    init(
        device: DashboardDevice,
        initialContainer: DockerContainerSummary,
        connection: SynologyDockerConnection,
        onContainersUpdated: @escaping ([DockerContainerSummary]) -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.device = device
        self.initialContainer = initialContainer
        self.connection = connection
        self.onContainersUpdated = onContainersUpdated
        self.onError = onError
        _container = State(initialValue: initialContainer)
        _containers = State(initialValue: device.dockerContainers)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    headerCard
                    actionGrid
                    logCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 26)
            }
            .background(ServeraBackground().ignoresSafeArea())
            .navigationTitle("容器管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await perform(.refresh) }
                    } label: {
                        if activeAction == .refresh {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(activeAction != nil || isConnecting)
                }
            }
        }
        .task {
            await connectAndLoad()
        }
        .onDisappear {
            Task { await service?.close() }
        }
        .alert("确认操作", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })) {
            Button(pendingAction?.title ?? "确认", role: pendingAction == .delete ? .destructive : nil) {
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
        .alert("确认 NAS SSH Host Key", isPresented: Binding(get: { pendingHostKeyPrompt != nil }, set: { if !$0 { pendingHostKeyPrompt = nil } })) {
            Button(pendingHostKeyPrompt?.isChanged == true ? "确认更新并读取" : "信任并读取") {
                guard let prompt = pendingHostKeyPrompt else { return }
                pendingHostKeyPrompt = nil
                Task {
                    await loadLogsFromSSH(
                        acceptUnknownHostKey: !prompt.isChanged,
                        acceptChangedHostKey: prompt.isChanged
                    )
                }
            }
            Button("取消", role: .cancel) {
                pendingHostKeyPrompt = nil
            }
        } message: {
            if let prompt = pendingHostKeyPrompt {
                Text(prompt.message)
            }
        }
        .alert("操作失败", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) {
            Button("知道了", role: .cancel) { localError = nil }
        } message: {
            Text(localError ?? "")
        }
    }

    private var headerCard: some View {
        ServeraCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(container.isRunning ? Color.serveraLeaf : Color.serveraTextSecondary)
                        .frame(width: 38, height: 38)
                        .background((container.isRunning ? Color.serveraLeafSoft : Color.serveraTintSoft), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(container.name)
                            .font(.system(size: 23, weight: .black))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(container.image.isEmpty ? device.name : container.image)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.serveraTextSecondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    StatusPill(text: container.isRunning ? "运行中" : "已停止")
                }

                DockerResourceCapsule(container: container, pulse: activeAction != nil, width: 320)

                HStack(spacing: 10) {
                    NASDockerInfoPill(title: "状态", value: container.status.isEmpty ? container.state : container.status)
                    NASDockerInfoPill(title: "运行", value: container.uptimeText.isEmpty ? "-" : container.uptimeText)
                }
            }
        }
    }

    private var actionGrid: some View {
        ServeraCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(icon: "slider.horizontal.3", title: "容器操作", color: .serveraAccentDeep, trailing: isConnecting ? "连接中" : "免费")
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                    ForEach(availableActions) { action in
                        NASDockerActionButton(
                            action: action,
                            isLoading: activeAction == action,
                            isDisabled: isConnecting || activeAction != nil
                        ) {
                            request(action)
                        }
                    }
                }
            }
        }
    }

    private var logCard: some View {
        ServeraCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    CardHeader(icon: "doc.text.magnifyingglass", title: "最近日志", color: .serveraLeaf, trailing: logTrailingText)
                    Spacer(minLength: 0)
                    if isLoadingLogs {
                        ProgressView()
                            .scaleEffect(0.76)
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

                if !logStatusText.isEmpty {
                    Text(logStatusText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.serveraTextSecondary)
                        .lineLimit(2)
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
                                .id("logBottom")
                        }
                        .padding(14)
                    }
                    .frame(minHeight: 220, maxHeight: 320)
                    .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .onChange(of: logText) { _, _ in
                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo("logBottom", anchor: .bottom)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await loadLogs() }
                    } label: {
                        Label("刷新日志", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(NASDockerSecondaryButtonStyle())
                    .disabled(isConnecting || isLoadingLogs)

                    Button {
                        UIPasteboard.general.string = logText
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(NASDockerSecondaryButtonStyle())
                    .disabled(logText.isEmpty)
                }
            }
        }
    }

    private var availableActions: [NASDockerAction] {
        if container.isRunning {
            return [.stop, .restart, .refresh, .delete]
        }
        return [.start, .refresh, .delete]
    }

    private var logTrailingText: String {
        logSource == nil ? "\(selectedLogLines) 行" : "\(selectedLogLines) 行 · 仅容器输出"
    }

    private var logDisplayText: String {
        if !logText.isEmpty { return logText }
        if isConnecting { return "正在连接 Container Manager..." }
        if isLoadingLogs { return "正在读取日志..." }
        return "暂无容器日志。"
    }

    private func request(_ action: NASDockerAction) {
        if action.isDestructive {
            pendingAction = action
        } else {
            Task { await perform(action) }
        }
    }

    private func connectAndLoad() async {
        isConnecting = true
        defer { isConnecting = false }
        do {
            let service = SynologyDockerService(connection: connection)
            try await service.connect()
            self.service = service
            try await refreshContainers(using: service)
            await loadLogs(using: service)
        } catch {
            localError = error.localizedDescription
            onError(error.localizedDescription)
        }
    }

    private func perform(_ action: NASDockerAction) async {
        guard let service else { return }
        activeAction = action
        defer { activeAction = nil }
        do {
            switch action {
            case .start:
                try await service.start(container: container)
            case .stop:
                try await service.stop(container: container)
            case .restart:
                try await service.restart(container: container)
            case .delete:
                try await service.delete(container: container)
            case .refresh:
                break
            }
            try await refreshContainers(using: service)
            if action == .delete {
                dismiss()
            } else {
                // 真实操作后自动刷新日志。部分 NAS 版本 DSM 日志可能为空，
                // 所以启动/重启后会尝试 SSH 兜底，展示真实容器输出。
                let hasDSMLogs = await loadLogs(using: service)
                if (action == .start || action == .restart), !hasDSMLogs {
                    await loadLogsFromSSH()
                }
            }
        } catch {
            localError = error.localizedDescription
        }
    }

    private func refreshContainers(using service: SynologyDockerService) async throws {
        // 容器操作后始终从 DSM 读回状态，不做本地乐观切换。
        let refreshed = try await service.refreshContainers()
        containers = refreshed
        if let updated = refreshed.first(where: { $0.id == container.id || $0.name == container.name }) {
            container = updated
        }
        onContainersUpdated(refreshed)
    }

    private func loadLogs() async {
        guard let service else { return }
        let hasDSMLogs = await loadLogs(using: service)
        if !hasDSMLogs {
            await loadLogsFromSSH()
        }
    }

    @discardableResult
    private func loadLogs(using service: SynologyDockerService) async -> Bool {
        // 优先使用 DSM API，因为它不要求 NAS 开启 SSH。空日志不视为致命错误。
        isLoadingLogs = true
        defer { isLoadingLogs = false }
        do {
            let result = try await service.fetchLogs(container: container, lines: selectedLogLines)
            logText = sanitizeDockerLogText(result.text)
            logSource = result.source
            logStatusText = ""
            return !logText.isEmpty
        } catch {
            logText = ""
            logSource = nil
            logStatusText = ""
            return false
        }
    }

    private func loadLogsFromSSH(acceptUnknownHostKey: Bool = false, acceptChangedHostKey: Bool = false) async {
        // SSH 兜底使用 DSM 凭据和 22 端口，仍然必须经过 Host Key 确认，
        // 不会自动信任 NAS shell 访问。
        isLoadingLogs = true
        defer { isLoadingLogs = false }

        let request = SSHConnectionRequest(
            host: connection.host,
            port: 22,
            username: connection.account,
            authenticationKind: .password,
            credential: DeviceCredentialBundle(password: connection.password, privateKeyPEM: nil, privateKeyPassphrase: nil),
            acceptUnknownHostKey: acceptUnknownHostKey,
            acceptChangedHostKey: acceptChangedHostKey,
            networkMode: .direct
        )

        do {
            let result = try await SSHConnectionService.shared.executeCommand(
                request: request,
                command: sshLogCommand(containerName: container.name, lines: selectedLogLines),
                standardInput: "\(connection.password)\n"
            )
            let output = extractDockerLogText(from: result.standardOutput)
            let errorOutput = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            let failureOutput = [errorOutput, output].filter { !$0.isEmpty }.joined(separator: "\n")
            if result.succeeded, !output.isEmpty {
                logText = output
                logSource = .ssh
                logStatusText = ""
            } else if result.succeeded {
                logText = ""
                logSource = .ssh
                logStatusText = "容器暂时没有返回日志。"
            } else {
                logText = ""
                logSource = nil
                logStatusText = sshLogFailureMessage(exitStatus: result.exitStatus, stderr: failureOutput)
            }
        } catch let error as ServeraSSHError {
            switch error {
            case .unknownHostKey(let algorithm, let fingerprint):
                pendingHostKeyPrompt = NASDockerSSHHostKeyPrompt(isChanged: false, algorithm: algorithm, fingerprintSHA256: fingerprint)
            case .hostKeyChanged(let algorithm, let fingerprint):
                pendingHostKeyPrompt = NASDockerSSHHostKeyPrompt(isChanged: true, algorithm: algorithm, fingerprintSHA256: fingerprint)
            default:
                logText = ""
                logSource = nil
                logStatusText = error.localizedDescription
            }
        } catch {
            logText = ""
            logSource = nil
            logStatusText = error.localizedDescription
        }
    }

    private func sshLogCommand(containerName: String, lines: Int) -> String {
        // 用标记包住 docker 输出，过滤 sudo 或 shell 噪声，
        // 保证日志面板只显示容器日志。
        let normalizedName = containerName.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
        let safeName = shellSingleQuoted(normalizedName)
        let safeLines = max(20, min(lines, 1000))
        let script = """
        printf '%s\\n' '__SERVERAOPS_DOCKER_LOG_BEGIN__'
        /usr/local/bin/docker logs --tail \(safeLines) --timestamps \(safeName) 2>&1
        status=$?
        printf '%s\\n' '__SERVERAOPS_DOCKER_LOG_END__'
        exit $status
        """
        return "sudo -S -p '' sh -c \(shellSingleQuoted(script))"
    }

    private func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private func extractDockerLogText(from rawOutput: String) -> String {
        let begin = "__SERVERAOPS_DOCKER_LOG_BEGIN__"
        let end = "__SERVERAOPS_DOCKER_LOG_END__"
        guard let beginRange = rawOutput.range(of: begin),
              let endRange = rawOutput.range(of: end, range: beginRange.upperBound..<rawOutput.endIndex) else {
            return sanitizeDockerLogText(rawOutput)
        }
        let body = String(rawOutput[beginRange.upperBound..<endRange.lowerBound])
        return sanitizeDockerLogText(body)
    }

    private func sanitizeDockerLogText(_ text: String) -> String {
        let blockedFragments = [
            "__SERVERAOPS_DOCKER_LOG_BEGIN__",
            "__SERVERAOPS_DOCKER_LOG_END__",
            "DSM 未返回日志",
            "正在尝试 SSH 读取",
            "正在读取 SSH 日志"
        ]
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return true }
                return !blockedFragments.contains { trimmed.localizedCaseInsensitiveContains($0) }
            }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sshLogFailureMessage(exitStatus: Int?, stderr: String) -> String {
        let detail = stderr.isEmpty ? "退出码 \(exitStatus.map(String.init) ?? "-")" : stderr
        if detail.localizedCaseInsensitiveContains("permission denied") {
            return "SSH 已连接，但当前账号没有读取 Docker 日志的权限。请在 DSM 中检查账号 sudo 或 Container Manager 权限。"
        }
        if detail.localizedCaseInsensitiveContains("sudo") {
            return "SSH 已连接，但 sudo 验证失败，无法读取 Docker 日志。"
        }
        if detail.localizedCaseInsensitiveContains("No such container") {
            return "NAS 上找不到这个容器，刷新容器列表后再试。"
        }
        if detail.localizedCaseInsensitiveContains("not found") {
            return "SSH 已连接，但未找到 Docker 命令。请确认 NAS 已安装 Container Manager。"
        }
        return "SSH 日志读取失败：\(detail)"
    }
}

private struct NASDockerSSHHostKeyPrompt: Identifiable {
    let id = UUID()
    let isChanged: Bool
    let algorithm: String
    let fingerprintSHA256: String

    var message: String {
        if isChanged {
            return "NAS 的 SSH Host Key 与本机记录不一致。如果你确认这台 NAS 重装或 SSH 配置变化，可以更新信任后继续读取日志。\n算法：\(algorithm)\nSHA256：\(fingerprintSHA256)"
        }
        return "首次通过 SSH 读取 NAS 日志，需要信任这台 NAS 的 Host Key。\n算法：\(algorithm)\nSHA256：\(fingerprintSHA256)"
    }
}

private struct NASDockerInfoPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(Color.serveraTextSecondary)
            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct NASDockerActionButton: View {
    let action: NASDockerAction
    let isLoading: Bool
    let isDisabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: action.systemImage)
                        .font(.system(size: 14, weight: .black))
                }
                Text(isLoading ? "正在\(action.title)" : action.title)
                    .font(.system(size: 14, weight: .heavy))
                    .lineLimit(1)
            }
            .foregroundStyle(action == .delete ? Color.serveraAccentDeep : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(action == .delete ? Color.serveraTintSoft : Color.white.opacity(0.58))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.serveraBorder.opacity(0.54), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled && !isLoading ? 0.55 : 1)
    }
}

private struct NASDockerSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Color.serveraLeaf)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.serveraLeaf.opacity(configuration.isPressed ? 0.18 : 0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension String {
    func nasVisibleError(fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        if trimmed.localizedCaseInsensitiveContains("cancel")
            || trimmed.contains("取消") {
            return fallback
        }
        if trimmed.localizedCaseInsensitiveContains("SYNO.Docker.Container")
            && trimmed.contains("114") {
            return "Container Manager 状态正在重新读取，请下拉刷新后查看。"
        }
        if trimmed.localizedCaseInsensitiveContains("SYNO.Core.Storage")
            || trimmed.localizedCaseInsensitiveContains("SYNO.Storage") {
            if trimmed.contains("权限不足") {
                return "当前 DSM 账号没有读取存储空间的权限。"
            }
            return "DSM 暂未返回存储空间信息，请下拉刷新后查看。"
        }
        return trimmed
    }
}

struct NASIcon: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: [.indigo.opacity(0.55), .serveraLeaf.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 76, height: 76)
            .overlay {
                HStack(spacing: 6) {
                    Capsule().fill(.white.opacity(0.75)).frame(width: 5)
                    Capsule().fill(.white.opacity(0.75)).frame(width: 5)
                    Capsule().fill(.white.opacity(0.75)).frame(width: 5)
                }
                .padding(.vertical, 12)
            }
    }
}

struct StorageDrawer: View {
    let volume: SynologyStorageVolume

    var body: some View {
        ServeraCard(cornerRadius: 30) {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    NASIcon()
                        .frame(width: 54, height: 54)
                        .scaleEffect(0.72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(volume.name)
                            .font(.system(size: 20, weight: .heavy))
                        Text(volume.detailText)
                            .foregroundStyle(Color.serveraTextSecondary)
                    }
                    Spacer()
                    Text("\(volume.usedPercent)%")
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(isWarm ? Color.serveraAccentDeep : Color.serveraLeaf)
                }
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.serveraTintSoft.opacity(0.62))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(LinearGradient(colors: isWarm ? [.serveraAmber, .serveraAccentDeep] : [.serveraLeaf, .serveraAccent], startPoint: .leading, endPoint: .trailing))
                                .frame(width: proxy.size.width * CGFloat(volume.usedPercent) / 100)
                        }
                }
                .frame(height: 8)
            }
        }
    }

    private var isWarm: Bool {
        volume.usedPercent >= 85 || volume.status.localizedCaseInsensitiveContains("warning")
    }
}

struct StorageSummaryCard: View {
    let volumes: [SynologyStorageVolume]
    var onOpenVolume: ((SynologyStorageVolume) -> Void)?

    var body: some View {
        ServeraCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(Color.serveraAccentDeep)
                        .frame(width: 34, height: 34)
                        .background(Color.serveraTintSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("存储空间")
                            .font(.system(size: 18, weight: .heavy))
                        Text(storageSubtitle)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.serveraTextSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(highestUsage)%")
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(highestUsage >= 85 ? Color.serveraAccentDeep : Color.serveraLeaf)
                }

                VStack(spacing: 10) {
                    ForEach(volumes) { volume in
                        StorageCompactRow(volume: volume) {
                            onOpenVolume?(volume)
                        }
                    }
                }
            }
        }
    }

    private var highestUsage: Int {
        volumes.map(\.usedPercent).max() ?? 0
    }

    private var storageSubtitle: String {
        let warningCount = volumes.filter { $0.usedPercent >= 85 || $0.status.localizedCaseInsensitiveContains("warning") }.count
        if warningCount > 0 {
            return "\(volumes.count) 个卷 · \(warningCount) 个接近满载"
        }
        return "\(volumes.count) 个卷 · 状态正常"
    }
}

private struct StorageCompactRow: View {
    let volume: SynologyStorageVolume
    var onOpen: (() -> Void)?

    var body: some View {
        Button {
            onOpen?()
        } label: {
            VStack(spacing: 7) {
                HStack(spacing: 10) {
                    Text(volume.name)
                        .font(.system(size: 15, weight: .heavy))
                        .lineLimit(1)
                    Text(volume.detailText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.serveraTextSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "folder")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Color.serveraTextSecondary)
                    Text("\(volume.usedPercent)%")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(isWarm ? Color.serveraAccentDeep : Color.serveraLeaf)
                        .monospacedDigit()
                }

                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.serveraTintSoft.opacity(0.58))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(LinearGradient(colors: isWarm ? [.serveraAmber, .serveraAccentDeep] : [.serveraLeaf, .serveraAccent], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(8, proxy.size.width * CGFloat(volume.usedPercent) / 100))
                        }
                }
                .frame(height: 6)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.serveraBorder.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        // 部分 DSM 存储池有容量但没有可浏览卷路径。
        // 这种行仍要显示在存储卡里，只是不允许点击进入文件浏览。
        .disabled(onOpen == nil)
    }

    private var isWarm: Bool {
        volume.usedPercent >= 85 || volume.status.localizedCaseInsensitiveContains("warning")
    }
}

struct NASMetric: View {
    let icon: String
    let title: String
    let value: String
    var tint: Color = .white.opacity(0.65)
    var accent: Color = .serveraAccentDeep

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(accent)
                    .frame(width: 26, height: 26)
                    .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(title)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: title == "网络" ? 21 : 24, weight: .black))
                .lineLimit(2)
                .minimumScaleFactor(title == "网络" ? 0.42 : 0.5)
                .monospacedDigit()
                .frame(height: 52, alignment: .bottomLeading)
        }
        .frame(maxWidth: .infinity, minHeight: 104, maxHeight: 104, alignment: .leading)
        .padding(15)
        .background(tint, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.serveraBorder.opacity(0.6), lineWidth: 1))
    }
}

private extension NASControlPanelModule {
    var accentColor: Color {
        switch tintName {
        case "leaf": .serveraLeaf
        case "sky": .serveraSky
        case "amber": .serveraAmber
        case "cyan": .cyan
        case "slate": .serveraTextSecondary
        default: .serveraAccentDeep
        }
    }
}

private extension Error {
    var isNASControlPanelCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        return localizedDescription.localizedCaseInsensitiveContains("cancel")
            || localizedDescription.contains("取消")
    }
}
