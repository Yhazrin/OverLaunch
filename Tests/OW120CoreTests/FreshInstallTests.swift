import Foundation
import Testing
@testable import OW120Core

struct FreshInstallTests {
    @Test func bootstrapTimesOutAndCapturesCompletedOutput() async throws {
        let output = try await BootstrapCommand.run("/bin/echo", ["bootstrap-ready"])
        #expect(output.contains("bootstrap-ready"))
        let clock = ContinuousClock()
        let started = clock.now
        do {
            _ = try await BootstrapCommand.run("/bin/sleep", ["30"], timeout: 0.1)
            Issue.record("A stuck bootstrap must fail instead of waiting indefinitely")
        } catch {
            #expect(error.localizedDescription.contains("超时"))
        }
        #expect(started.duration(to: clock.now) < .seconds(5))
    }

    @Test func freshDocumentsStayPrivateAfterPrefixMove() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let staged = root.appendingPathComponent("staged")
        let host = root.appendingPathComponent("host-documents")
        let user = staged.appendingPathComponent("drive_c/users/mac-user")
        let privateDocuments = root.appendingPathComponent("private-documents")
        try Command.write("host-unchanged", to: host.appendingPathComponent("keep.txt"))
        try fm.createDirectory(at: user, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: user.appendingPathComponent("Documents"), withDestinationURL: host)
        try FreshPrefix.isolateDocuments(prefix: staged, documents: privateDocuments)
        let installed = root.appendingPathComponent("installed")
        try fm.moveItem(at: staged, to: installed)
        try fm.createDirectory(at: privateDocuments, withIntermediateDirectories: true)
        let legacy = installed.appendingPathComponent("drive_c/users/crossover/Documents")
        #expect(legacy.resolvingSymlinksInPath() == privateDocuments.resolvingSymlinksInPath())
        try Command.write("private", to: legacy.appendingPathComponent("game.ini"))
        #expect(try String(contentsOf: host.appendingPathComponent("keep.txt"), encoding: .utf8) == "host-unchanged")
        #expect(!fm.fileExists(atPath: host.appendingPathComponent("game.ini").path))
    }

    @Test func installerRejectsHTMLAndTruncatedPE() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("<html>download unavailable</html>".utf8).write(to: file)
        #expect(throws: (any Error).self) { try BattleNetInstaller.validateExecutable(file) }
        var bytes = Data(repeating: 0, count: 68)
        bytes[0] = 0x4d; bytes[1] = 0x5a; bytes[60] = 64
        try bytes.write(to: file)
        #expect(throws: (any Error).self) { try BattleNetInstaller.validateExecutable(file) }
        bytes.replaceSubrange(64..<68, with: [0x50, 0x45, 0, 0])
        try bytes.write(to: file)
        try BattleNetInstaller.validateExecutable(file)
        bytes[60] = 255
        try bytes.write(to: file)
        #expect(throws: (any Error).self) { try BattleNetInstaller.validateExecutable(file) }
    }

    @Test func clientReadinessDoesNotRequireGameAlreadyDownloaded() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = Layout(root: root)
        try Command.write("community-soju26\n", to: root.appendingPathComponent("active-runtime"))
        let service = EnvironmentService(layout: layout)
        #expect(await service.battleNetInstalled() == false)
        try Command.write("client-fixture", to: layout.bottle.appendingPathComponent("drive_c/Program Files (x86)/Battle.net/Battle.net.exe"))
        #expect(await service.battleNetInstalled())
        #expect(!FileManager.default.fileExists(atPath: layout.bottle.appendingPathComponent("drive_c/Program Files (x86)/Overwatch/_retail_/Overwatch.exe").path))
    }
}
