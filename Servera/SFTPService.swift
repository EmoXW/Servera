import Foundation
import Traversio

// MARK: - SFTP 文件传输服务
// 基于 Traversio 的 SFTPClient 封装，用于在已认证的 SSH 连接上做文件浏览、
// 上传、下载、删除、重命名和新建文件夹。所有操作都通过 SSHConnectionService
// 复用已建立的连接，避免重复握手。

enum SFTPEntryKind: Sendable, Equatable {
    case directory
    case regularFile
    case symbolicLink
    case other
}

struct SFTPEntry: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let absolutePath: String
    let kind: SFTPEntryKind
    let sizeBytes: UInt64?
    let modificationDate: Date?

    var isDirectory: Bool { kind == .directory }
}

enum SFTPServiceError: LocalizedError, Sendable {
    case notConnected
    case operationFailed(String)
    case invalidPath(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "SFTP 通道未建立，请检查 SSH 连接后重试。"
        case .operationFailed(let message): message
        case .invalidPath(let path): "路径无效：\(path)"
        }
    }
}

actor SFTPService {
    static let shared = SFTPService()

    // MARK: - 目录浏览

    func listDirectory(_ path: String, for request: SSHConnectionRequest) async throws -> [SFTPEntry] {
        let sftp = try await SSHConnectionService.shared.openSFTPChannel(for: request)
        do {
            let entries = try await sftp.listDirectory(path)
            return entries
                .filter { $0.filename != "." && $0.filename != ".." }
                .map { entry in
                    makeEntry(from: entry, parentPath: path)
                }
                .sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
        } catch {
            throw SFTPServiceError.operationFailed(error.localizedDescription)
        }
    }

    func homeDirectory(for request: SSHConnectionRequest) async throws -> String {
        let sftp = try await SSHConnectionService.shared.openSFTPChannel(for: request)
        do {
            let entry = try await sftp.realPath(".")
            return entry.filename
        } catch {
            throw SFTPServiceError.operationFailed(error.localizedDescription)
        }
    }

    // MARK: - 文件操作

    func createDirectory(_ path: String, for request: SSHConnectionRequest) async throws {
        let sftp = try await SSHConnectionService.shared.openSFTPChannel(for: request)
        do {
            try await sftp.makeDirectory(path)
        } catch {
            throw SFTPServiceError.operationFailed(error.localizedDescription)
        }
    }

    func removeFile(_ path: String, for request: SSHConnectionRequest) async throws {
        let sftp = try await SSHConnectionService.shared.openSFTPChannel(for: request)
        do {
            try await sftp.removeFile(path)
        } catch {
            throw SFTPServiceError.operationFailed(error.localizedDescription)
        }
    }

    func removeDirectory(_ path: String, for request: SSHConnectionRequest) async throws {
        let sftp = try await SSHConnectionService.shared.openSFTPChannel(for: request)
        do {
            try await sftp.removeDirectory(path)
        } catch {
            throw SFTPServiceError.operationFailed(error.localizedDescription)
        }
    }

    func rename(_ oldPath: String, to newPath: String, for request: SSHConnectionRequest) async throws {
        let sftp = try await SSHConnectionService.shared.openSFTPChannel(for: request)
        do {
            try await sftp.rename(oldPath, to: newPath)
        } catch {
            throw SFTPServiceError.operationFailed(error.localizedDescription)
        }
    }

    // MARK: - 文件传输

    func downloadFile(
        _ remotePath: String,
        to localURL: URL,
        for request: SSHConnectionRequest,
        progress: (@Sendable (Double) async -> Void)? = nil
    ) async throws {
        let sftp = try await SSHConnectionService.shared.openSFTPChannel(for: request)
        do {
            let attributes = try await sftp.stat(remotePath)
            let totalBytes = attributes.size ?? 0

            let byteArray = try await sftp.readFile(remotePath) { transferProgress in
                if totalBytes > 0 {
                    let ratio = Double(transferProgress.bytesTransferred) / Double(totalBytes)
                    await progress?(min(1.0, ratio))
                }
            }

            let data = Data(byteArray)
            try data.write(to: localURL)
            await progress?(1.0)
        } catch {
            throw SFTPServiceError.operationFailed(error.localizedDescription)
        }
    }

    func uploadFile(
        _ localURL: URL,
        to remotePath: String,
        for request: SSHConnectionRequest,
        progress: (@Sendable (Double) async -> Void)? = nil
    ) async throws {
        let sftp = try await SSHConnectionService.shared.openSFTPChannel(for: request)
        do {
            let data = try Data(contentsOf: localURL)
            let bytes = Array(data)
            let totalBytes = UInt64(bytes.count)

            try await sftp.writeFile(remotePath, data: bytes) { transferProgress in
                if totalBytes > 0 {
                    let ratio = Double(transferProgress.bytesTransferred) / Double(totalBytes)
                    await progress?(min(1.0, ratio))
                }
            }
            await progress?(1.0)
        } catch {
            throw SFTPServiceError.operationFailed(error.localizedDescription)
        }
    }

    // MARK: - 私有工具

    private func makeEntry(from entry: SSHSFTPNameEntry, parentPath: String) -> SFTPEntry {
        let name = entry.filename
        let normalizedParent = parentPath.hasSuffix("/") ? String(parentPath.dropLast()) : parentPath
        let absolutePath = "\(normalizedParent)/\(name)"

        let kind: SFTPEntryKind
        if let permissions = entry.attributes.permissions {
            switch permissions & 0o170000 {
            case 0o040000: kind = .directory
            case 0o100000: kind = .regularFile
            case 0o120000: kind = .symbolicLink
            default: kind = .other
            }
        } else {
            switch entry.longName.first {
            case "d": kind = .directory
            case "-": kind = .regularFile
            case "l": kind = .symbolicLink
            default: kind = .other
            }
        }

        let modificationDate: Date? = {
            if let timestamp = entry.attributes.modificationTime {
                return Date(timeIntervalSince1970: TimeInterval(timestamp))
            }
            return nil
        }()

        return SFTPEntry(
            id: absolutePath,
            name: name,
            absolutePath: absolutePath,
            kind: kind,
            sizeBytes: entry.attributes.size,
            modificationDate: modificationDate
        )
    }
}
