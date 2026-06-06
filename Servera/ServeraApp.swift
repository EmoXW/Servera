import SwiftUI
import SwiftData

// MARK: - 应用入口
// 创建 RootView 和各个功能页共用的 SwiftData 容器。

@main
struct ServeraApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(for: ManagedDeviceRecord.self)
        }
    }
}
