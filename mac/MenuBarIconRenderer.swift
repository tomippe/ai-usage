import Cocoa

/// メニューバー用テンプレートアイコン。正本意匠は `icon-menubar.svg` / `icon.svg`（512）。
/// PNG は使わず even-odd で塗り角丸四角から三本バーをくり抜く。
enum MenuBarIconRenderer {
    static let logicalSide: CGFloat = 20
    private static let cardInset: CGFloat = 2
    private static let cardSide: CGFloat = 16
    private static let cardRadius: CGFloat = 2.5

    static func makeTemplateImage() -> NSImage {
        let size = NSSize(width: logicalSide, height: logicalSide)
        let image = NSImage(size: size, flipped: false) { rect in
            drawIcon(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawIcon(in rect: NSRect) {
        let scale = rect.width / logicalSide
        guard scale > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let path = NSBezierPath()
        path.windingRule = .evenOdd

        let card = topRect(x: cardInset, y: cardInset, width: cardSide, height: cardSide, canvas: logicalSide)
            .scaled(by: scale, in: rect)
        path.append(NSBezierPath(roundedRect: card, xRadius: cardRadius * scale, yRadius: cardRadius * scale))

        // 18pt / 13 字形から 20pt / 16 へ等比スケール（icon.svg 比・穴幅は維持）
        let bars: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)] = [
            (5.63, 7.29, 1.91, 6.28),
            (8.95, 9.2, 2.28, 4.62),
            (12.27, 5.38, 1.91, 8.31),
        ]
        for bar in bars {
            let r = topRect(x: bar.x, y: bar.y, width: bar.w, height: bar.h, canvas: logicalSide)
                .scaled(by: scale, in: rect)
            path.appendRect(r)
        }

        NSColor.black.setFill()
        path.fill()
    }

    /// SVG と同じく Y 下向き（viewBox 上端基準）→ AppKit 座標
    private static func topRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, canvas: CGFloat) -> NSRect {
        NSRect(x: x, y: canvas - y - height, width: width, height: height)
    }
}

private extension NSRect {
    func scaled(by scale: CGFloat, in dest: NSRect) -> NSRect {
        NSRect(
            x: dest.minX + minX * scale,
            y: dest.minY + minY * scale,
            width: width * scale,
            height: height * scale
        )
    }
}
