import SwiftUI
import CoreText

enum LauncherTheme {
    static let background = Color(red: 0.78, green: 0.83, blue: 0.90)
    static let sidebar = Color(red: 0.07, green: 0.10, blue: 0.19)
    static let surface = Color(red: 0.91, green: 0.94, blue: 0.97)
    static let text = Color(red: 0.10, green: 0.15, blue: 0.24)
    static let muted = Color(red: 0.29, green: 0.36, blue: 0.46)
    static let accent = Color(red: 0.94, green: 0.32, blue: 0.08)
    static let blue = Color(red: 0.025, green: 0.32, blue: 0.63)
    static let cyan = Color(red: 0.09, green: 0.80, blue: 0.86)
    static let rule = Color(red: 0.36, green: 0.45, blue: 0.58).opacity(0.25)
    static let success = Color(red: 0.08, green: 0.38, blue: 0.28)
    static let settingRow = Color(red: 0.24, green: 0.28, blue: 0.36).opacity(0.68)
    // A tall condensed Latin face with macOS CJK fallback. These are visual
    // substitutes, not Blizzard's proprietary Big Noodle / localized fonts.
    static let displayFont = "DINCondensed-Bold"
    static func heading(_ size: CGFloat) -> Font { .custom(displayFont, size: size) }
    static func uiFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("PingFangSC-Regular", size: size).weight(weight)
    }
    static func chineseHeading(_ size: CGFloat) -> Font { .custom("SmileySans-Oblique", size: size) }
    static func registerFonts() {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Fonts/SmileySans-Oblique.otf")
        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/Fonts/SmileySans-Oblique.otf")
        guard let url = [bundled, local].compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return }
        // Registration lasts for this process only. Never install system fonts.
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

/// DIN Condensed has no italic face on macOS. Use a small geometric shear
/// rather than an italic modifier that silently keeps this custom face upright.
struct GameDisplayText: View {
    let text: String
    let size: CGFloat
    var spacing: CGFloat = 1
    var body: some View {
        Text(text).font(LauncherTheme.heading(size)).tracking(spacing)
            .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.18, d: 1, tx: size * 0.18, ty: 0))
            .padding(.trailing, size * 0.18)
    }
}

struct SlantedPanel: Shape {
    func path(in rect: CGRect) -> Path {
        let slant = min(15.0, rect.width * 0.15)
        return Path { p in
            p.move(to: CGPoint(x: rect.minX + slant, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - slant, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); p.closeSubpath()
        }
    }
}

struct OWEmblem: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) * 0.37
            var crown = Path(); crown.addArc(center: center, radius: r, startAngle: .degrees(220), endAngle: .degrees(320), clockwise: false)
            context.stroke(crown, with: .color(LauncherTheme.accent), style: StrokeStyle(lineWidth: r * 0.30))
            var ring = Path(); ring.addArc(center: center, radius: r, startAngle: .degrees(331), endAngle: .degrees(569), clockwise: false)
            context.stroke(ring, with: .color(Color(red: 0.93, green: 0.96, blue: 0.99)), style: StrokeStyle(lineWidth: r * 0.30))
            var arms = Path()
            for direction in [-1.0, 1.0] {
                arms.move(to: CGPoint(x: center.x + direction * r * 0.12, y: center.y - r * 0.55))
                arms.addLine(to: CGPoint(x: center.x + direction * r * 0.12, y: center.y))
                arms.addLine(to: CGPoint(x: center.x + direction * r * 0.77, y: center.y + r * 0.66))
            }
            context.stroke(arms, with: .color(Color(red: 0.93, green: 0.96, blue: 0.99)), style: StrokeStyle(lineWidth: r * 0.29, lineJoin: .miter))
        }
    }
}
