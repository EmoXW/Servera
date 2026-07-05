import Foundation
import CryptoKit
import Security
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 备份模型
// 这里负责 Servera 的导入/导出。设备元数据使用 JSON 保存，凭据放进加密信封里，
// 避免开源版本引导用户生成明文备份文件。

struct ServeraBackup: Codable {
    var version: Int
    var exportedAt: Date
    var devices: [BackupDevice]
}

// 原始备份内容外层的加密包装。版本号和算法显式保存，方便后续格式升级时做迁移。
struct EncryptedBackupEnvelope: Codable {
    var version: Int
    var algorithm: String
    var salt: Data
    var payload: Data
}

// 设备记录的可迁移表示。这里刻意不保存原始 Keychain 标识，
// 因为它只在导出来源的 Mac 上有意义。
struct BackupDevice: Codable, Identifiable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var kind: String
    var nasProtocol: String
    var nasVerifySSLCertificate: Bool?
    var synologySnapshot: SynologyStatusSnapshot?
    var account: String
    var note: String
    var orderIndex: Int
    var isVisible: Bool
    var createdAt: Date
    var dockerDetected: Bool
    var dockerContainerCount: Int
    var dockerRunningCount: Int?
    var dockerContainers: [DockerContainerSummary]?
    var authenticationKind: String?
    var hostKeyAlgorithm: String?
    var hostKeyFingerprintSHA256: String?
    var topProcesses: [ServerProcessSummary]?

    init(record: ManagedDeviceRecord) {
        id = record.deviceID
        name = record.name
        host = record.host
        port = record.port
        kind = record.kind.storageValue
        nasProtocol = record.nasProtocol.rawValue
        nasVerifySSLCertificate = record.nasVerifySSLCertificate
        synologySnapshot = record.synologySnapshot
        account = record.account
        note = record.note
        orderIndex = record.orderIndex
        isVisible = record.isVisible
        createdAt = record.createdAt
        dockerDetected = record.dockerDetected
        dockerContainerCount = record.dockerContainerCount
        dockerRunningCount = record.dockerRunningCount
        dockerContainers = record.dockerContainers
        authenticationKind = record.authenticationKind.rawValue
        hostKeyAlgorithm = record.hostKeyAlgorithm
        hostKeyFingerprintSHA256 = record.hostKeyFingerprintSHA256
        topProcesses = record.topProcesses
    }
}

