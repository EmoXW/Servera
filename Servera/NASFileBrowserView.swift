import SwiftUI
import UniformTypeIdentifiers

// MARK: - NAS 文件浏览器
// 单个 DSM 卷/共享文件夹的 File Station 浏览器。所有会修改文件的操作都走
// SynologyFileService，上传冲突和 DSM 错误映射集中处理。

struct NASFileBrowserView: View {
    let device: DashboardDevice
    let volume: SynologyStorageVolume
    let connection: SynologyFileConnection

    @Environment(\.dismiss) private var dismiss
    @State private var service: SynologyFileService?
    @State private var shares: [SynologySharedFolder] = []
    @State private var filesByPath: [String: [SynologyFileItem]] = [:]
    @State private var pathStack: [FileBrowserPath] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var newFolderName = ""
    @State private var renameText = ""
    @State private var showingNewFolder = false
    @State private var renamingItem: SynologyFileItem?
    @State private var deletingItem: SynologyFileItem?
    @State private var movingItem: SynologyFileItem?
    @State private var movingDestinationPath = ""
    @State private var pendingUploadOverwrite: PendingUploadOverwrite?
    @State private var showingImporter = false
    @State private var shareItem: ShareFileItem?

    private var currentPath: FileBrowserPath? {
        pathStack.last
    }

