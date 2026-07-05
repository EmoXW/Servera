import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - SFTP 文件浏览器
// 沿用 ServeraCard / HeaderBar / ServeraBackground / serveraAccent 配色，
// 与设置页、详情页保持一致的玻璃卡片质感。

struct SFTPView: View {
    let device: DashboardDevice

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var currentPath: String = ""
    @State private var entries: [SFTPEntry] = []
    @State private var pathStack: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var connectionState: SFTPConnectionState = .idle
    @State private var pendingAction: SFTPAction?
    @State private var newFolderName = ""
    @State private var renameTarget: SFTPEntry?
    @State private var renameText = ""
    @State private var isImportingFile = false
    @State private var isExportingFile = false
    @State private var exportDocument: SFTPFileDocument?
    @State private var exportFilename: String = "download"
    @State private var transferProgress: Double?
    @State private var transferLabel: String = ""

    var body: some View {
        ZStack {
            ServeraBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                sftpHeader
                pathBreadcrumb
                contentList
                if let progress = transferProgress {
                    transferBar(progress: progress)
                }
            }
        }
        .task {
            await initializeSession()
        }
        .onDisappear {
            connectionState = .closed
        }
        .edgeSwipeBack {
            dismiss()
        }
        .alert("SFTP", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $pendingAction) { action in
            switch action {
            case .newFolder:
                NavigationStack {
                    SFTPInputSheet(
                        title: "新建文件夹",
                        placeholder: "文件夹名称",
                        confirmTitle: "创建"
                    ) { name in
                        newFolderName = name
                        pendingAction = nil
                        Task { await createFolder(name: name) }
                    }
                }
                .presentationDetents([.medium])
            case .rename(let entry):
                NavigationStack {
                    SFTPInputSheet(
                        title: "重命名",
                        placeholder: "新名称",
                        initialText: entry.name,
                        confirmTitle: "保存"
                    ) { name in
                        renameText = name
                        pendingAction = nil
                        Task { await renameEntry(entry, to: name) }
                    }
                }
                .presentationDetents([.medium])
            }
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.item]
        ) { result in
            switch result {
            case .success(let url):
                Task { await uploadFile(from: url) }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $isExportingFile,
            document: exportDocument,
            contentType: .data,
            defaultFilename: exportFilename
        ) { _ in
            exportDocument = nil
        }
    }

    // MARK: - 头部

    private var sftpHeader: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.78), in: Circle())
                    .shadow(color: Color.serveraAccent.opacity(0.14), radius: 16, y: 8)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text("文件管理")
                    .font(.system(size: 22, weight: .black))
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionState.tint)
                        .frame(width: 7, height: 7)
                    Text(connectionState.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.serveraTextSecondary)
                }
            }

            Spacer()

            Button {
                pendingAction = .newFolder
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Color.serveraAccentDeep)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.78), in: Circle())
                    .shadow(color: Color.serveraAccent.opacity(0.14), radius: 16, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(connectionState != .connected)

            Button {
                isImportingFile = true
            } label: {
                Image(systemName: "arrow.up.to.line.alt")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Color.serveraAccentDeep)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.78), in: Circle())
                    .shadow(color: Color.serveraAccent.opacity(0.14), radius: 16, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(connectionState != .connected)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - 路径面包屑

    private var pathBreadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    pathStack.removeAll()
                    currentPath = ""
                    Task { await loadDirectory("/") }
                } label: {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color.serveraAccentDeep)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.serveraTintSoft, in: Capsule())
                }
                .buttonStyle(.plain)

                ForEach(pathStack.indices, id: \.self) { index in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Color.serveraTextSecondary.opacity(0.55))

                    Button {
                        let target = pathStack[...index].joined(separator: "/")
                        pathStack.removeLast(pathStack.count - index - 1)
                        Task { await loadDirectory(target) }
                    } label: {
                        Text(pathStack[index])
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.66), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    // MARK: - 文件列表

    private var contentList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                if isLoading && entries.isEmpty {
                    SFTPEmptyState(
                        icon: "arrow.triangle.2.circlepath",
                        title: "正在加载",
                        subtitle: "正在连接服务器并读取目录…"
                    )
                } else if entries.isEmpty {
                    SFTPEmptyState(
                        icon: "tray",
                        title: "空文件夹",
                        subtitle: "点击右上角上传文件或新建文件夹。"
                    )
                } else {
                    ForEach(entries) { entry in
                        SFTPEntryRow(
                            entry: entry,
                            onOpen: {
                                if entry.isDirectory {
                                    pathStack.append(entry.name)
                                    Task { await loadDirectory(entry.absolutePath) }
                                } else {
                                    Task { await downloadFile(entry: entry) }
                                }
                            },
                            onRename: {
                                pendingAction = .rename(entry)
                            },
                            onDelete: {
                                Task { await deleteEntry(entry) }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 32)
        }
        .refreshable {
            await loadDirectory(currentPath)
        }
    }

    // MARK: - 传输进度条

    private func transferBar(progress: Double) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(transferLabel)
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Color.serveraAccentDeep)
            }
            ProgressView(value: progress)
                .tint(Color.serveraAccentDeep)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - 业务逻辑

    private func initializeSession() async {
        connectionState = .connecting
        do {
            let request = try makeRequest()
            let home = try await SFTPService.shared.homeDirectory(for: request)
            currentPath = home
            pathStack = home.split(separator: "/").map(String.init)
            connectionState = .connected
            await loadDirectory(home)
        } catch {
            connectionState = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func loadDirectory(_ path: String) async {
        isLoading = true
        currentPath = path
        do {
            let request = try makeRequest()
            entries = try await SFTPService.shared.listDirectory(path, for: request)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func createFolder(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newPath = currentPath.hasSuffix("/") ? "\(currentPath)\(trimmed)" : "\(currentPath)/\(trimmed)"
        do {
            let request = try makeRequest()
            try await SFTPService.shared.createDirectory(newPath, for: request)
            await loadDirectory(currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renameEntry(_ entry: SFTPEntry, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != entry.name else { return }
        let parent = entry.absolutePath.contains("/")
            ? String(entry.absolutePath.dropLast(entry.name.count).dropLast())
            : ""
        let newPath = parent.isEmpty ? "/\(trimmed)" : "\(parent)/\(trimmed)"
        do {
            let request = try makeRequest()
            try await SFTPService.shared.rename(entry.absolutePath, to: newPath, for: request)
            await loadDirectory(currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteEntry(_ entry: SFTPEntry) async {
        do {
            let request = try makeRequest()
            if entry.isDirectory {
                try await SFTPService.shared.removeDirectory(entry.absolutePath, for: request)
            } else {
                try await SFTPService.shared.removeFile(entry.absolutePath, for: request)
            }
            await loadDirectory(currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadFile(from localURL: URL) async {
        transferLabel = "正在上传 \(localURL.lastPathComponent)"
        transferProgress = 0
        let remotePath = currentPath.hasSuffix("/")
            ? "\(currentPath)\(localURL.lastPathComponent)"
            : "\(currentPath)/\(localURL.lastPathComponent)"
        do {
            let didAccess = localURL.startAccessingSecurityScopedResource()
            defer { if didAccess { localURL.stopAccessingSecurityScopedResource() } }
            let request = try makeRequest()
            try await SFTPService.shared.uploadFile(
                localURL,
                to: remotePath,
                for: request,
                progress: { ratio in
                    await MainActor.run {
                        transferProgress = ratio
                    }
                }
            )
            transferProgress = nil
            await loadDirectory(currentPath)
        } catch {
            transferProgress = nil
            errorMessage = error.localizedDescription
        }
    }

    private func downloadFile(entry: SFTPEntry) async {
        transferLabel = "正在下载 \(entry.name)"
        transferProgress = 0
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(entry.name)
        do {
            let request = try makeRequest()
            try await SFTPService.shared.downloadFile(
                entry.absolutePath,
                to: temporaryURL,
                for: request,
                progress: { ratio in
                    await MainActor.run {
                        transferProgress = ratio
                    }
                }
            )
            transferProgress = nil
            let data = try Data(contentsOf: temporaryURL)
            exportDocument = SFTPFileDocument(data: data)
            exportFilename = entry.name
            isExportingFile = true
        } catch {
            transferProgress = nil
            errorMessage = error.localizedDescription
        }
    }

    private func makeRequest() throws -> SSHConnectionRequest {
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
        return SSHConnectionRequest(
            host: record.host,
            port: record.port,
            username: record.account,
            authenticationKind: record.authenticationKind,
            credential: credential,
            acceptUnknownHostKey: false
        )
    }
}

// MARK: - 子组件

enum SFTPAction: Identifiable {
    case newFolder
    case rename(SFTPEntry)

    var id: String {
        switch self {
        case .newFolder: "newFolder"
        case .rename(let entry): "rename-\(entry.id)"
        }
    }
}

enum SFTPConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case failed
    case closed

    var title: String {
        switch self {
        case .idle: "等待连接"
        case .connecting: "正在连接…"
        case .connected: "已连接"
        case .failed: "连接失败"
        case .closed: "已断开"
        }
    }

    var tint: Color {
        switch self {
        case .idle: Color.serveraTextSecondary
        case .connecting: Color.serveraAmber
        case .connected: Color.serveraLeaf
        case .failed, .closed: Color.serveraAccentDeep
        }
    }
}

struct SFTPEntryRow: View {
    let entry: SFTPEntry
    var onOpen: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void

    @State private var isShowingActions = false

    var body: some View {
        Button {
            onOpen()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: entry.isDirectory ? "folder.fill" : iconForFile)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(entry.isDirectory ? Color.serveraAccentDeep : Color.serveraSky)
                    .frame(width: 44, height: 44)
                    .background(
                        (entry.isDirectory ? Color.serveraTintSoft : Color.serveraSky.opacity(0.18)),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.serveraTextSecondary)
                }

                Spacer()

                if !entry.isDirectory {
                    Image(systemName: "arrow.down.to.line.alt")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color.serveraTextSecondary.opacity(0.6))
                }

                Menu {
                    Button {
                        onRename()
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(Color.serveraTextSecondary)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(14)
            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.serveraBorder.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var iconForFile: String {
        let ext = (entry.name as NSString).pathExtension.lowercased()
        switch ext {
        case "txt", "md", "log": "doc.text.fill"
        case "png", "jpg", "jpeg", "gif", "heic": "photo.fill"
        case "mp4", "mov", "avi", "mkv": "film.fill"
        case "mp3", "wav", "flac": "music.note"
        case "zip", "tar", "gz", "rar", "7z": "archivebox.fill"
        case "json", "xml", "yaml", "yml", "toml": "curlybraces"
        case "sh", "bash": "terminal.fill"
        case "pdf": "doc.richtext.fill"
        default: "doc.fill"
        }
    }

    private var subtitle: String {
        if entry.isDirectory {
            return "文件夹"
        }
        if let size = entry.sizeBytes, let intSize = Int64(exactly: size) {
            return ServerStatusParser.byteText(intSize)
        }
        return "文件"
    }
}

struct SFTPEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .heavy))
                .foregroundStyle(Color.serveraAccentDeep.opacity(0.7))
                .frame(width: 72, height: 72)
                .background(Color.serveraTintSoft, in: Circle())
            Text(title)
                .font(.system(size: 18, weight: .black))
            Text(subtitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.serveraTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

struct SFTPInputSheet: View {
    let title: String
    let placeholder: String
    var initialText: String = ""
    let confirmTitle: String
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color.serveraBorder)
                .frame(width: 42, height: 5)
                .padding(.top, 8)

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(Color.serveraAccentDeep)
                .frame(width: 64, height: 64)
                .background(Color.serveraTintSoft, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            Text(title)
                .font(.system(size: 24, weight: .black))

            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.serveraBorder, lineWidth: 1))

            Button {
                onConfirm(text)
                dismiss()
            } label: {
                Text(confirmTitle)
            }
            .font(.system(size: 17, weight: .heavy))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(.white)
            .background(text.isEmpty ? Color.serveraTextSecondary.opacity(0.38) : Color.serveraAccentDeep, in: Capsule())
            .disabled(text.isEmpty)
        }
        .padding(22)
        .background(ServeraBackground().ignoresSafeArea())
        .onAppear {
            text = initialText
        }
    }
}

// MARK: - 文件导出辅助

struct SFTPFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }

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
