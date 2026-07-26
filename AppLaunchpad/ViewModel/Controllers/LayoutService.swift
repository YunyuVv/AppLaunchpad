import AppKit
import Observation

/// 布局与几何服务：负责网格密度计算、按密度重分页、扫描合并布局、持久化加载。
/// 只读写 `LaunchpadData`，不碰拖拽 / 文件夹等业务逻辑。
@Observable
@MainActor
final class LayoutService {

    let data: LaunchpadData
    private let store: LayoutStore

    init(data: LaunchpadData, store: LayoutStore = .shared) {
        self.data = data
        self.store = store
    }

    // MARK: - 几何（每页密度）

    /// 仅按屏幕宽度自动决定的列数（不含用户手动覆盖），供 LaunchpadView 在覆盖值为 0 时调用
    func autoColumnCount(for screen: NSScreen) -> Int {
        switch screen.frame.width {                     // 根据屏幕宽度自动，宽屏多列
        case 2560...: return 12
        case 1920 ..< 2560: return 9
        case 1440 ..< 1920: return 7
        case 1280 ..< 1440: return 6
        default: return 5
        }
    }

    /// 仅按屏幕高度自动决定的每页行数（不含用户手动覆盖）
    func autoRowCount(for screen: NSScreen) -> Int {
        let h = screen.frame.height
        switch h {
        case 1200...: return 6
        case 900 ..< 1200: return 5
        default: return 4
        }
    }

    /// 每页列数：用户手动覆盖优先，否则按屏幕宽度自动
    func columnCount(for screen: NSScreen) -> Int {
        let override = UserPreferences.shared.columnCountOverride
        return override >= 3 ? min(override, 12) : autoColumnCount(for: screen)
    }

    /// 每页行数：用户手动覆盖优先，否则按屏幕高度自动
    func rowCount(for screen: NSScreen) -> Int {
        let override = UserPreferences.shared.rowCountOverride
        return override >= 3 ? min(override, 8) : autoRowCount(for: screen)
    }

    var itemsPerPage: Int {
        let screen = NSScreen.screens.first ?? NSScreen.screens[0]
        return columnCount(for: screen) * rowCount(for: screen)
    }

    /// 当用户调整列数/行数导致 itemsPerPage 变化时，按新密度重新分页。
    /// 规则：保持所有图标的相对顺序，将当前所有 page 拍平后按新 pageSize 重切。
    func reflowLayout(to itemsPerPage: Int) {
        guard itemsPerPage > 0 else { return }
        let allItems = data.layout.pages.flatMap { $0 }
        guard !allItems.isEmpty else { return }
        data.layout.pages = allItems.chunked(into: itemsPerPage)
        data.currentPageIndex = min(data.currentPageIndex, max(0, data.layout.pages.count - 1))
        data.saveLayout()
    }

    // MARK: - 应用加载与布局合并

    func loadApps() async {
        let scanned = await AppScanner.shared.scan()
        data.allApps = scanned

        // 后台批量预热所有图标（预缩放 + 缓存），首屏与翻页时 cachedIcon 直接命中，
        // 不在主线程做磁盘 IO——根治「第一次打开启动台 / 第一次翻页很卡」。
        Task.detached(priority: .utility) {
            await IconCache.shared.prewarm(scanned)
        }

        if let saved = await store.load() {
            data.layout = mergeLayout(saved: saved, scanned: scanned)
        } else {
            data.layout = LayoutData.initial(from: scanned, itemsPerPage: itemsPerPage)
        }
    }

    /// FSEvents 触发时调用：重新扫描并合并布局（保留用户排列，追加/移除变化的 App）
    func refreshApps() async {
        // 拖拽进行中：重建 layout.pages 会让 dragState 的 sourceSlotIndex/cursorSlot 失效，
        // 导致落点错乱甚至把刚排好的顺序冲掉。挂起，等拖拽结束后再补执行（见 DragController.endDrag）。
        guard !data.dragState.isDragging else {
            data.pendingAppsRefresh = true
            return
        }
        let scanned = await AppScanner.shared.scan()
        data.allApps = scanned
        data.layout = mergeLayout(saved: data.layout, scanned: scanned)
        // 如果当前页已不存在（如卸载 App 导致页数减少），回到第一页
        if data.currentPageIndex >= data.totalPages {
            data.currentPageIndex = max(0, data.totalPages - 1)
        }

        // 后台批量预热所有图标（预缩放 + 缓存），翻页/重建直接命中，消除首次卡顿。
        Task.detached(priority: .utility) {
            await IconCache.shared.prewarm(scanned)
        }
    }

    /// 合并已存储布局与最新扫描结果：保留顺序，追加新 App，移除已卸载 App
    private func mergeLayout(saved: LayoutData, scanned: [AppInfo]) -> LayoutData {
        let scannedIDs = Set(scanned.map(\.bundleID))

        // 移除已卸载的 app
        var pages = saved.pages.map { page in
            page.filter { item in
                if case .app(let id) = item { return scannedIDs.contains(id) }
                return true
            }
        }.filter { !$0.isEmpty }

        // 找出新增的 app
        let existingIDs = Set(pages.flatMap { $0 }.compactMap {
            if case .app(let id) = $0 { return id }
            return nil
        })
        let newItems = scanned
            .filter { !existingIDs.contains($0.bundleID) }
            .map { LayoutItem.app(bundleID: $0.bundleID) }

        // 将新 app 追加到末页（满页则新建一页）
        if !newItems.isEmpty {
            for item in newItems {
                if pages.isEmpty {
                    pages = [[item]]
                } else if pages[pages.count - 1].count < itemsPerPage {
                    pages[pages.count - 1].append(item)
                } else {
                    pages.append([item])
                }
            }
        }

        // 文件夹功能（2026-07-24）：保留 folders 字典，不再展开 .folder 为 app。
        // 文件夹作为一个不可拆分单元留在布局中；folders 字典同步保留。
        // 仅过滤掉已卸载的文件夹（所有内部 app 都已卸载 → 文件夹无内容 → 移除其占位）。
        let validFolderIDs = Set(saved.folders.filter { _, folder in
            folder.appIDs.contains { scannedIDs.contains($0) }
        }.keys)
        for i in pages.indices {
            pages[i].removeAll { item in
                if case .folder(let id) = item, !validFolderIDs.contains(id) {
                    return true
                }
                return false
            }
        }
        pages = pages.filter { !$0.isEmpty }

        return LayoutData(pages: pages.isEmpty ? [newItems] : pages, folders: saved.folders)
    }

