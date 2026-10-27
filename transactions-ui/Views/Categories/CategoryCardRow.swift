import SwiftUI

/// One category row inside a column card. Modeled on `ReserveCardView`:
/// a leading colored SF-Symbol chip, the display name, and — for roots — a
/// leaf-count badge. Leaf rows are indented to sit under their parent.
struct CategoryCardRow: View {
    let category: Category
    let isRoot: Bool
    let leafCount: Int
    var onSelect: (Category) -> Void = { _ in }

    private var tint: Color { Color(hex: category.color) }

    var body: some View {
        Button {
            onSelect(category)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                symbolChip
                Text(category.displayName)
                    .font(isRoot ? .callout.weight(.bold) : .callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isRoot, leafCount > 0 {
                    Text("\(leafCount)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .leading)
            .contentShape(Rectangle())
            .padding(8)
            .padding(.leading, isRoot ? 0 : 20)
        }
        .buttonStyle(.plain)
        .hoverHighlight(in: .rect(cornerRadius: 12))
    }

    private var symbolChip: some View {
        Image(systemName: category.symbol)
            .font(.callout)
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    VStack(spacing: 4) {
        CategoryCardRow(
            category: Category(id: "cat_food", displayName: "Food", parent: nil,
                               color: "#EB5757", symbol: "fork.knife",
                               transactionType: .expense, patterns: []),
            isRoot: true, leafCount: 2
        )
        CategoryCardRow(
            category: Category(id: "cat_gro", displayName: "Groceries", parent: "cat_food",
                               color: "#EB5757", symbol: "cart.fill",
                               transactionType: .expense, patterns: []),
            isRoot: false, leafCount: 0
        )
    }
    .frame(width: 320)
    .padding(20)
}
