import SwiftUI

// Row-style hover affordance: a subtle, animated background overlay driven by
// pointer hover. Uses `Color.primary` so it adapts to light/dark, unlike a
// hardcoded white overlay. Clipped to any `Shape`, mirroring `background(_:in:)`.
//
//   Button(action: …) { … }
//       .buttonStyle(.plain)
//       .hoverHighlight()                       // rectangle
//       .hoverHighlight(in: .rect(cornerRadius: 12))
//       .hoverHighlight(in: .capsule)           // pill / circle
//       .hoverHighlight(in: .rect(cornerRadius: 4), color: .red, opacity: 0.15)  // tinted
struct HoverHighlight<S: Shape>: ViewModifier {
    var shape: S
    // Defaults reproduce the original neutral affordance; callers can tint it
    // (e.g. a category's color) and bump opacity so the color reads clearly.
    var color: Color = .primary
    var opacity: Double = 0.07
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                color
                    .opacity(isHovered ? opacity : 0),
                in: shape
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

extension View {
    /// Hover affordance clipped to `shape` (e.g. `.rect(cornerRadius:)`, `.capsule`).
    /// `color`/`opacity` default to the neutral `Color.primary` at 0.07; pass a tint to
    /// highlight in a specific color.
    func hoverHighlight(
        in shape: some Shape = .rect,
        color: Color = .primary,
        opacity: Double = 0.07
    ) -> some View {
        modifier(HoverHighlight(shape: shape, color: color, opacity: opacity))
    }
}
