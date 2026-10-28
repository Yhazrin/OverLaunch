import Foundation
import Darwin

/// Wine may leave background processes holding stdout open after wineboot exits.
/// A private file avoids waiting for pipe EOF, and every bootstrap process has a deadline.
enum BootstrapCommand {
    static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil,
                    timeout: TimeInterval = 120) async throws -> String {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("overlaunch-bootstrap-" + UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: directory) }
        let log = directory.appendingPathComponent("output")
        fm.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments; process.environment = environment
        process.standardOutput = handle; process.standardError = handle
        try process.run()
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while process.isRunning {
            try Task.checkCancellation()
            if clock.now >= deadline { throw OWError.message("Windows 环境初始化超时，请退出安装后重试。") }
            try await Task.sleep(for: .milliseconds(100))
        }
        process.waitUntilExit()
        let output = String(decoding: try Data(contentsOf: log), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw OWError.message("Windows 环境初始化失败 (\(process.terminationStatus))：\n\(output.suffix(3000))")
        }
        return output
    }
}
