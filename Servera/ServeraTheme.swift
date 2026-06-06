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

struct ServeraCard<Content: View>: View {
    var cornerRadius: CGFloat = 28
    @ViewBuilder var content: Content

    var body: some View {
        // Server、NAS、Docker、设置页通用的玻璃卡片样式。
        content
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(0.78))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.serveraBorder.opacity(0.72), lineWidth: 1)
                    )
                    .shadow(color: Color.serveraAccent.opacity(0.14), radius: 24, y: 14)
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
