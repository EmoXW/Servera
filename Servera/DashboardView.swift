import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 服务器首页
// 服务器页同时承担两个任务：顶部做轻量视觉概览，下面做可排序的运维列表。
// 数据仍由根视图从 SwiftData 记录传入，本视图只负责渲染和转发用户操作。

struct DashboardView: View {
    let devices: [DashboardDevice]
    var autoRefreshEnabled: Bool = true
    let onReorder: ([UUID]) -> Void
    let refreshingDeviceIDs: Set<UUID>
    let onSelect: (DashboardDevice) -> Void
    let onRefresh: (DashboardDevice) -> Void
    let onRefreshAll: () async -> Void
    let onAutoRefresh: (DashboardDevice) -> Void
    let onAddServer: () -> Void
    let onEdit: (DashboardDevice) -> Void
    let onDelete: (DashboardDevice) -> Void
    @State private var draggingDevice: DashboardDevice?
    @State private var orderedDeviceIDs: [UUID] = []
    @State private var livePulse = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                HeaderBar(title: "Server", trailing: "plus", trailingAction: onAddServer)

                ServeraCard {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("服务器花园")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.serveraTextSecondary)
                            Text(devices.isEmpty ? "还没有 SSH 服务器，先添加一台服务器" : "\(devices.count) 台服务器在线，\(devices.filter(\.warning).count) 个状态需要关注")
                                .font(.system(size: 26, weight: .heavy))
                                .lineLimit(2)
                        }
                        Spacer()
                        StatusPill(text: devices.isEmpty ? "健康 -" : "健康 \(gardenHealthScore)", color: devices.contains(where: \.warning) ? .serveraAmber : .serveraLeaf)
                    }
                }

                HStack {
                    Text("服务器星图")
                        .font(.system(size: 18, weight: .heavy))
                    Spacer()
                    if !orderedDevices.isEmpty {
                        Text(orderedDevices.count > 1 ? "拖动漂移 · 点击进入详情" : "点击进入详情")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.serveraTextSecondary)
                    }
                }

                if devices.isEmpty {
                    ServeraCard(cornerRadius: 30) {
                        VStack(spacing: 12) {
                            Image(systemName: "plus.rectangle.on.folder")
                                .font(.system(size: 38, weight: .heavy))
                                .foregroundStyle(Color.serveraAccentDeep)
                            Text("服务器会在这里生长出来")
                                .font(.system(size: 22, weight: .black))
                            Text("通过 SSH 添加的设备会显示在 Server 栏；通过 NAS 表单添加的群晖只显示在 NAS 栏。")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.serveraTextSecondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ServerOrbitGardenView(devices: orderedDevices, onSelect: onSelect)

                    VStack(spacing: 12) {
                        ForEach(orderedDevices) { device in
                            DashboardDeviceCard(
                                device: device,
                                isRefreshing: refreshingDeviceIDs.contains(device.id),
                                pulse: livePulse,
                                onRefresh: { onRefresh(device) },
                                onEdit: { onEdit(device) },
                                onDelete: { onDelete(device) }
                            )
                            .opacity(draggingDevice == device ? 0.64 : 1)
                            .scaleEffect(draggingDevice == device ? 0.975 : 1)
                            .shadow(color: draggingDevice == device ? Color.serveraAccent.opacity(0.22) : .clear, radius: 22, y: 14)
                            .overlay {
                                if draggingDevice == device {
                                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                                        .stroke(Color.serveraAccentDeep.opacity(0.42), lineWidth: 1.5)
                                }
                            }
                            .zIndex(draggingDevice == device ? 1 : 0)
                            .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                            .onTapGesture {
                                guard draggingDevice == nil else { return }
                                onSelect(device)
                            }
                            .onDrag {
                                draggingDevice = device
                                reconcileOrder(with: devices)
                                return NSItemProvider(object: device.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: DashboardDeviceDropDelegate(
                                    item: device,
                                    devices: orderedDevices,
                                    draggingDevice: $draggingDevice,
                                    orderedDeviceIDs: $orderedDeviceIDs,
                                    onCommit: commitCurrentOrder
                                )
                            )
                        }
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: DashboardDeviceListDropDelegate(
                            draggingDevice: $draggingDevice,
                            orderedDeviceIDs: $orderedDeviceIDs,
                            onCommit: commitCurrentOrder
                        )
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
        .onAppear {
            reconcileOrder(with: devices, force: orderedDeviceIDs.isEmpty)
        }
        .onChange(of: devices.map(\.id)) { _, _ in
            guard draggingDevice == nil else { return }
            reconcileOrder(with: devices)
        }
        .task {
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 1.2)) {
                    livePulse.toggle()
                }
                do { try await Task.sleep(for: .milliseconds(1200)) } catch { return }
            }
        }
        .task(id: autoRefreshSignature) {
            guard autoRefreshEnabled, !devices.isEmpty else { return }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }

            while !Task.isCancelled {
                guard autoRefreshEnabled else { return }
                guard draggingDevice == nil else {
                    do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
                    continue
                }
                for device in orderedDevices where draggingDevice == nil && !refreshingDeviceIDs.contains(device.id) {
                    onAutoRefresh(device)
                    do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                }
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
            }
        }
        .refreshable {
            await onRefreshAll()
        }
    }

    private var autoRefreshSignature: String {
        "\(autoRefreshEnabled)-" + devices.map { $0.id.uuidString }.joined(separator: ",")
    }

    private var orderedDevices: [DashboardDevice] {
        guard !orderedDeviceIDs.isEmpty else { return devices }
        let devicesByID = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
        let ordered = orderedDeviceIDs.compactMap { devicesByID[$0] }
        let orderedIDSet = Set(ordered.map(\.id))
        let appended = devices.filter { !orderedIDSet.contains($0.id) }
        return ordered + appended
    }

    private var gardenHealthScore: Int {
        guard !devices.isEmpty else { return 0 }
        let total = devices.reduce(0) { $0 + $1.healthScore }
        return max(0, min(100, total / devices.count))
    }

    private func reconcileOrder(with devices: [DashboardDevice], force: Bool = false) {
        let incomingIDs = devices.map(\.id)
        guard !force, !orderedDeviceIDs.isEmpty else {
            orderedDeviceIDs = incomingIDs
            return
        }

        let incomingIDSet = Set(incomingIDs)
        var reconciled = orderedDeviceIDs.filter { incomingIDSet.contains($0) }
        let reconciledIDSet = Set(reconciled)
        reconciled.append(contentsOf: incomingIDs.filter { !reconciledIDSet.contains($0) })
        orderedDeviceIDs = reconciled
    }

    private func commitCurrentOrder() {
        let visibleIDSet = Set(devices.map(\.id))
        let orderedIDs = orderedDeviceIDs.filter { visibleIDSet.contains($0) }
        draggingDevice = nil
        orderedDeviceIDs = orderedIDs
        onReorder(orderedIDs)
    }
}

struct DashboardDevice: Identifiable, Hashable {
    let id: UUID
    let name: String
    let subtitle: String
    let latency: String
    let cpu: Int
    let cpuValue: Double
    let ram: Int
    let docker: Int
    let dockerRunningCount: Int
    let dockerContainers: [DockerContainerSummary]
    let warning: Bool
    let kind: ManagedDeviceKind
    let credentialNeedsVerification: Bool
    let systemName: String
    let systemVersion: String
    let uptimeSeconds: Int64
    let cpuCoreCount: Int
    let cpuCorePercents: [Int]
    let cpuCorePercentValues: [Double]
    let cpuUserPercent: Int
    let cpuUserPercentValue: Double
    let cpuSystemPercent: Int
    let cpuSystemPercentValue: Double
    let cpuNicePercent: Int
    let cpuNicePercentValue: Double
    let cpuIOWaitPercent: Int
    let cpuIOWaitPercentValue: Double
    let cpuTemperatureCelsius: Int?
    let memoryTotalBytes: Int64
    let memoryUsedBytes: Int64
    let memoryAvailableBytes: Int64
    let memoryCachedBytes: Int64
    let memoryFreeBytes: Int64
    let swapTotalBytes: Int64
    let swapUsedBytes: Int64
    let diskTotalBytes: Int64
    let diskUsedBytes: Int64
    let diskAvailableBytes: Int64
    let diskDeviceName: String
    let diskFilesystemType: String
    let diskMountPoint: String
    let load1: Double
    let load5: Double
    let load15: Double
    let storageUsedPercent: Int
    let networkReceiveText: String
    let networkTransmitText: String
    let networkReceiveTotalText: String
    let networkTransmitTotalText: String
    let networkInterfaceName: String
    let primaryIPText: String
    let topProcesses: [ServerProcessSummary]
    let lastStatusCollectedAt: Date?
    let cpuDataAvailable: Bool
    let memoryDataAvailable: Bool
    let diskDataAvailable: Bool
    let networkDataAvailable: Bool
    let processDataAvailable: Bool
    let dockerDataAvailable: Bool
    let cpuErrorMessage: String
    let memoryErrorMessage: String
    let diskErrorMessage: String
    let networkErrorMessage: String
    let processErrorMessage: String
    let dockerErrorMessage: String
    let lastCollectionScriptKind: SSHCollectionScriptKind?
    let lastCollectionDurationMilliseconds: Int
    let lastRawStatusOutput: String
    let nasStorageVolumes: [SynologyStorageVolume]
    let nasControlPanelSnapshot: NASControlPanelSnapshot

    static func == (lhs: DashboardDevice, rhs: DashboardDevice) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var healthScore: Int {
        guard !credentialNeedsVerification else { return 0 }
        var score = 100
        if warning { score -= 12 }
        if cpu >= 90 { score -= 18 } else if cpu >= 75 { score -= 8 }
        if ram >= 90 { score -= 18 } else if ram >= 75 { score -= 8 }
        if storageUsedPercent >= 90 { score -= 22 } else if storageUsedPercent >= 80 { score -= 10 }
        return max(0, min(100, score))
    }

    var storageUsedText: String {
        guard diskUsedBytes > 0 else { return "-" }
        return ServerStatusParser.byteText(diskUsedBytes)
    }

    var storageAvailableText: String {
        guard diskAvailableBytes > 0 else { return "-" }
        return ServerStatusParser.byteText(diskAvailableBytes)
    }

    var hasUnavailableLiveModules: Bool {
        !cpuDataAvailable || !memoryDataAvailable || !networkDataAvailable
    }

