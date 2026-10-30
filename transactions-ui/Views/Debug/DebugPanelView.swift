#if DEBUG
import AppKit
import SwiftUI

struct DebugPanelView: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var showResetConfirm = false
    @State private var counts: AppViewModel.RowCounts =
        AppViewModel.RowCounts(accounts: 0, transactions: 0, edits: 0,
                               reserves: 0, activity: 0, reimbursements: 0)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Developer")
                    .font(.title2.weight(.semibold))
                Text("DEBUG-only utilities. Not present in release builds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                loadWarningsSection
                rowCountsSection
                dataProfileSection
                categoryBrokenEditsSection
                categoryStructuralSection
                categoryStaleRefsSection
                danglingUseLinksSection
                danglingReimbursementLinksSection
                storePathSection
                resetSection

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .alert("Delete all data?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.resetAllData()
                counts = viewModel.rowCounts()
            }
        } message: {
            Text("This removes every account, transaction, and edit. Cannot be undone.")
        }
        .onAppear { counts = viewModel.rowCounts() }
    }

    // MARK: - Sections

    private var loadWarningsSection: some View {
        section(
            title: "Load warnings",
            description: "Non-fatal problems from the last load. Files on disk are not rewritten."
        ) {
            if viewModel.loadWarnings.isEmpty {
                Text("No load warnings.").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.loadWarnings) { w in
                        Label("\(w.scope): \(w.message)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var rowCountsSection: some View {
        section(title: "Row counts", description: "Counts per data type. Refresh to re-fetch.") {
            HStack(spacing: 20) {
                countCell("Accounts", counts.accounts)
                countCell("Transactions", counts.transactions)
                countCell("Edits", counts.edits)
                countCell("Reserves", counts.reserves)
                countCell("Activity", counts.activity)
                countCell("Reimbursements", counts.reimbursements)
                Spacer()
                Button("Refresh") { counts = viewModel.rowCounts() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var dataProfileSection: some View {
        section(
            title: "Data profile",
            description: "Switch the data folder the whole app reads from. Applies immediately."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Profile", selection: profileBinding) {
                    ForEach(DataProfile.allCases) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(viewModel.activeDataDirectoryPath)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var profileBinding: Binding<DataProfile> {
        Binding(
            get: { viewModel.activeProfile },
            set: { newProfile in
                viewModel.switchProfile(to: newProfile)
                counts = viewModel.rowCounts()
            }
        )
    }

    private var categoryBrokenEditsSection: some View {
        section(
            title: "Broken edits",
            description: "TransactionEdits whose category/subcategory id no longer resolves."
        ) {
            let items = viewModel.categoryValidation.brokenEdits
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Button("Copy") {
                        copyString(DebugValidationClipboard.brokenEditsJSON(items))
                    }
                    .buttonStyle(.bordered)
                    .disabled(items.isEmpty)
                }
                if items.isEmpty {
                    Text("No broken edits.").font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(items) { b in
                            HStack(spacing: 12) {
                                Text(String(b.contentHash.prefix(8)))
                                    .font(.caption.monospaced())
                                Text(b.field.rawValue).font(.caption)
                                Spacer()
                                Text(b.referencedID).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var categoryStructuralSection: some View {
        section(
            title: "Structural violations",
            description: "Corruption sentinel — should be empty under normal ops."
        ) {
            let items = viewModel.categoryValidation.structuralViolations
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Button("Copy") {
                        copyString(DebugValidationClipboard.structuralViolationsJSON(items))
                    }
                    .buttonStyle(.bordered)
                    .disabled(items.isEmpty)
                }
                if items.isEmpty {
                    Text("No structural violations.").font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(items) { v in
                            HStack(spacing: 12) {
                                Text(v.displayName).font(.caption)
                                Text("·").foregroundStyle(.secondary)
                                Text(v.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(v.categoryID).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var categoryStaleRefsSection: some View {
        section(
            title: "Stale edit references",
            description: "Edits whose contentHash matches no currently-loaded transaction."
        ) {
            let items = viewModel.categoryValidation.staleRefs
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Button("Copy") {
                        copyString(DebugValidationClipboard.staleRefsJSON(items))
                    }
                    .buttonStyle(.bordered)
                    .disabled(items.isEmpty)
                }
                if items.isEmpty {
                    Text("No stale edit references.").font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(items) { s in
                            Text(String(s.contentHash.prefix(8)))
                                .font(.caption.monospaced())
                        }
                    }
                }
            }
        }
    }

    private var danglingUseLinksSection: some View {
        section(
            title: "Dangling use links",
            description: "Use activity whose linked transaction no longer resolves."
        ) {
            let items = viewModel.danglingUseLinks
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Button("Copy") {
                        copyString(DebugValidationClipboard.danglingUseLinksJSON(items))
                    }
                    .buttonStyle(.bordered)
                    .disabled(items.isEmpty)
                }
                if items.isEmpty {
                    Text("No dangling use links.").font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(items) { link in
                            HStack(spacing: 12) {
                                Text(String(link.contentHash.prefix(8)))
                                    .font(.caption.monospaced())
                                Spacer()
                                Text(link.reserveName).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var danglingReimbursementLinksSection: some View {
        section(
            title: "Dangling reimbursement links",
            description: "Reimbursement links whose expense or source transaction no longer resolves."
        ) {
            let items = viewModel.danglingReimbursementLinks
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Button("Copy") {
                        copyString(DebugValidationClipboard.danglingReimbursementLinksJSON(items))
                    }
                    .buttonStyle(.bordered)
                    .disabled(items.isEmpty)
                }
                if items.isEmpty {
                    Text("No dangling reimbursement links.").font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(items) { link in
                            HStack(spacing: 12) {
                                Text(String(link.expenseHash.prefix(8)))
                                    .font(.caption.monospaced())
                                Spacer()
                                Text(missingLabel(for: link)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func missingLabel(for link: AppViewModel.DanglingReimbursementLink) -> String {
        switch (link.expenseMissing, link.sourceMissing) {
        case (true, true):  return "expense + source missing"
        case (true, false): return "expense missing"
        default:            return "source missing"
        }
    }

    private var storePathSection: some View {
        section(title: "Store path", description: "App support directory for this app.") {
            VStack(alignment: .leading, spacing: 8) {
                Text(storePath)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Button("Reveal in Finder", action: revealStore)
                        .buttonStyle(.bordered)
                    Button("Copy path", action: copyStorePath)
                        .buttonStyle(.bordered)
                    Spacer()
                }
            }
        }
    }

    private var resetSection: some View {
        section(title: "Reset all data", description: "Deletes every account, transaction, and edit. Cannot be undone.") {
            HStack {
                Spacer()
                Button("Reset all data") { showResetConfirm = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
    }

    // MARK: - Helpers

    private var storePath: String {
        URL.applicationSupportDirectory.appendingPathComponent("default.store").path
    }

    private func revealStore() {
        NSWorkspace.shared.open(URL.applicationSupportDirectory)
    }

    private func copyStorePath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(storePath, forType: .string)
    }

    private func copyString(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    @ViewBuilder
    private func countCell(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title3.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
                .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.08))
        )
    }
}
#endif
