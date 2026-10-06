// Static production guide views, using isolated fixture files. This does not
// perform installation, capture a desktop, or prove GUI interaction/game FPS.
import SwiftUI
import AppKit
import OW120Core

enum Assets {
    static var heroIcons: URL { URL(fileURLWithPath: "Assets/HeroIcons", isDirectory: true) }
    static var graphicsProbe: URL { URL(fileURLWithPath: "dist.noindex/OverLaunch.app/Contents/MacOS/OW120GraphicsProbe") }
    static var archive: URL { URL(fileURLWithPath: "Vendor/dxmt-ow2-pack-v0.2.tar.gz") }
}

@main struct SetupSheet {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        LauncherTheme.registerFonts()
        let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "dist.noindex/DesignPreviews")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("overlaunch-layout-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LauncherModel(layout: OW120Core.Layout(root: root.appendingPathComponent("private")))
        model.machine = await model.environment.inspect()
        model.setupDevice = await model.environment.setupDeviceReport()
        model.hasLoaded = true
        model.setupVisible = true
        model.sourceBottle = root.appendingPathComponent("GameContainer")
        for path in ["drive_c/Program Files (x86)/Battle.net/Battle.net.exe", "drive_c/Program Files (x86)/Overwatch/_retail_/Overwatch.exe"] {
            try Command.write("inert-layout-fixture", to: model.sourceBottle!.appendingPathComponent(path))
        }
        model.assessSource()
        for width in [660.0, 1120.0] {
            for step in SetupStep.allCases {
                model.setupStep = step
                let view = VStack(alignment: .leading, spacing: 20) {
                    Text("OVERLAUNCH / 静态引导样张").font(LauncherTheme.uiFont(14, weight: .bold))
                    SetupGuideView(model: model, compact: width < 860) {
                        VStack(spacing: 5) {
                            GameSelect(title: "配置模式", selection: .constant("automatic"), choices: [GameChoice("automatic", "自动匹配"), GameChoice("manual", "手动")], compact: width < 860)
                            GameSelect(title: "输出分辨率", selection: .constant("desktop"), choices: [GameChoice("desktop", "跟随桌面"), GameChoice("1920x1200", "1920 × 1200")], compact: width < 860)
                            GameSelect(title: "渲染比例", selection: .constant(80), choices: [GameChoice(80, "80%"), GameChoice(100, "100%")], compact: width < 860)
                        }
                    }
                }.padding(24).frame(width: width).foregroundStyle(LauncherTheme.text).background(LauncherTheme.background)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                guard let image = renderer.nsImage, let data = image.tiffRepresentation, let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) else { throw OWError.message("Static guide rendering failed") }
                try png.write(to: directory.appendingPathComponent("setup-\(Int(width))-\(step.rawValue).png"))
            }
        }
        print("Rendered 10 static guide layouts; no installation performed")
    }
}
