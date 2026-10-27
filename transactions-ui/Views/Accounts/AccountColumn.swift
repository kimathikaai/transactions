import SwiftUI

/// Single source of truth for the Accounts table's column layout. Both the
/// header (`AccountsHeaderRow`) and each data row (`AccountRowView`) apply
/// `.accountColumn(_:)`, so widths and alignments can never drift apart.
enum AccountColumn {
    case type, name, updated, count, balance

    /// Fixed width in points; `nil` = flexible (the Name column expands).
    var width: CGFloat? {
        switch self {
        case .type:    120
        case .name:    nil
        case .updated: 110
        case .count:   100
        case .balance: 110
        }
    }

    var alignment: Alignment {
        switch self {
        case .type, .name:               .leading
        case .updated, .count, .balance: .trailing
        }
    }

    /// Shared row metrics so header and rows share spacing/padding too.
    static let spacing: CGFloat = 12
    static let horizontalPadding: CGFloat = 4
}

extension View {
    /// Applies the shared width + alignment for one Accounts-table column.
    @ViewBuilder
    func accountColumn(_ column: AccountColumn) -> some View {
        if let width = column.width {
            frame(width: width, alignment: column.alignment)
        } else {
            frame(maxWidth: .infinity, alignment: column.alignment)
        }
    }
}
