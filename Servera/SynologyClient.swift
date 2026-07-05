import Foundation

// MARK: - 群晖状态采集
// 添加/刷新 NAS 时使用的 DSM 状态客户端。它会探测 API 可用性、登录一次，
// 并独立采集系统、资源、存储、Docker 模块，避免某个 DSM 套件缺失时拖垮整个 NAS 面板。

struct SynologyConnectionRequest: Sendable {
    var host: String
    var port: Int
    var scheme: NASConnectionProtocol
    var account: String
    var password: String
    var verifySSLCertificate: Bool
}

struct SynologyConnectionOutcome: Sendable {
    var snapshot: SynologyStatusSnapshot
    var latencyMilliseconds: Int
}

// 控制面板模块按 raw value 存储，用于 Codable 兼容。
// 即使 UI 标题已经改成“终端机”，terminalSNMP 的原始值也要保留。
enum NASControlPanelModule: String, CaseIterable, Codable, Identifiable, Sendable {
    case users
    case externalAccess
    case network
    case terminalSNMP
    case infoCenter
    case updateRestore

    var id: String { rawValue }

    static var visibleCases: [NASControlPanelModule] {
        [.users, .externalAccess, .network, .terminalSNMP, .infoCenter]
    }

    var title: String {
        switch self {
        case .users: "用户与群组"
        case .externalAccess: "外部访问"
        case .network: "网络"
        case .terminalSNMP: "终端机"
        case .infoCenter: "信息中心"
        case .updateRestore: "系统版本"
        }
    }

    var systemImage: String {
        switch self {
        case .users: "person.2.fill"
        case .externalAccess: "globe.asia.australia.fill"
        case .network: "network"
        case .terminalSNMP: "terminal.fill"
        case .infoCenter: "info.circle.fill"
        case .updateRestore: "arrow.triangle.2.circlepath"
        }
    }

    var tintName: String {
        switch self {
        case .users: "leaf"
        case .externalAccess: "sky"
        case .network: "accent"
        case .terminalSNMP: "slate"
        case .infoCenter: "amber"
        case .updateRestore: "cyan"
        }
    }
}

struct NASControlPanelRow: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: String { title }
    var title: String
    var value: String
}

struct NASControlPanelModuleSnapshot: Codable, Equatable, Hashable, Sendable, Identifiable {
    var module: NASControlPanelModule
    var collectedAt: Date
    var available: Bool
    var summary: String
    var statusText: String
    var errorMessage: String
    var rows: [NASControlPanelRow]

    var id: String { module.rawValue }

    static func waiting(module: NASControlPanelModule) -> NASControlPanelModuleSnapshot {
        // 用于旧记录和还没采集过的模块。
        NASControlPanelModuleSnapshot(
            module: module,
            collectedAt: .distantPast,
            available: false,
            summary: "等待刷新",
            statusText: "等待刷新",
            errorMessage: "等待 DSM 刷新",
            rows: []
        )
    }
}

struct NASControlPanelSnapshot: Codable, Equatable, Sendable {
    var collectedAt: Date
    var modules: [NASControlPanelModuleSnapshot]

    static let empty = NASControlPanelSnapshot(
        collectedAt: .distantPast,
        modules: NASControlPanelModule.visibleCases.map { .waiting(module: $0) }
    )

    func module(_ module: NASControlPanelModule) -> NASControlPanelModuleSnapshot {
        // visibleCases 变化后，缺失模块应显示“等待刷新”，而不是解码崩溃。
        modules.first { $0.module == module } ?? .waiting(module: module)
    }
}

// DSM 概览快照。可用性标记按模块保存，存储/Docker 失败不会隐藏系统/资源指标。
struct SynologyStatusSnapshot: Codable, Equatable, Sendable {
    var collectedAt: Date
    var modelName: String
    var dsmVersion: String
    var systemName: String
    var uptimeSeconds: Int64
    var cpuPercent: Int
    var memoryPercent: Int
    var networkReceiveText: String
    var networkTransmitText: String
    var temperatureCelsius: Int?
    var volumes: [SynologyStorageVolume]
    var dockerInstalled: Bool
    var dockerContainerCount: Int
    var dockerRunningCount: Int
    var dockerContainers: [DockerContainerSummary]
    var systemAvailable: Bool
    var resourceAvailable: Bool
    var storageAvailable: Bool
    var dockerAvailable: Bool
    var systemErrorMessage: String
    var resourceErrorMessage: String
    var storageErrorMessage: String
    var dockerErrorMessage: String

