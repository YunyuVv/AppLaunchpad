import SwiftUI

/// 底部页码圆点指示器，点击区域扩大为 30×30pt
struct PageIndicatorView: View {
    let totalPages: Int
    let currentPage: Int
    let onTap: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(index == currentPage ? 1.0 : 0.4))
                    .frame(
                        width: index == currentPage ? 8 : 6,
                        height: index == currentPage ? 8 : 6
                    )
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
                    // 扩大点击热区，原圆点只有 6-8pt 难以命中
                    .contentShape(Circle().size(CGSize(width: 28, height: 28)))
                    .onTapGesture { onTap(index) }
            }
        }
        .padding(.bottom, 30)
    }
}
