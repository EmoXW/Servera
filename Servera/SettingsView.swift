import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - 设置与备份界面
// 设置页目前承载备份导入/导出和主题切换。备份工作交给 BackupService，
// 让加密和文件格式保持可测试。

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("servera.theme.id") private var selectedThemeID = ServeraThemePreset.fallback.id
    @AppStorage("servera.biometricAuth.enabled") private var isBiometricAuthEnabled = false
    @Query(sort: [SortDescriptor(\ManagedDeviceRecord.orderIndex), SortDescriptor(\ManagedDeviceRecord.createdAt)])
    private var deviceRecords: [ManagedDeviceRecord]
    @State private var activeSheet: SettingsSheet?
    @State private var exportDocument = BackupFileDocument()
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var pendingImportPassword = ""
    @State private var resultMessage: String?
    @State private var biometricAvailability: BiometricAvailability = .notAvailable

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                HeaderBar(title: "设置")

                Button {
                    if let url = URL(string: "https://www.emoxw.cn") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    ServeraCard(cornerRadius: 32) {
                        VStack(spacing: 12) {
                            if let uiImage = UIImage(named: "8ce-avatar.png") {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 58, height: 58)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(LinearGradient(colors: [.black.opacity(0.82), .serveraAccentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 58, height: 58)
                                    .overlay(Image(systemName: "person.fill").font(.title2.weight(.heavy)).foregroundStyle(.white))
                            }
                            Text("8CE")
                                .font(.system(size: 26, weight: .black))
                            Text("访问个人主页，了解更多内容。")
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
                                    Text("删除 App 会清除本机设备配置。建议定期导出加密备份。")
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
                        Button {
                            activeSheet = .theme
                        } label: {
                            SettingsRow(icon: "circle.lefthalf.filled", title: "设置主题", value: currentTheme.name)
                        }
                        .buttonStyle(.plain)
                        if biometricAvailability.isAvailable {
                            Toggle(isOn: Binding(
                                get: { isBiometricAuthEnabled },
                                set: { newValue in
                                    Task { await toggleBiometricAuth(newValue) }
                                }
                            )) {
                                HStack(spacing: 14) {
                                    Image(systemName: biometricAvailability.type == .faceID ? "faceid" : "touchid")
                                        .frame(width: 26)
                                    Text(biometricAvailability.type == .faceID ? "Face ID 安全验证" : "Touch ID 安全验证")
                                        .font(.system(size: 17, weight: .bold))
                                }
                            }
                            .tint(Color.serveraAccentDeep)
                            .padding(.vertical, 15)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
        .onAppear {
            Task {
                biometricAvailability = await BiometricAuthService.shared.availability()
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
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

    private var currentTheme: ServeraThemePreset {
        ServeraThemePreset.preset(for: selectedThemeID)
    }

    private func toggleBiometricAuth(_ newValue: Bool) async {
        if newValue {
            do {
                let success = try await BiometricAuthService.shared.authenticate(
                    reason: "开启生物识别验证"
                )
                if success {
                    isBiometricAuthEnabled = true
                }
            } catch {
                isBiometricAuthEnabled = false
                resultMessage = error.localizedDescription
            }
        } else {
            isBiometricAuthEnabled = false
        }
    }

    private func prepareBackupExport(password: String) {
        Task {
            if isBiometricAuthEnabled {
                do {
                    let success = try await BiometricAuthService.shared.authenticate(
                        reason: "导出备份前需要验证身份"
                    )
                    guard success else { return }
                } catch {
                    resultMessage = error.localizedDescription
                    return
                }
            }
            await MainActor.run {
                do {
                    exportDocument = BackupFileDocument(data: try BackupService.exportData(from: deviceRecords, password: password))
                    activeSheet = nil
                    isExportingBackup = true
                } catch {
                    resultMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleBackupImport(_ result: Result<URL, Error>) {
        Task {
            if isBiometricAuthEnabled {
                do {
                    let success = try await BiometricAuthService.shared.authenticate(
                        reason: "恢复备份前需要验证身份"
                    )
                    guard success else {
                        isImportingBackup = false
                        return
                    }
                } catch {
                    await MainActor.run {
                        resultMessage = error.localizedDescription
                        isImportingBackup = false
                    }
                    return
                }
            }
            await MainActor.run {
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
                isImportingBackup = false
            }
        }
    }
}

enum SettingsSheet: Identifiable {
    case theme
    case backupExport
    case backupRestore

    var id: String {
        switch self {
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
    @AppStorage("servera.theme.id") private var selectedThemeID = ServeraThemePreset.fallback.id
    @AppStorage("servera.appearance.mode") private var appearanceModeRawValue = ServeraAppearanceMode.system.rawValue
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 2)

    private var selectedAppearanceMode: ServeraAppearanceMode {
        ServeraAppearanceMode.mode(for: appearanceModeRawValue)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Capsule()
                    .fill(Color.serveraBorder)
                    .frame(width: 42, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                Text("设置主题")
                    .font(.system(size: 32, weight: .black))

                Text("选择一套柔和混色主调，背景、底部导航和玻璃卡片会立即跟随变化。")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.serveraTextSecondary)
                    .lineSpacing(3)

                ServeraCard(cornerRadius: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("外观模式")
                            .font(.system(size: 18, weight: .black))

                        HStack(spacing: 10) {
                            ForEach(ServeraAppearanceMode.allCases) { mode in
                                ThemeAppearanceButton(
                                    mode: mode,
                                    isSelected: selectedAppearanceMode == mode
                                ) {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                        appearanceModeRawValue = mode.rawValue
                                    }
                                }
                            }
                        }
                    }
                }

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(ServeraThemePreset.presets) { preset in
                        ThemePresetCard(
                            preset: preset,
                            isSelected: selectedThemeID == preset.id
                        ) {
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                                selectedThemeID = preset.id
                            }
                        }
                    }
                }
            }
            .padding(22)
        }
        .environment(\.serveraTheme, ServeraThemePreset.preset(for: selectedThemeID))
        .background(ServeraBackground().ignoresSafeArea())
    }
}

struct ThemeAppearanceButton: View {
    @Environment(\.serveraTheme) private var theme
    let mode: ServeraAppearanceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: mode.icon)
                    .font(.system(size: 15, weight: .heavy))
                Text(mode.title)
                    .font(.system(size: 13, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(isSelected ? .white : theme.accentDeep)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? theme.accentDeep : theme.tintSoft.opacity(0.58))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isSelected ? Color.white.opacity(0.74) : theme.border.opacity(0.64), lineWidth: 1)
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

struct ThemePresetCard: View {
    let preset: ServeraThemePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [preset.background, preset.tintSoft, .white],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 104)
                        .overlay(alignment: .topLeading) {
                            Circle()
                                .fill(preset.tint.opacity(0.56))
                                .frame(width: 74, height: 74)
                                .blur(radius: 8)
                                .offset(x: -18, y: -14)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            Circle()
                                .fill(preset.leafSoft.opacity(0.92))
                                .frame(width: 72, height: 72)
                                .blur(radius: 10)
                                .offset(x: 16, y: 12)
                        }
                        .overlay(alignment: .center) {
                            Circle()
                                .fill(.white.opacity(0.72))
                                .frame(width: 54, height: 54)
                                .overlay(
                                    Image(systemName: preset.icon)
                                        .font(.system(size: 18, weight: .heavy))
                                        .foregroundStyle(preset.accentDeep)
                                )
                                .shadow(color: preset.accent.opacity(0.20), radius: 14, y: 8)
                        }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(preset.accentDeep)
                            .background(.white, in: Circle())
                            .padding(10)
                    }
                }

                HStack(spacing: 8) {
                    Text(preset.name)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Spacer(minLength: 4)
                    Circle().fill(preset.accentDeep).frame(width: 10, height: 10)
                    Circle().fill(preset.sky).frame(width: 10, height: 10)
                    Circle().fill(preset.amber).frame(width: 10, height: 10)
                }
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.86 : 0.66))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(isSelected ? preset.accentDeep.opacity(0.36) : preset.border.opacity(0.62), lineWidth: isSelected ? 1.4 : 1)
                    )
                    .shadow(color: preset.accent.opacity(isSelected ? 0.20 : 0.10), radius: isSelected ? 22 : 14, y: isSelected ? 12 : 8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
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


