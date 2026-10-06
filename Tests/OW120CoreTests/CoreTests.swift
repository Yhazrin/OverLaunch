import Testing
import Foundation
import SQLite3
@testable import OW120Core

struct CoreTests {
    @Test func testDeviceMatchingUsesDesktopWorkloadAndPreservesManualSettings() throws {
        func machine(_ chip: String, _ memory: Int, _ width: Int, _ height: Int, _ hz: Double = 120) -> MachineInfo {
            MachineInfo(chip: chip, memoryGB: memory, macOS: "test", crossoverVersion: "", sourceBottle: nil, displayHz: hz, maximumDisplayHz: hz, lowPowerMode: false, prepared: false, desktopWidth: width, desktopHeight: height)
        }
        let base = machine("Apple M5", 32, 1920, 1200)
        let automatic = LaunchConfiguration.match(.automatic, machine: base, current: GameProfile())
        #expect(automatic.width == 1920 && automatic.height == 1200 && automatic.borderless)
        #expect(automatic.effectiveRenderScale == 80 && automatic.targetFPS == 120)
        let balanced = LaunchConfiguration.match(.balanced, machine: base, current: GameProfile())
        #expect(balanced.effectiveRenderScale == 90)
        var conserving = base; conserving.lowPowerMode = true
        let lowPower = LaunchConfiguration.match(.automatic, machine: conserving, current: GameProfile())
        #expect(lowPower.effectiveRenderScale < automatic.effectiveRenderScale && lowPower.targetFPS == 120)
        let pro = LaunchConfiguration.match(.automatic, machine: machine("Apple M4 Pro", 32, 1920, 1200, 165), current: GameProfile())
        #expect(pro.effectiveRenderScale == 100 && pro.targetFPS == 165)
        let lowMemory = LaunchConfiguration.match(.automatic, machine: machine("Apple M1", 8, 3840, 2160, 60), current: GameProfile())
        #expect(!lowMemory.borderless && !lowMemory.disableRetina && lowMemory.width <= 1600)
        #expect(lowMemory.releaseShaderIR && lowMemory.targetFPS == 120)
        let ultraWide = LaunchConfiguration.match(.automatic, machine: machine("Apple M5", 32, 3440, 1440), current: GameProfile())
        #expect(ultraWide.width == 3440 && ultraWide.height == 1440 && ultraWide.borderless)
        #expect(ultraWide.effectiveRenderScale == 55)
        let large = LaunchConfiguration.match(.automatic, machine: machine("Apple M5", 32, 5120, 2880), current: GameProfile())
        #expect(!large.borderless && large.width == 1600 && large.height == 900)
        var manual = GameProfile().withFixedOutput(width: 2048, height: 1280)
        manual.renderScalePercent = 73; manual.targetFPS = 144; manual.msync = false
        #expect(LaunchConfiguration.match(.manual, machine: base, current: manual) == manual)
        for mode in ConfigurationMode.allCases {
            let profile = LaunchConfiguration.match(mode, machine: base, current: manual)
            try profile.validate()
            if mode != .manual { #expect(profile.selectedConfigurationMode == mode) }
        }
    }
    @Test func testPresetModesPersistWhileOldProfilesRemainManual() throws {
        let old = try JSONDecoder().decode(GameProfile.self, from: JSONEncoder().encode(GameProfile()))
        #expect(old.selectedConfigurationMode == .manual)
        var preset = old; preset.configurationMode = .clarity
        let restored = try JSONDecoder().decode(GameProfile.self, from: JSONEncoder().encode(preset))
        #expect(restored.selectedConfigurationMode == .clarity)
    }
    @Test func testFirstImportAndLegacyMigrationKeepQueuedOutputAndInitializeBrowserOnce() async throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let archive = project.appendingPathComponent("Vendor/dxmt-ow2-pack-v0.2.tar.gz")
        for legacy in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("ow120-import-preferences-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let layout = Layout(root: root)
            let source = root.appendingPathComponent("source")
            let browserRelative = "drive_c/users/crossover/AppData/Roaming/Battle.net/Battle.net.config"
            for relative in ["drive_c/Program Files (x86)/Overwatch/_retail_/Overwatch.exe", "drive_c/Program Files (x86)/Battle.net/Battle.net.exe", "user.reg", "system.reg"] {
                try Command.write("isolated-fixture", to: source.appendingPathComponent(relative))
            }
            try Command.write("[Bottle]\n", to: source.appendingPathComponent("cxbottle.conf"))
            try Command.write(#"{"Client":{"HardwareAcceleration":"true","Region":"CN"},"Other":{"Keep":42}}"#, to: source.appendingPathComponent(browserRelative))
            let original = try Data(contentsOf: source.appendingPathComponent(browserRelative))
            let sourceFingerprint = try CommunityInstaller.sourceFingerprint(source)
            // Signed inert fixtures satisfy runtime validation; no Wine or game runs.
            // System files can live on a different APFS volume on hosted runners.
            // Fixture setup may copy bytes; production game import still uses clonefile.
            func signedFixture(at target: URL) throws {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: target)
            }
            let engine = layout.community.appendingPathComponent("soju26/bin")
            try signedFixture(at: engine.appendingPathComponent("wine"))
            try signedFixture(at: engine.appendingPathComponent("wineserver"))
            if legacy {
                try signedFixture(at: layout.engine.appendingPathComponent("bin/wine"))
                try Command.write("[Bottle]\n", to: layout.bottle.appendingPathComponent("cxbottle.conf"))
                try JSONFile.write(Installation(sourceApp: "", sourceBottle: source.path, crossoverVersion: "", createdAt: Date(), patchSHA256: EnvironmentService.patchHash, sourceFingerprint: sourceFingerprint), to: layout.manifest)
            }
            #expect(layout.isPrepared == legacy)
            let service = EnvironmentService(layout: layout)
            var queued = GameProfile().withFixedOutput(width: 1920, height: 1200)
            queued.renderScalePercent = 75
            queued.metalFramePacing = false
            try await service.saveLaunchProfile(queued)
            try await service.prepareFreeRuntime(archive: archive, sourceBottle: source)
            #expect(layout.isSoju && layout.isPrepared)
            #expect(await service.profile() == queued)
            #expect(await service.launchProfile() == queued)
            let config = layout.bottle.appendingPathComponent(browserRelative)
            let imported = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
            #expect((imported["Client"] as? [String: String])?["HardwareAcceleration"] == "false")
            #expect((imported["Client"] as? [String: String])?["Region"] == "CN")
            #expect((imported["Other"] as? [String: Int])?["Keep"] == 42)
            // Preparing an existing import preserves a later explicit choice.
            try original.write(to: config, options: .atomic)
            try await service.prepareFreeRuntime(archive: archive, sourceBottle: source)
            let existing = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
            #expect((existing["Client"] as? [String: String])?["HardwareAcceleration"] == "true")
            #expect(await service.profile() == queued)
            #expect(try Data(contentsOf: source.appendingPathComponent(browserRelative)) == original)
            #expect(try CommunityInstaller.sourceFingerprint(source) == sourceFingerprint)
        }
    }
    @Test func testAppearancePersistsAllowedHeroWithoutChangingGameFiles() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try HeroIconCatalog(contentsOf: project.appendingPathComponent("Assets/HeroIcons/catalog.json"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ow120-appearance-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppearanceStore(root: root)
        let game = root.appendingPathComponent("Community/Documents-soju26/Overwatch/Settings/Settings_v0.ini")
        try Command.write("unchanged-game-settings", to: game)
        try store.save(LauncherAppearance(iconID: "mei"), catalog: catalog)
        #expect(AppearanceStore(root: root).load(catalog: catalog).iconID == "mei")
        #expect(try String(contentsOf: game, encoding: .utf8) == "unchanged-game-settings")
        #expect(throws: Error.self) { try store.save(LauncherAppearance(iconID: "../outside"), catalog: catalog) }
        #expect(store.load(catalog: catalog).iconID == "mei")
        try store.save(LauncherAppearance(), catalog: catalog)
        #expect(store.load(catalog: catalog).iconID == "default")
        try Command.write("corrupt", to: store.file)
        #expect(store.load(catalog: catalog).iconID == "default")
    }
    @Test func testHeroCatalogRejectsDuplicateAndUnsafeNames() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ow120-catalog-" + UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let valid: [String: Any] = ["id": "mei", "title": "美", "englishName": "Mei", "sha256": String(repeating: "a", count: 64)]
        for items in [[valid, valid], [["id": "../outside", "title": "Bad", "englishName": "Bad", "sha256": String(repeating: "a", count: 64)]]] {
            try JSONSerialization.data(withJSONObject: ["sourceURL": "https://example.com", "sourceRevision": "test", "heroes": items]).write(to: file)
            #expect(throws: Error.self) { try HeroIconCatalog(contentsOf: file) }
        }
    }
    @Test func testHardwareRecommendationAndWideDisplayPreserveFPSAndExactSize() throws {
        let small = GameProfile.recommended(memoryGB: 8, chip: "Apple M1")
        let base = GameProfile.recommended(memoryGB: 32, chip: "Apple M5")
        let pro = GameProfile.recommended(memoryGB: 32, chip: "Apple M4 Pro")
        #expect(small.releaseShaderIR && small.videoMemoryMB == 6144 && small.effectiveRenderScale == 75)
        #expect(!base.releaseShaderIR && base.effectiveRenderScale == 80)
        #expect(!pro.releaseShaderIR && pro.effectiveRenderScale == 100)
        for profile in [small, base, pro] {
            try profile.validate()
            #expect(profile.targetFPS == 120)
        }
        for resolution in OutputResolution.presets {
            let actual = resolution.applying(to: base).fittingDesktop(width: 1512, height: 982)
            try actual.validate()
            #expect(actual.width == resolution.width && actual.height == resolution.height)
            #expect(!actual.borderless && !actual.disableRetina && actual.targetFPS == 120)
        }
        let sameWidth = OutputResolution.presets.filter { $0.width == 1920 }
        #expect(Set(sameWidth.map(\.id)).count == 2)
    }
    @Test func testBattleNetLaunchPreservesBrowserCompatibilityChoiceAndOtherSettings() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ow120-browser-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Command.write("community-soju26", to: root.appendingPathComponent("active-runtime"))
        let layout = Layout(root: root)
        let config = layout.bottle.appendingPathComponent("drive_c/users/crossover/AppData/Roaming/Battle.net/Battle.net.config")
        try Command.write(#"{"Client":{"HardwareAcceleration":"false","Region":"CN"},"Other":{"Keep":42}}"#, to: config)
        let service = EnvironmentService(layout: layout)
        try await service.configureBattleNetBrowser()
        try await service.configureBattleNetBrowser()
        let actual = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        let client = try #require(actual["Client"] as? [String: Any])
        #expect(client["HardwareAcceleration"] as? String == "false")
        #expect(client["Region"] as? String == "CN")
        #expect((actual["Other"] as? [String: Int])?["Keep"] == 42)
        try Command.write(#"{"Client":{"Region":"CN"}}"#, to: config)
        try await service.configureBattleNetBrowser()
        let initial = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        #expect((initial["Client"] as? [String: String])?["HardwareAcceleration"] == "false")
        try Command.write(#"{"Client":{"HardwareAcceleration":"true","Region":"CN"}}"#, to: config)
        try await service.configureBattleNetBrowser()
        let existing = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        #expect((existing["Client"] as? [String: String])?["HardwareAcceleration"] == "true")
        try await service.configureBattleNetBrowser(resetForNewInstallation: true)
        let imported = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        #expect((imported["Client"] as? [String: String])?["HardwareAcceleration"] == "false")
        #expect((imported["Client"] as? [String: String])?["Region"] == "CN")
    }
    @Test func testRenderScaleUsesWorldBoundsWithoutReducingOutputOrFPS() throws {
        var profile = GameProfile().withFixedOutput(width: 1920, height: 1200)
        profile.renderScalePercent = 80
        try profile.validate()
        let original = "[Render.13]\nRenderScale=\"100\"\nUseCustomWorldScale=\"0\"\nMinWorldScale=\"50.000000\"\nMaxWorldScale=\"200.000000\"\nUseCustomFrameRates=\"0\"\nMaxFramesPerSecond=\"60\"\nTextureDetail=\"3\"\n[Input]\nSensitivity=\"2.3\"\n"
        let actual = INI.merge(original, section: "Render.13", values: profile.gameOverrides)
        #expect(actual.contains("RenderScale = \"0\""))
        #expect(!actual.contains("RenderScale=\"100\""))
        #expect(actual.contains("UseCustomWorldScale = \"1\""))
        #expect(actual.contains("MinWorldScale = \"80.000000\""))
        #expect(actual.contains("MaxWorldScale = \"80.000000\""))
        #expect(actual.contains("DynamicRenderScale = \"0\""))
        #expect(actual.contains("UseCustomFrameRates = \"1\""))
        #expect(actual.contains("MaxFramesPerSecond = \"120\""))
        #expect(actual.contains("FullScreenWidth = \"1920\""))
        #expect(actual.contains("FullScreenHeight = \"1200\""))
        #expect(actual.contains("TextureDetail=\"3\""))
        #expect(actual.contains("Sensitivity=\"2.3\""))
        #expect(INI.merge(actual, section: "Render.13", values: profile.gameOverrides) == actual)
    }
    @Test func testOlderProfilesKeepNativeScaleAndInvalidScaleIsRejected() throws {
        let data = try JSONEncoder().encode(GameProfile())
        #expect(!String(decoding: data, as: UTF8.self).contains("renderScalePercent"))
        let old = try JSONDecoder().decode(GameProfile.self, from: data)
        #expect(old.effectiveRenderScale == 100)
        #expect(old.gameOverrides["MaxWorldScale"] == "100.000000")
        for value in [0, 49, 101, 200] {
            var invalid = old; invalid.renderScalePercent = value
            #expect(throws: (any Error).self) { try invalid.validate() }
        }
    }
    @Test func testFixedOutputSurvivesDesktopFittingAndRetinaCanBeRestored() throws {
        let high = GameProfile().withFixedOutput(width: 1920, height: 1200)
        try high.validate()
        #expect(high.fittingDesktop(width: 1512, height: 982) == high)
        #expect(high.gameOverrides["WindowedWidth"] == "1920")
        #expect(high.gameOverrides["WindowedHeight"] == "1200")
        #expect(high.gameOverrides["WindowMode"] == "1")
        #expect(high.targetFPS == 120)
        let old = "[Software\\\\Wine\\\\Mac Driver]\n\"RetinaMode\"=\"n\"\n[Other]\n\"keep\"=\"yes\"\n"
        let enabled = high.displayRegistry(old, community: true)
        #expect(enabled.contains("\"RetinaMode\"=\"y\""))
        #expect(enabled.contains("\"keep\"=\"yes\""))
        let restored = GameProfile().displayRegistry(enabled, community: true)
        #expect(!restored.contains("\"RetinaMode\"=\"y\""))
        #expect(restored.contains("\"RetinaMode\"=\"n\""))
    }
    @Test func testQueuedResolutionDoesNotChangeActiveRuntimeFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ow120-launch-prefs-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Command.write("community-soju26", to: root.appendingPathComponent("active-runtime"))
        let layout = Layout(root: root)
        let active = GameProfile().fittingDesktop(width: 1512, height: 982)
        try JSONFile.write(active, to: layout.profileFile)
        let managed = [layout.settings, layout.dxmtConfig, layout.bottle.appendingPathComponent("user.reg"), layout.bottle.appendingPathComponent("cxbottle.conf")]
        for file in managed { try Command.write("unchanged-live-config", to: file) }
        let before = try Data(contentsOf: layout.profileFile)
        let service = EnvironmentService(layout: layout)
        var selected = active.withFixedOutput(width: 2560, height: 1600)
        selected.renderScalePercent = 80
        try await service.saveLaunchProfile(selected)
        #expect(await service.launchProfile() == selected)
        #expect(try Data(contentsOf: layout.profileFile) == before)
        for file in managed { #expect(try String(contentsOf: file, encoding: .utf8) == "unchanged-live-config") }
        var invalid = selected; invalid.targetFPS = 60
        do { try await service.saveLaunchProfile(invalid); Issue.record("Invalid preferences accepted") } catch {}
        #expect(await service.launchProfile() == selected)
        let renewed = EnvironmentService(layout: layout)
        #expect(await renewed.launchProfile() == selected)
    }
    @Test func testShaderCacheMergePreservesExistingEntriesAndReadsCommittedWAL() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ow120-cache-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.db"), destination = root.appendingPathComponent("target.db"), backup = root.appendingPathComponent("backup.db")
        var writer: OpaquePointer?
        #expect(sqlite3_open(source.path, &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        #expect(sqlite3_exec(writer, "PRAGMA journal_mode=WAL; CREATE TABLE cache_24 (key BLOB PRIMARY KEY,value BLOB NOT NULL); INSERT INTO cache_24 VALUES (zeroblob(40),X'AA'),(CAST(X'01'||zeroblob(39) AS BLOB),X'CC');", nil, nil, nil) == SQLITE_OK)
        try Command.run("/usr/bin/sqlite3", [destination.path, "CREATE TABLE cache_24 (key BLOB PRIMARY KEY,value BLOB NOT NULL); INSERT INTO cache_24 VALUES (zeroblob(40),X'BB');"])
        let before = try Command.sha256(source)
        let wal = URL(fileURLWithPath: source.path + "-wal"), walBefore = try Command.sha256(wal)
        #expect(try ShaderCacheMigration.merge(source: source, destination: destination, backup: backup) == 1)
        #expect(try Command.run("/usr/bin/sqlite3", [destination.path, "SELECT COUNT(*) FROM cache_24;"]).trimmingCharacters(in: .whitespacesAndNewlines) == "2")
        #expect(try Command.run("/usr/bin/sqlite3", [destination.path, "SELECT hex(value) FROM cache_24 WHERE key=zeroblob(40);"]).trimmingCharacters(in: .whitespacesAndNewlines) == "BB")
        #expect(try Command.run("/usr/bin/sqlite3", [backup.path, "SELECT COUNT(*) FROM cache_24;"]).trimmingCharacters(in: .whitespacesAndNewlines) == "1")
        #expect(try Command.sha256(source) == before && Command.sha256(wal) == walBefore)
        #expect(try ShaderCacheMigration.merge(source: source, destination: destination, backup: root.appendingPathComponent("second.db")) == 0)
    }
    @Test func testIncompatibleShaderCacheIsRejectedBeforeChangingDestination() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ow120-bad-cache-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.db"), destination = root.appendingPathComponent("target.db")
        try Command.run("/usr/bin/sqlite3", [source.path, "CREATE TABLE cache_24 (key BLOB PRIMARY KEY,value BLOB NOT NULL); INSERT INTO cache_24 VALUES (X'AA',X'BB');"])
        try Command.write("untouched", to: destination)
        let before = try Command.sha256(destination)
        #expect(throws: (any Error).self) { try ShaderCacheMigration.merge(source: source, destination: destination, backup: root.appendingPathComponent("backup.db")) }
        #expect(try Command.sha256(destination) == before)
        #expect(throws: (any Error).self) { try ShaderCacheMigration.merge(source: source, destination: source, backup: root.appendingPathComponent("backup.db")) }
    }
    @Test func testFramePacingExperimentKeepsGameFPSFloorAndOldProfilesDecode() throws {
        let oldJSON = try JSONEncoder().encode(GameProfile())
        var game = try JSONDecoder().decode(GameProfile.self, from: oldJSON)
        #expect(game.metalFramePacing == nil && game.usesMetalFramePacing)
        #expect(game.dxmtText.contains("preferredMaxFrameRate = 120"))
        game.metalFramePacing = false
        try game.validate()
        #expect(game.dxmtText.contains("preferredMaxFrameRate = 0"))
        #expect(game.gameOverrides["FrameRateCap"] == "120")
        #expect(game.width == 1600 && game.height == 1000 && game.releaseShaderIR == false)
    }
    @Test func testGameRestartRediscoversStaleStreamAndResetsOnlyOldSampleMarks() {
        let now = Date()
        #expect(TelemetryService.requiresDiscovery(gamePID: nil, modified: now, now: now))
        #expect(TelemetryService.requiresDiscovery(gamePID: 2028, modified: now.addingTimeInterval(-31), now: now))
        #expect(!TelemetryService.requiresDiscovery(gamePID: 2028, modified: now, now: now))
        var session = SessionInfo(profile: GameProfile(), folder: URL(fileURLWithPath: "/tmp/ow120-session"))
        session.gamePID = 2028; session.benchmarkStartFrame = 900; session.benchmarkEndFrame = 1200
        session.benchmarkStartedAt = now; session.benchmarkEndedAt = now
        let same = TelemetryService.adoptingGamePID(2028, in: session)
        #expect(same.benchmarkStartFrame == 900 && same.benchmarkEndFrame == 1200)
        let new = TelemetryService.adoptingGamePID(1624, in: session)
        #expect(new.gamePID == 1624)
        #expect(new.benchmarkStartFrame == nil && new.benchmarkEndFrame == nil)
        #expect(new.benchmarkStartedAt == nil && new.benchmarkEndedAt == nil)
        #expect(new.profile == session.profile && new.folder == session.folder)
    }
    @Test func testBorderlessUsesDesktopCoordinatesAndResetsSavedOrigin() throws {
        let fitted = GameProfile().fittingDesktop(width: 1512, height: 982)
        try fitted.validate()
        #expect(fitted.width == 1512 && fitted.height == 982)
        #expect(fitted.targetFPS == 120 && fitted.backend == .dxmt)
        let old = "[Render.13]\nWindowedPosX=\"-5\"\nWindowedPosY=\"-56\"\nWindowedWidth=\"1600\"\nFullScreenHeight=\"1000\"\nMouseSensitivity=\"2.3\"\n"
        let updated = INI.merge(old, section: "Render.13", values: fitted.gameOverrides)
        #expect(updated.contains("WindowedPosX = \"0\""))
        #expect(updated.contains("WindowedPosY = \"0\""))
        #expect(updated.contains("WindowedWidth = \"1512\""))
        #expect(updated.contains("FullScreenHeight = \"982\""))
        #expect(updated.contains("MouseSensitivity=\"2.3\""))
        #expect(GameProfile().fittingDesktop(width: 0, height: 0) == GameProfile())
        var windowed = GameProfile(); windowed.borderless = false
        #expect(windowed.fittingDesktop(width: 1512, height: 982) == windowed)
        var retina = GameProfile(); retina.disableRetina = false
        #expect(retina.fittingDesktop(width: 1512, height: 982) == retina)
    }
    @Test func testSystemGraphicsFailureExpiresAfterRebootAndRequiresActualSuccess() {
        var result = SystemGraphicsResult(checkedAt: Date(), bootSession: "boot-a", nativeSucceeded: true, rosettaSucceeded: false, rosettaMetalSignatureFailure: true, timedOut: false)
        #expect(result.applies(to: "boot-a"))
        #expect(!result.applies(to: "boot-b"))
        #expect(!result.applies(to: ""))
        #expect(result.issue?.title == "系统 Rosetta 图形测试失败")
        result.rosettaSucceeded = true
        #expect(result.issue == nil)
        result.nativeSucceeded = false
        #expect(result.issue?.title == "系统原生图形测试未通过")
    }
    @Test func testFreeMigrationFingerprintDoesNotRequireCrossOverApp() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ow120-free-source-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Command.write("registry", to: root.appendingPathComponent("user.reg"))
        let before = try CommunityInstaller.sourceFingerprint(root)
        #expect(before.keys.sorted() == ["user.reg"])
        try Command.write("changed", to: root.appendingPathComponent("user.reg"))
        #expect(try CommunityInstaller.sourceFingerprint(root) != before)
    }
    @Test func testArchiveValidationRejectsEscapes() throws {
        try CommunityInstaller.validateMembers("bin/wine\nlib/wine/x86_64-unix/ntdll.so\n")
        #expect(throws: (any Error).self) { try CommunityInstaller.validateMembers("../../Applications/file\n") }
        #expect(throws: (any Error).self) { try CommunityInstaller.validateMembers("/Applications/file\n") }
    }
    @Test func testMetalVariablesAreRemovedOnlyFromManagedSection() {
        let input = "[EnvironmentVariables]\n\"MTL_HUD_ENABLED\"=\"0\"\n\"MTL_SHADER_VALIDATION\"=\"0\"\n\"WINEMSYNC\"=\"1\"\n[Other]\n\"MTL_HUD_ENABLED\"=\"keep\"\n"
        let clean = INI.remove(input, section: "EnvironmentVariables", keys: ["MTL_HUD_ENABLED", "MTL_SHADER_VALIDATION"])
        #expect(!clean.contains("\"0\""))
        #expect(clean.contains("\"WINEMSYNC\"=\"1\""))
        #expect(clean.contains("\"MTL_HUD_ENABLED\"=\"keep\""))
    }
    @Test func testStartupErrorsAreNotReportedAsSuccessfulGameplay() {
        #expect(StartupIssue.detect(gameLog: "Selected graphics API is not supported", launcherLog: "")?.title.contains("0xE0010110") == true)
        #expect(StartupIssue.detect(gameLog: "", launcherLog: "rosetta error: Attachment of code signature supplement failed: 1 /libMetalMetricsInterpose.dylib.aot")?.title == "系统图形组件启动失败")
        #expect(StartupIssue.detect(gameLog: "Selected VidDeviceType: Dx11", launcherLog: "") == nil)
    }
    @Test func testAgentGameGraphicsUseStandard64BitPathsAndPreserveBrowser() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ow120-graphics-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Command.write("community-soju26", to: root.appendingPathComponent("active-runtime"))
        let layout = Layout(root: root)
        let pack = layout.community.appendingPathComponent("graphics/dxmt-ow2-pack")
        let engine64 = layout.engine.appendingPathComponent("lib/wine/x86_64-windows")
        let browserDLL = layout.engine.appendingPathComponent("lib/wine/i386-windows/d3d11.dll")
        try Command.write("browser-original", to: browserDLL)
        for name in ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll"] {
            try Command.write("dxmt-" + name, to: pack.appendingPathComponent("x86_64-windows/" + name))
            try Command.write("original-" + name, to: engine64.appendingPathComponent(name))
        }
        let metal = pack.appendingPathComponent("x86_64-unix/winemetal.so")
        try FileManager.default.createDirectory(at: metal.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Signed fixture exercises signature validation without running Wine.
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: metal)
        let service = EnvironmentService(layout: layout)
        try await service.prepareGameGraphicsPath()
        try await service.prepareGameGraphicsPath()
        #expect(try String(contentsOf: browserDLL, encoding: .utf8) == "browser-original")
        #expect(try String(contentsOf: engine64.appendingPathComponent("d3d11.dll"), encoding: .utf8) == "dxmt-d3d11.dll")
        #expect(try String(contentsOf: layout.bottle.appendingPathComponent("drive_c/windows/system32/winemetal.dll"), encoding: .utf8) == "dxmt-winemetal.dll")
        #expect(try String(contentsOf: layout.community.appendingPathComponent("GraphicsBackups/soju26-before-dxmt/engine/d3d11.dll"), encoding: .utf8) == "original-d3d11.dll")
        let env = await service.wineEnvironment()
        #expect(env["WINEDLLPATH_PREPEND"] == nil)
    }
    @Test func testCommunityRoutingKeepsOriginalBottleAndDocumentsSeparate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ow120-routing-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = Layout(root: root)
        let oldBottle = layout.bottle, oldDocuments = layout.documents
        try Command.write("community-cx24\n", to: root.appendingPathComponent("active-runtime"))
        #expect(layout.isCommunity)
        #expect(layout.bottle != oldBottle)
        #expect(layout.documents != oldDocuments)
        #expect(layout.engine.path.hasSuffix("Community/cx24/wswine.bundle"))
        #expect(layout.wineArguments(["cmd.exe", "/c", "echo ok"]) == ["cmd.exe", "/c", "echo ok"])
        try Command.write("community-soju26", to: root.appendingPathComponent("active-runtime"))
        #expect(layout.isSoju && layout.isCommunity)
        #expect(layout.engine.path.hasSuffix("Community/soju26"))
        #expect(layout.bottle.path.hasSuffix("Community/prefix-soju26"))
        #expect(layout.documents.path.hasSuffix("Community/Documents-soju26"))
        try Command.write("crossover", to: root.appendingPathComponent("active-runtime"))
        #expect(layout.bottle == oldBottle)
        #expect(layout.wineArguments(["cmd.exe"]).contains("--cx-app"))
    }
    @Test func testINIUpdatesCorrectSectionAndPreservesOtherValues() {
        let original = "[EnvironmentVariables]\n\"WINEMSYNC\" = \"0\"\n\n[Other]\n\"WINEMSYNC\" = \"untouched\"\n"
        let result = INI.merge(original, section: "EnvironmentVariables", values: ["WINEMSYNC": "1", "DXMT_CONFIG_FILE": "/a path/配置.conf"], quotedKeys: true)
        #expect(result.contains("\"WINEMSYNC\" = \"1\""))
        #expect(result.contains("[Other]\n\"WINEMSYNC\" = \"untouched\""))
        #expect(result.range(of: "DXMT_CONFIG_FILE")!.lowerBound < result.range(of: "[Other]")!.lowerBound)
    }
    @Test func testINIDeduplicatesManagedKeyAndIsIdempotent() {
        let original = "[Render.13]\nFrameRateCap=\"60\"\nFrameRateCap=\"30\"\nMouseSensitivity=\"2.3\"\n"
        let once = INI.merge(original, section: "Render.13", values: ["FrameRateCap": "120"])
        #expect(once.components(separatedBy: "FrameRateCap").count - 1 == 1)
        #expect(once.contains("MouseSensitivity=\"2.3\""))
        #expect(once == INI.merge(once, section: "Render.13", values: ["FrameRateCap": "120"]))
    }
    @Test func test120FloorIsNotSilentlyReduced() throws {
        let p = GameProfile()
        #expect(p.targetFPS == 120)
        #expect(p.dxmtText.contains("preferredMaxFrameRate = 120"))
        #expect(p.gameOverrides["FrameRateCap"] == "120")
        #expect(p.releaseShaderIR == false)
        #expect(p.borderless)
        #expect(p.gameOverrides["WindowMode"] == "2")
        #expect(p.gameOverrides["FullscreenWindow"] == "1")
        #expect(p.dxmtText.contains("releaseShaderIR = False"))
        #expect(p.dxmtText.contains("customVideoMemory = 10240"))
        #expect(GameProfile.competitive(memoryGB: 16).releaseShaderIR)
        #expect(GameProfile.competitive(memoryGB: 32).releaseShaderIR == false)
        var low = p; low.targetFPS = 60
        #expect(throws: (any Error).self) { try low.validate() }
    }
    @Test func testCSVDoesNotFabricateOrDropLongFrames() {
        let csv = "frame,dt_us,commit_us,prep_us,flush_us,block_us,latwait_us,cmdbufs,compiles\n1,8333,1,1,1,1,1,1,0\n2,100000,1,1,1,1,1,1,5\n3,nan,1,1,1,1,1,1,0\n4,8333,1"
        let samples = FrameCSV.parse(csv)
        #expect(samples.count == 2)
        let m = FrameMetrics.calculate(samples)!
        #expect(m.over50MS == 1)
        #expect(abs(m.onePercentLow - 10) < 0.001)
        #expect(abs(m.p99MS - 100) < 0.001)
        #expect(m.compileCorrelatedLongFrames == 1)
    }
    @Test func testOnePercentLowUsesSlowestOnePercentMean() {
        var samples = (0..<198).map { FrameSample(frame: $0, milliseconds: 8, shaderCompiles: 0, blockedMS: 0) }
        samples.append(FrameSample(frame: 198, milliseconds: 20, shaderCompiles: 0, blockedMS: 0))
        samples.append(FrameSample(frame: 199, milliseconds: 40, shaderCompiles: 0, blockedMS: 0))
        let m = FrameMetrics.calculate(samples)!
        #expect(abs(m.onePercentLow - 1000 / 30.0) < 0.001)
        #expect(m.p99MS == 8)
        #expect(FrameMetrics.calculate([]) == nil)
    }
    @Test func testWindowsCRLFAndSplitTailAreReadWithoutLosingCompiles() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ow120-csv-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let header = "frame,dt_us,commit_us,prep_us,flush_us,block_us,latwait_us,cmdbufs,compiles\r\n"
        let row = "0,53930,16,9373,15228,5676,0,64,7\r\n"
        #expect(FrameCSV.parse(header + row).first?.shaderCompiles == 7)
        try Data((header + row + "1,8333,1,2,3,4,5,6,0\r").utf8).write(to: file)
        let tail = FrameTail(file)
        #expect(tail.readNewFrames().count == 1)
        let writer = try FileHandle(forWritingTo: file)
        try writer.seekToEnd(); try writer.write(contentsOf: Data("\n".utf8)); try writer.close()
        #expect(tail.readNewFrames().count == 2)
        #expect(tail.readNewFrames().count == 2)
        #expect(tail.frames.last?.milliseconds == 8.333)
    }
    @Test func testAPFSCloneIsNotHardLinked() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ow120-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source"), target = dir.appendingPathComponent("clone")
        try Command.write("original", to: source.appendingPathComponent("settings.ini"))
        try Command.clone(source, to: target)
        try Command.write("changed", to: target.appendingPathComponent("settings.ini"))
        #expect(try String(contentsOf: source.appendingPathComponent("settings.ini"), encoding: .utf8) == "original")
        #expect(throws: (any Error).self) { try Command.clone(source, to: target) }
    }
    @Test func testDamagedRuntimeIsRejectedBeforeExecution() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ow120-signature-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let layout = Layout(root: dir)
        let contents = layout.runtime.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: contents.appendingPathComponent("MacOS/Fixture"))
        let plist: [String: String] = ["CFBundleExecutable": "Fixture", "CFBundleIdentifier": "local.ow120.signature-fixture", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let resource = contents.appendingPathComponent("Resources/fixture.txt")
        try Command.write("original", to: resource)
        try Command.run("/usr/bin/codesign", ["--force", "--sign", "-", layout.runtime.path])
        let environment = EnvironmentService(layout: layout)
        try await environment.verifyRuntime()
        try Command.write("modified after signing", to: resource)
        await         #expect(throws: (any Error).self) { try await environment.verifyRuntime() }
    }
    @Test func testWineRegistryUpdatesRetinaWithoutTouchingOtherKeys() {
        let original = "[Software\\\\Wine\\\\Mac Driver] 123\n#time=1\n\"AllowSetGamma\"=dword:00000000\n\"RetinaMode\"=\"Y\"\n\n[Other]\n\"RetinaMode\"=\"keep\"\n"
        let result = WineReg.set(original, section: "Software\\\\Wine\\\\Mac Driver", values: ["RetinaMode": "n"])
        #expect(result.contains("\"RetinaMode\"=\"n\""))
        #expect(result.contains("\"AllowSetGamma\"=dword:00000000"))
        #expect(result.contains("[Other]\n\"RetinaMode\"=\"keep\""))
        #expect(!result.contains("\"RetinaMode\"=\"Y\""))
    }
}
