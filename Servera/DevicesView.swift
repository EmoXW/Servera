import SwiftUI
import SwiftData
import OSLog

private let addDeviceLogger = Logger(subsystem: "com.hs.Servera", category: "AddDevice")
private let prototypeInk = Color(red: 0.32, green: 0.25, blue: 0.34)

// MARK: - 设备添加流程
// SSH 服务器和群晖 NAS 共用同一个添加页。调用方传入 preferredKind，
// 让服务器/NAS 页的加号可以直接落到对应表单，而不用拆成两个添加页面。

struct DevicesView: View {
    var preferredKind: ManagedDeviceKind = .server
    var requestID: Int = 0
    var onDeviceAdded: (DashboardDevice) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\ManagedDeviceRecord.orderIndex), SortDescriptor(\ManagedDeviceRecord.createdAt)])
    private var deviceRecords: [ManagedDeviceRecord]
    @State private var selectedKind: ManagedDeviceKind = .server
    @State private var nasProtocol: NASConnectionProtocol = .http
    @State private var name = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var account = "root"
    @State private var password = ""
    @State private var authenticationKind: ServerAuthenticationKind = .password
    @State private var privateKeyPEM = ""
    @State private var privateKeyPassphrase = ""
    @State private var verifySSLCertificate = true
    @State private var isConnecting = false
    @State private var connectionStage = ""
    @State private var didConnect = false
    @State private var addStatus: AddDeviceStatus = .idle
    @State private var activeAlert: AddDeviceAlert?

    init(
        preferredKind: ManagedDeviceKind = .server,
        requestID: Int = 0,
        onDeviceAdded: @escaping (DashboardDevice) -> Void = { _ in }
    ) {
        self.preferredKind = preferredKind
        self.requestID = requestID
        self.onDeviceAdded = onDeviceAdded
        // 首次渲染必须匹配入口来源。requestID.onChange 只会处理后续加号请求，
        // 所以 NAS 默认值要在这里初始化，不能等后面的状态同步。
        _selectedKind = State(initialValue: preferredKind)
        switch preferredKind {
        case .server:
            _port = State(initialValue: "22")
            _account = State(initialValue: "root")
            _authenticationKind = State(initialValue: .password)
        case .nas:
            _nasProtocol = State(initialValue: .http)
            _port = State(initialValue: String(NASConnectionProtocol.http.defaultPort))
            _account = State(initialValue: "")
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                HeaderBar(title: "设备", trailing: "plus")

                Picker("设备类型", selection: $selectedKind) {
                    ForEach(ManagedDeviceKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .padding(4)
                .background(.white.opacity(0.62), in: Capsule())
                .onChange(of: selectedKind) { _, newValue in
                    applyDefaults(for: newValue)
                }

                AddMachineIllustration(kind: selectedKind)

                if selectedKind == .server {
                    SSHQuickPasteCard()
                } else {
                    NASQuickTipCard()
                }

                if selectedKind == .server {
                    ServerConnectionForm(
                        name: $name,
                        host: $host,
                        port: $port,
                        account: $account,
                        password: $password,
                        authenticationKind: $authenticationKind,
                        privateKeyPEM: $privateKeyPEM,
                        privateKeyPassphrase: $privateKeyPassphrase
                    )
                } else {
                    NASConnectionForm(
                        name: $name,
                        host: $host,
                        port: $port,
                        account: $account,
                        password: $password,
                        protocolSelection: $nasProtocol,
                        verifySSLCertificate: $verifySSLCertificate
                    ) { protocolSelection in
                        port = String(protocolSelection.defaultPort)
                    }
                }

                Button {
                    connect()
                } label: {
                    HStack(spacing: 10) {
                        if isConnecting {
                            ProgressView()
                        } else {
                            Image(systemName: didConnect ? "checkmark.circle.fill" : "bolt.horizontal.circle.fill")
                        }
                        Text(isConnecting ? "正在验证连接" : didConnect ? "连接成功，已加入列表" : "连接并添加设备")
                    }
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(didConnect ? Color.serveraLeaf : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(didConnect ? Color.serveraLeafSoft : Color.serveraAccentDeep, in: Capsule())
                    .shadow(color: Color.serveraAccent.opacity(0.18), radius: 18, y: 10)
                }
                .buttonStyle(.plain)
                .disabled(isConnecting)
                .contentShape(Capsule())

                if addStatus.isVisible {
                    AddDeviceStatusBanner(status: addStatus)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(selectedKind == .server ? "SSH 添加的设备会进入 Server 与 Docker 栏" : "NAS 添加后只进入 NAS 栏，避免和 Server 混淆")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.serveraLeaf)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(Color.serveraLeafSoft, in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .error(let message):
                Alert(
                    title: Text("无法添加设备"),
                    message: Text(message),
                    dismissButton: .default(Text("知道了"))
                )
            case .unknownHostKey(let prompt):
                Alert(
                    title: Text("确认服务器 Host Key"),
                    message: Text("首次连接 \(prompt.form.host):\(String(prompt.form.port))，请确认指纹可信后继续。\n\n算法：\(prompt.algorithm)\nSHA256：\(prompt.fingerprintSHA256)"),
                    primaryButton: .default(Text("信任并继续")) {
                        trustHostKeyAndRetry(prompt, changedHostKey: false)
                    },
                    secondaryButton: .cancel(Text("取消")) {
                        connectionStage = ""
                        isConnecting = false
                        addStatus = .failed("已取消 Host Key 信任，设备没有添加。")
                    }
                )
            case .changedHostKey(let prompt):
                Alert(
                    title: Text("确认服务器已重装？"),
                    message: Text("这台服务器的 Host Key 与本机已信任记录不一致。常见原因是服务器重装或换系统，也可能存在中间人风险。\n\n如果你确认这是自己的服务器，请更新信任后继续。\n\n算法：\(prompt.algorithm)\nSHA256：\(prompt.fingerprintSHA256)"),
                    primaryButton: .destructive(Text("确认重装，更新并继续")) {
                        trustHostKeyAndRetry(prompt, changedHostKey: true)
                    },
                    secondaryButton: .cancel(Text("取消")) {
                        connectionStage = ""
                        isConnecting = false
                        addStatus = .failed("已取消 Host Key 更新，设备没有添加。")
                    }
                )
            }
        }
        .onChange(of: requestID) { _, _ in
            selectedKind = preferredKind
            applyDefaults(for: preferredKind)
        }
    }

    private func applyDefaults(for kind: ManagedDeviceKind) {
        // 用户手动切换类型，或服务器/NAS 加号发起新添加流程时重置表单。
        // 这样 NAS 保持 5000、SSH 保持 22，不会把上一种设备的旧字段带过来。
        didConnect = false
        connectionStage = ""
        addStatus = .idle
        activeAlert = nil

        switch kind {
        case .server:
            name = ""
            host = ""
            port = "22"
            account = "root"
            authenticationKind = .password
        case .nas:
            name = ""
            host = ""
            nasProtocol = .http
            port = String(NASConnectionProtocol.http.defaultPort)
            account = ""
        }
    }

    private func connect() {
        guard !isConnecting else { return }
        activeAlert = nil
        didConnect = false
        connectionStage = "正在检查输入"
        withAnimation(.easeInOut(duration: 0.18)) {
            addStatus = .connecting(connectionStage)
        }

        #if DEBUG
        print("[DevicesView] add button tapped kind=\(selectedKind.rawValue)")
        #endif
        addDeviceLogger.info("Add button tapped kind=\(selectedKind.rawValue, privacy: .public)")

        // 校验前先提交硬件键盘/输入法组合态。否则用户看到的密码框内容
        // 可能已经变化，但 SwiftUI 状态还没写入。
        UIApplication.shared.serveraEndEditing()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !isConnecting else { return }
            guard let form = validatedForm() else { return }
            isConnecting = true
            didConnect = false
            connectionStage = selectedKind == .server
                ? "正在连接 \(form.host):\(form.port)"
                : "正在登录 DSM \(form.host):\(form.port)"
            withAnimation(.easeInOut(duration: 0.18)) {
                addStatus = .connecting(connectionStage)
            }

            #if DEBUG
            print("[DevicesView] add \(selectedKind.rawValue) tapped host=\(form.host) port=\(form.port) account=\(form.account)")
            #endif
            addDeviceLogger.info("Add \(selectedKind.rawValue, privacy: .public) tapped host=\(form.host, privacy: .public) port=\(form.port) account=\(form.account, privacy: .public)")

            if selectedKind == .server {
                await connectServer(form)
            } else {
                await saveNAS(form)
            }
        }
    }

    @MainActor
    private func connectServer(_ form: DeviceForm, acceptUnknownHostKey: Bool = false, acceptChangedHostKey: Bool = false) async {
        do {
            // SSH 连接成功并采集到系统状态前不保存任何记录。
            // Host Key 弹窗会有意中断这里，等用户明确确认后再重试。
            let bundle = DeviceCredentialBundle(
                password: authenticationKind == .password ? password : nil,
                privateKeyPEM: authenticationKind == .privateKey ? privateKeyPEM : nil,
                privateKeyPassphrase: authenticationKind == .privateKey ? privateKeyPassphrase : nil
            )
            let request = SSHConnectionRequest(
                host: form.host,
                port: form.port,
                username: form.account,
                authenticationKind: authenticationKind,
                credential: bundle,
                acceptUnknownHostKey: acceptUnknownHostKey,
                acceptChangedHostKey: acceptChangedHostKey
            )
            let outcome = try await SSHConnectionService.shared.validateAndCollect(request: request) { stage in
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        connectionStage = stage
                        addStatus = .connecting(stage)
                    }
                }
            }
            let credentialRef = try KeychainService.saveCredentialBundle(bundle)
            let record = ManagedDeviceRecord(
                name: form.displayName,
                host: form.host,
                port: form.port,
                kind: .server,
                account: form.account,
                credentialIdentifier: credentialRef.id,
                authenticationKind: authenticationKind,
                orderIndex: (deviceRecords.map(\.orderIndex).max() ?? -1) + 1,
                connectionStatus: .online
            )
            record.applyServerSnapshot(outcome)

            modelContext.insert(record)
            try modelContext.save()
            let addedDevice = record.dashboardDevice

            withAnimation(.spring(response: 0.44, dampingFraction: 0.78)) {
                isConnecting = false
                didConnect = true
                connectionStage = "已采集系统状态"
                addStatus = .success("连接成功，已采集系统状态。")
                password = ""
                privateKeyPEM = ""
                privateKeyPassphrase = ""
            }
            onDeviceAdded(addedDevice)
        } catch let error as ServeraSSHError {
            #if DEBUG
            print("[DevicesView] SSH add failed host=\(form.host):\(form.port) error=\(error.localizedDescription)")
            #endif
            addDeviceLogger.error("SSH add failed host=\(form.host, privacy: .public):\(form.port) error=\(error.localizedDescription, privacy: .public)")
            isConnecting = false
            connectionStage = ""
            if case .unknownHostKey(let algorithm, let fingerprintSHA256) = error {
                let prompt = PendingHostKeyPrompt(
                    form: form,
                    algorithm: algorithm,
                    fingerprintSHA256: fingerprintSHA256
                )
                addStatus = .waitingConfirmation("需要确认服务器 Host Key 后继续。")
                activeAlert = .unknownHostKey(prompt)
            } else if case .hostKeyChanged(let algorithm, let fingerprintSHA256) = error {
                let prompt = PendingHostKeyPrompt(
                    form: form,
                    algorithm: algorithm,
                    fingerprintSHA256: fingerprintSHA256
                )
                addStatus = .waitingConfirmation("Host Key 已变化，需要确认是否重装后继续。")
                activeAlert = .changedHostKey(prompt)
            } else {
                showAddError(formattedServerError(error))
            }
        } catch {
            #if DEBUG
            print("[DevicesView] SSH add failed host=\(form.host):\(form.port) error=\(error.localizedDescription)")
            #endif
            addDeviceLogger.error("SSH add failed host=\(form.host, privacy: .public):\(form.port) error=\(error.localizedDescription, privacy: .public)")
            isConnecting = false
            connectionStage = ""
            showAddError(formattedServerError(error))
        }
    }

    private func trustHostKeyAndRetry(_ prompt: PendingHostKeyPrompt, changedHostKey: Bool) {
        guard !isConnecting else { return }
        isConnecting = true
        didConnect = false
        connectionStage = changedHostKey ? "已确认重装，更新 Host Key" : "已确认 Host Key，继续登录"
        addStatus = .connecting(connectionStage)
        Task {
            await connectServer(
                prompt.form,
                acceptUnknownHostKey: !changedHostKey,
                acceptChangedHostKey: changedHostKey
            )
        }
    }

    @MainActor
    private func saveNAS(_ form: DeviceForm) async {
        do {
            // 添加 NAS 前先验证 DSM 并保存首个快照，再插入记录，
            // 这样进入 NAS 页时马上有可用信息。
            connectionStage = "探测 DSM API"
            let request = SynologyConnectionRequest(
                host: form.host,
                port: form.port,
                scheme: nasProtocol,
                account: form.account,
                password: password,
                verifySSLCertificate: verifySSLCertificate
            )
            let outcome = try await SynologyClient.shared.validateAndCollect(request: request)
            connectionStage = "保存 NAS 状态"
            let credentialRef = try KeychainService.saveSecret(password)
            let record = ManagedDeviceRecord(
                name: form.displayName,
                host: form.host,
                port: form.port,
                kind: .nas,
                nasProtocol: nasProtocol,
                nasVerifySSLCertificate: verifySSLCertificate,
                account: form.account,
                credentialIdentifier: credentialRef.id,
                orderIndex: (deviceRecords.map(\.orderIndex).max() ?? -1) + 1,
                connectionStatus: .online,
                dockerDetected: false,
                dockerContainerCount: 0,
                cpuPercent: 0,
                ramPercent: 0
            )
            record.applySynologySnapshot(outcome)

            modelContext.insert(record)
            try modelContext.save()
            let addedDevice = record.dashboardDevice

            withAnimation(.spring(response: 0.44, dampingFraction: 0.78)) {
                isConnecting = false
                didConnect = true
                connectionStage = ""
                addStatus = .success("NAS 连接成功，已保存最新状态。")
                password = ""
            }
            onDeviceAdded(addedDevice)
        } catch {
            isConnecting = false
            connectionStage = ""
            showAddError(formattedNASError(error))
        }
    }

    private func validatedForm() -> DeviceForm? {
        // 只 trim 标识类字段。密码和私钥保持用户原始输入，因为空格可能有意义。
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedHost.isEmpty else {
            showAddError(selectedKind == .server ? "请输入服务器主机地址。" : "请输入 DSM 地址、IP 或 QuickConnect ID。")
            return nil
        }
        guard !isDocumentationAddress(trimmedHost) else {
            showAddError("这是文档示例地址，不能作为真实设备保存。请输入你的服务器或 NAS 地址。")
            return nil
        }
        guard let parsedPort = Int(port), (1...65535).contains(parsedPort) else {
            showAddError("端口需要是 1 到 65535 之间的数字。")
            return nil
        }
        guard !trimmedAccount.isEmpty else {
            showAddError("请输入账号。")
            return nil
        }
        if selectedKind == .server {
            switch authenticationKind {
            case .password where password.isEmpty:
                showAddError("请输入 SSH 密码。")
                return nil
            case .privateKey where privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
                showAddError("请粘贴 OpenSSH 私钥内容。")
                return nil
            default:
                break
            }
        } else if password.isEmpty {
            showAddError("请输入 DSM 密码。")
            return nil
        }

        return DeviceForm(
            displayName: trimmedName.isEmpty ? (selectedKind == .server ? "New Server" : "New NAS") : trimmedName,
            host: trimmedHost,
            port: parsedPort,
            account: trimmedAccount
        )
    }

    private func isDocumentationAddress(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.hasPrefix("203.0.113.")
            || normalized.hasPrefix("198.51.100.")
            || normalized.hasPrefix("192.0.2.")
    }

    private func saveCredentialIfNeeded() throws -> DeviceCredentialRef? {
        // 旧的纯密码保存辅助方法保留给老调用点；新的 SSH 流程使用 DeviceCredentialBundle。
        guard !password.isEmpty else { return nil }
        return try KeychainService.saveSecret(password)
    }

    private func formattedNASError(_ error: Error) -> String {
        var message = error.localizedDescription
        if case SynologyClientError.authenticationFailed = error {
            message += "\n\n可以点密码框右侧眼睛检查大小写、半角句号和隐藏空格。"
        }
        message += "\n\n如果你输入的是 QuickConnect ID，本阶段建议先使用局域网 IP、域名或反向代理地址。"
        return message
    }

    private func formattedServerError(_ error: Error) -> String {
        if let sshError = error as? ServeraSSHError, sshError.isCancellation {
            return "SSH 连接被取消，设备没有添加。\n\n如果是在模拟器里测试，当前连接可能被 Mac 系统代理或 127.0.0.1:7890 这类本地代理中断。请关闭代理或把 SSH 目标加入直连规则后重试。"
        }

        var message = error.localizedDescription
        if let sshError = error as? ServeraSSHError {
            switch sshError {
            case .authenticationFailed:
                message += "\n\n可以点密码框右侧眼睛检查大小写，或打开 A↑ 处理模拟器硬件键盘大写输入异常。"
            case .unreachable(let failureMessage):
                if failureMessage.localizedCaseInsensitiveContains("cancel")
                    || failureMessage.localizedCaseInsensitiveContains("proxy")
                    || failureMessage.contains("7890") {
                    message += "\n\n这次连接像是被系统代理或本地代理中断了。如果是在模拟器里测试，请关闭 Mac 代理，或把 \(host.trimmingCharacters(in: .whitespacesAndNewlines)) 加入直连/绕过代理规则。"
                } else {
                    message += "\n\n请确认服务器端口已开放；如果是在模拟器里测试，也检查 Mac 网络代理是否拦截了 SSH 连接。"
                }
            default:
                break
            }
        }
        return message
    }

    private func showAddError(_ message: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            addStatus = .failed(message)
        }
        activeAlert = .error(message)
    }
}