    init(
        id: UUID = UUID(),
        name: String,
        subtitle: String,
        latency: String,
        cpu: Int,
        cpuValue: Double? = nil,
        ram: Int,
        docker: Int,
        dockerRunningCount: Int = 0,
        dockerContainers: [DockerContainerSummary] = [],
        warning: Bool,
        kind: ManagedDeviceKind,
        credentialNeedsVerification: Bool = false,
        systemName: String = "",
        systemVersion: String = "",
        uptimeSeconds: Int64 = 0,
        cpuCoreCount: Int = 0,
        cpuCorePercents: [Int] = [],
        cpuCorePercentValues: [Double] = [],
        cpuUserPercent: Int = 0,
        cpuUserPercentValue: Double? = nil,
        cpuSystemPercent: Int = 0,
        cpuSystemPercentValue: Double? = nil,
        cpuNicePercent: Int = 0,
        cpuNicePercentValue: Double? = nil,
        cpuIOWaitPercent: Int = 0,
        cpuIOWaitPercentValue: Double? = nil,
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
        topProcesses: [ServerProcessSummary] = [],
        lastStatusCollectedAt: Date? = nil,
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
        lastCollectionScriptKind: SSHCollectionScriptKind? = nil,
        lastCollectionDurationMilliseconds: Int = 0,
        lastRawStatusOutput: String = "",
        nasStorageVolumes: [SynologyStorageVolume] = [],
        nasControlPanelSnapshot: NASControlPanelSnapshot = .empty
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.latency = latency
        self.cpu = cpu
        self.cpuValue = cpuValue ?? Double(cpu)
        self.ram = ram
        self.docker = docker
        self.dockerRunningCount = dockerRunningCount
        self.dockerContainers = dockerContainers
        self.warning = warning
        self.kind = kind
        self.credentialNeedsVerification = credentialNeedsVerification
        self.systemName = systemName
        self.systemVersion = systemVersion
        self.uptimeSeconds = uptimeSeconds
        self.cpuCoreCount = cpuCoreCount
        self.cpuCorePercents = cpuCorePercents
        self.cpuCorePercentValues = cpuCorePercentValues.isEmpty ? cpuCorePercents.map(Double.init) : cpuCorePercentValues
        self.cpuUserPercent = cpuUserPercent
        self.cpuUserPercentValue = cpuUserPercentValue ?? Double(cpuUserPercent)
        self.cpuSystemPercent = cpuSystemPercent
        self.cpuSystemPercentValue = cpuSystemPercentValue ?? Double(cpuSystemPercent)
        self.cpuNicePercent = cpuNicePercent
        self.cpuNicePercentValue = cpuNicePercentValue ?? Double(cpuNicePercent)
        self.cpuIOWaitPercent = cpuIOWaitPercent
        self.cpuIOWaitPercentValue = cpuIOWaitPercentValue ?? Double(cpuIOWaitPercent)
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
        self.topProcesses = topProcesses
        self.lastStatusCollectedAt = lastStatusCollectedAt
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
        self.lastCollectionScriptKind = lastCollectionScriptKind
        self.lastCollectionDurationMilliseconds = lastCollectionDurationMilliseconds
        self.lastRawStatusOutput = lastRawStatusOutput
        self.nasStorageVolumes = nasStorageVolumes
        self.nasControlPanelSnapshot = nasControlPanelSnapshot
    }

    static let samples: [DashboardDevice] = [
        DashboardDevice(name: "Tokyo Compute", subtitle: "Ubuntu 24.04", latency: "29 ms", cpu: 34, ram: 58, docker: 12, warning: true, kind: .server),
        DashboardDevice(name: "DS423+ Home", subtitle: "Synology DSM", latency: "42%", cpu: 5, ram: 42, docker: 3, warning: false, kind: .nas),
        DashboardDevice(name: "Lab Node", subtitle: "Debian 12", latency: "63 ms", cpu: 18, ram: 35, docker: 5, warning: false, kind: .server),
        DashboardDevice(name: "Backup Vault", subtitle: "Storage", latency: "在线", cpu: 9, ram: 28, docker: 0, warning: false, kind: .server)
    ]
}

enum ManagedDeviceKind: String, CaseIterable, Identifiable, Hashable {
    case server = "SSH 服务器"
    case nas = "群晖 NAS"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .server: "server.rack"
        case .nas: "externaldrive.connected.to.line.below"
        }
    }
}

struct ServerOrbitGardenView: View {
    let devices: [DashboardDevice]
    let onSelect: (DashboardDevice) -> Void
    @State private var dragDistance: CGFloat = 0
    @State private var isDragging = false
    @State private var suppressTap = false
    @State private var dragTranslation: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let visibleDevices = Array(devices.prefix(5))
            ZStack {
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.serveraTintSoft.opacity(0.34), .white.opacity(0.25)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                ForEach(Array(visibleDevices.enumerated()), id: \.element.id) { index, device in
                    let placement = placement(for: index, count: visibleDevices.count, in: size)
                    let drift = parallaxOffset(for: index, strength: placement.parallax)
                    ServerBubbleClusterNode(
                        device: device,
                        diameter: placement.diameter,
                        accentIndex: index,
                        opacity: placement.opacity,
                        isDragging: isDragging
                    )
                        .position(x: placement.position.x + drift.width, y: placement.position.y + drift.height)
                        .zIndex(placement.depth)
                        .onTapGesture {
                            guard !suppressTap, dragDistance < 10 else { return }
                            onSelect(device)
                        }
                }

                if devices.count > 5 {
                    Text("+\(devices.count - 5)")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Color.serveraTextSecondary)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.72), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1))
                        .position(x: size.width - 48, y: 42)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
            .simultaneousGesture(bubbleDragGesture)
        }
        .frame(height: 258)
    }

    private var bubbleDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let distance = hypot(value.translation.width, value.translation.height)
                dragDistance = distance
                let horizontalDominant = abs(value.translation.width) > max(10, abs(value.translation.height) * 0.72)
                guard horizontalDominant || isDragging else { return }

                if !isDragging {
                    withAnimation(.easeOut(duration: 0.14)) {
                        isDragging = true
                    }
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dragTranslation = value.translation
                }
            }
            .onEnded { value in
                let finalDistance = hypot(value.translation.width, value.translation.height)
                withAnimation(.interpolatingSpring(stiffness: 150, damping: 22)) {
                    isDragging = false
                    dragTranslation = .zero
                }
                dragDistance = finalDistance
                if finalDistance > 10 {
                    suppressTap = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        suppressTap = false
                        if dragDistance == finalDistance {
                            dragDistance = 0
                        }
                    }
                } else {
                    dragDistance = 0
                }
            }
    }

    private func placement(for index: Int, count: Int, in size: CGSize) -> OrbitPlacement {
        let spec = layoutSpec(index: index, count: count)
        let x = size.width * spec.anchor.x
        let y = size.height * spec.anchor.y
        return OrbitPlacement(
            position: CGPoint(x: clamped(x, lower: 62, upper: size.width - 62), y: clamped(y, lower: 56, upper: size.height - 52)),
            diameter: spec.diameter,
            opacity: 0.98,
            depth: spec.depth,
            parallax: spec.parallax
        )
    }

    private func parallaxOffset(for index: Int, strength: CGFloat) -> CGSize {
        let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
        let x = clamped(dragTranslation.width * strength * direction, lower: -16, upper: 16)
        let y = clamped(dragTranslation.height * strength * 0.45, lower: -8, upper: 8)
        return CGSize(width: x, height: y)
    }

    private func layoutSpec(index: Int, count: Int) -> BubbleClusterLayout {
        // 点位保持确定性。星群只是前五台服务器的视觉入口，不是物理布局；
        // 固定锚点可以避免刷新或 SwiftData 重新保存后首页跳动。
        let layouts: [[BubbleClusterLayout]] = [
            [.init(anchor: CGPoint(x: 0.54, y: 0.50), diameter: 88, depth: 2, parallax: 0.16)],
            [
                .init(anchor: CGPoint(x: 0.34, y: 0.46), diameter: 90, depth: 3, parallax: 0.18),
                .init(anchor: CGPoint(x: 0.68, y: 0.55), diameter: 74, depth: 2, parallax: 0.13)
            ],
            [
                .init(anchor: CGPoint(x: 0.31, y: 0.45), diameter: 88, depth: 4, parallax: 0.18),
                .init(anchor: CGPoint(x: 0.70, y: 0.35), diameter: 62, depth: 2, parallax: 0.12),
                .init(anchor: CGPoint(x: 0.56, y: 0.70), diameter: 72, depth: 3, parallax: 0.15)
            ],
            [
                .init(anchor: CGPoint(x: 0.30, y: 0.45), diameter: 88, depth: 5, parallax: 0.18),
                .init(anchor: CGPoint(x: 0.70, y: 0.39), diameter: 68, depth: 3, parallax: 0.12),
                .init(anchor: CGPoint(x: 0.56, y: 0.72), diameter: 74, depth: 4, parallax: 0.15),
                .init(anchor: CGPoint(x: 0.62, y: 0.18), diameter: 58, depth: 2, parallax: 0.1)
            ],
            [
                .init(anchor: CGPoint(x: 0.29, y: 0.45), diameter: 88, depth: 5, parallax: 0.18),
                .init(anchor: CGPoint(x: 0.71, y: 0.42), diameter: 66, depth: 4, parallax: 0.12),
                .init(anchor: CGPoint(x: 0.55, y: 0.72), diameter: 72, depth: 4, parallax: 0.15),
                .init(anchor: CGPoint(x: 0.62, y: 0.18), diameter: 58, depth: 2, parallax: 0.1),
                .init(anchor: CGPoint(x: 0.42, y: 0.26), diameter: 54, depth: 1, parallax: 0.14)
            ]
        ]
        return layouts[max(0, min(count, 5)) - 1][index]
    }

    private func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}

private struct OrbitPlacement {
    let position: CGPoint
    let diameter: CGFloat
    let opacity: CGFloat
    let depth: Double
    let parallax: CGFloat
}

private struct BubbleClusterLayout {
    let anchor: CGPoint
    let diameter: CGFloat
    let depth: Double
    let parallax: CGFloat
}

struct ServerBubbleClusterNode: View {
    let device: DashboardDevice
    let diameter: CGFloat
    let accentIndex: Int
    let opacity: CGFloat
    let isDragging: Bool

