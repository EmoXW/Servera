import Foundation

// MARK: - 群晖 File Station API
// NAS 文件浏览器的列表、上传、下载、移动、删除都共用这里。
// 文件冲突和 DSM 权限错误在这里映射，UI 代码保持清晰。

struct SynologyFileConnection: Sendable {
    var host: String
    var port: Int
    var scheme: NASConnectionProtocol
    var account: String
    var password: String
    var verifySSLCertificate: Bool
}

struct SynologySharedFolder: Identifiable, Hashable, Sendable {
    var name: String
    var path: String
    var volumePath: String
    var isWritable: Bool?

    var id: String { path }
}

struct SynologyFileItem: Identifiable, Hashable, Sendable {
    var name: String
    var path: String
    var isDirectory: Bool
    var sizeBytes: Int64
    var modifiedAt: Date?
    var fileExtension: String

    var id: String { path }

    var displaySize: String {
        isDirectory ? "文件夹" : ServerStatusParser.byteText(sizeBytes)
    }

    var modifiedText: String {
        guard let modifiedAt else { return "-" }
        return SynologyFileItem.dateFormatter.string(from: modifiedAt)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

struct SynologyFileUploadConflict: LocalizedError, Equatable {
    var fileName: String

    var errorDescription: String? {
        "文件已存在，是否覆盖？"
    }
}

/// NAS 文件浏览器使用的 File Station 客户端。
///
/// 上传逻辑刻意放在这里，而不是走通用 JSON helper：
/// DSM 要求 api/version/method/_sid 放在 URL query，multipart body 只放文件相关字段。
/// 之前混在一起就是 Upload 101 的根因。
final class SynologyFileService: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let connection: SynologyFileConnection
    private var session: URLSession!
    private var apiInfo: [String: APIInfo] = [:]
    private var sid: String?

    init(connection: SynologyFileConnection) {
        self.connection = connection
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 120
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
                "version": "\(min(max(auth.maxVersion, auth.minVersion), 6))",
                "method": "logout",
                "session": "FileStation",
                "_sid": sid
            ],
            requiresSuccess: false
        )
        self.sid = nil
    }

    func listSharedFolders(for volume: SynologyStorageVolume) async throws -> [SynologySharedFolder] {
        let json = try await authenticatedJSON(api: "SYNO.FileStation.List", method: "list_share", extraParameters: [
            "additional": "[\"real_path\",\"owner\",\"time\",\"perm\"]"
        ])
        let data = (json["data"] as? [String: Any]) ?? json
        let shares = extractDictionaries(from: data, keys: ["shares", "share", "items"]).compactMap(parseSharedFolder)
        let volumePath = normalizedPath(volume.path)
        guard !volumePath.isEmpty else { return shares }
        let filtered = shares.filter { share in
            let shareVolume = normalizedPath(share.volumePath)
            return shareVolume == volumePath || normalizedPath(share.path).hasPrefix(volumePath + "/")
        }
        return filtered.isEmpty ? shares : filtered
    }

    func listDirectory(path: String) async throws -> [SynologyFileItem] {
        let json = try await authenticatedJSON(api: "SYNO.FileStation.List", method: "list", extraParameters: [
            "folder_path": path,
            "additional": "[\"real_path\",\"size\",\"time\",\"type\",\"perm\"]",
            "sort_by": "name",
            "sort_direction": "asc"
        ])
        let data = (json["data"] as? [String: Any]) ?? json
        return extractDictionaries(from: data, keys: ["files", "file", "items"]).compactMap(parseFileItem)
    }

    func createFolder(parentPath: String, name: String) async throws {
        _ = try await authenticatedJSON(api: "SYNO.FileStation.CreateFolder", method: "create", extraParameters: [
            "folder_path": parentPath,
            "name": name,
            "force_parent": "false"
        ])
    }

    func rename(path: String, newName: String) async throws {
        _ = try await authenticatedJSON(api: "SYNO.FileStation.Rename", method: "rename", extraParameters: [
            "path": path,
            "name": newName
        ])
    }

    func delete(paths: [String]) async throws {
        _ = try await authenticatedJSON(api: "SYNO.FileStation.Delete", method: "start", extraParameters: [
            "path": encodedJSONArray(paths)
        ])
    }

    func move(paths: [String], destinationFolderPath: String) async throws {
        _ = try await authenticatedJSON(api: "SYNO.FileStation.CopyMove", method: "start", extraParameters: [
            "path": encodedJSONArray(paths),
            "dest_folder_path": destinationFolderPath,
            "overwrite": "false",
            "remove_src": "true"
        ])
    }

    func download(path: String) async throws -> URL {
        guard let sid else { throw SynologyClientError.sessionExpired }
        var components = try baseURL()
        components.path = fileStationPath(for: "SYNO.FileStation.Download")
        components.queryItems = [
            URLQueryItem(name: "api", value: "SYNO.FileStation.Download"),
            URLQueryItem(name: "version", value: "\(apiInfo["SYNO.FileStation.Download"]?.maxVersion ?? 2)"),
            URLQueryItem(name: "method", value: "download"),
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "mode", value: "download"),
            URLQueryItem(name: "_sid", value: sid)
        ]
        guard let url = components.url else { throw SynologyClientError.invalidAddress }
        let (temporaryURL, response) = try await session.download(from: url)
        try validateHTTPResponse(response)
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Servera-NAS", isDirectory: true)
            .appendingPathComponent(fileName.isEmpty ? "download" : fileName)
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    func upload(localFileURL: URL, destinationFolderPath: String, overwrite: Bool = false) async throws {
        guard let sid else { throw SynologyClientError.sessionExpired }
        let data = try Data(contentsOf: localFileURL)
        let fileName = localFileURL.lastPathComponent
        let boundary = "ServeraBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: try uploadURL(sid: sid))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // api/version/method/_sid 必须留在 query 中。
        // multipart body 只放 File Station 表单字段和二进制文件内容。
        request.httpBody = multipartBody(
            boundary: boundary,
            fields: [
                "path": destinationFolderPath,
                "create_parents": "false",
                "overwrite": overwrite ? "true" : "false"
            ],
            fileName: fileName,
            fileData: data
        )
        let (responseData, response) = try await session.data(for: request)
        try validateHTTPResponse(response)
        guard let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw SynologyClientError.apiUnavailable("上传接口返回内容不是 JSON。")
        }
        if (object["success"] as? Bool) != true {
            throw mapUploadError(object, fileName: fileName)
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

private extension SynologyFileService {
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
                "query": "SYNO.API.Auth,SYNO.FileStation.List,SYNO.FileStation.Upload,SYNO.FileStation.Download,SYNO.FileStation.CreateFolder,SYNO.FileStation.Rename,SYNO.FileStation.Delete,SYNO.FileStation.CopyMove"
            ],
            requiresSuccess: true
        )
        guard let data = json["data"] as? [String: Any] else {
            throw SynologyClientError.apiUnavailable("DSM File Station API 探测失败。")
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
                "version": "\(min(max(auth.maxVersion, auth.minVersion), 6))",
                "method": "login",
                "account": connection.account,
                "passwd": connection.password,
                "session": "FileStation",
                "format": "sid"
            ],
            requiresSuccess: true,
            errorContext: .auth
        )
        guard let data = json["data"] as? [String: Any],
              let sid = data["sid"] as? String,
              !sid.isEmpty else {
            throw SynologyClientError.authenticationFailed("DSM 登录成功但没有返回文件会话。")
        }
        return sid
    }

    func authenticatedJSON(api: String, method: String, extraParameters: [String: String]) async throws -> [String: Any] {
        do {
            return try await authenticatedJSONWithoutRetry(api: api, method: method, extraParameters: extraParameters)
        } catch SynologyClientError.sessionExpired {
            sid = try await login()
            return try await authenticatedJSONWithoutRetry(api: api, method: method, extraParameters: extraParameters)
        }
    }

    func authenticatedJSONWithoutRetry(api: String, method: String, extraParameters: [String: String]) async throws -> [String: Any] {
        guard let sid else { throw SynologyClientError.sessionExpired }
        guard let info = apiInfo[api] else {
            throw SynologyClientError.apiUnavailable("\(api) 不可用，请确认 File Station 已启用。")
        }
        var parameters = [
            "api": api,
            "version": "\(info.maxVersion)",
            "method": method,
            "_sid": sid
        ]
        parameters.merge(extraParameters) { _, new in new }
        return try await requestJSON(
            path: info.path,
            parameters: parameters,
            requiresSuccess: true,
            errorContext: .module(api)
        )
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

    func uploadURL(sid: String) throws -> URL {
        var components = try baseURL()
        components.path = fileStationPath(for: "SYNO.FileStation.Upload")
        // DSM Upload 比其它 File Station 接口更严格：
        // 这些参数必须是 URL query item，不能放进 multipart 表单字段。
        components.queryItems = [
            URLQueryItem(name: "api", value: "SYNO.FileStation.Upload"),
            URLQueryItem(name: "version", value: "\(apiInfo["SYNO.FileStation.Upload"]?.maxVersion ?? 2)"),
            URLQueryItem(name: "method", value: "upload"),
            URLQueryItem(name: "_sid", value: sid)
        ]
        guard let url = components.url else { throw SynologyClientError.invalidAddress }
        return url
    }

    func fileStationPath(for api: String) -> String {
        apiInfo[api]?.path ?? "/webapi/entry.cgi"
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
        return mapDSMError(json, apiName: apiName, isAuth: isAuth)
    }

    func mapDSMError(_ json: [String: Any], apiName: String, isAuth: Bool = false) -> SynologyClientError {
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
        case 101, 102:
            return .apiUnavailable("\(apiName) 参数或路径无效，请刷新目录后重试。")
        case 402, 407:
            return .permissionDenied("当前 DSM 账号没有访问或操作此文件夹的权限，请在 DSM 控制面板中检查共享文件夹权限。")
        case 408, 409, 410:
            return .permissionDenied("当前路径不可访问或文件被占用，请检查 DSM 权限和文件状态。")
        default:
            return .apiUnavailable(code == 0 ? "\(apiName) 调用失败。" : "\(apiName) 调用失败，错误码 \(code)。")
        }
    }

    func mapUploadError(_ json: [String: Any], fileName: String) -> Error {
        let code = ((json["error"] as? [String: Any])?["code"] as? Int) ?? 0
        switch code {
        case 105, 106, 107, 119:
            return SynologyClientError.sessionExpired
        case 101, 102:
            return SynologyClientError.apiUnavailable("上传参数无效，请重新选择文件或刷新目录后重试。")
        case 402, 407:
            return SynologyClientError.permissionDenied("当前 DSM 账号没有上传到此文件夹的权限，请在 DSM 控制面板中检查共享文件夹权限。")
        case 414, 1805, 1807, 1810, 1812, 1815:
            // 不同 DSM 构建对上传冲突码不一致。当前测试 NAS 的“文件已存在”返回 414；
            // 旧文档或旧安装可能使用 18xx 区间。
            return SynologyFileUploadConflict(fileName: fileName)
        default:
            return SynologyClientError.apiUnavailable(code == 0 ? "SYNO.FileStation.Upload 调用失败。" : "SYNO.FileStation.Upload 调用失败，错误码 \(code)。")
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

    func parseSharedFolder(_ dictionary: [String: Any]) -> SynologySharedFolder? {
        let path = firstString(in: dictionary, keys: ["path", "folder_path", "real_path"]) ?? ""
        let name = firstString(in: dictionary, keys: ["name", "display_name"]) ?? URL(fileURLWithPath: path).lastPathComponent
        guard !path.isEmpty || !name.isEmpty else { return nil }
        let resolvedPath = path.isEmpty ? "/\(name)" : path
        let realPath = firstString(in: dictionary, keys: ["real_path", "volume_path"]) ?? ""
        return SynologySharedFolder(
            name: name,
            path: resolvedPath,
            volumePath: volumePath(from: realPath.isEmpty ? resolvedPath : realPath),
            isWritable: writableValue(from: dictionary)
        )
    }

    func parseFileItem(_ dictionary: [String: Any]) -> SynologyFileItem? {
        let path = firstString(in: dictionary, keys: ["path", "file_path"]) ?? ""
        let name = firstString(in: dictionary, keys: ["name", "display_name"]) ?? URL(fileURLWithPath: path).lastPathComponent
        guard !path.isEmpty || !name.isEmpty else { return nil }
        let type = firstString(in: dictionary, keys: ["type"])?.lowercased() ?? ""
        let isDirectory = type == "dir" || type == "folder" || boolValue(findValue(in: dictionary, keys: ["isdir", "is_dir"])) == true
        let modifiedSeconds = firstInt64(in: dictionary, keys: ["mtime", "modified", "modification_time"])
            ?? firstInt64(in: firstDictionary(in: dictionary, keys: ["time"]) ?? [:], keys: ["mtime", "modified"])
        let resolvedName = name.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : name
        return SynologyFileItem(
            name: resolvedName,
            path: path.isEmpty ? resolvedName : path,
            isDirectory: isDirectory,
            sizeBytes: firstByteCount(in: dictionary, keys: ["size", "filesize", "byte_size"]),
            modifiedAt: modifiedSeconds.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            fileExtension: URL(fileURLWithPath: resolvedName).pathExtension.lowercased()
        )
    }

    func multipartBody(boundary: String, fields: [String: String], fileName: String, fileData: Data) -> Data {
        var data = Data()
        for (key, value) in fields {
            data.appendString("--\(boundary)\r\n")
            data.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            data.appendString("\(value)\r\n")
        }
        data.appendString("--\(boundary)\r\n")
        data.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        data.appendString("Content-Type: application/octet-stream\r\n\r\n")
        data.append(fileData)
        data.appendString("\r\n--\(boundary)--\r\n")
        return data
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

    func volumePath(from path: String) -> String {
        let normalized = normalizedPath(path)
        guard normalized.hasPrefix("/volume") else { return "" }
        let parts = normalized.split(separator: "/")
        guard let first = parts.first else { return "" }
        return "/\(first)"
    }

    func normalizedPath(_ path: String) -> String {
        var trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/"), trimmed.count > 1 {
            trimmed.removeLast()
        }
        return trimmed
    }

    func writableValue(from dictionary: [String: Any]) -> Bool? {
        if let value = boolValue(findValue(in: dictionary, keys: ["writable", "writeable", "can_write"])) {
            return value
        }
        if let perm = findValue(in: dictionary, keys: ["perm"]) as? [String: Any] {
            return boolValue(findValue(in: perm, keys: ["write", "writable", "can_write"]))
        }
        return nil
    }

    func extractDictionaries(from data: [String: Any], keys: [String]) -> [[String: Any]] {
        if let list = findValue(in: data, keys: keys) as? [[String: Any]] { return list }
        if let dict = findValue(in: data, keys: keys) as? [String: Any] {
            return dict.values.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    func firstDictionary(in dictionary: [String: Any], keys: [String]) -> [String: Any]? {
        findValue(in: dictionary, keys: keys) as? [String: Any]
    }

    func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
        guard let value = findValue(in: dictionary, keys: keys) else { return nil }
        return stringValue(value)
    }

    func firstInt64(in dictionary: [String: Any], keys: [String]) -> Int64? {
        guard let value = findValue(in: dictionary, keys: keys) else { return nil }
        return int64Value(value)
    }

    func firstByteCount(in dictionary: [String: Any], keys: [String]) -> Int64 {
        guard let value = findValue(in: dictionary, keys: keys) else { return 0 }
        if let number = int64Value(value) { return number }
        if let string = stringValue(value) {
            return byteCount(from: string)
        }
        return 0
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

    func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "yes", "1", "write", "rw"].contains(normalized) { return true }
            if ["false", "no", "0", "read", "ro"].contains(normalized) { return false }
        }
        return nil
    }
}

private extension Data {
    mutating func appendString(_ text: String) {
        append(Data(text.utf8))
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
