import Foundation

/// 用户创建的应用分组文件夹
struct FolderInfo: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var appIDs: [String]        // 文件夹内 app 的 bundleID 顺序列表
    var isUserNamed: Bool       // 用户是否手动改过名称

    init(id: UUID = UUID(), name: String = "文件夹", appIDs: [String] = [], isUserNamed: Bool = false) {
        self.id = id
        self.name = name
        self.appIDs = appIDs
        self.isUserNamed = isUserNamed
    }
}
