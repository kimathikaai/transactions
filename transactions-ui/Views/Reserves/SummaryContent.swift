import SwiftUI

struct SummaryContent: View {
    let summary: ReservoirSummary

    private var fillFraction: Double {
        reservedFraction(reserved: summary.reserved, balance: summary.balance)
    }

    private var reservedText: String {
        summary.reserved.formatted(.cad)
    }

    private var unreservedText: String {
        summary.unreserved.formatted(.cad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                stat(amount: reservedText, label: "Reserved", tone: .reserved)
                Spacer(minLength: 24)
                stat(amount: unreservedText, label: "Unreserved", tone: .unreserved)
            }

            ProgressView(value: fillFraction).tint(Color.reserved)
        }
    }

    private func stat(amount: String, label: String, tone: Tone) -> some View {
        VStack(alignment: tone == .reserved ? .leading : .trailing, spacing: 2) {
            Text(amount)
                .font(.system(size: 34, weight: .semibold, design: .default))
                .monospacedDigit()
                .foregroundStyle(tone == .reserved ? Color.reserved : Color.unreserved)

            Text(label)
                .font(.caption)
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(tone == .reserved ? Color.reserved : Color.unreserved)
        }
        .fixedSize()
    }

    private enum Tone { case reserved, unreserved }
}

#Preview("Under-reserved") {
    SectionContainer(title: "Reservoir") {
        SummaryContent(
            summary: ReservoirSummary(balance: 44_400, reserved: 19_750, unreserved: 24_650)
        )
    }
    .frame(width: 720)
    .padding(20)
}
