// Static production components with labeled fixture data. Not a desktop
// capture or a performance/interaction measurement of the user's environment.
import SwiftUI
import AppKit
private typealias PreviewState<Value> = SwiftUI.State<Value>

struct HomeSheet: View {
    let width: CGFloat
    let state: String
    private var compact: Bool { width < 860 }
    private var running: Bool { state == "running" }
    private var imported: Bool { state != "import" }
    @PreviewState private var mode = "manual"
    @PreviewState private var output = "1920x1200"
    @PreviewState private var render = 80
    private var heroID: String { running ? "genji" : "tracer" }
    private func portrait(_ id: String) -> NSImage? {
        NSImage(contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/HeroIcons/2d/\(id).png"))
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    OWEmblem().frame(width: 26, height: 26)
                    GameDisplayText(text: "OVERLAUNCH", size: 28, spacing: 0.6)
                    Spacer()
                    Text("静态布局样张").font(LauncherTheme.uiFont(12)).foregroundStyle(Color.white.opacity(0.7))
                }.foregroundStyle(Color.white).padding(.horizontal, 24).frame(height: 56)
                HStack(spacing: -9) {
                    ForEach(["开始", "启动设置", "性能", "外观", "工具箱"], id: \.self) { title in
                        Button {} label: { GameNavigationTabLabel(title: title, selected: title == "开始") }
                            .buttonStyle(OverNavigationStyle()).accessibilityLabel(title)
                    }
                }.padding(.horizontal, compact ? 12 : 26)
            }.background(LauncherTheme.sidebar).clipped()
            VStack(alignment: .leading, spacing: 28) {
                VStack(spacing: 0) {
                    LaunchStage(compact: compact, portrait: portrait(heroID),
                                heroTitle: running ? "源氏" : "猎空", heroEnglishName: heroID,
                                status: running ? "战网运行中" : imported ? "已就绪" : "待导入",
                                statusColor: running ? LauncherTheme.cyan : .white.opacity(0.7),
                                machine: "APPLE SILICON  /  16 GB",
                                message: running ? "请在战网内点击“进入游戏”。" : imported ? "独立环境已就绪" : "导入已有游戏后即可启动") {
                        VStack(alignment: .leading, spacing: 10) {
                            Button {} label: {
                                HStack(spacing: 16) {
                                    Text(running ? "战网运行中" : imported ? "启动国服战网" : "导入游戏")
                                    Spacer(minLength: 8)
                                    Image(systemName: imported ? "chevron.forward.2" : "square.and.arrow.down").font(.system(size: 16, weight: .bold))
                                }.frame(maxWidth: .infinity)
                            }.buttonStyle(LaunchPrimaryButtonStyle()).frame(maxWidth: 340, alignment: .leading).disabled(running)
                            if running { Button("停止游戏与战网") {}.buttonStyle(LaunchSecondaryButtonStyle()) }
                            if !imported { Button("选择已有游戏目录…") {}.buttonStyle(LaunchSecondaryButtonStyle()) }
                        }
                    }
                    if imported { LaunchProfileStrip(mode: "手动", output: "1920 × 1200", render: "80%", target: "120 FPS") }
                    else { Text("首次下载运行组件约 367 MB").font(LauncherTheme.uiFont(12)).foregroundStyle(LauncherTheme.muted).padding(16).frame(maxWidth: .infinity, alignment: .leading) }
                }
                if imported {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("启动设置").font(LauncherTheme.chineseHeading(22))
                            Spacer()
                            Button("全部设置") {}.buttonStyle(OverButtonStyle(kind: .quiet))
                            Button("已保存") {}.disabled(true)
                        }
                        VStack(spacing: 5) {
                            GameSelect(title: "配置模式", selection: $mode, choices: [GameChoice("manual", "手动")], compact: compact)
                            GameSelect(title: "输出分辨率", selection: $output, choices: [GameChoice("1920x1200", "1920 × 1200")], compact: compact)
                            GameSelect(title: "渲染比例", selection: $render, choices: [GameChoice(80, "80%")], compact: compact)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("应用外观").font(LauncherTheme.chineseHeading(22))
                        Spacer()
                        Button {} label: { Image(systemName: "chevron.left") }
                            .buttonStyle(OverButtonStyle(kind: .quiet)).disabled(true)
                        Button {} label: { Image(systemName: "chevron.right") }
                            .buttonStyle(OverButtonStyle(kind: .quiet))
                        Button("全部英雄") {}.buttonStyle(OverButtonStyle(kind: .quiet))
                    }
                    HStack(spacing: 8) {
                        LaunchHeroCard(portrait: nil, title: "默认 OW 标志", englishName: "Overwatch", selected: !running) {}
                        ForEach(compact ? ["ana", "tracer", "genji", "mercy"] : ["ana", "tracer", "genji", "mercy", "dva", "ashe", "mei", "reaper", "hanzo"], id: \.self) { id in
                            LaunchHeroCard(portrait: portrait(id), title: id, englishName: id, selected: running && id == "genji") {}
                        }
                    }.padding(.horizontal, 4).padding(.vertical, 5)
                }
            }.padding(compact ? 22 : 36)
        }.frame(width: width).background(LauncherTheme.background)
            .foregroundStyle(LauncherTheme.text).buttonStyle(OverButtonStyle())
    }
}

@main struct RenderHomeSheet {
    @MainActor static func main() throws {
        LauncherTheme.registerFonts()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (width, state) in [(CGFloat(660), "ready"), (1120, "ready"), (660, "running"), (660, "import")] {
            let renderer = ImageRenderer(content: HomeSheet(width: width, state: state)); renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "OverLaunchHomeSheet", code: 1)
            }
            try png.write(to: output.appendingPathComponent("home-\(Int(width))-\(state).png"))
        }
    }
}
