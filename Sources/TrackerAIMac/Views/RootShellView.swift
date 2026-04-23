import SwiftUI

struct RootShellView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: TrackerTheme.Spacing.sm) {
            ShellNavigationRail(model: model)
                .frame(minWidth: 250, idealWidth: 262, maxWidth: 276)

            TrackerPanel(padded: false) {
                VStack(spacing: 0) {
                    TrackerPageHeader(
                        eyebrow: model.selectedPageEyebrow,
                        title: model.selectedPageTitle,
                        summary: model.selectedPageSummary,
                        detail: model.selectedPageContextDetail,
                        statusText: model.shellPrimaryStatusText,
                        statusTone: model.shellPrimaryStatusTone
                    ) {
                        ShellHeaderActions(model: model)
                    }
                    .padding(.horizontal, TrackerTheme.Spacing.lg)
                    .padding(.vertical, TrackerTheme.Spacing.md)

                    Divider()
                        .overlay(TrackerTheme.divider)

                    ScrollView {
                        currentPage
                            .padding(TrackerTheme.Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            .frame(minWidth: 880, maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
        }
        .padding(TrackerTheme.Spacing.sm)
        .background(TrackerTheme.shellGradient.ignoresSafeArea())
    }

    @ViewBuilder
    private var currentPage: some View {
        switch model.selectedTab {
        case .import:
            WorkspaceDeckView(model: model, embeddedInShell: true)
        case .overview:
            OverviewDashboardView(model: model, showsHero: false)
        case .setup:
            SetupWorkspaceView(model: model, showsHeroHeader: false)
        case .review:
            ReviewJournalView(model: model, showsHeader: false)
        case .results:
            ResultsLabView(model: model, showsHeader: false)
        case .help:
            HelpCenterView(model: model, showsHero: false)
        }
    }
}

private struct ShellNavigationRail: View {
    @Bindable var model: AppModel

    private let sessionTabs: [LabTab] = [.import, .overview]
    private let workflowTabs: [LabTab] = [.setup, .review, .results]
    private let referenceTabs: [LabTab] = [.help]

    var body: some View {
        TrackerPanel(padded: false) {
            VStack(alignment: .leading, spacing: 0) {
                railBrandHeader

                Divider()
                    .overlay(TrackerTheme.divider)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: TrackerTheme.Spacing.sm) {
                        railProgressCard

                        railSection(title: "Session", tabs: sessionTabs)
                        railSection(title: "Workflow", tabs: workflowTabs)
                        railSection(title: "Reference", tabs: referenceTabs)
                    }
                    .padding(TrackerTheme.Spacing.sm)
                }

                Spacer(minLength: TrackerTheme.Spacing.sm)

                railFooterCard
                .overlay(alignment: .top) {
                    Divider()
                        .overlay(TrackerTheme.divider)
                }
            }
        }
    }

    private var railBrandHeader: some View {
        VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
            HStack(spacing: TrackerTheme.Spacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(TrackerTheme.heroGradient)
                    Image(systemName: "scope")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tracker AI")
                        .trackerText(.sectionTitle)
                    Text("Motion analysis workspace")
                        .trackerText(.helper, color: TrackerTheme.muted)
                }
            }

            Text("A stable rail keeps import, setup, review, and results anchored to the same active clip.")
                .trackerText(.caption, color: TrackerTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TrackerTheme.Spacing.md)
    }

    private var railProgressCard: some View {
        VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionEyebrow(text: "Workflow")
                Spacer(minLength: 0)
                Text(model.shellActiveWorkflowStepLabel)
                    .trackerText(.helper, color: TrackerTheme.tertiaryText)
            }

            Text(model.shellWorkflowProgressSummary)
                .trackerText(.cardTitle)

            Text(model.activeClipReadinessSummary)
                .trackerText(.caption, color: TrackerTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                StatusPill(text: model.workflowState.title, tone: workflowTone)
                if model.engineState == .running {
                    StatusPill(text: "Analysis Running", style: .processing)
                } else if model.hasActiveAnalysisResults {
                    StatusPill(text: "Results Loaded", style: .complete)
                } else if model.currentVideoURL != nil {
                    StatusPill(text: "Setup Pending", style: .warning)
                } else {
                    StatusPill(text: "Awaiting Import", style: .warning)
                }
            }
        }
        .padding(TrackerTheme.Spacing.sm)
        .background(Color.white.opacity(0.62))
        .overlay(
            RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 4, style: .continuous)
                .strokeBorder(TrackerTheme.panelStroke.opacity(0.68), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 4, style: .continuous))
    }

    private func railSection(title: String, tabs: [LabTab]) -> some View {
        VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
            SectionEyebrow(text: title)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(tabs) { tab in
                    TrackerShellNavigationButton(
                        title: tab.title,
                        symbolName: tab.iconName,
                        stepNumber: tab.railStepNumber,
                        state: model.shellNavigationState(for: tab),
                        statusText: model.shellNavigationStatusText(for: tab),
                        statusTone: model.shellNavigationStatusTone(for: tab),
                        summary: tab.railSummary,
                        accessoryText: model.shellNavigationAccessory(for: tab),
                        isSelected: model.selectedTab == tab,
                        action: { model.selectTab(tab) }
                    )
                    .help(model.shellNavigationDetail(for: tab))
                }
            }
        }
    }

    private var railFooterCard: some View {
        VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionEyebrow(text: "Active Clip")
                Spacer(minLength: 0)
                Text(model.currentVideoURL == nil ? "Idle" : "Live")
                    .trackerText(.helper, color: TrackerTheme.tertiaryText)
            }

            Text(model.shellWorkspaceStatusText)
                .trackerText(.cardTitle)
                .lineLimit(2)

            Text(model.shellWorkspaceDetailText)
                .trackerText(.caption, color: TrackerTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Text(model.shellClipStatusMetadata)
                .trackerText(.helper, color: TrackerTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                StatusPill(text: model.workflowState.title, tone: workflowTone)
                if model.hasActiveAnalysisResults {
                    StatusPill(text: "Trustworthy Results", style: .complete)
                } else if model.currentVideoURL != nil {
                    StatusPill(text: "No Analysis Yet", style: .warning)
                }
            }
        }
        .padding(TrackerTheme.Spacing.md)
        .background(Color.white.opacity(0.44))
    }

    private var workflowTone: Color {
        switch model.workflowState {
        case .import:
            return TrackerTheme.warning
        case .calibrate:
            return TrackerTheme.ready
        case .track:
            return TrackerTheme.processing
        case .review:
            return TrackerTheme.accent
        case .export:
            return TrackerTheme.success
        }
    }
}

private struct ShellHeaderActions: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .trailing, spacing: TrackerTheme.Spacing.xs) {
            HStack(spacing: TrackerTheme.Spacing.xs) {
                Button(model.currentVideoURL == nil ? "Open Video" : "Import Clip") {
                    model.openVideo()
                }
                .buttonStyle(PrimaryActionButtonStyle())

                Menu {
                    Button("Load Session", action: model.loadSession)
                    Button("Load Workspace", action: model.loadWorkspace)
                    Divider()
                    Button("Save Session", action: model.saveSession)
                        .disabled(!model.canSaveSession)
                    Button("Save Workspace", action: model.saveWorkspace)
                        .disabled(!model.canSaveWorkspace)
                } label: {
                    Label("Workspace", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Toggle("Advanced", isOn: $model.advancedMode)
                .toggleStyle(.switch)
                .trackerText(.caption, color: TrackerTheme.muted)
        }
    }
}
