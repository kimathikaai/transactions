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
    @State private var isHovering = false

    // Held = still reserved (not yet spent) = Σallocation − Σrelease − Σuse.
    private var heldAmount: Double {
        total(of: reserve.id, reservations: viewModel.reservations)
    }

    // Used = cumulative money spent toward the goal (the teal bar segment).
    private var usedAmount: Double {
        used(of: reserve.id, events: viewModel.reserveEvents)
    }

    // Bar total fill (held + used) over target, capped at 1.
    private var filledFraction: Double {
        filledProgress(of: reserve, reservations: viewModel.reservations, events: viewModel.reserveEvents)
    }

    // The spent segment, as a fraction of target, never exceeding the fill.
    private var usedFraction: Double {
        guard reserve.target > 0 else { return 0 }
        return min(filledFraction, usedAmount / reserve.target)
    }

    private let cornerRadius: CGFloat = 12

    var body: some View {
        Menu {
            menuItems
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ReserveEmojiChip(emoji: reserve.emoji, size: 20)

                    Text(reserve.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                description

                progressSlot
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .contentShape(.rect(cornerRadius: cornerRadius))
            .hoverHighlight(in: .rect(cornerRadius: cornerRadius))
            .background(.thickMaterial, in: .rect(cornerRadius: cornerRadius))
            .glassEffect(.regular.tint(.clear), in: .rect(cornerRadius: cornerRadius))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .help(equationHelp)
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

    // One-line tagline. Description is mandatory for new edits, but older reserves
    // may still have none, so a placeholder keeps every card the same height.
    @ViewBuilder private var description: some View {
        let tagline = reserve.tagline.trimmingCharacters(in: .whitespacesAndNewlines)
        Group {
            if tagline.isEmpty {
                Text("No description")
                    .italic()
                    .foregroundStyle(.tertiary)
            } else {
                Text(tagline)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    // The progress bar, swapped on hover for the colour-coded equation
    // (used + held) / target. Fixed height so the card never resizes on hover.
    private var progressSlot: some View {
        ZStack {
            ReserveProgressBar(filledFraction: filledFraction, usedFraction: usedFraction)
                .opacity(isHovering ? 0 : 1)

            equation
                .opacity(isHovering ? 1 : 0)
        }
        .frame(height: 16)
    }

    // Colour carries the meaning (spent = used, reserved = held), matching the bar segments.
    private var equation: some View {
        let usedText = Text(usedAmount, format: .cadWhole).foregroundStyle(Color.spent)
        let heldText = Text(heldAmount, format: .cadWhole).foregroundStyle(Color.reserved)
        return Text("(\(usedText) + \(heldText)) / \(reserve.target, format: .cadWhole)")
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
    }

    // Worded version of `equation` for the tooltip.
    private var equationHelp: String {
        let used = usedAmount.formatted(.cadWhole)
        let held = heldAmount.formatted(.cadWhole)
        let target = reserve.target.formatted(.cadWhole)
        return "(\(used) used + \(held) held) / \(target) target"
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
}

/// Horizontal 3-segment bar over a faint track: a leading "spent" (used)
/// segment, then "reserved" (held), then the empty remainder up to the target.
/// `usedFraction` is expected to be ≤ `filledFraction`; both are fractions of target.
private struct ReserveProgressBar: View {
    let filledFraction: Double      // held + used, over target
    let usedFraction: Double        // used, over target
    var height: CGFloat = 6

    var body: some View {
        let filled = min(max(filledFraction, 0), 1)
        let used = min(max(usedFraction, 0), 1)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Color.reserved.opacity(0.15)                       // empty track
                Color.reserved.frame(width: proxy.size.width * filled)  // held + used
                Color.spent.frame(width: proxy.size.width * used)       // used (spent)
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
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
        .frame(width: 215)
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
        .frame(width: 215)
        .padding(20)
        .environment(previewViewModel(reserve: reserve, allocation: 850))
}
