import SwiftUI

/// Shared page-level chrome — the whole-page analog of `SectionContainer`.
/// Caps page content to one consistent max width, lets it fill the detail pane
/// up to that cap, centers it horizontally, and sets the navigation title.
/// Scroll-agnostic: callers supply their own `ScrollView` (or none, for pages
/// with internal scrolling).
struct PageContainer<Content: View>: View {
    /// The single knob for page width: cards fill the detail pane up to this width, then center.
    /// Every page routes through here, so changing this one value resizes all tab sections uniformly.
    static var contentMaxWidth: CGFloat { 900 }

    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: Self.contentMaxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle(title)
    }
}