    var body: some View {
        ZStack {
            ForEach(Array(bubbles.enumerated()), id: \.offset) { _, bubble in
                Circle()
                    .fill(bubble.color.opacity(bubble.opacity))
                    .frame(width: bubble.size, height: bubble.size)
                    .overlay(Circle().stroke(.white.opacity(0.28), lineWidth: 0.8))
                    .offset(bubble.offset)
                    .blur(radius: bubble.blur)
                    .zIndex(bubble.zIndex)
            }

            Circle()
                .fill(.white.opacity(0.94))
                .frame(width: diameter, height: diameter)
                .overlay(Circle().stroke(statusColor.opacity(device.warning ? 0.3 : 0.14), lineWidth: device.warning ? 2 : 1))
                .shadow(color: Color.serveraAccent.opacity(0.12), radius: 16, y: 8)
                .overlay {
                    VStack(spacing: diameter < 66 ? 1 : 2) {
                        Text(shortName)
                            .font(.system(size: diameter < 66 ? 11 : 13, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                        Text(device.latency)
                            .font(.system(size: diameter < 66 ? 9 : 11, weight: .semibold))
                            .foregroundStyle(Color.serveraTextSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 9)
                }
                .zIndex(3)

            Circle()
                .fill(statusColor)
                .frame(width: max(8, diameter * 0.13), height: max(8, diameter * 0.13))
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.8))
                .shadow(color: statusColor.opacity(0.26), radius: 5)
                .offset(x: diameter * 0.34, y: -diameter * 0.32)
                .zIndex(4)
        }
        .frame(width: 154, height: 144)
        .scaleEffect(isDragging ? 1.018 : 1)
        .opacity(opacity)
        .shadow(color: isDragging ? Color.serveraAccent.opacity(0.1) : .clear, radius: isDragging ? 14 : 0, y: isDragging ? 8 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isDragging)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.name)，\(device.latency)")
    }

    private var statusColor: Color {
        device.warning ? .serveraAmber : .serveraLeaf
    }

    private var shortName: String {
        String(device.name.split(separator: " ").first ?? Substring(device.name.prefix(4)))
    }

    private var bubbles: [ClusterBubble] {
        let palettes: [[Color]] = [
            [.serveraSky, .serveraAmber, .serveraLeaf, .serveraTint],
            [.serveraLeaf, .serveraSky, .serveraTint, .white],
            [.serveraTint, .serveraAmber, .white, .serveraSky],
            [.serveraSky, .white, .serveraLeaf, .serveraTint],
            [.serveraAmber, .serveraLeaf, .serveraSky, .white]
        ]
        let colors = palettes[accentIndex % palettes.count]
        let d = diameter
        return [
            ClusterBubble(size: d * 0.74, offset: CGSize(width: -d * 0.42, height: -d * 0.1), color: colors[0], opacity: 0.28, blur: 0, zIndex: 0),
            ClusterBubble(size: d * 0.58, offset: CGSize(width: -d * 0.18, height: -d * 0.42), color: colors[1], opacity: 0.24, blur: 0, zIndex: 0),
            ClusterBubble(size: d * 0.56, offset: CGSize(width: d * 0.42, height: -d * 0.1), color: colors[2], opacity: 0.2, blur: 0, zIndex: 0),
            ClusterBubble(size: d * 0.62, offset: CGSize(width: -d * 0.12, height: d * 0.38), color: colors[3], opacity: 0.16, blur: 0.4, zIndex: 0),
            ClusterBubble(size: d * 0.38, offset: CGSize(width: d * 0.52, height: d * 0.28), color: .white, opacity: 0.26, blur: 0.5, zIndex: 1)
        ]
    }
}

private struct ClusterBubble {
    let size: CGFloat
    let offset: CGSize
    let color: Color
    let opacity: Double
    let blur: CGFloat
    let zIndex: Double
}

struct MetricChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.serveraTextSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Color.serveraTintSoft, in: Capsule())
    }
}

struct DashboardDeviceCard: View {
    let device: DashboardDevice
    var isRefreshing: Bool = false
    var pulse: Bool = false
    var onRefresh: () -> Void = {}
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        ServeraCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ServerCardGlyph(device: device, pulse: pulse, isRefreshing: isRefreshing)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name)
                            .font(.system(size: 22, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text(device.subtitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.serveraTextSecondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        StatusPill(text: device.latency, color: device.warning ? .serveraAmber : .serveraLeaf)
                        Menu {
                            Button(action: onRefresh) {
                                Label("刷新状态", systemImage: "arrow.clockwise")
                            }
                            Button(action: onEdit) {
                                Label("编辑连接", systemImage: "pencil")
                            }
                            Button(role: .destructive, action: onDelete) {
                                Label("删除服务器", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: isRefreshing ? "hourglass" : "ellipsis")
                                .font(.system(size: 16, weight: .black))
                                .foregroundStyle(Color.serveraTextSecondary.opacity(0.72))
                                .frame(width: 42, height: 32)
                                .background(.white.opacity(0.64), in: Capsule())
                                .symbolEffect(.pulse, value: isRefreshing ? pulse : false)
                        }
                        .disabled(isRefreshing)
                    }
                }

                HardwareSummaryStrip(device: device, pulse: pulse || isRefreshing)

                CardLiveStatusPanel(device: device, pulse: pulse)
            }
        }
    }
}

struct ServerCardGlyph: View {
    let device: DashboardDevice
    let pulse: Bool
    let isRefreshing: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 19, style: .continuous)
            .fill(
                LinearGradient(
                    colors: device.warning ? [.serveraAmber.opacity(0.82), .serveraTint] : [.serveraSky, .serveraLeaf],
                    startPoint: pulse ? .topTrailing : .topLeading,
                    endPoint: pulse ? .bottomLeading : .bottomTrailing
                )
            )
            .frame(width: 58, height: 58)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(.white.opacity(pulse ? 0.36 : 0.12))
                    .frame(width: 30, height: 30)
                    .blur(radius: 8)
                    .offset(x: pulse ? -4 : 8, y: pulse ? 4 : -8)
            }
            .overlay {
                Image(systemName: device.warning ? "exclamationmark" : device.kind.icon)
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, value: isRefreshing ? pulse : false)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(.white.opacity(pulse ? 0.9 : 0.54), lineWidth: 1)
            )
            .shadow(color: (device.warning ? Color.serveraAmber : Color.serveraLeaf).opacity(pulse ? 0.24 : 0.12), radius: pulse ? 18 : 10, y: 8)
    }
}

struct HardwareSummaryStrip: View {
    let device: DashboardDevice
    let pulse: Bool

    var body: some View {
        HStack(spacing: 7) {
            HardwareLeafMetric(icon: "cpu", title: "核心", value: coreValue, unit: "核", color: .serveraSky, pulse: pulse)
            HardwareLeafMetric(icon: "memorychip", title: "内存", value: memoryValue, unit: "", color: .serveraAccentDeep, pulse: pulse)
            HardwareLeafMetric(icon: "internaldrive", title: "硬盘", value: diskValue, unit: "", color: .serveraLeaf, pulse: pulse)
            HardwareLeafMetric(icon: "power", title: "运行", value: uptimeValue, unit: uptimeUnit, color: .serveraAmber, pulse: pulse)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.serveraTintSoft.opacity(0.72), .white.opacity(0.62), .serveraLeafSoft.opacity(0.34)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.white.opacity(pulse ? 0.22 : 0.06))
                        .frame(width: pulse ? 180 : 58)
                        .blur(radius: 16)
                        .offset(x: pulse ? 166 : -48)
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.serveraBorder.opacity(0.62), lineWidth: 1)
        )
    }

    private var coreValue: String {
        device.cpuCoreCount > 0 ? "\(device.cpuCoreCount)" : "-"
    }

    private var memoryValue: String {
        device.memoryTotalBytes > 0 ? hardwareMemoryText(device.memoryTotalBytes) : "-"
    }

    private var diskValue: String {
        device.diskTotalBytes > 0 ? ServerStatusParser.byteText(device.diskTotalBytes) : "-"
    }

    private var uptimeValue: String {
        guard device.uptimeSeconds > 0 else { return "-" }
        if device.uptimeSeconds >= 86_400 { return "\(device.uptimeSeconds / 86_400)" }
        if device.uptimeSeconds >= 3_600 { return "\(device.uptimeSeconds / 3_600)" }
        return "\(max(1, device.uptimeSeconds / 60))"
    }

    private var uptimeUnit: String {
        guard device.uptimeSeconds > 0 else { return "" }
        if device.uptimeSeconds >= 86_400 { return "天" }
        if device.uptimeSeconds >= 3_600 { return "小时" }
        return "分钟"
    }

    private func hardwareMemoryText(_ bytes: Int64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        guard gib >= 1 else { return ServerStatusParser.byteText(bytes) }

        let nearestAdvertisedSize = gib.rounded(.toNearestOrAwayFromZero)
        let shortfallRatio = (nearestAdvertisedSize - gib) / nearestAdvertisedSize
        if nearestAdvertisedSize >= gib, shortfallRatio >= 0, shortfallRatio <= 0.12 {
            return "\(Int(nearestAdvertisedSize))G"
        }

        return ServerStatusParser.byteText(bytes)
    }
}

struct HardwareLeafMetric: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let color: Color
    let pulse: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(color)
                    .symbolEffect(.pulse, value: pulse)
                Text(title)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Color.serveraTextSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.54), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct CardLiveStatusPanel: View {
    let device: DashboardDevice
    let pulse: Bool

    var body: some View {
        HStack(spacing: 10) {
            MiniStatusRing(title: "CPU", value: device.cpuValue, color: .serveraSky, pulse: pulse, isAvailable: device.cpuDataAvailable)
                .id("cpu-\(device.cpuValue)")
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            MiniStatusRing(title: "RAM", value: Double(device.ram), color: .serveraAccentDeep, pulse: pulse, isAvailable: device.memoryDataAvailable)
                .id("ram-\(device.ram)")
                .transition(.scale(scale: 0.96).combined(with: .opacity))

            VStack(spacing: 8) {
                LiveStatusLine(icon: "arrow.down.circle.fill", title: "网络", value: device.networkDataAvailable ? "↓\(device.networkReceiveText)  ↑\(device.networkTransmitText)" : "等待刷新", color: .serveraSky, pulse: pulse)
                    .id("net-\(device.networkReceiveText)-\(device.networkTransmitText)")
                    .transition(.move(edge: .top).combined(with: .opacity))
                LiveStatusLine(icon: "shippingbox.fill", title: "Docker", value: device.dockerDataAvailable ? (device.docker > 0 ? "\(device.docker) 个容器" : "0 个容器") : "等待刷新", color: .serveraLeaf, pulse: pulse)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: device.networkReceiveText)
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: device.networkTransmitText)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: device.cpuValue)
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: device.ram)
    }
}

