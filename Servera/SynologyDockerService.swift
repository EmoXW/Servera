import Foundation

// MARK: - 群晖 Container Manager API
// NAS Docker 操作优先走 DSM API。SSH 日志兜底留在 NASView，
// 让本 service 专注处理 Container Manager 的会话和 API 行为。

struct SynologyDockerConnection: Sendable {
    var host: String
    var port: Int
    var scheme: NASConnectionProtocol
    var account: String
    var password: String
    var verifySSLCertificate: Bool
}

enum NASDockerLogSource: String, Sendable {
    case dsm = "DSM 日志"
    case ssh = "SSH 日志"
}

struct NASDockerLogResult: Sendable {
    var text: String
    var source: NASDockerLogSource
}

enum NASDockerAction: String, CaseIterable, Identifiable, Sendable {
    case start
    case stop
    case restart
    case delete
    case refresh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: "启动"
        case .stop: "停止"
        case .restart: "重启"
        case .delete: "删除"
        case .refresh: "刷新"
        }
    }

    var systemImage: String {
        switch self {
        case .start: "play.fill"
        case .stop: "stop.fill"
        case .restart: "arrow.clockwise"
        case .delete: "trash"
        case .refresh: "arrow.clockwise.circle"
        }
    }

    var isDestructive: Bool {
        self == .stop || self == .restart || self == .delete
    }

    var confirmationTitle: String {
        switch self {
        case .start: "启动容器？"
        case .stop: "停止容器？"
        case .restart: "重启容器？"
        case .delete: "删除容器？"
        case .refresh: "刷新容器？"
        }
    }

    func confirmationMessage(containerName: String) -> String {
        switch self {
        case .start:
            return "将在 NAS 上启动容器 \(containerName)。"
        case .stop:
            return "将在 NAS 上停止容器 \(containerName)，正在运行的服务会中断。"
        case .restart:
            return "将在 NAS 上重启容器 \(containerName)，正在运行的服务会短暂中断。"
        case .delete:
            return "将在 NAS 上删除容器 \(containerName)。此操作会真实影响 Container Manager 中的容器。"
        case .refresh:
            return "将重新读取容器 \(containerName) 的最新状态。"
        }
    }
}

/// NAS Container Manager 操作使用的轻量 DSM 客户端。
///
/// 群晖在不同 DSM / Container Manager 版本中同时出现过 SYNO.Docker.* 和
/// SYNO.ContainerManager.* 两套命名，所以这里始终探测并尝试两类 API，
/// 不假设存在一个稳定名称。
final class SynologyDockerService: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let connection: SynologyDockerConnection
    private var session: URLSession!
    private var apiInfo: [String: APIInfo] = [:]
    private var sid: String?

    init(connection: SynologyDockerConnection) {
        self.connection = connection
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 60
        super.init()
        if connection.verifySSLCertificate {
            self.session = URLSession(configuration: configuration)
        } else {
            self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        }
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
                "session": "ServeraDocker",
                "_sid": sid
            ],
            requiresSuccess: false
        )
        self.sid = nil
    }

    func refreshContainers() async throws -> [DockerContainerSummary] {
        let json = try await callContainerAPI(method: "list", extraParameters: [
            "limit": "-1",
            "offset": "0",
            "type": "all"
        ])
        let data = (json["data"] as? [String: Any]) ?? json
        var containerDictionaries = extractContainerDictionaries(from: data)
        // 很多 DSM 构建把容器列表和实时资源占用放在不同 API。
        // 这里按名称/id 合并，让 UI 能显示 CPU/内存，而不要求列表接口自带资源字段。
        let resourceDictionaries = (try? await fetchResourceDictionaries()) ?? []
        mergeDockerResources(resourceDictionaries, into: &containerDictionaries)
        return parseDockerContainers(from: containerDictionaries)
    }

    func start(container: DockerContainerSummary) async throws {
        try await performContainerAction(container: container, methods: ["start"])
    }

    func stop(container: DockerContainerSummary) async throws {
        try await performContainerAction(container: container, methods: ["stop"])
    }

    func restart(container: DockerContainerSummary) async throws {
        try await performContainerAction(container: container, methods: ["restart"])
    }

    func delete(container: DockerContainerSummary) async throws {
        try await performContainerAction(container: container, methods: ["delete", "remove"])
    }

    func fetchLogs(container: DockerContainerSummary, lines: Int) async throws -> NASDockerLogResult {
        let methods = ["get", "list", "get_log", "log"]
        let identifiers = logIdentifierParameterSets(for: container)
        var lastError: Error?
        // 不同 DSM 版本对方法名、容器名是否需要前导 / 都不一致。
        // 候选矩阵集中放在这里，调用方只决定何时降级到 SSH。
        for method in methods {
            for identifier in identifiers {
                do {
                    var parameters = identifier
                    parameters["offset"] = "0"
                    parameters["limit"] = "\(lines)"
                    parameters["line"] = "\(lines)"
                    parameters["lines"] = "\(lines)"
                    let json = try await callAPI(
                        apiNames: ["SYNO.Docker.Container.Log", "SYNO.ContainerManager.Container.Log"],
                        method: method,
                        extraParameters: parameters
                    )
                    if let text = parseLogText(from: json) {
                        return NASDockerLogResult(text: text, source: .dsm)
                    }
                    lastError = SynologyClientError.apiUnavailable("DSM 未返回容器日志。")
                } catch {
                    lastError = error
                }
            }
        }
        throw lastError ?? SynologyClientError.apiUnavailable("当前 DSM 接口不支持读取容器日志。")
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}

