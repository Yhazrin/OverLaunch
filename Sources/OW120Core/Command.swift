import Foundation
import CryptoKit

public enum Command {
    @discardableResult
    public static func run(_ executable: String, _ args: [String] = [], environment: [String: String]? = nil, directory: URL? = nil, allowFailure: Bool = false) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = args
        p.environment = environment; p.currentDirectoryURL = directory
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run()
        let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let output = String(decoding: bytes, as: UTF8.self)
        if p.terminationStatus != 0 && !allowFailure {
            let reason = p.terminationReason == .uncaughtSignal ? "signal" : "exit"
            throw OWError.message("\(URL(fileURLWithPath: executable).lastPathComponent) 失败 (\(reason) \(p.terminationStatus))：\n\(output.suffix(3000))")
        }
        return output
    }
    public static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func clone(_ source: URL, to destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw OWError.message("目标目录已存在：\(destination.path)") }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // -c clones regular files with APFS copy-on-write; never hard-link mutable game files.
        try run("/bin/cp", ["-cR", source.path, destination.path])
    }
    public static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
