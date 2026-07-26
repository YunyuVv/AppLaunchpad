import Foundation

/// 在 AppDelegate（创建启动台与 ViewModel）与 SwiftUI 设置窗之间传递运行时单例。
///
/// 设置窗在用户点击 ⌘, 后才构建，彼时 AppDelegate 早已完成启动并写入本引用；
/// 因此让设置页在「按钮点击时」读取 `AppContext.viewModel`，避开场景构建时序问题，
/// 不必把 ViewModel 通过 Window 场景参数层层下传。
enum AppContext {
    /// AppDelegate 启动后写入；设置页导入/恢复布局时读取。
    /// 仅 MainActor 访问（设置页按钮/AppDelegate 均在主线程），故标记为 @MainActor 以满足 Swift 6 并发安全。
    @MainActor static var viewModel: LaunchpadViewModel?
}
