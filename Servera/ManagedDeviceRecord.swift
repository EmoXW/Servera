import Foundation
import SwiftData

// MARK: - 设备持久化记录
// 设备的 SwiftData 数据源。运行时快照会摊平成基础字段/JSON 字符串，
// 既让 schema 迁移保持简单，也让 UI 能快速还原 DashboardDevice。

@Model
final class ManagedDeviceRecord {
    @Attribute(.unique) var deviceID: UUID
    var name: String
    var host: String
    var port: Int
    var kindRawValue: String
    var nasProtocolRawValue: String
    var nasVerifySSLCertificate: Bool = true
    var synologySnapshotJSON: String = ""
    var synologyControlPanelSnapshotJSON: String = ""
    var account: String
    var credentialIdentifier: String?
    var credentialNeedsVerification: Bool = false
    var authenticationKindRawValue: String = "password"
    var privateKeyIdentifier: String?
    var privateKeyPassphraseIdentifier: String?
    var hostKeyAlgorithm: String = ""
    var hostKeyFingerprintSHA256: String = ""
    var note: String
    var orderIndex: Int
    var isVisible: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastConnectedAt: Date?
    var connectionStatusRawValue: String
    var lastLatencyMilliseconds: Int?
    var dockerDetected: Bool = false
    var dockerContainerCount: Int = 0
    var dockerRunningCount: Int = 0
    var dockerContainersJSON: String = ""
    var warning: Bool = false
    var cpuPercent: Int = 0
    var cpuPercentValue: Double = 0
    var ramPercent: Int = 0
    var systemName: String = ""
    var systemVersion: String = ""
    var cpuCoreCount: Int = 0
    var cpuCorePercentsJSON: String = ""
    var cpuCorePercentValuesJSON: String = ""
    var cpuUserPercent: Int = 0
    var cpuUserPercentValue: Double = 0
    var cpuSystemPercent: Int = 0
    var cpuSystemPercentValue: Double = 0
    var cpuNicePercent: Int = 0
    var cpuNicePercentValue: Double = 0
    var cpuIOWaitPercent: Int = 0
    var cpuIOWaitPercentValue: Double = 0
    var cpuTemperatureCelsius: Int?
    var memoryTotalBytes: Int64 = 0
    var memoryUsedBytes: Int64 = 0
    var memoryAvailableBytes: Int64 = 0
    var memoryCachedBytes: Int64 = 0
    var memoryFreeBytes: Int64 = 0
    var swapTotalBytes: Int64 = 0
    var swapUsedBytes: Int64 = 0
    var diskTotalBytes: Int64 = 0
    var diskUsedBytes: Int64 = 0
    var diskAvailableBytes: Int64 = 0
    var diskDeviceName: String = ""
    var diskFilesystemType: String = ""
    var diskMountPoint: String = ""
    var uptimeSeconds: Int64 = 0
    var lastStatusCollectedAt: Date?
    var load1: Double = 0
    var load5: Double = 0
    var load15: Double = 0
    var storageUsedPercent: Int = 0
    var networkReceiveText: String = "-"
    var networkTransmitText: String = "-"
    var networkReceiveTotalText: String = "-"
    var networkTransmitTotalText: String = "-"
    var networkInterfaceName: String = ""
    var primaryIPText: String = ""
    var topProcessesJSON: String = ""
    var cpuDataAvailable: Bool = false
    var memoryDataAvailable: Bool = false
    var diskDataAvailable: Bool = false
    var networkDataAvailable: Bool = false
    var processDataAvailable: Bool = false
    var dockerDataAvailable: Bool = false
    var cpuErrorMessage: String = ""
    var memoryErrorMessage: String = ""
    var diskErrorMessage: String = ""
    var networkErrorMessage: String = ""
    var processErrorMessage: String = ""
    var dockerErrorMessage: String = ""
    var lastCollectionScriptKindRawValue: String = ""
    var lastCollectionDurationMilliseconds: Int = 0
    var lastRawStatusOutput: String = ""

