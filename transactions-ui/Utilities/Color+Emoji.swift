import SwiftUI
import CoreText
import CoreGraphics

extension Color {
    /// Extracts the dominant color from an emoji string by rendering it
    /// into a small bitmap and averaging the non-transparent pixels.
    static func fromEmoji(_ emoji: String) -> Color? {
        guard !emoji.isEmpty else { return nil }

        let size = 32
        let bytesPerPixel = 4
        let bytesPerRow = size * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: size * size * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Render the emoji via Core Text (cross-platform)
        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, CGFloat(size - 4), nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        let attrString = NSAttributedString(string: emoji, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)

        // Center the glyph in the bitmap
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let xOffset = (CGFloat(size) - bounds.width) / 2 - bounds.origin.x
        let yOffset = (CGFloat(size) - bounds.height) / 2 - bounds.origin.y

        context.textPosition = CGPoint(x: xOffset, y: yOffset)
        CTLineDraw(line, context)

        // Sample pixels — accumulate non-transparent color values
        var totalR = 0.0
        var totalG = 0.0
        var totalB = 0.0
        var count = 0.0

        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * bytesPerPixel
                let a = Double(pixelData[offset + 3])

                guard a > 30 else { continue } // skip near-transparent

                // Un-premultiply
                let factor = 255.0 / a
                let r = Double(pixelData[offset]) * factor
                let g = Double(pixelData[offset + 1]) * factor
                let b = Double(pixelData[offset + 2]) * factor

                // Skip near-white and near-black (outlines / highlights)
                if r > 230 && g > 230 && b > 230 { continue }
                if r < 25 && g < 25 && b < 25 { continue }

                totalR += r
                totalG += g
                totalB += b
                count += 1
            }
        }

        guard count > 0 else { return nil }

        return Color(
            red: totalR / count / 255.0,
            green: totalG / count / 255.0,
            blue: totalB / count / 255.0
        )
    }
}