struct MiniStatusRing: View {
    let title: String
    let value: Double
    let color: Color
    let pulse: Bool
    var isAvailable: Bool = true

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(Color.serveraBorder.opacity(0.42), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: isAvailable ? CGFloat(min(max(value, 0), 100)) / 100 : 0)
                    .stroke(
                        LinearGradient(colors: [color.opacity(0.48), color], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(pulse ? 0.24 : 0.08), radius: pulse ? 8 : 3)
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                    Circle()
                        .trim(from: 0, to: 0.13)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.2), color.opacity(0.72), .white.opacity(0.08)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(phase * 360 - 90))
                        .opacity(isAvailable ? (value > 0 ? 0.92 : 0.34) : 0.18)
                        .blur(radius: 0.2)
                }
                Text(isAvailable ? percentText : "-")
                    .font(.system(size: 12, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .contentTransition(.numericText())
                    .scaleEffect(pulse ? 1.08 : 0.98)
                    .animation(.spring(response: 0.32, dampingFraction: 0.58), value: pulse)
                    .animation(.spring(response: 0.36, dampingFraction: 0.68), value: value)
            }
            .frame(width: 52, height: 52)
            Text(title)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color.serveraTextSecondary)
        }
        .frame(width: 62)
        .padding(.vertical, 8)
        .background(.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .scaleEffect(pulse ? 1.015 : 0.995)
        .animation(.easeInOut(duration: 1.2), value: pulse)
    }

    private var percentText: String {
        if value <= 0 { return "0%" }
        if value < 10 { return String(format: "%.1f%%", value) }
        return String(format: "%.0f%%", value.rounded())
    }
}

struct LiveStatusLine: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    let pulse: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.12), in: Circle())
                .symbolEffect(.pulse, value: pulse)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.serveraTextSecondary)
                Text(value)
                    .font(.system(size: 13, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .contentTransition(.numericText())
                    .scaleEffect(pulse ? 1.035 : 0.985, anchor: .leading)
                    .animation(.spring(response: 0.32, dampingFraction: 0.62), value: pulse)
                    .animation(.spring(response: 0.36, dampingFraction: 0.72), value: value)
            }
            Spacer(minLength: 0)
            Circle()
                .fill(color.opacity(pulse ? 0.9 : 0.42))
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(pulse ? 0.35 : 0), radius: pulse ? 8 : 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            NetworkFlowTrace(color: color, pulse: pulse)
                .padding(.leading, 40)
                .padding(.bottom, 5)
        }
    }
}

struct NetworkFlowTrace: View {
    let color: Color
    let pulse: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let progress = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.35) / 1.35
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(pulse ? 0.22 : 0.12))
                    .frame(width: 82, height: 2)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.clear, color.opacity(0.86), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 26, height: 2.5)
                    .offset(x: progress * 56)
            }
        }
        .frame(width: 82, height: 3)
    }
}

struct ServerDetailView: View {
    let initialDevice: DashboardDevice
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var device: DashboardDevice
    @State private var isRefreshing = false
    @State private var refreshError: String?
    @State private var refreshTask: Task<Void, Never>?
    @State private var livePulse = false
    @State private var clock = Date()
    @State private var dockerDetailDevice: DashboardDevice?
    @State private var diagnosticsDevice: DashboardDevice?
    @State private var terminalDevice: DashboardDevice?
    @State private var lastFullRefreshAt: Date?
    @State private var refreshViewState: ServerRefreshViewState = .idle
    @State private var detailModuleOrder: [ServerDetailModule] = []
    @State private var draggingDetailModule: ServerDetailModule?

    init(device: DashboardDevice, onEdit: @escaping () -> Void = {}, onDelete: @escaping () -> Void = {}) {
        self.initialDevice = device
        self.onEdit = onEdit
        self.onDelete = onDelete
        _device = State(initialValue: device)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                DetailTopBar(
                    title: device.name,
                    subtitle: refreshSubtitle,
                    isRefreshing: isRefreshing,
                    onRefresh: refreshStatus,
                    onDiagnostics: { diagnosticsDevice = device },
                    onEdit: onEdit,
                    onDelete: onDelete
                ) {
                    dismiss()
                }

                ServerHeroCard(device: device, isVisible: isVisible)
                TerminalLaunchCard {
                    stopAutoRefresh()
                    terminalDevice = device
                }
                OperationalSnapshotRail(device: device, pulse: livePulse)

                HStack {
                    Text("状态模块")
                        .font(.system(size: 18, weight: .heavy))
                    Spacer()
                    Text(draggingDetailModule == nil ? "长按拖拽排序" : "松手保存顺序")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(draggingDetailModule == nil ? Color.serveraTextSecondary : Color.serveraAccentDeep)
                        .contentTransition(.opacity)
                }
                .padding(.top, 2)

                VStack(spacing: 16) {
                    ForEach(orderedDetailModules) { module in
                        detailModuleView(for: module)
                            .opacity(draggingDetailModule == module ? 0.66 : 1)
                            .scaleEffect(draggingDetailModule == module ? 0.975 : 1)
                            .shadow(color: draggingDetailModule == module ? Color.serveraAccent.opacity(0.22) : .clear, radius: 22, y: 14)
                            .overlay {
                                if draggingDetailModule == module {
                                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                                        .stroke(Color.serveraAccentDeep.opacity(0.42), lineWidth: 1.5)
                                }
                            }
                            .zIndex(draggingDetailModule == module ? 1 : 0)
                            .onDrag {
                                draggingDetailModule = module
                                reconcileDetailModuleOrder(force: detailModuleOrder.isEmpty)
                                return NSItemProvider(object: module.rawValue as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: ServerDetailModuleDropDelegate(
                                    item: module,
                                    modules: orderedDetailModules,
                                    draggingModule: $draggingDetailModule,
                                    moduleOrder: $detailModuleOrder,
                                    onCommit: persistDetailModuleOrder
                                )
                            )
                    }
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: ServerDetailModuleListDropDelegate(
                        draggingModule: $draggingDetailModule,
                        moduleOrder: $detailModuleOrder,
                        onCommit: persistDetailModuleOrder
                    )
                )

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .background(ServeraBackground().ignoresSafeArea())
        .overlay(alignment: .top) {
            TopSafeAreaMist()
        }
        .onAppear {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.84)) {
                isVisible = true
            }
            loadDetailModuleOrder()
            startAutoRefresh()
        }
        .task {
            while !Task.isCancelled {
                clock = .now
                withAnimation(.easeInOut(duration: 1.15)) {
                    livePulse.toggle()
                }
                do {
                    try await Task.sleep(for: .milliseconds(1150))
                } catch {
                    return
                }
            }
        }
        .onDisappear {
            stopAutoRefresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                startAutoRefresh()
            } else {
                stopAutoRefresh()
            }
        }
        .alert("刷新失败", isPresented: Binding(get: { refreshError != nil }, set: { if !$0 { refreshError = nil } })) {
            Button("知道了", role: .cancel) { refreshError = nil }
        } message: {
            Text(refreshError ?? "")
        }
        .refreshable {
            await refreshStatusManually()
        }
        .edgeSwipeBack(enabled: draggingDetailModule == nil) {
            dismiss()
        }
        .onChange(of: device.id) { _, _ in
            loadDetailModuleOrder()
        }
        .onChange(of: device.docker) { _, _ in
            reconcileDetailModuleOrder()
        }
        .onChange(of: device.dockerContainers.count) { _, _ in
            reconcileDetailModuleOrder()
        }
        .sheet(item: $dockerDetailDevice) { device in
            DockerDetailSheet(device: device)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $diagnosticsDevice) { device in
            ServerCollectionDiagnosticsSheet(device: device)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $terminalDevice, onDismiss: {
            if scenePhase == .active {
                startAutoRefresh(runImmediately: false)
            }
        }) { device in
            ServerTerminalView(device: device)
        }
    }

    private var refreshSubtitle: String {
        switch refreshViewState {
        case .refreshingFull:
            return "正在完整刷新"
        case .refreshingLive:
            return "正在轻量刷新"
        case .failed:
            return "刷新失败"
        case .partial, .idle:
            break
        }
        guard let collectedAt = device.lastStatusCollectedAt else { return "等待首次采集" }
        let seconds = max(0, Int(clock.timeIntervalSince(collectedAt)))
        let prefix = refreshViewState == .partial || hasUnavailableLiveModules ? "部分数据不可用 · " : ""
        if seconds < 60 { return "\(prefix)最后更新 \(seconds) 秒前" }
        return "\(prefix)最后更新 \(seconds / 60) 分钟前"
    }

    private var visibleDetailModules: [ServerDetailModule] {
        ServerDetailModule.allCases.filter { module in
            switch module {
            case .docker:
                return true
            default:
                return true
            }
        }
    }

    private var orderedDetailModules: [ServerDetailModule] {
        guard !detailModuleOrder.isEmpty else { return visibleDetailModules }
        let visibleSet = Set(visibleDetailModules)
        let ordered = detailModuleOrder.filter { visibleSet.contains($0) }
        let orderedSet = Set(ordered)
        return ordered + visibleDetailModules.filter { !orderedSet.contains($0) }
    }

    private var hasUnavailableLiveModules: Bool {
        device.hasUnavailableLiveModules
    }

    @ViewBuilder
    private func detailModuleView(for module: ServerDetailModule) -> some View {
        switch module {
        case .cpuCores:
            CPUCoreMatrixCard(device: device, isVisible: isVisible, pulse: livePulse)
        case .cpuLoad:
            CPULoadCard(device: device, isVisible: isVisible, pulse: livePulse)
        case .memory:
            MemoryInsightCard(device: device, isVisible: isVisible, pulse: livePulse)
        case .process:
            ProcessSnapshotCard(device: device, pulse: livePulse)
        case .network:
            NetworkSnapshotCard(device: device, pulse: livePulse)
        case .storage:
            StorageSnapshotCard(device: device, pulse: livePulse)
        case .docker:
            DockerOverviewCard(device: device, pulse: livePulse) {
                dockerDetailDevice = device
            }
        }
    }

    private var detailModuleOrderKey: String {
        "Servera.ServerDetailModuleOrder.\(device.id.uuidString)"
    }

    private func loadDetailModuleOrder() {
        let storedRawValues = UserDefaults.standard.stringArray(forKey: detailModuleOrderKey) ?? []
        let storedModules = storedRawValues.compactMap(ServerDetailModule.init(rawValue:))
        detailModuleOrder = storedModules.isEmpty ? visibleDetailModules : reconciledDetailModules(from: storedModules)
    }

    private func reconcileDetailModuleOrder(force: Bool = false) {
        if force || detailModuleOrder.isEmpty {
            detailModuleOrder = visibleDetailModules
            return
        }
        detailModuleOrder = reconciledDetailModules(from: detailModuleOrder)
    }

    private func reconciledDetailModules(from modules: [ServerDetailModule]) -> [ServerDetailModule] {
        let visibleSet = Set(visibleDetailModules)
        let filtered = modules.filter { visibleSet.contains($0) }
        let filteredSet = Set(filtered)
        return filtered + visibleDetailModules.filter { !filteredSet.contains($0) }
    }

    private func persistDetailModuleOrder() {
        let finalOrder = reconciledDetailModules(from: detailModuleOrder)
        draggingDetailModule = nil
        detailModuleOrder = finalOrder
        UserDefaults.standard.set(finalOrder.map(\.rawValue), forKey: detailModuleOrderKey)
    }

    private func refreshStatus() {
        Task {
            await refreshStatusManually()
        }
    }

    private func startAutoRefresh(runImmediately: Bool = true) {
        guard refreshTask == nil else { return }
        refreshTask = Task {
            if runImmediately {
                await refreshStatusNow(mode: .full, showErrors: false)
            }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(4))
                } catch {
                    return
                }
                let isSortingModules = await MainActor.run { draggingDetailModule != nil }
                if isSortingModules { continue }
                let needsFull = await MainActor.run {
                    lastFullRefreshAt.map { Date().timeIntervalSince($0) >= 60 } ?? true
                }
                await refreshStatusNow(mode: needsFull ? .full : .live, showErrors: false)
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    @MainActor
    private func refreshStatusManually() async {
        let shouldResumeAutoRefresh = refreshTask != nil && scenePhase == .active
        stopAutoRefresh()

        var waitAttempts = 0
        while isRefreshing && waitAttempts < 12 {
            try? await Task.sleep(for: .milliseconds(90))
            waitAttempts += 1
        }

        if !isRefreshing {
            await refreshStatusNow(mode: .full, showErrors: true)
        }

        if shouldResumeAutoRefresh {
            startAutoRefresh(runImmediately: false)
        }
    }

    @MainActor
    private func refreshStatusNow(mode: ServerRefreshMode, showErrors: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshViewState = mode == .full ? .refreshingFull : .refreshingLive
        defer {
            isRefreshing = false
        }

        do {
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

            let request = SSHConnectionRequest(
                host: record.host,
                port: record.port,
                username: record.account,
                authenticationKind: record.authenticationKind,
                credential: credential,
                acceptUnknownHostKey: false
            )
            switch mode {
            case .full:
                let outcome = try await SSHConnectionService.shared.validateAndCollect(request: request)
                record.applyServerSnapshot(outcome)
                lastFullRefreshAt = outcome.status.collectedAt
            case .live:
                let outcome = try await SSHConnectionService.shared.collectLiveMetrics(request: request)
                record.applyLiveMetricsSnapshot(outcome)
            }
            try modelContext.save()
            let updatedDevice = record.dashboardDevice
            withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
                device = updatedDevice
            }
            refreshViewState = updatedDevice.hasUnavailableLiveModules ? .partial : .idle
        } catch {
            if showErrors, !error.isRefreshCancellation {
                refreshError = error.localizedDescription
                refreshViewState = .failed
            } else {
                refreshViewState = hasUnavailableLiveModules ? .partial : .idle
            }
        }
    }
}