    init(
        deviceID: UUID = UUID(),
        name: String,
        host: String,
        port: Int,
        kind: ManagedDeviceKind,
        nasProtocol: NASConnectionProtocol = .http,
        nasVerifySSLCertificate: Bool = true,
        synologySnapshotJSON: String = "",
        synologyControlPanelSnapshotJSON: String = "",
        account: String,
        credentialIdentifier: String? = nil,
        credentialNeedsVerification: Bool = false,
        authenticationKind: ServerAuthenticationKind = .password,
        privateKeyIdentifier: String? = nil,
        privateKeyPassphraseIdentifier: String? = nil,
        hostKeyAlgorithm: String = "",
        hostKeyFingerprintSHA256: String = "",
        note: String = "",
        orderIndex: Int,
        isVisible: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastConnectedAt: Date? = .now,
        connectionStatus: ConnectionStatus = .online,
        lastLatencyMilliseconds: Int? = nil,
        dockerDetected: Bool = false,
        dockerContainerCount: Int = 0,
        dockerRunningCount: Int = 0,
        dockerContainersJSON: String = "",
        warning: Bool = false,
        cpuPercent: Int = 8,
        cpuPercentValue: Double? = nil,
        ramPercent: Int = 32,
        systemName: String = "",
        systemVersion: String = "",
        cpuCoreCount: Int = 0,
        cpuCorePercentsJSON: String = "",
        cpuCorePercentValuesJSON: String = "",
        cpuUserPercent: Int = 0,
        cpuUserPercentValue: Double = 0,
        cpuSystemPercent: Int = 0,
        cpuSystemPercentValue: Double = 0,
        cpuNicePercent: Int = 0,
        cpuNicePercentValue: Double = 0,
        cpuIOWaitPercent: Int = 0,
        cpuIOWaitPercentValue: Double = 0,
        cpuTemperatureCelsius: Int? = nil,
        memoryTotalBytes: Int64 = 0,
        memoryUsedBytes: Int64 = 0,
        memoryAvailableBytes: Int64 = 0,
        memoryCachedBytes: Int64 = 0,
        memoryFreeBytes: Int64 = 0,
        swapTotalBytes: Int64 = 0,
        swapUsedBytes: Int64 = 0,
        diskTotalBytes: Int64 = 0,
        diskUsedBytes: Int64 = 0,
        diskAvailableBytes: Int64 = 0,
        diskDeviceName: String = "",
        diskFilesystemType: String = "",
        diskMountPoint: String = "",
        uptimeSeconds: Int64 = 0,
        lastStatusCollectedAt: Date? = nil,
        load1: Double = 0,
        load5: Double = 0,
        load15: Double = 0,
        storageUsedPercent: Int = 0,
        networkReceiveText: String = "-",
        networkTransmitText: String = "-",
        networkReceiveTotalText: String = "-",
        networkTransmitTotalText: String = "-",
        networkInterfaceName: String = "",
        primaryIPText: String = "",
        topProcessesJSON: String = "",
        cpuDataAvailable: Bool = false,
        memoryDataAvailable: Bool = false,
        diskDataAvailable: Bool = false,
        networkDataAvailable: Bool = false,
        processDataAvailable: Bool = false,
        dockerDataAvailable: Bool = false,
        cpuErrorMessage: String = "",
        memoryErrorMessage: String = "",
        diskErrorMessage: String = "",
        networkErrorMessage: String = "",
        processErrorMessage: String = "",
        dockerErrorMessage: String = "",
        lastCollectionScriptKindRawValue: String = "",
        lastCollectionDurationMilliseconds: Int = 0,
        lastRawStatusOutput: String = ""
    ) {
        self.deviceID = deviceID
        self.name = name
        self.host = host
        self.port = port
        self.kindRawValue = kind.storageValue
        self.nasProtocolRawValue = nasProtocol.rawValue
        self.nasVerifySSLCertificate = nasVerifySSLCertificate
        self.synologySnapshotJSON = synologySnapshotJSON
        self.synologyControlPanelSnapshotJSON = synologyControlPanelSnapshotJSON
        self.account = account
        self.credentialIdentifier = credentialIdentifier
        self.credentialNeedsVerification = credentialNeedsVerification
        self.authenticationKindRawValue = authenticationKind.rawValue
        self.privateKeyIdentifier = privateKeyIdentifier
        self.privateKeyPassphraseIdentifier = privateKeyPassphraseIdentifier
        self.hostKeyAlgorithm = hostKeyAlgorithm
        self.hostKeyFingerprintSHA256 = hostKeyFingerprintSHA256
        self.note = note
        self.orderIndex = orderIndex
        self.isVisible = isVisible
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastConnectedAt = lastConnectedAt
        self.connectionStatusRawValue = connectionStatus.rawValue
        self.lastLatencyMilliseconds = lastLatencyMilliseconds
        self.dockerDetected = dockerDetected
        self.dockerContainerCount = dockerContainerCount
        self.dockerRunningCount = dockerRunningCount
        self.dockerContainersJSON = dockerContainersJSON
        self.warning = warning
        self.cpuPercent = cpuPercent
        self.cpuPercentValue = cpuPercentValue ?? Double(cpuPercent)
        self.ramPercent = ramPercent
        self.systemName = systemName
        self.systemVersion = systemVersion
        self.cpuCoreCount = cpuCoreCount
        self.cpuCorePercentsJSON = cpuCorePercentsJSON
        self.cpuCorePercentValuesJSON = cpuCorePercentValuesJSON
        self.cpuUserPercent = cpuUserPercent
        self.cpuUserPercentValue = cpuUserPercentValue
        self.cpuSystemPercent = cpuSystemPercent
        self.cpuSystemPercentValue = cpuSystemPercentValue
        self.cpuNicePercent = cpuNicePercent
        self.cpuNicePercentValue = cpuNicePercentValue
        self.cpuIOWaitPercent = cpuIOWaitPercent
        self.cpuIOWaitPercentValue = cpuIOWaitPercentValue
        self.cpuTemperatureCelsius = cpuTemperatureCelsius
        self.memoryTotalBytes = memoryTotalBytes
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryAvailableBytes = memoryAvailableBytes
        self.memoryCachedBytes = memoryCachedBytes
        self.memoryFreeBytes = memoryFreeBytes
        self.swapTotalBytes = swapTotalBytes
        self.swapUsedBytes = swapUsedBytes
        self.diskTotalBytes = diskTotalBytes
        self.diskUsedBytes = diskUsedBytes
        self.diskAvailableBytes = diskAvailableBytes
        self.diskDeviceName = diskDeviceName
        self.diskFilesystemType = diskFilesystemType
        self.diskMountPoint = diskMountPoint
        self.uptimeSeconds = uptimeSeconds
        self.lastStatusCollectedAt = lastStatusCollectedAt
        self.load1 = load1
        self.load5 = load5
        self.load15 = load15
        self.storageUsedPercent = storageUsedPercent
        self.networkReceiveText = networkReceiveText
        self.networkTransmitText = networkTransmitText
        self.networkReceiveTotalText = networkReceiveTotalText
        self.networkTransmitTotalText = networkTransmitTotalText
        self.networkInterfaceName = networkInterfaceName
        self.primaryIPText = primaryIPText
        self.topProcessesJSON = topProcessesJSON
        self.cpuDataAvailable = cpuDataAvailable
        self.memoryDataAvailable = memoryDataAvailable
        self.diskDataAvailable = diskDataAvailable
        self.networkDataAvailable = networkDataAvailable
        self.processDataAvailable = processDataAvailable
        self.dockerDataAvailable = dockerDataAvailable
        self.cpuErrorMessage = cpuErrorMessage
        self.memoryErrorMessage = memoryErrorMessage
        self.diskErrorMessage = diskErrorMessage
        self.networkErrorMessage = networkErrorMessage
        self.processErrorMessage = processErrorMessage
        self.dockerErrorMessage = dockerErrorMessage
        self.lastCollectionScriptKindRawValue = lastCollectionScriptKindRawValue
        self.lastCollectionDurationMilliseconds = lastCollectionDurationMilliseconds
        self.lastRawStatusOutput = lastRawStatusOutput
    }

