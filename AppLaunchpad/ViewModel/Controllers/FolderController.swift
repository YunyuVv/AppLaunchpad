import Foundation
import Observation

/// 文件夹控制器：创建 / 修改 / 删除 / 内容操作。
/// 所有变更写入 LaunchpadData.layout → JSON 持久化。
@Observable
@MainActor
final class FolderController {

    let data: LaunchpadData

    init(data: LaunchpadData) {
        self.data = data
    }

    // MARK: - Create

    /// 创建新文件夹，包含指定的 app bundleIDs，放在指定页的指定槽位。
    /// 返回新文件夹的 UUID。
    @discardableResult
    func createFolder(containing bundleIDs: [String],
                      atPage pageIndex: Int,
                      atSlot slot: Int,
                      name: String? = nil) -> UUID {
        let folderID = UUID()
        let firstName = bundleIDs.first.flatMap { id in
            data.allApps.first { $0.bundleID == id }?.displayName
        } ?? "文件夹"
        data.layout.folders[folderID] = FolderInfo(
            id: folderID,
            name: name ?? firstName,
            appIDs: bundleIDs,
            isUserNamed: name != nil
        )
        ensurePageExists(pageIndex)
        var page = data.layout.pages[pageIndex]
        page.insert(.folder(id: folderID), at: min(slot, page.count))
        data.layout.pages[pageIndex] = page
        return folderID
    }

    // MARK: - Add / Remove

    func addApp(_ bundleID: String, toFolder folderID: UUID) {
        data.layout.folders[folderID]?.appIDs.append(bundleID)
    }

    /// 从文件夹中移除一个 app。若文件夹变空则自动删除。
    func removeApp(_ bundleID: String, fromFolder folderID: UUID) {
        guard var folder = data.layout.folders[folderID] else { return }
        folder.appIDs.removeAll { $0 == bundleID }
        if folder.appIDs.isEmpty {
            deleteFolder(folderID)
        } else {
            data.layout.folders[folderID] = folder
        }
    }

    /// 从文件夹移除一个 app，并把该 app 插回主网格中「文件夹所在的位置」（展开一格）。
    /// 用于「拖出文件夹内容面板 → 接管主网格拖拽」的交接：app 必须回到 `pages`，
    /// 主网格的 `beginDrag` 才能按槽位找到它。
    /// - Returns: app 被插回的页码（主网格拖拽应从该页开始）。
    @discardableResult
    func removeAppAndReinsert(_ bundleID: String, fromFolder folderID: UUID) -> Int {
        // 先定位文件夹在主网格中的位置（插回原处；文件夹可能随之保留或随空删除）
        var insertPage = 0
        var insertSlot = data.layout.pages.first?.count ?? 0
        for pageIdx in data.layout.pages.indices {
            if let slot = data.layout.pages[pageIdx].firstIndex(where: {
                if case .folder(let id) = $0, id == folderID { return true }
                return false
            }) {
                insertPage = pageIdx
                insertSlot = slot
                break
            }
        }
        // 再执行移除（可能删除空文件夹）
        removeApp(bundleID, fromFolder: folderID)
        ensurePageExists(insertPage)
        data.layout.pages[insertPage].insert(.app(bundleID: bundleID),
                                             at: min(insertSlot, data.layout.pages[insertPage].count))
        return insertPage
    }

    // MARK: - Delete

    /// 删除文件夹，将其中的 app 展开回到主网格指定页末尾。
    /// - Parameter expandToPage: app 展开到哪一页（默认第 0 页）
    func deleteFolder(_ folderID: UUID, expandToPage pageIndex: Int = 0) {
        guard let folder = data.layout.folders[folderID] else { return }

        // 移除所有页面中的 .folder 占位
        for i in data.layout.pages.indices {
            data.layout.pages[i].removeAll {
                if case .folder(let id) = $0, id == folderID { return true }
                return false
            }
        }

        // 展开文件夹内的 app 到目标页
        let appItems = folder.appIDs.map { LayoutItem.app(bundleID: $0) }
        ensurePageExists(pageIndex)
        data.layout.pages[pageIndex].append(contentsOf: appItems)

        data.layout.folders.removeValue(forKey: folderID)
    }

    // MARK: - Rename

    func renameFolder(_ folderID: UUID, to name: String) {
        data.layout.folders[folderID]?.name = name
        data.layout.folders[folderID]?.isUserNamed = true
    }

    // MARK: - Query

    func folderInfo(for folderID: UUID) -> FolderInfo? {
        data.layout.folders[folderID]
    }

    // MARK: - Helpers

    private func ensurePageExists(_ pageIndex: Int) {
        while data.layout.pages.count <= pageIndex {
            data.layout.pages.append([])
        }
    }
}
