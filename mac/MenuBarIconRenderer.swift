import Cocoa

/// メニューバー用テンプレートアイコン。正本意匠は `icon-menubar.svg` / `icon.svg`（512）。
/// PNG は使わず even-odd で塗り角丸四角から三本バーをくり抜く。
enum MenuBarIconRenderer {
    static let logicalSide: CGFloat = 18

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

        let card = topRect(x: 2.5, y: 2.5, width: 13, height: 13, canvas: logicalSide)
            .scaled(by: scale, in: rect)
        path.append(NSBezierPath(roundedRect: card, xRadius: 2 * scale, yRadius: 2 * scale))

        // バー位置は icon.svg 比。幅は 18pt でも目視できるよう 1.5pt 前後（ベクターなので Retina でも穴が潰れない）
        let bars: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)] = [
            (5.45, 6.8, 1.55, 5.1),
            (8.15, 8.35, 1.85, 3.75),
            (10.85, 5.25, 1.55, 6.75),
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