    var kind: ManagedDeviceKind {
        get { ManagedDeviceKind(storageValue: kindRawValue) }
        set { kindRawValue = newValue.storageValue }
    }

    var nasProtocol: NASConnectionProtocol {
        get { NASConnectionProtocol(rawValue: nasProtocolRawValue) ?? .http }
        set { nasProtocolRawValue = newValue.rawValue }
    }

    var connectionStatus: ConnectionStatus {
        get { ConnectionStatus(rawValue: connectionStatusRawValue) ?? .needsVerification }
        set { connectionStatusRawValue = newValue.rawValue }
    }

    var isDocumentationPlaceholder: Bool {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedHost.hasPrefix("203.0.113.")
            || normalizedHost.hasPrefix("198.51.100.")
            || normalizedHost.hasPrefix("192.0.2.")
    }

    var authenticationKind: ServerAuthenticationKind {
        get { ServerAuthenticationKind(rawValue: authenticationKindRawValue) ?? .password }
        set { authenticationKindRawValue = newValue.rawValue }
    }

    var credentialRef: DeviceCredentialRef? {
        guard let credentialIdentifier else { return nil }
        return DeviceCredentialRef(id: credentialIdentifier)
    }

    var dashboardDevice: DashboardDevice {
        DashboardDevice(
            id: deviceID,
            name: name,
            subtitle: subtitle,
            latency: latencyText,
            cpu: cpuPercent,
            cpuValue: cpuPercentValue,
            ram: ramPercent,
            docker: dockerDetected ? dockerContainerCount : 0,
            dockerRunningCount: dockerDetected ? dockerRunningCount : 0,
            dockerContainers: dockerContainers,
            warning: warning || connectionStatus == .needsVerification,
            kind: kind,
            credentialNeedsVerification: credentialNeedsVerification,
            systemName: systemName,
            systemVersion: systemVersion,
            uptimeSeconds: uptimeSeconds,
            cpuCoreCount: cpuCoreCount,
            cpuCorePercents: cpuCorePercents,
            cpuCorePercentValues: cpuCorePercentValues,
            cpuUserPercent: cpuUserPercent,
            cpuUserPercentValue: cpuUserPercentValue,
            cpuSystemPercent: cpuSystemPercent,
            cpuSystemPercentValue: cpuSystemPercentValue,
            cpuNicePercent: cpuNicePercent,
            cpuNicePercentValue: cpuNicePercentValue,
            cpuIOWaitPercent: cpuIOWaitPercent,
            cpuIOWaitPercentValue: cpuIOWaitPercentValue,
            cpuTemperatureCelsius: cpuTemperatureCelsius,
            memoryTotalBytes: memoryTotalBytes,
            memoryUsedBytes: memoryUsedBytes,
            memoryAvailableBytes: memoryAvailableBytes,
            memoryCachedBytes: memoryCachedBytes,
            memoryFreeBytes: memoryFreeBytes,
            swapTotalBytes: swapTotalBytes,
            swapUsedBytes: swapUsedBytes,
            diskTotalBytes: diskTotalBytes,
            diskUsedBytes: diskUsedBytes,
            diskAvailableBytes: diskAvailableBytes,
            diskDeviceName: diskDeviceName,
            diskFilesystemType: diskFilesystemType,
            diskMountPoint: diskMountPoint,
            load1: load1,
            load5: load5,
            load15: load15,
            storageUsedPercent: storageUsedPercent,
            networkReceiveText: networkReceiveText,
            networkTransmitText: networkTransmitText,
            networkReceiveTotalText: networkReceiveTotalText,
            networkTransmitTotalText: networkTransmitTotalText,
            networkInterfaceName: networkInterfaceName,
            primaryIPText: primaryIPText,
            topProcesses: topProcesses,
            lastStatusCollectedAt: lastStatusCollectedAt,
            cpuDataAvailable: cpuDataAvailable,
            memoryDataAvailable: memoryDataAvailable,
            diskDataAvailable: diskDataAvailable,
            networkDataAvailable: networkDataAvailable,
            processDataAvailable: processDataAvailable,
            dockerDataAvailable: dockerDataAvailable,
            cpuErrorMessage: cpuErrorMessage,
            memoryErrorMessage: memoryErrorMessage,
            diskErrorMessage: diskErrorMessage,
            networkErrorMessage: networkErrorMessage,
            processErrorMessage: processErrorMessage,
            dockerErrorMessage: dockerErrorMessage,
            lastCollectionScriptKind: SSHCollectionScriptKind(rawValue: lastCollectionScriptKindRawValue),
            lastCollectionDurationMilliseconds: lastCollectionDurationMilliseconds,
            lastRawStatusOutput: lastRawStatusOutput,
            nasStorageVolumes: synologySnapshot.volumes,
            nasControlPanelSnapshot: synologyControlPanelSnapshot
        )
    }