private enum ServerRefreshMode {
    case full
    case live
}

private enum ServerRefreshViewState {
    case idle
    case refreshingFull
    case refreshingLive
    case failed
    case partial
}

private enum ServerDetailModule: String, CaseIterable, Identifiable, Hashable {
    case cpuCores
    case cpuLoad
    case memory
    case process
    case network
    case storage
    case docker

    var id: String { rawValue }
}

private struct ServerDetailModuleDropDelegate: DropDelegate {
    let item: ServerDetailModule
    let modules: [ServerDetailModule]
    @Binding var draggingModule: ServerDetailModule?
    @Binding var moduleOrder: [ServerDetailModule]
    let onCommit: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingModule, draggingModule != item else { return }
        if moduleOrder.isEmpty {
            moduleOrder = modules
        }

        guard let from = moduleOrder.firstIndex(of: draggingModule),
              let to = moduleOrder.firstIndex(of: item),
              from != to
        else { return }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            moduleOrder.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        onCommit()
        return true
    }
}

private struct ServerDetailModuleListDropDelegate: DropDelegate {
    @Binding var draggingModule: ServerDetailModule?
    @Binding var moduleOrder: [ServerDetailModule]
    let onCommit: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard draggingModule != nil else { return true }
        onCommit()
        return true
    }
}

private extension String {
    func nonEmptyOr(_ fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

private extension Error {
    var isRefreshCancellation: Bool {
        if self is CancellationError { return true }
        if let sshError = self as? ServeraSSHError { return sshError.isCancellation }
        return localizedDescription.localizedCaseInsensitiveContains("cancel")
            || localizedDescription.contains("取消")
    }
}

struct DetailTopBar: View {
    let title: String
    var subtitle: String? = nil
    var isRefreshing: Bool = false
    var onRefresh: (() -> Void)? = nil
    var onDiagnostics: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.76), in: Circle())
                    .shadow(color: Color.serveraAccent.opacity(0.14), radius: 16, y: 8)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .black))
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.serveraTextSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if onRefresh != nil || onDiagnostics != nil || onEdit != nil || onDelete != nil {
                Menu {
                    if let onRefresh {
                        Button(action: onRefresh) {
                            Label("刷新状态", systemImage: "arrow.clockwise")
                        }
                        .disabled(isRefreshing)
                    }
                    if let onDiagnostics {
                        Button(action: onDiagnostics) {
                            Label("采集诊断", systemImage: "stethoscope")
                        }
                    }
                    if let onEdit {
                        Button(action: onEdit) {
                            Label("编辑连接", systemImage: "pencil")
                        }
                    }
                    if let onDelete {
                        Button(role: .destructive, action: onDelete) {
                            Label("删除设备", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: isRefreshing ? "hourglass" : "ellipsis")
                        .font(.system(size: 18, weight: .black))
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.76), in: Circle())
                        .shadow(color: Color.serveraAccent.opacity(0.14), radius: 16, y: 8)
                        .rotationEffect(.degrees(isRefreshing ? 180 : 0))
                        .animation(.easeInOut(duration: 0.35), value: isRefreshing)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 48, height: 48)
            }
        }
    }
}

struct ServerCollectionDiagnosticsSheet: View {
    let device: DashboardDevice
    @State private var didCopyRawOutput = false

    private var modules: [(title: String, icon: String, available: Bool, message: String)] {
        [
            ("CPU", "cpu", device.cpuDataAvailable, device.cpuErrorMessage),
            ("内存", "memorychip", device.memoryDataAvailable, device.memoryErrorMessage),
            ("磁盘", "externaldrive", device.diskDataAvailable, device.diskErrorMessage),
            ("网络", "arrow.up.arrow.down", device.networkDataAvailable, device.networkErrorMessage),
            ("进程", "list.bullet.rectangle", device.processDataAvailable, device.processErrorMessage),
            ("Docker", "shippingbox", device.dockerDataAvailable, device.dockerErrorMessage)
        ]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("采集诊断")
                        .font(.system(size: 30, weight: .black))
                    Text(device.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.serveraTextSecondary)
                }
                .padding(.top, 8)

                ServeraCard(cornerRadius: 30) {
                    VStack(spacing: 14) {
                        DiagnosticsInfoRow(title: "脚本类型", value: scriptKindText)
                        DiagnosticsInfoRow(title: "命令耗时", value: durationText)
                        DiagnosticsInfoRow(title: "更新时间", value: collectedAtText)
                    }
                }

                ServeraCard(cornerRadius: 30) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("模块状态")
                            .font(.system(size: 18, weight: .black))

                        ForEach(modules, id: \.title) { module in
                            DiagnosticsModuleRow(
                                title: module.title,
                                icon: module.icon,
                                available: module.available,
                                message: module.message
                            )
                        }
                    }
                }

                ServeraCard(cornerRadius: 30) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Debug 原始输出")
                                .font(.system(size: 18, weight: .black))
                            Spacer()
                            if !device.lastRawStatusOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button {
                                    copyRawOutput()
                                } label: {
                                    Label(didCopyRawOutput ? "已复制" : "复制", systemImage: didCopyRawOutput ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 12, weight: .black))
                                        .foregroundStyle(Color.serveraAccentDeep)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(Color.serveraAccent.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            } else {
                                StatusPill(text: "暂无")
                            }
                        }

                        if device.lastRawStatusOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("暂无原始输出。Debug 构建刷新一次服务器后，这里会显示 SSH 脚本返回内容；Release 构建不会保存原始输出。")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.serveraTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ScrollView(.horizontal, showsIndicators: true) {
                                Text(device.lastRawStatusOutput)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color.primary.opacity(0.82))
                                    .textSelection(.enabled)
                                    .padding(12)
                                    .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .frame(maxHeight: 300)
                        }
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .background(ServeraBackground().ignoresSafeArea())
    }

    private var scriptKindText: String {
        switch device.lastCollectionScriptKind {
        case .full:
            return "完整采集"
        case .live:
            return "轻量采集"
        case nil:
            return "-"
        }
    }

    private var durationText: String {
        guard device.lastCollectionDurationMilliseconds > 0 else { return "-" }
        return "\(device.lastCollectionDurationMilliseconds) ms"
    }

    private var collectedAtText: String {
        guard let lastStatusCollectedAt = device.lastStatusCollectedAt else { return "-" }
        return lastStatusCollectedAt.formatted(date: .numeric, time: .standard)
    }

    private func copyRawOutput() {
        #if canImport(UIKit)
        UIPasteboard.general.string = device.lastRawStatusOutput
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            didCopyRawOutput = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    didCopyRawOutput = false
                }
            }
        }
        #endif
    }
}

struct DiagnosticsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.serveraTextSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

struct DiagnosticsModuleRow: View {
    let title: String
    let icon: String
    let available: Bool
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(statusColor)
                .frame(width: 30, height: 30)
                .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .black))
                if !available {
                    Text(message.nonEmptyOr("等待完整刷新"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.serveraTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            StatusPill(text: available ? "成功" : "不可用", color: statusColor)
        }
    }

    private var statusColor: Color {
        available ? .serveraLeaf : .serveraAmber
    }
}