    // MARK: - 原生启动台布局导入 / 恢复

    /// 导入结果：成功携带统计；失败仅描述原因，**绝不**写入 `data.layout`。
    enum NativeImportResult {
        /// - apps: 导入后布局中的 App 总数（含追加项）
        /// - folders: 导入的文件夹数
        /// - skipped: 原生库中有、但本机未安装的 App（已跳过）
        /// - appended: 本机已安装、但原生库未收录、被自动追加到末页的 App（如后续安装 / 包裹型）
        case success(apps: Int, folders: Int, skipped: Int, appended: Int)
        case noDatabase
        case parseError(String)
    }

    /// 导入系统原生启动台布局（保序重流 + 自动备份）。
    ///
    /// 安全保障：任何失败（无数据库 / 解析异常 / 空结果）都只返回错误结果，
    /// **绝不写 `data.layout`、绝不保存**——当前布局与现有功能完全不受影响。
    /// 仅当解析成功后才 `backup()` 再覆盖，并回到第 1 页。
    @discardableResult
    func importNativeLayout() async -> NativeImportResult {
        guard NativeLaunchpadImporter.hasImportableDatabase() else { return .noDatabase }

        let scannedIDs = Set(data.allApps.map(\.bundleID))
        let per = itemsPerPage

        // sqlite 读取放到后台线程，避免阻塞主线程；返回具体 Sendable 错误类型以跨 actor。
        let parseResult: Result<[NativeCell], NativeImportError> = await Task.detached(priority: .userInitiated) {
            do { return .success(try NativeLaunchpadImporter.parseNativeLayout()) }
            catch let err as NativeImportError { return .failure(err) }
            catch { return .failure(.parseFailure(error.localizedDescription)) }
        }.value

        switch parseResult {
        case .failure(let err):
            return .parseError(err.localizedDescription)
        case .success(let cells):
            guard !cells.isEmpty else { return .parseError("系统启动台为空或无已安装 App") }

            // 映射为 LayoutData（此段在主线程，操作 data）
            var pages: [[LayoutItem]] = []
            var folders: [UUID: FolderInfo] = [:]
            var current: [LayoutItem] = []
            var skipped = 0

            for cell in cells {
                switch cell {
                case .app(let bid):
                    if scannedIDs.contains(bid) { current.append(.app(bundleID: bid)) }
                    else { skipped += 1 }
                case .folder(let name, let bids):
                    let installed = bids.filter { scannedIDs.contains($0) }
                    guard !installed.isEmpty else { continue }
                    let id = UUID()
                    folders[id] = FolderInfo(id: id, name: name, appIDs: installed, isUserNamed: true)
                    current.append(.folder(id: id))
                }
                if current.count >= per { pages.append(current); current.removeAll() }
            }
            if !current.isEmpty { pages.append(current) }

            // 统计已纳入布局的 App（含文件夹内部的 App）
            let placedAppIDs = Set(pages.flatMap { $0 }.compactMap { item -> String? in
                if case .app(let id) = item { return id }
                return nil
            })
            let folderAppIDs = Set(folders.values.flatMap { $0.appIDs })
            let coveredIDs = placedAppIDs.union(folderAppIDs)

            // 追加：本机已安装、但原生布局未收录的 App（如后续安装 / 不被启动台收录的包裹型 app）。
            // 这保证「导入绝不会让任何一个已安装 App 从启动台消失」。
            let missing = data.allApps
                .filter { !coveredIDs.contains($0.bundleID) }
                .map { LayoutItem.app(bundleID: $0.bundleID) }

            var appended = 0
            for item in missing {
                appended += 1
                if pages.isEmpty {
                    pages = [[item]]
                } else if pages[pages.count - 1].count < per {
                    pages[pages.count - 1].append(item)
                } else {
                    pages.append([item])
                }
            }

            // 先备份当前布局，再覆盖
            await store.backup()
            data.layout = LayoutData(pages: pages, folders: folders)
            data.currentPageIndex = 0
            data.saveLayout()
            return .success(apps: pages.flatMap { $0 }.count, folders: folders.count, skipped: skipped, appended: appended)
        }
    }

    /// 恢复为默认布局：按当前扫描结果重新生成（保序），先备份再覆盖。
    /// 失败（未扫描到 App）不写 `data.layout`，不影响现有布局。
    @discardableResult
    func restoreDefaultLayout() async -> NativeImportResult {
        guard !data.allApps.isEmpty else { return .parseError("尚未扫描到任何 App") }
        await store.backup()
        let fresh = LayoutData.initial(from: data.allApps, itemsPerPage: itemsPerPage)
        data.layout = fresh
        data.currentPageIndex = 0
        data.saveLayout()
        return .success(apps: fresh.pages.flatMap { $0 }.count, folders: 0, skipped: 0, appended: 0)
    }
}
