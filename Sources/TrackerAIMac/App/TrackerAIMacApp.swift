import SwiftUI

@main
struct TrackerAIMacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootShellView(model: model)
                .frame(minWidth: 1380, minHeight: 900)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}