struct TopSafeAreaMist: View {
    var body: some View {
        GeometryReader { proxy in
            let mistHeight = proxy.safeAreaInsets.top + 88

            VStack(spacing: 0) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        LinearGradient(
                            colors: [
                                .white.opacity(0.78),
                                .serveraTint.opacity(0.42),
                                .white.opacity(0.18),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black.opacity(0.96), location: 0.48),
                                .init(color: .black.opacity(0.36), location: 0.78),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .frame(height: mistHeight)

                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ServerHeroCard: View {
    let device: DashboardDevice
    let isVisible: Bool

    var body: some View {
        ServeraCard(cornerRadius: 34) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.serveraSky, .serveraLeaf, .serveraTint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 66, height: 66)
                    .overlay {
                        Image(systemName: device.kind.icon)
                            .font(.system(size: 27, weight: .black))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 7) {
                    Text(device.name)
                        .font(.system(size: 28, weight: .black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(device.subtitle)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    .foregroundStyle(Color.serveraTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 6) {
                    StatusPill(text: device.latency, color: device.warning ? .serveraAmber : .serveraLeaf)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(uptimeText)
                            .font(.system(size: 12, weight: .bold))
                        Text(device.credentialNeedsVerification ? "健康 -" : "健康 \(device.healthScore)")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(device.healthScore < 80 ? Color.serveraAmber : Color.serveraLeaf)
                    }
                    .foregroundStyle(Color.serveraTextSecondary)
                }
                .frame(width: 78, alignment: .trailing)
            }
        }
        .offset(y: isVisible ? 0 : 16)
        .opacity(isVisible ? 1 : 0)
    }

    private var uptimeText: String {
        guard device.uptimeSeconds > 0 else { return "运行 -" }
        return "运行 \(max(1, device.uptimeSeconds / 86_400)) 天"
    }
}

struct TerminalLaunchCard: View {
    var onOpen: () -> Void = {}

    var body: some View {
        Button {
            onOpen()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "terminal")
                    .font(.system(size: 21, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Color.serveraAccentDeep, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("终端")
                        .font(.system(size: 18, weight: .black))
                    Text("进入 SSH 终端会话")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.serveraTextSecondary)
                }

                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Color.serveraAccentDeep)
            }
            .padding(16)
            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.serveraBorder.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct OperationalSnapshotRail: View {
    let device: DashboardDevice
    var pulse: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            CompactStatusTile(title: "进程", value: device.processDataAvailable ? "\(device.topProcesses.count) 个热点" : "暂无数据", footnote: device.processDataAvailable ? "CPU 排序" : "等待完整刷新", icon: "slider.horizontal.3", color: .serveraAccent, pulse: pulse)
            CompactStatusTile(title: "网络", value: device.networkDataAvailable ? "↓\(device.networkReceiveText)" : "-", footnote: device.networkDataAvailable ? "↑\(device.networkTransmitText)" : "等待刷新", icon: "arrow.up.arrow.down", color: .serveraSky, pulse: pulse)
            CompactStatusTile(title: "存储", value: device.diskDataAvailable ? "\(device.storageUsedPercent)%" : "-", footnote: device.diskDataAvailable ? ServerStatusParser.byteText(device.diskTotalBytes) : "等待完整刷新", icon: "internaldrive", color: .serveraLeaf, pulse: pulse)
        }
    }
}

struct CompactStatusTile: View {
    let title: String
    let value: String
    let footnote: String
    let icon: String
    let color: Color
    var pulse: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(color)
                .symbolEffect(.pulse, value: pulse)
            Text(title)
                .font(.system(size: 12, weight: .black))
            Text(value)
                .font(.system(size: 17, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(footnote)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.serveraTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.serveraBorder.opacity(0.7), lineWidth: 1))
        .shadow(color: color.opacity(pulse ? 0.22 : 0.12), radius: pulse ? 24 : 18, y: 10)
    }
}

struct CPUCoreMatrixCard: View {
    let device: DashboardDevice
    let isVisible: Bool
    var pulse: Bool = false

    private var coreUsages: [Int] {
        if !device.cpuCorePercents.isEmpty { return device.cpuCorePercents }
        return []
    }

    private var coreUsageValues: [Double] {
        if !device.cpuCorePercentValues.isEmpty { return device.cpuCorePercentValues }
        return coreUsages.map(Double.init)
    }

    var body: some View {
        ServeraCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 16) {
                CardHeader(icon: "cpu", title: "CPU 核心活跃度", color: .serveraSky, trailing: samplingText)

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(device.cpuDataAvailable ? percentNumberText(device.cpuValue) : "-")
                            .font(.system(size: 48, weight: .black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.34, dampingFraction: 0.74), value: device.cpuValue)
                        Text("%")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.serveraTextSecondary)
                    }

                    if !device.cpuDataAvailable || coreUsageValues.isEmpty {
                        Text(device.cpuDataAvailable ? "暂无核心数据" : device.cpuErrorMessage.nonEmptyOr("等待 CPU 采样"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.serveraTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 18)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(coreUsageValues.indices, id: \.self) { row in
                                HStack(spacing: 4) {
                                    ForEach(0..<22, id: \.self) { column in
                                        Capsule()
                                            .fill(coreColor(row: row, column: column))
                                            .frame(width: 4, height: 16)
                                            .scaleEffect(y: coreScale(row: row, column: column), anchor: .bottom)
                                            .opacity(coreOpacity(row: row, column: column))
                                            .animation(.spring(response: 0.45, dampingFraction: 0.78).delay(Double(row + column) * 0.004), value: isVisible)
                                            .animation(.easeInOut(duration: 0.9).delay(Double((row + column) % 5) * 0.035), value: pulse)
                                    }
                                    Text(percentText(coreUsageValues[row]))
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.serveraTextSecondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                        .frame(width: 38, alignment: .trailing)
                                        .contentTransition(.numericText())
                                }
                            }
                        }
                        .padding(10)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color.serveraSky.opacity(pulse ? 0.12 : 0.05),
                                    Color.serveraAccent.opacity(pulse ? 0.08 : 0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.serveraSky.opacity(pulse ? 0.22 : 0.08), lineWidth: 1)
                        }
                    }
                }

                HStack(spacing: 12) {
                    LegendDot(color: .serveraSky, title: "User", value: percentText(device.cpuUserPercentValue))
                    LegendDot(color: .serveraAccent, title: "System", value: percentText(device.cpuSystemPercentValue))
                    LegendDot(color: .serveraLeaf, title: "Nice", value: percentText(device.cpuNicePercentValue))
                    LegendDot(color: .purple.opacity(0.75), title: "IOWait", value: percentText(device.cpuIOWaitPercentValue))
                }
            }
        }
    }

    private var samplingText: String {
        guard device.cpuDataAvailable else { return "采样中" }
        if device.cpuCoreCount > 0 { return "实时 · \(device.cpuCoreCount) 核" }
        return "采样中"
    }

    private var temperatureText: String {
        guard let temperature = device.cpuTemperatureCelsius else { return "" }
        return "\(temperature)°C"
    }

    private func coreColor(row: Int, column: Int) -> Color {
        let usage = coreUsageValues[row]
        let activeColumns = activeColumnCount(for: usage)
        guard column < activeColumns else { return Color.serveraBorder.opacity(0.26) }
        if usage <= 3 { return Color.serveraSky.opacity(pulse ? 0.74 : 0.48) }
        if column > activeColumns - 4 { return Color.serveraAccent.opacity(0.88) }
        if column == activeColumns - 5 { return Color.purple.opacity(0.68) }
        return Color.serveraSky.opacity(0.92)
    }

    private func coreScale(row: Int, column: Int) -> CGFloat {
        guard isVisible else { return 0.25 }
        let activeColumns = activeColumnCount(for: coreUsageValues[row])
        guard column < activeColumns else {
            return pulse && (row + column).isMultiple(of: 7) ? 0.98 : 0.9
        }
        if coreUsageValues[row] <= 3 {
            return pulse ? 1.08 : 0.96
        }
        return pulse && (row + column).isMultiple(of: 4) ? 1.14 : 1
    }

    private func coreOpacity(row: Int, column: Int) -> Double {
        let activeColumns = activeColumnCount(for: coreUsageValues[row])
        guard column < activeColumns else { return pulse ? 0.34 : 0.18 }
        if coreUsageValues[row] <= 3 {
            return pulse ? 0.84 : 0.54
        }
        return pulse && (row + column).isMultiple(of: 4) ? 1 : 0.88
    }

    private func activeColumnCount(for usage: Double) -> Int {
        guard usage > 0 else { return 0 }
        return max(1, Int(ceil(usage / 100 * 22)))
    }

    private func percentNumberText(_ value: Double) -> String {
        if value <= 0 { return "0" }
        if value < 10 { return String(format: "%.1f", value) }
        return String(format: "%.0f", value.rounded())
    }

    private func percentText(_ value: Double) -> String {
        "\(percentNumberText(value))%"
    }
}

struct CPULoadCard: View {
    let device: DashboardDevice
    let isVisible: Bool
    var pulse: Bool = false

    var body: some View {
        ServeraCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(icon: "waveform.path.ecg", title: "CPU 负载", color: .serveraAmber, trailing: String(format: "%.2f / %.2f / %.2f", device.load1, device.load5, device.load15))

                HStack(spacing: 7) {
                    Circle()
                        .fill(loadStateColor.opacity(pulse ? 0.9 : 0.68))
                        .frame(width: pulse ? 7 : 5, height: pulse ? 7 : 5)
                        .animation(.easeInOut(duration: 0.9), value: pulse)

                    Text(loadStateText)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(loadStateColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(loadStateColor.opacity(pulse ? 0.14 : 0.09), in: Capsule())

                VStack(spacing: 12) {
                    LoadSnapshotBar(label: "1m", value: device.load1, cores: device.cpuCoreCount, color: .serveraAccent, isVisible: isVisible && device.cpuDataAvailable, pulse: pulse)
                    LoadSnapshotBar(label: "5m", value: device.load5, cores: device.cpuCoreCount, color: .serveraSky, isVisible: isVisible && device.cpuDataAvailable, pulse: pulse)
                    LoadSnapshotBar(label: "15m", value: device.load15, cores: device.cpuCoreCount, color: .serveraAmber, isVisible: isVisible && device.cpuDataAvailable, pulse: pulse)
                }
                .padding(16)
                .background(Color.serveraTintSoft.opacity(0.28), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                HStack(spacing: 18) {
                    LegendDot(color: .serveraAccent, title: "1m", value: String(format: "%.2f", device.load1))
                    LegendDot(color: .serveraSky, title: "5m", value: String(format: "%.2f", device.load5))
                    LegendDot(color: .serveraAmber, title: "15m", value: String(format: "%.2f", device.load15))
                }
            }
        }
    }

    private var loadStateText: String {
        guard device.cpuDataAvailable, device.cpuCoreCount > 0 else {
            return "负载采样中"
        }

        let cores = "\(device.cpuCoreCount) 核"
        switch loadRatio {
        case ..<0.35:
            return "\(cores) · 轻松运行"
        case ..<0.75:
            return "\(cores) · 稳定承载"
        default:
            return "\(cores) · 压力偏高"
        }
    }

    private var loadStateColor: Color {
        guard device.cpuDataAvailable, device.cpuCoreCount > 0 else {
            return .serveraTextSecondary
        }

        switch loadRatio {
        case ..<0.35:
            return .serveraLeaf
        case ..<0.75:
            return .serveraAmber
        default:
            return .serveraAccentDeep
        }
    }

    private var loadRatio: Double {
        guard device.cpuCoreCount > 0 else { return 0 }
        return device.load1 / Double(device.cpuCoreCount)
    }
}

struct LoadSnapshotBar: View {
    let label: String
    let value: Double
    let cores: Int
    let color: Color
    let isVisible: Bool
    var pulse: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Color.serveraTextSecondary)
                .frame(width: 30, alignment: .leading)
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.serveraBorder.opacity(0.34))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color.opacity(0.32))
                            .frame(width: max(proxy.size.width * normalized, value > 0 ? 1.5 : 0))
                            .animation(.spring(response: 0.48, dampingFraction: 0.82), value: value)

                        Capsule()
                            .fill(LinearGradient(colors: [color.opacity(0.62), color], startPoint: .leading, endPoint: .trailing))
                            .frame(width: proxy.size.width * (isVisible ? visualNormalized : 0))
                            .opacity(value > 0 ? (normalized < 0.035 ? 0.58 : 0.88) : 0)
                            .overlay(alignment: .trailing) {
                                Circle()
                                    .fill(.white.opacity(pulse ? 0.9 : 0.36))
                                    .frame(width: 10, height: 10)
                                    .blur(radius: 1.2)
                                    .padding(.trailing, 2)
                            }
                            .animation(.spring(response: 0.48, dampingFraction: 0.82), value: value)
                            .animation(.easeInOut(duration: 1.1), value: pulse)
                    }
                    .overlay(alignment: .leading) {
                        if value > 0, normalized < 0.035 {
                            Circle()
                                .fill(color.opacity(pulse ? 0.72 : 0.38))
                                .frame(width: pulse ? 12 : 8, height: pulse ? 12 : 8)
                                .blur(radius: pulse ? 1.4 : 0.4)
                                .offset(x: 4)
                                .animation(.easeInOut(duration: 0.85), value: pulse)
                        }
                    }
            }
            .frame(height: 14)
            Text(String(format: "%.2f", value))
                .font(.system(size: 12, weight: .black))
                .frame(width: 44, alignment: .trailing)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.34, dampingFraction: 0.76), value: value)
        }
    }

    private var normalized: CGFloat {
        let denominator = max(Double(cores), 1)
        return CGFloat(min(max(value / denominator, 0), 1))
    }

    private var visualNormalized: CGFloat {
        guard value > 0 else { return 0 }
        return min(max(normalized, 0.035), 1)
    }
}

