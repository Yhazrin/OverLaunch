// Offline production navigation labels, not a capture of a live app window.
import SwiftUI
import AppKit

struct NavigationSheet: View {
    let width: CGFloat
    private let titles = ["开始", "启动设置", "性能", "外观", "工具箱"]
    var body: some View {
        VStack(spacing: 12) {
            ForEach(titles, id: \.self) { selected in
                HStack(spacing: -9) {
                    ForEach(titles, id: \.self) { title in
                        Button {} label: { GameNavigationTabLabel(title: title, selected: selected == title) }
                            .buttonStyle(OverNavigationStyle()).accessibilityLabel(title)
                    }
                }
                .padding(.horizontal, width < 860 ? 12 : 26)
                .background(LauncherTheme.sidebar).clipped()
            }
        }.padding(.vertical, 16).frame(width: width).background(LauncherTheme.background)
    }
}

@main struct RenderNavigationSheet {
    @MainActor static func main() throws {
        LauncherTheme.registerFonts()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for width: CGFloat in [660, 974, 1120] {
            let renderer = ImageRenderer(content: NavigationSheet(width: width))
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "OverLaunchNavigationSheet", code: 1)
            }
            try png.write(to: output.appendingPathComponent("navigation-\(Int(width)).png"))
        }
    }
}