    init(
        collectedAt: Date,
        modelName: String,
        dsmVersion: String,
        systemName: String,
        uptimeSeconds: Int64,
        cpuPercent: Int,
        memoryPercent: Int,
        networkReceiveText: String,
        networkTransmitText: String,
        temperatureCelsius: Int?,
        volumes: [SynologyStorageVolume],
        dockerInstalled: Bool,
        dockerContainerCount: Int,
        dockerRunningCount: Int,
        dockerContainers: [DockerContainerSummary],
        systemAvailable: Bool,
        resourceAvailable: Bool,
        storageAvailable: Bool,
        dockerAvailable: Bool,
        systemErrorMessage: String,
        resourceErrorMessage: String,
        storageErrorMessage: String,
        dockerErrorMessage: String
    ) {
        self.collectedAt = collectedAt
        self.modelName = modelName
        self.dsmVersion = dsmVersion
        self.systemName = systemName
        self.uptimeSeconds = uptimeSeconds
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.networkReceiveText = networkReceiveText
        self.networkTransmitText = networkTransmitText
        self.temperatureCelsius = temperatureCelsius
        self.volumes = volumes
        self.dockerInstalled = dockerInstalled
        self.dockerContainerCount = dockerContainerCount
        self.dockerRunningCount = dockerRunningCount
        self.dockerContainers = dockerContainers
        self.systemAvailable = systemAvailable
        self.resourceAvailable = resourceAvailable
        self.storageAvailable = storageAvailable
        self.dockerAvailable = dockerAvailable
        self.systemErrorMessage = systemErrorMessage
        self.resourceErrorMessage = resourceErrorMessage
        self.storageErrorMessage = storageErrorMessage
        self.dockerErrorMessage = dockerErrorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        collectedAt = try container.decodeIfPresent(Date.self, forKey: .collectedAt) ?? .distantPast
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName) ?? ""
        dsmVersion = try container.decodeIfPresent(String.self, forKey: .dsmVersion) ?? ""
        systemName = try container.decodeIfPresent(String.self, forKey: .systemName) ?? ""
        uptimeSeconds = try container.decodeIfPresent(Int64.self, forKey: .uptimeSeconds) ?? 0
        cpuPercent = try container.decodeIfPresent(Int.self, forKey: .cpuPercent) ?? 0
        memoryPercent = try container.decodeIfPresent(Int.self, forKey: .memoryPercent) ?? 0
        networkReceiveText = try container.decodeIfPresent(String.self, forKey: .networkReceiveText) ?? "-"
        networkTransmitText = try container.decodeIfPresent(String.self, forKey: .networkTransmitText) ?? "-"
        temperatureCelsius = try container.decodeIfPresent(Int.self, forKey: .temperatureCelsius)
        volumes = try container.decodeIfPresent([SynologyStorageVolume].self, forKey: .volumes) ?? []
        dockerInstalled = try container.decodeIfPresent(Bool.self, forKey: .dockerInstalled) ?? false
        dockerContainerCount = try container.decodeIfPresent(Int.self, forKey: .dockerContainerCount) ?? 0
        dockerRunningCount = try container.decodeIfPresent(Int.self, forKey: .dockerRunningCount) ?? 0
        dockerContainers = try container.decodeIfPresent([DockerContainerSummary].self, forKey: .dockerContainers) ?? []
        systemAvailable = try container.decodeIfPresent(Bool.self, forKey: .systemAvailable) ?? false
        resourceAvailable = try container.decodeIfPresent(Bool.self, forKey: .resourceAvailable) ?? false
        storageAvailable = try container.decodeIfPresent(Bool.self, forKey: .storageAvailable) ?? false
        dockerAvailable = try container.decodeIfPresent(Bool.self, forKey: .dockerAvailable) ?? false
        systemErrorMessage = try container.decodeIfPresent(String.self, forKey: .systemErrorMessage) ?? "等待 DSM 刷新"
        resourceErrorMessage = try container.decodeIfPresent(String.self, forKey: .resourceErrorMessage) ?? "等待 DSM 刷新"
        storageErrorMessage = try container.decodeIfPresent(String.self, forKey: .storageErrorMessage) ?? "等待 DSM 刷新"
        dockerErrorMessage = try container.decodeIfPresent(String.self, forKey: .dockerErrorMessage) ?? "等待 DSM 刷新"
    }

    static let empty = SynologyStatusSnapshot(
        collectedAt: .distantPast,
        modelName: "",
        dsmVersion: "",
        systemName: "",
        uptimeSeconds: 0,
        cpuPercent: 0,
        memoryPercent: 0,
        networkReceiveText: "-",
        networkTransmitText: "-",
        temperatureCelsius: nil,
        volumes: [],
        dockerInstalled: false,
        dockerContainerCount: 0,
        dockerRunningCount: 0,
        dockerContainers: [],
        systemAvailable: false,
        resourceAvailable: false,
        storageAvailable: false,
        dockerAvailable: false,
        systemErrorMessage: "等待 DSM 刷新",
        resourceErrorMessage: "等待 DSM 刷新",
        storageErrorMessage: "等待 DSM 刷新",
        dockerErrorMessage: "等待 DSM 刷新"
    )
}

struct SynologyStorageVolume: Codable, Equatable, Hashable, Sendable, Identifiable {
    var name: String
    var path: String
    var status: String
    var totalBytes: Int64
    var usedBytes: Int64
    var availableBytes: Int64

    var id: String { "\(name)-\(path)-\(totalBytes)-\(usedBytes)" }

    init(name: String, path: String = "", status: String, totalBytes: Int64, usedBytes: Int64, availableBytes: Int64) {
        self.name = name
        self.path = path
        self.status = status
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "存储空间"
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        totalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0
        usedBytes = try container.decodeIfPresent(Int64.self, forKey: .usedBytes) ?? 0
        availableBytes = try container.decodeIfPresent(Int64.self, forKey: .availableBytes) ?? 0
    }

    var usedPercent: Int {
        guard totalBytes > 0 else { return 0 }
        return min(100, max(0, Int((Double(usedBytes) / Double(totalBytes) * 100).rounded())))
    }

    var detailText: String {
        "\(ServerStatusParser.byteText(usedBytes)) / \(ServerStatusParser.byteText(totalBytes))"
    }
}

final class SynologyClient: NSObject, URLSessionDelegate, @unchecked Sendable {
    static let shared = SynologyClient()

    private override init() {}