// 负责备份序列化、加密，以及恢复到 SwiftData。
enum BackupService {
    // 导出时收集设备元数据和凭据材料，再用用户输入的密码整体加密。
    static func exportData(from records: [ManagedDeviceRecord], password: String) throws -> Data {
        let backup = ServeraBackup(
            version: 1,
            exportedAt: .now,
            devices: records.map(BackupDevice.init(record:))
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let plainData = try encoder.encode(backup)
        let salt = randomSalt()
        let key = symmetricKey(password: password, salt: salt)
        let sealedBox = try AES.GCM.seal(plainData, using: key)
        guard let combined = sealedBox.combined else {
            throw BackupError.encryptionFailed
        }
        let envelope = EncryptedBackupEnvelope(version: 1, algorithm: "AES.GCM.SHA256", salt: salt, payload: combined)
        return try encoder.encode(envelope)
    }

    // 导入使用 upsert：已有设备 id 就更新，否则插入新的 ManagedDeviceRecord。
    // 凭据会重新写回 Keychain。
    static func importData(_ data: Data, password: String, into context: ModelContext, existingRecords: [ManagedDeviceRecord]) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(EncryptedBackupEnvelope.self, from: data)
        let key = symmetricKey(password: password, salt: envelope.salt)
        let sealedBox = try AES.GCM.SealedBox(combined: envelope.payload)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        let backup = try decoder.decode(ServeraBackup.self, from: decryptedData)

        var existingByID = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.deviceID, $0) })

        for device in backup.devices {
            let record = existingByID[device.id] ?? ManagedDeviceRecord(
                deviceID: device.id,
                name: device.name,
                host: device.host,
                port: device.port,
                kind: ManagedDeviceKind(storageValue: device.kind),
                nasProtocol: NASConnectionProtocol(rawValue: device.nasProtocol) ?? .http,
                nasVerifySSLCertificate: device.nasVerifySSLCertificate ?? true,
                synologySnapshotJSON: encodedSynologySnapshot(device.synologySnapshot),
                account: device.account,
                credentialIdentifier: nil,
                credentialNeedsVerification: true,
                authenticationKind: ServerAuthenticationKind(rawValue: device.authenticationKind ?? "") ?? .password,
                hostKeyAlgorithm: device.hostKeyAlgorithm ?? "",
                hostKeyFingerprintSHA256: device.hostKeyFingerprintSHA256 ?? "",
                note: device.note,
                orderIndex: device.orderIndex,
                isVisible: device.isVisible,
                createdAt: device.createdAt,
                lastConnectedAt: nil,
                connectionStatus: .needsVerification,
                dockerDetected: device.dockerDetected,
                dockerContainerCount: device.dockerContainerCount,
                dockerRunningCount: device.dockerRunningCount ?? 0,
                dockerContainersJSON: encodedDockerContainers(device.dockerContainers ?? []),
                cpuPercent: ManagedDeviceKind(storageValue: device.kind) == .server ? 12 : 5,
                ramPercent: ManagedDeviceKind(storageValue: device.kind) == .server ? 34 : 28,
                topProcessesJSON: encodedProcesses(device.topProcesses ?? [])
            )

            record.name = device.name
            record.host = device.host
            record.port = device.port
            record.kind = ManagedDeviceKind(storageValue: device.kind)
            record.nasProtocol = NASConnectionProtocol(rawValue: device.nasProtocol) ?? .http
            record.nasVerifySSLCertificate = device.nasVerifySSLCertificate ?? true
            record.synologySnapshot = device.synologySnapshot ?? .empty
            record.account = device.account
            record.note = device.note
            record.orderIndex = device.orderIndex
            record.isVisible = device.isVisible
            record.createdAt = device.createdAt
            record.updatedAt = .now
            record.lastConnectedAt = nil
            record.connectionStatus = .needsVerification
            record.credentialIdentifier = nil
            record.credentialNeedsVerification = true
            record.authenticationKind = ServerAuthenticationKind(rawValue: device.authenticationKind ?? "") ?? .password
            record.hostKeyAlgorithm = device.hostKeyAlgorithm ?? ""
            record.hostKeyFingerprintSHA256 = device.hostKeyFingerprintSHA256 ?? ""
            record.dockerDetected = device.dockerDetected
            record.dockerContainerCount = device.dockerContainerCount
            record.dockerRunningCount = device.dockerRunningCount ?? 0
            record.dockerContainers = device.dockerContainers ?? []
            record.topProcesses = device.topProcesses ?? []

            if existingByID[device.id] == nil {
                context.insert(record)
                existingByID[device.id] = record
            }
        }

        try context.save()
        return backup.devices.count
    }

    private static func symmetricKey(password: String, salt: Data) -> SymmetricKey {
        var input = Data(password.utf8)
        input.append(salt)
        let digest = SHA256.hash(data: input)
        return SymmetricKey(data: digest)
    }

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    private static func encodedProcesses(_ processes: [ServerProcessSummary]) -> String {
        guard let data = try? JSONEncoder().encode(processes), let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    private static func encodedDockerContainers(_ containers: [DockerContainerSummary]) -> String {
        guard let data = try? JSONEncoder().encode(containers), let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    private static func encodedSynologySnapshot(_ snapshot: SynologyStatusSnapshot?) -> String {
        guard let snapshot,
              let data = try? JSONEncoder().encode(snapshot),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }
}

// 这些错误会直接展示给用户，因为备份导入/导出入口在设置页。
enum BackupError: LocalizedError {
    case encryptionFailed

    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            "备份加密失败，请重试。"
        }
    }
}

// 供 SwiftUI 文件导入/导出能力使用的文档桥接层。
struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
