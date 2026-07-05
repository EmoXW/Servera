import Foundation

// MARK: - 服务器快照与解析器
// ServerStatusSnapshot 是 UI 使用的归一化结构。解析器接收 Linux/macOS shell 脚本
// 输出的 Servera 标记，并按模块降级，而不是让整次刷新失败。

struct ServerStatusSnapshot: Codable, Equatable, Sendable {
    var systemName: String
    var systemVersion: String
    var kernelSummary: String
    var cpuPercent: Int
    var cpuPercentValue: Double
    var cpuCoreCount: Int
    var cpuCorePercents: [Int]
    var cpuCorePercentValues: [Double]
    var cpuUserPercent: Int
    var cpuUserPercentValue: Double
    var cpuSystemPercent: Int
    var cpuSystemPercentValue: Double
    var cpuNicePercent: Int
    var cpuNicePercentValue: Double
    var cpuIOWaitPercent: Int
    var cpuIOWaitPercentValue: Double
    var cpuTemperatureCelsius: Int?
    var memoryUsedPercent: Int
    var memoryTotalBytes: Int64
    var memoryUsedBytes: Int64
    var memoryAvailableBytes: Int64
    var memoryCachedBytes: Int64
    var memoryFreeBytes: Int64
    var swapTotalBytes: Int64
    var swapUsedBytes: Int64
    var diskUsedPercent: Int
    var diskTotalBytes: Int64
    var diskUsedBytes: Int64
    var diskAvailableBytes: Int64
    var diskDeviceName: String
    var diskFilesystemType: String
    var diskMountPoint: String
    var uptimeSeconds: Int64
    var load1: Double
    var load5: Double
    var load15: Double
    var networkReceiveText: String
    var networkTransmitText: String
    var networkReceiveTotalText: String
    var networkTransmitTotalText: String
    var networkInterfaceName: String
    var primaryIPText: String
    var topProcesses: [ServerProcessSummary]
    var dockerInstalled: Bool
    var dockerContainerCount: Int
    var dockerRunningCount: Int
    var dockerContainers: [DockerContainerSummary]
    var cpuAvailable: Bool
    var memoryAvailable: Bool
    var diskAvailable: Bool
    var networkAvailable: Bool
    var processAvailable: Bool
    var dockerAvailable: Bool
    var cpuErrorMessage: String
    var memoryErrorMessage: String
    var diskErrorMessage: String
    var networkErrorMessage: String
    var processErrorMessage: String
    var dockerErrorMessage: String
    var collectedAt: Date

    static let empty = ServerStatusSnapshot(
        systemName: "Linux",
        systemVersion: "Unknown",
        kernelSummary: "",
        cpuPercent: 0,
        cpuPercentValue: 0,
        cpuCoreCount: 0,
        cpuCorePercents: [],
        cpuCorePercentValues: [],
        cpuUserPercent: 0,
        cpuUserPercentValue: 0,
        cpuSystemPercent: 0,
        cpuSystemPercentValue: 0,
        cpuNicePercent: 0,
        cpuNicePercentValue: 0,
        cpuIOWaitPercent: 0,
        cpuIOWaitPercentValue: 0,
        cpuTemperatureCelsius: nil,
        memoryUsedPercent: 0,
        memoryTotalBytes: 0,
        memoryUsedBytes: 0,
        memoryAvailableBytes: 0,
        memoryCachedBytes: 0,
        memoryFreeBytes: 0,
        swapTotalBytes: 0,
        swapUsedBytes: 0,
        diskUsedPercent: 0,
        diskTotalBytes: 0,
        diskUsedBytes: 0,
        diskAvailableBytes: 0,
        diskDeviceName: "",
        diskFilesystemType: "",
        diskMountPoint: "",
        uptimeSeconds: 0,
        load1: 0,
        load5: 0,
        load15: 0,
        networkReceiveText: "-",
        networkTransmitText: "-",
        networkReceiveTotalText: "-",
        networkTransmitTotalText: "-",
        networkInterfaceName: "",
        primaryIPText: "",
        topProcesses: [],
        dockerInstalled: false,
        dockerContainerCount: 0,
        dockerRunningCount: 0,
        dockerContainers: [],
        cpuAvailable: false,
        memoryAvailable: false,
        diskAvailable: false,
        networkAvailable: false,
        processAvailable: false,
        dockerAvailable: false,
        cpuErrorMessage: "等待 CPU 采样",
        memoryErrorMessage: "等待内存采样",
        diskErrorMessage: "等待存储采样",
        networkErrorMessage: "等待网络采样",
        processErrorMessage: "等待完整刷新采集进程",
        dockerErrorMessage: "等待 Docker 探测",
        collectedAt: .now
    )
}

