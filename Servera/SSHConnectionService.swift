import Foundation
import Traversio

// MARK: - SSH 传输与服务器采集
// 这里封装 Traversio，用于 Host Key 校验、命令执行、交互式终端和指标采集。
// 默认使用直连网络，避免 macOS 的 SOCKS/HTTP 代理误伤 SSH 流量。

enum ServerAuthenticationKind: String, Codable, CaseIterable, Identifiable {
    case password
    case privateKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .password: "密码"
        case .privateKey: "私钥"
        }
    }
}

struct DeviceCredentialBundle: Codable, Equatable {
    var password: String?
    var privateKeyPEM: String?
    var privateKeyPassphrase: String?
}

enum SSHNetworkMode: String, Codable, Sendable {
    case direct
    case systemProxy
}

struct SSHConnectionRequest: Sendable {
    var host: String
    var port: Int
    var username: String
    var authenticationKind: ServerAuthenticationKind
    var credential: DeviceCredentialBundle
    var acceptUnknownHostKey: Bool = false
    var acceptChangedHostKey: Bool = false
    var networkMode: SSHNetworkMode = .direct
}

struct SSHConnectionOutcome: Sendable {
    var latencyMilliseconds: Int?
    var hostKeyAlgorithm: String
    var hostKeyFingerprintSHA256: String
    var status: ServerStatusSnapshot
    var diagnostics: SSHCollectionDiagnostics
    var rawStatusOutput: String
}

struct SSHCommandExecutionResult: Equatable, Sendable {
    var command: String
    var standardOutput: String
    var standardError: String
    var exitStatus: Int?
    var durationMilliseconds: Int
    var executedAt: Date

    var succeeded: Bool {
        exitStatus == 0
    }
}

enum SSHCommandStreamEvent: Sendable {
    case standardOutput(String)
    case standardError(String)
    case exitStatus(Int)
}

enum SSHShellStreamEvent: Sendable {
    case standardOutput(String)
    case standardError(String)
    case exitStatus(Int)
    case exitSignal(String)
    case closed
}

final class SSHInteractiveShellSession: @unchecked Sendable {
    private let session: SSHSession

    init(session: SSHSession) {
        self.session = session
    }

    func write(_ text: String) async throws {
        try await session.write(text)
    }

    func interrupt() async throws {
        try await session.sendSignal(.interrupt)
    }

    func close() async {
        try? await session.close()
    }

    func streamEvents(onEvent: @escaping @Sendable (SSHShellStreamEvent) async -> Void) async throws {
        for try await event in session.events {
            switch event {
            case let .standardOutput(bytes):
                await onEvent(.standardOutput(String(decoding: bytes, as: UTF8.self)))
            case let .standardError(bytes):
                await onEvent(.standardError(String(decoding: bytes, as: UTF8.self)))
            case let .exitStatus(status):
                await onEvent(.exitStatus(Int(status)))
            case let .exitSignal(signal):
                await onEvent(.exitSignal(signal.signal.rawValue))
            case .endOfFile:
                await onEvent(.closed)
            }
        }
        await onEvent(.closed)
    }
}

enum SSHCollectionScriptKind: String, Codable, Hashable, Sendable {
    case full
    case live
}

struct SSHCollectionDiagnostics: Codable, Equatable, Sendable {
    var scriptKind: SSHCollectionScriptKind
    var commandDurationMilliseconds: Int
    var cpuAvailable: Bool
    var memoryAvailable: Bool
    var diskAvailable: Bool
    var networkAvailable: Bool
    var processAvailable: Bool
    var dockerAvailable: Bool

    static func make(scriptKind: SSHCollectionScriptKind, duration: Int, status: ServerStatusSnapshot) -> SSHCollectionDiagnostics {
        SSHCollectionDiagnostics(
            scriptKind: scriptKind,
            commandDurationMilliseconds: duration,
            cpuAvailable: status.cpuAvailable,
            memoryAvailable: status.memoryAvailable,
            diskAvailable: status.diskAvailable,
            networkAvailable: status.networkAvailable,
            processAvailable: status.processAvailable,
            dockerAvailable: status.dockerAvailable
        )
    }
}

