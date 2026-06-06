import XCTest
@testable import Servera

/// 终端命令历史只保存命令本身，不保存输出转录，避免把敏感结果长期落盘。
final class ServerTerminalTests: XCTestCase {
    /// 历史记录按“最近使用”去重，并限制 10 条，保持终端输入补全轻量可控。
    func testTerminalHistoryKeepsNewestUniqueTenCommands() {
        let deviceID = UUID()
        var commands: [String] = []

        for index in 0..<12 {
            commands = ServerTerminalHistoryStore.insert("echo \(index)", for: deviceID, into: commands)
        }
        commands = ServerTerminalHistoryStore.insert("echo 6", for: deviceID, into: commands)

        XCTAssertEqual(commands.count, 10)
        XCTAssertEqual(commands.first, "echo 6")
        XCTAssertEqual(Set(commands).count, commands.count)
        XCTAssertFalse(commands.contains("echo 0"))
        XCTAssertFalse(commands.contains("echo 1"))
    }
}
