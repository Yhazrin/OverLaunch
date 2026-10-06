import Foundation
import CoreGraphics

/// Keeps a dropdown connected to its field and within the content canvas.
/// Long lists scroll; they never extend above the navigation or below the window.
struct DropdownGeometry {
    let frame: CGRect
    let opensUp: Bool
    init(anchor: CGRect, canvas: CGSize, topInset: CGFloat = 8, idealHeight: CGFloat) {
        let top = min(max(8, topInset), max(8, canvas.height - 52))
        let bottom = max(top + 44, canvas.height - 8)
        let below = max(0, bottom - anchor.maxY)
        let above = max(0, anchor.minY - top)
        opensUp = below < idealHeight && above > below
        let height = min(idealHeight, max(1, opensUp ? above : below))
        let width = min(anchor.width, max(1, canvas.width - 16))
        let x = min(max(8, anchor.minX), max(8, canvas.width - width - 8))
        let y = opensUp ? max(top, anchor.minY - height) : min(anchor.maxY, bottom - height)
        frame = CGRect(x: x, y: y, width: width, height: height)
    }
}
