import Foundation

/// One persistent read-only CLI connection, rather than spawning a polling process.
@MainActor
final class FocusSubscription {
    private var process: Process?
    private var pipe: Pipe?
    private var pending = Data()
    private var retry: Task<Void, Never>?
    private var enabled = false
    private var path = ""
    private var generation = 0
    var onFocus: ((String, Int?) -> Void)?

    func start(path: String) {
        stop()
        enabled = true; self.path = path
        connect()
    }

    private func connect() {
        guard enabled else { return }
        let child = Process(), output = Pipe()
        let connection = generation
        child.executableURL = URL(fileURLWithPath: path)
        child.arguments = ["subscribe", "focus-changed", "focused-workspace-changed"]
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        child.standardInput = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in
                guard let self, self.generation == connection else { return }
                self.receive(data)
            }
        }
        child.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == connection else { return }
                self.scheduleReconnect()
            }
        }
        do {
            try child.run()
            process = child; pipe = output
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            scheduleReconnect()
        }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        pending.append(data)
        while let newline = pending.firstIndex(of: 0x0a) {
            let line = pending[..<newline]
            pending.removeSubrange(...newline)
            if let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
               let workspace = json["workspace"] as? String {
                onFocus?(workspace, json["windowId"] as? Int)
            }
        }
        if pending.count > 1_048_576 { pending.removeAll() }
    }

    private func scheduleReconnect() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        process = nil; pipe = nil; pending.removeAll()
        guard enabled else { return }
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.connect()
        }
    }

    func stop() {
        generation += 1
        enabled = false
        retry?.cancel(); retry = nil
        pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if let process, process.isRunning { process.terminate() }
        process = nil; pipe = nil; pending.removeAll()
    }
}