    private var subtitle: String {
        switch kind {
        case .server:
            if credentialNeedsVerification { return "凭据需要重新验证" }
            if !systemVersion.isEmpty { return systemVersion }
            return "SSH \(account)@\(host)"
        case .nas:
            if credentialNeedsVerification { return "凭据需要重新验证" }
            if !systemVersion.isEmpty { return systemVersion }
            return "Synology DSM \(nasProtocol.rawValue.uppercased())"
        }
    }

    private var latencyText: String {
        if connectionStatus == .needsVerification { return "待验证" }
        if let lastLatencyMilliseconds { return "\(lastLatencyMilliseconds) ms" }
        return connectionStatus.displayText
    }

    // 完整 SSH 校验刷新。添加/编辑服务器后走这里，
    // 保存 Host Key 元数据和所有解析后的状态字段。
    func applyServerSnapshot(_ outcome: SSHConnectionOutcome) {
        hostKeyAlgorithm = outcome.hostKeyAlgorithm
        hostKeyFingerprintSHA256 = outcome.hostKeyFingerprintSHA256
        lastLatencyMilliseconds = outcome.latencyMilliseconds
        cpuPercent = outcome.status.cpuPercent
        cpuPercentValue = outcome.status.cpuPercentValue
        ramPercent = outcome.status.memoryUsedPercent
        dockerDetected = outcome.status.dockerInstalled
        dockerContainerCount = outcome.status.dockerContainerCount
        dockerRunningCount = outcome.status.dockerRunningCount
        dockerContainers = outcome.status.dockerContainers
        systemName = outcome.status.systemName
        systemVersion = outcome.status.systemVersion
        cpuCoreCount = outcome.status.cpuCoreCount
        cpuCorePercents = outcome.status.cpuCorePercents
        cpuCorePercentValues = outcome.status.cpuCorePercentValues
        cpuUserPercent = outcome.status.cpuUserPercent
        cpuUserPercentValue = outcome.status.cpuUserPercentValue
        cpuSystemPercent = outcome.status.cpuSystemPercent
        cpuSystemPercentValue = outcome.status.cpuSystemPercentValue
        cpuNicePercent = outcome.status.cpuNicePercent
        cpuNicePercentValue = outcome.status.cpuNicePercentValue
        cpuIOWaitPercent = outcome.status.cpuIOWaitPercent
        cpuIOWaitPercentValue = outcome.status.cpuIOWaitPercentValue
        cpuTemperatureCelsius = outcome.status.cpuTemperatureCelsius
        memoryTotalBytes = outcome.status.memoryTotalBytes
        memoryUsedBytes = outcome.status.memoryUsedBytes
        memoryAvailableBytes = outcome.status.memoryAvailableBytes
        memoryCachedBytes = outcome.status.memoryCachedBytes
        memoryFreeBytes = outcome.status.memoryFreeBytes
        swapTotalBytes = outcome.status.swapTotalBytes
        swapUsedBytes = outcome.status.swapUsedBytes
        diskTotalBytes = outcome.status.diskTotalBytes
        diskUsedBytes = outcome.status.diskUsedBytes
        diskAvailableBytes = outcome.status.diskAvailableBytes
        diskDeviceName = outcome.status.diskDeviceName
        diskFilesystemType = outcome.status.diskFilesystemType
        diskMountPoint = outcome.status.diskMountPoint
        uptimeSeconds = outcome.status.uptimeSeconds
        lastStatusCollectedAt = outcome.status.collectedAt
        load1 = outcome.status.load1
        load5 = outcome.status.load5
        load15 = outcome.status.load15
        storageUsedPercent = outcome.status.diskUsedPercent
        networkReceiveText = outcome.status.networkReceiveText
        networkTransmitText = outcome.status.networkTransmitText
        networkReceiveTotalText = outcome.status.networkReceiveTotalText
        networkTransmitTotalText = outcome.status.networkTransmitTotalText
        networkInterfaceName = outcome.status.networkInterfaceName
        primaryIPText = outcome.status.primaryIPText
        topProcesses = outcome.status.topProcesses
        cpuDataAvailable = outcome.status.cpuAvailable
        memoryDataAvailable = outcome.status.memoryAvailable
        diskDataAvailable = outcome.status.diskAvailable
        networkDataAvailable = outcome.status.networkAvailable
        processDataAvailable = outcome.status.processAvailable
        dockerDataAvailable = outcome.status.dockerAvailable
        cpuErrorMessage = outcome.status.cpuErrorMessage
        memoryErrorMessage = outcome.status.memoryErrorMessage
        diskErrorMessage = outcome.status.diskErrorMessage
        networkErrorMessage = outcome.status.networkErrorMessage
        processErrorMessage = outcome.status.processErrorMessage
        dockerErrorMessage = outcome.status.dockerErrorMessage
        applyDiagnostics(outcome)
        lastConnectedAt = .now
        updatedAt = .now
        connectionStatus = .online
        credentialNeedsVerification = false
        warning = outcome.status.dockerInstalled && outcome.status.dockerContainerCount > outcome.status.dockerRunningCount
    }

