import SwiftUI

/// A money-movement action reachable from a reserve card's menu (tap or right-click).
enum ReserveMoneyAction {
    case add, release, use
}

struct ReserveCardView: View {
    let reserve: Reserve
    var onEdit: () -> Void = {}
    var onActivity: () -> Void = {}
    var onDelete: () -> Void = {}

    // Money actions, gated by whether they're currently possible.
    var canAddOrRelease: Bool = false
    var canUse: Bool = false
    var onMoneyAction: (ReserveMoneyAction) -> Void = { _ in }

    @Environment(AppViewModel.self) private var viewModel
    @State private var confirmDelete = false

    // Held = still reserved (not yet spent) = Σallocation − Σrelease − Σuse.
    private var heldAmount: Double {
        total(of: reserve.id, reservations: viewModel.reservations)
    }

    // Used = cumulative money spent toward the goal (the teal sub-arc).
    private var usedAmount: Double {
        used(of: reserve.id, events: viewModel.reserveEvents)
    }

    // Ring total fill (held + used) over target, capped at 1.
    private var filledFraction: Double {
        filledProgress(of: reserve, reservations: viewModel.reservations, events: viewModel.reserveEvents)
    }

    // The spent sub-arc, as a fraction of target, never exceeding the fill.
    private var usedFraction: Double {
        guard reserve.target > 0 else { return 0 }
        return min(filledFraction, usedAmount / reserve.target)
    }

    var body: some View {
        Menu {
            menuItems
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ReserveEmojiChip(emoji: reserve.emoji, size: 20)

                ReserveProgressRing(
                    filledFraction: filledFraction,
                    usedFraction: usedFraction
                )

                Text(reserve.name)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 12)

                amounts
            }
            .frame(maxWidth: .infinity, minHeight: 25, maxHeight: 25, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .hoverHighlight(in: .rect(cornerRadius: 6))
        .contextMenu { menuItems }
        .confirmationDialog(
            "Delete \(reserve.name)?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Any funds held in this reserve will be released.")
        }
    }

    // The reserve's actions, shared by the tap-to-open Menu and the right-click
    // context menu so both surface the same list.
    @ViewBuilder private var menuItems: some View {
        Button("Edit", systemImage: "pencil") { onEdit() }
        Button("Activity", systemImage: "list.bullet") { onActivity() }
        Button("Add Funds", systemImage: "plus") { onMoneyAction(.add) }
            .disabled(!canAddOrRelease)
        Button("Release Funds", systemImage: "minus") { onMoneyAction(.release) }
            .disabled(!canAddOrRelease)
        Button("Use Funds", systemImage: "cart") { onMoneyAction(.use) }
            .disabled(!canUse)
        Divider()
        Button(role: .destructive) { confirmDelete = true } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // Trailing figures in fixed-width, trailing-aligned columns so they line up
    // down the list: used (spent, teal — always shown, even at 0), held
    // (still reserved), then the target led by a bullseye.
    private var amounts: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(usedAmount, format: .number.precision(.fractionLength(2)))
                .foregroundStyle(Color.spent)
                .frame(width: 80, alignment: .trailing)

            Text(heldAmount, format: .number.precision(.fractionLength(2)))
                .foregroundStyle(.primary)
                .frame(width: 80, alignment: .trailing)

            HStack(spacing: 4) {
                Image(systemName: "target")
                Text(reserve.target, format: .number.precision(.fractionLength(2)))
            }
            .foregroundStyle(.secondary)
            .frame(width: 104, alignment: .trailing)
        }
        .font(.caption)
        .monospacedDigit()
        .lineLimit(1)
    }
}

/// Circular twin of the old ReserveProgressBar: a leading "spent" (used)
/// arc and a "reserved" (held) arc over a faint empty track. `usedFraction`
/// is expected to be ≤ `filledFraction`; both are fractions of the full circle.
struct ReserveProgressRing: View {
    let filledFraction: Double      // held + used, over target
    let usedFraction: Double        // used, over target
    var lineWidth: CGFloat = 5

    var body: some View {
        let filled = min(max(filledFraction, 0), 1)
        let used = min(max(usedFraction, 0), 1)
        ZStack {
            Circle()                                   // empty track
                .stroke(Color.reserved.opacity(0.15), lineWidth: lineWidth)
            Circle().trim(from: 0, to: filled)         // held + used
                .stroke(Color.reserved,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            Circle().trim(from: 0, to: used)           // used (spent)
                .stroke(Color.spent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
        }
        .rotationEffect(.degrees(-90))                 // start at 12 o'clock
        .frame(width: 12, height: 12)
    }
}

// MARK: - Previews

/// Builds a view model whose reserve ledger already contains an allocation
/// (and optionally a use) so the ring renders with visible fill.
private func previewViewModel(
    reserve: Reserve,
    allocation: Double,
    use: Double = 0
) -> AppViewModel {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-\(UUID())", isDirectory: true)
    let accountID = UUID()
    let eventStore = ReserveEventStore(fileURL: dir.appendingPathComponent("reserveEvents.json"))
    try? eventStore.append(ReserveEvent(
        reserveID: reserve.id, accountID: accountID, type: .allocation, amount: allocation
    ))
    if use > 0 {
        try? eventStore.append(ReserveEvent(
            reserveID: reserve.id, accountID: accountID, type: .use, amount: use
        ))
    }
    return AppViewModel(
        accountStore: AccountStore(fileURL: dir.appendingPathComponent("accounts.json")),
        reserveStore: ReserveStore(fileURL: dir.appendingPathComponent("reserves.json")),
        reserveEventStore: eventStore,
        editStore: EditStore(fileURL: dir.appendingPathComponent("edits.json"))
    )
}

#Preview("Under target") {
    let reserve = Reserve(
        name: "Vacation",
        emoji: "🏖️",
        colorHex: "#80b1d3",
        target: 5000,
        tagline: "Costa Rica · December"
    )
    return ReserveCardView(reserve: reserve)
        .frame(width: 600)
        .padding(20)
        .environment(previewViewModel(reserve: reserve, allocation: 1240, use: 300))
}

#Preview("At target") {
    let reserve = Reserve(
        name: "New Bike",
        emoji: "🚲",
        colorHex: "#80b1d3",
        target: 850,
        tagline: "Spring rebuild"
    )
    return ReserveCardView(reserve: reserve)
        .frame(width: 600)
        .padding(20)
        .environment(previewViewModel(reserve: reserve, allocation: 850))
}