actor SSHConnectionService {
    static let shared = SSHConnectionService()

    private let hostKeyStore = ServeraHostKeyStore()
    private var liveConnections: [String: SSHConnection] = [:]
    private var activeCollectionKeys: Set<String> = []

    func validateAndCollect(
        request: SSHConnectionRequest,
        stage: @escaping @Sendable (String) async -> Void = { _ in }
    ) async throws -> SSHConnectionOutcome {
        await stage("准备认证材料")
        let configuration = try makeConfiguration(for: request, connectionTimeout: 12, responseTimeout: 10)
        let key = liveConnectionKey(for: request)
        try await waitForCollectionSlot(key)
        defer { activeCollectionKeys.remove(key) }

        do {
            await stage("验证 Host Key")
            let startedAt = Date()
            let connection = try await connect(configuration: configuration, networkMode: request.networkMode)
            defer {
                Task { await connection.close() }
            }

            let latency = Int(Date().timeIntervalSince(startedAt) * 1000)
            await stage("采集系统状态")
            // 状态脚本会从 stdin 读取可选 sudo 密码。
            // 这样不在 docker 组但可 sudo 的用户也能走 Docker 兜底，
            // 同时密码不会出现在 shell 命令字符串或调试输出里。
            let result = try await executeCommand(
                Self.statusCommand,
                using: connection,
                standardInput: collectionStandardInput(for: request),
                onEvent: { _ in }
            )
            let commandDuration = result.durationMilliseconds
            let output = result.standardOutput
            var snapshot = ServerStatusParser.parse(output, collectedAt: .now)
            if snapshot.systemVersion == "Unknown", !connection.metadata.remoteIdentification.isEmpty {
                snapshot.systemVersion = connection.metadata.remoteIdentification
            }
            let diagnostics = SSHCollectionDiagnostics.make(scriptKind: .full, duration: commandDuration, status: snapshot)

            return SSHConnectionOutcome(
                latencyMilliseconds: latency,
                hostKeyAlgorithm: connection.metadata.hostKeyAlgorithm,
                hostKeyFingerprintSHA256: connection.metadata.hostKeyFingerprintSHA256,
                status: snapshot,
                diagnostics: diagnostics,
                rawStatusOutput: Self.debugRawOutput(output)
            )
        } catch {
            throw mapError(error)
        }
    }

    func collectLiveMetrics(request: SSHConnectionRequest) async throws -> SSHConnectionOutcome {
        let configuration = try makeConfiguration(for: request, connectionTimeout: 8, responseTimeout: 5)
        let key = liveConnectionKey(for: request)
        try await waitForCollectionSlot(key)
        defer { activeCollectionKeys.remove(key) }

        do {
            let connection = try await liveConnection(for: key, configuration: configuration, networkMode: request.networkMode)
            return try await collectLiveMetrics(using: connection, request: request)
        } catch {
            if let staleConnection = liveConnections.removeValue(forKey: key) {
                await staleConnection.close()
            }

            do {
                let connection = try await liveConnection(for: key, configuration: configuration, networkMode: request.networkMode)
                return try await collectLiveMetrics(using: connection, request: request)
            } catch {
                throw mapError(error)
            }
        }
    }

    func executeCommand(request: SSHConnectionRequest, command: String) async throws -> SSHCommandExecutionResult {
        try await executeCommandStreaming(request: request, command: command, onEvent: { _ in })
    }

    func executeCommand(
        request: SSHConnectionRequest,
        command: String,
        standardInput: String
    ) async throws -> SSHCommandExecutionResult {
        try await executeCommandStreaming(
            request: request,
            command: command,
            standardInput: standardInput,
            onEvent: { _ in }
        )
    }

    func executeCommandStreaming(
        request: SSHConnectionRequest,
        command: String,
        standardInput: String? = nil,
        onEvent: @escaping @Sendable (SSHCommandStreamEvent) async -> Void
    ) async throws -> SSHCommandExecutionResult {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            throw ServeraSSHError.commandFailed("命令不能为空。")
        }

        let configuration = try makeConfiguration(for: request, connectionTimeout: 10, responseTimeout: 24)
        let key = liveConnectionKey(for: request)
        try await waitForCollectionSlot(key)
        defer { activeCollectionKeys.remove(key) }

        do {
            let connection = try await liveConnection(for: key, configuration: configuration, networkMode: request.networkMode)
            return try await executeCommand(trimmedCommand, using: connection, standardInput: standardInput, onEvent: onEvent)
        } catch {
            if let staleConnection = liveConnections.removeValue(forKey: key) {
                await staleConnection.close()
            }

            do {
                let connection = try await liveConnection(for: key, configuration: configuration, networkMode: request.networkMode)
                return try await executeCommand(trimmedCommand, using: connection, standardInput: standardInput, onEvent: onEvent)
            } catch {
                throw mapError(error)
            }
        }
    }

    func openInteractiveShell(request: SSHConnectionRequest) async throws -> SSHInteractiveShellSession {
        let configuration = try makeConfiguration(for: request, connectionTimeout: 10, responseTimeout: 60)
        let key = liveConnectionKey(for: request)
        try await waitForCollectionSlot(key)
        defer { activeCollectionKeys.remove(key) }

        do {
            let connection = try await liveConnection(for: key, configuration: configuration, networkMode: request.networkMode)
            let shell = try await connection.openShell()
            return SSHInteractiveShellSession(session: shell)
        } catch {
            if let staleConnection = liveConnections.removeValue(forKey: key) {
                await staleConnection.close()
            }

            do {
                let connection = try await liveConnection(for: key, configuration: configuration, networkMode: request.networkMode)
                let shell = try await connection.openShell()
                return SSHInteractiveShellSession(session: shell)
            } catch {
                throw mapError(error)
            }
        }
    }

    /// 打开一个 SFTP 通道，复用已建立的 SSH 连接。
    /// SFTPService 通过这个方法获取底层 SFTPClient，所有文件操作都在其上执行。
    func openSFTPChannel(for request: SSHConnectionRequest) async throws -> SFTPClient {
        let configuration = try makeConfiguration(for: request, connectionTimeout: 12, responseTimeout: 30)
        let key = liveConnectionKey(for: request)
        try await waitForCollectionSlot(key)
        defer { activeCollectionKeys.remove(key) }

        do {
            let connection = try await liveConnection(for: key, configuration: configuration, networkMode: request.networkMode)
            return try await connection.openSFTP()
        } catch {
            if let staleConnection = liveConnections.removeValue(forKey: key) {
                await staleConnection.close()
            }

            do {
                let connection = try await liveConnection(for: key, configuration: configuration, networkMode: request.networkMode)
                return try await connection.openSFTP()
            } catch {
                throw mapError(error)
            }
        }
    }

    private func executeCommand(
        _ command: String,
        using connection: SSHConnection,
        standardInput: String? = nil,
        onEvent: @escaping @Sendable (SSHCommandStreamEvent) async -> Void
    ) async throws -> SSHCommandExecutionResult {
        let startedAt = Date()
        let session = try await connection.openExec(command)
        var standardOutput = ""
        var standardError = ""
        var exitStatus: Int?

        if let standardInput {
            try await session.write(standardInput)
            try await session.sendEOF()
        }

        for try await event in session.events {
            switch event {
            case let .standardOutput(bytes):
                let text = String(decoding: bytes, as: UTF8.self)
                standardOutput += text
                await onEvent(.standardOutput(text))
            case let .standardError(bytes):
                let text = String(decoding: bytes, as: UTF8.self)
                standardError += text
                await onEvent(.standardError(text))
            case let .exitStatus(status):
                let intStatus = Int(status)
                exitStatus = intStatus
                await onEvent(.exitStatus(intStatus))
            case .exitSignal, .endOfFile:
                break
            }
        }

        let duration = Int(Date().timeIntervalSince(startedAt) * 1000)

        return SSHCommandExecutionResult(
            command: command,
            standardOutput: standardOutput,
            standardError: standardError,
            exitStatus: exitStatus,
            durationMilliseconds: duration,
            executedAt: startedAt
        )
    }

    private func collectLiveMetrics(using connection: SSHConnection, request: SSHConnectionRequest) async throws -> SSHConnectionOutcome {
        // 实时刷新尽量复用已打开的 SSH 连接。脚本比首次校验短，
        // 但保留同样的 Docker sudo 兜底，避免详情页刷新能力退化。
        let result = try await executeCommand(
            Self.liveStatusCommand,
            using: connection,
            standardInput: collectionStandardInput(for: request),
            onEvent: { _ in }
        )
        let commandDuration = result.durationMilliseconds
        let output = result.standardOutput
        let snapshot = ServerStatusParser.parse(output, collectedAt: .now)
        let latency = await connection.latency.map { Int($0.roundTripTimeMilliseconds.rounded()) }
        let diagnostics = SSHCollectionDiagnostics.make(scriptKind: .live, duration: commandDuration, status: snapshot)

        return SSHConnectionOutcome(
            latencyMilliseconds: latency,
            hostKeyAlgorithm: connection.metadata.hostKeyAlgorithm,
            hostKeyFingerprintSHA256: connection.metadata.hostKeyFingerprintSHA256,
            status: snapshot,
            diagnostics: diagnostics,
            rawStatusOutput: Self.debugRawOutput(output)
        )
    }

    private static func debugRawOutput(_ output: String) -> String {
        #if DEBUG
        output
        #else
        ""
        #endif
    }

    private func collectionStandardInput(for request: SSHConnectionRequest) -> String {
        guard request.authenticationKind == .password,
              let password = request.credential.password,
              !password.isEmpty else {
            return ""
        }
        // 末尾一个换行用于满足远端脚本里的 read -r SERVERA_SUDO_PASSWORD。
        // 不要添加标记，也不要在远端 echo 密码。
        return "\(password)\n"
    }

    private func liveConnection(
        for key: String,
        configuration: SSHClientConfiguration,
        networkMode: SSHNetworkMode
    ) async throws -> SSHConnection {
        // 详情刷新和类终端操作不应该每次都重新握手。
        // 连接失效时由调用方移除，再按需重试。
        if let connection = liveConnections[key] {
            return connection
        }

        let connection = try await connect(configuration: configuration, networkMode: networkMode)
        liveConnections[key] = connection
        return connection
    }

    private func connect(configuration: SSHClientConfiguration, networkMode: SSHNetworkMode) async throws -> SSHConnection {
        switch networkMode {
        case .direct:
        // 旧传输层避开 macOS Network.framework 的代理行为，
        // 防止 SSH 被路由到本地 HTTP/SOCKS 代理。
            return try await SSHClient.connect(
                configuration: configuration,
                transportBackendPreference: .legacy
            )
        case .systemProxy:
            return try await SSHClient.connect(configuration: configuration)
        }
    }

    private func waitForCollectionSlot(_ key: String) async throws {
        // 同一端点串行采集。两个状态脚本同时跑会让 CPU/网络差值采样不准，
        // 也会浪费 SSH 会话。
        while activeCollectionKeys.contains(key) {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(120))
        }
        activeCollectionKeys.insert(key)
    }

    private func makeConfiguration(
        for request: SSHConnectionRequest,
        connectionTimeout: TimeInterval,
        responseTimeout: TimeInterval
    ) throws -> SSHClientConfiguration {
        guard let port = UInt16(exactly: request.port) else {
            throw ServeraSSHError.invalidPort
        }

        let authentication = try makeAuthentication(for: request)
        return SSHClientConfiguration(
            host: request.host,
            port: port,
            username: request.username,
            authentication: authentication,
            hostKeyPolicy: makeHostKeyPolicy(
                acceptUnknownHostKey: request.acceptUnknownHostKey,
                acceptChangedHostKey: request.acceptChangedHostKey
            ),
            timeoutPolicy: SSHTimeoutPolicy(
                connectionSetupTimeInterval: connectionTimeout,
                responseTimeInterval: responseTimeout
            )
        )
    }

    private func liveConnectionKey(for request: SSHConnectionRequest) -> String {
        "\(request.networkMode.rawValue)|\(request.authenticationKind.rawValue)|\(request.username)@\(request.host):\(request.port)"
    }

    private func makeAuthentication(for request: SSHConnectionRequest) throws -> SSHAuthenticationMethod {
        switch request.authenticationKind {
        case .password:
            guard let password = request.credential.password, !password.isEmpty else {
                throw ServeraSSHError.missingPassword
            }
            return .password(password)
        case .privateKey:
            guard let privateKey = request.credential.privateKeyPEM, !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ServeraSSHError.missingPrivateKey
            }
            return try .openSSHPrivateKey(privateKey, passphrase: request.credential.privateKeyPassphrase?.nilIfBlank)
        }
    }

    private func makeHostKeyPolicy(acceptUnknownHostKey: Bool, acceptChangedHostKey: Bool) -> SSHHostKeyPolicy {
        let store = hostKeyStore
        return .callback { validation in
        // 未知或变化的 Host Key 绝不静默信任。
        // UI 流程只有在用户确认指纹后才会传入接受标记。
            if let storedHostKey = try await store.lookupHostKey(
                endpointHost: validation.endpointHost,
                endpointPort: validation.endpointPort
            ) {
                if validation.matches(storedHostKey) {
                    return .callback
                }

                guard acceptChangedHostKey else {
                    throw ServeraSSHError.hostKeyChanged(
                        algorithm: validation.trustedHostKey.algorithmName,
                        fingerprintSHA256: validation.trustedHostKey.fingerprintSHA256
                    )
                }

                try await store.storeHostKey(
                    SSHHostKeyStoreRequest(
                        endpointHost: validation.endpointHost,
                        endpointPort: validation.endpointPort,
                        remoteIdentification: validation.remoteIdentification,
                        expectedStoredHostKey: storedHostKey,
                        trustedHostKey: validation.trustedHostKey
                    )
                )
                return .callback
            }

            guard acceptUnknownHostKey else {
                throw ServeraSSHError.unknownHostKey(
                    algorithm: validation.trustedHostKey.algorithmName,
                    fingerprintSHA256: validation.trustedHostKey.fingerprintSHA256
                )
            }

            try await store.storeHostKey(
                SSHHostKeyStoreRequest(
                    endpointHost: validation.endpointHost,
                    endpointPort: validation.endpointPort,
                    remoteIdentification: validation.remoteIdentification,
                    expectedStoredHostKey: nil,
                    trustedHostKey: validation.trustedHostKey
                )
            )
            return .callback
        }
    }

    private func mapError(_ error: any Error) -> ServeraSSHError {
        if let mapped = error as? ServeraSSHError { return mapped }

        if let clientError = error as? SSHClientError {
                // Traversio 会把回调失败包装进连接诊断里。
                // 这里保留 Servera 的 Host Key 错误，让添加/编辑页显示专门的信任确认，
                // 而不是泛化成普通连接失败。
            switch clientError {
            case .authenticationRejected:
                return .authenticationFailed
            case .passwordChangeRequired:
                return .passwordChangeRequired
            case .connectionFailed(let failure):
                if let callback = failure.diagnostics.callbackFailure {
                    if callback.diagnosticCode == "servera-unknown-host-key" {
                        let parts = (callback.diagnosticSummary ?? "").split(separator: "|", maxSplits: 1).map(String.init)
                        return .unknownHostKey(
                            algorithm: parts.first ?? "unknown",
                            fingerprintSHA256: parts.count > 1 ? parts[1] : (callback.diagnosticSummary ?? "")
                        )
                    }
                    if callback.diagnosticCode == "servera-host-key-changed" {
                        let parts = (callback.diagnosticSummary ?? "").split(separator: "|", maxSplits: 1).map(String.init)
                        return .hostKeyChanged(
                            algorithm: parts.first ?? "unknown",
                            fingerprintSHA256: parts.count > 1 ? parts[1] : (callback.diagnosticSummary ?? "")
                        )
                    }
                }
                if failure.stage == .hostKeyTrust || failure.code == .hostKeyTrustFailed {
                    return .hostKeyChanged(algorithm: "unknown", fingerprintSHA256: "")
                }
                if failure.stage == .transport || failure.stage == .identification {
                    return .unreachable(failure.message)
                }
                if failure.stage == .authentication {
                    return .authenticationFailed
                }
                return .connectionFailed(failure.message)
            case .operationFailed(let failure):
                return .commandFailed(failure.message)
            case .connectionScopeEnded:
                return .connectionFailed("SSH 连接已关闭。")
            }
        }

        if error is CancellationError {
            return .connectionFailed("连接已取消。")
        }

        return .connectionFailed(error.localizedDescription)
    }

