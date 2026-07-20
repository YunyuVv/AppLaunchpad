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
}