private struct DeviceForm {
    let displayName: String
    let host: String
    let port: Int
    let account: String
}

private struct PendingHostKeyPrompt: Identifiable {
    let id = UUID()
    let form: DeviceForm
    let algorithm: String
    let fingerprintSHA256: String
}

private enum AddDeviceAlert: Identifiable {
    case error(String)
    case unknownHostKey(PendingHostKeyPrompt)
    case changedHostKey(PendingHostKeyPrompt)

    var id: String {
        switch self {
        case .error(let message):
            "error-\(message)"
        case .unknownHostKey(let prompt):
            "unknown-\(prompt.id)"
        case .changedHostKey(let prompt):
            "changed-\(prompt.id)"
        }
    }
}

private enum AddDeviceStatus: Equatable {
    case idle
    case connecting(String)
    case waitingConfirmation(String)
    case failed(String)
    case success(String)

    var isVisible: Bool {
        if case .idle = self { return false }
        return true
    }

    var message: String {
        switch self {
        case .idle:
            ""
        case .connecting(let message),
             .waitingConfirmation(let message),
             .failed(let message),
             .success(let message):
            message
        }
    }

    var iconName: String {
        switch self {
        case .idle:
            "circle"
        case .connecting:
            "arrow.triangle.2.circlepath"
        case .waitingConfirmation:
            "key.horizontal.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .success:
            "checkmark.circle.fill"
        }
    }