private static let liveStatusCommand = #"""
sh -lc '
SERVERA_SUDO_PASSWORD=
IFS= read -r SERVERA_SUDO_PASSWORD || true

echo __SERVERA_CPU__
cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 0)
case "$cores" in
  '"'"''"'"'|*[!0-9]*) cores=0 ;;
esac
if [ "$cores" -le 0 ] && [ -r /proc/stat ]; then
  cores=$(grep -c "^cpu[0-9]" /proc/stat 2>/dev/null || echo 0)
fi
echo CORES=$cores

cpu_a=$(mktemp 2>/dev/null || echo /tmp/servera_live_cpu_a_$$)
cpu_b=$(mktemp 2>/dev/null || echo /tmp/servera_live_cpu_b_$$)
net_a=$(mktemp 2>/dev/null || echo /tmp/servera_live_net_a_$$)
net_b=$(mktemp 2>/dev/null || echo /tmp/servera_live_net_b_$$)
cat /proc/stat 2>/dev/null > "$cpu_a" || true
cat /proc/net/dev 2>/dev/null > "$net_a" || true
sleep 1
cat /proc/stat 2>/dev/null > "$cpu_b" || true
cat /proc/net/dev 2>/dev/null > "$net_b" || true
[ -s "$cpu_a" ] && [ -s "$cpu_b" ] || echo "ERROR=CPU 采样不可用"

