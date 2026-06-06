import Foundation

// MARK: - 群晖控制面板 API
// DSM 控制面板模块的读写门面。很多接口没有稳定公开契约，
// 所以写入方法保持保守，并在保存后重新读取对应模块。

struct SynologyControlPanelConnection: Sendable {
    var deviceID: UUID? = nil
    var host: String
    var port: Int
    var scheme: NASConnectionProtocol
    var account: String
    var password: String
    var verifySSLCertificate: Bool
}

struct SynologyExternalAccessSnapshot: Equatable, Sendable {
    var ddnsRecords: [SynologyDDNSRecord]
    var quickConnect: SynologyQuickConnectSettings
    var dsmExternalHostname: String
    var collectedAt: Date
}

// DDNS 编辑模型。密码对 DSM 来说只写不可读，所以读取时留空；
// UI 会说明未修改记录不需要重新输入密码/令牌。
struct SynologyDDNSRecord: Identifiable, Equatable, Sendable {
    var id: String
    var hostname: String
    var provider: String
    var username: String
    var ip: String
    var ipv6: String
    var status: String
    var net: String
    var interfaceV4: String
    var interfaceV6: String
    var enabled: Bool
    var heartbeat: Bool = false
    var password: String = ""
}

// QuickConnect 在更多 DSM 版本上可读但不可写。
// 保存错误单独映射，必要时明确提示用户去 DSM 控制台修改。
struct SynologyQuickConnectSettings: Equatable, Sendable {
    var enabled: Bool
    var serverID: String
    var domain: String
    var account: String
    var region: String
}

// 网络页详情模型，包含 DSM 系统代理设置。
// 代理写入必须读回校验，因为 DSM 可能接受请求但忽略字段。
struct SynologyNetworkSettingsSnapshot: Equatable, Sendable {
    var hostname: String
    var primaryIP: String
    var gateway: String
    var dnsServers: [String]
    var interfaces: [String]
    var proxyEnabled: Bool
    var proxyHost: String
    var proxyPort: String
    var proxyBypassLocal: Bool
    var collectedAt: Date
}

// 终端机模块刻意收窄：只处理 SSH、Telnet 和 SSH 端口。
struct SynologyTerminalSettingsSnapshot: Equatable, Sendable {
    var sshEnabled: Bool
    var telnetEnabled: Bool
    var sshPort: Int
    var collectedAt: Date
}

// 用户/群组完整读取模型。部分字段在精简 UI 中不再展示，
// 但 DSM 会返回它们，后续页面可能复用。
struct SynologyUsersGroupsSnapshot: Equatable, Sendable {
    var users: [SynologyNASUser]
    var groups: [SynologyNASGroup]
    var sharedFolders: [SynologySharedFolderPermission]
    var quotas: [SynologyUserQuota]
    var home: SynologyUserHomeSettings
    var passwordPolicy: SynologyPasswordPolicySettings
    var collectedAt: Date
}

// DSM 账号行。name 是登录账号，不是显示名称。
struct SynologyNASUser: Identifiable, Equatable, Sendable {
    var id: String { name }
    var name: String
    var uid: Int?
    var fullName: String
    var email: String
    var description: String
    var isEditable: Bool?
    var isEnabled: Bool?
    var otpEnabled: Bool?
    var otpEnforced: Bool?
    var disallowPasswordChange: Bool?
    var passwordLastChangeDay: Int?
    var groupNames: [String]
}

// DSM 群组行；如果 API 暴露成员列表，也一并保存成员名。
struct SynologyNASGroup: Identifiable, Equatable, Sendable {
    var id: String { name }
    var name: String
    var gid: Int?
    var description: String
    var memberNames: [String]
}

// 共享文件夹权限归一化。DSM 使用 rw、ro、deny 等短字符串，
// UI 使用类型化枚举。
enum SynologySharePermissionLevel: String, CaseIterable, Codable, Equatable, Sendable, Identifiable {
    case readWrite
    case readOnly
    case noAccess
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readWrite: "读写"
        case .readOnly: "只读"
        case .noAccess: "无权限"
        case .unknown: "未读取"
        }
    }

    init(dsmRawValue: String) {
        let normalized = dsmRawValue.lowercased()
        if ["rw", "readwrite", "read_write", "write", "writable", "1"].contains(normalized) {
            self = .readWrite
        } else if ["ro", "readonly", "read_only", "read", "readable"].contains(normalized) {
            self = .readOnly
        } else if ["deny", "none", "no", "no_access", "0"].contains(normalized) {
            self = .noAccess
        } else {
            self = .unknown
        }
    }

    var dsmValue: String {
        switch self {
        case .readWrite: "rw"
        case .readOnly: "ro"
        case .noAccess: "deny"
        case .unknown: ""
        }
    }
}

struct SynologySharedFolderPermission: Identifiable, Equatable, Sendable {
    var id: String { name }
    var name: String
    var path: String
    var volume: String
    var permission: SynologySharePermissionLevel
}

struct SynologyUserQuota: Identifiable, Equatable, Sendable {
    var id: String { volume }
    var volume: String
    var usedBytes: Int64?
    var limitBytes: Int64?
    var enabled: Bool?
}

struct SynologyUserHomeSettings: Equatable, Sendable {
    var enabled: Bool?
    var location: String
    var recycleBinEnabled: Bool?
    var encryption: Int?
}

struct SynologyPasswordPolicySettings: Equatable, Sendable {
    var minLengthEnabled: Bool? = nil
    var minLength: Int? = nil
    var mixedCase: Bool? = nil
    var numeric: Bool? = nil
    var specialCharacter: Bool? = nil
    var excludeUsername: Bool? = nil
    var excludeCommonPassword: Bool? = nil
    var passwordMustChange: Bool? = nil
    var resetByEmailEnabled: Bool? = nil
}

