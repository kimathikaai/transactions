import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Create/edit a reserve. Styled after the macOS Calendar "New Event" quick
/// editor: no field captions — the placeholder text carries intent and is
/// overwritable. `reserve == nil` is create mode.
struct ReserveEditSheet: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    let reserve: Reserve?

    @State private var name: String
    @State private var emoji: String
    @State private var target: Double
    @State private var tagline: String

    @FocusState private var nameFocused: Bool
    @State private var confirmDelete = false

    init(reserve: Reserve?) {
        self.reserve = reserve
        _name = State(initialValue: reserve?.name ?? "")
        _emoji = State(initialValue: reserve?.emoji ?? "🪣")
        _target = State(initialValue: reserve?.target ?? 0)
        _tagline = State(initialValue: reserve?.tagline ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Both name and target are mandatory; Save stays disabled until both are provided.
    private var canSave: Bool { !trimmedName.isEmpty && target > 0 }

    // Sources with an active (non-zero) allocation to this reserve, largest first.
    // Empty in create mode — a reserve that doesn't exist yet has no reservations.
    private var allocations: [(account: Account, amount: Double)] {
        guard let reserve else { return [] }
        var result: [(account: Account, amount: Double)] = []
        for reservation in viewModel.reservations
        where reservation.reserveID == reserve.id && reservation.amount != 0 {
            if let account = viewModel.account(id: reservation.accountID) {
                result.append((account: account, amount: reservation.amount))
            }
        }
        return result.sorted { $0.amount > $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerCard
            targetCard
            sourcesSection
            footer
        }
        .padding(20)
        .frame(minWidth: 420)
        .presentationBackground(.clear)
        .onAppear { nameFocused = true }
        .confirmationDialog(
            "Delete \(trimmedName.isEmpty ? "reserve" : trimmedName)?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            if let reserve {
                Button("Delete reserve and release \(total(of: reserve.id, reservations: viewModel.reservations).formatted(.cad))", role: .destructive) {
                    viewModel.deleteReserve(id: reserve.id)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All reservations will be released back to their source accounts.")
        }
    }

    // Name + emoji picker, divider, description — one material card.
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 0) {
                TextField("New Reserve", text: $name)
                    .textFieldStyle(.plain)
                    .font(.title.weight(.bold))
                    .focused($nameFocused)
                    
                Spacer()
                EmojiPickerChip(emoji: $emoji)
            }

            Divider()

            TextField("Add a description", text: $tagline)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    // Target — its own prominent card since it's mandatory.
    private var targetCard: some View {
        TextField(
            "Target Amount",
            value: Binding(
                get: { target == 0 ? nil : target },
                set: { target = $0 ?? 0 }
            ),
            format: .cad
        )
        .textFieldStyle(.plain)
        .font(.callout)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    // Read-only strip of the sources currently allocating to this reserve.
    // Under a bare divider; wraps to as many rows as needed.
    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            if allocations.isEmpty {
                Text("No allocations yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout {
                    ForEach(allocations, id: \.account.id) { allocation in
                        pill(name: allocation.account.name, amount: allocation.amount)
                    }
                }
            }
        }
    }

    private func pill(name: String, amount: Double) -> some View {
        HStack(spacing: 4) {
            Text(name)
            Text(amount, format: .cad)
                .fontWeight(.bold)
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if reserve != nil {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.glass)
            }

            if !canSave {
                Text("Name and target required")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button("Cancel") { dismiss() }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)

            Button("Save", action: save)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
    }

    private func save() {
        let trimmedTagline = tagline.trimmingCharacters(in: .whitespacesAndNewlines)
        if var existing = reserve {
            existing.name = trimmedName
            existing.emoji = emoji
            existing.target = target
            existing.tagline = trimmedTagline
            viewModel.upsertReserve(existing)
        } else {
            let next = Reserve(
                name: trimmedName,
                emoji: emoji,
                colorHex: "#80b1d3",
                target: target,
                tagline: trimmedTagline,
                sortOrder: (viewModel.reserves.map(\.sortOrder).max() ?? -1) + 1
            )
            viewModel.upsertReserve(next)
        }
        dismiss()
    }
}

// MARK: - Emoji picker

/// A tappable emoji chip. On macOS, tapping opens the system Character Viewer,
/// which inserts into the hidden focused field bound to `emoji`. On other
/// platforms the field simply accepts keyboard emoji input.
private struct EmojiPickerChip: View {
    @Binding var emoji: String
    @FocusState private var focused: Bool

    private var tint: Color { Color.fromEmoji(emoji) ?? .accentColor }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.2))

            Text(emoji.isEmpty ? "🪣" : emoji)
                .font(.title2)

            // Invisible receiver: the Character Viewer inserts here when focused.
            TextField("", text: $emoji)
                .textFieldStyle(.plain)
                .focused($focused)
                .frame(width: 1, height: 1)
                .opacity(0.01)
        }
        .frame(width: 36, height: 36)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { openPicker() }
        .onChange(of: emoji) { _, newValue in
            // Keep only the last grapheme so the chip always shows a single emoji.
            let clamped = String(newValue.suffix(1))
            if clamped != emoji { emoji = clamped }
        }
        .help("Pick an emoji")
        .accessibilityLabel("Reserve emoji")
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .hoverHighlight(in: .rect(cornerRadius: 12))
    }

    private func openPicker() {
        focused = true
        #if canImport(AppKit)
        NSApp.orderFrontCharacterPalette(nil)
        #endif
    }
}

// MARK: - Previews

private func previewViewModel() -> AppViewModel {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-\(UUID())", isDirectory: true)
    return AppViewModel(
        accountStore: AccountStore(fileURL: dir.appendingPathComponent("accounts.json")),
        reserveStore: ReserveStore(fileURL: dir.appendingPathComponent("reserves.json")),
        reserveEventStore: ReserveEventStore(fileURL: dir.appendingPathComponent("reserveEvents.json")),
        editStore: EditStore(fileURL: dir.appendingPathComponent("edits.json"))
    )
}

#Preview("Create") {
    ReserveEditSheet(reserve: nil)
        .frame(width: 460)
        .padding(40)
        .environment(previewViewModel())
}

#Preview("Edit") {
    ReserveEditSheet(reserve: Reserve(
        name: "Vacation",
        emoji: "🏖️",
        colorHex: "#80b1d3",
        target: 5_000,
        tagline: "Costa Rica · December"
    ))
    .frame(width: 460)
    .padding(40)
    .environment(previewViewModel())
}