    // NAS 记录的 DSM 刷新。快照里的模块可以独立失败，
    // 某个 DSM API 不可用时，NAS 面板仍能展示其它模块的部分状态。
    func applySynologySnapshot(_ outcome: SynologyConnectionOutcome) {
        synologySnapshot = outcome.snapshot
        lastLatencyMilliseconds = outcome.latencyMilliseconds
        systemName = outcome.snapshot.systemName
        systemVersion = outcome.snapshot.dsmVersion
        uptimeSeconds = outcome.snapshot.uptimeSeconds
        cpuPercent = outcome.snapshot.cpuPercent
        cpuPercentValue = Double(outcome.snapshot.cpuPercent)
        ramPercent = outcome.snapshot.memoryPercent
        cpuTemperatureCelsius = outcome.snapshot.temperatureCelsius
        networkReceiveText = outcome.snapshot.networkReceiveText
        networkTransmitText = outcome.snapshot.networkTransmitText
        dockerDetected = outcome.snapshot.dockerInstalled
        dockerContainerCount = outcome.snapshot.dockerContainerCount
        dockerRunningCount = outcome.snapshot.dockerRunningCount
        dockerContainers = outcome.snapshot.dockerContainers
        dockerDataAvailable = outcome.snapshot.dockerAvailable
        dockerErrorMessage = outcome.snapshot.dockerErrorMessage
        cpuDataAvailable = outcome.snapshot.resourceAvailable
        memoryDataAvailable = outcome.snapshot.resourceAvailable
        networkDataAvailable = outcome.snapshot.resourceAvailable
        cpuErrorMessage = outcome.snapshot.resourceErrorMessage
        memoryErrorMessage = outcome.snapshot.resourceErrorMessage
        networkErrorMessage = outcome.snapshot.resourceErrorMessage
        diskDataAvailable = outcome.snapshot.storageAvailable
        diskErrorMessage = outcome.snapshot.storageErrorMessage
        if let primaryVolume = outcome.snapshot.volumes.first {
            diskDeviceName = primaryVolume.name
            diskFilesystemType = primaryVolume.status
            diskMountPoint = primaryVolume.name
            diskTotalBytes = primaryVolume.totalBytes
            diskUsedBytes = primaryVolume.usedBytes
            diskAvailableBytes = primaryVolume.availableBytes
            storageUsedPercent = primaryVolume.usedPercent
        } else {
            diskTotalBytes = 0
            diskUsedBytes = 0
            diskAvailableBytes = 0
            storageUsedPercent = 0
        }
        lastStatusCollectedAt = outcome.snapshot.collectedAt
        lastConnectedAt = .now
        updatedAt = .now
        connectionStatus = .online
        credentialNeedsVerification = false
        warning = outcome.snapshot.volumes.contains { $0.usedPercent >= 90 }
    }

