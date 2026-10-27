import SwiftUI

struct AccountDraft {
    var name: String = ""
    var type: AccountType = .chequing
    var initialBalance: Double = 0
}

struct AccountFocusedEditView: View {
    @Binding var draft: AccountDraft
    var commit: (AccountDraft) -> Void
    var cancel: () -> Void
    var uploadCSV: ((AccountDraft) -> Void)? = nil
    var uploadCSVLabel: String = "Upload first CSV (optional)"
    var delete: (() -> Void)? = nil
    /// Transactions belonging to the account being edited (empty for create mode).
    var accountTransactions: [Transaction] = []

    @FocusState private var nameFocused: Bool
    @FocusState private var balanceFocused: Bool
    @Namespace private var typeNamespace

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool { !trimmedName.isEmpty }

    private var transactionsCount: Int {
        accountTransactions.count
    }

    private var transactionsNet: Double {
        accountTransactions.reduce(0) { $0 + $1.effectiveAmount }
    }

    private var resolvedBalance: Double {
        draft.initialBalance + transactionsNet
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            field(caption: "Account name") {
                TextField("e.g. Everyday Chequing", text: $draft.name)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                    .focused($nameFocused)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Type")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .tracking(0.4)

                TypePicker(selection: $draft.type, namespace: typeNamespace)
            }

            field(caption: "Initial balance") {
                TextField(
                    "$0.00",
                    value: Binding(
                        get: { draft.initialBalance == 0 ? nil : draft.initialBalance },
                        set: { draft.initialBalance = $0 ?? 0 }
                    ),
                    format: .cad
                )
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .focused($balanceFocused)
            }

            if let uploadCSV {
                ReconciliationPanel(
                    resolved: resolvedBalance,
                    count: transactionsCount,
                    net: transactionsNet,
                    csvLabel: uploadCSVLabel,
                    csvDisabled: !isValid,
                    onUpload: {
                        var d = draft
                        d.name = trimmedName
                        uploadCSV(d)
                    }
                )
            }

            ActionFooter(
                isValid: isValid,
                onCancel: cancel,
                onSave: {
                    var d = draft
                    d.name = trimmedName
                    commit(d)
                },
                onDelete: delete
            )
        }
        .frame(width: 440)
        .animation(.easeInOut(duration: 0.25), value: draft.type)
        .onAppear { nameFocused = true }
    }

    @ViewBuilder
    private func field<Content: View>(
        caption: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .tracking(0.4)

            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                )
        }
    }
}

private struct TypePicker: View {
    @Binding var selection: AccountType
    let namespace: Namespace.ID

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(AccountType.allCases) { type in
                    TypeOption(
                        type: type,
                        isSelected: selection == type,
                        namespace: namespace,
                        action: { selection = type }
                    )
                }
            }
        }
    }
}

private struct TypeOption: View {
    let type: AccountType
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    private var tint: Color { Color(hex: type.tint) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: type.symbol)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.white : tint)
                Text(type.displayName)
                    .font(.caption2)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected
                ? .regular.tint(tint.opacity(0.7)).interactive()
                : .regular.interactive(),
            in: .rect(cornerRadius: 14)
        )
        .glassEffectID(type.id, in: namespace)
        .accessibilityLabel(type.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ReconciliationPanel: View {
    let resolved: Double
    let count: Int
    let net: Double
    let csvLabel: String
    let csvDisabled: Bool
    let onUpload: () -> Void

    private var resolvedColor: Color {
        if resolved > 0 { return .income }
        if resolved < 0 { return .expense }
        return .primary
    }

    private var netColor: Color {
        if net > 0 { return .income }
        if net < 0 { return .expense }
        return .secondary
    }

    private var formattedResolved: String {
        resolved.formatted(.cad)
    }

    private var formattedNet: String {
        let abs = Swift.abs(net).formatted(.cad)
        if net > 0 { return "+\(abs)" }
        if net < 0 { return "\u{2212}\(abs)" }
        return abs
    }

    private var csvCaption: AttributedString {
        if count == 0 {
            return AttributedString("no transactions yet")
        }
        let label = count == 1 ? "1 transaction" : "\(count) transactions"
        let prefix = AttributedString("Loaded \(label), netting to ")
        var amount = AttributedString(formattedNet)
        amount.foregroundColor = netColor
        return prefix + amount
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(formattedResolved)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(resolvedColor)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())

            Text(csvCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())

            Button(action: onUpload) {
                Label(csvLabel, systemImage: "arrow.up.doc")
                    .font(.callout)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .disabled(csvDisabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
    }
}

private struct ActionFooter: View {
    let isValid: Bool
    let onCancel: () -> Void
    let onSave: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Delete account")
                }

                Spacer(minLength: 0)

                if !isValid {
                    Text("Name required")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                Button("Cancel", action: onCancel)
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)

                Button("Save", action: onSave)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
    }
}

#Preview {
    @Previewable @State var draft: AccountDraft = AccountDraft()
    return AccountFocusedEditView(
        draft: $draft,
        commit: { _ in },
        cancel: { }
    )
    .padding(40)
    .frame(width: 600, height: 520)
}
