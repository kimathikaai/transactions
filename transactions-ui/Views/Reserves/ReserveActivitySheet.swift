import SwiftUI

/// A read-only sheet showing the activity ledger for a single reserve — the same
/// rows as the Reserves page's global Activity section, filtered to just this
/// reserve. Reuses `ActivityContent` unchanged; the per-row delete on `.use`
/// rows stays functional. Styled after `ReserveUseSheet` (footer with a single
/// dismiss button, clear presentation background).
struct ReserveActivitySheet: View {
    let reserve: Reserve

    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    // All activity for this reserve, newest-first (reserveActivity is already sorted).
    private var rows: [AppViewModel.ReserveActivityRow] {
        viewModel.reserveActivity.filter { $0.reserveID == reserve.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                SectionContainer(title: "Activity") {
                    ActivityContent(
                        rows: rows,
                        onDelete: { viewModel.deleteReserveEvent(id: $0) }
                    )
                }
            }

            HStack {
                Spacer(minLength: 0)
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 360)
        .presentationBackground(.clear)
    }
}

// MARK: - Previews

#Preview("Reserve Activity") {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-\(UUID())", isDirectory: true)
    let reserve = Reserve(name: "Vacation", emoji: "🏖️", colorHex: "", target: 5_000, tagline: "")
    let accountID = UUID()
    let eventStore = ReserveEventStore(fileURL: dir.appendingPathComponent("reserveEvents.json"))
    try? eventStore.append(ReserveEvent(
        reserveID: reserve.id, accountID: accountID, type: .allocation, amount: 1_240
    ))
    try? eventStore.append(ReserveEvent(
        reserveID: reserve.id, accountID: accountID, type: .release, amount: 200
    ))
    let vm = AppViewModel(
        accountStore: AccountStore(fileURL: dir.appendingPathComponent("accounts.json")),
        reserveStore: ReserveStore(fileURL: dir.appendingPathComponent("reserves.json")),
        reserveEventStore: eventStore,
        editStore: EditStore(fileURL: dir.appendingPathComponent("edits.json"))
    )
    vm.upsertReserve(reserve)
    return ReserveActivitySheet(reserve: reserve)
        .frame(width: 640)
        .padding(40)
        .environment(vm)
}