    // 初次添加后的轻量 SSH 刷新。只更新实时指标和 Docker 状态，
    // 不改变已保存的连接身份信息。
    func applyLiveMetricsSnapshot(_ outcome: SSHConnectionOutcome) {
        if !outcome.hostKeyAlgorithm.isEmpty {
            hostKeyAlgorithm = outcome.hostKeyAlgorithm
        }
        if !outcome.hostKeyFingerprintSHA256.isEmpty {
            hostKeyFingerprintSHA256 = outcome.hostKeyFingerprintSHA256
        }
        if let latencyMilliseconds = outcome.latencyMilliseconds {
            lastLatencyMilliseconds = latencyMilliseconds
        }

        if outcome.status.cpuAvailable {
            cpuPercent = outcome.status.cpuPercent
            cpuPercentValue = outcome.status.cpuPercentValue
            cpuDataAvailable = true
            if outcome.status.cpuCoreCount > 0 {
                cpuCoreCount = outcome.status.cpuCoreCount
            }
            if !outcome.status.cpuCorePercents.isEmpty {
                cpuCorePercents = outcome.status.cpuCorePercents
            }
            if !outcome.status.cpuCorePercentValues.isEmpty {
                cpuCorePercentValues = outcome.status.cpuCorePercentValues
            }
            cpuUserPercent = outcome.status.cpuUserPercent
            cpuUserPercentValue = outcome.status.cpuUserPercentValue
            cpuSystemPercent = outcome.status.cpuSystemPercent
            cpuSystemPercentValue = outcome.status.cpuSystemPercentValue
            cpuNicePercent = outcome.status.cpuNicePercent
            cpuNicePercentValue = outcome.status.cpuNicePercentValue
            cpuIOWaitPercent = outcome.status.cpuIOWaitPercent
            cpuIOWaitPercentValue = outcome.status.cpuIOWaitPercentValue
            cpuErrorMessage = ""
        } else {
            cpuDataAvailable = false
            cpuErrorMessage = outcome.status.cpuErrorMessage
        }

        if outcome.status.memoryAvailable {
            memoryDataAvailable = true
            ramPercent = outcome.status.memoryUsedPercent
            memoryTotalBytes = outcome.status.memoryTotalBytes
            memoryUsedBytes = outcome.status.memoryUsedBytes
            memoryAvailableBytes = outcome.status.memoryAvailableBytes
            memoryCachedBytes = outcome.status.memoryCachedBytes
            memoryFreeBytes = outcome.status.memoryFreeBytes
            swapTotalBytes = outcome.status.swapTotalBytes
            swapUsedBytes = outcome.status.swapUsedBytes
            memoryErrorMessage = ""
        } else {
            memoryDataAvailable = false
            memoryErrorMessage = outcome.status.memoryErrorMessage
        }

        if outcome.status.uptimeSeconds > 0 {
            uptimeSeconds = outcome.status.uptimeSeconds
        }
        load1 = outcome.status.load1
        load5 = outcome.status.load5
        load15 = outcome.status.load15
        if outcome.status.networkAvailable {
            networkDataAvailable = true
            networkReceiveText = outcome.status.networkReceiveText
            networkTransmitText = outcome.status.networkTransmitText
            networkReceiveTotalText = outcome.status.networkReceiveTotalText
            networkTransmitTotalText = outcome.status.networkTransmitTotalText
            networkInterfaceName = outcome.status.networkInterfaceName
            primaryIPText = outcome.status.primaryIPText
            networkErrorMessage = ""
        } else {
            networkDataAvailable = false
            networkErrorMessage = outcome.status.networkErrorMessage
        }

        if outcome.status.dockerAvailable {
            dockerDetected = outcome.status.dockerInstalled
            dockerContainerCount = outcome.status.dockerContainerCount
            dockerRunningCount = outcome.status.dockerRunningCount
            dockerContainers = outcome.status.dockerContainers
            dockerDataAvailable = true
            warning = outcome.status.dockerInstalled && outcome.status.dockerContainerCount > outcome.status.dockerRunningCount
            dockerErrorMessage = ""
        } else {
            dockerDataAvailable = false
            dockerErrorMessage = outcome.status.dockerErrorMessage
        }
        lastStatusCollectedAt = outcome.status.collectedAt
        applyDiagnostics(outcome)
        lastConnectedAt = .now
        updatedAt = .now
        connectionStatus = .online
        credentialNeedsVerification = false
    }