// Server Docker 和 NAS Docker UI 共用的归一化容器行。
// 视图不直接接触原始解析字典，因为 CLI 模板和 DSM API 的 Docker 输出格式不同。
struct DockerContainerSummary: Codable, Equatable, Hashable, Sendable, Identifiable {
    var containerID: String
    var name: String
    var image: String
    var state: String
    var status: String
    var cpuPercent: Double
    var memoryUsageText: String
    var memoryLimitText: String
    var memoryPercent: Double
    var uptimeText: String

    var id: String {
        containerID.isEmpty ? name : containerID
    }

    var isRunning: Bool {
        // Docker CLI 可能在 State 里给 running，也可能只在 Status 里给 Up ...。
        let normalizedState = state.lowercased()
        let normalizedStatus = status.lowercased()
        return normalizedState == "running"
            || normalizedStatus.hasPrefix("up")
            || normalizedStatus.contains("running")
    }
}

struct ServerProcessSummary: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: Int { pid }
    var pid: Int
    var command: String
    var user: String
    var cpuPercent: Double
    var memoryText: String
}

// Servera shell 脚本输出解析器。每个段落以 __SERVERA_<NAME>__ 开头，
// 这样单个模块失败不会破坏整个状态快照。
enum ServerStatusParser {
    static func parse(_ output: String, collectedAt: Date = .now) -> ServerStatusSnapshot {
        let sections = sectioned(output)
        let os = parseOS(sections["OS"] ?? "")
        let cpu = parseCPU(sections["CPU"] ?? "")
        let memory = parseMemory(sections["MEM"] ?? "")
        let load = parseLoad(sections["LOAD"] ?? "")
        let disk = parseDisk(sections["DF"] ?? "")
        let uptime = parseUptime(sections["UPTIME"] ?? "")
        let network = parseNetwork(sections["NET"] ?? "")
        let processes = parseProcesses(sections["PROC"] ?? "")
        let docker = parseDocker(sections["DOCKER"] ?? "")
        let cpuAvailable = cpu.available
        let memoryAvailable = memory.availableData
        let diskAvailable = disk.availableData
        let networkAvailable = network.available
        let processAvailable = processes.isEmpty == false
        let dockerAvailable = docker.available

        return ServerStatusSnapshot(
            systemName: os.name,
            systemVersion: os.version,
            kernelSummary: os.kernel,
            cpuPercent: cpu.percent,
            cpuPercentValue: cpu.percentValue,
            cpuCoreCount: cpu.cores,
            cpuCorePercents: cpu.corePercents,
            cpuCorePercentValues: cpu.corePercentValues,
            cpuUserPercent: cpu.user,
            cpuUserPercentValue: cpu.userValue,
            cpuSystemPercent: cpu.system,
            cpuSystemPercentValue: cpu.systemValue,
            cpuNicePercent: cpu.nice,
            cpuNicePercentValue: cpu.niceValue,
            cpuIOWaitPercent: cpu.iowait,
            cpuIOWaitPercentValue: cpu.iowaitValue,
            cpuTemperatureCelsius: parseTemperature(sections["TEMP"] ?? ""),
            memoryUsedPercent: memory.percent,
            memoryTotalBytes: memory.total,
            memoryUsedBytes: memory.used,
            memoryAvailableBytes: memory.availableBytes,
            memoryCachedBytes: memory.cached,
            memoryFreeBytes: memory.free,
            swapTotalBytes: memory.swapTotal,
            swapUsedBytes: memory.swapUsed,
            diskUsedPercent: disk.percent,
            diskTotalBytes: disk.total,
            diskUsedBytes: disk.used,
            diskAvailableBytes: disk.availableBytes,
            diskDeviceName: disk.device,
            diskFilesystemType: disk.filesystem,
            diskMountPoint: disk.mountPoint,
            uptimeSeconds: uptime,
            load1: load.0,
            load5: load.1,
            load15: load.2,
            networkReceiveText: network.receive,
            networkTransmitText: network.transmit,
            networkReceiveTotalText: network.receiveTotal,
            networkTransmitTotalText: network.transmitTotal,
            networkInterfaceName: network.interfaceName,
            primaryIPText: network.primaryIP,
            topProcesses: processes,
            dockerInstalled: docker.installed,
            dockerContainerCount: docker.total,
            dockerRunningCount: docker.running,
            dockerContainers: docker.containers,
            cpuAvailable: cpuAvailable,
            memoryAvailable: memoryAvailable,
            diskAvailable: diskAvailable,
            networkAvailable: networkAvailable,
            processAvailable: processAvailable,
            dockerAvailable: dockerAvailable,
            cpuErrorMessage: cpuAvailable ? "" : moduleErrorMessage(sections["CPU"] ?? "", fallback: "CPU 采样不可用"),
            memoryErrorMessage: memoryAvailable ? "" : moduleErrorMessage(sections["MEM"] ?? "", fallback: "内存信息不可用"),
            diskErrorMessage: diskAvailable ? "" : moduleErrorMessage(sections["DF"] ?? "", fallback: "根分区容量不可用"),
            networkErrorMessage: networkAvailable ? "" : moduleErrorMessage(sections["NET"] ?? "", fallback: "默认网卡流量不可用"),
            processErrorMessage: processAvailable ? "" : moduleErrorMessage(sections["PROC"] ?? "", fallback: "暂无进程数据"),
            dockerErrorMessage: dockerAvailable ? "" : moduleErrorMessage(sections["DOCKER"] ?? "", fallback: "Docker 状态不可用"),
            collectedAt: collectedAt
        )
    }