struct MemoryInsightCard: View {
    let device: DashboardDevice
    let isVisible: Bool
    var pulse: Bool = false

    var body: some View {
        ServeraCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 16) {
                CardHeader(
                    icon: "memorychip",
                    title: "内存结构",
                    color: .serveraAccentDeep,
                    trailing: device.memoryDataAvailable ? ServerStatusParser.byteText(device.memoryTotalBytes) : "-"
                )

                if !device.memoryDataAvailable {
                    MetricUnavailableState(
                        icon: "memorychip",
                        title: "暂无内存数据",
                        message: device.memoryErrorMessage.nonEmptyOr("等待下一次采集 /proc/meminfo。")
                    )
                } else {

                    HStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .stroke(Color.serveraBorder.opacity(0.5), lineWidth: 20)
                            Circle()
                                .trim(from: 0, to: isVisible ? CGFloat(device.ram) / 100 : 0)
                                .stroke(
                                    AngularGradient(colors: [.serveraAccentDeep, .serveraTint, .serveraAccentDeep], center: .center),
                                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                                )
                                .rotationEffect(.degrees(pulse ? -82 : -90))
                                .shadow(color: Color.serveraAccentDeep.opacity(pulse ? 0.24 : 0.12), radius: pulse ? 12 : 4)
                            Circle()
                                .trim(from: 0.68, to: isVisible ? 0.82 : 0.68)
                                .stroke(Color.serveraTextSecondary.opacity(0.32), style: StrokeStyle(lineWidth: 20, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 1) {
                                Text("Total")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.serveraTextSecondary)
                                Text(ServerStatusParser.byteText(device.memoryTotalBytes))
                                    .font(.system(size: 21, weight: .black))
                            }
                        }
                        .frame(width: 128, height: 128)

                        VStack(alignment: .leading, spacing: 14) {
                            MemoryLegend(color: .serveraAccentDeep, value: ServerStatusParser.byteText(device.memoryUsedBytes), label: "\(device.ram)% Used")
                            MemoryLegend(color: .serveraTextSecondary.opacity(0.5), value: ServerStatusParser.byteText(device.memoryCachedBytes), label: "\(percent(device.memoryCachedBytes, of: device.memoryTotalBytes))% Cached")
                            MemoryLegend(color: .serveraBorder, value: ServerStatusParser.byteText(device.memoryAvailableBytes), label: "\(percent(device.memoryAvailableBytes, of: device.memoryTotalBytes))% Available")
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("交换空间")
                                .font(.system(size: 16, weight: .black))
                            Spacer()
                            Text(swapText)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.serveraTextSecondary)
                        }
                        if device.swapTotalBytes > 0 {
                            MetricFillBar(value: isVisible ? swapProgress : 0, color: .serveraAccentDeep, pulse: pulse)
                        } else {
                            DisabledMetricStrip(text: swapHint)
                        }
                    }
                }
            }
        }
    }

    private var swapText: String {
        guard device.memoryTotalBytes > 0 else { return "暂无数据" }
        guard device.swapTotalBytes > 0 else { return "未启用" }
        return "\(ServerStatusParser.byteText(device.swapUsedBytes)) of \(ServerStatusParser.byteText(device.swapTotalBytes)) Used"
    }

    private var swapHint: String {
        guard device.memoryTotalBytes > 0 else { return "等待下一次采集内存信息" }
        return "这台服务器当前没有配置 Swap"
    }

    private var swapProgress: CGFloat {
        guard device.swapTotalBytes > 0 else { return 0 }
        return CGFloat(min(max(Double(device.swapUsedBytes) / Double(device.swapTotalBytes), 0), 1))
    }

    private func percent(_ value: Int64, of total: Int64) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(value) / Double(total) * 100).rounded())
    }
}

struct ProcessSnapshotCard: View {
    let device: DashboardDevice
    var pulse: Bool = false

    private var displayRows: [(String, String, String, String, String)] {
        return device.topProcesses.prefix(4).map {
            (
                "\($0.pid)",
                $0.command,
                $0.user,
                String(format: "%.1f", $0.cpuPercent),
                $0.memoryText
            )
        }
    }

    var body: some View {
        ServeraCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 13) {
                CardHeader(
                    icon: "slider.horizontal.3",
                    title: "进程快照",
                    color: .serveraAccent,
                    trailing: device.processDataAvailable ? "按 CPU" : "等待刷新"
                )
                HStack {
                    ProcessColumn("Pid", width: 48, alignment: .leading)
                    ProcessColumn("Process", width: 118, alignment: .leading)
                    ProcessColumn("User", width: 54, alignment: .leading)
                    ProcessColumn("CPU%", width: 48, alignment: .trailing)
                    ProcessColumn("Mem", width: 52, alignment: .trailing)
                }
                .foregroundStyle(Color.serveraAccentDeep)

                if displayRows.isEmpty {
                    MetricUnavailableState(
                        icon: "slider.horizontal.3",
                        title: device.processDataAvailable ? "暂无进程数据" : "等待完整刷新采集进程",
                        message: device.processDataAvailable ? "当前没有可展示的热点进程。" : device.processErrorMessage.nonEmptyOr("下拉刷新或等待 60 秒完整采集。")
                    )
                } else {
                    ForEach(displayRows, id: \.0) { row in
                        HStack {
                            ProcessColumn(row.0, width: 48, alignment: .leading)
                            ProcessColumn(row.1, width: 118, alignment: .leading)
                            ProcessColumn(row.2, width: 54, alignment: .leading)
                            ProcessColumn(row.3, width: 48, alignment: .trailing)
                            ProcessColumn(row.4, width: 52, alignment: .trailing)
                        }
                        .foregroundStyle(Color.serveraTextSecondary)
                        .opacity(pulse ? 0.82 : 1)
                        .animation(.easeInOut(duration: 0.7), value: pulse)
                    }
                }
            }
        }
    }
}

struct MetricUnavailableState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(Color.serveraTextSecondary)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.56), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct NetworkSnapshotCard: View {
    let device: DashboardDevice
    var pulse: Bool = false

    var body: some View {
        ServeraCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 15) {
                CardHeader(icon: "wifi", title: "网络使用情况", color: .serveraAmber, trailing: device.networkInterfaceName.isEmpty ? "-" : device.networkInterfaceName)

                if !device.networkDataAvailable {
                    MetricUnavailableState(
                        icon: "wifi.slash",
                        title: "暂无网络数据",
                        message: device.networkErrorMessage.nonEmptyOr("等待下一次采样默认网卡流量。")
                    )
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 104), spacing: 10),
                            GridItem(.flexible(minimum: 104), spacing: 10)
                        ],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        BigMetric(icon: "arrow.up.circle.fill", title: "上传速率", value: device.networkTransmitText, unit: "", color: .serveraAmber)
                        BigMetric(icon: "arrow.down.circle.fill", title: "下载速率", value: device.networkReceiveText, unit: "", color: .serveraSky)
                        BigMetric(icon: "arrow.up.circle.fill", title: "累计上传", value: device.networkTransmitTotalText, unit: "", color: .serveraAmber)
                        BigMetric(icon: "arrow.down.circle.fill", title: "累计下载", value: device.networkReceiveTotalText, unit: "", color: .serveraSky)
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 12) {
                            LegendDot(color: .serveraAmber, title: "上传", value: device.networkTransmitText)
                            LegendDot(color: .serveraSky, title: "下载", value: device.networkReceiveText)
                        }
                        Spacer()
                        ZStack {
                            Circle()
                                .stroke(Color.serveraBorder.opacity(0.58), lineWidth: 18)
                            Circle()
                                .trim(from: 0, to: 0.72)
                                .stroke(Color.serveraSky, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                                .rotationEffect(.degrees(pulse ? -62 : -90))
                            Circle()
                                .trim(from: 0.76, to: 0.96)
                                .stroke(Color.serveraAmber, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                                .rotationEffect(.degrees(pulse ? -72 : -90))
                        }
                        .frame(width: 90, height: 90)
                        .shadow(color: Color.serveraSky.opacity(pulse ? 0.24 : 0.08), radius: pulse ? 18 : 6)
                        .animation(.easeInOut(duration: 1.15), value: pulse)
                        Spacer()
                        VStack(alignment: .leading, spacing: 12) {
                            LegendDot(color: .serveraAmber.opacity(0.72), title: "累计上传", value: device.networkTransmitTotalText)
                            LegendDot(color: .serveraSky.opacity(0.72), title: "累计下载", value: device.networkReceiveTotalText)
                        }
                    }
                    if !device.primaryIPText.isEmpty {
                        Text(device.primaryIPText)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.serveraTextSecondary)
                    }
                }
            }
        }
    }
}