    var foregroundColor: Color {
        switch self {
        case .idle:
            Color.serveraTextSecondary
        case .connecting:
            Color.serveraAccentDeep
        case .waitingConfirmation:
            Color.serveraAmber
        case .failed:
            Color.red.opacity(0.78)
        case .success:
            Color.serveraLeaf
        }
    }

    var backgroundColor: Color {
        switch self {
        case .idle:
            Color.serveraSurface.opacity(0.72)
        case .connecting:
            Color.serveraAccent.opacity(0.12)
        case .waitingConfirmation:
            Color.serveraAmber.opacity(0.13)
        case .failed:
            Color.red.opacity(0.08)
        case .success:
            Color.serveraLeafSoft
        }
    }
}

private struct AddDeviceStatusBanner: View {
    let status: AddDeviceStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: status.iconName)
                .font(.system(size: 13, weight: .black))
                .symbolEffect(.pulse, options: .repeating, isActive: isPulsing)

            Text(status.message)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .foregroundStyle(status.foregroundColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(status.backgroundColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(status.foregroundColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var isPulsing: Bool {
        if case .connecting = status { return true }
        return false
    }
}

struct SSHQuickPasteCard: View {
    var body: some View {
        ServeraCard {
            VStack(alignment: .leading, spacing: 13) {
                Text("快速粘贴")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.serveraTextSecondary)
                Text("ssh root@example.com -p 22")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.serveraTextSecondary.opacity(0.55))
                Divider().overlay(Color.serveraBorder)
                Label("解析 SSH 命令", systemImage: "sparkles")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.purple.opacity(0.75))
            }
        }
    }
}

