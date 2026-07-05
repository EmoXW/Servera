import SwiftUI

// MARK: - Servera 设计系统
// 统一保存颜色和小型 UI 基础组件，开源后调整视觉风格时不用在各个功能页里翻找。

extension Color {
    // Servera 的色板集中维护。功能页应组合这些颜色，而不是零散硬编码新的粉/绿值。
    static let serveraBackground = Color(red: 0.980, green: 0.973, blue: 0.980)
    static let serveraSurface = Color.white
    static let serveraTintSoft = Color(red: 0.988, green: 0.925, blue: 0.949)
    static let serveraTint = Color(red: 0.965, green: 0.788, blue: 0.847)
    static let serveraAccent = Color(red: 0.937, green: 0.627, blue: 0.722)
    static let serveraAccentDeep = Color(red: 0.851, green: 0.427, blue: 0.573)
    static let serveraBorder = Color(red: 0.945, green: 0.867, blue: 0.898)
    static let serveraTextSecondary = Color(red: 0.549, green: 0.506, blue: 0.533)
    static let serveraLeaf = Color(red: 0.561, green: 0.725, blue: 0.588)
    static let serveraLeafSoft = Color(red: 0.918, green: 0.965, blue: 0.929)
    static let serveraSky = Color(red: 0.620, green: 0.796, blue: 0.937)
    static let serveraAmber = Color(red: 0.937, green: 0.725, blue: 0.369)
}

struct ServeraThemePreset: Identifiable {
    let id: String
    let name: String
    let icon: String
    let background: Color
    let tintSoft: Color
    let tint: Color
    let accent: Color
    let accentDeep: Color
    let border: Color
    let leafSoft: Color
    let sky: Color
    let amber: Color

    static let presets: [ServeraThemePreset] = [
        .init(
            id: "default-pink",
            name: "默认粉白",
            icon: "circle.lefthalf.filled",
            background: .serveraBackground,
            tintSoft: .serveraTintSoft,
            tint: .serveraTint,
            accent: .serveraAccent,
            accentDeep: .serveraAccentDeep,
            border: .serveraBorder,
            leafSoft: .serveraLeafSoft,
            sky: .serveraSky,
            amber: .serveraAmber
        ),
        .init(
            id: "mint-cloud",
            name: "薄荷云",
            icon: "leaf.fill",
            background: Color(red: 0.964, green: 0.988, blue: 0.976),
            tintSoft: Color(red: 0.893, green: 0.973, blue: 0.929),
            tint: Color(red: 0.643, green: 0.859, blue: 0.741),
            accent: Color(red: 0.408, green: 0.729, blue: 0.604),
            accentDeep: Color(red: 0.243, green: 0.580, blue: 0.478),
            border: Color(red: 0.808, green: 0.918, blue: 0.866),
            leafSoft: Color(red: 0.902, green: 0.969, blue: 0.918),
            sky: Color(red: 0.584, green: 0.804, blue: 0.910),
            amber: Color(red: 0.918, green: 0.733, blue: 0.431)
        ),
        .init(
            id: "sea-salt-blue",
            name: "海盐蓝",
            icon: "water.waves",
            background: Color(red: 0.957, green: 0.978, blue: 0.992),
            tintSoft: Color(red: 0.878, green: 0.948, blue: 0.988),
            tint: Color(red: 0.616, green: 0.816, blue: 0.949),
            accent: Color(red: 0.420, green: 0.690, blue: 0.894),
            accentDeep: Color(red: 0.247, green: 0.529, blue: 0.769),
            border: Color(red: 0.788, green: 0.884, blue: 0.949),
            leafSoft: Color(red: 0.902, green: 0.965, blue: 0.949),
            sky: Color(red: 0.471, green: 0.792, blue: 0.914),
            amber: Color(red: 0.914, green: 0.741, blue: 0.455)
        ),
        .init(
            id: "peach-orange",
            name: "蜜桃橙",
            icon: "sun.max.fill",
            background: Color(red: 0.996, green: 0.968, blue: 0.946),
            tintSoft: Color(red: 0.996, green: 0.909, blue: 0.878),
            tint: Color(red: 0.973, green: 0.690, blue: 0.584),
            accent: Color(red: 0.929, green: 0.561, blue: 0.463),
            accentDeep: Color(red: 0.812, green: 0.392, blue: 0.329),
            border: Color(red: 0.949, green: 0.835, blue: 0.792),
            leafSoft: Color(red: 0.944, green: 0.965, blue: 0.886),
            sky: Color(red: 0.655, green: 0.812, blue: 0.914),
            amber: Color(red: 0.941, green: 0.694, blue: 0.341)
        ),
        .init(
            id: "wisteria-mist",
            name: "紫藤雾",
            icon: "sparkles",
            background: Color(red: 0.977, green: 0.965, blue: 0.996),
            tintSoft: Color(red: 0.931, green: 0.906, blue: 0.992),
            tint: Color(red: 0.737, green: 0.647, blue: 0.929),
            accent: Color(red: 0.612, green: 0.502, blue: 0.843),
            accentDeep: Color(red: 0.447, green: 0.329, blue: 0.698),
            border: Color(red: 0.855, green: 0.816, blue: 0.943),
            leafSoft: Color(red: 0.918, green: 0.957, blue: 0.949),
            sky: Color(red: 0.631, green: 0.780, blue: 0.945),
            amber: Color(red: 0.914, green: 0.718, blue: 0.447)
        ),
        .init(
            id: "morning-gold",
            name: "晨光金",
            icon: "sunrise.fill",
            background: Color(red: 0.996, green: 0.982, blue: 0.940),
            tintSoft: Color(red: 0.988, green: 0.937, blue: 0.808),
            tint: Color(red: 0.933, green: 0.757, blue: 0.427),
            accent: Color(red: 0.831, green: 0.631, blue: 0.275),
            accentDeep: Color(red: 0.690, green: 0.486, blue: 0.184),
            border: Color(red: 0.918, green: 0.839, blue: 0.659),
            leafSoft: Color(red: 0.914, green: 0.957, blue: 0.890),
            sky: Color(red: 0.631, green: 0.800, blue: 0.902),
            amber: Color(red: 0.933, green: 0.690, blue: 0.294)
        )
    ]

    static let fallback = presets[0]

    static func preset(for id: String) -> ServeraThemePreset {
        presets.first { $0.id == id } ?? fallback
    }
}

private struct ServeraThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = ServeraThemePreset.fallback
}

extension EnvironmentValues {
    var serveraTheme: ServeraThemePreset {
        get { self[ServeraThemeEnvironmentKey.self] }
        set { self[ServeraThemeEnvironmentKey.self] = newValue }
    }
}

enum ServeraAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: "iphone"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func mode(for rawValue: String) -> ServeraAppearanceMode {
        ServeraAppearanceMode(rawValue: rawValue) ?? .system
    }
}

struct ServeraCard<Content: View>: View {
    @Environment(\.serveraTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 28
    @ViewBuilder var content: Content

    var body: some View {
        // Server、NAS、Docker、设置页通用的玻璃卡片样式。
        content
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(colorScheme == .dark ? 0.10 : 0.78))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke((colorScheme == .dark ? Color.white : theme.border).opacity(colorScheme == .dark ? 0.14 : 0.72), lineWidth: 1)
                    )
                    .shadow(color: theme.accent.opacity(colorScheme == .dark ? 0.08 : 0.14), radius: 24, y: 14)
            }
    }
}

struct StatusPill: View {
    let text: String
    var color: Color = .serveraLeaf

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(color.opacity(0.13), in: Capsule())
    }
}