awk '"'"'
NR==FNR && $1 ~ /^cpu/ {
  key=$1
  total=0
  for (i=2; i<=NF; i++) total += $i
  t[key]=total
  idle[key]=$5+$6
  user[key]=$2
  nice[key]=$3
  sys[key]=$4
  iow[key]=$6
  next
}
NR!=FNR && $1 ~ /^cpu/ {
  key=$1
  total=0
  for (i=2; i<=NF; i++) total += $i
  dt=total-t[key]
  didle=($5+$6)-idle[key]
  if (dt <= 0) pct_value=0; else pct_value=(dt-didle)*100/dt
  if (pct_value < 0) pct_value=0
  if (pct_value > 100) pct_value=100
  pct=int(pct_value+0.5)
  if (key=="cpu") {
    printf("PERCENT=%d\n", pct)
    printf("PERCENT_DECIMAL=%.1f\n", pct_value)
    if (dt <= 0) {
      print "USER=0"
      print "USER_DECIMAL=0.0"
      print "NICE=0"
      print "NICE_DECIMAL=0.0"
      print "SYSTEM=0"
      print "SYSTEM_DECIMAL=0.0"
      print "IOWAIT=0"
      print "IOWAIT_DECIMAL=0.0"
    } else {
      user_value=($2-user[key])*100/dt
      nice_value=($3-nice[key])*100/dt
      system_value=($4-sys[key])*100/dt
      iowait_value=($6-iow[key])*100/dt
      if (user_value < 0) user_value=0
      if (nice_value < 0) nice_value=0
      if (system_value < 0) system_value=0
      if (iowait_value < 0) iowait_value=0
      printf("USER=%d\n", int(user_value+0.5))
      printf("USER_DECIMAL=%.1f\n", user_value)
      printf("NICE=%d\n", int(nice_value+0.5))
      printf("NICE_DECIMAL=%.1f\n", nice_value)
      printf("SYSTEM=%d\n", int(system_value+0.5))
      printf("SYSTEM_DECIMAL=%.1f\n", system_value)
      printf("IOWAIT=%d\n", int(iowait_value+0.5))
      printf("IOWAIT_DECIMAL=%.1f\n", iowait_value)
    }
  } else {
    sub(/^cpu/, "", key)
    printf("CORE%s=%d\n", key, pct)
    printf("CORE%s_DECIMAL=%.1f\n", key, pct_value)
  }
}
'"'"' "$cpu_a" "$cpu_b" 2>/dev/null || true

echo __SERVERA_MEM__
if [ -r /proc/meminfo ]; then
  grep -E "^(MemTotal|MemAvailable|MemFree|Cached|Buffers|SReclaimable|SwapTotal|SwapFree):" /proc/meminfo 2>/dev/null || echo "ERROR=内存字段不可读"
else
  echo "ERROR=内存信息不可用"
fi

echo __SERVERA_LOAD__
cat /proc/loadavg 2>/dev/null || sysctl -n vm.loadavg 2>/dev/null | awk '"'"'{print $2, $3, $4}'"'"' || true