    func validateAndCollect(request: SynologyConnectionRequest) async throws -> SynologyConnectionOutcome {
        let startedAt = Date()
        let session = makeSession(verifySSLCertificate: request.verifySSLCertificate)
        let apiInfo = try await fetchAPIInfo(request: request, session: session)
        let sid = try await login(request: request, session: session, apiInfo: apiInfo)

        do {
            var snapshot = SynologyStatusSnapshot.empty
            snapshot.collectedAt = .now

            do {
                let system = try await fetchSystem(request: request, session: session, apiInfo: apiInfo, sid: sid)
                snapshot.modelName = system.modelName
                snapshot.dsmVersion = system.dsmVersion
                snapshot.systemName = system.systemName
                snapshot.uptimeSeconds = system.uptimeSeconds
                snapshot.temperatureCelsius = system.temperatureCelsius
                snapshot.systemAvailable = true
                snapshot.systemErrorMessage = ""
            } catch {
                if error.isSynologyCancellation { throw error }
                snapshot.systemErrorMessage = error.localizedDescription
            }

            do {
                let resource = try await fetchResource(request: request, session: session, apiInfo: apiInfo, sid: sid)
                snapshot.cpuPercent = resource.cpuPercent
                snapshot.memoryPercent = resource.memoryPercent
                snapshot.networkReceiveText = resource.networkReceiveText
                snapshot.networkTransmitText = resource.networkTransmitText
                if snapshot.temperatureCelsius == nil {
                    snapshot.temperatureCelsius = resource.temperatureCelsius
                }
                snapshot.resourceAvailable = true
                snapshot.resourceErrorMessage = ""
            } catch {
                if error.isSynologyCancellation { throw error }
                snapshot.resourceErrorMessage = error.localizedDescription
            }

            do {
                let storage = try await fetchStorage(request: request, session: session, apiInfo: apiInfo, sid: sid)
                snapshot.volumes = storage.volumes
                if snapshot.temperatureCelsius == nil {
                    snapshot.temperatureCelsius = storage.maxDiskTemperatureCelsius
                }
                snapshot.storageAvailable = true
                snapshot.storageErrorMessage = storage.volumes.isEmpty ? "暂无存储卷数据" : ""
            } catch {
                if error.isSynologyCancellation { throw error }
                snapshot.storageErrorMessage = error.localizedDescription
            }

            do {
                let docker = try await fetchDocker(request: request, session: session, apiInfo: apiInfo, sid: sid)
                snapshot.dockerInstalled = docker.installed
                snapshot.dockerContainerCount = docker.total
                snapshot.dockerRunningCount = docker.running
                snapshot.dockerContainers = docker.containers
                snapshot.dockerAvailable = true
                snapshot.dockerErrorMessage = ""
            } catch {
                if error.isSynologyCancellation { throw error }
                snapshot.dockerErrorMessage = error.localizedDescription
            }

            await logout(request: request, session: session, apiInfo: apiInfo, sid: sid)
            return SynologyConnectionOutcome(
                snapshot: snapshot,
                latencyMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000)
            )
        } catch {
            await logout(request: request, session: session, apiInfo: apiInfo, sid: sid)
            throw error
        }
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}

#if DEBUG
extension SynologyClient {
    func testExtractVolumes(from data: [String: Any]) -> [SynologyStorageVolume] {
        extractVolumes(from: data)
    }

    func testParseDockerContainers(from dictionaries: [[String: Any]]) -> [DockerContainerSummary] {
        parseDockerContainers(from: dictionaries)
    }
}
#endif

private extension SynologyClient {
    struct APIInfo: Sendable {
        var path: String
        var minVersion: Int
        var maxVersion: Int
    }

    struct SystemResult {
        var modelName: String
        var dsmVersion: String
        var systemName: String
        var uptimeSeconds: Int64
        var temperatureCelsius: Int?
    }

    struct ResourceResult {
        var cpuPercent: Int
        var memoryPercent: Int
        var networkReceiveText: String
        var networkTransmitText: String
        var temperatureCelsius: Int?
    }

    struct StorageResult {
        var volumes: [SynologyStorageVolume]
        var maxDiskTemperatureCelsius: Int?
    }

    func makeSession(verifySSLCertificate: Bool) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 24
        if verifySSLCertificate {
            return URLSession(configuration: configuration)
        }
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func baseURL(for request: SynologyConnectionRequest) throws -> URLComponents {
        var host = request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = URLComponents(string: host), let parsedHost = parsed.host {
            host = parsedHost
        }
        guard !host.isEmpty else { throw SynologyClientError.invalidAddress }

        var components = URLComponents()
        components.scheme = request.scheme.rawValue
        components.host = host
        components.port = request.port
        return components
    }

    func fetchAPIInfo(request: SynologyConnectionRequest, session: URLSession) async throws -> [String: APIInfo] {
        do {
            return try await fetchAPIInfo(path: "/webapi/query.cgi", request: request, session: session)
        } catch {
            if error.isSynologyCancellation { throw error }
            return try await fetchAPIInfo(path: "/webapi/entry.cgi", request: request, session: session)
        }
    }

    func fetchAPIInfo(path: String, request: SynologyConnectionRequest, session: URLSession) async throws -> [String: APIInfo] {
        let json = try await requestJSON(
            path: path,
            request: request,
            session: session,
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
            guard let dict = value as? [String: Any] else { continue }
            result[name] = APIInfo(
                path: normalizedAPIPath(stringValue(dict["path"])),
                minVersion: intValue(dict["minVersion"]) ?? 1,
                maxVersion: intValue(dict["maxVersion"]) ?? 1
            )
        }
        return result
    }