    private var currentFiles: [SynologyFileItem] {
        guard let currentPath else { return [] }
        return filesByPath[currentPath.path] ?? []
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                DetailTopBar(title: volume.name, subtitle: currentSubtitle, isRefreshing: isLoading, onRefresh: {
                    Task { await reloadCurrent() }
                }, onBack: {
                    close()
                })

                FileBrowserHeader(volume: volume, currentPath: currentPath, isLoading: isLoading) {
                    goUp()
                }

                if pathStack.isEmpty {
                    sharedFolderList
                } else {
                    directoryList
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .background(ServeraBackground().ignoresSafeArea())
        .task {
            await connectAndLoad()
        }
        .refreshable {
            await reloadCurrent()
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(activityItems: [item.url])
                .presentationDetents([.medium])
        }
        .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("文件已存在", isPresented: Binding(get: { pendingUploadOverwrite != nil }, set: { if !$0 { pendingUploadOverwrite = nil } })) {
            Button("覆盖", role: .destructive) {
                let pending = pendingUploadOverwrite
                pendingUploadOverwrite = nil
                Task { await uploadPending(pending, overwrite: true) }
            }
            Button("取消", role: .cancel) {
                pendingUploadOverwrite = nil
            }
        } message: {
            Text("\(pendingUploadOverwrite?.fileName ?? "此文件") 已存在，是否覆盖 NAS 上的旧文件？")
        }
        .alert("新建文件夹", isPresented: $showingNewFolder) {
            TextField("文件夹名称", text: $newFolderName)
            Button("创建") {
                let name = newFolderName
                newFolderName = ""
                Task { await createFolder(name: name) }
            }
            Button("取消", role: .cancel) {
                newFolderName = ""
            }
        } message: {
            Text("将在当前目录创建新文件夹。")
        }
        .alert("重命名", isPresented: Binding(get: { renamingItem != nil }, set: { if !$0 { renamingItem = nil } })) {
            TextField("新名称", text: $renameText)
            Button("保存") {
                let item = renamingItem
                let name = renameText
                renamingItem = nil
                renameText = ""
                Task { await rename(item: item, newName: name) }
            }
            Button("取消", role: .cancel) {
                renamingItem = nil
                renameText = ""
            }
        } message: {
            Text("DSM 会按当前账号权限执行重命名。")
        }
        .alert("删除项目？", isPresented: Binding(get: { deletingItem != nil }, set: { if !$0 { deletingItem = nil } })) {
            Button("删除", role: .destructive) {
                let item = deletingItem
                deletingItem = nil
                Task { await delete(item: item) }
            }
            Button("取消", role: .cancel) {
                deletingItem = nil
            }
        } message: {
            Text("删除后会在 NAS 上真实生效，请确认 DSM 权限和路径。")
        }
        .alert("移动项目", isPresented: Binding(get: { movingItem != nil }, set: { if !$0 { movingItem = nil } })) {
            TextField("目标文件夹路径", text: $movingDestinationPath)
            Button("移动") {
                let item = movingItem
                let destination = movingDestinationPath
                movingItem = nil
                movingDestinationPath = ""
                Task { await move(item: item, destination: destination) }
            }
            Button("取消", role: .cancel) {
                movingItem = nil
                movingDestinationPath = ""
            }
        } message: {
            Text("请输入 DSM 中的目标文件夹路径，例如 /home 或 /photo。")
        }
        .edgeSwipeBack {
            close()
        }
        .onDisappear {
            Task { await service?.close() }
        }
    }

    private var currentSubtitle: String {
        if pathStack.isEmpty { return "共享文件夹" }
        return currentPath?.displayName ?? "文件"
    }

    private var sharedFolderList: some View {
        ServeraCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 12) {
                FileSectionTitle(icon: "folder.badge.gearshape", title: "共享文件夹", trailing: "\(shares.count)")
                if isLoading && shares.isEmpty {
                    LoadingFileRows()
                } else if shares.isEmpty {
                    FileEmptyState(title: "暂无共享文件夹", message: "当前 DSM 账号没有可见共享文件夹，或 File Station 权限尚未开放。")
                } else {
                    VStack(spacing: 8) {
                        ForEach(shares) { share in
                            Button {
                                openShare(share)
                            } label: {
                                SharedFolderRow(share: share)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var directoryList: some View {
        ServeraCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    FileSectionTitle(icon: "folder", title: currentPath?.displayName ?? "文件", trailing: "\(currentFiles.count)")
                    Spacer()
                    Menu {
                        Button {
                            showingImporter = true
                        } label: {
                            Label("上传文件", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            showingNewFolder = true
                        } label: {
                            Label("新建文件夹", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(Color.serveraAccentDeep)
                            .frame(width: 34, height: 34)
                            .background(Color.serveraTintSoft, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                if isLoading && currentFiles.isEmpty {
                    LoadingFileRows()
                } else if currentFiles.isEmpty {
                    FileEmptyState(title: "此文件夹为空", message: "可以上传文件或新建文件夹。")
                } else {
                    VStack(spacing: 8) {
                        ForEach(currentFiles) { item in
                            FileItemRow(item: item) {
                                if item.isDirectory {
                                    openDirectory(item)
                                } else {
                                    Task { await download(item: item) }
                                }
                            } onRename: {
                                renamingItem = item
                                renameText = item.name
                            } onMove: {
                                movingItem = item
                                movingDestinationPath = currentPath?.path ?? ""
                            } onDelete: {
                                deletingItem = item
                            }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func connectAndLoad() async {
        // 每个浏览会话只连接一次。File Station sid 保存在 service 中，直到页面关闭。
        guard service == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fileService = SynologyFileService(connection: connection)
            try await fileService.connect()
            service = fileService
            shares = try await fileService.listSharedFolders(for: volume)
        } catch {
            handle(error)
        }
    }

    @MainActor
    private func reloadCurrent() async {
        // currentPath == nil 表示共享列表；否则刷新当前文件夹，并按 DSM 绝对路径缓存。
        guard !isLoading else { return }
        if service == nil {
            await connectAndLoad()
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            guard let service else { return }
            if let currentPath {
                filesByPath[currentPath.path] = try await service.listDirectory(path: currentPath.path)
            } else {
                shares = try await service.listSharedFolders(for: volume)
            }
        } catch {
            handle(error)
        }
    }

    @MainActor
    private func openShare(_ share: SynologySharedFolder) {
        // 路径栈同时作为面包屑和当前文件夹状态。
        pathStack = [FileBrowserPath(displayName: share.name, path: share.path)]
        Task { await reloadCurrent() }
    }

    @MainActor
    private func openDirectory(_ item: SynologyFileItem) {
        pathStack.append(FileBrowserPath(displayName: item.name, path: item.path))
        Task { await reloadCurrent() }
    }

    @MainActor
    private func goUp() {
        if !pathStack.isEmpty {
            pathStack.removeLast()
        }
    }

    private func close() {
        Task { await service?.close() }
        dismiss()
    }

    @MainActor
    private func createFolder(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let currentPath else { return }
        await performFileMutation {
            try await service?.createFolder(parentPath: currentPath.path, name: trimmed)
        }
    }

    @MainActor
    private func rename(item: SynologyFileItem?, newName: String) async {
        guard let item else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await performFileMutation {
            try await service?.rename(path: item.path, newName: trimmed)
        }
    }

    @MainActor
    private func delete(item: SynologyFileItem?) async {
        guard let item else { return }
        await performFileMutation {
            try await service?.delete(paths: [item.path])
        }
    }

    @MainActor
    private func move(item: SynologyFileItem?, destination: String) async {
        guard let item, currentPath != nil else { return }
        let trimmedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDestination.isEmpty else { return }
        await performFileMutation {
            try await service?.move(paths: [item.path], destinationFolderPath: trimmedDestination)
        }
    }

    @MainActor
    private func download(item: SynologyFileItem) async {
        // 下载先落到临时文件，再弹系统分享面板；App 不维护持久下载目录。
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            guard let service else { return }
            shareItem = ShareFileItem(url: try await service.download(path: item.path))
        } catch {
            handle(error)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            Task { @MainActor in
                await upload(url: url)
            }
        } catch {
            // 用户主动取消文件选择时保持静默。
            if !error.localizedDescription.localizedCaseInsensitiveContains("cancel") {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func upload(url: URL) async {
        guard let currentPath else { return }
        await uploadPending(
            PendingUploadOverwrite(url: url, destinationPath: currentPath.path, fileName: url.lastPathComponent),
            overwrite: false
        )
    }

    @MainActor
    private func uploadPending(_ pending: PendingUploadOverwrite?, overwrite: Bool) async {
        guard let pending, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        // iOS 文件选择器返回 security-scoped URL。SynologyFileService 读取 Data 前
        // 必须先打开访问权限。
        let didAccess = pending.url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { pending.url.stopAccessingSecurityScopedResource() }
        }

        do {
            try await service?.upload(
                localFileURL: pending.url,
                destinationFolderPath: pending.destinationPath,
                overwrite: overwrite
            )
            if currentPath?.path == pending.destinationPath {
                filesByPath[pending.destinationPath] = try await service?.listDirectory(path: pending.destinationPath) ?? []
            }
        } catch {
            if !overwrite, isUploadConflict(error) {
                // 第一次上传默认不覆盖。DSM 冲突转为用户确认，再用同一个本地 URL 重试。
                pendingUploadOverwrite = PendingUploadOverwrite(
                    url: pending.url,
                    destinationPath: pending.destinationPath,
                    fileName: pending.fileName
                )
                return
            }
            handle(error)
        }
    }

    private func isUploadConflict(_ error: Error) -> Bool {
        if error is SynologyFileUploadConflict { return true }
        let message = error.localizedDescription
        return message.contains("文件已存在")
            || message.contains("是否覆盖")
            || message.contains("错误码 414")
    }

    @MainActor
    private func performFileMutation(_ operation: () async throws -> Void) async {
        // 新建/重命名/删除/移动统一处理 loading 和错误，再从 DSM 读回当前目录，
        // 避免 UI 假装成功。
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await operation()
            if let currentPath {
                filesByPath[currentPath.path] = try await service?.listDirectory(path: currentPath.path) ?? []
            }
        } catch {
            handle(error)
        }
    }

    @MainActor
    private func handle(_ error: Error) {
        if error is CancellationError { return }
        errorMessage = error.localizedDescription
    }
}

private struct FileBrowserPath: Hashable {
    var displayName: String
    var path: String
}

private struct ShareFileItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PendingUploadOverwrite {
    let url: URL
    let destinationPath: String
    let fileName: String
}

private struct FileBrowserHeader: View {
    let volume: SynologyStorageVolume
    let currentPath: FileBrowserPath?
    let isLoading: Bool
    let onUp: () -> Void

    var body: some View {
        ServeraCard(cornerRadius: 28) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(Color.serveraAccentDeep)
                    .frame(width: 44, height: 44)
                    .background(Color.serveraTintSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentPath?.displayName ?? volume.name)
                        .font(.system(size: 19, weight: .black))
                        .lineLimit(1)
                    Text(currentPath?.path ?? "选择共享文件夹")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.serveraTextSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if currentPath != nil {
                    Button(action: onUp) {
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(Color.serveraLeaf)
                            .frame(width: 38, height: 38)
                            .background(Color.serveraLeafSoft, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                if isLoading {
                    ProgressView()
                        .tint(Color.serveraAccentDeep)
                }
            }
        }
    }
}

private struct FileSectionTitle: View {
    let icon: String
    let title: String
    let trailing: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title)
                .lineLimit(1)
            Spacer()
            Text(trailing)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.serveraTextSecondary)
        }
        .font(.system(size: 18, weight: .black))
        .foregroundStyle(Color.serveraAccentDeep)
    }
}

private struct SharedFolderRow: View {
    let share: SynologySharedFolder

    var body: some View {
        HStack(spacing: 12) {
            FileIcon(systemName: "folder.fill", color: .serveraAmber)
            VStack(alignment: .leading, spacing: 3) {
                Text(share.name)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(share.path)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color.serveraTextSecondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.serveraBorder.opacity(0.48), lineWidth: 1)
        )
    }
}

private struct FileItemRow: View {
    let item: SynologyFileItem
    let onOpen: () -> Void
    let onRename: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                FileIcon(systemName: iconName, color: item.isDirectory ? .serveraAmber : .serveraSky)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(item.displaySize) · \(item.modifiedText)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.serveraTextSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Menu {
                    Button(action: onRename) {
                        Label("重命名", systemImage: "pencil")
                    }
                    Button(action: onMove) {
                        Label("移动", systemImage: "folder")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(Color.serveraTextSecondary)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.65), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.serveraBorder.opacity(0.48), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        if item.isDirectory { return "folder.fill" }
        switch item.fileExtension {
        case "jpg", "jpeg", "png", "heic", "webp": return "photo"
        case "mp4", "mov", "mkv": return "play.rectangle"
        case "pdf": return "doc.richtext"
        case "zip", "rar", "7z": return "archivebox"
        default: return "doc"
        }
    }
}

private struct FileIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 20, weight: .black))
            .foregroundStyle(color)
            .frame(width: 42, height: 42)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct FileEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(Color.serveraTextSecondary)
            Text(title)
                .font(.system(size: 18, weight: .black))
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.serveraTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

private struct LoadingFileRows: View {
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.serveraTintSoft.opacity(0.5))
                    .frame(height: 66)
                    .overlay(alignment: .leading) {
                        ProgressView()
                            .tint(Color.serveraAccentDeep)
                            .padding(.leading, 18)
                    }
            }
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