echo __SERVERA_UPTIME__
cat /proc/uptime 2>/dev/null || sysctl -n kern.boottime 2>/dev/null | awk -F"[ ,}]" '"'"'{for (i=1;i<=NF;i++) if ($i=="sec") {print systime()-$(i+2); exit}}'"'"' || true

echo __SERVERA_NET__
iface=$(ip route show default 2>/dev/null | awk '"'"'{
  for (i=1; i<=NF; i++) {
    if ($i=="dev" && (i+1)<=NF) { print $(i+1); exit }
  }
}'"'"' | head -n 1)
[ -z "$iface" ] && iface=$(awk -F: '"'"'NR>2 {gsub(/^[ \t]+|[ \t]+$/, "", $1); if ($1 != "lo") {print $1; exit}}'"'"' "$net_b" 2>/dev/null)
[ -z "$iface" ] && iface=$(awk -F: '"'"'NR>2 {gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1; exit}'"'"' "$net_b" 2>/dev/null)
if [ -z "$iface" ] || [ ! -s "$net_a" ] || [ ! -s "$net_b" ]; then
  echo "ERROR=默认网卡流量不可读"
fi
awk -v target="$iface" -F: '"'"'
function trim(value) { gsub(/^[ \t]+|[ \t]+$/, "", value); return value }
NR==FNR {
  iface=trim($1)
  if (NR>2 && iface==target) {
    split($2, first, /[ \t]+/)
    rx1=first[2]
    tx1=first[10]
  }
  next
}
FNR>2 {
  iface=trim($1)
  if (iface != target) next
  split($2, second, /[ \t]+/)
  rx2=second[2]
  tx2=second[10]
  rx_rate=rx2-rx1
  tx_rate=tx2-tx1
  if (rx_rate < 0) rx_rate=0
  if (tx_rate < 0) tx_rate=0
  printf("IFACE=%s\n", target)
  printf("RX_RATE=%d\n", rx_rate)
  printf("TX_RATE=%d\n", tx_rate)
  printf("RX_TOTAL=%d\n", rx2)
  printf("TX_TOTAL=%d\n", tx2)
}
'"'"' "$net_a" "$net_b" 2>/dev/null || true
if command -v ip >/dev/null 2>&1 && [ -n "$iface" ]; then
  ip -o -4 addr show dev "$iface" scope global 2>/dev/null | awk "{print \"IP=\"\$4; exit}"
fi

