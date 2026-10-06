import Foundation
import CoreGraphics

@main struct CheckDropdownPlacement {
    static func main() {
        let cases: [(CGRect, CGSize, CGFloat, Bool)] = [
            (CGRect(x: 800, y: 180, width: 284, height: 44), CGSize(width: 1120, height: 780), 220, false),
            (CGRect(x: 414, y: 420, width: 208, height: 44), CGSize(width: 660, height: 500), 360, true),
            (CGRect(x: 414, y: 280, width: 208, height: 44), CGSize(width: 660, height: 500), 360, true),
            (CGRect(x: 414, y: 110, width: 208, height: 44), CGSize(width: 660, height: 500), 360, false),
            (CGRect(x: 520, y: 320, width: 284, height: 44), CGSize(width: 660, height: 500), 220, true),
            (CGRect(x: 720, y: 600, width: 284, height: 44), CGSize(width: 1120, height: 780), 44, false)
        ]
        for (anchor, canvas, height, direction) in cases {
            let placement = DropdownGeometry(anchor: anchor, canvas: canvas, topInset: 106, idealHeight: height)
            let frame = placement.frame
            precondition(placement.opensUp == direction)
            precondition(frame.minX >= 8 && frame.maxX <= canvas.width - 8)
            precondition(frame.minY >= 106 && frame.maxY <= canvas.height - 8)
            precondition(frame.height <= height && frame.height > 0)
            precondition(direction ? frame.maxY == anchor.minY : frame.minY == anchor.maxY)
        }
        print("Dropdown placement: 6 connected-field / narrow-window / long-list cases passed")
    }
}