private extension SynologyDockerService {
    struct APIInfo: Sendable {
        var path: String
        var minVersion: Int
        var maxVersion: Int
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
                "query": "SYNO.API.Auth,SYNO.Docker.Container,SYNO.ContainerManager.Container,SYNO.Docker.Container.Resource,SYNO.Docker.Container.Log,SYNO.ContainerManager.Container.Log"
            ],
            requiresSuccess: true
        )
        guard let data = json["data"] as? [String: Any] else {
            throw SynologyClientError.apiUnavailable("DSM Docker API 探测失败。")
        }
        var result: [String: APIInfo] = [:]
        for (name, value) in data {
            guard let dictionary = value as? [String: Any] else { continue }
            result[name] = APIInfo(
                path: normalizedAPIPath(stringValue(dictionary["path"])),
                minVersion: intValue(dictionary["minVersion"]) ?? 1,
                maxVersion: intValue(dictionary["maxVersion"]) ?? 1
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
                "session": "ServeraDocker",
                "format": "sid"
            ],
            requiresSuccess: true,
            errorContext: .auth
        )
        guard let data = json["data"] as? [String: Any],
              let sid = data["sid"] as? String,
              !sid.isEmpty else {
            throw SynologyClientError.authenticationFailed("DSM 登录成功但没有返回 Docker 会话。")
        }
        return sid
    }

    func callContainerAPI(method: String, extraParameters: [String: String]) async throws -> [String: Any] {
        try await callAPI(
            apiNames: ["SYNO.Docker.Container", "SYNO.ContainerManager.Container"],
            method: method,
            extraParameters: extraParameters
        )
    }

    func callAPI(apiNames: [String], method: String, extraParameters: [String: String]) async throws -> [String: Any] {
        do {
            return try await callAPIWithoutRetry(apiNames: apiNames, method: method, extraParameters: extraParameters)
        } catch SynologyClientError.sessionExpired {
        // DSM sid 会话较短；静默重登一次可以避免用户长时间停留 NAS 详情页后，
        // 手动容器操作直接失败。
            sid = try await login()
            return try await callAPIWithoutRetry(apiNames: apiNames, method: method, extraParameters: extraParameters)
        }
    }

    func callAPIWithoutRetry(apiNames: [String], method: String, extraParameters: [String: String]) async throws -> [String: Any] {
        guard let sid else { throw SynologyClientError.sessionExpired }
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
                    parameters: parameters,
                    requiresSuccess: true,
                    errorContext: .module(apiName)
                )
            } catch {
                lastError = error
            }
        }
        throw lastError ?? SynologyClientError.apiUnavailable("当前 DSM 接口不支持此 Docker 操作或账号权限不足。")
    }

    func performContainerAction(container: DockerContainerSummary, methods: [String]) async throws {
        let identifiers = actionIdentifierParameterSets(for: container)
        var lastError: Error?
        for method in methods {
            for identifier in identifiers {
                do {
                    _ = try await callContainerAPI(method: method, extraParameters: identifier)
                    return
                } catch {
                    lastError = error
                }
            }
        }
        throw lastError ?? SynologyClientError.apiUnavailable("当前 DSM 接口不支持此 Docker 操作或账号权限不足。")
    }

    func actionIdentifierParameterSets(for container: DockerContainerSummary) -> [[String: String]] {
        var identifiers: [[String: String]] = []
        let trimmedName = normalizedContainerName(container.name)
        // 操作接口参数不统一：有的接受 container，有的只接受 name、id 或 JSON 数组。
        // 先尝试成本低的变体，遇到第一个真实 DSM 成功就停止。
        if !trimmedName.isEmpty {
            identifiers.append(["container": trimmedName])
            identifiers.append(["name": trimmedName])
            identifiers.append(["container_name": trimmedName])
        }
        if !container.containerID.isEmpty {
            identifiers.append(["container": container.containerID])
            identifiers.append(["id": container.containerID])
            identifiers.append(["container_id": container.containerID])
        }
        if !trimmedName.isEmpty {
            identifiers.append(["names": encodedJSONArray([trimmedName])])
        }
        if !container.containerID.isEmpty {
            identifiers.append(["ids": encodedJSONArray([container.containerID])])
        }
        return identifiers
    }

    func logIdentifierParameterSets(for container: DockerContainerSummary) -> [[String: String]] {
        var identifiers: [[String: String]] = []
        let trimmedName = normalizedContainerName(container.name)
        if !trimmedName.isEmpty {
            identifiers.append(["name": "/\(trimmedName)"])
            identifiers.append(["container": "/\(trimmedName)"])
            identifiers.append(["container_name": "/\(trimmedName)"])
            identifiers.append(["name": trimmedName])
            identifiers.append(["container": trimmedName])
            identifiers.append(["container_name": trimmedName])
            identifiers.append(["names": encodedJSONArray(["/\(trimmedName)"])])
            identifiers.append(["names": encodedJSONArray([trimmedName])])
        }
        if !container.containerID.isEmpty {
            identifiers.append(["container": container.containerID])
            identifiers.append(["id": container.containerID])
            identifiers.append(["container_id": container.containerID])
            identifiers.append(["ids": encodedJSONArray([container.containerID])])
        }
        return identifiers
    }

    func fetchResourceDictionaries() async throws -> [[String: Any]] {
        let json = try await callAPI(
            apiNames: ["SYNO.Docker.Container.Resource"],
            method: "get",
            extraParameters: [:]
        )
        let data = (json["data"] as? [String: Any]) ?? json
        if let resources = findValue(in: data, keys: ["resources"]) as? [[String: Any]] {
            return resources
        }
        if let resources = findValue(in: data, keys: ["containers"]) as? [[String: Any]] {
            return resources
        }
        return extractContainerDictionaries(from: data)
    }

    func requestJSON(
        path: String,
        parameters: [String: String],
        requiresSuccess: Bool,
        errorContext: DSMErrorContext = .module("DSM")
    ) async throws -> [String: Any] {
        var components = try baseURL()
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw SynologyClientError.invalidAddress }
        do {
            let (data, response) = try await session.data(from: url)
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

    func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SynologyClientError.connectionFailed("DSM 没有返回有效响应。")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw SynologyClientError.connectionFailed("DSM HTTP 状态码 \(httpResponse.statusCode)。")
        }
    }

    enum DSMErrorContext {
        case auth
        case module(String)
    }

    func mapDSMError(_ json: [String: Any], context: DSMErrorContext) -> SynologyClientError {
        let apiName: String
        let isAuth: Bool
        switch context {
        case .auth:
            apiName = "DSM"
            isAuth = true
        case .module(let name):
            apiName = name
            isAuth = false
        }
        let code = ((json["error"] as? [String: Any])?["code"] as? Int) ?? 0
        if isAuth {
            switch code {
            case 400, 401, 404:
                return .authenticationFailed("DSM 账号或密码错误。")
            case 403:
                return .twoFactorRequired
            default:
                return .apiUnavailable(code == 0 ? "DSM 登录失败。" : "DSM 登录失败，错误码 \(code)。")
            }
        }
        switch code {
        case 105, 106, 107, 119:
            return .sessionExpired
        case 101, 102, 103, 114:
            return .apiUnavailable("当前 DSM 接口不支持此 Docker 操作或参数不兼容。")
        case 402, 407:
            return .permissionDenied("\(apiName) 权限不足，请在 DSM 中检查 Container Manager 权限。")
        default:
            return .apiUnavailable(code == 0 ? "\(apiName) 调用失败。" : "\(apiName) 调用失败，错误码 \(code)。")
        }
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

    func parseDockerContainers(from dictionaries: [[String: Any]]) -> [DockerContainerSummary] {
        dictionaries.map { dictionary in
            let id = firstString(in: dictionary, keys: ["id", "container_id", "containerId", "uuid"]) ?? ""
            let name = firstString(in: dictionary, keys: ["name", "container_name", "containerName", "display_name"]) ?? (id.isEmpty ? "container" : String(id.prefix(12)))
            let image = firstString(in: dictionary, keys: ["image", "Image", "image_name", "repository", "repo", "config_image"]) ?? ""
            let state = firstString(in: dictionary, keys: ["state", "State", "status", "running"]) ?? ""
            let status = firstString(in: dictionary, keys: ["status_text", "status", "up_status", "up_time", "uptime"]) ?? state
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

    func parseLogText(from json: [String: Any]) -> String? {
        let data = (json["data"] as? [String: Any]) ?? json
        if let text = findValue(in: data, keys: ["log", "logs", "content", "text"]) as? String {
            return text
        }
        if let logs = findValue(in: data, keys: ["logs", "log", "lines", "items"]) as? [Any] {
            if logs.isEmpty { return "" }
            let lines = logs.compactMap { item -> String? in
                if let text = item as? String { return text }
                if let dictionary = item as? [String: Any] {
                    return firstString(in: dictionary, keys: ["text", "log", "message", "content"])
                }
                return stringValue(item)
            }
            return lines.joined(separator: "\n")
        }
        if let lines = findValue(in: data, keys: ["logs", "log", "lines", "items"]) as? [String] {
            return lines.joined(separator: "\n")
        }
        if let dictionaries = findValue(in: data, keys: ["logs", "log", "items"]) as? [[String: Any]] {
            let lines = dictionaries.compactMap { firstString(in: $0, keys: ["text", "log", "message", "content"]) }
            if !lines.isEmpty { return lines.joined(separator: "\n") }
        }
        return nil
    }

    func extractContainerDictionaries(from data: [String: Any]) -> [[String: Any]] {
        if let containers = findValue(in: data, keys: ["containers", "container", "items"]) as? [[String: Any]] {
            return containers
        }
        if let containerMap = findValue(in: data, keys: ["containers", "container"]) as? [String: Any] {
            return containerMap.values.compactMap { $0 as? [String: Any] }
        }
        if data.keys.contains(where: { ["name", "id", "container_id"].contains($0.lowercased()) }) {
            return [data]
        }
        return []
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
        name.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines)).lowercased()
    }

    func memoryText(from bytes: Int64) -> String {
        bytes > 0 ? ServerStatusParser.byteText(bytes) : "-"
    }

    func encodedJSONArray(_ values: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: values),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    func normalizedAPIPath(_ rawPath: String?) -> String {
        let trimmed = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "/webapi/entry.cgi" }
        if trimmed.hasPrefix("/webapi/") { return trimmed }
        if trimmed.hasPrefix("/") { return "/webapi\(trimmed)" }
        return "/webapi/\(trimmed)"
    }

    func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
        guard let value = findValue(in: dictionary, keys: keys) else { return nil }
        return stringValue(value)
    }

    func firstDouble(in dictionary: [String: Any], keys: [String]) -> Double? {
        guard let value = findValue(in: dictionary, keys: keys) else { return nil }
        return doubleValue(value)
    }

    func firstByteCount(in dictionary: [String: Any], keys: [String]) -> Int64 {
        guard let value = findValue(in: dictionary, keys: keys) else { return 0 }
        if let number = int64Value(value) { return number }
        if let string = stringValue(value) {
            return byteCount(from: string)
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
        switch value {
        case let value as Double:
            return value
        case let value as Float:
            return Double(value)
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")
            return Double(cleaned)
        default:
            return nil
        }
    }

    func byteCount(from text: String) -> Int64 {
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

private extension Error {
    var isSynologyCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        return localizedDescription.localizedCaseInsensitiveContains("cancel")
            || localizedDescription.contains("取消")
    }
}