    func login(request: SynologyConnectionRequest, session: URLSession, apiInfo: [String: APIInfo]) async throws -> String {
        guard let auth = apiInfo["SYNO.API.Auth"] else {
            throw SynologyClientError.apiUnavailable("DSM 登录接口不可用。")
        }
        let version = min(max(auth.maxVersion, auth.minVersion), 6)
        let json = try await requestJSON(
            path: auth.path,
            request: request,
            session: session,
            parameters: [
                "api": "SYNO.API.Auth",
                "version": "\(version)",
                "method": "login",
                "account": request.account,
                "passwd": request.password,
                "session": "Servera",
                "format": "sid"
            ],
            requiresSuccess: true,
            errorContext: .auth
        )
        guard let data = json["data"] as? [String: Any],
              let sid = data["sid"] as? String,
              !sid.isEmpty else {
            throw SynologyClientError.authenticationFailed("DSM 登录成功但没有返回会话。")
        }
        return sid
    }

    func logout(request: SynologyConnectionRequest, session: URLSession, apiInfo: [String: APIInfo], sid: String) async {
        guard let auth = apiInfo["SYNO.API.Auth"] else { return }
        _ = try? await requestJSON(
            path: auth.path,
            request: request,
            session: session,
            parameters: [
                "api": "SYNO.API.Auth",
                "version": "\(min(max(auth.maxVersion, auth.minVersion), 6))",
                "method": "logout",
                "session": "Servera",
                "_sid": sid
            ],
            requiresSuccess: false
        )
    }

    func fetchSystem(request: SynologyConnectionRequest, session: URLSession, apiInfo: [String: APIInfo], sid: String) async throws -> SystemResult {
        let json = try await callFirstAvailable(
            apiNames: ["SYNO.Core.System", "SYNO.Core.System.Info"],
            method: "info",
            request: request,
            session: session,
            apiInfo: apiInfo,
            sid: sid
        )
        let data = (json["data"] as? [String: Any]) ?? json
        return SystemResult(
            modelName: firstString(in: data, keys: ["model_name", "model", "sys_model_name", "product_model"]) ?? "",
            dsmVersion: firstString(in: data, keys: ["firmware_ver", "version", "dsm_version", "majorversion"]) ?? "",
            systemName: firstString(in: data, keys: ["server_name", "hostname", "system_name", "device_name"]) ?? "",
            uptimeSeconds: firstInt64(in: data, keys: ["up_time", "uptime", "uptime_seconds"]) ?? 0,
            temperatureCelsius: extractSystemTemperature(from: data)
        )
    }

    func fetchResource(request: SynologyConnectionRequest, session: URLSession, apiInfo: [String: APIInfo], sid: String) async throws -> ResourceResult {
        let json = try await callFirstAvailable(
            apiNames: ["SYNO.Core.System.Utilization", "SYNO.Core.System.Process"],
            method: "get",
            request: request,
            session: session,
            apiInfo: apiInfo,
            sid: sid
        )
        let data = (json["data"] as? [String: Any]) ?? json
        let cpu = extractCPUPercent(from: data)
        let memory = extractMemoryPercent(from: data)
        let network = extractNetworkText(from: data)
        return ResourceResult(
            cpuPercent: cpu,
            memoryPercent: memory,
            networkReceiveText: network.receive,
            networkTransmitText: network.transmit,
            temperatureCelsius: extractSystemTemperature(from: data)
        )
    }

    func fetchStorage(request: SynologyConnectionRequest, session: URLSession, apiInfo: [String: APIInfo], sid: String) async throws -> StorageResult {
        // 不同 DSM 版本的存储结构差异很大。先尝试旧聚合接口，
        // 因为它可能同时包含卷和硬盘温度，再降级到较新的 Core.Storage 接口。
        let attempts: [(api: String, method: String)] = [
            ("SYNO.Storage.CGI.Storage", "load_info"),
            ("SYNO.Core.Storage.Volume", "list"),
            ("SYNO.Core.Storage.StoragePool", "list")
        ]
        var lastError: Error?
        for attempt in attempts {
            do {
                let json = try await callFirstAvailable(
                    apiNames: [attempt.api],
                    method: attempt.method,
                    request: request,
                    session: session,
                    apiInfo: apiInfo,
                    sid: sid
                )
                let data = (json["data"] as? [String: Any]) ?? json
                let volumes = extractVolumes(from: data)
                let maxDiskTemperature = extractMaxDiskTemperature(from: data)
                if !volumes.isEmpty {
                    return StorageResult(
                        volumes: volumes,
                        maxDiskTemperatureCelsius: maxDiskTemperature
                    )
                }
                lastError = SynologyClientError.apiUnavailable("暂无存储卷数据。")
            } catch {
                lastError = error
            }
        }
        if let synologyError = lastError as? SynologyClientError {
            switch synologyError {
            case .permissionDenied, .authenticationFailed, .sessionExpired, .connectionFailed, .invalidAddress, .certificateInvalid, .twoFactorRequired:
                throw synologyError
            case .apiUnavailable:
                break
            }
        }
        throw SynologyClientError.apiUnavailable("DSM 暂未返回存储空间信息，请下拉刷新后查看。")
    }

