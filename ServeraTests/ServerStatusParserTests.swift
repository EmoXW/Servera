import XCTest
@testable import Servera

/// SSH 采集脚本的解析回归测试。
///
/// 这些样本固定住真实服务器采集过的边界：低 CPU 小数、低网络速率、
/// Docker 权限不足、Docker 资源统计为空、旧格式运行时长，以及单个模块不可用时的错误透传。
final class ServerStatusParserTests: XCTestCase {
    /// CentOS 低负载时整数 CPU 会显示 0%，但详情仍要保留小数精度。
    func testCentOSLowLoadFixtureKeepsHardwareAndDecimalCPU() {
        let snapshot = ServerStatusParser.parse(Self.centosLowLoadFixture, collectedAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(snapshot.systemVersion, "CentOS Linux 7 (Core)")
        XCTAssertEqual(snapshot.cpuCoreCount, 4)
        XCTAssertEqual(snapshot.cpuPercent, 0)
        XCTAssertEqual(snapshot.cpuPercentValue, 0.4, accuracy: 0.01)
        XCTAssertEqual(snapshot.cpuCorePercentValues, [0.2, 0.0, 1.1, 0.3])
        XCTAssertTrue(snapshot.cpuAvailable)
        XCTAssertEqual(snapshot.memoryTotalBytes, 4_096_000 * 1024)
        XCTAssertEqual(snapshot.memoryUsedPercent, 22)
        XCTAssertTrue(snapshot.memoryAvailable)
        XCTAssertEqual(snapshot.diskTotalBytes, 30_000_000_000)
        XCTAssertEqual(snapshot.diskUsedPercent, 10)
        XCTAssertTrue(snapshot.diskAvailable)
        XCTAssertEqual(snapshot.uptimeSeconds, 735_000)
        XCTAssertEqual(snapshot.load1, 0.00, accuracy: 0.001)
        XCTAssertEqual(snapshot.load5, 0.01, accuracy: 0.001)
        XCTAssertEqual(snapshot.load15, 0.05, accuracy: 0.001)
    }

    /// 网络速率必须转成用户可读单位，避免 UI 直接展示原始字节数。
    func testNetworkRatesAreFormattedAndNotRawBytes() {
        let snapshot = ServerStatusParser.parse(Self.networkFixture)

        XCTAssertTrue(snapshot.networkAvailable)
        XCTAssertEqual(snapshot.networkInterfaceName, "eth0")
        XCTAssertEqual(snapshot.networkReceiveText, "302B/s")
        XCTAssertEqual(snapshot.networkTransmitText, "134B/s")
        XCTAssertEqual(snapshot.networkReceiveTotalText, "118M")
        XCTAssertEqual(snapshot.networkTransmitTotalText, "7.7M")
    }

    /// Docker 列表和资源统计是两条数据源，解析器需要把容器基础信息和资源占用合并。
    func testDockerContainersParseResourceFields() {
        let snapshot = ServerStatusParser.parse(Self.dockerFixture)

        XCTAssertTrue(snapshot.dockerAvailable)
        XCTAssertTrue(snapshot.dockerInstalled)
        XCTAssertEqual(snapshot.dockerContainerCount, 2)
        XCTAssertEqual(snapshot.dockerRunningCount, 1)
        XCTAssertEqual(snapshot.dockerContainers.count, 2)
        XCTAssertEqual(snapshot.dockerContainers[0].name, "web")
        XCTAssertEqual(snapshot.dockerContainers[0].cpuPercent, 0.08, accuracy: 0.001)
        XCTAssertEqual(snapshot.dockerContainers[0].memoryUsageText, "48.97MiB")
        XCTAssertEqual(snapshot.dockerContainers[0].memoryPercent, 1.2, accuracy: 0.001)
        XCTAssertFalse(snapshot.dockerContainers[1].isRunning)
    }

    /// 有些服务器 Docker 资源统计会空返回；容器列表仍应可见，只把资源占用置空。
    func testDockerContainerParsesWhenStatsAreEmpty() {
        let snapshot = ServerStatusParser.parse(Self.dockerEmptyStatsFixture)

        XCTAssertTrue(snapshot.dockerAvailable)
        XCTAssertTrue(snapshot.dockerInstalled)
        XCTAssertEqual(snapshot.dockerContainerCount, 1)
        XCTAssertEqual(snapshot.dockerRunningCount, 1)
        XCTAssertEqual(snapshot.dockerContainers.count, 1)
        XCTAssertEqual(snapshot.dockerContainers[0].name, "ubuntu64")
        XCTAssertEqual(snapshot.dockerContainers[0].image, "nginx:latest")
        XCTAssertEqual(snapshot.dockerContainers[0].cpuPercent, 0)
        XCTAssertEqual(snapshot.dockerContainers[0].memoryUsageText, "-")
    }

    /// 旧脚本/旧系统可能只给格式化运行时长，这里保证运行态判断不依赖单一字段。
    func testDockerContainerParsesLegacyFormattedStatus() {
        let snapshot = ServerStatusParser.parse(Self.dockerLegacyStatusFixture)

        XCTAssertTrue(snapshot.dockerAvailable)
        XCTAssertEqual(snapshot.dockerContainerCount, 1)
        XCTAssertEqual(snapshot.dockerRunningCount, 1)
        XCTAssertEqual(snapshot.dockerContainers.count, 1)
        XCTAssertEqual(snapshot.dockerContainers[0].name, "legacy-web")
        XCTAssertTrue(snapshot.dockerContainers[0].isRunning)
        XCTAssertEqual(snapshot.dockerContainers[0].uptimeText, "Up 11 days")
    }

    /// 发现 Docker 但套接字无权限时，要显示权限不可用，而不是误判成未安装。
    func testDockerPermissionDeniedIsUnavailableButStillDetected() {
        let snapshot = ServerStatusParser.parse(Self.dockerPermissionDeniedFixture)

        XCTAssertFalse(snapshot.dockerAvailable)
        XCTAssertTrue(snapshot.dockerInstalled)
        XCTAssertEqual(snapshot.dockerContainerCount, 0)
        XCTAssertEqual(snapshot.dockerRunningCount, 0)
        XCTAssertEqual(snapshot.dockerErrorMessage, "Docker 权限不足或服务不可用")
        XCTAssertTrue(snapshot.dockerContainers.isEmpty)
    }

    /// Ubuntu 样本覆盖低网络流量和进程列表，防止系统差异破坏首页指标。
    func testUbuntuFixtureKeepsLowNetworkAndProcessData() {
        let snapshot = ServerStatusParser.parse(Self.ubuntuLowNetworkFixture)

        XCTAssertEqual(snapshot.systemName, "Ubuntu")
        XCTAssertEqual(snapshot.systemVersion, "Ubuntu 24.04.2 LTS")
        XCTAssertTrue(snapshot.networkAvailable)
        XCTAssertEqual(snapshot.networkInterfaceName, "ens3")
        XCTAssertEqual(snapshot.networkReceiveText, "0B/s")
        XCTAssertEqual(snapshot.networkTransmitText, "2.0K/s")
        XCTAssertTrue(snapshot.processAvailable)
        XCTAssertEqual(snapshot.topProcesses.first?.command, "nginx")
        XCTAssertEqual(snapshot.topProcesses.first?.cpuPercent ?? 0, 0.3, accuracy: 0.001)
    }

    /// 单个模块采集失败时，其它模块仍可用，错误信息要能被 UI 精准展示。
    func testUnavailableModulesExposeErrorMessages() {
        let snapshot = ServerStatusParser.parse(Self.unavailableFixture)

        XCTAssertFalse(snapshot.cpuAvailable)
        XCTAssertFalse(snapshot.memoryAvailable)
        XCTAssertFalse(snapshot.diskAvailable)
        XCTAssertFalse(snapshot.networkAvailable)
        XCTAssertFalse(snapshot.processAvailable)
        XCTAssertTrue(snapshot.dockerAvailable)
        XCTAssertFalse(snapshot.dockerInstalled)
        XCTAssertEqual(snapshot.cpuErrorMessage, "CPU 采样不可用")
        XCTAssertEqual(snapshot.networkErrorMessage, "默认网卡流量不可用")
        XCTAssertEqual(snapshot.processErrorMessage, "权限不足，无法读取进程")
    }

    private static let centosLowLoadFixture = """
    __SERVERA_OS__
    KERNEL=Linux 3.10.0-1160.el7.x86_64 x86_64
    NAME="CentOS Linux"
    PRETTY_NAME="CentOS Linux 7 (Core)"
    __SERVERA_CPU__
    CORES=4
    PERCENT=0
    PERCENT_DECIMAL=0.4
    USER=0
    USER_DECIMAL=0.2
    NICE=0
    NICE_DECIMAL=0.0
    SYSTEM=0
    SYSTEM_DECIMAL=0.1
    IOWAIT=0
    IOWAIT_DECIMAL=0.0
    CORE0=0
    CORE0_DECIMAL=0.2
    CORE1=0
    CORE1_DECIMAL=0.0
    CORE2=1
    CORE2_DECIMAL=1.1
    CORE3=0
    CORE3_DECIMAL=0.3
    __SERVERA_MEM__
    MemTotal: 4096000 kB
    MemAvailable: 3194880 kB
    MemFree: 2048000 kB
    Cached: 700000 kB
    Buffers: 120000 kB
    SReclaimable: 20000 kB
    SwapTotal: 0 kB
    SwapFree: 0 kB
    __SERVERA_LOAD__
    0.00 0.01 0.05 1/166 1201
    __SERVERA_DF__
    Filesystem Type 1B-blocks Used Available Use% Mounted
    /dev/vda1 ext4 30000000000 3000000000 27000000000 10% /
    __SERVERA_UPTIME__
    735000.00 2040000.00
    """

    private static let networkFixture = """
    __SERVERA_NET__
    IFACE=eth0
    RX_RATE=302
    TX_RATE=134
    RX_TOTAL=123456789
    TX_TOTAL=8080000
    IP=203.0.113.10/24
    """

    private static let dockerFixture = """
    __SERVERA_DOCKER__
    INSTALLED=1
    TOTAL=2
    RUNNING=1
    CONTAINER\tabc123\tweb\tnginx:latest\trunning\tUp 3 hours\t0.08%\t48.97MiB\t4GiB\t1.20%\tUp 3 hours
    CONTAINER\tdef456\tworker\tbusybox\texited\tExited (0) 4 minutes ago\t\t\t\t\tExited (0) 4 minutes ago
    """

    private static let dockerEmptyStatsFixture = """
    __SERVERA_DOCKER__
    INSTALLED=1
    TOTAL=1
    RUNNING=1
    CONTAINER\t9d3764ce9f2a\tubuntu64\tnginx:latest\trunning\tUp 2 hours\t\t\t\t\tUp 2 hours
    """

    private static let dockerLegacyStatusFixture = """
    __SERVERA_DOCKER__
    INSTALLED=1
    TOTAL=1
    RUNNING=1
    CONTAINER\t9d3764ce9f2a\tlegacy-web\tnginx:1.10\trunning\tUp 11 days\t0.01%\t20MiB\t4GiB\t0.50%\tUp 11 days
    """

    private static let dockerPermissionDeniedFixture = """
    __SERVERA_DOCKER__
    INSTALLED=1
    ERROR=Docker 权限不足或服务不可用
    TOTAL=0
    RUNNING=0
    """

    private static let ubuntuLowNetworkFixture = """
    __SERVERA_OS__
    KERNEL=Linux 6.8.0-60-generic x86_64
    NAME="Ubuntu"
    PRETTY_NAME="Ubuntu 24.04.2 LTS"
    __SERVERA_NET__
    IFACE=ens3
    RX_RATE=0
    TX_RATE=2048
    RX_TOTAL=1024
    TX_TOTAL=1048576
    IP=10.0.0.2/24
    __SERVERA_PROC__
    PID COMMAND USER CPU RSS
    101 nginx www-data 0.3 20480
    202 sshd root 0.0 8192
    """

    private static let unavailableFixture = """
    __SERVERA_CPU__
    ERROR=CPU 采样不可用
    __SERVERA_MEM__
    ERROR=内存信息不可用
    __SERVERA_DF__
    ERROR=根分区容量不可用
    __SERVERA_NET__
    ERROR=默认网卡流量不可用
    __SERVERA_PROC__
    ERROR=权限不足，无法读取进程
    __SERVERA_DOCKER__
    INSTALLED=0
    TOTAL=0
    RUNNING=0
    """
}