echo __SERVERA_DOCKER__
if command -v docker >/dev/null 2>&1; then
  echo INSTALLED=1
  docker_cmd=docker
  if ! docker ps -a --format "{{.ID}}" >/dev/null 2>&1; then
    if [ -n "$SERVERA_SUDO_PASSWORD" ] && command -v sudo >/dev/null 2>&1 && printf "%s\n" "$SERVERA_SUDO_PASSWORD" | sudo -S -p "" docker ps -a --format "{{.ID}}" >/dev/null 2>&1; then
      docker_cmd=sudo_docker
    else
      echo "ERROR=Docker 权限不足或 sudo 不可用"
    fi
  fi
  docker_run() {
    if [ "$docker_cmd" = "sudo_docker" ]; then
      printf "%s\n" "$SERVERA_SUDO_PASSWORD" | sudo -S -p "" docker "$@"
    else
      docker "$@"
    fi
  }
  echo TOTAL=$(docker_run ps -a --format "{{.ID}}" 2>/dev/null | wc -l | tr -d " ")
  echo RUNNING=$(docker_run ps --format "{{.ID}}" 2>/dev/null | wc -l | tr -d " ")
  docker_ps=$(mktemp 2>/dev/null || echo /tmp/servera_live_docker_ps_$$)
  docker_stats=$(mktemp 2>/dev/null || echo /tmp/servera_live_docker_stats_$$)
  docker_run ps -a --format "{{.ID}}|{{.Names}}|{{.Image}}|{{.State}}|{{.Status}}" 2>/dev/null > "$docker_ps" || true
  if [ ! -s "$docker_ps" ]; then
    docker_run ps -a --format "{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}" 2>/dev/null | awk -F"|" '"'"'
    {
      state=$4
      if ($4 ~ /^Up/) state="running"
      else if ($4 ~ /^Exited/) state="exited"
      printf("%s|%s|%s|%s|%s\n", $1, $2, $3, state, $4)
    }
    '"'"' > "$docker_ps" || true
  fi
  if [ ! -s "$docker_ps" ]; then
    docker_run ps -a --format "{{.ID}}" 2>/dev/null | while IFS= read -r id; do
      [ -n "$id" ] || continue
      info=$(docker_run inspect -f "{{.Name}}|{{.Config.Image}}|{{.State.Status}}" "$id" 2>/dev/null | head -n 1)
      name=${info%%|*}
      rest=${info#*|}
      image=${rest%%|*}
      state=${rest#*|}
      [ "$state" != "$rest" ] || state=""
      name=${name#/}
      status=$state
      [ "$state" = "running" ] && status="Up"
      printf "%s|%s|%s|%s|%s\n" "$id" "${name:-$id}" "$image" "$state" "$status"
    done > "$docker_ps" || true
  fi
  docker_run stats --no-stream --format "{{.ID}}|{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}" 2>/dev/null > "$docker_stats" || true
  awk -F"|" '"'"'
  FILENAME == ARGV[1] {
    cpu[$1]=$2
    split($3, mem, " / ")
    mem_used[$1]=mem[1]
    mem_limit[$1]=mem[2]
    mem_percent[$1]=$4
    next
  }
  {
    if (++count > 20) exit
    id=$1
    name=$2
    image=$3
    state=$4
    status=$5
    uptime=status
    gsub(/\t/, " ", name)
    gsub(/\t/, " ", image)
    gsub(/\t/, " ", state)
    gsub(/\t/, " ", status)
    printf("CONTAINER\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", id, name, image, state, status, cpu[id], mem_used[id], mem_limit[id], mem_percent[id], uptime)
  }
  '"'"' "$docker_stats" "$docker_ps" 2>/dev/null || true
  rm -f "$docker_ps" "$docker_stats"
else
  echo INSTALLED=0
  echo TOTAL=0
  echo RUNNING=0
fi

rm -f "$cpu_a" "$cpu_b" "$net_a" "$net_b"
'
"""#

    private static let statusCommand = #"""
sh -lc '
SERVERA_SUDO_PASSWORD=
IFS= read -r SERVERA_SUDO_PASSWORD || true

echo __SERVERA_OS__
uname -srm | sed "s/^/KERNEL=/"
if [ -f /etc/os-release ]; then grep -E "^(NAME|PRETTY_NAME)=" /etc/os-release; fi

echo __SERVERA_CPU__
cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 0)
case "$cores" in
  '"'"''"'"'|*[!0-9]*) cores=0 ;;
esac
if [ "$cores" -le 0 ]; then
  cores=$(grep -c "^cpu[0-9]" /proc/stat 2>/dev/null || echo 0)
fi
echo CORES=$cores
cpu_a=$(mktemp 2>/dev/null || echo /tmp/servera_cpu_a_$$)
cpu_b=$(mktemp 2>/dev/null || echo /tmp/servera_cpu_b_$$)
cat /proc/stat 2>/dev/null > "$cpu_a" || true
sleep 1
cat /proc/stat 2>/dev/null > "$cpu_b" || true
[ -s "$cpu_a" ] && [ -s "$cpu_b" ] || echo "ERROR=CPU 采样不可用"
awk '"'"'
NR==FNR && $1 ~ /^cpu/ {
  key=$1
  total=0
  for (i=2; i<=NF; i++) total += $i
  t[key]=total
  idle[key]=$5+$6
  user[key]=$2
  nice[key]=$3
  sys[key]=$4
  iow[key]=$6
  next
}
NR!=FNR && $1 ~ /^cpu/ {
  key=$1
  total=0
  for (i=2; i<=NF; i++) total += $i
  dt=total-t[key]
  didle=($5+$6)-idle[key]
  if (dt <= 0) pct_value=0; else pct_value=(dt-didle)*100/dt
  if (pct_value < 0) pct_value=0
  if (pct_value > 100) pct_value=100
  pct=int(pct_value+0.5)
  if (key=="cpu") {
    printf("PERCENT=%d\n", pct)
    printf("PERCENT_DECIMAL=%.1f\n", pct_value)
    if (dt <= 0) {
      print "USER=0"
      print "USER_DECIMAL=0.0"
      print "NICE=0"
      print "NICE_DECIMAL=0.0"
      print "SYSTEM=0"
      print "SYSTEM_DECIMAL=0.0"
      print "IOWAIT=0"
      print "IOWAIT_DECIMAL=0.0"
    } else {
      user_value=($2-user[key])*100/dt
      nice_value=($3-nice[key])*100/dt
      system_value=($4-sys[key])*100/dt
      iowait_value=($6-iow[key])*100/dt
      if (user_value < 0) user_value=0
      if (nice_value < 0) nice_value=0
      if (system_value < 0) system_value=0
      if (iowait_value < 0) iowait_value=0
      printf("USER=%d\n", int(user_value+0.5))
      printf("USER_DECIMAL=%.1f\n", user_value)
      printf("NICE=%d\n", int(nice_value+0.5))
      printf("NICE_DECIMAL=%.1f\n", nice_value)
      printf("SYSTEM=%d\n", int(system_value+0.5))
      printf("SYSTEM_DECIMAL=%.1f\n", system_value)
      printf("IOWAIT=%d\n", int(iowait_value+0.5))
      printf("IOWAIT_DECIMAL=%.1f\n", iowait_value)
    }
  } else {
    sub(/^cpu/, "", key)
    printf("CORE%s=%d\n", key, pct)
    printf("CORE%s_DECIMAL=%.1f\n", key, pct_value)
  }
}
'"'"' "$cpu_a" "$cpu_b" 2>/dev/null || true
rm -f "$cpu_a" "$cpu_b"

echo __SERVERA_TEMP__
temp=""
for zone in /sys/class/thermal/thermal_zone*/temp; do
  [ -r "$zone" ] || continue
  raw=$(cat "$zone" 2>/dev/null)
  case "$raw" in
    '"'"''"'"'|*[!0-9]*) continue ;;
  esac
  if [ "$raw" -gt 1000 ]; then temp=$((raw/1000)); else temp=$raw; fi
  if [ "$temp" -gt 0 ] && [ "$temp" -lt 130 ]; then break; fi
done
if [ -z "$temp" ] && command -v sensors >/dev/null 2>&1; then
  temp=$(sensors 2>/dev/null | awk '"'"'/Core [0-9]+|Package id|Tctl|CPU/ { if (match($0, /\+[0-9]+(\.[0-9]+)?/)) { print substr($0, RSTART+1, RLENGTH-1); exit } }'"'"')
fi
[ -n "$temp" ] && echo TEMP_C=$temp

echo __SERVERA_MEM__
if [ -r /proc/meminfo ]; then
  grep -E "^(MemTotal|MemAvailable|MemFree|Cached|Buffers|SReclaimable|SwapTotal|SwapFree):" /proc/meminfo 2>/dev/null || echo "ERROR=内存字段不可读"
else
  echo "ERROR=内存信息不可用"
fi

echo __SERVERA_LOAD__
cat /proc/loadavg 2>/dev/null || sysctl -n vm.loadavg 2>/dev/null | awk '"'"'{print $2, $3, $4}'"'"' || true

echo __SERVERA_DF__
df_out=$(mktemp 2>/dev/null || echo /tmp/servera_df_$$)
if df -P -T -B1 / > "$df_out" 2>/dev/null; then
  head -n 2 "$df_out"
elif df -P -B1 / > "$df_out" 2>/dev/null; then
  head -n 2 "$df_out"
elif df -Pk / > "$df_out" 2>/dev/null; then
  awk '"'"'NR==1 {print "Filesystem 1B-blocks Used Available Use% Mounted"} NR==2 {printf "%s %d %d %d %s %s\n", $1, $2*1024, $3*1024, $4*1024, $5, $6}'"'"' "$df_out"
else
  echo "ERROR=根分区容量不可读"
fi
rm -f "$df_out"

echo __SERVERA_UPTIME__
cat /proc/uptime 2>/dev/null || sysctl -n kern.boottime 2>/dev/null | awk -F"[ ,}]" '"'"'{for (i=1;i<=NF;i++) if ($i=="sec") {print systime()-$(i+2); exit}}'"'"' || true

