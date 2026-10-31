import SwiftUI

/// Shared page-level chrome — the whole-page analog of `SectionContainer`.
/// Caps page content to one consistent max width, lets it fill the window
/// up to that cap, and centers it horizontally.
/// Scroll-agnostic: callers supply their own `ScrollView` (or none, for pages
/// with internal scrolling).
struct PageContainer<Content: View>: View {
    /// The single knob for page width: cards fill the window up to this width, then center.
    /// Every page routes through here, so changing this one value resizes all tab sections uniformly.
    /// Matches the fixed window width, so pages use the full window.
    static var contentMaxWidth: CGFloat { 1000 }

    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: Self.contentMaxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
