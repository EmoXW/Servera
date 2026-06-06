import SwiftUI
import SwiftData

// MARK: - NAS 编辑流程
// 编辑 NAS 连接信息时，保存前重新验证 DSM 凭据。
// 密码是可选项：留空表示继续使用现有 Keychain 密钥。

struct NASEditSheet: View {
    let deviceID: UUID
    var onSaved: (DashboardDevice) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var host = ""
    @State private var port = "5000"
    @State private var account = ""
    @State private var password = ""
    @State private var protocolSelection: NASConnectionProtocol = .http
    @State private var verifySSLCertificate = true
    @State private var originalName = ""
    @State private var originalHost = ""
    @State private var originalPort = 5000
    @State private var originalAccount = ""
    @State private var originalProtocol: NASConnectionProtocol = .http
    @State private var originalVerifySSLCertificate = true
    @State private var isSaving = false
    @State private var connectionStage = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    AddMachineIllustration(kind: .nas)

                    NASConnectionForm(
                        name: $name,
                        host: $host,
                        port: $port,
                        account: $account,
                        password: $password,
                        protocolSelection: $protocolSelection,
                        verifySSLCertificate: $verifySSLCertificate
                    ) { protocolValue in
                        if port == "5000" || port == "5001" {
                            port = protocolValue == .https ? "5001" : "5000"
                        }
                    }

