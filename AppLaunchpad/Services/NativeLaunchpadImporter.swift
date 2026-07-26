import Foundation
import SQLite3

/// 原生启动台布局导入：只读解析系统 Launchpad 数据库（macOS 自带 SQLite3，零体积增长）。
///
/// 设计要点：
/// - 用系统 `import SQLite3`（动态链 `/usr/lib/libsqlite3.dylib`），不打包任何第三方库。
/// - 数据库路径在用户私有目录，**运行时只读打开**，不复制、不写入系统数据。
/// - 任何解析异常都向上抛出，由调用方（LayoutService）兜底——绝不静默返回错误结果。

enum NativeImportError: LocalizedError, Sendable {
    case databaseNotFound
    case databaseUnreadable
    case unsupportedSchema
    case parseFailure(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound:  return "未找到系统启动台数据库"
        case .databaseUnreadable: return "无法读取系统启动台数据库"
        case .unsupportedSchema: return "系统启动台数据库格式不受支持"
        case .parseFailure(let m): return "解析失败：\(m)"
        }
    }
}

/// 单个网格单元：单个 App，或文件夹（内含已排序的 bundleID 列表）。
enum NativeCell: Sendable {
    case app(bundleID: String)
    case folder(name: String, appIDs: [String])
}

struct NativeLaunchpadImporter {

    // MARK: - 路径与探测

    /// 原生启动台数据库路径；`getconf` 失败返回 nil。
    static func databasePath() -> String? {
        guard let dir = runGetConf("DARWIN_USER_DIR"), !dir.isEmpty else { return nil }
        return "/private\(dir)com.apple.dock.launchpad/db/db"
    }

