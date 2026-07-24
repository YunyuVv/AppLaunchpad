import SwiftUI

/// 顶部搜索框，半透明磨砂玻璃材质
struct SearchBarView: View {
    @Binding var text: String
    /// 由父视图（LaunchpadView）持有的 @FocusState 注入，便于每次呼出启动台时
    /// 统一强制失焦，避免 panel 复用导致 SwiftUI @FocusState 不释放、搜索框焦点残留
    /// （残留焦点会让键盘 monitor 把左右箭头等按键全吞掉，无法翻页）。
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.7))
                .font(.system(size: 14))

            TextField("搜索", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .focused(focus)
                // 清空按钮
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }
}
