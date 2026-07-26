import Foundation

/// 将 LayoutData 以 JSON 格式持久化到本地
actor LayoutStore {
    static let shared = LayoutStore()

    private var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("AppLaunchpad", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("layout.json")
    }

    func save(_ layout: LayoutData) async {
        do {
            let data = try JSONEncoder().encode(layout)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[LayoutStore] 保存失败: \(error)")
        }
    }

    func load() async -> LayoutData? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(LayoutData.self, from: data)
    }

    /// 导入/恢复布局前调用：把当前 layout.json 复制为 layout.backup.json（覆盖旧备份）。
    /// 仅在源文件存在时生效；失败静默忽略（不影响主流程）。
    func backup() async {
        let src = fileURL
        let dst = fileURL.deletingLastPathComponent().appendingPathComponent("layout.backup.json")
        guard FileManager.default.fileExists(atPath: src.path) else { return }
        try? FileManager.default.removeItem(at: dst)
        try? FileManager.default.copyItem(at: src, to: dst)
    }
}
