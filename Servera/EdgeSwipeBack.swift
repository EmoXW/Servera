import SwiftUI

// MARK: - 自定义侧滑返回手势
// 用在隐藏了系统导航栏的全屏 SwiftUI 页面，补回 NavigationStack 原本的侧滑返回体验。

struct EdgeSwipeBackModifier: ViewModifier {
    var enabled = true
    var edgeWidth: CGFloat = 28
    var threshold: CGFloat = 80
    var onBack: () -> Void

    @State private var dragOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: dragOffset)
            .opacity(1 - min(dragOffset / 600, 0.08))
            .contentShape(Rectangle())
            .simultaneousGesture(edgeSwipeGesture)
    }

    private var edgeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard shouldTrack(value) else { return }
                withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
                    dragOffset = min(max(0, value.translation.width), 140)
                }
            }
            .onEnded { value in
                guard shouldTrack(value), value.translation.width >= threshold else {
                    resetOffset()
                    return
                }

                withAnimation(.easeOut(duration: 0.12)) {
                    dragOffset = min(max(0, value.translation.width), 120)
                }
                onBack()
            }
    }

    private func shouldTrack(_ value: DragGesture.Value) -> Bool {
        guard enabled, value.startLocation.x <= edgeWidth, value.translation.width > 0 else {
            return false
        }
        return value.translation.width > abs(value.translation.height) * 1.2
    }

    private func resetOffset() {
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.88)) {
            dragOffset = 0
        }
    }
}

extension View {
    func edgeSwipeBack(
        enabled: Bool = true,
        edgeWidth: CGFloat = 28,
        threshold: CGFloat = 80,
        onBack: @escaping () -> Void
    ) -> some View {
        modifier(
            EdgeSwipeBackModifier(
                enabled: enabled,
                edgeWidth: edgeWidth,
                threshold: threshold,
                onBack: onBack
            )
        )
    }
}
