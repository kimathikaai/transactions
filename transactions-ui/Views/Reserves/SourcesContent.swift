import SwiftUI

struct SourcesContent: View {
    let sources: [SourceSummary]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                SourceRowView(source: source)

                if index < sources.count - 1 {
                    Divider()
                }
            }
        }
    }
}

// MARK: - Layout

private enum SourceRowLayout {
    static let iconWidth: CGFloat = 24
    static let nameWidth: CGFloat = 80
    static let amountWidth: CGFloat = 90
    static let spacing: CGFloat = 8
}

// MARK: - Source Row

private struct SourceRowView: View {
    let source: SourceSummary

    private var isOverReserved: Bool { source.unreserved < 0 }

    private var progress: Double {
        reservedFraction(reserved: source.reserved, balance: source.balance)
    }

    private var freeLabel: String {
        if isOverReserved {
            return "-\(abs(source.unreserved).formatted(.cad)) over"
        }
        return "\(source.unreserved.formatted(.cad)) free"
    }

    private var tooltipText: String {
        "\(source.reserved.formatted(.cad)) reserved · \(source.unreserved.formatted(.cad)) free · \(source.balance.formatted(.cad)) total"
    }

    var body: some View {
        HStack(spacing: SourceRowLayout.spacing) {
            Group {
                if isOverReserved {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: source.account.type.symbol)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .frame(width: SourceRowLayout.iconWidth, alignment: .center)

            Text(source.account.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: SourceRowLayout.nameWidth, alignment: .leading)

            ProgressView(value: progress)
                .tint(isOverReserved ? .red : Color.reserved)
                .frame(maxWidth: .infinity)

            Text(freeLabel)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(isOverReserved ? .red : .secondary)
                .lineLimit(1)
                .frame(width: SourceRowLayout.amountWidth, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .help(tooltipText)
    }
}

// MARK: - Preview

#Preview("Mixed sources") {
    let sources: [SourceSummary] = [
        SourceSummary(
            account: Account(name: "Chequing", type: .chequing, initialBalance: 4_200, csvFileName: ""),
            balance: 4_200, reserved: 1_500, unreserved: 2_700
        ),
        SourceSummary(
            account: Account(name: "High-Interest Savings", type: .savings, initialBalance: 22_000, csvFileName: ""),
            balance: 22_000, reserved: 15_000, unreserved: 7_000
        ),
        SourceSummary(
            account: Account(name: "TFSA", type: .investment, initialBalance: 18_200, csvFileName: ""),
            balance: 18_200, reserved: 3_250, unreserved: 14_950
        ),
        SourceSummary(
            account: Account(name: "Travel Rewards Card", type: .debt, initialBalance: -1_800, csvFileName: ""),
            balance: -1_800, reserved: 0, unreserved: -1_800
        ),
    ]

    SectionContainer(title: "Sources") {
        SourcesContent(sources: sources)
    }
    .frame(width: 720)
    .padding(20)
}