struct NASQuickTipCard: View {
    var body: some View {
        ServeraCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("DSM 快速连接", systemImage: "externaldrive.connected.to.line.below")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Color.serveraAccentDeep)
                Text("支持局域网 IP、域名或 QuickConnect ID。HTTP 默认 5000，HTTPS 默认 5001。")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .lineSpacing(3)
            }
        }
    }
}

struct ServerConnectionForm: View {
    @Binding var name: String
    @Binding var host: String
    @Binding var port: String
    @Binding var account: String
    @Binding var password: String
    @Binding var authenticationKind: ServerAuthenticationKind
    @Binding var privateKeyPEM: String
    @Binding var privateKeyPassphrase: String

    var body: some View {
        VStack(spacing: 12) {
            ServeraCard {
                VStack(alignment: .leading, spacing: 14) {
                    EditableFormLine(title: "设备备注", text: $name)
                    EditableFormLine(title: "主机", text: $host)
                    EditableFormLine(title: "端口", text: $port, keyboardType: .numberPad)
                }
            }

            ServeraCard {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("认证方式", selection: $authenticationKind) {
                        ForEach(ServerAuthenticationKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 12) {
                        EditableFormLine(title: "账号", text: $account)
                        if authenticationKind == .password {
                            PasswordFormLine(title: "密码", text: $password)
                        } else {
                            PasswordFormLine(title: "私钥口令", text: $privateKeyPassphrase)
                        }
                    }

                    if authenticationKind == .privateKey {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("OpenSSH 私钥")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.serveraTextSecondary)
                            TextEditor(text: $privateKeyPEM)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .frame(minHeight: 120)
                                .padding(10)
                                .scrollContentBackground(.hidden)
                                .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.serveraBorder.opacity(0.8), lineWidth: 1))
                        }
                    }

