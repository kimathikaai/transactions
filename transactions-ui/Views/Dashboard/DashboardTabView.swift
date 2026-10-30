import SwiftUI

/// Top-level pages. String raw values so the selection persists via `@AppStorage`.
private enum DashboardTab: String {
    case transactions
    case categories
    case accounts
    case reserves
    #if DEBUG
    case debug
    #endif
}

struct DashboardTabView: View {
    // Remembers the last tab across launches. An unrecognized saved value
    // (e.g. "debug" in a release build) falls back to this default.
    #if DEBUG
    @AppStorage("dashboardTab") private var selection: DashboardTab = .debug
    #else
    @AppStorage("dashboardTab") private var selection: DashboardTab = .accounts
    #endif

    var body: some View {
        TabView(selection: $selection) {
            Tab("Accounts", systemImage: "creditcard", value: DashboardTab.accounts) {
                PageContainer { AccountsPage() }
            }
            Tab("Transactions", systemImage: "list.bullet", value: DashboardTab.transactions) {
                PageContainer { TransactionListView() }
            }
            Tab("Reserves", systemImage: "tray.2", value: DashboardTab.reserves) {
                PageContainer { ReservesPage() }
            }
            Tab("Categories", systemImage: "square.grid.2x2", value: DashboardTab.categories) {
                PageContainer { CategoriesPanelView() }
            }
            #if DEBUG
            Tab("Developer", systemImage: "hammer", value: DashboardTab.debug) {
                PageContainer { DebugPanelView() }
            }
            #endif
        }
        // The selected tab already names the page; drop the window title text.
        .toolbar(removing: .title)
    }
}
