import Foundation

/// 监听应用安装目录变化，应用安装/卸载后防抖触发回调
/// 使用 DispatchSource（O_EVTONLY）替代 C API FSEvents，代码更简洁
actor FSEventsWatcher {

    private var sources: [DispatchSourceFileSystemObject] = []
    private var debounceTask: Task<Void, Never>? = nil
    private let onChanged: @Sendable () async -> Void

    /// debounce 间隔：目录变化后等待 2s，合并多次连续事件
    private let debounceInterval: UInt64 = 2_000_000_000

    private let watchPaths: [String] = [
        "/Applications",
        "/System/Applications",
        NSHomeDirectory() + "/Applications"
    ]

    init(onChanged: @escaping @Sendable () async -> Void) {
        self.onChanged = onChanged
    }

    /// 开始监听所有应用目录
    func start() {
        for path in watchPaths {
            guard let source = makeSource(for: path) else { continue }
            sources.append(source)
        }
    }

    /// 停止监听并释放所有 source
    func stop() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
        debounceTask?.cancel()
        debounceTask = nil
    }

    // MARK: - Private

    private func makeSource(for path: String) -> DispatchSourceFileSystemObject? {
        // O_EVTONLY：只监听事件，不阻止目录被 unmount
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .link, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { [self] in await self.scheduleRefresh() }
        }

        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    /// 防抖：2s 内多次目录变化合并为一次回调
    private func scheduleRefresh() {
        debounceTask?.cancel()
        debounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: debounceInterval)
                await onChanged()
            } catch {
                // Task 被取消（新事件到来），正常行为
            }
        }
    }
}