                    Text("服务器会先完成 Host Key 信任、SSH 登录，再采集系统状态；敏感凭据只保存到本机 Keychain。")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.serveraTextSecondary)
                        .lineSpacing(2)
                }
            }
        }
    }
}

struct NASConnectionForm: View {
    @Binding var name: String
    @Binding var host: String
    @Binding var port: String
    @Binding var account: String
    @Binding var password: String
    @Binding var protocolSelection: NASConnectionProtocol
    @Binding var verifySSLCertificate: Bool
    let onProtocolChanged: (NASConnectionProtocol) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ServeraCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("协议")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.serveraTextSecondary)
                            Picker("协议", selection: $protocolSelection) {
                                ForEach(NASConnectionProtocol.allCases) { item in
                                    Text(item.rawValue).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 118)
                            .onChange(of: protocolSelection) { _, newValue in
                                onProtocolChanged(newValue)
                            }
                        }

                        EditableFormLine(title: "网址/IP/QuickConnect ID", text: $host)
                    }

                    EditableFormLine(title: "端口", text: $port, keyboardType: .numberPad)
                    EditableFormLine(title: "设备备注", text: $name)
                }
            }

            ServeraCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        EditableFormLine(title: "账号", text: $account)
                        PasswordFormLine(title: "密码", text: $password)
                    }

                    Toggle("验证 SSL 证书", isOn: $verifySSLCertificate)
                        .font(.system(size: 16, weight: .heavy))
                        .tint(Color.serveraAccentDeep)
                    Text("如果 DSM 使用自签名证书，HTTPS 连接失败时可以临时关闭 SSL 校验。")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.serveraTextSecondary)
                        .lineSpacing(2)
                }
            }
        }
    }
}