    private static func sectioned(_ output: String) -> [String: String] {
        // 段落解析保持简单且宽容：未知标记由调用方忽略，
        // 缺失段落转成对应模块的空字符串。
        var result: [String: [String]] = [:]
        var current: String?

        for line in output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("__SERVERA_"), line.hasSuffix("__") {
                current = line.replacingOccurrences(of: "__SERVERA_", with: "").replacingOccurrences(of: "__", with: "")
                continue
            }
            if let current {
                result[current, default: []].append(line)
            }
        }

        return result.mapValues { $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func parseOS(_ text: String) -> (name: String, version: String, kernel: String) {
        var name = "Linux"
        var version = "Unknown"
        var kernel = ""

        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("PRETTY_NAME=") {
                version = cleanShellValue(line.replacingOccurrences(of: "PRETTY_NAME=", with: ""))
            } else if line.hasPrefix("NAME=") {
                name = cleanShellValue(line.replacingOccurrences(of: "NAME=", with: ""))
            } else if line.hasPrefix("KERNEL=") {
                kernel = cleanShellValue(line.replacingOccurrences(of: "KERNEL=", with: ""))
            }
        }

        return (name, version, kernel)
    }

    private static func parseCPU(_ text: String) -> (
        percent: Int,
        percentValue: Double,
        cores: Int,
        corePercents: [Int],
        corePercentValues: [Double],
        user: Int,
        userValue: Double,
        system: Int,
        systemValue: Double,
        nice: Int,
        niceValue: Double,
        iowait: Int,
        iowaitValue: Double,
        available: Bool
    ) {
        var percent = 0
        var percentValue: Double?
        var hasCPUPercent = false
        var cores = 0
        var corePercentsByIndex: [Int: Int] = [:]
        var corePercentValuesByIndex: [Int: Double] = [:]
        var user = 0
        var userValue: Double?
        var system = 0
        var systemValue: Double?
        var nice = 0
        var niceValue: Double?
        var iowait = 0
        var iowaitValue: Double?

        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=").map(String.init)
            guard parts.count == 2 else { continue }
            let value = Double(parts[1]) ?? 0
            switch parts[0] {
            case "PERCENT":
                percent = Int(value.rounded())
                hasCPUPercent = true
            case "PERCENT_DECIMAL":
                percentValue = value
                hasCPUPercent = true
            case "CORES":
                cores = Int(parts[1]) ?? 0
            case "USER":
                user = Int(value.rounded())
            case "USER_DECIMAL":
                userValue = value
            case "SYSTEM":
                system = Int(value.rounded())
            case "SYSTEM_DECIMAL":
                systemValue = value
            case "NICE":
                nice = Int(value.rounded())
            case "NICE_DECIMAL":
                niceValue = value
            case "IOWAIT":
                iowait = Int(value.rounded())
            case "IOWAIT_DECIMAL":
                iowaitValue = value
            case let key where key.hasPrefix("CORE") && key.hasSuffix("_DECIMAL"):
                if let index = Int(key.replacingOccurrences(of: "CORE", with: "").replacingOccurrences(of: "_DECIMAL", with: "")) {
                    corePercentValuesByIndex[index] = value
                }
            case let key where key.hasPrefix("CORE"):
                if let index = Int(key.replacingOccurrences(of: "CORE", with: "")) {
                    corePercentsByIndex[index] = Int(value.rounded())
                }
            default:
                break
            }
        }

