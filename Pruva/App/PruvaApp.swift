import SwiftUI

@main
struct PruvaApp: App {
    @State private var store = RaceStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Palette.teal)
        }
    }
}