struct AddMachineIllustration: View {
    let kind: ManagedDeviceKind

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                PrototypeLaptop()
                    .offset(x: -88, y: 10)

                PrototypeConnectionDots()
                    .offset(x: 0, y: -2)

                PrototypeTower()
                    .offset(x: 88, y: -4)
            }
            .frame(height: 118)

            VStack(spacing: 8) {
                Text(kind == .server ? "服务器在哪里？" : "NAS 在哪里？")
                    .font(.system(size: 26, weight: .black))
                Text(kind == .server ? "粘贴 SSH 命令或手动输入地址，连接成功后会自动加入仪表盘。" : "输入 DSM 地址、端口或 QuickConnect ID，用轻量方式查看 NAS 状态。")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .padding(.top, 12)
    }
}

private struct PrototypeConnectionDots: View {
    var body: some View {
        HStack(spacing: 9) {
            PrototypeConnectionDot(isSmall: false)
            PrototypeConnectionDot(isSmall: true)
            PrototypeConnectionDot(isSmall: false)
        }
    }
}

private struct PrototypeConnectionDot: View {
    let isSmall: Bool

    var body: some View {
        Circle()
            .fill(isSmall ? Color.serveraAccent.opacity(0.28) : .white.opacity(0.82))
            .frame(width: isSmall ? 7 : 14, height: isSmall ? 7 : 14)
            .overlay {
                Circle()
                    .stroke(prototypeInk.opacity(isSmall ? 0 : 0.78), lineWidth: isSmall ? 0 : 3)
            }
    }
}