/// DSM 控制面板门面。
///
/// 控制面板 API 比 File Station 更不稳定：部分模块在某些 DSM 构建上只读，
/// 部分必须 POST，部分会返回 success 但实际不改设置。
/// 因此公开写方法都会在写入后重新读取，并保留模块专属错误文案。
final class SynologyControlPanelService: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let connection: SynologyControlPanelConnection
    private var session: URLSession!
    private var apiInfo: [String: APIInfo] = [:]
    private var sid: String?

    init(connection: SynologyControlPanelConnection) {
        self.connection = connection
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 14
        configuration.timeoutIntervalForResource = 28
        super.init()
        if connection.verifySSLCertificate {
            session = URLSession(configuration: configuration)
        } else {
            session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        }
    }

    func collectSnapshot() async throws -> NASControlPanelSnapshot {
        try await connect()
        defer { Task { await close() } }
        let collectedAt = Date()
        let modules = await NASControlPanelModule.visibleCases.asyncMap { module in
            await collect(module: module, collectedAt: collectedAt)
        }
        return NASControlPanelSnapshot(collectedAt: collectedAt, modules: modules)
    }

    func fetchExternalAccessDetails() async throws -> SynologyExternalAccessSnapshot {
        try await connect()
        defer { Task { await close() } }
        return try await fetchExternalAccessDetailsWithoutReconnect()
    }

    func fetchNetworkDetails() async throws -> SynologyNetworkSettingsSnapshot {
        try await connect()
        defer { Task { await close() } }
        return try await fetchNetworkDetailsWithoutReconnect()
    }

    func fetchUsersGroupsDetails() async throws -> SynologyUsersGroupsSnapshot {
        try await connect()
        defer { Task { await close() } }
        return try await fetchUsersGroupsDetailsWithoutReconnect()
    }

    func fetchUserManagementDetails(for username: String) async throws -> SynologyUsersGroupsSnapshot {
        try await connect()
        defer { Task { await close() } }
        return try await fetchUsersGroupsDetailsWithoutReconnect(selectedUser: username)
    }

    func renameUserAccount(oldName: String, newName: String) async throws -> SynologyUsersGroupsSnapshot {
        try await connect()
        defer { Task { await close() } }

        // 改名是高风险操作，因为它可能改变 Servera 登录 DSM 使用的账号。
        // 只有读回新用户名后才视为成功。
        let trimmedOldName = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOldName.isEmpty, !trimmedNewName.isEmpty else {
            throw SynologyClientError.apiUnavailable("用户名称不能为空。")
        }
        guard trimmedOldName != trimmedNewName else {
            return try await fetchUsersGroupsDetailsWithoutReconnect(selectedUser: trimmedOldName)
        }

        _ = try await callAPI(
            apiNames: ["SYNO.Core.User"],
            method: "set",
            extraParameters: [
                "name": trimmedOldName,
                "new_name": trimmedNewName
            ],
            errorContext: .userManagement
        )
        let updated = try await fetchUsersGroupsDetailsWithoutReconnect(selectedUser: trimmedNewName)
        guard updated.users.contains(where: { $0.name == trimmedNewName }) else {
            throw SynologyClientError.apiUnavailable("DSM 已返回成功，但没有读取到新账号名，请刷新后确认。")
        }
        return updated
    }

    func changeUserPassword(username: String, password: String) async throws -> SynologyUsersGroupsSnapshot {
        try await connect()
        defer { Task { await close() } }
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else {
            throw SynologyClientError.apiUnavailable("用户名称不能为空。")
        }
        guard !password.isEmpty else {
            return try await fetchUsersGroupsDetailsWithoutReconnect(selectedUser: trimmedUsername)
        }
        // 只有用户输入非空密码时才发送；空字段表示“不修改密码”。
        _ = try await callAPI(
            apiNames: ["SYNO.Core.User"],
            method: "set",
            extraParameters: [
                "name": trimmedUsername,
                "password": password
            ],
            errorContext: .userManagement
        )
        return try await fetchUsersGroupsDetailsWithoutReconnect(selectedUser: trimmedUsername)
    }

    func saveUserGroups(username: String, groupNames: [String]) async throws -> SynologyUsersGroupsSnapshot {
        try await connect()
        defer { Task { await close() } }
        // DSM 期望逗号分隔的群组列表。至少选择一个群组由 UI 校验保证。
        _ = try await callAPI(
            apiNames: ["SYNO.Core.User"],
            method: "set",
            extraParameters: [
                "name": username,
                "groups": groupNames.joined(separator: ",")
            ],
            errorContext: .userManagement
        )
        return try await fetchUsersGroupsDetailsWithoutReconnect(selectedUser: username)
    }

    func saveUserSharePermissions(username: String, permissions: [SynologySharedFolderPermission]) async throws -> SynologyUsersGroupsSnapshot {
        try await connect()
        defer { Task { await close() } }
        for permission in permissions where permission.permission != .unknown {
            _ = try await callAPI(
                apiNames: ["SYNO.Core.Share.Permission", "SYNO.Core.Share"],
                method: "set",
                extraParameters: [
                    "name": permission.name,
                    "user": username,
                    "permission": permission.permission.dsmValue
                ],
                errorContext: .userManagement
            )
        }
        return try await fetchUsersGroupsDetailsWithoutReconnect(selectedUser: username)
    }

    func saveUserQuotas(username: String, quotas: [SynologyUserQuota]) async throws -> SynologyUsersGroupsSnapshot {
        try await connect()
        defer { Task { await close() } }
        for quota in quotas {
            _ = try await callAPI(
                apiNames: ["SYNO.Core.Quota", "SYNO.Core.User.Quota"],
                method: "set",
                extraParameters: [
                    "user": username,
                    "volume": quota.volume,
                    "quota": quota.limitBytes.map(String.init) ?? "0"
                ],
                errorContext: .userManagement
            )
        }
        return try await fetchUsersGroupsDetailsWithoutReconnect(selectedUser: username)
    }

    func saveDSMExternalHostname(_ hostname: String) async throws -> SynologyExternalAccessSnapshot {
        try await connect()
        defer { Task { await close() } }
        _ = try await callAPI(
            apiNames: ["SYNO.Core.Web.DSM.External"],
            method: "set",
            extraParameters: ["hostname": hostname]
        )
        return try await fetchExternalAccessDetailsWithoutReconnect()
    }

    func saveQuickConnect(_ settings: SynologyQuickConnectSettings) async throws -> SynologyExternalAccessSnapshot {
        try await connect()
        defer { Task { await close() } }
        // QuickConnect 经常允许读取，却用泛化参数错误拒绝写入。
        // 这里保持尽力写入，并让 quickConnect 上下文把错误映射为“请在 DSM 修改”，
        // 而不是误报“API 缺失”。
        _ = try await callAPI(
            apiNames: ["SYNO.Core.QuickConnect"],
            method: "set",
            extraParameters: [
                "enabled": settings.enabled ? "true" : "false",
                "server_id": settings.serverID,
                "server_alias": settings.serverID
            ],
            errorContext: .quickConnect
        )
        return try await fetchExternalAccessDetailsWithoutReconnect()
    }

    func saveDDNSRecord(_ record: SynologyDDNSRecord) async throws -> SynologyExternalAccessSnapshot {
        try await connect()
        defer { Task { await close() } }
        var parameters: [String: Any] = [
            "id": record.id,
            "provider": record.provider,
            "hostname": record.hostname,
            "username": record.username,
            "enable": record.enabled,
            "net": record.net.isEmpty ? "MANUAL_V4" : record.net,
            "ip": normalizedDDNSIPv4(record.ip),
            "ipv6": normalizedDDNSIPv6(record.ipv6),
            "interface_v4": record.interfaceV4.isEmpty ? "default" : record.interfaceV4,
            "interface_v6": record.interfaceV6.isEmpty ? "default" : record.interfaceV6,
            "heartbeat": record.heartbeat
        ]
        if !record.password.isEmpty {
            parameters["passwd"] = record.password
        } else if record.provider == "Synology" {
            parameters["passwd"] = "Synology"
        }
        try await callCompoundAPI([
            [
                "api": "SYNO.Core.DDNS.Record",
                "version": 1,
                "method": "set",
                "params": parameters
            ],
            [
                "api": "SYNO.Core.DDNS.Record",
                "version": 1,
                "method": "update_ip_address",
                "params": ["id": record.provider]
            ]
        ])
        return try await fetchExternalAccessDetailsWithoutReconnect()
    }

    func saveNetworkSettings(hostname: String, dnsServers: [String]) async throws -> SynologyNetworkSettingsSnapshot {
        try await connect()
        defer { Task { await close() } }
        let trimmedHostname = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDNS = normalizedDNSServers(dnsServers)
        guard !trimmedHostname.isEmpty else {
            throw SynologyClientError.apiUnavailable("主机名不能为空。")
        }
        var parameters: [String: String] = [
            "hostname": trimmedHostname,
            "server_name": trimmedHostname
        ]
        if !normalizedDNS.isEmpty {
        // DSM 网络 API 曾使用多种 DNS key。这里一起发送一组小兼容字段，
        // 让新旧构建各自读取能理解的字段。
            parameters["dns"] = normalizedDNS.joined(separator: ",")
            parameters["dns_server"] = normalizedDNS.joined(separator: ",")
            parameters["primary_dns"] = normalizedDNS.first ?? ""
            parameters["secondary_dns"] = normalizedDNS.dropFirst().first ?? ""
            parameters["dns_primary"] = normalizedDNS.first ?? ""
            parameters["dns_secondary"] = normalizedDNS.dropFirst().first ?? ""
            parameters["dns_manual"] = "true"
        }
        _ = try await callAPI(
            apiNames: ["SYNO.Core.Network", "SYNO.Core.Network.General"],
            method: "set",
            extraParameters: parameters,
            errorContext: .networkSettings
        )
        return try await fetchNetworkDetailsWithoutReconnect()
    }

    func saveProxySettings(enabled: Bool, host: String, port: String, bypassLocal: Bool) async throws -> SynologyNetworkSettingsSnapshot {
        try await connect()
        defer { Task { await close() } }
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        if enabled {
            guard !trimmedHost.isEmpty else { throw SynologyClientError.apiUnavailable("代理服务器地址不能为空。") }
            guard let portNumber = Int(trimmedPort), (1...65535).contains(portNumber) else {
                throw SynologyClientError.apiUnavailable("代理服务器端口必须是 1-65535。")
            }
        }
        return try await saveProxySettingsWithFallback(
            enabled: enabled,
            host: trimmedHost,
            port: trimmedPort,
            bypassLocal: bypassLocal
        )
    }

    func fetchTerminalSettings() async throws -> SynologyTerminalSettingsSnapshot {
        try await connect()
        defer { Task { await close() } }
        return try await fetchTerminalSettingsWithoutReconnect()
    }

    func saveTerminalSettings(sshEnabled: Bool, telnetEnabled: Bool, sshPort: Int) async throws -> SynologyTerminalSettingsSnapshot {
        try await connect()
        defer { Task { await close() } }
        guard (1...65_535).contains(sshPort) else {
            throw SynologyClientError.apiUnavailable("SSH 端口必须是 1-65535。")
        }
        let parameters: [String: String] = [
            "enable_ssh": sshEnabled ? "true" : "false",
            "enable_telnet": telnetEnabled ? "true" : "false",
            "ssh_port": "\(sshPort)"
        ]
        // 终端机设置刻意收窄：Servera 只编辑 SSH/Telnet/SSH 端口，
        // SNMP 和加密细节交给 DSM 控制台。
        _ = try await callAPI(
            apiNames: ["SYNO.Core.Terminal", "SYNO.Core.Terminal.SSH"],
            method: "set",
            extraParameters: parameters,
            errorContext: .terminalSettings,
            preferredVersion: 3,
            httpMethod: "POST"
        )
        return try await fetchTerminalSettingsWithoutReconnect()
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}

private extension SynologyControlPanelService {
    struct APIInfo: Sendable {
        var path: String
        var minVersion: Int
        var maxVersion: Int
        var requestFormat: String
    }

    func connect() async throws {
        apiInfo = try await fetchAPIInfo()
        sid = try await login()
    }

    func close() async {
        guard let sid, let auth = apiInfo["SYNO.API.Auth"] else { return }
        _ = try? await requestJSON(
            path: auth.path,
            parameters: [
                "api": "SYNO.API.Auth",
                "version": "\(min(max(auth.maxVersion, auth.minVersion), 7))",
                "method": "logout",
                "session": "ServeraControlPanel",
                "_sid": sid
            ],
            requiresSuccess: false
        )
        self.sid = nil
    }

