import AppKit
import OW120Core

@MainActor
final class AppAppearance {
    let catalog: HeroIconCatalog
    private var images: [String: NSImage] = [:]
    private let directory: URL
    init(directory: URL = Assets.heroIcons) throws {
        self.directory = directory
        catalog = try HeroIconCatalog(contentsOf: directory.appendingPathComponent("catalog.json"))
    }
    func portrait(_ id: String) -> NSImage? {
        guard id != "default", catalog.contains(id) else { return nil }
        if let cached = images[id] { return cached }
        guard let image = NSImage(contentsOf: directory.appendingPathComponent("2d/\(id).png")) else { return nil }
        images[id] = image
        return image
    }
    func icon(_ id: String) -> NSImage? {
        if id == "default" {
            let resource = Bundle.main.resourceURL?.appendingPathComponent("OW120.icns")
            return resource.flatMap { NSImage(contentsOf: $0) }
        }
        guard let hero = portrait(id) else { return nil }
        return NSImage(size: NSSize(width: 512, height: 512), flipped: false) { rect in
            NSColor(calibratedRed: 0.075, green: 0.10, blue: 0.19, alpha: 1).setFill()
            let base = NSBezierPath(roundedRect: rect.insetBy(dx: 24, dy: 24), xRadius: 104, yRadius: 104)
            base.fill()
            NSGraphicsContext.saveGraphicsState(); base.addClip()
            hero.draw(in: rect.insetBy(dx: 28, dy: 28), from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }
    /// Supported dynamic macOS application icon. Finder custom icons attach
    /// resource forks/FinderInfo that fail strict signature verification, so
    /// never use setIcon(forFile:) on a signed launcher bundle.
    func apply(_ appearance: LauncherAppearance) throws {
        guard let image = icon(appearance.iconID) else { throw OWError.message("英雄图标无法读取，请重新选择。") }
        NSApplication.shared.applicationIconImage = image
    }
}
