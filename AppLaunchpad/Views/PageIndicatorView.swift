import SwiftUI

/// 底部页码圆点指示器
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
                    .onTapGesture { onTap(index) }
            }
        }
        .padding(.bottom, 30)
    }
}
