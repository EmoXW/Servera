import SwiftUI
import SwiftData

// MARK: - 服务器编辑流程
// 编辑服务器时，保存前重新验证 SSH 和 Host Key 状态。
// 密码/私钥字段留空表示继续使用现有 Keychain 凭据。

struct ServerEditSheet: View {
    let deviceID: UUID
    var onSaved: (DashboardDevice) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var account = "root"
    @State private var password = ""
    @State private var authenticationKind: ServerAuthenticationKind = .password
    @State private var privateKeyPEM = ""
    @State private var privateKeyPassphrase = ""
    @State private var originalName = ""
    @State private var originalHost = ""
    @State private var originalPort = 22
    @State private var originalAccount = "root"
    @State private var originalAuthenticationKind: ServerAuthenticationKind = .password
    @State private var isSaving = false
    @State private var connectionStage = ""
    @State private var errorMessage: String?
    @State private var pendingHostKeyPrompt: ServerEditHostKeyPrompt?
    @State private var pendingChangedHostKeyPrompt: ServerEditHostKeyPrompt?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    AddMachineIllustration(kind: .server)

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

                    ServeraCard {
                        Label("密码或私钥留空时，会沿用已保存的 Keychain 凭据；修改主机、端口、账号或凭据后需要重新 SSH 验证。", systemImage: "key.fill")
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
                            Text(isSaving ? "正在验证并保存" : "保存连接")
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
            .navigationTitle("编辑连接")
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
        .alert(item: $pendingHostKeyPrompt) { prompt in
            Alert(
                title: Text("确认服务器 Host Key"),
                message: Text("首次连接 \(prompt.submission.host):\(String(prompt.submission.port))，请确认指纹可信后继续。\n\n算法：\(prompt.algorithm)\nSHA256：\(prompt.fingerprintSHA256)"),
                primaryButton: .default(Text("信任并保存")) {
                    Task {
                        await save(submission: prompt.submission, acceptUnknownHostKey: true, acceptChangedHostKey: false)
                    }
                },
                secondaryButton: .cancel(Text("取消")) {
                    isSaving = false
                    connectionStage = ""
                }
            )
        }
        .alert(item: $pendingChangedHostKeyPrompt) { prompt in
            Alert(
                title: Text("确认服务器已重装？"),
                message: Text("这台服务器的 Host Key 与本机已信任记录不一致。常见原因是服务器重装或换系统，也可能存在中间人风险。\n\n如果你确认这是自己的服务器，请更新信任后保存。\n\n算法：\(prompt.algorithm)\nSHA256：\(prompt.fingerprintSHA256)"),
                primaryButton: .destructive(Text("确认重装，更新并保存")) {
                    Task {
                        await save(submission: prompt.submission, acceptUnknownHostKey: false, acceptChangedHostKey: true)
                    }
                },
                secondaryButton: .cancel(Text("取消")) {
                    isSaving = false
                    connectionStage = ""
                }
            )
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
            authenticationKind = record.authenticationKind
            originalName = record.name
            originalHost = record.host
            originalPort = record.port
            originalAccount = record.account
            originalAuthenticationKind = record.authenticationKind
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard !isSaving else { return }
        guard let submission = makeSubmission() else { return }

        // 先使用严格 Host Key 策略。Traversio 如果报告未知或变更的 Key，
        // catch 分支会弹出确认框，用户确认后再重试。
        Task {
            await save(submission: submission, acceptUnknownHostKey: false, acceptChangedHostKey: false)
        }
    }

    @MainActor
    private func save(submission: ServerEditSubmission, acceptUnknownHostKey: Bool, acceptChangedHostKey: Bool) async {
        isSaving = true
        connectionStage = acceptChangedHostKey ? "更新 Host Key 并保存" : "准备保存"

        do {
            guard let record = try fetchRecord() else {
                throw ServeraSSHError.connectionFailed("未找到本地设备记录。")
            }

            if !submission.requiresVerification {
                // 只改显示名称时，不触碰凭据，也不重新连接。
                record.name = submission.name
                record.updatedAt = .now
                try modelContext.save()
                onSaved(record.dashboardDevice)
                isSaving = false
                dismiss()
                return
            }

            // 任何影响连接的编辑，都必须通过一次新的 SSH 校验后才能保存主机/账号/凭据。
            let credential = try credentialBundle(for: record, submission: submission)
            let request = SSHConnectionRequest(
                host: submission.host,
                port: submission.port,
                username: submission.account,
                authenticationKind: submission.authenticationKind,
                credential: credential,
                acceptUnknownHostKey: acceptUnknownHostKey,
                acceptChangedHostKey: acceptChangedHostKey
            )
            let outcome = try await SSHConnectionService.shared.validateAndCollect(request: request) { stage in
                await MainActor.run {
                    connectionStage = stage
                }
            }

            let credentialRef = try KeychainService.saveCredentialBundle(
                credential,
                id: record.credentialIdentifier ?? UUID().uuidString
            )
            record.name = submission.name
            record.host = submission.host
            record.port = submission.port
            record.account = submission.account
            record.authenticationKind = submission.authenticationKind
            record.credentialIdentifier = credentialRef.id
            record.applyServerSnapshot(outcome)
            try modelContext.save()

            onSaved(record.dashboardDevice)
            isSaving = false
            dismiss()
        } catch let error as ServeraSSHError {
            if case .unknownHostKey(let algorithm, let fingerprintSHA256) = error {
                pendingHostKeyPrompt = ServerEditHostKeyPrompt(
                    submission: submission,
                    algorithm: algorithm,
                    fingerprintSHA256: fingerprintSHA256
                )
            } else if case .hostKeyChanged(let algorithm, let fingerprintSHA256) = error {
                pendingChangedHostKeyPrompt = ServerEditHostKeyPrompt(
                    submission: submission,
                    algorithm: algorithm,
                    fingerprintSHA256: fingerprintSHA256
                )
            } else {
                errorMessage = error.localizedDescription
            }
            isSaving = false
            connectionStage = ""
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
            connectionStage = ""
        }
    }

    private func makeSubmission() -> ServerEditSubmission? {
        // 标识字段可以 trim，但密钥字段必须保持原样；口令可能合法包含首尾空格。
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedHost.isEmpty else {
            errorMessage = "请输入服务器主机地址。"
            return nil
        }
        guard !isDocumentationAddress(trimmedHost) else {
            errorMessage = "这是文档示例地址，不能作为真实设备保存。请输入你的服务器地址。"
            return nil
        }
        guard let parsedPort = Int(port), (1...65535).contains(parsedPort) else {
            errorMessage = "端口需要是 1 到 65535 之间的数字。"
            return nil
        }
        guard !trimmedAccount.isEmpty else {
            errorMessage = "请输入账号。"
            return nil
        }

        let displayName = trimmedName.isEmpty ? "New Server" : trimmedName
        let changedConnection = trimmedHost != originalHost
            || parsedPort != originalPort
            || trimmedAccount != originalAccount
            || authenticationKind != originalAuthenticationKind
            || !password.isEmpty
            || !privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !privateKeyPassphrase.isEmpty

        return ServerEditSubmission(
            name: displayName,
            host: trimmedHost,
            port: parsedPort,
            account: trimmedAccount,
            authenticationKind: authenticationKind,
            password: password,
            privateKeyPEM: privateKeyPEM,
            privateKeyPassphrase: privateKeyPassphrase,
            requiresVerification: changedConnection
        )
    }

    private func credentialBundle(for record: ManagedDeviceRecord, submission: ServerEditSubmission) throws -> DeviceCredentialBundle {
        // 密码/私钥字段留空表示复用 Keychain 中已有内容，
        // 这样用户只改服务器名称时不用重新输入敏感信息。
        let savedCredential: DeviceCredentialBundle?
        if let credentialIdentifier = record.credentialIdentifier {
            savedCredential = try KeychainService.loadCredentialBundle(id: credentialIdentifier)
        } else {
            savedCredential = nil
        }

        switch submission.authenticationKind {
        case .password:
            let passwordValue = submission.password.isEmpty ? savedCredential?.password : submission.password
            guard let passwordValue, !passwordValue.isEmpty else {
                throw ServeraSSHError.missingPassword
            }
            return DeviceCredentialBundle(password: passwordValue, privateKeyPEM: nil, privateKeyPassphrase: nil)
        case .privateKey:
            let keyValue = submission.privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? savedCredential?.privateKeyPEM : submission.privateKeyPEM
            guard let keyValue, !keyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ServeraSSHError.missingPrivateKey
            }
            let passphrase = submission.privateKeyPassphrase.isEmpty ? savedCredential?.privateKeyPassphrase : submission.privateKeyPassphrase
            return DeviceCredentialBundle(password: nil, privateKeyPEM: keyValue, privateKeyPassphrase: passphrase)
        }
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
}

private struct ServerEditSubmission: Hashable {
    let name: String
    let host: String
    let port: Int
    let account: String
    let authenticationKind: ServerAuthenticationKind
    let password: String
    let privateKeyPEM: String
    let privateKeyPassphrase: String
    let requiresVerification: Bool
}

private struct ServerEditHostKeyPrompt: Identifiable {
    let id = UUID()
    let submission: ServerEditSubmission
    let algorithm: String
    let fingerprintSHA256: String
}