struct StorageSnapshotCard: View {
    let device: DashboardDevice
    var pulse: Bool = false

    var body: some View {
        ServeraCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(icon: "internaldrive", title: "存储", color: .serveraLeaf, trailing: device.diskFilesystemType.isEmpty ? "-" : device.diskFilesystemType)

                if !device.diskDataAvailable {
                    MetricUnavailableState(
                        icon: "internaldrive",
                        title: "暂无存储数据",
                        message: device.diskErrorMessage.nonEmptyOr("等待完整刷新读取根分区容量。")
                    )
                } else {
                    HStack {
                        Text(device.diskDeviceName.isEmpty ? "根分区" : device.diskDeviceName)
                            .font(.system(size: 22, weight: .black))
                        Spacer()
                        Text(device.diskTotalBytes > 0 ? "\(device.storageUsedPercent)% / \(ServerStatusParser.byteText(device.diskTotalBytes))" : "-")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.serveraTextSecondary)
                    }
                    MetricFillBar(value: Double(device.storageUsedPercent) / 100, color: .serveraLeaf, pulse: pulse)
                    HStack(spacing: 12) {
                        StorageMetric(label: "已用", value: device.storageUsedText, unit: "", color: .serveraAmber)
                        StorageMetric(label: "可用", value: device.storageAvailableText, unit: "", color: .serveraSky)
                        StorageMetric(label: "挂载点", value: device.diskMountPoint.isEmpty ? "-" : device.diskMountPoint, unit: "", color: .serveraLeaf)
                        StorageMetric(label: "I/O", value: "-", unit: "", color: .serveraAccent)
                    }
                }
            }
        }
    }
}

struct DockerOverviewCard: View {
    let device: DashboardDevice
    var pulse: Bool = false
    var onOpenAll: () -> Void

    var body: some View {
        ServeraCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(
                    icon: "shippingbox",
                    title: "Docker",
                    color: .serveraAccentDeep,
                    trailing: dockerTrailingText
                )

                if device.dockerContainers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(dockerEmptyTitle)
                            .font(.system(size: 17, weight: .heavy))
                        Text(dockerEmptyMessage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.serveraTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(device.dockerContainers.prefix(4))) { container in
                            DockerCompactRow(container: container, pulse: pulse)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }

                Button(action: onOpenAll) {
                    HStack {
                        Text("查看全部容器")
                            .font(.system(size: 15, weight: .heavy))
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 14, weight: .black))
                    }
                    .foregroundStyle(Color.serveraAccentDeep)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(Color.serveraAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dockerTrailingText: String {
        guard device.dockerDataAvailable else { return hasDockerError ? "不可用" : "等待刷新" }
        let total = max(device.docker, device.dockerContainers.count)
        return "\(device.dockerRunningCount)/\(total) 运行"
    }

    private var dockerEmptyTitle: String {
        guard device.dockerDataAvailable else { return hasDockerError ? "Docker 不可用" : "等待 Docker 刷新" }
        if device.docker > 0 { return "已检测到 \(device.docker) 个容器" }
        return "暂无容器"
    }

    private var dockerEmptyMessage: String {
        if !device.dockerDataAvailable {
            return device.dockerErrorMessage.nonEmptyOr("刷新服务器后会显示 Docker 容器数量、名称和资源占用。")
        }
        if device.docker > 0 {
            return "下一次刷新会继续尝试读取容器名称、CPU 和内存占用。"
        }
        return "当前服务器没有检测到 Docker 容器。"
    }

    private var hasDockerError: Bool {
        let message = device.dockerErrorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return !message.isEmpty && !message.contains("等待")
    }
}

struct DockerCompactRow: View {
    let container: DockerContainerSummary
    var pulse: Bool = false

    private var statusColor: Color {
        container.isRunning ? .serveraLeaf : .gray.opacity(0.46)
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: pulse && container.isRunning ? 10 : 8, height: pulse && container.isRunning ? 10 : 8)
                .shadow(color: statusColor.opacity(pulse ? 0.34 : 0.12), radius: pulse ? 8 : 3)
                .animation(.easeInOut(duration: 1.15), value: pulse)

            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                    .font(.system(size: 15, weight: .heavy))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(container.image.isEmpty ? container.status : container.image)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            DockerResourceCapsule(container: container, pulse: pulse, width: 126)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.serveraBorder.opacity(0.45)).frame(height: 1)
        }
    }
}

struct DockerResourceCapsule: View {
    let container: DockerContainerSummary
    var pulse: Bool = false
    var width: CGFloat = 126

    private var isActive: Bool {
        container.isRunning
    }

    var body: some View {
        VStack(spacing: 6) {
            DockerResourceLine(
                label: "CPU",
                value: isActive ? formatDockerCPUText(container.cpuPercent) : "停止",
                progress: isActive ? min(container.cpuPercent / 100, 1) : 0,
                color: isActive ? .serveraAccentDeep : .gray.opacity(0.42),
                pulse: pulse && isActive
            )
            DockerResourceLine(
                label: "内存",
                value: isActive ? dockerMemoryText(container) : "-",
                progress: isActive ? dockerMemoryProgress(container) : 0,
                color: isActive ? .serveraSky : .gray.opacity(0.35),
                pulse: false
            )
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(isActive ? 0.58 : 0.38))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.serveraBorder.opacity(0.48), lineWidth: 1)
                )
        )
    }
}

struct DockerResourceLine: View {
    let label: String
    let value: String
    let progress: Double
    let color: Color
    var pulse: Bool = false

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .frame(width: 24, alignment: .leading)
                Spacer(minLength: 4)
                Text(value)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .contentTransition(.numericText())
            }

            GeometryReader { proxy in
                let resolvedProgress = min(max(progress, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.serveraTintSoft.opacity(0.8))
                    Capsule()
                        .fill(color.opacity(resolvedProgress > 0 ? 0.7 : 0.22))
                        .frame(width: resolvedProgress > 0 ? max(proxy.size.width * resolvedProgress, 6) : (pulse ? 10 : 4))
                        .offset(x: resolvedProgress == 0 && pulse ? (proxy.size.width - 16) * 0.28 : 0)
                        .animation(.easeInOut(duration: 1.15), value: pulse)
                        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: resolvedProgress)
                }
            }
            .frame(height: 3)
        }
    }
}

func formatDockerCPUText(_ value: Double) -> String {
    if value <= 0 { return "空闲" }
    if value < 0.1 { return "<0.1%" }
    if value < 10 { return String(format: "%.1f%%", value) }
    return String(format: "%.0f%%", value)
}

func formatDockerPercent(_ value: Double) -> String {
    if value == 0 { return "0%" }
    if value < 10 { return String(format: "%.1f%%", value) }
    return String(format: "%.0f%%", value)
}

func dockerMemoryText(_ container: DockerContainerSummary) -> String {
    if container.memoryUsageText != "-" { return container.memoryUsageText }
    if container.memoryPercent > 0 { return formatDockerPercent(container.memoryPercent) }
    return "-"
}

func dockerMemoryProgress(_ container: DockerContainerSummary) -> Double {
    if container.memoryPercent > 0 {
        return min(container.memoryPercent / 100, 1)
    }
    return container.memoryUsageText == "-" ? 0 : 0.18
}

struct CardHeader: View {
    let icon: String
    let title: String
    let color: Color
    let trailing: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .black))
            Text(title)
                .font(.system(size: 20, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(trailing)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.serveraTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(color)
    }
}

struct LegendDot: View {
    let color: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.serveraTextSecondary)
                Text(value)
                    .font(.system(size: 12, weight: .black))
            }
        }
    }
}

struct MemoryLegend: View {
    let color: Color
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .black))
                Text(label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.serveraTextSecondary)
            }
        }
    }
}

struct MetricFillBar: View {
    let value: CGFloat
    let color: Color
    var pulse: Bool = false

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.serveraBorder.opacity(0.45))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.72), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * value)
                        .overlay(alignment: .trailing) {
                            Circle()
                                .fill(.white.opacity(pulse ? 0.82 : 0.28))
                                .frame(width: 12, height: 12)
                                .blur(radius: 1.5)
                                .padding(.trailing, 2)
                        }
                        .animation(.spring(response: 0.5, dampingFraction: 0.84), value: value)
                        .animation(.easeInOut(duration: 1.1), value: pulse)
                }
        }
        .frame(height: 16)
    }
}

struct DisabledMetricStrip: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Color.serveraTextSecondary.opacity(0.58))
            Text(text)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.serveraTextSecondary.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.62))
                .overlay(
                    Capsule()
                        .stroke(Color.serveraBorder.opacity(0.55), lineWidth: 1)
                )
        )
    }
}

struct ProcessColumn: View {
    let text: String
    let width: CGFloat
    let alignment: Alignment

    init(_ text: String, width: CGFloat, alignment: Alignment) {
        self.text = text
        self.width = width
        self.alignment = alignment
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }
}

struct BigMetric: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.serveraTextSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 18, weight: .black))
                    Text(unit)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.serveraTextSecondary)
                }
            }
        }
    }
}

struct StorageMetric: View {
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.serveraTextSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 15, weight: .black))
                Text(unit)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.serveraTextSecondary)
            }
            Capsule()
                .fill(color.opacity(0.72))
                .frame(width: 28, height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DashboardDeviceDropDelegate: DropDelegate {
    let item: DashboardDevice
    let devices: [DashboardDevice]
    @Binding var draggingDevice: DashboardDevice?
    @Binding var orderedDeviceIDs: [UUID]
    let onCommit: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingDevice, draggingDevice != item else { return }
        if orderedDeviceIDs.isEmpty {
            orderedDeviceIDs = devices.map(\.id)
        }

        guard let from = orderedDeviceIDs.firstIndex(of: draggingDevice.id),
              let to = orderedDeviceIDs.firstIndex(of: item.id),
              from != to
        else { return }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            orderedDeviceIDs.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        onCommit()
        return true
    }
}

struct DashboardDeviceListDropDelegate: DropDelegate {
    @Binding var draggingDevice: DashboardDevice?
    @Binding var orderedDeviceIDs: [UUID]
    let onCommit: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard draggingDevice != nil else { return true }
        onCommit()
        return true
    }
}

struct HeaderBar: View {
    let title: String
    var trailing: String? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 36, weight: .black))
            Spacer()
            if let trailing {
                Button {
                    trailingAction?()
                } label: {
                    Image(systemName: trailing)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.78), in: Circle())
                        .shadow(color: Color.serveraAccent.opacity(0.14), radius: 16, y: 8)
                }
                .buttonStyle(.plain)
                .disabled(trailingAction == nil)
            }
        }
    }
}
