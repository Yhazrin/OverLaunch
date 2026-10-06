// Offline design artifact using the production controls; not a desktop capture
// or evidence of a live app's interaction, accessibility or responsive behavior.
import SwiftUI
import AppKit

private typealias PreviewState<Value> = SwiftUI.State<Value>

struct ControlSheet: View {
    let compact: Bool
    @PreviewState var mode = "automatic"
    @PreviewState var resolution = "1920x1200"
    @PreviewState var enabled = true
    @PreviewState var scale = 80
    @PreviewState var host = GameSelectHost()
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                GameDisplayText(text: "OVERLAUNCH", size: 28).foregroundStyle(.white)
                Spacer()
                Text("控件样张").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
            }.padding(22).background(LauncherTheme.sidebar)
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    GameDisplayText(text: "LAUNCH SETTINGS", size: compact ? 40 : 50)
                    Text("启动设置").font(LauncherTheme.chineseHeading(32))
                }.foregroundStyle(LauncherTheme.text)
                VStack(spacing: 5) {
                    GameSelect(title: "配置模式", selection: $mode, choices: [GameChoice("automatic", "自动匹配"), GameChoice("manual", "手动")], compact: compact)
                    GameSelect(title: "输出分辨率", selection: $resolution, choices: [GameChoice("desktop", "跟随桌面 · 无边框"), GameChoice("1920x1200", "1920 × 1200")], compact: compact)
                    GameRange(title: "渲染比例", value: $scale)
                    GameToggle(title: "MSync 同步", value: $enabled, compact: compact)
                    GameToggle(title: "性能叠层", value: .constant(false), compact: compact).disabled(true)
                }
                HStack(spacing: 12) {
                    Button("保存设置") {}.buttonStyle(OverButtonStyle(kind: .primary))
                    Button("撤销修改") {}.buttonStyle(OverButtonStyle(kind: .secondary))
                    Spacer()
                }
            }.padding(compact ? 22 : 36)
            SoftwareInfoView(info: SoftwareInfo(name: "OverLaunch", version: "0.4.2 (9)", repository: nil))
                .foregroundStyle(LauncherTheme.text).padding(.horizontal, compact ? 22 : 36).padding(.bottom, 22)
        }
        .frame(width: compact ? 660 : 1080).background(LauncherTheme.background)
        .coordinateSpace(name: "gameSelectCanvas")
        .environment(\.gameSelectHost, host)
        .overlay { GameSelectPortalLayer(host: host) }
        .onAppear { host.canvasSize = CGSize(width: compact ? 660 : 1080, height: 720) }
    }
}

struct OpenDropdownSheet: View {
    let compact: Bool
    private var width: CGFloat { compact ? 660 : 1080 }
    private var valueWidth: CGFloat { compact ? 208 : 284 }
    private var choices: [GameChoice<String>] {
        [GameChoice("automatic", "自动匹配"), GameChoice("performance", "流畅优先"), GameChoice("balanced", "均衡"), GameChoice("clarity", "清晰优先"), GameChoice("manual", "手动")]
    }
    var body: some View {
        let anchor = CGRect(x: width - 22 - 16 - valueWidth, y: 146, width: valueWidth, height: 44)
        let placement = DropdownGeometry(anchor: anchor, canvas: CGSize(width: width, height: 500), topInset: 106, idealHeight: 220)
        ZStack(alignment: .topLeading) {
            LauncherTheme.background
            HStack {
                GameDisplayText(text: "OVERLAUNCH", size: 28).foregroundStyle(.white)
                Spacer()
                Text("下拉控件静态预览").font(LauncherTheme.uiFont(12)).foregroundStyle(.white)
            }.padding(22).frame(width: width, height: 72).background(LauncherTheme.sidebar)
            Text("启动设置").font(LauncherTheme.chineseHeading(32)).foregroundStyle(LauncherTheme.text).offset(x: 22, y: 92)
            VStack(spacing: 5) {
                GameSelect(title: "配置模式", selection: .constant("automatic"), choices: choices, compact: compact)
                GameSelect(title: "输出分辨率", selection: .constant("desktop"), choices: [GameChoice("desktop", "跟随桌面 · 无边框")], compact: compact)
                GameToggle(title: "MSync 同步", value: .constant(true), compact: compact)
            }.frame(width: width - 44).offset(x: 22, y: 146)
            GameSelectMenu(title: "配置模式", selection: .constant("automatic"), choices: choices,
                           width: placement.frame.width, listHeight: placement.frame.height, onDismiss: {})
                .offset(x: placement.frame.minX, y: placement.frame.minY)
        }.frame(width: width, height: 500)
    }
}

@main struct RenderControlSheet {
    @MainActor static func main() throws {
        LauncherTheme.registerFonts()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, content) in [
            ("controls-1080.png", AnyView(ControlSheet(compact: false))),
            ("controls-660.png", AnyView(ControlSheet(compact: true))),
            ("dropdown-1080.png", AnyView(OpenDropdownSheet(compact: false))),
            ("dropdown-660.png", AnyView(OpenDropdownSheet(compact: true)))
        ] {
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "OverLaunchControlSheet", code: 1)
            }
            try png.write(to: output.appendingPathComponent(name))
        }
    }
}