private struct PrototypeLaptop: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.72))
                .frame(width: 92, height: 58)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(prototypeInk.opacity(0.82), lineWidth: 4)
                }
                .offset(y: -11)

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.serveraAccent.opacity(0.28))
                .frame(width: 108, height: 16)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(prototypeInk.opacity(0.82), lineWidth: 3)
                }
        }
        .frame(width: 116, height: 86)
    }
}

private struct PrototypeTower: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.serveraAccent.opacity(0.24))
            .frame(width: 58, height: 88)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(prototypeInk.opacity(0.82), lineWidth: 4)
            }
            .overlay {
                VStack(spacing: 16) {
                    Circle()
                        .fill(Color.orange.opacity(0.78))
                        .frame(width: 7, height: 7)
                    Circle()
                        .fill(Color.orange.opacity(0.78))
                        .frame(width: 7, height: 7)
                }
            }
    }
}

struct EditableFormLine: View {
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.serveraTextSecondary)
            Group {
                if isSecure {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                }
            }
            .font(.system(size: 18, weight: .medium))
            .keyboardType(keyboardType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityLabel(Text(title))
            .accessibilityIdentifier("form.\(title)")
            Divider().overlay(Color.serveraBorder)
        }
    }
}

struct PasswordFormLine: View {
    let title: String
    @Binding var text: String
    @State private var isVisible = false
    @State private var forceUppercaseInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.serveraTextSecondary)
            HStack(spacing: 8) {
                PasswordTextFieldRepresentable(
                    title: title,
                    text: $text,
                    isSecure: !isVisible,
                    forceUppercaseInput: forceUppercaseInput
                )
                .frame(height: 28)
                .privacySensitive()
                .accessibilityLabel(Text(title))
                .accessibilityIdentifier("form.\(title)")

                Button {
                    forceUppercaseInput.toggle()
                } label: {
                    Text("A↑")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(forceUppercaseInput ? .white : Color.serveraAccentDeep)
                        .frame(width: 34, height: 28)
                        .background(
                            forceUppercaseInput ? Color.serveraAccentDeep : Color.serveraAccent.opacity(0.14),
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(forceUppercaseInput ? "关闭大写输入" : "开启大写输入")

                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.serveraTextSecondary.opacity(0.72))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isVisible ? "隐藏密码" : "显示密码")
            }
            Divider().overlay(Color.serveraBorder)

            if let warningText {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(warningText)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.serveraAmber)
            }
            if forceUppercaseInput {
                Text("大写输入已开启，输入字母会按大写写入。")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.serveraAccentDeep)
            }
        }
    }

    private var warningText: String? {
        if text.contains("。") {
            return "密码里包含全角句号“。”，请确认是否应为半角“.”。"
        }
        if text.contains("\u{3000}") {
            return "密码里包含全角空格，请确认是否为误输入。"
        }
        if text.first?.isWhitespace == true || text.last?.isWhitespace == true {
            return "密码首尾包含空白字符，请确认是否需要保留。"
        }
        return nil
    }
}

