import XCTest
@testable import Servera

/// Synology DSM 返回结构在不同版本差异很大，这里锁住解析层的兼容策略。
final class SynologyClientParsingTests: XCTestCase {
    /// 同时出现存储池和卷时，优先保留可进入文件浏览的真实挂载路径。
    func testStorageVolumesFilterEmptySyntheticPathsAndDeduplicate() {
        let client = SynologyClient.shared
        let data: [String: Any] = [
            "volumes": [
                [
                    "display_name": "Storage Pool 1",
                    "total_size": 1000,
                    "used_size": 200,
                    "size_free": 800
                ],
                [
                    "display_name": "volume 1",
                    "total_size": 1000,
                    "used_size": 250,
                    "size_free": 750
                ],
                [
                    "display_name": "Volume 1",
                    "volume_path": "/volume1",
                    "total_size": 1000,
                    "used_size": 300,
                    "size_free": 700
                ]
            ]
        ]

        let volumes = client.testExtractVolumes(from: data)

        XCTAssertEqual(volumes.count, 1)
        XCTAssertEqual(volumes.first?.path, "/volume1")
        XCTAssertEqual(volumes.first?.usedBytes, 250)
    }

    /// 只有“无路径存储池”时也要能显示容量，避免首页误以为没有读到存储信息。
    func testStorageVolumesKeepPathlessStoragePoolWhenNoBrowsableVolumeExists() {
        let client = SynologyClient.shared
        let data: [String: Any] = [
            "storage_pools": [
                [
                    "display_name": "Storage Pool 1",
                    "total_size": 4096,
                    "used_size": 1024,
                    "size_free": 3072
                ]
            ]
        ]

        let volumes = client.testExtractVolumes(from: data)

        XCTAssertEqual(volumes.count, 1)
        XCTAssertEqual(volumes.first?.name, "Storage Pool 1")
        XCTAssertEqual(volumes.first?.path, "")
        XCTAssertEqual(volumes.first?.totalBytes, 4096)
        XCTAssertEqual(volumes.first?.usedBytes, 1024)
        XCTAssertEqual(volumes.first?.availableBytes, 3072)
    }

    /// DSM 有时只给自然语言状态或字符串布尔值，解析器要统一成稳定的运行/停止状态。
    func testDockerStateNormalizesStatusTextAndBooleanValues() {
        let client = SynologyClient.shared
        let containers = client.testParseDockerContainers(from: [
            [
                "id": "abc",
                "name": "demo-api",
                "image": "redis:latest",
                "state": "",
                "status": "Up 3 hours"
            ],
            [
                "id": "def",
                "name": "stopped-web",
                "image": "nginx",
                "running": "false",
                "status": "Exited (0) 2 minutes ago"
            ]
        ])

        XCTAssertEqual(containers.map { $0.state }, ["running", "stopped"])
        XCTAssertTrue(containers[0].isRunning)
        XCTAssertFalse(containers[1].isRunning)
    }
}