    func fetchAPIInfo() async throws -> [String: APIInfo] {
        do {
            return try await fetchAPIInfo(path: "/webapi/query.cgi")
        } catch {
            if error.isSynologyCancellation { throw error }
            return try await fetchAPIInfo(path: "/webapi/entry.cgi")
        }
    }

    func fetchAPIInfo(path: String) async throws -> [String: APIInfo] {
        let json = try await requestJSON(
            path: path,
            parameters: [
                "api": "SYNO.API.Info",
                "version": "1",
                "method": "query",
                "query": "all"
            ],
            requiresSuccess: true
        )
        guard let data = json["data"] as? [String: Any] else {
            throw SynologyClientError.apiUnavailable("DSM API 探测失败。")
        }
        var result: [String: APIInfo] = [:]
        for (name, value) in data {
            guard let dictionary = value as? [String: Any] else { continue }
            result[name] = APIInfo(
                path: normalizedAPIPath(stringValue(dictionary["path"])),
                minVersion: intValue(dictionary["minVersion"]) ?? 1,
                maxVersion: intValue(dictionary["maxVersion"]) ?? 1,
                requestFormat: stringValue(dictionary["requestFormat"]).uppercased()
            )
        }
        return result
    }

    func login() async throws -> String {
        guard let auth = apiInfo["SYNO.API.Auth"] else {
            throw SynologyClientError.apiUnavailable("DSM 登录接口不可用。")
        }
        let json = try await requestJSON(
            path: auth.path,
            parameters: [
                "api": "SYNO.API.Auth",
                "version": "\(min(max(auth.maxVersion, auth.minVersion), 7))",
                "method": "login",
                "account": connection.account,
                "passwd": connection.password,
                "session": "ServeraControlPanel",
                "format": "sid"
            ],
            requiresSuccess: true,
            errorContext: .auth
        )
        guard let data = json["data"] as? [String: Any],
              let sid = data["sid"] as? String,
              !sid.isEmpty else {
            throw SynologyClientError.authenticationFailed("DSM 登录成功但没有返回控制面板会话。")
        }
        return sid
    }

    func collect(module: NASControlPanelModule, collectedAt: Date) async -> NASControlPanelModuleSnapshot {
        do {
            let rows = try await fetchRows(for: module)
            return NASControlPanelModuleSnapshot(
                module: module,
                collectedAt: collectedAt,
                available: true,
                summary: summary(for: module, rows: rows),
                statusText: "可读取",
                errorMessage: "",
                rows: rows
            )
        } catch {
            let message = normalizedModuleError(error)
            return NASControlPanelModuleSnapshot(
                module: module,
                collectedAt: collectedAt,
                available: false,
                summary: message,
                statusText: "不可用",
                errorMessage: message,
                rows: []
            )
        }
    }

    func fetchRows(for module: NASControlPanelModule) async throws -> [NASControlPanelRow] {
        switch module {
        case .users:
            return try await fetchUsersAndGroups()
        case .externalAccess:
            return try await fetchExternalAccess()
        case .network:
            return try await fetchNetwork()
        case .terminalSNMP:
            return try await fetchTerminalSNMP()
        case .infoCenter:
            return try await fetchInfoCenter()
        case .updateRestore:
            return try await fetchUpdateRestore()
        }
    }

    func fetchUsersAndGroups() async throws -> [NASControlPanelRow] {
        let details = try await fetchUsersGroupsDetailsWithoutReconnect()
        let adminGroup = details.groups.first { $0.name == "administrators" }
        let passwordText = details.passwordPolicy.minLengthEnabled == true
            ? "至少 \(details.passwordPolicy.minLength ?? 0) 位"
            : "未强制长度"
        return [
            NASControlPanelRow(title: "用户", value: "\(details.users.count) 个"),
            NASControlPanelRow(title: "群组", value: "\(details.groups.count) 个"),
            NASControlPanelRow(title: "管理员", value: adminGroup.map { "\($0.memberNames.count) 个成员" } ?? "需要 DSM 权限"),
            NASControlPanelRow(title: "家目录", value: details.home.enabled == true ? (details.home.location.isEmpty ? "已开启" : details.home.location) : "未开启"),
            NASControlPanelRow(title: "密码策略", value: passwordText)
        ]
    }

    func fetchUsersGroupsDetailsWithoutReconnect(selectedUser: String? = nil) async throws -> SynologyUsersGroupsSnapshot {
        guard let userJSON = try await optionalJSON(apiNames: ["SYNO.Core.User"], method: "list", extraParameters: [:]) else {
            throw SynologyClientError.apiUnavailable("当前 DSM 账号没有读取用户列表的权限。")
        }
        let groupJSON = try await optionalJSON(apiNames: ["SYNO.Core.Group"], method: "list", extraParameters: [:]) ?? [:]
        var users = parseNASUsers(from: userJSON)
        var groups = parseNASGroups(from: groupJSON)

        for index in users.indices {
            users[index] = await enrichedUser(users[index])
        }
        for index in groups.indices {
            groups[index] = await enrichedGroup(groups[index])
            let members = await fetchGroupMembers(groupName: groups[index].name)
            groups[index].memberNames = members.map(\.name)
            for member in members {
                if let userIndex = users.firstIndex(where: { $0.name == member.name }),
                   !users[userIndex].groupNames.contains(groups[index].name) {
                    users[userIndex].groupNames.append(groups[index].name)
                    if users[userIndex].uid == nil {
                        users[userIndex].uid = member.uid
                    }
                    if users[userIndex].description.isEmpty {
                        users[userIndex].description = member.description
                    }
                }
            }
        }

        return SynologyUsersGroupsSnapshot(
            users: users,
            groups: groups,
            sharedFolders: await fetchSharedFolderPermissions(username: selectedUser),
            quotas: await fetchUserQuotas(username: selectedUser),
            home: await fetchUserHomeSettings(),
            passwordPolicy: await fetchPasswordPolicy(),
            collectedAt: Date()
        )
    }

    func fetchExternalAccess() async throws -> [NASControlPanelRow] {
        let details = try await fetchExternalAccessDetailsWithoutReconnect()
        let ddnsCount = details.ddnsRecords.count
        return [
            NASControlPanelRow(title: "DDNS", value: "\(ddnsCount) 条记录"),
            NASControlPanelRow(title: "QuickConnect", value: details.quickConnect.enabled ? "已开启" : "未开启"),
            NASControlPanelRow(title: "外部地址", value: details.dsmExternalHostname.isEmpty ? "未设置" : details.dsmExternalHostname),
            NASControlPanelRow(title: "操作", value: "可编辑")
        ]
    }

    func fetchExternalAccessDetailsWithoutReconnect() async throws -> SynologyExternalAccessSnapshot {
        let ddnsJSON = try await optionalJSON(apiNames: ["SYNO.Core.DDNS.Record"], method: "list", extraParameters: [:])
        let quickConnectJSON = try await optionalJSON(apiNames: ["SYNO.Core.QuickConnect"], method: "get", extraParameters: [:])
        let dsmExternalJSON = try await optionalJSON(apiNames: ["SYNO.Core.Web.DSM.External"], method: "get", extraParameters: [:])
        guard ddnsJSON != nil || quickConnectJSON != nil || dsmExternalJSON != nil else {
            throw SynologyClientError.apiUnavailable("当前 DSM 版本未提供此状态接口。")
        }
        return SynologyExternalAccessSnapshot(
            ddnsRecords: parseDDNSRecords(from: ddnsJSON ?? [:]),
            quickConnect: parseQuickConnect(from: quickConnectJSON ?? [:]),
            dsmExternalHostname: firstString(in: dsmExternalJSON ?? [:], keys: ["hostname"]) ?? "",
            collectedAt: Date()
        )
    }

    func fetchNetwork() async throws -> [NASControlPanelRow] {
        let details = try await fetchNetworkDetailsWithoutReconnect()
        let dns = details.dnsServers.isEmpty ? "未读取到" : details.dnsServers.joined(separator: "、")
        return [
            NASControlPanelRow(title: "主机名", value: details.hostname),
            NASControlPanelRow(title: "IP", value: details.primaryIP),
            NASControlPanelRow(title: "网关", value: details.gateway),
            NASControlPanelRow(title: "DNS", value: dns),
            NASControlPanelRow(title: "代理", value: details.proxyEnabled ? "\(details.proxyHost):\(details.proxyPort)" : "未开启")
        ]
    }