echo __SERVERA_NET__
net_a=$(mktemp 2>/dev/null || echo /tmp/servera_net_a_$$)
net_b=$(mktemp 2>/dev/null || echo /tmp/servera_net_b_$$)
cat /proc/net/dev 2>/dev/null > "$net_a" || true
sleep 1
cat /proc/net/dev 2>/dev/null > "$net_b" || true
iface=$(ip route show default 2>/dev/null | awk '"'"'{
  for (i=1; i<=NF; i++) {
    if ($i=="dev" && (i+1)<=NF) { print $(i+1); exit }
  }
}'"'"' | head -n 1)
[ -z "$iface" ] && iface=$(awk -F: '"'"'NR>2 {gsub(/^[ \t]+|[ \t]+$/, "", $1); if ($1 != "lo") {print $1; exit}}'"'"' "$net_b" 2>/dev/null)
[ -z "$iface" ] && iface=$(awk -F: '"'"'NR>2 {gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1; exit}'"'"' "$net_b" 2>/dev/null)
if [ -z "$iface" ] || [ ! -s "$net_a" ] || [ ! -s "$net_b" ]; then
  echo "ERROR=默认网卡流量不可读"
fi
awk -v target="$iface" -F: '"'"'
function trim(value) { gsub(/^[ \t]+|[ \t]+$/, "", value); return value }
NR==FNR {
  iface=trim($1)
  if (NR>2 && iface==target) {
    split($2, first, /[ \t]+/)
    rx1=first[2]
    tx1=first[10]
  }
  next
}
FNR>2 {
  iface=trim($1)
  if (iface != target) next
  split($2, second, /[ \t]+/)
  rx2=second[2]
  tx2=second[10]
  rx_rate=rx2-rx1
  tx_rate=tx2-tx1
  if (rx_rate < 0) rx_rate=0
  if (tx_rate < 0) tx_rate=0
  printf("IFACE=%s\n", target)
  printf("RX_RATE=%d\n", rx_rate)
  printf("TX_RATE=%d\n", tx_rate)
  printf("RX_TOTAL=%d\n", rx2)
  printf("TX_TOTAL=%d\n", tx2)
}
'"'"' "$net_a" "$net_b" 2>/dev/null || true
if command -v ip >/dev/null 2>&1 && [ -n "$iface" ]; then
  ip -o -4 addr show dev "$iface" scope global 2>/dev/null | awk "{print \"IP=\"\$4; exit}"
fi
rm -f "$net_a" "$net_b"

echo __SERVERA_PROC__
echo "PID COMMAND USER CPU RSS"
proc_a=$(mktemp 2>/dev/null || echo /tmp/servera_proc_a_$$)
proc_b=$(mktemp 2>/dev/null || echo /tmp/servera_proc_b_$$)
proc_out=$(mktemp 2>/dev/null || echo /tmp/servera_proc_out_$$)
hz=$(getconf CLK_TCK 2>/dev/null || echo 100)
case "$hz" in
  '"'"''"'"'|*[!0-9]*) hz=100 ;;
esac
proc_cores=$cores
if [ -z "$proc_cores" ] || [ "$proc_cores" -le 0 ]; then
  proc_cores=$(grep -c "^cpu[0-9]" /proc/stat 2>/dev/null || echo 1)
