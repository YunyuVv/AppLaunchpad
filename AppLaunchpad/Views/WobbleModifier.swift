import SwiftUI

/// 图标编辑模式抖动动画，每个图标随机相位防止整体同步摆动
struct WobbleModifier: ViewModifier {
    let isWobbling: Bool
    @State private var angle: Double = 0
    private let amplitude: Double = 2.2
    private let duration: Double

    init(isWobbling: Bool) {
        self.isWobbling = isWobbling
        self.duration = Double.random(in: 0.10...0.13)
    }

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isWobbling ? angle : 0))
            .onChange(of: isWobbling) { _, wobble in
                if wobble { startWobble() }
                else { withAnimation(.easeOut(duration: 0.1)) { angle = 0 } }
            }
            .onAppear { if isWobbling { startWobble() } }
    }

    private func startWobble() {
        let delay = Double.random(in: 0...0.25)
        // duration 每次随机，防止多次进出编辑模式后所有图标 duration 趋同而同步
        let dur = Double.random(in: 0.10...0.14)
        withAnimation(
            .easeInOut(duration: dur)
            .repeatForever(autoreverses: true)
            .delay(delay)
        ) { angle = amplitude }
    }
}

extension View {
    /// 图标编辑模式抖动
    func wobble(_ isWobbling: Bool) -> some View {
        modifier(WobbleModifier(isWobbling: isWobbling))
    }
}
