import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - 设置与备份界面
// 设置页目前承载备份导入/导出和 Pro 展示。备份工作交给 BackupService，
// 让加密和文件格式保持可测试。

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\ManagedDeviceRecord.orderIndex), SortDescriptor(\ManagedDeviceRecord.createdAt)])
    private var deviceRecords: [ManagedDeviceRecord]
    @State private var activeSheet: SettingsSheet?
    @State private var exportDocument = BackupFileDocument()
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var pendingImportPassword = ""
    @State private var resultMessage: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                HeaderBar(title: "设置")

                Button {
                    activeSheet = .premium
                } label: {
                    ServeraCard(cornerRadius: 32) {
                        VStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(LinearGradient(colors: [.black.opacity(0.82), .serveraAccentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 58, height: 58)
                                .overlay(Image(systemName: "sparkle").font(.title2.weight(.heavy)).foregroundStyle(.white))
                            Text("获取 Pro")
                                .font(.system(size: 26, weight: .black))
                            Text("解锁服务器 Docker 操作、数据同步、文件编辑和高级主题。")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.serveraTextSecondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 10) {
                    Text("数据保护")
                        .font(.system(size: 18, weight: .black))
                        .padding(.horizontal, 6)

                    ServeraCard(cornerRadius: 28) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.shield.fill")
                                    .font(.system(size: 22, weight: .heavy))
                                    .foregroundStyle(Color.serveraAmber)
                                    .frame(width: 38, height: 38)
                                    .background(Color.serveraAmber.opacity(0.13), in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("未开启同步时请先备份")
                                        .font(.system(size: 17, weight: .black))
                                    Text("删除 App 会清除本机设备配置。手动加密备份可免费使用，iCloud 自动同步属于 Pro。")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.serveraTextSecondary)
                                        .lineSpacing(2)
                                }
                            }

                            Divider().overlay(Color.serveraBorder)

                            SettingsActionRow(icon: "lock.doc", title: "导出加密备份", value: "免费") {
                                activeSheet = .backupExport
                            }

                            SettingsActionRow(icon: "square.and.arrow.down", title: "恢复备份", value: "导入") {
                                activeSheet = .backupRestore
                            }
                        }
                    }
                }

                ServeraCard(cornerRadius: 28) {
                    VStack(spacing: 0) {
                        SettingsRow(icon: "icloud", title: "iCloud 同步", value: "未开启")
                        Button {
                            activeSheet = .theme
                        } label: {
                            SettingsRow(icon: "circle.lefthalf.filled", title: "柔光主题", value: "默认")
                        }
                        .buttonStyle(.plain)
                        SettingsRow(icon: "faceid", title: "Face ID 安全验证", value: "已开启")
                        SettingsRow(icon: "envelope", title: "反馈", value: "发送")
                        SettingsRow(icon: "star.fill", title: "评价 App", value: "去评分", showDivider: false)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .premium:
                PremiumSheet()
                    .presentationDetents([.medium])
            case .theme:
                ThemeSheet()
                    .presentationDetents([.large])
            case .backupExport:
                BackupSheet(mode: .export) { password in
                    prepareBackupExport(password: password)
                }
                    .presentationDetents([.medium])
            case .backupRestore:
                BackupSheet(mode: .restore) { password in
                    pendingImportPassword = password
                    activeSheet = nil
                    isImportingBackup = true
                }
                    .presentationDetents([.medium])
            }
        }
        .fileExporter(
            isPresented: $isExportingBackup,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Servera-Backup"
        ) { result in
            switch result {
            case .success:
                resultMessage = "加密备份已导出。请记住备份密码，首版备份不包含明文密码或私钥。"
            case .failure(let error):
                resultMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $isImportingBackup, allowedContentTypes: [.json]) { result in
            handleBackupImport(result)
        }
        .alert("数据保护", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func prepareBackupExport(password: String) {
        // 真正的编码/加密由备份服务完成；设置页只准备 SwiftUI 导出需要的文档对象。
        do {
            exportDocument = BackupFileDocument(data: try BackupService.exportData(from: deviceRecords, password: password))
            activeSheet = nil
            isExportingBackup = true
        } catch {
            resultMessage = error.localizedDescription
        }
    }

    private func handleBackupImport(_ result: Result<URL, Error>) {
        // 文件可能来自 iCloud/文件 App，读取加密备份字节前先申请 security-scoped 访问。
        do {
            let url = try result.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            let restoredCount = try BackupService.importData(data, password: pendingImportPassword, into: modelContext, existingRecords: deviceRecords)
            pendingImportPassword = ""
            resultMessage = "已恢复 \(restoredCount) 台设备的基础配置。密码、私钥和 DSM Token 需要重新验证。"
        } catch {
            pendingImportPassword = ""
            resultMessage = error.localizedDescription
        }
    }
}

enum SettingsSheet: Identifiable {
    case premium
    case theme
    case backupExport
    case backupRestore

    var id: String {
        switch self {
        case .premium: "premium"
        case .theme: "theme"
        case .backupExport: "backupExport"
        case .backupRestore: "backupRestore"
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let value: String
    var showDivider = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .frame(width: 26)
            Text(title)
                .font(.system(size: 17, weight: .bold))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.serveraTextSecondary)
        }
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) {
            if showDivider {
                Rectangle().fill(Color.serveraBorder.opacity(0.6)).frame(height: 1)
            }
        }
    }
}