    /// 数据库存在且含 legacy 三表（apps/groups/items）→ 可导入。
    /// 仅在按钮可用性判断等轻量场景调用；解析时仍会二次校验。
    static func hasImportableDatabase() -> Bool {
        guard let path = databasePath(), FileManager.default.fileExists(atPath: path) else { return false }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return false }
        defer { sqlite3_close(db) }
        return tableExists(in: db, name: "apps")
            && tableExists(in: db, name: "groups")
            && tableExists(in: db, name: "items")
    }

    // MARK: - 解析（只读，任何异常向上抛）

    /// 只读解析原生布局，返回跨所有页、保序的扁平 cell 序列。
    /// - 顶层容器：`items.type=3 && parent_id=1`
    /// - 容器内子项：`type=4`(直接 app) 与 `type=2`(文件夹)，按原生 ordering 保相对顺序
    /// - 文件夹名：来自 `groups.title`；若是占位符（未命名/文件夹等）则取文件夹内前 3 个 app 名生成
    static func parseNativeLayout() throws -> [NativeCell] {
        guard let path = databasePath() else { throw NativeImportError.databaseNotFound }
        guard FileManager.default.fileExists(atPath: path) else { throw NativeImportError.databaseNotFound }

        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw NativeImportError.databaseUnreadable
        }
        defer { sqlite3_close(db) }

        guard tableExists(in: db, name: "apps"),
              tableExists(in: db, name: "groups"),
              tableExists(in: db, name: "items") else {
            throw NativeImportError.unsupportedSchema
        }

        let apps = try parseApps(db)
        let groups = try parseGroups(db)
        let items = try parseItems(db)

        // 构建父子索引（按 parent_id 分组，组内按 ordering 升序）
        var childrenByParent: [Int: [ItemRow]] = [:]
        for it in items { childrenByParent[it.parentId, default: []].append(it) }
        for (k, v) in childrenByParent { childrenByParent[k] = v.sorted { $0.ordering < $1.ordering } }

        // 顶层容器：type=3 且 parent_id=1
        let topContainers = items
            .filter { $0.type == 3 && $0.parentId == 1 }
            .sorted { $0.ordering < $1.ordering }

        var cells: [NativeCell] = []
        for container in topContainers {
            let containerId = container.rowId
            for child in childrenByParent[containerId] ?? [] {
                if child.type == 4 {
                    // apps 表以 item_id 索引，而 item_id == items.rowid
                    if let app = apps[String(child.rowId)], !app.bundleId.isEmpty {
                        cells.append(.app(bundleID: app.bundleId))
                    }
                } else if child.type == 2 {
                    let nameRaw = (groups[String(child.rowId)] ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let appIDs = folderAppIDs(folderId: child.rowId,
                                              childrenByParent: childrenByParent, apps: apps)
                    let name: String
                    if isPlaceholderFolderTitle(nameRaw) {
                        name = folderFallbackName(folderId: child.rowId,
                                                  childrenByParent: childrenByParent, apps: apps)
                    } else if nameRaw.isEmpty {
                        name = "未命名文件夹"
                    } else {
                        name = nameRaw
                    }
                    cells.append(.folder(name: name, appIDs: appIDs))
                }
            }
        }
        return cells
    }

    // MARK: - 内部类型与解析

    private struct ItemRow { let rowId: Int; let type: Int; let parentId: Int; let ordering: Int }
    private struct AppRow { let title: String; let bundleId: String }

    private static func runGetConf(_ name: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/getconf")
        task.arguments = [name]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tableExists(in db: OpaquePointer?, name: String) -> Bool {
        let query = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        name.withCString { cstr in
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            _ = sqlite3_bind_text(stmt, 1, cstr, -1, SQLITE_TRANSIENT)
        }
        if sqlite3_step(stmt) == SQLITE_ROW { return sqlite3_column_int(stmt, 0) > 0 }
        return false
    }

    private static func parseApps(_ db: OpaquePointer?) throws -> [String: AppRow] {
        var result: [String: AppRow] = [:]
        let query = "SELECT item_id, title, bundleid FROM apps"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw NativeImportError.parseFailure("apps")
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let itemId = String(sqlite3_column_int(stmt, 0))
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let bundleId = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            result[itemId] = AppRow(title: title, bundleId: bundleId)
        }
        return result
    }

    private static func parseGroups(_ db: OpaquePointer?) throws -> [String: String] {
        var result: [String: String] = [:]
        let query = "SELECT item_id, title FROM groups"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw NativeImportError.parseFailure("groups")
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let itemId = String(sqlite3_column_int(stmt, 0))
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            result[itemId] = title
        }
        return result
    }

    private static func parseItems(_ db: OpaquePointer?) throws -> [ItemRow] {
        var result: [ItemRow] = []
        let query = "SELECT rowid, type, parent_id, ordering FROM items"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw NativeImportError.parseFailure("items")
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(ItemRow(
                rowId: Int(sqlite3_column_int(stmt, 0)),
                type: Int(sqlite3_column_int(stmt, 1)),
                parentId: Int(sqlite3_column_int(stmt, 2)),
                ordering: Int(sqlite3_column_int(stmt, 3))
            ))
        }
        return result
    }

    /// 收集 folderId 下所有 type=4 后代（兼容 type=3 槽位嵌套与直接平铺），保序。
    private static func folderAppIDs(folderId: Int,
                                     childrenByParent: [Int: [ItemRow]],
                                     apps: [String: AppRow]) -> [String] {
        var ids: [String] = []
        func collect(_ parentId: Int) {
            for child in childrenByParent[parentId] ?? [] {
                if child.type == 4 {
                    if let b = apps[String(child.rowId)]?.bundleId, !b.isEmpty { ids.append(b) }
                } else if child.type == 3 {
                    collect(child.rowId)   // 槽位容器，递归进入
                }
            }
        }
        collect(folderId)
        return ids
    }

    /// 占位符文件夹名兜底：取文件夹内前 3 个 app 的标题拼成。
    private static func folderFallbackName(folderId: Int,
                                           childrenByParent: [Int: [ItemRow]],
                                           apps: [String: AppRow]) -> String {
        let titles = folderAppIDs(folderId: folderId, childrenByParent: childrenByParent, apps: apps)
            .compactMap { bid in apps.first(where: { $0.value.bundleId == bid })?.value.title }
            .filter { !$0.isEmpty }
        let top = Array(titles.prefix(3))
        if top.isEmpty { return "未命名文件夹" }
        if top.count == 1 { return top[0] }
        if top.count == 2 { return top[0] + " + " + top[1] }
        return top[0] + " + " + top[1] + " + …"
    }

    private static func isPlaceholderFolderTitle(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return true }
        let placeholders = ["untitled", "folder", "new folder", "未命名", "文件夹", "未命名文件夹"]
        return placeholders.contains(t)
    }
}
