import SwiftUI

@main
struct transactions_uiApp: App {

    @State private var viewModel = AppViewModel(profile: .persisted)

    var body: some Scene {
        WindowGroup {
            DashboardSidebarView()
                .environment(viewModel)
                .preferredColorScheme(.dark)
                #if os(macOS)
                // Pin the content size; `.contentSize` resizability below
                // then locks the window to it so it can't be stretched.
                .frame(width: 900, height: 700)
                #endif
        }
        .defaultSize(width: 900, height: 700)
        #if os(macOS)
        .windowResizability(.contentSize)
        #endif
    }
}