fi
[ "$proc_cores" -le 0 ] && proc_cores=1
sample_proc() {
  awk '"'"'
  {
    closeIndex = match($0, /\) /)
    if (closeIndex <= 0) next
    pid = $1
    rest = substr($0, closeIndex + 2)
    split(rest, fields, " ")
    ticks = fields[12] + fields[13]
    print pid, ticks
  }
  '"'"' /proc/[0-9]*/stat 2>/dev/null
}
sample_proc > "$proc_a" || true
sleep 1
sample_proc > "$proc_b" || true
awk -v hz="$hz" -v cores="$proc_cores" '"'"'
NR==FNR {
  ticks[$1]=$2
  next
}
{
  if (!($1 in ticks)) next
  dt=$2-ticks[$1]
  if (dt <= 0) next
  cpu=(dt*100)/(hz*cores)
  printf("%s %.1f\n", $1, cpu)
}
'"'"' "$proc_a" "$proc_b" 2>/dev/null | sort -k2,2nr | head -n 5 > "$proc_out" || true
if [ -s "$proc_out" ]; then
while read -r pid cpu; do
  meta=$(ps -p "$pid" -o comm= -o user= -o rss= 2>/dev/null | awk '"'"'
  NF >= 3 {
    rss=$NF
    user=$(NF-1)
    comm=$1
    for (i=2; i<=NF-2; i++) comm=comm" "$i
    print comm "|" user "|" rss
    exit
  }'"'"')
  [ -n "$meta" ] || continue
  command_name=${meta%%|*}
  rest=${meta#*|}
  process_user=${rest%%|*}
  rss=${rest#*|}
  printf "%s %s %s %.1f %s\n" "$pid" "$command_name" "$process_user" "$cpu" "$rss"
done < "$proc_out"
elif [ -d /proc/1 ]; then
  ps -eo pid=,comm=,user=,pcpu=,rss= --sort=-pcpu 2>/dev/null | head -n 5 | awk '"'"'{printf "%s %s %s %.1f %s\n", $1, $2, $3, $4, $5}'"'"'
else
  ps -axo pid=,comm=,user=,pcpu=,rss= 2>/dev/null | sort -k4,4nr | head -n 5 | awk '"'"'{printf "%s %s %s %.1f %s\n", $1, $2, $3, $4, $5}'"'"'
fi
rm -f "$proc_a" "$proc_b" "$proc_out"

echo __SERVERA_DOCKER__
if command -v docker >/dev/null 2>&1; then
  echo INSTALLED=1
  docker_cmd=docker
  if ! docker ps -a --format "{{.ID}}" >/dev/null 2>&1; then
    if [ -n "$SERVERA_SUDO_PASSWORD" ] && command -v sudo >/dev/null 2>&1 && printf "%s\n" "$SERVERA_SUDO_PASSWORD" | sudo -S -p "" docker ps -a --format "{{.ID}}" >/dev/null 2>&1; then
      docker_cmd=sudo_docker
    else
      echo "ERROR=Docker 权限不足或 sudo 不可用"
    fi
  fi
  docker_run() {
    if [ "$docker_cmd" = "sudo_docker" ]; then
      printf "%s\n" "$SERVERA_SUDO_PASSWORD" | sudo -S -p "" docker "$@"
    else
      docker "$@"
    fi
  }
  echo TOTAL=$(docker_run ps -a --format "{{.ID}}" 2>/dev/null | wc -l | tr -d " ")
  echo RUNNING=$(docker_run ps --format "{{.ID}}" 2>/dev/null | wc -l | tr -d " ")
  docker_ps=$(mktemp 2>/dev/null || echo /tmp/servera_docker_ps_$$)
  docker_stats=$(mktemp 2>/dev/null || echo /tmp/servera_docker_stats_$$)
  docker_run ps -a --format "{{.ID}}|{{.Names}}|{{.Image}}|{{.State}}|{{.Status}}" 2>/dev/null > "$docker_ps" || true
  if [ ! -s "$docker_ps" ]; then
    docker_run ps -a --format "{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}" 2>/dev/null | awk -F"|" '"'"'
    {
      state=$4
      if ($4 ~ /^Up/) state="running"
      else if ($4 ~ /^Exited/) state="exited"
      printf("%s|%s|%s|%s|%s\n", $1, $2, $3, state, $4)
    }
    '"'"' > "$docker_ps" || true
  fi
  if [ ! -s "$docker_ps" ]; then
    docker_run ps -a --format "{{.ID}}" 2>/dev/null | while IFS= read -r id; do
      [ -n "$id" ] || continue
      info=$(docker_run inspect -f "{{.Name}}|{{.Config.Image}}|{{.State.Status}}" "$id" 2>/dev/null | head -n 1)
      name=${info%%|*}
      rest=${info#*|}
      image=${rest%%|*}
      state=${rest#*|}
      [ "$state" != "$rest" ] || state=""
      name=${name#/}
      status=$state
      [ "$state" = "running" ] && status="Up"
      printf "%s|%s|%s|%s|%s\n" "$id" "${name:-$id}" "$image" "$state" "$status"
    done > "$docker_ps" || true
  fi
  docker_run stats --no-stream --format "{{.ID}}|{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}" 2>/dev/null > "$docker_stats" || true
  awk -F"|" '"'"'
  FILENAME == ARGV[1] {
    cpu[$1]=$2
    split($3, mem, " / ")
    mem_used[$1]=mem[1]
    mem_limit[$1]=mem[2]
    mem_percent[$1]=$4
    next
  }
  {
    if (++count > 20) exit
    id=$1
    name=$2
    image=$3
    state=$4
    status=$5
    uptime=status
    gsub(/\t/, " ", name)
    gsub(/\t/, " ", image)
    gsub(/\t/, " ", state)
    gsub(/\t/, " ", status)
    printf("CONTAINER\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", id, name, image, state, status, cpu[id], mem_used[id], mem_limit[id], mem_percent[id], uptime)
  }
  '"'"' "$docker_stats" "$docker_ps" 2>/dev/null || true
  rm -f "$docker_ps" "$docker_stats"
else
  echo INSTALLED=0
  echo TOTAL=0
  echo RUNNING=0
fi
'
"""#
}

actor ServeraHostKeyStore: SSHHostKeyTrustStore {
    private let defaults = UserDefaults.standard
    private let prefix = "Servera.HostKey."

    func lookupHostKey(endpointHost: String, endpointPort: UInt16) async throws -> SSHTrustedHostKey? {
    // 这里使用 UserDefaults 足够，因为保存的是公开 Host Key 材料，不是凭据。
        guard let value = defaults.string(forKey: storageKey(host: endpointHost, port: endpointPort)),
              let data = Data(base64Encoded: value) else {
            return nil
        }
        return try SSHTrustedHostKey(rawRepresentation: Array(data))
    }

    func storeHostKey(_ request: SSHHostKeyStoreRequest) async throws {
        defaults.set(
            Data(request.trustedHostKey.rawRepresentation).base64EncodedString(),
            forKey: storageKey(host: request.endpointHost, port: request.endpointPort)
        )
    }

    func decisionForChangedHostKey(_ request: SSHHostKeyChangeRequest) async throws -> SSHHostKeyChangeDecision {
        .reject
    }

    private func storageKey(host: String, port: UInt16) -> String {
        "\(prefix)\(host):\(port)"
    }
}

enum ServeraSSHError: LocalizedError, SSHCallbackFailureDiagnosticProviding, Sendable {
    case invalidPort
    case missingPassword
    case missingPrivateKey
    case unknownHostKey(algorithm: String, fingerprintSHA256: String)
    case authenticationFailed
    case passwordChangeRequired
    case hostKeyChanged(algorithm: String, fingerprintSHA256: String)
    case unreachable(String)
    case commandFailed(String)
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            "端口需要是 1 到 65535 之间的数字。"
        case .missingPassword:
            "请输入 SSH 密码。"
        case .missingPrivateKey:
            "请粘贴 OpenSSH 私钥内容。"
        case .unknownHostKey(let algorithm, let fingerprint):
            "首次连接到这台服务器，需要确认 Host Key。\n算法：\(algorithm)\nSHA256：\(fingerprint)"
        case .authenticationFailed:
            "账号、密码或私钥认证失败，请检查凭据。"
        case .passwordChangeRequired:
            "服务器要求先修改 SSH 密码，App 暂时无法继续登录。"
        case .hostKeyChanged:
            "服务器 Host Key 与本机已信任记录不一致，已阻止连接。请确认服务器是否重装或存在中间人风险。"
        case .unreachable(let message):
            "无法连接到服务器或端口未开放：\(message)"
        case .commandFailed(let message):
            "SSH 已连接，但状态采集命令执行失败：\(message)"
        case .connectionFailed(let message):
            "SSH 连接失败：\(message)"
        }
    }

    var sshCallbackFailureDiagnosticCode: String {
        switch self {
        case .unknownHostKey:
            "servera-unknown-host-key"
        case .hostKeyChanged:
            "servera-host-key-changed"
        default:
            "servera-ssh-error"
        }
    }

    var sshCallbackFailureDiagnosticSummary: String? {
        switch self {
        case .unknownHostKey(let algorithm, let fingerprint),
             .hostKeyChanged(let algorithm, let fingerprint):
            "\(algorithm)|\(fingerprint)"
        default:
            errorDescription
        }
    }

    var isCancellation: Bool {
        if case .connectionFailed(let message) = self {
            return message.contains("取消") || message.localizedCaseInsensitiveContains("cancel")
        }
        return false
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
