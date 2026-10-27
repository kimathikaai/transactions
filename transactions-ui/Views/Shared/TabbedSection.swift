import SwiftUI

/// One tab in a `TabbedSection`: metadata plus its content. Content is captured as a
/// closure and type-erased so different tabs can render entirely different view types;
/// it is only evaluated for the selected tab.
struct SectionTab {
    let title: String
    let symbol: String       // shown in the rail; ignored when there is a single tab
    let help: String?
    let content: () -> AnyView

    init<Content: View>(
        _ title: String,
        symbol: String,
        help: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.help = help
        self.content = { AnyView(content()) }
    }
}

/// Collects the `SectionTab`s declared in a `TabbedSection { … }` body.
@resultBuilder
enum TabbedSectionBuilder {
    static func buildBlock(_ tabs: SectionTab...) -> [SectionTab] { tabs }
}

/// A titled card section with an optional vertical symbol rail for switching between
/// tabs. Reuses `SectionContainer` for card chrome. When there is only one tab the rail
/// is hidden but its width is still reserved (via `.hidden()`), so cards stacked on the
/// same page share a common left edge whether or not they have tabs.
struct TabbedSection: View {
    private let tabs: [SectionTab]
    @State private var selection = 0

    init(@TabbedSectionBuilder _ tabs: () -> [SectionTab]) {
        self.tabs = tabs()
    }

    var body: some View {
        // Clamp defensively; a section is expected to have at least one tab.
        let index = min(selection, max(tabs.count - 1, 0))
        HStack(alignment: .top, spacing: 12) {
            rail.padding(.top, 21)
            SectionContainer(title: tabs[index].title) {
                tabs[index].content()
            }
        }
    }

    /// The rail is always built so its width is constant; single-tab sections hide it
    /// (keeps layout, drops hit-testing) to reserve the gutter and stay aligned.
    @ViewBuilder
    private var rail: some View {
        if tabs.count > 1 {
            TabRail(tabs: tabs, selection: $selection)
        } else {
            TabRail(tabs: tabs, selection: $selection).hidden()
        }
    }
}

/// Bare vertical strip of symbol buttons that selects the active tab by index.
private struct TabRail: View {
    let tabs: [SectionTab]
    @Binding var selection: Int

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                TabRailButton(tab: tab, isSelected: selection == index) {
                    selection = index
                }
            }
        }
    }
}

/// One symbol button. The active tab shows a filled rounded-square glass background behind a
/// white glyph; inactive tabs are a bare `.secondary` glyph.
private struct TabRailButton: View {
    let tab: SectionTab
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 36, height: 36)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .contentShape(.rect(cornerRadius: 16))
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16).fill(.thickMaterial)
                    }
                }
                .glassEffect(isSelected ? .regular.tint(.clear) : .identity, in: .rect(cornerRadius: 16))
                .hoverHighlight(in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .help(tab.help ?? tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Two tabs") {
    TabbedSection {
        SectionTab("Reserves", symbol: "tray.2", help: "Reserves — savings goals") {
            Text("Reserves content")
        }
        SectionTab("Activity", symbol: "clock.arrow.circlepath", help: "Activity history") {
            Text("Activity content")
        }
    }
    .padding(20)
}

#Preview("Single tab (gutter reserved)") {
    TabbedSection {
        SectionTab("Reservoir", symbol: "drop") {
            Text("Reservoir content")
        }
    }
    .padding(20)
}
