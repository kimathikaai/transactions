import Foundation
import SwiftUI

enum AccountType: String, CaseIterable, Identifiable, Codable, Sendable {
    case chequing
    case savings
    case investment
    case debt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chequing:   "Chequing"
        case .savings:    "Savings"
        case .investment: "Investment"
        case .debt:       "Debt"
        }
    }

    var symbol: String {
        switch self {
        case .chequing:   "banknote"
        case .savings:    "building.columns.fill"
        case .investment: "chart.line.uptrend.xyaxis"
        case .debt:       "creditcard.fill"
        }
    }

    var tint: String {
        switch self {
        case .chequing:   "#8dd3c7"
        case .savings:    "#80b1d3"
        case .investment: "#bebada"
        case .debt:       "#fb8072"
        }
    }

    /// Position in declaration order — used for grouping cards by type
    /// (depository → investment → debt), which a raw-string sort
    /// would scramble.
    var sortRank: Int {
        AccountType.allCases.firstIndex(of: self) ?? Int.max
    }
}

/// Value-type account record. Persisted as one element of `accounts.json`.
/// Balance / reservation-derived properties (`netBalance`, `allotted`, `free`,
/// `isReservoirSource`) live in `ReserveComputations.swift` and take
/// transaction / reservation lists as inputs — no relationships on the type
/// itself.
struct Account: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var type: AccountType
    var initialBalance: Double
    var csvFileName: String

    init(
        id: UUID = UUID(),
        name: String,
        type: AccountType,
        initialBalance: Double,
        csvFileName: String
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.initialBalance = initialBalance
        self.csvFileName = csvFileName
    }
}