    private func applyDiagnostics(_ outcome: SSHConnectionOutcome) {
        lastCollectionScriptKindRawValue = outcome.diagnostics.scriptKind.rawValue
        lastCollectionDurationMilliseconds = outcome.diagnostics.commandDurationMilliseconds
        lastRawStatusOutput = outcome.rawStatusOutput
    }

    // NAS Docker 操作会从 DSM 返回新的容器列表；这里写入持久化记录，
    // 保证启动/停止/重启/删除后首页和详情页同步。
    func applyNASDockerContainers(_ containers: [DockerContainerSummary]) {
        var snapshot = synologySnapshot
        snapshot.dockerInstalled = true
        snapshot.dockerAvailable = true
        snapshot.dockerContainerCount = containers.count
        snapshot.dockerRunningCount = containers.filter(\.isRunning).count
        snapshot.dockerContainers = containers
        snapshot.dockerErrorMessage = ""
        synologySnapshot = snapshot

        dockerDetected = true
        dockerContainers = containers
        dockerContainerCount = snapshot.dockerContainerCount
        dockerRunningCount = snapshot.dockerRunningCount
        dockerDataAvailable = true
        dockerErrorMessage = ""
        updatedAt = .now
    }

    var topProcesses: [ServerProcessSummary] {
        get {
            guard !topProcessesJSON.isEmpty, let data = topProcessesJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([ServerProcessSummary].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue), let string = String(data: data, encoding: .utf8) else {
                topProcessesJSON = ""
                return
            }
            topProcessesJSON = string
        }
    }