// 密码输入的 UIKit 桥接层。这里不用 SecureField，是因为模拟器/硬件键盘组合态
// 曾导致“用户看到的输入”和“SwiftUI 实际提交的值”不一致。
struct PasswordTextFieldRepresentable: UIViewRepresentable {
    let title: String
    @Binding var text: String
    var isSecure: Bool
    var forceUppercaseInput: Bool

    func makeUIView(context: Context) -> ExactPasswordTextField {
        let textField = ExactPasswordTextField()
        textField.placeholder = title
        textField.font = .systemFont(ofSize: 18, weight: .medium)
        textField.textColor = .label
        textField.tintColor = UIColor(Color.serveraAccentDeep)
        textField.backgroundColor = .clear
        textField.borderStyle = .none
        textField.keyboardType = .default
        textField.textContentType = nil
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.smartInsertDeleteType = .no
        textField.clearButtonMode = .never
        textField.isSecureTextEntry = isSecure
        textField.forceUppercaseInput = forceUppercaseInput
        textField.delegate = context.coordinator
        textField.onExactTextChange = { value in
            context.coordinator.sync(value)
        }
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ textField: ExactPasswordTextField, context: Context) {
        textField.forceUppercaseInput = forceUppercaseInput
        if textField.text != text {
            textField.text = text
        }
        if textField.isSecureTextEntry != isSecure {
            // 切换安全输入可能重置 UITextField 的文本和光标位置，
            // 所以这里要恢复二者，保持密码框稳定。
            let wasFirstResponder = textField.isFirstResponder
            let selectedRange = textField.selectedTextRange
            textField.isSecureTextEntry = isSecure
            textField.text = text
            if wasFirstResponder {
                textField.becomeFirstResponder()
                if let selectedRange {
                    textField.selectedTextRange = selectedRange
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        @objc func textDidChange(_ textField: UITextField) {
            sync(textField.text ?? "")
        }

        func sync(_ value: String) {
            text = value
        }
    }
}

final class ExactPasswordTextField: UITextField {
    var onExactTextChange: ((String) -> Void)?
    var forceUppercaseInput = false

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // 在 UIKit 把错误的小写字符插入安全输入框前，先修正大小写偏移。
        guard
            let press = presses.first,
            let key = press.key,
            shouldRepairHardwareKeyboardInput(key)
        else {
            super.pressesBegan(presses, with: event)
            return
        }

        insertText(key.characters.uppercased())
    }

    override func insertText(_ text: String) {
        super.insertText(adjustedInsertedText(text))
        onExactTextChange?(self.text ?? "")
    }

    override func deleteBackward() {
        super.deleteBackward()
        onExactTextChange?(text ?? "")
    }

    private func shouldRepairHardwareKeyboardInput(_ key: UIKey) -> Bool {
        let modifiers = key.modifierFlags
        guard modifiers.contains(.shift) || modifiers.contains(.alphaShift) else {
            return false
        }
        guard key.characters.count == 1 else {
            return false
        }
        guard key.charactersIgnoringModifiers.count == 1 else {
            return false
        }
        return key.charactersIgnoringModifiers.rangeOfCharacter(from: .letters) != nil
            && key.characters == key.characters.lowercased()
    }

    private func adjustedInsertedText(_ value: String) -> String {
        // 手动 A↑ 模式是给模拟器键盘异常准备的用户兜底开关。
        // 它只影响单个字母，不处理标点或空格。
        guard forceUppercaseInput, value.count == 1 else { return value }
        guard value.rangeOfCharacter(from: .letters) != nil else { return value }
        return value.uppercased()
    }
}

struct FormLine: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.serveraTextSecondary)
            Text(value)
                .font(.system(size: 18, weight: .medium))
            Divider().overlay(Color.serveraBorder)
        }
    }
}

private extension UIApplication {
    func serveraEndEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
