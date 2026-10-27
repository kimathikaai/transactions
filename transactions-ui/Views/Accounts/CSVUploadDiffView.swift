import SwiftUI

struct PendingUpload: Identifiable {
    let id = UUID()
    let account: Account
    let diff: CSVDiff
    let rawCsv: String
    let addedRawLines: [String]
    let existingIsEmpty: Bool
}

struct CSVUploadDiffView: View {
    let pending: PendingUpload
    var commitReplace: () -> Void
    var commitAppend: () -> Void
    var cancel: () -> Void
    var commitError: Error?

    @State private var addExpanded = true
    @State private var removeExpanded = true

    private var addedCount: Int { pending.diff.added.count }
    private var removedCount: Int { pending.diff.removed.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if removedCount > 0 && !pending.existingIsEmpty {
                warningBanner
            }
            if let commitError {
                errorBanner(commitError)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !pending.diff.added.isEmpty {
                        DisclosureGroup(isExpanded: $addExpanded) {
                            VStack(spacing: 0) {
                                ForEach(sortedAdds, id: \.contentHash) { tx in
                                    DiffRow(transaction: tx, sign: .add)
                                }
                            }
                            .padding(.top, 4)
                        } label: {
                            Text("Will add (\(addedCount))")
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    if !pending.diff.removed.isEmpty && !pending.existingIsEmpty {
                        DisclosureGroup(isExpanded: $removeExpanded) {
                            VStack(spacing: 0) {
                                ForEach(sortedRemoves, id: \.contentHash) { tx in
                                    DiffRow(transaction: tx, sign: .remove)
                                }
                            }
                            .padding(.top, 4)
                        } label: {
                            Text("Will remove if you Replace (\(removedCount))")
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    if pending.diff.isEmpty {
                        Text("No changes — this CSV is identical to what's already imported.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 16)
                    }
                }
            }

            Divider()

            buttonRow
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 360, idealHeight: 600)
    }

    // MARK: - Button row

    @ViewBuilder
    private var buttonRow: some View {
        HStack(spacing: 12) {
            Button("Cancel") { cancel() }
                .keyboardShortcut(.cancelAction)
            Spacer()

            if pending.existingIsEmpty {
                // New account / first upload — no history to preserve, single button.
                Button("Commit (+\(addedCount))") { commitReplace() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(pending.diff.isEmpty)
            } else if pending.diff.isEmpty {
                Button("Commit") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            } else if pending.diff.removed.isEmpty {
                // Adds only — Append and Replace are equivalent; single button.
                Button("Commit (+\(addedCount))") { commitAppend() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Replace (+\(addedCount), −\(removedCount))") { commitReplace() }
                    .buttonStyle(.bordered)
                    .tint(.red)
                Button("Append (+\(addedCount))") { commitAppend() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(pending.diff.added.isEmpty)
                    .help(pending.diff.added.isEmpty ? "No new rows to append." : "")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Import CSV")
                .font(.headline)
            Text(pending.account.name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var warningBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("\(removedCount) existing transactions are missing from this CSV. Click **Replace** to delete them, or **Append** to keep them.")
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.1))
        )
    }

    @ViewBuilder
    private func errorBanner(_ error: Error) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't commit changes")
                    .font(.caption.weight(.semibold))
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.red.opacity(0.1))
        )
    }

    private var sortedAdds: [Transaction] {
        pending.diff.added.sorted { $0.date < $1.date }
    }

    private var sortedRemoves: [Transaction] {
        pending.diff.removed.sorted { $0.date < $1.date }
    }
}

private struct DiffRow: View {
    enum Sign { case add, remove }

    let transaction: Transaction
    let sign: Sign

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        // Dates originate from BankCsvParser anchored at 00:00 UTC — render
        // in UTC so the diff preview matches the raw CSV row byte-for-byte.
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sign == .add ? "plus" : "minus")
                .font(.caption2.weight(.bold))
                .foregroundStyle(sign == .add ? Color.income : Color.expense)
                .frame(width: 12)
            Text(Self.dateFormatter.string(from: transaction.date))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(transaction.details)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(transaction.amount.formatted(.cad))
                .font(.caption.monospacedDigit())
                .foregroundStyle(transaction.amount < 0 ? Color.expense : .primary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
    }
}
