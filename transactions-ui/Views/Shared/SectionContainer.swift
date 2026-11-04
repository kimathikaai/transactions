import SwiftUI

/// Card surface treatment for `SectionContainer`.
enum SectionContainerStyle {
    /// Thick material + glass: the default card that sits above the page.
    case raised
    /// No fill, just a border in the title's `.secondary` style: a frame that holds raised tiles.
    case outlined
}

struct SectionContainer<Accessory: View, Content: View>: View {
    let title: String
    var style: SectionContainerStyle = .raised
    /// Optional trailing control in the title row (e.g. a `+` button). Keep it caption-sized
    /// so the title row height matches neighbouring cards.
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    private let cornerRadius: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.light)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1)
                Spacer(minLength: 0)
                accessory()
            }
            .padding(.horizontal, 16)

            surface(content().frame(maxWidth: .infinity).padding(20))
        }
    }

    @ViewBuilder
    private func surface(_ view: some View) -> some View {
        switch style {
        case .raised:
            view
                .background(.thickMaterial, in: .rect(cornerRadius: cornerRadius))
                .glassEffect(
                    .regular.tint(.clear),
                    in: .rect(cornerRadius: cornerRadius)
                )
        case .outlined:
            view
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.secondary, lineWidth: 1)
                )
        }
    }
}

extension SectionContainer where Accessory == EmptyView {
    init(
        title: String,
        style: SectionContainerStyle = .raised,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(title: title, style: style, accessory: { EmptyView() }, content: content)
    }
}