    var dockerContainers: [DockerContainerSummary] {
        get {
            guard !dockerContainersJSON.isEmpty, let data = dockerContainersJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([DockerContainerSummary].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue), let string = String(data: data, encoding: .utf8) else {
                dockerContainersJSON = ""
                return
            }
            dockerContainersJSON = string
        }
    }

    var synologySnapshot: SynologyStatusSnapshot {
        get {
            guard !synologySnapshotJSON.isEmpty, let data = synologySnapshotJSON.data(using: .utf8) else { return .empty }
            return (try? JSONDecoder().decode(SynologyStatusSnapshot.self, from: data)) ?? .empty
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue), let string = String(data: data, encoding: .utf8) else {
                synologySnapshotJSON = ""
                return
            }
            synologySnapshotJSON = string
        }
    }

    var synologyControlPanelSnapshot: NASControlPanelSnapshot {
        get {
            guard !synologyControlPanelSnapshotJSON.isEmpty, let data = synologyControlPanelSnapshotJSON.data(using: .utf8) else { return .empty }
            guard var snapshot = try? JSONDecoder().decode(NASControlPanelSnapshot.self, from: data) else { return .empty }
            snapshot.modules.removeAll { !NASControlPanelModule.visibleCases.contains($0.module) }
            return snapshot
        }
        set {
            var visibleSnapshot = newValue
            visibleSnapshot.modules.removeAll { !NASControlPanelModule.visibleCases.contains($0.module) }
            guard let data = try? JSONEncoder().encode(visibleSnapshot), let string = String(data: data, encoding: .utf8) else {
                synologyControlPanelSnapshotJSON = ""
                return
            }
            synologyControlPanelSnapshotJSON = string
        }
    }

    var cpuCorePercents: [Int] {
        get {
            guard !cpuCorePercentsJSON.isEmpty, let data = cpuCorePercentsJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([Int].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue), let string = String(data: data, encoding: .utf8) else {
                cpuCorePercentsJSON = ""
                return
            }
            cpuCorePercentsJSON = string
        }
    }

    var cpuCorePercentValues: [Double] {
        get {
            guard !cpuCorePercentValuesJSON.isEmpty, let data = cpuCorePercentValuesJSON.data(using: .utf8) else {
                return cpuCorePercents.map(Double.init)
            }
            return (try? JSONDecoder().decode([Double].self, from: data)) ?? cpuCorePercents.map(Double.init)
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue), let string = String(data: data, encoding: .utf8) else {
                cpuCorePercentValuesJSON = ""
                return
            }
            cpuCorePercentValuesJSON = string
        }
    }
}

struct DeviceCredentialRef: Codable, Hashable, Identifiable {
    let id: String
}

// 列表行和添加/编辑反馈使用的高层连接状态。
enum ConnectionStatus: String, Codable, CaseIterable {
    case online
    case offline
    case connecting
    case failed
    case needsVerification

    var displayText: String {
        switch self {
        case .online: "在线"
        case .offline: "离线"
        case .connecting: "连接中"
        case .failed: "失败"
        case .needsVerification: "待验证"
        }
    }
}

// NAS 协议和主机分开保存，用户切换 HTTP/HTTPS 时不用重写地址字段。
enum NASConnectionProtocol: String, Codable, CaseIterable, Identifiable {
    case http
    case https

    var id: String { rawValue }

    var defaultPort: Int {
        switch self {
        case .http: 5000
        case .https: 5001
        }
    }
}

extension ManagedDeviceKind {
    var storageValue: String {
        switch self {
        case .server: "server"
        case .nas: "nas"
        }
    }

    init(storageValue: String) {
        switch storageValue {
        case "nas":
            self = .nas
        default:
            self = .server
        }
    }
}
