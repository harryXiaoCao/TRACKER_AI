import SwiftUI

@MainActor
private final class AppModelStore: ObservableObject {
    let model = AppModel()
}

@main
struct TrackerAIMacApp: App {
    @StateObject private var store = AppModelStore()

    var body: some Scene {
        WindowGroup {
            RootShellView(model: store.model)
                .frame(minWidth: 1240, minHeight: 820)
        }
        .defaultSize(width: 1320, height: 860)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            WorkspaceCommands(model: store.model)
        }
    }
}
