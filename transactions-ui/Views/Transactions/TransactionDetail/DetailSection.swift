import SwiftUI

/// The colour of a section's status chip.
enum DetailStatusTint {
    case neutral     // nothing set yet, nothing wrong
    case attention   // overridden / needs a look
    case done        // linked or following the rules
}

/// One collapsible card in the transaction modal: a header row (chevron, title,
/// status chip) that toggles the section, a one-line descriptor of what the
/// section is for (shown even when collapsed), then the content when expanded.
struct DetailSection<Content: View>: View {
    let title: String
    let descriptor: String
    let status: String
    let statusTint: DetailStatusTint
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)

            Text(descriptor)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 20)

            if isExpanded {
                content()
                    .padding(.leading, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .detailCardBackground()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 12)
            Text(title)
                .font(.callout.weight(.semibold))
            Spacer(minLength: 8)
            statusChip
        }
        .contentShape(.rect)
    }

    private var statusChip: some View {
        Text(status)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(chipForeground)
            .background(chipBackground, in: Capsule())
    }

    private var chipForeground: Color {
        switch statusTint {
        case .neutral:   return .secondary
        case .attention: return .orange
        case .done:      return .income
        }
    }

    private var chipBackground: Color {
        switch statusTint {
        case .neutral:   return .secondary.opacity(0.12)
        case .attention: return .orange.opacity(0.15)
        case .done:      return Color.income.opacity(0.15)
        }
    }
}

extension View {
    /// The transaction modal's card recipe: material fill, continuous 16pt corners
    /// (matches `CategoryEditSheet` / `ReserveEditSheet`).
    func detailCardBackground() -> some View {
        self
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
            )
    }
}
