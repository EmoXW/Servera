import SwiftData
import SwiftUI
import UIKit

// MARK: - 交互式 SSH 终端
// 基于 Traversio 交互 shell 的轻量终端界面。命令历史只保存在本机且限制数量，
// 避免它变成另一处敏感命令持久化入口。

struct ServerTerminalView: View {
    let device: DashboardDevice

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var inputFocused: Bool

    @State private var transcript = "Servera Terminal\n终端命令会直接在服务器执行。\n\n"
    @State private var commandInput = ""
    @State private var connectionState: TerminalConnectionState = .idle
    @State private var shellSession: SSHInteractiveShellSession?
    @State private var connectTask: Task<Void, Never>?
    @State private var streamTask: Task<Void, Never>?
    @State private var copiedOutput = false
    @State private var recentCommands: [String] = []

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.045, green: 0.04, blue: 0.055),
                    Color(red: 0.11, green: 0.055, blue: 0.085)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                terminalHeader
                terminalOutput
                terminalInput
            }
        }
        .onAppear {
            recentCommands = ServerTerminalHistoryStore.load(for: device.id)
            connect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                inputFocused = true
            }
        }
        .onDisappear {
            closeTerminal()
        }
        .edgeSwipeBack {
            closeTerminal()
            dismiss()
        }
    }

    private var terminalHeader: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionState.tint)
                        .frame(width: 7, height: 7)
                    Text(connectionState.title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.68))
                }
            }

            Spacer()

            Menu {
                Button("重连", systemImage: "arrow.clockwise") {
                    connect()
                }
                Button("复制全部输出", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = transcript
                    copiedOutput = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        copiedOutput = false
                    }
                }
                Button("清屏", systemImage: "eraser") {
                    transcript = ""
                }
                Button("发送 Ctrl+C", systemImage: "keyboard.badge.ellipsis") {
                    sendInterrupt()
                }
                Button("断开连接", systemImage: "power", role: .destructive) {
                    disconnect()
                }
            } label: {
                Image(systemName: copiedOutput ? "checkmark" : "ellipsis")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: Circle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 66)
        .padding(.bottom, 14)
        .background(.black.opacity(0.22))
    }

    private var terminalOutput: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                Text(transcript.isEmpty ? " " : transcript)
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.88))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .id("terminal-transcript")

                Color.clear
                    .frame(height: 1)
                    .id("terminal-bottom")
            }
            .background(.black.opacity(0.38))
            .onChange(of: transcript) { _, _ in
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo("terminal-bottom", anchor: .bottom)
                }
            }
        }
    }

    private var terminalInput: some View {
        VStack(spacing: 8) {
            if !recentCommands.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recentCommands, id: \.self) { command in
                            Button {
                                commandInput = command
                                inputFocused = true
                            } label: {
                                Text(command)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.86))
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                    .background(.white.opacity(0.11), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            HStack(spacing: 10) {
                Text("$")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.serveraAccent)

                TextField("输入命令", text: $commandInput)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .focused($inputFocused)
                    .onSubmit(sendCommand)

                Button {
                    sendCommand()
                } label: {
                    Image(systemName: "return")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(canSendCommand ? Color.serveraAccentDeep : .white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSendCommand)
            }
            .padding(12)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.11), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .padding(.top, 10)
        .background(.black.opacity(0.30))
    }

    private var canSendCommand: Bool {
        connectionState == .connected && !commandInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func connect() {
        // 先关闭旧 shell。交互会话带状态，重新连接应从干净的远端 shell 开始。
        closeTerminal()
        connectionState = .connecting
        appendLine("[Servera] 正在连接 \(device.name)...")

        connectTask = Task { @MainActor in
            do {
                let request = try makeRequest()
                let shell = try await SSHConnectionService.shared.openInteractiveShell(request: request)
                guard !Task.isCancelled else { return }
                shellSession = shell
                connectionState = .connected
                appendLine("[Servera] 已连接。")
                startStreaming(shell)
                inputFocused = true
            } catch {
                guard !Task.isCancelled else { return }
                connectionState = .failed(error.localizedDescription)
                appendLine("[Servera] 连接失败：\(error.localizedDescription)")
            }
        }
    }

    private func startStreaming(_ shell: SSHInteractiveShellSession) {
        // 输出流放在可取消任务中，UI 断开连接时不用等待远端命令结束。
        streamTask?.cancel()
        streamTask = Task { @MainActor in
            do {
                try await shell.streamEvents { event in
                    await MainActor.run {
                        switch event {
                        case let .standardOutput(text):
                            append(text)
                        case let .standardError(text):
                            append(text)
                        case let .exitStatus(status):
                            appendLine("[Servera] shell 退出码 \(status)")
                        case let .exitSignal(signal):
                            appendLine("[Servera] shell 收到信号 \(signal)")
                        case .closed:
                            if connectionState == .connected {
                                connectionState = .closed
                            }
                        }
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                connectionState = .failed(error.localizedDescription)
                appendLine("[Servera] 会话已断开：\(error.localizedDescription)")
            }
        }
    }

    private func sendCommand() {
        let command = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSendCommand, let shellSession else { return }
        commandInput = ""
        // 历史记录只保存命令文本，不保存终端输出。
        recentCommands = ServerTerminalHistoryStore.insert(command, for: device.id, into: recentCommands)

        Task {
            do {
                try await shellSession.write(command + "\n")
            } catch {
                await MainActor.run {
                    connectionState = .failed(error.localizedDescription)
                    appendLine("[Servera] 发送失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func sendInterrupt() {
        guard let shellSession else { return }
        Task {
            do {
                try await shellSession.interrupt()
                await MainActor.run {
                    appendLine("^C")
                }
            } catch {
                await MainActor.run {
                    appendLine("[Servera] Ctrl+C 发送失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func disconnect() {
        connectionState = .closed
        closeTerminal()
        appendLine("[Servera] 已断开连接。")
    }

    private func closeTerminal() {
        connectTask?.cancel()
        streamTask?.cancel()
        connectTask = nil
        streamTask = nil

        if let shellSession {
            Task {
                await shellSession.close()
            }
        }
        shellSession = nil
    }

    private func makeRequest() throws -> SSHConnectionRequest {
        let id = device.id
        let descriptor = FetchDescriptor<ManagedDeviceRecord>(
            predicate: #Predicate { $0.deviceID == id }
        )
        guard let record = try modelContext.fetch(descriptor).first else {
            throw ServeraSSHError.connectionFailed("未找到本地设备记录。")
        }
        guard let credentialIdentifier = record.credentialIdentifier,
              let credential = try KeychainService.loadCredentialBundle(id: credentialIdentifier) else {
            record.connectionStatus = .needsVerification
            record.credentialNeedsVerification = true
            try modelContext.save()
            throw ServeraSSHError.connectionFailed("凭据不存在，请编辑连接后重新验证。")
        }
        return SSHConnectionRequest(
            host: record.host,
            port: record.port,
            username: record.account,
            authenticationKind: record.authenticationKind,
            credential: credential,
            acceptUnknownHostKey: false
        )
    }

    private func appendLine(_ line: String) {
        append(line + "\n")
    }

    private func append(_ text: String) {
        transcript += text
        if transcript.count > 80_000 {
            transcript = String(transcript.suffix(60_000))
        }
    }
}

enum TerminalConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case closed
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            "等待连接"
        case .connecting:
            "Connecting..."
        case .connected:
            "Connected"
        case .closed:
            "Disconnected"
        case .failed:
            "Failed"
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            .serveraTextSecondary
        case .connecting:
            .serveraAmber
        case .connected:
            .serveraLeaf
        case .closed:
            .serveraTextSecondary
        case .failed:
            .serveraAccent
        }
    }
}

enum ServerTerminalHistoryStore {
    // 每台设备独立的轻量历史记录。命令可能包含敏感路径或运维细节，所以必须保持短列表。
    static func load(for deviceID: UUID) -> [String] {
        UserDefaults.standard.stringArray(forKey: key(for: deviceID)) ?? []
    }

    static func insert(_ command: String, for deviceID: UUID, into current: [String]) -> [String] {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return current }
        var items = current.filter { $0 != trimmed }
        items.insert(trimmed, at: 0)
        items = Array(items.prefix(10))
        UserDefaults.standard.set(items, forKey: key(for: deviceID))
        return items
    }

    private static func key(for deviceID: UUID) -> String {
        "Servera.ServerTerminalHistory.\(deviceID.uuidString)"
    }
}
