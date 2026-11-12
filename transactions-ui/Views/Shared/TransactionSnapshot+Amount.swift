import SwiftUI

/// A transaction's amount as the UI shows it: outflows (expense, transfer out)
/// get a "-", inflows none, tinted income / expense / grey for transfers.
/// Shared by `TransactionCard` and the reserve link pickers, so a paycheque
/// and an equal expense never look identical.
extension TransactionSnapshot {
    var signedAmountText: String {
        let formatted = abs(effectiveAmount).formatted(.cad)
        switch effectiveType {
        case .expense, .transfer_out: return "-\(formatted)"
        case .income, .transfer_in:   return formatted
        }
    }

    var amountTint: Color {
        switch effectiveType {
        case .income:                     return .income
        case .expense:                    return .expense
        case .transfer_in, .transfer_out: return .gray
        }
    }
}