        // 保留 CPU 小数值给图表使用，同时保留四舍五入整数给紧凑标签使用。
        let sortedCoreIndexes = Array(Set(corePercentsByIndex.keys).union(corePercentValuesByIndex.keys)).sorted()
        let corePercents = sortedCoreIndexes.map { index in
            corePercentsByIndex[index] ?? Int((corePercentValuesByIndex[index] ?? 0).rounded())
        }
        let corePercentValues = sortedCoreIndexes.map { index in
            corePercentValuesByIndex[index] ?? Double(corePercentsByIndex[index] ?? 0)
        }
        let resolvedPercentValue = percentValue ?? Double(percent)
        let resolvedUserValue = userValue ?? Double(user)
        let resolvedSystemValue = systemValue ?? Double(system)
        let resolvedNiceValue = niceValue ?? Double(nice)
        let resolvedIOWaitValue = iowaitValue ?? Double(iowait)

        return (
            min(max(percent, 0), 100),
            min(max(resolvedPercentValue, 0), 100),
            max(cores, corePercents.count, 0),
            corePercents.map { min(max($0, 0), 100) },
            corePercentValues.map { min(max($0, 0), 100) },
            min(max(user, 0), 100),
            min(max(resolvedUserValue, 0), 100),
            min(max(system, 0), 100),
            min(max(resolvedSystemValue, 0), 100),
            min(max(nice, 0), 100),
            min(max(resolvedNiceValue, 0), 100),
            min(max(iowait, 0), 100),
            min(max(resolvedIOWaitValue, 0), 100),
            hasCPUPercent || !corePercentValues.isEmpty || !corePercents.isEmpty
        )
    }

    private static func parseMemory(_ text: String) -> (
        percent: Int,
        total: Int64,
        used: Int64,
        availableBytes: Int64,
        cached: Int64,
        free: Int64,
        swapTotal: Int64,
        swapUsed: Int64,
        availableData: Bool
    ) {
        var values: [String: Int64] = [:]
        // Linux /proc/meminfo 使用 KiB，这里统一转换一次，
        // 后续 App 内部都按字节处理。
        for line in text.components(separatedBy: .newlines) {
            let pieces = line.split(whereSeparator: { $0 == " " || $0 == ":" }).map(String.init)
            guard pieces.count >= 2, let value = Int64(pieces[1]) else { continue }
            values[pieces[0]] = value * 1024
        }

        let total = values["MemTotal"] ?? 0
        let free = values["MemFree"] ?? 0
        let cached = (values["Cached"] ?? 0) + (values["SReclaimable"] ?? 0) + (values["Buffers"] ?? 0)
        let availableBytes = values["MemAvailable"] ?? min(total, free + cached)
        let used = max(total - availableBytes, 0)
        let swapTotal = values["SwapTotal"] ?? 0
        let swapFree = values["SwapFree"] ?? 0
        let swapUsed = max(swapTotal - swapFree, 0)
        let percent = total > 0 ? Int((Double(used) / Double(total) * 100).rounded()) : 0
        return (min(max(percent, 0), 100), total, used, availableBytes, cached, free, swapTotal, swapUsed, total > 0)
    }

    private static func parseLoad(_ text: String) -> (Double, Double, Double) {
        let pieces = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        return (
            Double(pieces[safe: 0] ?? "") ?? 0,
            Double(pieces[safe: 1] ?? "") ?? 0,
            Double(pieces[safe: 2] ?? "") ?? 0
        )
    }

    private static func parseDisk(_ text: String) -> (
        percent: Int,
        total: Int64,
        used: Int64,
        availableBytes: Int64,
        device: String,
        filesystem: String,
        mountPoint: String,
        availableData: Bool
    ) {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { return (0, 0, 0, 0, "", "", "", false) }
        let parts = lines[1].split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count >= 5 else { return (0, 0, 0, 0, "", "", "", false) }

        if parts.count >= 7 {
            let total = Int64(parts[2]) ?? 0
            let used = Int64(parts[3]) ?? 0
            let available = Int64(parts[4]) ?? 0
            let percentText = parts[5].replacingOccurrences(of: "%", with: "")
            return (Int(percentText) ?? 0, total, used, available, parts[0], parts[1], parts[6], total > 0)
        }

        let total = Int64(parts[1]) ?? 0
        let used = Int64(parts[2]) ?? 0
        let available = Int64(parts[3]) ?? 0
        let percentText = parts[4].replacingOccurrences(of: "%", with: "")
        return (Int(percentText) ?? 0, total, used, available, parts[0], "", parts[safe: 5] ?? "/", total > 0)
    }

    private static func parseUptime(_ text: String) -> Int64 {
        let first = text.split(separator: " ").first.map(String.init) ?? ""
        return Int64(Double(first) ?? 0)
    }

    private static func parseNetwork(_ text: String) -> (
        receive: String,
        transmit: String,
        receiveTotal: String,
        transmitTotal: String,
        interfaceName: String,
        primaryIP: String,
        available: Bool
    ) {
        var receive = "-"
        var transmit = "-"
        var receiveTotal = "-"
        var transmitTotal = "-"
        var interfaceName = ""
        var primaryIP = ""
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("RX_RATE=") {
                receive = rateText(line.replacingOccurrences(of: "RX_RATE=", with: ""))
            } else if line.hasPrefix("TX_RATE=") {
                transmit = rateText(line.replacingOccurrences(of: "TX_RATE=", with: ""))
            } else if line.hasPrefix("RX_TOTAL=") {
                receiveTotal = byteText(Int64(line.replacingOccurrences(of: "RX_TOTAL=", with: "")) ?? 0)
            } else if line.hasPrefix("TX_TOTAL=") {
                transmitTotal = byteText(Int64(line.replacingOccurrences(of: "TX_TOTAL=", with: "")) ?? 0)
            } else if line.hasPrefix("IFACE=") {
                interfaceName = line.replacingOccurrences(of: "IFACE=", with: "")
            } else if line.hasPrefix("IP=") {
                primaryIP = line.replacingOccurrences(of: "IP=", with: "")
            } else if line.hasPrefix("RX=") {
                receiveTotal = byteText(Int64(line.replacingOccurrences(of: "RX=", with: "")) ?? 0)
            } else if line.hasPrefix("TX=") {
                transmitTotal = byteText(Int64(line.replacingOccurrences(of: "TX=", with: "")) ?? 0)
            }
        }
        let available = receive != "-" || transmit != "-" || receiveTotal != "-" || transmitTotal != "-"
        return (receive, transmit, receiveTotal, transmitTotal, interfaceName, primaryIP, available)
    }

    private static func parseProcesses(_ text: String) -> [ServerProcessSummary] {
        text.components(separatedBy: .newlines)
            .dropFirst()
            .compactMap { line -> ServerProcessSummary? in
                let parts = line.split(maxSplits: 4, whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                guard parts.count >= 5, let pid = Int(parts[0]) else { return nil }
                let rssKB = Int64(parts[4]) ?? 0
                return ServerProcessSummary(
                    pid: pid,
                    command: parts[1],
                    user: parts[2],
                    cpuPercent: Double(parts[3]) ?? 0,
                    memoryText: byteText(rssKB * 1024)
                )
            }
    }

    private static func parseDocker(_ text: String) -> (installed: Bool, total: Int, running: Int, containers: [DockerContainerSummary], available: Bool) {
        var installed = false
        var total = 0
        var running = 0
        var containers: [DockerContainerSummary] = []
        var sawInstalledLine = false
        var hasPermissionOrServiceError = false

        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("ERROR=") {
                hasPermissionOrServiceError = true
                continue
            }
            if line.hasPrefix("CONTAINER\t") {
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 11 else { continue }
                containers.append(
                    DockerContainerSummary(
                        containerID: parts[1],
                        name: parts[2].isEmpty ? parts[1] : parts[2],
                        image: parts[3],
                        state: parts[4],
                        status: parts[5],
                        cpuPercent: percentValue(parts[6]),
                        memoryUsageText: parts[7].isEmpty ? "-" : parts[7],
                        memoryLimitText: parts[8].isEmpty ? "-" : parts[8],
                        memoryPercent: percentValue(parts[9]),
                        uptimeText: parts[10].isEmpty ? parts[5] : parts[10]
                    )
                )
                continue
            }

            let parts = line.split(separator: "=").map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "INSTALLED":
                installed = parts[1] == "1"
                sawInstalledLine = true
            case "TOTAL":
                total = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            case "RUNNING":
                running = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            default:
                break
            }
        }

        return (installed, total, running, containers, sawInstalledLine && !hasPermissionOrServiceError)
    }

    private static func moduleErrorMessage(_ text: String, fallback: String) -> String {
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("ERROR=") {
                let raw = cleanShellValue(line.replacingOccurrences(of: "ERROR=", with: ""))
                return raw.isEmpty ? fallback : raw
            }
        }
        return fallback
    }

    private static func percentValue(_ text: String) -> Double {
        Double(
            text
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        ) ?? 0
    }

    private static func parseTemperature(_ text: String) -> Int? {
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("TEMP_C=") {
                let value = Int(Double(line.replacingOccurrences(of: "TEMP_C=", with: ""))?.rounded() ?? -1)
                return value >= 0 ? value : nil
            }
        }
        return nil
    }

    private static func cleanShellValue(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
    }

    static func byteText(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "-" }
        let units = ["B", "K", "M", "G", "T"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return String(format: value >= 10 || index == 0 ? "%.0f%@" : "%.1f%@", value, units[index])
    }

    static func rateText(_ bytesPerSecondText: String) -> String {
        guard let bytes = Int64(bytesPerSecondText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return "-" }
        let formatted = byteText(bytes)
        return formatted == "-" ? "0B/s" : "\(formatted)/s"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