    func fetchDocker(request: SynologyConnectionRequest, session: URLSession, apiInfo: [String: APIInfo], sid: String) async throws -> (installed: Bool, total: Int, running: Int, containers: [DockerContainerSummary]) {
        // NAS Docker 是可选套件，并且后续改名为 Container Manager。
        // API 缺失在 UI 层视为“Docker 未安装/不可用”，但最后一次尝试的权限/会话错误要保留。
        let attempts: [(api: String, method: String, parameters: [String: String])] = [
            ("SYNO.Docker.Container", "list", ["limit": "-1", "offset": "0", "type": "all"]),
            ("SYNO.ContainerManager.Container", "list", ["limit": "-1", "offset": "0", "type": "all"]),
            ("SYNO.Docker.Container", "get", [:])
        ]
        var lastError: Error?
        for attempt in attempts {
            do {
                let json = try await callFirstAvailable(
                    apiNames: [attempt.api],
                    method: attempt.method,
                    request: request,
                    session: session,
                    apiInfo: apiInfo,
                    sid: sid,
                    extraParameters: attempt.parameters
                )
                let data = (json["data"] as? [String: Any]) ?? json
                var containerDictionaries = extractContainerDictionaries(from: data)
                let resourceDictionaries = (try? await fetchDockerResourceDictionaries(
                    request: request,
                    session: session,
                    apiInfo: apiInfo,
                    sid: sid
                )) ?? []
                mergeDockerResources(resourceDictionaries, into: &containerDictionaries)
                let containers = parseDockerContainers(from: containerDictionaries)
                return (
                    installed: true,
                    total: containers.count,
                    running: containers.filter(\.isRunning).count,
                    containers: containers
                )
            } catch {
                lastError = error
            }
        }
        throw lastError ?? SynologyClientError.apiUnavailable("未检测到 Container Manager / Docker。")
    }

    func fetchDockerResourceDictionaries(request: SynologyConnectionRequest, session: URLSession, apiInfo: [String: APIInfo], sid: String) async throws -> [[String: Any]] {
        let resourceInfo = apiInfo["SYNO.Docker.Container.Resource"] ?? APIInfo(path: "/webapi/entry.cgi", minVersion: 1, maxVersion: 1)
        let json = try await requestJSON(
            path: resourceInfo.path,
            request: request,
            session: session,
            parameters: [
                "api": "SYNO.Docker.Container.Resource",
                "version": "\(resourceInfo.maxVersion)",
                "method": "get",
                "_sid": sid
            ],
            requiresSuccess: true,
            errorContext: .module("SYNO.Docker.Container.Resource")
        )
        let data = (json["data"] as? [String: Any]) ?? json
        if let resources = findValue(in: data, keys: ["resources"]) as? [[String: Any]] {
            return resources
        }
        return []
    }

    func callFirstAvailable(
        apiNames: [String],
        method: String,
        request: SynologyConnectionRequest,
        session: URLSession,
        apiInfo: [String: APIInfo],
        sid: String,
        extraParameters: [String: String] = [:]
    ) async throws -> [String: Any] {
        var lastError: Error?
        for apiName in apiNames {
            guard let info = apiInfo[apiName] else {
                lastError = SynologyClientError.apiUnavailable("\(apiName) 不可用。")
                continue
            }
            do {
                var parameters = [
                    "api": apiName,
                    "version": "\(info.maxVersion)",
                    "method": method,
                    "_sid": sid
                ]
                parameters.merge(extraParameters) { _, new in new }
                return try await requestJSON(
                    path: info.path,
                    request: request,
                    session: session,
                    parameters: parameters,
                    requiresSuccess: true,
                    errorContext: .module(apiName)
                )
            } catch {
                lastError = error
            }
        }
        throw lastError ?? SynologyClientError.apiUnavailable("DSM 接口不可用。")
    }

    func requestJSON(
        path: String,
        request: SynologyConnectionRequest,
        session: URLSession,
        parameters: [String: String],
        requiresSuccess: Bool,
        errorContext: DSMErrorContext = .module("DSM")
    ) async throws -> [String: Any] {
        var components = try baseURL(for: request)
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw SynologyClientError.invalidAddress }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SynologyClientError.connectionFailed("DSM 没有返回有效响应。")
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw SynologyClientError.connectionFailed("DSM HTTP 状态码 \(httpResponse.statusCode)。")
            }
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
            if error.code == .cancelled {
                throw CancellationError()
            }
            throw mapURLError(error, verifySSLCertificate: request.verifySSLCertificate)
        } catch {
            if error.isSynologyCancellation {
                throw error
            }
            throw SynologyClientError.connectionFailed(error.localizedDescription)
        }
    }

    enum DSMErrorContext {
        case auth
        case module(String)
    }

    func normalizedAPIPath(_ rawPath: String?) -> String {
        let trimmed = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "/webapi/entry.cgi" }
        if trimmed.hasPrefix("/webapi/") { return trimmed }
        if trimmed.hasPrefix("/") { return "/webapi\(trimmed)" }
        return "/webapi/\(trimmed)"
    }

    func mapDSMError(_ json: [String: Any], context: DSMErrorContext) -> SynologyClientError {
        let code = ((json["error"] as? [String: Any])?["code"] as? Int) ?? 0
        switch context {
        case .auth:
            switch code {
            case 400, 401, 404:
                return .authenticationFailed("DSM 账号或密码错误。")
            case 402:
                return .permissionDenied("DSM 账号权限不足。")
            case 403:
                return .twoFactorRequired
            case 105, 106, 107, 119:
                return .sessionExpired
            default:
                return .apiUnavailable(code == 0 ? "DSM 登录失败。" : "DSM 登录失败，错误码 \(code)。")
            }
        case .module(let apiName):
            switch code {
            case 105, 106, 107, 119:
                return .sessionExpired
            case 402, 407:
                return .permissionDenied("\(apiName) 权限不足。")
            case 114 where apiName.contains("Docker") || apiName.contains("Container"):
                return .apiUnavailable("Container Manager / Docker 接口暂不可用，可能是 DSM 版本或接口参数不兼容。")
            default:
                return .apiUnavailable(code == 0 ? "\(apiName) 调用失败。" : "\(apiName) 调用失败，错误码 \(code)。")
            }
        }
    }

    func mapURLError(_ error: URLError, verifySSLCertificate: Bool) -> SynologyClientError {
        switch error.code {
        case .cannotFindHost, .dnsLookupFailed:
            return .connectionFailed("找不到 DSM 地址。本阶段建议使用 IP、域名或反向代理地址。")
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            return .connectionFailed("无法连接 DSM，请检查地址、端口和网络。")
        case .timedOut:
            return .connectionFailed("连接 DSM 超时，请检查端口是否开放。")
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .secureConnectionFailed:
            return .certificateInvalid("DSM SSL 证书无效；如果是自签名证书，可以关闭 SSL 校验后重试。")
        default:
            return .connectionFailed(error.localizedDescription)
        }
    }
}

