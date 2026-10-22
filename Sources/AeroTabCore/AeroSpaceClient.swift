import Foundation
import Darwin

public enum AeroSpaceError: LocalizedError, Sendable {
    case missingExecutable(String)
    case commandFailed(String)
    case timedOut
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .missingExecutable(let path): return L10n.string("AeroSpace CLI not found: \(path). Choose its path in Settings.")
        case .commandFailed(let message): return L10n.string("AeroSpace request failed: \(message)")
        case .timedOut: return L10n.string("AeroSpace timed out. Make sure it is running.")
        case .invalidResponse(let message): return L10n.string("Could not read AeroSpace data: \(message)")
        }
    }
}

public protocol CommandRunning: Sendable {
    func run(executable: String, arguments: [String]) throws -> Data
}

private final class DataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func set(_ value: Data) { lock.lock(); defer { lock.unlock() }; data = value }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}

public struct ProcessRunner: CommandRunning {
    public var timeout: TimeInterval
    public init(timeout: TimeInterval = 3) { self.timeout = timeout }

    public func run(executable: String, arguments: [String]) throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw AeroSpaceError.missingExecutable(executable)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments // Never run workspace names or user paths through a shell.
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "AEROSPACE_WINDOW_ID")
        environment.removeValue(forKey: "AEROSPACE_WORKSPACE")
        process.environment = environment
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout; process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()

        // Drain BOTH pipes while the child is running: large window lists must not deadlock.
        let group = DispatchGroup()
        let output = DataBuffer(), error = DataBuffer()
        for (pipe, buffer) in [(stdout, output), (stderr, error)] {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                buffer.set(pipe.fileHandleForReading.readDataToEndOfFile())
                group.leave()
            }
        }
        let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 0.3) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }
        group.wait()
        if timedOut { throw AeroSpaceError.timedOut }
        guard process.terminationStatus == 0 else {
            let message = String(decoding: error.get(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw AeroSpaceError.commandFailed(message.isEmpty ? L10n.string("Exit status \(process.terminationStatus)") : message)
        }
        return output.get()
    }
}

public struct AeroSpaceClient: Sendable {
    public let executable: String
    public let runner: any CommandRunning
    public init(executable: String, runner: any CommandRunning = ProcessRunner()) {
        self.executable = executable; self.runner = runner
    }

    private func query<T: Decodable & Sendable>(_ arguments: [String], as type: T.Type) async throws -> T {
        try await Task.detached(priority: .userInitiated) {
            let data = try runner.run(executable: executable, arguments: arguments)
            do { return try JSONDecoder().decode(T.self, from: data) }
            catch { throw AeroSpaceError.invalidResponse(error.localizedDescription) }
        }.value
    }

    public func snapshot() async throws -> Snapshot {
        async let monitors = query(["list-monitors", "--format", "%{monitor-id} %{monitor-name} %{monitor-appkit-nsscreen-screens-id}", "--json"], as: [Monitor].self)
        async let workspaces = query(["list-workspaces", "--all", "--format", "%{workspace} %{monitor-id} %{workspace-is-visible} %{workspace-is-focused} %{workspace-root-container-layout}", "--json"], as: [Workspace].self)
        async let windows = query(["list-windows", "--all", "--format", "%{window-id} %{app-name} %{app-bundle-id} %{app-pid} %{workspace} %{window-title} %{window-layout}", "--json"], as: [WorkspaceWindow].self)
        return try await Snapshot(monitors: monitors, workspaces: workspaces, windows: windows)
    }

    public func workspaceOrder() async -> AeroSpaceWorkspaceOrder {
        await Task.detached(priority: .userInitiated) {
            do {
                // config --get exposes only some keys in AeroSpace 0.21. Read the actual
                // server-selected file so custom --config-path launches work as well.
                let data = try runner.run(executable: executable, arguments: ["config", "--config-path"])
                let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard path.hasPrefix("/") else { throw AeroSpaceError.invalidResponse(L10n.string("Configuration path unavailable")) }
                let source = try String(contentsOfFile: path, encoding: .utf8)
                return AeroSpaceWorkspaceOrder(names: try PersistentWorkspaceReader.read(source), issue: nil)
            } catch {
                return AeroSpaceWorkspaceOrder(names: [], issue: L10n.string("Could not read the AeroSpace workspace order; sorting by name. \(error.localizedDescription)"))
            }
        }.value
    }

    public func focus(_ target: SwitchTarget) async throws {
        _ = try await Task.detached(priority: .userInitiated) {
            try runner.run(executable: executable, arguments: target.arguments)
        }.value
    }
}

public struct AeroSpaceWorkspaceOrder: Sendable {
    public var names: [String]
    public var issue: String?
}
