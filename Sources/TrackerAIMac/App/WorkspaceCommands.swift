import SwiftUI

struct WorkspaceCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Workspace") {
            Section("Open") {
                Button("Open Video") {
                    model.openVideo()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Load Session") {
                    model.loadSession()
                }
                .keyboardShortcut("o")

                Button("Load Workspace") {
                    model.loadWorkspace()
                }
                .keyboardShortcut("o", modifiers: [.command, .option])
            }

            Section("Save") {
                Button("Save Session") {
                    model.saveSession()
                }
                .keyboardShortcut("s")
                .disabled(!model.canSaveSession)

                Button("Save Workspace") {
                    model.saveWorkspace()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!model.canSaveWorkspace)
            }
        }
    }
}
