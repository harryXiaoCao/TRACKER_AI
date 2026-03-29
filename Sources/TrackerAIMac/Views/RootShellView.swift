import SwiftUI

struct RootShellView: View {
    @Bindable var model: AppModel

    var body: some View {
        HSplitView {
            WorkspaceDeckView(model: model)
                .frame(minWidth: 860, idealWidth: 980)

            InspectorPanelView(model: model)
                .frame(minWidth: 520, idealWidth: 620)
        }
        .padding(18)
        .background(TrackerTheme.canvas)
        .toolbar {
            ToolbarItemGroup {
                Button("Open Video", action: openVideo)
                Button("Load Session", action: loadSession)
                Button("Save Session", action: saveSession)
                Button("Load Workspace", action: loadWorkspace)
                Button("Save Workspace", action: saveWorkspace)
            }
        }
    }

    private func openVideo() {
        model.openVideo()
    }

    private func loadSession() {
        model.loadSession()
    }

    private func loadWorkspace() {
        model.loadWorkspace()
    }

    private func saveSession() {
        model.saveSession()
    }

    private func saveWorkspace() {
        model.saveWorkspace()
    }
}

private struct InspectorPanelView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            TrackerPanel {
                HStack(spacing: 10) {
                    ForEach(LabTab.allCases) { tab in
                        NavChipButton(title: tab.title, selected: model.selectedTab == tab) {
                            model.selectedTab = tab
                        }
                    }
                }
            }

            ScrollView {
                VStack(spacing: 16) {
                    switch model.selectedTab {
                    case .overview:
                        OverviewDashboardView(model: model)
                    case .setup:
                        SetupWorkspaceView(model: model)
                    case .review:
                        ReviewJournalView(model: model)
                    case .results:
                        ResultsLabView(model: model)
                    case .help:
                        HelpCenterView(model: model)
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }
}