                    ServeraCard {
                        Label("密码留空时会沿用 Keychain 中已保存的 DSM 密码；修改地址、端口、账号或密码后需要重新登录验证。", systemImage: "lock.shield.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.serveraTextSecondary)
                            .lineSpacing(3)
                    }

                    Button {
                        save()
                    } label: {
                        HStack(spacing: 10) {
                            if isSaving {
                                ProgressView()
                            } else {
                                Image(systemName: "checkmark.seal.fill")
                            }
                            Text(isSaving ? "正在验证并保存" : "保存 NAS")
                        }
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.serveraAccentDeep, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)

                    if isSaving, !connectionStage.isEmpty {
                        Text(connectionStage)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.serveraTextSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .background(ServeraBackground().ignoresSafeArea())
            .navigationTitle("编辑 NAS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        .task(id: deviceID) {
            loadRecord()
        }
        .alert("保存失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func loadRecord() {
        do {
            guard let record = try fetchRecord() else { return }
            name = record.name
            host = record.host
            port = String(record.port)
            account = record.account
            protocolSelection = record.nasProtocol
            verifySSLCertificate = record.nasVerifySSLCertificate
            password = ""
            originalName = record.name
            originalHost = record.host
            originalPort = record.port
            originalAccount = record.account
            originalProtocol = record.nasProtocol
            originalVerifySSLCertificate = record.nasVerifySSLCertificate
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard !isSaving else { return }
        guard let submission = makeSubmission() else { return }

        // NAS 连接字段保存前必须通过 DSM 验证，否则错误的 SSL/协议/端口会让记录失联。
        Task {
            await save(submission: submission)
        }
    }

    @MainActor
    private func save(submission: NASEditSubmission) async {
        isSaving = true
        connectionStage = "准备保存"

        do {
            guard let record = try fetchRecord() else {
                throw SynologyClientError.connectionFailed("未找到本地 NAS 记录。")
            }

            if !submission.requiresVerification {
                // 只改显示名称时保留当前 DSM 快照。
                record.name = submission.name
                record.updatedAt = .now
                try modelContext.save()
                onSaved(record.dashboardDevice)
                isSaving = false
                dismiss()
                return
            }

            // 连接信息变更后重新采集，避免存储、Docker、控制面板继续显示旧端点的数据。
            let passwordValue = try passwordValue(for: record, submission: submission)
            connectionStage = "探测 DSM API"
            let request = SynologyConnectionRequest(
                host: submission.host,
                port: submission.port,
                scheme: submission.protocolSelection,
                account: submission.account,
                password: passwordValue,
                verifySSLCertificate: submission.verifySSLCertificate
            )
            let outcome = try await SynologyClient.shared.validateAndCollect(request: request)

            connectionStage = "保存 NAS 状态"
            let credentialRef = try KeychainService.saveSecret(
                passwordValue,
                id: record.credentialIdentifier ?? UUID().uuidString
            )
            record.name = submission.name
            record.host = submission.host
            record.port = submission.port
            record.account = submission.account
            record.nasProtocol = submission.protocolSelection
            record.nasVerifySSLCertificate = submission.verifySSLCertificate
            record.credentialIdentifier = credentialRef.id
            record.applySynologySnapshot(outcome)
            try modelContext.save()

            onSaved(record.dashboardDevice)
            isSaving = false
            dismiss()
        } catch {
            errorMessage = formattedNASError(error)
            isSaving = false
            connectionStage = ""
        }
    }

    private func makeSubmission() -> NASEditSubmission? {
        // 不 trim 密码。DSM 密码可能故意包含空格，留空则表示复用现有密码。
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedHost.isEmpty else {
            errorMessage = "请输入 DSM 地址、IP 或域名。"
            return nil
        }
        guard !isDocumentationAddress(trimmedHost) else {
            errorMessage = "这是文档示例地址，不能作为真实设备保存。请输入你的 NAS 地址。"
            return nil
        }
        guard let parsedPort = Int(port), (1...65535).contains(parsedPort) else {
            errorMessage = "端口需要是 1 到 65535 之间的数字。"
            return nil
        }
        guard !trimmedAccount.isEmpty else {
            errorMessage = "请输入 DSM 账号。"
            return nil
        }

        let displayName = trimmedName.isEmpty ? "New NAS" : trimmedName
        let changedConnection = trimmedHost != originalHost
            || parsedPort != originalPort
            || trimmedAccount != originalAccount
            || protocolSelection != originalProtocol
            || verifySSLCertificate != originalVerifySSLCertificate
            || !password.isEmpty

        return NASEditSubmission(
            name: displayName,
            host: trimmedHost,
            port: parsedPort,
            account: trimmedAccount,
            password: password,
            protocolSelection: protocolSelection,
            verifySSLCertificate: verifySSLCertificate,
            requiresVerification: changedConnection
        )
    }

    private func passwordValue(for record: ManagedDeviceRecord, submission: NASEditSubmission) throws -> String {
        // 编辑时密码框为空是“保留原密码”的信号，不是清空 Keychain 密码。
        if !submission.password.isEmpty {
            return submission.password
        }
        guard let credentialIdentifier = record.credentialIdentifier,
              let savedPassword = try KeychainService.loadSecret(id: credentialIdentifier),
              !savedPassword.isEmpty else {
            throw SynologyClientError.authenticationFailed("DSM 凭据不存在，请重新输入密码。")
        }
        return savedPassword
    }

    private func fetchRecord() throws -> ManagedDeviceRecord? {
        let descriptor = FetchDescriptor<ManagedDeviceRecord>(
            predicate: #Predicate { $0.deviceID == deviceID }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func isDocumentationAddress(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.hasPrefix("203.0.113.")
            || normalized.hasPrefix("198.51.100.")
            || normalized.hasPrefix("192.0.2.")
    }

    private func formattedNASError(_ error: Error) -> String {
        var message = error.localizedDescription
        if case SynologyClientError.authenticationFailed = error {
            message += "\n\n可以点密码框右侧眼睛检查大小写、半角句号和隐藏空格。"
        }
        message += "\n\n如果你输入的是 QuickConnect ID，本阶段建议先使用局域网 IP、域名或反向代理地址。"
        return message
    }
}

private struct NASEditSubmission {
    let name: String
    let host: String
    let port: Int
    let account: String
    let password: String
    let protocolSelection: NASConnectionProtocol
    let verifySSLCertificate: Bool
    let requiresVerification: Bool
}