struct SettingsActionRow: View {
    let icon: String
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .frame(width: 26)
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Text(value)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.serveraAccentDeep)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.serveraTextSecondary.opacity(0.55))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ThemeSheet: View {
    @State private var selectedAccent = Color.serveraAccentDeep
    @State private var selectedIcon = "Default"

    private let accents: [Color] = [
        .serveraAccentDeep, .serveraAccent, .serveraSky, .serveraLeaf,
        .serveraAmber, .purple, .cyan, .red
    ]
    private let icons = ["Default", "Pink Glass", "Blue Shell", "Classic"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Capsule()
                    .fill(Color.serveraBorder)
                    .frame(width: 42, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                Text("主题外观")
                    .font(.system(size: 32, weight: .black))

                ServeraCard(cornerRadius: 30) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("主题色")
                            .font(.system(size: 18, weight: .heavy))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                            ForEach(accents.indices, id: \.self) { index in
                                Button {
                                    selectedAccent = accents[index]
                                } label: {
                                    Circle()
                                        .fill(accents[index])
                                        .frame(width: 48, height: 48)
                                        .overlay {
                                            Circle()
                                                .stroke(.white, lineWidth: 4)
                                                .opacity(selectedAccent == accents[index] ? 1 : 0)
                                        }
                                        .shadow(color: accents[index].opacity(0.28), radius: 12, y: 8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                ServeraCard(cornerRadius: 30) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("应用图标")
                            .font(.system(size: 18, weight: .heavy))
                        ForEach(icons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                HStack(spacing: 14) {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(iconGradient(icon))
                                        .frame(width: 54, height: 54)
                                        .overlay(Image(systemName: "sparkles").foregroundStyle(.white).fontWeight(.heavy))
                                    Text(icon)
                                        .font(.system(size: 17, weight: .bold))
                                    Spacer()
                                    if selectedIcon == icon {
                                        Image(systemName: "checkmark")
                                            .font(.headline.weight(.heavy))
                                            .foregroundStyle(Color.serveraAccentDeep)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(22)
        }
        .background(ServeraBackground().ignoresSafeArea())
    }

    private func iconGradient(_ icon: String) -> LinearGradient {
        switch icon {
        case "Pink Glass":
            LinearGradient(colors: [.serveraTint, .serveraAccentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "Blue Shell":
            LinearGradient(colors: [.serveraSky, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "Classic":
            LinearGradient(colors: [.black.opacity(0.82), .gray], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            LinearGradient(colors: [.black.opacity(0.82), .serveraAccentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct BackupSheet: View {
    let mode: BackupMode
    let action: (String) -> Void
    @State private var password = ""

    var body: some View {
        // 导入/导出共用同一个 sheet，保证加密文案和密码校验一致。
        VStack(spacing: 18) {
            Capsule()
                .fill(Color.serveraBorder)
                .frame(width: 42, height: 5)
                .padding(.top, 8)

            Image(systemName: "lock.doc")
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(Color.serveraAccentDeep)
                .frame(width: 72, height: 72)
                .background(Color.serveraTintSoft, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            Text("加密备份")
                .font(.system(size: 30, weight: .black))

            Text(mode.description)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.serveraTextSecondary)
                .lineSpacing(3)

            SecureField(mode.passwordPlaceholder, text: $password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.serveraBorder, lineWidth: 1))

            Button {
                action(password)
            } label: {
                Text(mode.buttonTitle)
            }
                .font(.system(size: 17, weight: .heavy))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(.white)
                .background(password.isEmpty ? Color.serveraTextSecondary.opacity(0.38) : Color.serveraAccentDeep, in: Capsule())
                .disabled(password.isEmpty)
        }
        .padding(22)
        .background(ServeraBackground().ignoresSafeArea())
    }
}

enum BackupMode {
    case export
    case restore

    var description: String {
        switch self {
        case .export:
            "免费用户可以导出一份加密备份文件，保存服务器和 NAS 基础配置。请自己保存备份密码；密码、私钥等敏感凭据默认不明文导出。"
        case .restore:
            "输入导出时设置的备份密码，然后选择备份文件恢复。恢复后敏感凭据需要重新验证。"
        }
    }

    var buttonTitle: String {
        switch self {
        case .export: "导出加密备份"
        case .restore: "选择备份文件恢复"
        }
    }

    var passwordPlaceholder: String {
        switch self {
        case .export: "设置备份密码"
        case .restore: "输入备份密码"
        }
    }
}

struct PremiumSheet: View {
    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color.serveraBorder)
                .frame(width: 42, height: 5)
                .padding(.top, 8)

            Text("Servera Pro")
                .font(.system(size: 30, weight: .black))

            Text("更适合多服务器、服务器 Docker 操作、文件预览编辑和数据同步的高级工作流。")
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.serveraTextSecondary)

            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                PremiumFeature(title: "无限设备", icon: "infinity")
                PremiumFeature(title: "服务器 Docker", icon: "shippingbox")
                PremiumFeature(title: "文件编辑", icon: "doc.text")
                PremiumFeature(title: "iCloud 同步", icon: "icloud")
            }

            Button("继续查看") {}
                .font(.system(size: 17, weight: .heavy))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(.white)
                .background(Color.serveraAccentDeep, in: Capsule())
        }
        .padding(22)
        .background(ServeraBackground().ignoresSafeArea())
    }
}

struct PremiumFeature: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Color.serveraAccentDeep)
            Text(title)
                .font(.system(size: 14, weight: .bold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
