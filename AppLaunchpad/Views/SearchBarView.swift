import SwiftUI

/// 顶部搜索框，液态玻璃材质（与启动台面板背景同款 NSGlassEffectView），
/// 视觉上与默认玻璃背景统一，且 .regular 玻璃比 .ultraThinMaterial 更有实体感、
/// 文字/图标对比度更好（浅色模式也能看清）。
struct SearchBarView: View {
    @Binding var text: String
    /// 由父视图（LaunchpadView）持有的 @FocusState 注入，便于每次呼出启动台时
    /// 统一强制失焦，避免 panel 复用导致 SwiftUI @FocusState 不释放、搜索框焦点残留
    /// （残留焦点会让键盘 monitor 把左右箭头等按键全吞掉，无法翻页）。
    ///
    /// ⚠️ 注意：GlassHostingView 会把内容塞进独立的 NSHostingView，不转发父视图环境，
    /// 跨 hosting 的 FocusState 协调有失效风险。若真机发现 ESC 关台/方向键翻页/输入异常，
    /// 把下方 GlassHostingView 包回 `.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))`
    /// 即可（即方案 B）。
    var focus: FocusState<Bool>.Binding

    var body: some View {
        GlassHostingView(cornerRadius: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))

                TextField("搜索", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .focused(focus)

                // 清空按钮
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 380)
    }
}