private extension SynologyClient {
    func extractSystemTemperature(from data: [String: Any]) -> Int? {
        firstInt(
            in: data,
            keys: [
                "sys_temp",
                "system_temp",
                "sys_temperature",
                "system_temperature",
                "temperature",
                "thermal",
                "cpu_temperature"
            ]
        )
    }

    func extractMaxDiskTemperature(from object: Any) -> Int? {
        var temperatures: [Int] = []
        collectDiskTemperatures(from: object, into: &temperatures)
        return temperatures.max()
    }

    func collectDiskTemperatures(from object: Any, into temperatures: inout [Int]) {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                if key.caseInsensitiveCompare("temp") == .orderedSame,
                   let temperature = intValue(value),
                   (1...120).contains(temperature) {
                    temperatures.append(temperature)
                }
                collectDiskTemperatures(from: value, into: &temperatures)
            }
        } else if let array = object as? [Any] {
            for value in array {
                collectDiskTemperatures(from: value, into: &temperatures)
            }
        }
    }

    func extractCPUPercent(from data: [String: Any]) -> Int {
        if let cpu = firstDictionary(in: data, keys: ["cpu"]) {
            let user = firstDouble(in: cpu, keys: ["user_load", "user", "cpu_user_load"]) ?? 0
            let system = firstDouble(in: cpu, keys: ["system_load", "system", "cpu_system_load"]) ?? 0
            let other = firstDouble(in: cpu, keys: ["other_load", "nice_load", "iowait_load"]) ?? 0
            let sum = user + system + other
            if sum > 0 { return clippedPercent(sum) }
            if let usage = firstDouble(in: cpu, keys: ["usage", "total_load", "cpu_usage"]) {
                return clippedPercent(usage)
            }
        }
        return clippedPercent(firstDouble(in: data, keys: ["cpu_usage", "cpu_user_load", "total_load"]) ?? 0)
    }

    func extractMemoryPercent(from data: [String: Any]) -> Int {
        if let memory = firstDictionary(in: data, keys: ["memory", "mem"]) {
            if let usage = firstDouble(in: memory, keys: ["real_usage", "usage", "memory_usage", "used_percent"]) {
                return clippedPercent(usage)
            }
            let total = firstDouble(in: memory, keys: ["total", "mem_total", "total_bytes"]) ?? 0
            let used = firstDouble(in: memory, keys: ["used", "mem_used", "used_bytes"]) ?? 0
            if total > 0, used >= 0 {
                return clippedPercent(used / total * 100)
            }
        }
        return clippedPercent(firstDouble(in: data, keys: ["memory_usage", "real_usage", "mem_usage"]) ?? 0)
    }

    func extractNetworkText(from data: [String: Any]) -> (receive: String, transmit: String) {
        let networkObject = findValue(in: data, keys: ["network", "networks", "nics"])
        var receive: Double = 0
        var transmit: Double = 0

        if let dict = networkObject as? [String: Any] {
            receive = firstDouble(in: dict, keys: ["rx", "rx_rate", "recv", "receive", "download", "download_rate"]) ?? 0
            transmit = firstDouble(in: dict, keys: ["tx", "tx_rate", "sent", "transmit", "upload", "upload_rate"]) ?? 0
        } else if let list = networkObject as? [[String: Any]] {
            for item in list {
                receive += firstDouble(in: item, keys: ["rx", "rx_rate", "recv", "receive", "download", "download_rate"]) ?? 0
                transmit += firstDouble(in: item, keys: ["tx", "tx_rate", "sent", "transmit", "upload", "upload_rate"]) ?? 0
            }
        }

        return (
            ServerStatusParser.rateText("\(Int64(receive))"),
            ServerStatusParser.rateText("\(Int64(transmit))")
        )
    }

    func extractVolumes(from data: [String: Any]) -> [SynologyStorageVolume] {
        // DSM 返回挂载路径时优先使用真实卷，因为它们可以进入 File Station 浏览。
        // 如果 DSM 只返回存储池，就保留无路径行，让用户仍能看到真实容量，而不是空存储卡。
        let volumeCandidates = [
            findValue(in: data, keys: ["volumes"]),
            findValue(in: data, keys: ["volume"])
        ]
        let storagePoolCandidates = [
            findValue(in: data, keys: ["storage_pools"]),
            findValue(in: data, keys: ["storagePools"]),
            findValue(in: data, keys: ["pools"])
        ]

        let volumeDictionaries = dictionaries(from: volumeCandidates)
        let volumes = parseStorageVolumes(from: volumeDictionaries, allowPathlessDisplay: true)
        if !volumes.isEmpty {
            let browsableVolumes = volumes.filter { !$0.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return browsableVolumes.isEmpty ? volumes : browsableVolumes
        }

        let storagePoolDictionaries = dictionaries(from: storagePoolCandidates)
        return parseStorageVolumes(from: storagePoolDictionaries, allowPathlessDisplay: true)
    }

    func dictionaries(from values: [Any?]) -> [[String: Any]] {
        values.flatMap { value -> [[String: Any]] in
            if let list = value as? [[String: Any]] { return list }
            if let dict = value as? [String: Any] {
                return dict.values.compactMap { $0 as? [String: Any] }
            }
            return []
        }
    }

    func parseStorageVolumes(from dictionaries: [[String: Any]], allowPathlessDisplay: Bool) -> [SynologyStorageVolume] {
        var seenPaths = Set<String>()
        var seenPathlessNames = Set<String>()
        return dictionaries.compactMap { item in
            let name = firstString(in: item, keys: ["display_name", "name", "id", "volume_path"]) ?? "存储空间"
            let total = firstByteCount(in: item, keys: ["total", "total_size", "size_total", "capacity"])
            let used = firstByteCount(in: item, keys: ["used", "used_size", "size_used"])
            let available = firstByteCount(in: item, keys: ["free", "available", "size_free"])
            let resolvedUsed = used > 0 ? used : max(total - available, 0)
            guard total > 0 else { return nil }
            let path = firstString(in: item, keys: ["volume_path", "path", "mount_point", "mountPath"]) ?? normalizedVolumePath(from: name)
            if !path.isEmpty {
                guard seenPaths.insert(path).inserted else { return nil }
            } else {
                // 存储池可能有容量但没有挂载路径。这类数据只用于展示状态；
                // 除非名称明确编码了卷号，否则不要凭空造一个 /volumeX 路径。
                guard allowPathlessDisplay else { return nil }
                let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalizedName.isEmpty, seenPathlessNames.insert(normalizedName).inserted else { return nil }
            }
            return SynologyStorageVolume(
                name: name,
                path: path,
                status: firstString(in: item, keys: ["status", "health", "desc"]) ?? "",
                totalBytes: total,
                usedBytes: resolvedUsed,
                availableBytes: available > 0 ? available : max(total - resolvedUsed, 0)
            )
        }
    }

    func normalizedVolumePath(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("/") { return trimmed }
        let compact = trimmed.lowercased().replacingOccurrences(of: " ", with: "")
        if compact.hasPrefix("volume") { return "/\(compact)" }
        return ""
    }

    func extractContainerDictionaries(from data: [String: Any]) -> [[String: Any]] {
        let candidates = [
            findValue(in: data, keys: ["containers"]),
            findValue(in: data, keys: ["container"]),
            findValue(in: data, keys: ["items"]),
            findValue(in: data, keys: ["data"])
        ]

        for value in candidates {
            if let list = value as? [[String: Any]] { return list }
            if let dict = value as? [String: Any] {
                let nested = dict.values.compactMap { $0 as? [String: Any] }
                if !nested.isEmpty { return nested }
            }
        }
        return []
    }

    func dictionaryIsRunning(_ dictionary: [String: Any]) -> Bool {
        let value = firstString(in: dictionary, keys: ["status", "state", "running"])?.lowercased() ?? ""
        return value.contains("running") || value == "true" || value == "1"
    }

    func parseDockerContainers(from dictionaries: [[String: Any]]) -> [DockerContainerSummary] {
        dictionaries.map { dictionary in
            let id = firstString(in: dictionary, keys: ["id", "container_id", "containerId", "uuid"]) ?? ""
            let name = firstString(in: dictionary, keys: ["name", "container_name", "containerName", "display_name"]) ?? (id.isEmpty ? "container" : String(id.prefix(12)))
            let image = firstString(in: dictionary, keys: ["image", "image_name", "repository", "repo", "config_image"]) ?? ""
            let rawState = firstString(in: dictionary, keys: ["state", "status", "running"]) ?? ""
            let rawStatus = firstString(in: dictionary, keys: ["status_text", "status", "up_time", "uptime"]) ?? rawState
            let state = normalizedDockerState(state: rawState, status: rawStatus)
            let status = rawStatus.isEmpty ? state : rawStatus
            let cpuPercent = firstDouble(in: dictionary, keys: ["cpu_percent", "cpuPercent", "cpu", "cpu_usage", "cpu_usage_percent"]) ?? 0
            let memoryPercent = firstDouble(in: dictionary, keys: ["memory_percent", "memoryPercent", "mem_percent", "memory_usage_percent"]) ?? 0
            let memoryUsageText = firstString(in: dictionary, keys: ["memory_usage", "memoryUsage", "mem_usage", "memUsage"]) ?? memoryText(from: firstByteCount(in: dictionary, keys: ["memory_used", "memoryUsed", "mem_used", "memory"]))
            let memoryLimitText = firstString(in: dictionary, keys: ["memory_limit", "memoryLimit", "mem_limit", "memLimit"]) ?? memoryText(from: firstByteCount(in: dictionary, keys: ["memory_limit_bytes", "memoryLimitBytes", "mem_limit_bytes"]))
            let uptimeText = firstString(in: dictionary, keys: ["uptime", "up_time", "running_time", "status_text"]) ?? ""
            return DockerContainerSummary(
                containerID: id,
                name: name,
                image: image,
                state: state,
                status: status,
                cpuPercent: cpuPercent,
                memoryUsageText: memoryUsageText,
                memoryLimitText: memoryLimitText,
                memoryPercent: memoryPercent,
                uptimeText: uptimeText
            )
        }
    }

    func normalizedDockerState(state: String, status: String) -> String {
        let candidates = [state, status].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if candidates.contains(where: { $0 == "true" || $0 == "1" || $0 == "running" || $0.hasPrefix("up ") || $0.contains("running") }) {
            return "running"
        }
        if candidates.contains(where: { $0 == "false" || $0 == "0" || $0 == "stopped" || $0.contains("exited") || $0.contains("stopped") || $0.contains("dead") }) {
            return "stopped"
        }
        if candidates.contains(where: { $0.contains("paused") }) {
            return "paused"
        }
        if candidates.contains(where: { $0.contains("restarting") }) {
            return "restarting"
        }
        return state.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func memoryText(from bytes: Int64) -> String {
        bytes > 0 ? ServerStatusParser.byteText(bytes) : "-"
    }

    func mergeDockerResources(_ resources: [[String: Any]], into containers: inout [[String: Any]]) {
        guard !resources.isEmpty, !containers.isEmpty else { return }
        var resourcesByName: [String: [String: Any]] = [:]
        for resource in resources {
            guard let name = firstString(in: resource, keys: ["name", "container_name", "containerName"]) else { continue }
            resourcesByName[normalizedContainerName(name)] = resource
        }
        for index in containers.indices {
            guard let name = firstString(in: containers[index], keys: ["name", "container_name", "containerName", "display_name"]) else { continue }
            guard let resource = resourcesByName[normalizedContainerName(name)] else { continue }
            for (key, value) in resource {
                containers[index][key] = value
            }
        }
    }

    func normalizedContainerName(_ name: String) -> String {
        name.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
    }
}

private extension SynologyClient {
    func firstDictionary(in dictionary: [String: Any], keys: [String]) -> [String: Any]? {
        findValue(in: dictionary, keys: keys) as? [String: Any]
    }

    func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
        guard let value = findValue(in: dictionary, keys: keys) else { return nil }
        return stringValue(value)
    }

    func firstInt(in dictionary: [String: Any], keys: [String]) -> Int? {
        guard let value = findValue(in: dictionary, keys: keys) else { return nil }
        return intValue(value)
    }

    func firstInt64(in dictionary: [String: Any], keys: [String]) -> Int64? {
        guard let value = findValue(in: dictionary, keys: keys) else { return nil }
        return int64Value(value)
    }

    func firstDouble(in dictionary: [String: Any], keys: [String]) -> Double? {
        guard let value = findValue(in: dictionary, keys: keys) else { return nil }
        return doubleValue(value)
    }

    func firstByteCount(in dictionary: [String: Any], keys: [String]) -> Int64 {
        guard let value = findValue(in: dictionary, keys: keys) else { return 0 }
        if let number = int64Value(value) { return number }
        if let string = stringValue(value) {
            return SynologyClient.byteCount(from: string)
        }
        return 0
    }

    func findValue(in object: Any, keys: [String]) -> Any? {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary where keys.contains(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) {
                return value
            }
            for value in dictionary.values {
                if let found = findValue(in: value, keys: keys) {
                    return found
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = findValue(in: value, keys: keys) {
                    return found
                }
            }
        }
        return nil
    }

    func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String, let double = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return Int(double)
        }
        return nil
    }

    func int64Value(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String, let double = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return Int64(double)
        }
        return nil
    }

    func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")) }
        return nil
    }

    func clippedPercent(_ value: Double) -> Int {
        min(100, max(0, Int(value.rounded())))
    }

    static func byteCount(from text: String) -> Int64 {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        if let raw = Int64(trimmed) { return raw }

        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*([KMGTPE]?i?B?|[KMGTPE])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let valueRange = Range(match.range(at: 1), in: trimmed),
              let unitRange = Range(match.range(at: 2), in: trimmed),
              let value = Double(trimmed[valueRange]) else {
            return 0
        }
        let unit = trimmed[unitRange].uppercased()
        let power: Int
        if unit.hasPrefix("P") { power = 5 }
        else if unit.hasPrefix("T") { power = 4 }
        else if unit.hasPrefix("G") { power = 3 }
        else if unit.hasPrefix("M") { power = 2 }
        else if unit.hasPrefix("K") { power = 1 }
        else { power = 0 }
        return Int64(value * pow(1024, Double(power)))
    }
}

enum SynologyClientError: LocalizedError, Equatable {
    case invalidAddress
    case connectionFailed(String)
    case certificateInvalid(String)
    case authenticationFailed(String)
    case twoFactorRequired
    case permissionDenied(String)
    case sessionExpired
    case apiUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "DSM 地址无效。"
        case .connectionFailed(let message):
            return message
        case .certificateInvalid(let message):
            return message
        case .authenticationFailed(let message):
            return message
        case .twoFactorRequired:
            return "DSM 账号需要两步验证，本阶段暂不支持 2FA 登录。"
        case .permissionDenied(let message):
            return message
        case .sessionExpired:
            return "DSM 会话已失效，请重新验证账号。"
        case .apiUnavailable(let message):
            return message
        }
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
