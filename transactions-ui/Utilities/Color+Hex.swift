import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        #if canImport(AppKit)
        guard let comps = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(comps.redComponent * 255)
        let g = Int(comps.greenComponent * 255)
        let b = Int(comps.blueComponent * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
        #else
        return "#000000"
        #endif
    }
}
