import SwiftUI

/// Reservoir card: a vertical split bar (reserved on top, unreserved below) beside the
/// Reserved and Unreserved totals, each pinned level with the end of its bar segment.
struct SummaryContent: View {
    let summary: ReservoirSummary

    private let barWidth: CGFloat = 40
    /// Matches `SectionContainer`'s corner radius.
    private let barCornerRadius: CGFloat = 16

    private var fillFraction: Double {
        reservedFraction(reserved: summary.reserved, balance: summary.balance)
    }

    private var reservedText: String {
        summary.reserved.formatted(.cadWhole)
    }

    private var unreservedText: String {
        summary.unreserved.formatted(.cadWhole)
    }

    var body: some View {
        HStack(spacing: 12) {
            bar

            VStack(alignment: .leading, spacing: 0) {
                stat(label: "Reserved", amount: reservedText, color: .reserved)
                Spacer(minLength: 4)
                stat(label: "Unreserved", amount: unreservedText, color: .unreserved)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var bar: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Color.reserved.frame(height: proxy.size.height * fillFraction)
                Color.unreserved
            }
        }
        .frame(width: barWidth)
        .clipShape(.rect(cornerRadius: barCornerRadius))
    }

    private func stat(label: String, amount: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .textCase(.uppercase)
                .tracking(1)

            Text(amount)
                .font(.system(size: 24, weight: .semibold, design: .default))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(color)
    }
}

#Preview("Under-reserved") {
    SectionContainer(title: "Reservoir") {
        SummaryContent(
            summary: ReservoirSummary(balance: 44_400, reserved: 19_750, unreserved: 24_650)
        )
        .frame(height: 100)
    }
    .frame(width: 240)
    .padding(20)
}
