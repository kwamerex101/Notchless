import AppKit
import SwiftUI

/// Extracts a vibrant representative color from artwork for the album-art glow.
enum ColorExtractor {
    /// Returns a saturated, glow-friendly color sampled from the image, or nil.
    static func vibrantColor(from image: NSImage) -> Color? {
        guard let rep = downscaledBitmap(image, side: 36) else { return nil }

        var bestScore = -1.0
        var best = (r: 0.0, g: 0.0, b: 0.0)
        var sum = (r: 0.0, g: 0.0, b: 0.0)
        var count = 0.0

        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                let r = Double(c.redComponent), g = Double(c.greenComponent), b = Double(c.blueComponent)
                sum.r += r; sum.g += g; sum.b += b; count += 1

                let mx = max(r, g, b), mn = min(r, g, b)
                let sat = mx == 0 ? 0 : (mx - mn) / mx
                // Prefer saturated, mid-to-bright pixels (avoids near-black/near-white).
                let score = sat * mx * (1 - abs(mx - 0.7))
                if score > bestScore {
                    bestScore = score
                    best = (r, g, b)
                }
            }
        }
        guard count > 0 else { return nil }

        // Blend the vibrant pick with the average for stability, then lift
        // saturation/brightness so the glow reads on the black panel.
        let avg = (r: sum.r / count, g: sum.g / count, b: sum.b / count)
        var color = NSColor(
            red: best.r * 0.7 + avg.r * 0.3,
            green: best.g * 0.7 + avg.g * 0.3,
            blue: best.b * 0.7 + avg.b * 0.3,
            alpha: 1
        ).usingColorSpace(.deviceRGB) ?? .systemTeal

        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        color = NSColor(hue: h, saturation: min(1, s * 1.3 + 0.1), brightness: min(1, max(0.5, br)), alpha: 1)
        return Color(nsColor: color)
    }

    private static func downscaledBitmap(_ image: NSImage, side: Int) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
