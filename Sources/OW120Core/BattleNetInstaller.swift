import Foundation

/// Wine creates a user matching the macOS login name, unlike imported CrossOver bottles.
/// Keep every profile's Documents private and expose the legacy path to existing services.
enum FreshPrefix {
    static func isolateDocuments(prefix: URL, documents: URL) throws {
        let fm = FileManager.default
        let users = prefix.appendingPathComponent("drive_c/users")
        let profiles = try fm.contentsOfDirectory(at: users, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return values?.isDirectory == true && values?.isSymbolicLink != true && !["Public", "Default", "Default User", "All Users"].contains(url.lastPathComponent)
            }
        guard !profiles.isEmpty else { throw OWError.message("Windows 用户目录初始化失败。") }
        for profile in profiles {
            let link = profile.appendingPathComponent("Documents")
            if fm.fileExists(atPath: link.path) || (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil { try fm.removeItem(at: link) }
            try fm.createSymbolicLink(at: link, withDestinationURL: documents)
        }
        let legacy = users.appendingPathComponent("crossover")
        if !fm.fileExists(atPath: legacy.path) {
            try fm.createSymbolicLink(atPath: legacy.path, withDestinationPath: profiles.sorted { $0.path < $1.path }[0].lastPathComponent)
        }
    }
}

private final class SecureInstallerDownload: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
}

enum BattleNetInstaller {
    // Official rolling installer: not redistributed and deliberately not treated as a pinned runtime artifact.
    static let downloadURL = URL(string: "https://downloader.battlenet.com.cn/download/getInstaller?os=win&installer=Battle.net-Setup.exe")!

    static func validateExecutable(_ file: URL) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 64) ?? Data()
        guard header.count == 64, header[0] == 0x4d, header[1] == 0x5a else {
            throw OWError.message("下载内容不是 Windows 安装程序，请重试官方下载。")
        }
        let offset = header[60..<64].enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) }
        let size = try handle.seekToEnd()
        guard offset >= 64, offset <= size, size - offset >= 4, size < 200_000_000 else {
            throw OWError.message("战网安装程序不完整。")
        }
        try handle.seek(toOffset: offset)
        guard try handle.read(upToCount: 4) == Data([0x50, 0x45, 0, 0]) else { throw OWError.message("战网安装程序格式无效。") }
    }

    static func download(to destination: URL) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 900
        let session = URLSession(configuration: configuration, delegate: SecureInstallerDownload(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: downloadURL)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, response.url?.scheme == "https" else {
            throw OWError.message("官方战网安装器下载失败，请检查网络后重试。")
        }
        try validateExecutable(temporary)
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Replace only after a complete download; a failed retry leaves existing data intact.
        try Data(contentsOf: temporary).write(to: destination, options: .atomic)
    }
}