    func fetchNetworkDetailsWithoutReconnect() async throws -> SynologyNetworkSettingsSnapshot {
        let general = try await optionalJSON(apiNames: ["SYNO.Core.Network", "SYNO.Core.Network.General"], method: "get", extraParameters: [:])
        let interfacesJSON = try await optionalJSON(apiNames: ["SYNO.Core.Network.Interface", "SYNO.Core.Network.Ethernet"], method: "list", extraParameters: [:])
        let proxyJSON = try await optionalJSON(apiNames: ["SYNO.Core.Network.Proxy"], method: "get", extraParameters: [:], preferredVersion: 1)
        guard general != nil || interfacesJSON != nil || proxyJSON != nil else {
            throw SynologyClientError.apiUnavailable("当前 DSM 版本未提供此状态接口。")
        }
        let network = mergedNetworkObject(general: general ?? [:], interfaces: interfacesJSON ?? [:])
        let proxy = proxyJSON ?? [:]
        let hostname = firstString(in: network, keys: ["hostname", "server_name", "host_name"]) ?? connection.host
        let gateway = firstString(in: network, keys: ["gateway", "default_gateway", "gateway_ip"]) ?? "-"
        let dnsServers = extractDNSServers(from: network)
        let ip = firstString(in: network, keys: ["ip", "ip_address", "addr", "address"]) ?? firstIPAddress(in: network) ?? "-"
        let proxyHost = firstString(in: proxy, keys: ["http_host", "https_host", "proxy_server", "proxy_host", "host", "server", "address"]) ?? ""
        let proxyPort = firstString(in: proxy, keys: ["http_port", "https_port", "proxy_port", "port"]) ?? ""
        synologyDebugLog("Proxy get raw: \(proxy)")
        return SynologyNetworkSettingsSnapshot(
            hostname: hostname,
            primaryIP: ip,
            gateway: gateway,
            dnsServers: dnsServers,
            interfaces: interfaceSummaries(from: interfacesJSON ?? [:]),
            proxyEnabled: boolValue(findValue(in: proxy, keys: ["enable", "enabled", "proxy", "use_proxy", "proxy_enable"])) ?? false,
            proxyHost: proxyHost,
            proxyPort: proxyPort,
            proxyBypassLocal: boolValue(findValue(in: proxy, keys: ["enable_bypass", "skip_local", "bypass_local", "proxy_local_bypass", "local_bypass"])) ?? false,
            collectedAt: Date()
        )
    }

    func fetchTerminalSettingsWithoutReconnect() async throws -> SynologyTerminalSettingsSnapshot {
        guard let terminal = try await optionalJSON(apiNames: ["SYNO.Core.Terminal", "SYNO.Core.Terminal.SSH"], method: "get", extraParameters: [:]) else {
            throw SynologyClientError.apiUnavailable("当前 DSM 版本未提供此状态接口。")
        }
        let sshEnabled = boolValue(findValue(in: terminal, keys: ["ssh", "ssh_enable", "enable_ssh", "enabled"])) ?? false
        let telnetEnabled = boolValue(findValue(in: terminal, keys: ["telnet", "telnet_enable", "enable_telnet"])) ?? false
        let sshPort = firstInt(in: terminal, keys: ["ssh_port", "port"]) ?? 22
        return SynologyTerminalSettingsSnapshot(
            sshEnabled: sshEnabled,
            telnetEnabled: telnetEnabled,
            sshPort: sshPort,
            collectedAt: Date()
        )
    }

    func fetchTerminalSNMP() async throws -> [NASControlPanelRow] {
        let terminal = try await fetchTerminalSettingsWithoutReconnect()
        return [
            NASControlPanelRow(title: "SSH", value: enabledText(terminal.sshEnabled)),
            NASControlPanelRow(title: "Telnet", value: enabledText(terminal.telnetEnabled)),
            NASControlPanelRow(title: "SSH 端口", value: "\(terminal.sshPort)")
        ]
    }

    func fetchInfoCenter() async throws -> [NASControlPanelRow] {
        let system = try await firstAvailableJSON(
            apiNames: ["SYNO.Core.System", "SYNO.Core.System.Info"],
            methods: ["info", "get"],
            extraParameters: [:]
        )
        return [
            NASControlPanelRow(title: "型号", value: firstString(in: system, keys: ["model", "model_name"]) ?? "-"),
            NASControlPanelRow(title: "DSM", value: firstString(in: system, keys: ["version_string", "firmware_ver", "version"]) ?? "-"),
            NASControlPanelRow(title: "序列号", value: firstString(in: system, keys: ["serial", "serial_number"]) ?? "需要 DSM 权限"),
            NASControlPanelRow(title: "运行时间", value: systemUptimeText(from: system))
        ]
    }

    func fetchUpdateRestore() async throws -> [NASControlPanelRow] {
        let system = try await firstAvailableJSON(
            apiNames: ["SYNO.Core.System", "SYNO.Core.System.Info"],
            methods: ["info", "get"],
            extraParameters: [:]
        )
        return [
            NASControlPanelRow(title: "DSM 版本", value: firstString(in: system, keys: ["version_string", "firmware_ver", "version"]) ?? "-")
        ]
    }

    func optionalListCount(apiNames: [String], method: String, keys: [String]) async throws -> Int? {
        guard let json = try await optionalJSON(apiNames: apiNames, method: method, extraParameters: [:]) else { return nil }
        return countItems(in: json, keys: keys)
    }

    func optionalJSON(apiNames: [String], method: String, extraParameters: [String: String], preferredVersion: Int? = nil) async throws -> [String: Any]? {
        do {
            return try await callAPI(apiNames: apiNames, method: method, extraParameters: extraParameters, preferredVersion: preferredVersion)
        } catch SynologyClientError.apiUnavailable {
            return nil
        } catch SynologyClientError.permissionDenied {
            return nil
        }
    }

