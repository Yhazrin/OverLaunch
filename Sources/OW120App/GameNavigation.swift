import SwiftUI
import CoreText

/// Render the five navigation titles from the registered font's actual ink
/// bounds. This keeps the final slanted glyph out of SwiftUI Text's clipping
/// layer while retaining the same typeface and an accessible button label.
struct GameNavigationTabLabel: View {
    let title: String
    let selected: Bool

    var body: some View {
        let outline = NavigationTitleCache.outline(title)
        Path(outline.path).fill(Color.white)
            .frame(width: outline.size.width, height: outline.size.height)
            .fixedSize()
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(selected ? LauncherTheme.blue : Color.white.opacity(0.025), in: SlantedPanel())
            .overlay(alignment: .bottom) {
                if selected { Rectangle().fill(LauncherTheme.cyan).frame(height: 3) }
            }
            .clipShape(SlantedPanel())
            .contentShape(SlantedPanel())
            .accessibilityHidden(true)
    }
}

private struct NavigationTitleOutline {
    let path: CGPath
    let size: CGSize
}

@MainActor
private enum NavigationTitleCache {
    private static var titles: [String: NavigationTitleOutline] = [:]

    static func outline(_ text: String) -> NavigationTitleOutline {
        if let cached = titles[text] { return cached }
        let font = CTFontCreateWithName("SmileySans-Oblique" as CFString, 20, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ]))
        let glyphPath = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName] as! CTFont
            for index in 0..<count {
                if let path = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) {
                    glyphPath.addPath(path, transform: CGAffineTransform(translationX: positions[index].x, y: positions[index].y))
                }
            }
        }
        let bounds = glyphPath.boundingBoxOfPath
        // Reserve actual glyph extents plus an antialiasing margin on every
        // edge; neither the font advance nor a flexible Text frame clips ink.
        let margin: CGFloat = 3
        var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                         tx: margin - bounds.minX, ty: margin + bounds.maxY)
        let outline = NavigationTitleOutline(
            path: glyphPath.copy(using: &transform)!,
            size: CGSize(width: bounds.width + margin * 2, height: bounds.height + margin * 2)
        )
        titles[text] = outline
        return outline
    }
}