    func firstAvailableJSON(apiNames: [String], methods: [String], extraParameters: [String: String]) async throws -> [String: Any] {
        var lastError: Error?
        for method in methods {
            do {
                return try await callAPI(apiNames: apiNames, method: method, extraParameters: extraParameters)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? SynologyClientError.apiUnavailable("当前 DSM 版本未提供此状态接口。")
    }

    func callAPI(
        apiNames: [String],
        method: String,
        extraParameters: [String: String],
        errorContext: DSMErrorContext? = nil,
        preferredVersion: Int? = nil,
        httpMethod: String = "GET"
    ) async throws -> [String: Any] {
        do {
            return try await callAPIWithoutRetry(apiNames: apiNames, method: method, extraParameters: extraParameters, errorContext: errorContext, preferredVersion: preferredVersion, httpMethod: httpMethod)
        } catch SynologyClientError.sessionExpired {
            sid = try await login()
            return try await callAPIWithoutRetry(apiNames: apiNames, method: method, extraParameters: extraParameters, errorContext: errorContext, preferredVersion: preferredVersion, httpMethod: httpMethod)
        }
    }

    func callCompoundAPI(_ requests: [[String: Any]]) async throws {
        do {
            try await callCompoundAPIWithoutRetry(requests)
        } catch SynologyClientError.sessionExpired {
            sid = try await login()
            try await callCompoundAPIWithoutRetry(requests)
        }
    }

    func callCompoundAPIWithoutRetry(_ requests: [[String: Any]]) async throws {
        guard let sid else { throw SynologyClientError.sessionExpired }
        let data = try JSONSerialization.data(withJSONObject: requests)
        guard let compound = String(data: data, encoding: .utf8) else {
            throw SynologyClientError.apiUnavailable("DSM DDNS 保存参数生成失败。")
        }
        let entry = apiInfo["SYNO.Entry.Request"]
        let json = try await requestJSON(
            path: entry?.path ?? "/webapi/entry.cgi",
            parameters: [
                "api": "SYNO.Entry.Request",
                "version": "\(entry?.maxVersion ?? 1)",
                "method": "request",
                "mode": "sequential",
                "stopwhenerror": "true",
                "compound": compound,
                "_sid": sid
            ],
            requiresSuccess: true,
            errorContext: .module("SYNO.Entry.Request")
        )
        let dataObject = (json["data"] as? [String: Any]) ?? json
        let results = dataObject["result"] as? [[String: Any]] ?? []
        for result in results {
            if (result["success"] as? Bool) == false {
                throw mapDSMError(result, context: .module(firstString(in: result, keys: ["api"]) ?? "SYNO.Core.DDNS.Record"))
            }
        }
    }

    func callAPIWithoutRetry(
        apiNames: [String],
        method: String,
        extraParameters: [String: String],
        errorContext: DSMErrorContext? = nil,
        preferredVersion: Int? = nil,
        httpMethod: String = "GET"
    ) async throws -> [String: Any] {
        guard let sid else { throw SynologyClientError.sessionExpired }
        var lastError: Error?
        for apiName in apiNames {
            guard let info = apiInfo[apiName] else {
                lastError = SynologyClientError.apiUnavailable("\(apiName) 不可用。")
                continue
            }
            do {
                let version = preferredVersion.map { min(max($0, info.minVersion), info.maxVersion) } ?? info.maxVersion
                var parameters = [
                    "api": apiName,
                    "version": "\(version)",
                    "method": method,
                    "_sid": sid
                ]
                parameters.merge(extraParameters) { _, new in new }
                let json: [String: Any]
                if httpMethod.uppercased() == "POST", info.requestFormat == "JSON" {
                    json = try await requestJSONBody(
                        path: info.path,
                        queryParameters: [
                            "api": apiName,
                            "version": "\(version)",
                            "method": method,
                            "_sid": sid
                        ],
                        body: jsonBodyParameters(from: extraParameters),
                        requiresSuccess: true,
                        errorContext: errorContext ?? .module(apiName)
                    )
                } else {
                    json = try await requestJSON(
                        path: info.path,
                        parameters: parameters,
                        httpMethod: httpMethod,
                        requiresSuccess: true,
                        errorContext: errorContext ?? .module(apiName)
                    )
                }
                return (json["data"] as? [String: Any]) ?? json
            } catch {
                lastError = error
            }
        }
        throw lastError ?? SynologyClientError.apiUnavailable("当前 DSM 版本未提供此状态接口。")
    }

    func jsonBodyParameters(from parameters: [String: String]) -> [String: Any] {
        parameters.mapValues { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = trimmed.lowercased()
            if lowered == "true" { return true }
            if lowered == "false" { return false }
            if let intValue = Int(trimmed), String(intValue) == trimmed {
                return intValue
            }
            return value
        }
    }

    func requestJSON(
        path: String,
        parameters: [String: String],
        httpMethod: String = "GET",
        requiresSuccess: Bool,
        errorContext: DSMErrorContext = .module("DSM")
    ) async throws -> [String: Any] {
        var components = try baseURL()
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        var request: URLRequest
        if httpMethod.uppercased() == "POST" {
            let queryKeys: Set<String> = ["api", "version", "method", "_sid"]
            let queryParameters = parameters.filter { queryKeys.contains($0.key) }
            let bodyParameters = parameters.filter { !queryKeys.contains($0.key) }
            components.queryItems = queryParameters.map { URLQueryItem(name: $0.key, value: $0.value) }
            guard let url = components.url else { throw SynologyClientError.invalidAddress }
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = formURLEncodedData(bodyParameters)
        } else {
            components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
            guard let url = components.url else { throw SynologyClientError.invalidAddress }
            request = URLRequest(url: url)
        }
        do {
            let (data, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw SynologyClientError.apiUnavailable("DSM 返回内容不是 JSON。")
            }
            if requiresSuccess, (object["success"] as? Bool) != true {
                throw mapDSMError(object, context: errorContext)
            }
            return object
        } catch let error as SynologyClientError {
            throw error
        } catch let error as CancellationError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw mapURLError(error)
        } catch {
            if error.isSynologyCancellation { throw error }
            throw SynologyClientError.connectionFailed(error.localizedDescription)
        }
    }

    func requestJSONBody(
        path: String,
        queryParameters: [String: String],
        body: [String: Any],
        requiresSuccess: Bool,
        errorContext: DSMErrorContext = .module("DSM")
    ) async throws -> [String: Any] {
        var components = try baseURL()
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        if !queryParameters.isEmpty {
            components.queryItems = queryParameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw SynologyClientError.invalidAddress }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        guard JSONSerialization.isValidJSONObject(body) else {
            throw SynologyClientError.apiUnavailable("DSM 请求参数无效，请在 DSM 控制台中修改。")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        do {
            let (data, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw SynologyClientError.apiUnavailable("DSM 返回内容不是 JSON。")
            }
            if requiresSuccess, (object["success"] as? Bool) != true {
                throw mapDSMError(object, context: errorContext)
            }
            return (object["data"] as? [String: Any]) ?? object
        } catch let error as SynologyClientError {
            throw error
        } catch let error as CancellationError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw mapURLError(error)
        } catch {
            if error.isSynologyCancellation { throw error }
            throw SynologyClientError.connectionFailed(error.localizedDescription)
        }
    }

    func baseURL() throws -> URLComponents {
        var host = connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = URLComponents(string: host), let parsedHost = parsed.host {
            host = parsedHost
        }
        guard !host.isEmpty else { throw SynologyClientError.invalidAddress }
        var components = URLComponents()
        components.scheme = connection.scheme.rawValue
        components.host = host
        components.port = connection.port
        return components
    }

    func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SynologyClientError.connectionFailed("DSM 没有返回有效响应。")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw SynologyClientError.connectionFailed("DSM HTTP 状态码 \(httpResponse.statusCode)。")
        }
    }

    func formURLEncodedData(_ parameters: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._* ")
        let body = parameters.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed)?
                .replacingOccurrences(of: " ", with: "+") ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed)?
                .replacingOccurrences(of: " ", with: "+") ?? value
            return "\(encodedKey)=\(encodedValue)"
        }
        .joined(separator: "&")
        return Data(body.utf8)
    }

    enum DSMErrorContext {
        case auth
        case module(String)
        case userManagement
        case quickConnect
        case networkSettings
        case proxySettings
        case terminalSettings
    }

    func saveProxySettingsWithFallback(enabled: Bool, host: String, port: String, bypassLocal: Bool) async throws -> SynologyNetworkSettingsSnapshot {
        var lastError: Error?
        let submittedHost = enabled ? host : ""
        let submittedPort = enabled ? port : ""

        // 代理写入必须读回校验，因为部分 DSM 版本会返回 success=true，
        // 但静默丢弃不支持的参数名。除非经过 DSM 实测确认，否则不要调整顺序；
        // 第一组参数体匹配当前 DSM 控制面板。
        let candidateParameters: [[String: String]] = [
            [
                "enable": enabled ? "true" : "false",
                "http_host": submittedHost,
                "http_port": submittedPort,
                "https_host": submittedHost,
                "https_port": submittedPort,
                "enable_different_host": "false",
                "enable_auth": "false",
                "username": "",
                "password": "",
                "enable_bypass": bypassLocal ? "true" : "false"
            ],
            [
                "enable": enabled ? "true" : "false",
                "proxy_server": submittedHost,
                "proxy_port": submittedPort,
                "proxy_local_bypass": bypassLocal ? "true" : "false",
                "enable_bypass": bypassLocal ? "true" : "false"
            ],
            [
                "proxy_enabled": enabled ? "true" : "false",
                "proxy_host": submittedHost,
                "proxy_port": submittedPort,
                "proxy_local_bypass": bypassLocal ? "true" : "false",
                "enable_bypass": bypassLocal ? "true" : "false"
            ]
        ]

        for parameters in candidateParameters {
            do {
                synologyDebugLog("Proxy set try: \(parameters)")
                let setJSON = try await callAPI(
                    apiNames: ["SYNO.Core.Network.Proxy"],
                    method: "set",
                    extraParameters: parameters,
                    errorContext: .proxySettings,
                    preferredVersion: 1,
                    httpMethod: "POST"
                )
                synologyDebugLog("Proxy set response: \(setJSON)")
                let updated = try await fetchNetworkDetailsWithoutReconnect()
                synologyDebugLog("Proxy readback parsed: enabled=\(updated.proxyEnabled), host=\(updated.proxyHost), port=\(updated.proxyPort), bypass=\(updated.proxyBypassLocal)")
            // 这里 DSM 响应成功还不够；只有下一次 get 精确反映用户提交内容时，
            // 才接受这次保存。
                if proxySettingsMatch(updated, enabled: enabled, host: host, port: port, bypassLocal: bypassLocal) {
                    return updated
                }
                lastError = SynologyClientError.apiUnavailable("DSM 未接受代理服务器设置，请在 DSM 控制台中确认权限或接口支持。")
            } catch SynologyClientError.sessionExpired {
                throw SynologyClientError.sessionExpired
            } catch {
                lastError = error
            }
        }
        throw lastError ?? SynologyClientError.apiUnavailable("代理服务器设置保存失败，请在 DSM 控制台中修改。")
    }

    func synologyDebugLog(_ message: String) {
        #if DEBUG
        NSLog("[Servera][DSMProxy] %@", message)
        #endif
    }

    func proxySettingsMatch(
        _ snapshot: SynologyNetworkSettingsSnapshot,
        enabled: Bool,
        host: String,
        port: String,
        bypassLocal: Bool
    ) -> Bool {
        if !enabled {
            return snapshot.proxyEnabled == false
        }
        return snapshot.proxyEnabled == enabled
            && snapshot.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines) == host
            && snapshot.proxyPort.trimmingCharacters(in: .whitespacesAndNewlines) == port
            && snapshot.proxyBypassLocal == bypassLocal
    }

    func mapDSMError(_ json: [String: Any], context: DSMErrorContext) -> SynologyClientError {
        let code = ((json["error"] as? [String: Any])?["code"] as? Int) ?? 0
        switch context {
        case .auth:
            switch code {
            case 400, 401, 404:
                return .authenticationFailed("DSM 账号或密码错误。")
            case 403:
                return .twoFactorRequired
            default:
                return .apiUnavailable(code == 0 ? "DSM 登录失败。" : "DSM 登录失败，错误码 \(code)。")
            }
        case .userManagement:
            switch code {
            case 105, 106, 107, 119:
                return .sessionExpired
            case 402, 407:
                return .permissionDenied("当前 DSM 账号没有修改用户与群组的权限。")
            case 101, 102, 103, 104, 400:
                return .apiUnavailable("DSM 不接受当前用户管理参数，请检查密码策略、群组、权限或配额设置。")
            default:
                return .apiUnavailable(code == 0 ? "用户管理保存失败。" : "用户管理保存失败，错误码 \(code)。")
            }
        case .quickConnect:
            switch code {
            case 105, 106, 107, 119:
                return .sessionExpired
            case 402, 407:
                return .permissionDenied("当前 DSM 账号没有修改 QuickConnect 的权限。")
            case 101, 102, 103, 104, 400:
                return .apiUnavailable("QuickConnect 保存失败：当前 DSM 接口不支持 App 修改，或参数不兼容。请在 DSM 控制台中修改。")
            default:
                return .apiUnavailable(code == 0 ? "QuickConnect 保存失败。" : "QuickConnect 保存失败，错误码 \(code)。")
            }
        case .networkSettings:
            switch code {
            case 105, 106, 107, 119:
                return .sessionExpired
            case 402, 407:
                return .permissionDenied("当前 DSM 账号没有修改网络设置的权限。")
            case 101, 102, 103, 104, 400:
                return .apiUnavailable("当前 DSM 接口不支持 App 修改此设置，请在 DSM 控制台中修改。")
            default:
                return .apiUnavailable(code == 0 ? "网络设置保存失败。" : "网络设置保存失败，错误码 \(code)。")
            }
        case .proxySettings:
            switch code {
            case 105, 106, 107, 119:
                return .sessionExpired
            case 402, 407:
                return .permissionDenied("当前 DSM 账号没有修改代理服务器设置的权限。")
            case 101, 102, 103, 104, 400:
                return .apiUnavailable("代理服务器保存失败：当前 DSM 接口不支持 App 修改，或参数不兼容。请在 DSM 控制台中修改。")
            default:
                return .apiUnavailable(code == 0 ? "代理服务器保存失败。" : "代理服务器保存失败，错误码 \(code)。")
            }
        case .terminalSettings:
            switch code {
            case 105, 106, 107, 119:
                return .sessionExpired
            case 402, 407:
                return .permissionDenied("当前 DSM 账号没有修改终端机设置的权限。")
            case 101, 102, 103, 104, 400:
                return .apiUnavailable("当前 DSM 接口不支持 App 修改终端机设置，请在 DSM 控制台中修改。")
            default:
                return .apiUnavailable(code == 0 ? "终端机设置保存失败。" : "终端机设置保存失败，错误码 \(code)。")
            }
        case .module:
            if isDDNSContext(context) {
                switch code {
                case 105, 106, 107, 119:
                    return .sessionExpired
                case 402, 407:
                    return .permissionDenied("当前 DSM 账号没有修改 DDNS 的权限。")
                case 101, 102, 103, 114:
                    return .apiUnavailable("DDNS 保存失败：DSM 不接受当前参数，请检查服务商、主机名、账号和密码/Token。")
                default:
                    return .apiUnavailable(code == 0 ? "DDNS 保存失败。" : "DDNS 保存失败，错误码 \(code)。")
                }
            }
            switch code {
            case 105, 106, 107, 119:
                return .sessionExpired
            case 402, 407:
                return .permissionDenied("当前 DSM 账号没有读取此控制面板模块的权限。")
            default:
                return .apiUnavailable(code == 0 ? "当前 DSM 版本未提供此状态接口。" : "当前 DSM 版本未提供此状态接口，错误码 \(code)。")
            }
        }
    }

    func isDDNSContext(_ context: DSMErrorContext) -> Bool {
        guard case .module(let apiName) = context else { return false }
        return apiName == "SYNO.Core.DDNS.Record" || apiName == "SYNO.Entry.Request"
    }

    func mapURLError(_ error: URLError) -> SynologyClientError {
        switch error.code {
        case .cannotFindHost, .dnsLookupFailed:
            return .connectionFailed("找不到 DSM 地址。")
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            return .connectionFailed("无法连接 DSM，请检查地址、端口和网络。")
        case .timedOut:
            return .connectionFailed("连接 DSM 超时。")
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .secureConnectionFailed:
            return .certificateInvalid("DSM SSL 证书无效；如果是自签名证书，可以关闭 SSL 校验后重试。")
        default:
            return .connectionFailed(error.localizedDescription)
        }
    }

    func normalizedModuleError(_ error: Error) -> String {
        if let clientError = error as? SynologyClientError {
            return clientError.localizedDescription
        }
        if error.isSynologyCancellation { return "等待刷新" }
        return error.localizedDescription
    }

    func summary(for module: NASControlPanelModule, rows: [NASControlPanelRow]) -> String {
        switch module {
        case .users:
            return rows.prefix(2).map { "\($0.title) \($0.value)" }.joined(separator: " · ")
        case .externalAccess:
            return rows.first?.value ?? "外部访问状态可读取"
        case .network:
            return rows.first(where: { $0.title == "IP" })?.value ?? "网络状态可读取"
        case .terminalSNMP:
            let ssh = rows.first(where: { $0.title == "SSH" })?.value ?? "未读取"
            let telnet = rows.first(where: { $0.title == "Telnet" })?.value ?? "未读取"
            let port = rows.first(where: { $0.title == "SSH 端口" })?.value ?? "未读取"
            return "SSH \(ssh) · Telnet \(telnet) · 端口 \(port)"
        case .infoCenter:
            return rows.first(where: { $0.title == "DSM" })?.value ?? "系统信息可读取"
        case .updateRestore:
            return rows.first(where: { $0.title == "DSM 版本" })?.value ?? "DSM 版本可读取"
        }
    }

    func parseDDNSRecords(from json: [String: Any]) -> [SynologyDDNSRecord] {
        let rawRecords = findValue(in: json, keys: ["records", "items", "ddns"]) as? [[String: Any]] ?? []
        return rawRecords.enumerated().map { index, dictionary in
            let hostname = firstString(in: dictionary, keys: ["hostname", "host"]) ?? ""
            let provider = firstString(in: dictionary, keys: ["provider", "id"]) ?? ""
            return SynologyDDNSRecord(
                id: firstString(in: dictionary, keys: ["id"]) ?? "\(provider)-\(hostname)-\(index)",
                hostname: hostname,
                provider: provider,
                username: firstString(in: dictionary, keys: ["username", "account"]) ?? "",
                ip: firstString(in: dictionary, keys: ["ip", "ipv4"]) ?? "-",
                ipv6: firstString(in: dictionary, keys: ["ipv6"]) ?? "-",
                status: firstString(in: dictionary, keys: ["status", "state"]) ?? "-",
                net: firstString(in: dictionary, keys: ["net"]) ?? "MANUAL_V4",
                interfaceV4: firstString(in: dictionary, keys: ["interface_v4"]) ?? "default",
                interfaceV6: firstString(in: dictionary, keys: ["interface_v6"]) ?? "default",
                enabled: boolValue(findValue(in: dictionary, keys: ["enable", "enabled"])) ?? false,
                heartbeat: boolValue(findValue(in: dictionary, keys: ["heartbeat"])) ?? false
            )
        }
    }

    func parseQuickConnect(from json: [String: Any]) -> SynologyQuickConnectSettings {
        SynologyQuickConnectSettings(
            enabled: boolValue(findValue(in: json, keys: ["enabled", "enable"])) ?? false,
            serverID: firstString(in: json, keys: ["server_id", "server_alias", "quickconnect_id"]) ?? "",
            domain: firstString(in: json, keys: ["domain"]) ?? "quickconnect.to",
            account: firstString(in: json, keys: ["myds_account", "account"]) ?? "",
            region: firstString(in: json, keys: ["region"]) ?? ""
        )
    }

    func parseNASUsers(from json: [String: Any]) -> [SynologyNASUser] {
        let rawUsers = findValue(in: json, keys: ["users", "items", "user"]) as? [[String: Any]] ?? []
        return rawUsers.compactMap { dictionary in
            let name = firstString(in: dictionary, keys: ["name", "username", "user"]) ?? ""
            guard !name.isEmpty else { return nil }
            return SynologyNASUser(
                name: name,
                uid: firstInt(in: dictionary, keys: ["uid"]),
                fullName: firstString(in: dictionary, keys: ["fullname", "full_name", "display_name"]) ?? "",
                email: firstString(in: dictionary, keys: ["email", "mail"]) ?? "",
                description: firstString(in: dictionary, keys: ["description", "desc"]) ?? "",
                isEditable: boolValue(findValue(in: dictionary, keys: ["editable"])),
                isEnabled: enabledValue(in: dictionary),
                otpEnabled: boolValue(findValue(in: dictionary, keys: ["OTP_enable", "otp_enable", "otp_enabled"])),
                otpEnforced: boolValue(findValue(in: dictionary, keys: ["OTP_enforced", "otp_enforced"])),
                disallowPasswordChange: boolValue(findValue(in: dictionary, keys: ["disallowchpasswd", "disallow_change_password"])),
                passwordLastChangeDay: firstInt(in: dictionary, keys: ["password_last_change"]),
                groupNames: []
            )
        }
    }

    func parseNASGroups(from json: [String: Any]) -> [SynologyNASGroup] {
        let rawGroups = findValue(in: json, keys: ["groups", "items", "group"]) as? [[String: Any]] ?? []
        return rawGroups.compactMap { dictionary in
            let name = firstString(in: dictionary, keys: ["name", "groupname", "group"]) ?? ""
            guard !name.isEmpty else { return nil }
            return SynologyNASGroup(
                name: name,
                gid: firstInt(in: dictionary, keys: ["gid"]),
                description: firstString(in: dictionary, keys: ["description", "desc"]) ?? "",
                memberNames: []
            )
        }
    }

    func enrichedUser(_ user: SynologyNASUser) async -> SynologyNASUser {
        var updated = user
        if let json = try? await optionalJSON(
            apiNames: ["SYNO.Core.User"],
            method: "get",
            extraParameters: ["name": user.name]
        ) {
            let source = firstDictionary(in: json, keys: ["users", "user"]) ?? json
            updated.uid = updated.uid ?? firstInt(in: source, keys: ["uid"])
            updated.fullName = firstString(in: source, keys: ["fullname", "full_name", "display_name"]) ?? updated.fullName
            updated.email = firstString(in: source, keys: ["email", "mail"]) ?? updated.email
            updated.description = firstString(in: source, keys: ["description", "desc"]) ?? updated.description
            updated.isEditable = boolValue(findValue(in: source, keys: ["editable"])) ?? updated.isEditable
            updated.isEnabled = enabledValue(in: source) ?? updated.isEnabled
            updated.otpEnabled = boolValue(findValue(in: source, keys: ["OTP_enable", "otp_enable", "otp_enabled"])) ?? updated.otpEnabled
            updated.otpEnforced = boolValue(findValue(in: source, keys: ["OTP_enforced", "otp_enforced"])) ?? updated.otpEnforced
            updated.disallowPasswordChange = boolValue(findValue(in: source, keys: ["disallowchpasswd", "disallow_change_password"])) ?? updated.disallowPasswordChange
            updated.passwordLastChangeDay = firstInt(in: source, keys: ["password_last_change"]) ?? updated.passwordLastChangeDay
        }
        if user.name == connection.account,
           let json = try? await optionalJSON(
            apiNames: ["SYNO.Core.NormalUser"],
            method: "get",
            extraParameters: ["username": user.name]
           ) {
            updated.fullName = firstString(in: json, keys: ["fullname", "full_name", "display_name"]) ?? updated.fullName
            updated.email = firstString(in: json, keys: ["email", "mail"]) ?? updated.email
            updated.isEditable = boolValue(findValue(in: json, keys: ["editable"])) ?? updated.isEditable
            updated.isEnabled = enabledValue(in: json) ?? updated.isEnabled
            updated.otpEnabled = boolValue(findValue(in: json, keys: ["OTP_enable", "otp_enable", "otp_enabled"])) ?? updated.otpEnabled
            updated.otpEnforced = boolValue(findValue(in: json, keys: ["OTP_enforced", "otp_enforced"])) ?? updated.otpEnforced
            updated.disallowPasswordChange = boolValue(findValue(in: json, keys: ["disallowchpasswd", "disallow_change_password"])) ?? updated.disallowPasswordChange
            updated.passwordLastChangeDay = firstInt(in: json, keys: ["password_last_change"]) ?? updated.passwordLastChangeDay
        }
        return updated
    }

    func enrichedGroup(_ group: SynologyNASGroup) async -> SynologyNASGroup {
        guard let json = try? await optionalJSON(
            apiNames: ["SYNO.Core.Group"],
            method: "get",
            extraParameters: ["name": group.name]
        ) else {
            return group
        }
        var updated = group
        let source = firstDictionary(in: json, keys: ["groups", "group"]) ?? json
        updated.gid = updated.gid ?? firstInt(in: source, keys: ["gid"])
        updated.description = firstString(in: source, keys: ["description", "desc"]) ?? updated.description
        return updated
    }

    func fetchGroupMembers(groupName: String) async -> [SynologyNASUser] {
        guard let json = try? await optionalJSON(
            apiNames: ["SYNO.Core.Group.Member"],
            method: "list",
            extraParameters: ["group": groupName]
        ) else {
            return []
        }
        return parseNASUsers(from: json)
    }

    func fetchSharedFolderPermissions(username: String?) async -> [SynologySharedFolderPermission] {
        guard let username, !username.isEmpty else { return [] }
        let shareJSON = try? await optionalJSON(apiNames: ["SYNO.Core.Share"], method: "list", extraParameters: [:])
        let rawShares = shareJSON.flatMap { findValue(in: $0, keys: ["shares", "items", "share"]) as? [[String: Any]] } ?? []
        var permissions: [SynologySharedFolderPermission] = []
        for share in rawShares {
            let name = firstString(in: share, keys: ["name", "sharename", "share_name"]) ?? ""
            guard !name.isEmpty else { continue }
            let permissionJSON = try? await optionalJSON(
                apiNames: ["SYNO.Core.Share.Permission", "SYNO.Core.Share"],
                method: "get",
                extraParameters: ["name": name, "user": username]
            )
            permissions.append(
                SynologySharedFolderPermission(
                    name: name,
                    path: firstString(in: share, keys: ["path"]) ?? "",
                    volume: volumeName(from: share),
                    permission: sharePermission(from: permissionJSON ?? [:], username: username)
                )
            )
        }
        return permissions
    }

    func fetchUserQuotas(username: String?) async -> [SynologyUserQuota] {
        guard let username, !username.isEmpty else { return [] }
        guard let json = try? await optionalJSON(
            apiNames: ["SYNO.Core.Quota", "SYNO.Core.User.Quota"],
            method: "list",
            extraParameters: ["user": username]
        ) else {
            return []
        }
        let rawQuotas = findValue(in: json, keys: ["quotas", "items", "quota", "volumes"]) as? [[String: Any]] ?? []
        return rawQuotas.compactMap { item in
            let volume = firstString(in: item, keys: ["volume", "vol_path", "path", "name"]) ?? ""
            guard !volume.isEmpty else { return nil }
            return SynologyUserQuota(
                volume: volume,
                usedBytes: firstInt64(in: item, keys: ["used", "used_byte", "used_bytes"]),
                limitBytes: firstInt64(in: item, keys: ["quota", "quota_byte", "quota_bytes", "limit", "limit_bytes"]),
                enabled: boolValue(findValue(in: item, keys: ["enabled", "enable"]))
            )
        }
    }

    func fetchUserHomeSettings() async -> SynologyUserHomeSettings {
        guard let json = try? await optionalJSON(apiNames: ["SYNO.Core.User.Home"], method: "get", extraParameters: [:]) else {
            return SynologyUserHomeSettings(enabled: nil, location: "", recycleBinEnabled: nil, encryption: nil)
        }
        return SynologyUserHomeSettings(
            enabled: boolValue(findValue(in: json, keys: ["enable", "enabled"])),
            location: firstString(in: json, keys: ["location", "remote_location"]) ?? "",
            recycleBinEnabled: boolValue(findValue(in: json, keys: ["enable_recycle_bin", "recycle_bin"])),
            encryption: firstInt(in: json, keys: ["encryption"])
        )
    }

    func fetchPasswordPolicy() async -> SynologyPasswordPolicySettings {
        guard let json = try? await optionalJSON(apiNames: ["SYNO.Core.User.PasswordPolicy"], method: "get", extraParameters: [:]) else {
            return SynologyPasswordPolicySettings()
        }
        return SynologyPasswordPolicySettings(
            minLengthEnabled: boolValue(findValue(in: json, keys: ["min_length_enable"])),
            minLength: firstInt(in: json, keys: ["min_length"]),
            mixedCase: boolValue(findValue(in: json, keys: ["mixed_case"])),
            numeric: boolValue(findValue(in: json, keys: ["included_numeric_char"])),
            specialCharacter: boolValue(findValue(in: json, keys: ["included_special_char"])),
            excludeUsername: boolValue(findValue(in: json, keys: ["exclude_username"])),
            excludeCommonPassword: boolValue(findValue(in: json, keys: ["exclude_common_password"])),
            passwordMustChange: boolValue(findValue(in: json, keys: ["password_must_change"])),
            resetByEmailEnabled: boolValue(findValue(in: json, keys: ["enable_reset_passwd_by_email"]))
        )
    }

    func enabledValue(in dictionary: [String: Any]) -> Bool? {
        if let value = boolValue(findValue(in: dictionary, keys: ["enabled", "enable", "is_enabled"])) {
            return value
        }
        if let disabled = boolValue(findValue(in: dictionary, keys: ["disabled", "is_disabled", "expired"])) {
            return !disabled
        }
        if let status = firstString(in: dictionary, keys: ["status", "state"])?.lowercased() {
            if ["normal", "enabled", "active"].contains(status) { return true }
            if ["disabled", "expired", "deactivated"].contains(status) { return false }
        }
        return nil
    }

    func volumeName(from dictionary: [String: Any]) -> String {
        if let volume = firstString(in: dictionary, keys: ["volume", "vol_path", "vol"]) {
            return volume
        }
        let path = firstString(in: dictionary, keys: ["path"]) ?? ""
        let parts = path.split(separator: "/")
        return parts.first.map(String.init) ?? ""
    }

    func sharePermission(from json: [String: Any], username: String) -> SynologySharePermissionLevel {
        let source = firstDictionary(in: json, keys: ["permission", "acl", "user"]) ?? json
        if let raw = firstString(in: source, keys: [username, "permission", "privilege", "perm", "acl"]) {
            return SynologySharePermissionLevel(dsmRawValue: raw)
        }
        if let writable = boolValue(findValue(in: source, keys: ["writable", "write", "rw", "read_write"])), writable {
            return .readWrite
        }
        if let readable = boolValue(findValue(in: source, keys: ["readable", "read", "ro", "read_only"])), readable {
            return .readOnly
        }
        if let denied = boolValue(findValue(in: source, keys: ["deny", "no_access"])), denied {
            return .noAccess
        }
        return .unknown
    }

    func countText(_ value: Int?) -> String {
        value.map(String.init) ?? "需要 DSM 权限"
    }

    func countItems(in json: [String: Any], keys: [String]) -> Int? {
        if let items = findValue(in: json, keys: keys) as? [Any] { return items.count }
        if let items = findValue(in: json, keys: keys) as? [[String: Any]] { return items.count }
        if let items = findValue(in: json, keys: keys) as? [String: Any] { return items.count }
        if let total = firstInt(in: json, keys: ["total", "count"]) { return total }
        return nil
    }

    func mergedNetworkObject(general: [String: Any], interfaces: [String: Any]) -> [String: Any] {
        var merged = general
        merged["interfaces"] = interfaceDictionaries(from: interfaces)
        return merged
    }

    func extractDNSServers(from object: Any) -> [String] {
        let directKeys = ["dns", "dns_server", "dns_servers", "nameserver", "nameservers", "primary_dns", "secondary_dns", "dns_primary", "dns_secondary"]
        var values: [String] = []
        collectDNSValues(from: object, keys: Set(directKeys), into: &values)
        return normalizedDNSServers(values)
    }

    func collectDNSValues(from object: Any, keys: Set<String>, into values: inout [String]) {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                if keys.contains(key.lowercased()) {
                    appendDNSValue(value, into: &values)
                }
                collectDNSValues(from: value, keys: keys, into: &values)
            }
        } else if let array = object as? [Any] {
            for item in array {
                collectDNSValues(from: item, keys: keys, into: &values)
            }
        }
    }

    func appendDNSValue(_ value: Any, into values: inout [String]) {
        if let string = value as? String {
            values.append(contentsOf: string.components(separatedBy: CharacterSet(charactersIn: ",; ")))
        } else if let array = value as? [Any] {
            for item in array { appendDNSValue(item, into: &values) }
        } else {
            let text = stringValue(value)
            if !text.isEmpty { values.append(text) }
        }
    }

    func normalizedDNSServers(_ raw: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for item in raw {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "-" else { continue }
            guard trimmed.contains(".") || trimmed.contains(":") else { continue }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    func interfaceDictionaries(from object: Any) -> [[String: Any]] {
        if let dictionary = object as? [String: Any] {
            if let list = findValue(in: dictionary, keys: ["interfaces", "ifaces", "items", "list", "eth", "lan"]) as? [[String: Any]] {
                return list
            }
            if dictionary.keys.contains(where: { ["id", "name", "ip", "ip_address", "addr"].contains($0.lowercased()) }) {
                return [dictionary]
            }
            for value in dictionary.values {
                let result = interfaceDictionaries(from: value)
                if !result.isEmpty { return result }
            }
        } else if let array = object as? [[String: Any]] {
            return array
        } else if let array = object as? [Any] {
            for item in array {
                let result = interfaceDictionaries(from: item)
                if !result.isEmpty { return result }
            }
        }
        return []
    }

    func interfaceSummaries(from object: Any) -> [String] {
        interfaceDictionaries(from: object).compactMap { item in
            let name = firstString(in: item, keys: ["name", "id", "interface", "ifname"]) ?? ""
            let ip = firstString(in: item, keys: ["ip", "ip_address", "addr", "address"]) ?? firstIPAddress(in: item) ?? ""
            if name.isEmpty && ip.isEmpty { return nil }
            if name.isEmpty { return ip }
            if ip.isEmpty { return name }
            return "\(name) · \(ip)"
        }
    }

    func firstIPAddress(in object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                if ["ip", "ip_address", "addr", "address"].contains(key.lowercased()),
                   let string = value as? String,
                   string.contains(".") {
                    return string
                }
                if let result = firstIPAddress(in: value) { return result }
            }
        }
        if let array = object as? [Any] {
            for item in array {
                if let result = firstIPAddress(in: item) { return result }
            }
        }
        return nil
    }

    func uptimeText(_ seconds: Int64) -> String {
        guard seconds > 0 else { return "-" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        return "\(hours) 小时"
    }

    func systemUptimeText(from dictionary: [String: Any]) -> String {
        if let seconds = firstInt64(in: dictionary, keys: ["uptime", "uptime_seconds"]) {
            return uptimeText(seconds)
        }
        guard let raw = firstString(in: dictionary, keys: ["up_time", "upTime"]) else { return "-" }
        let parts = raw.split(separator: ":").compactMap { Int64($0) }
        guard parts.count == 3 else { return raw }
        let totalHours = parts[0]
        let days = totalHours / 24
        let hours = totalHours % 24
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        return "\(hours) 小时 \(parts[1]) 分钟"
    }

    func updateStatusText(_ raw: String?) -> String {
        let status = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch status {
        case "", "unknown":
            return "等待刷新"
        case "none", "no_update", "no updates", "latest":
            return "暂无可用更新"
        case "checking", "check":
            return "正在检查"
        case "available", "available_download", "has_update", "download_available":
            return "有可用更新"
        case "downloading", "download":
            return "正在下载"
        case "downloaded", "ready":
            return "已下载，等待安装"
        case "installing", "install", "upgrading":
            return "正在安装"
        case "rebooting", "reboot":
            return "等待重启"
        case "failed", "error":
            return "检查失败"
        default:
            return raw ?? "等待刷新"
        }
    }

    func enabledText(_ value: Bool?) -> String {
        guard let value else { return "需要 DSM 权限" }
        return value ? "已开启" : "未开启"
    }

    func enabledAlgorithmText(in dictionary: [String: Any], key: String) -> String {
        guard let algorithms = findValue(in: dictionary, keys: [key]) as? [[String: Any]] else {
            return "未读取到"
        }
        let names = algorithms.compactMap { algorithm -> String? in
            guard boolValue(findValue(in: algorithm, keys: ["in_use", "enabled"])) == true else { return nil }
            return firstString(in: algorithm, keys: ["name"])
        }
        guard !names.isEmpty else { return "未启用" }
        let preview = names.prefix(3).joined(separator: "、")
        return "\(names.count) 个启用 · \(preview)\(names.count > 3 ? "…" : "")"
    }

    func normalizedDDNSIPv4(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "-" ? "0.0.0.0" : trimmed
    }

    func normalizedDDNSIPv6(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "-" ? "0:0:0:0:0:0:0:0" : trimmed
    }

    func normalizedAPIPath(_ rawPath: String?) -> String {
        let trimmed = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "/webapi/entry.cgi" }
        if trimmed.hasPrefix("/webapi/") { return trimmed }
        if trimmed.hasPrefix("/") { return "/webapi\(trimmed)" }
        return "/webapi/\(trimmed)"
    }

    func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = findValue(in: dictionary, keys: [key]) {
                let text = stringValue(value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    func firstInt(in dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = findValue(in: dictionary, keys: [key]), let int = intValue(value) {
                return int
            }
        }
        return nil
    }

    func firstInt64(in dictionary: [String: Any], keys: [String]) -> Int64? {
        for key in keys {
            if let value = findValue(in: dictionary, keys: [key]), let int = int64Value(value) {
                return int
            }
        }
        return nil
    }

    func firstDictionary(in dictionary: [String: Any], keys: [String]) -> [String: Any]? {
        guard let value = findValue(in: dictionary, keys: keys) else { return nil }
        if let dictionary = value as? [String: Any] { return dictionary }
        if let array = value as? [[String: Any]] { return array.first }
        return nil
    }

    func findValue(in object: Any, keys: [String]) -> Any? {
        let lowered = Set(keys.map { $0.lowercased() })
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary where lowered.contains(key.lowercased()) {
                return value
            }
            for value in dictionary.values {
                if let found = findValue(in: value, keys: keys) { return found }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = findValue(in: value, keys: keys) { return found }
            }
        }
        return nil
    }

    func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int != 0 }
        if let string = value as? String {
            let lowered = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "yes", "1", "enable", "enabled", "on"].contains(lowered) { return true }
            if ["false", "no", "0", "disable", "disabled", "off"].contains(lowered) { return false }
        }
        return nil
    }

    func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    func int64Value(_ value: Any?) -> Int64? {
        if let int = value as? Int { return Int64(int) }
        if let int64 = value as? Int64 { return int64 }
        if let double = value as? Double { return Int64(double) }
        if let string = value as? String { return Int64(string.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    func stringValue(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let int as Int:
            return "\(int)"
        case let int64 as Int64:
            return "\(int64)"
        case let double as Double:
            return double.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(double))" : "\(double)"
        case let bool as Bool:
            return bool ? "已开启" : "未开启"
        default:
            return ""
        }
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var values: [T] = []
        for element in self {
            values.append(await transform(element))
        }
        return values
    }
}

private extension Error {
    var isSynologyCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        return localizedDescription.localizedCaseInsensitiveContains("cancel")
            || localizedDescription.contains("取消")
    }
}
