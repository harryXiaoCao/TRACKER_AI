# Tracker AI UI/UX Commercialization Roadmap

## Purpose

This document fully replaces the earlier phase notes. It is now the canonical planning document for the next wave of UI, UX, and commercialization work in Tracker AI.

It is grounded in three sources:

1. The current SwiftUI/macOS implementation in `Sources/TrackerAIMac`.
2. The current native app behavior already validated in the rebuilt Release app bundle.
3. The new design-reference image set in `docs/design_references/app_frontend_mockups/`.

Primary reference images:

1. `trackerai-import-workspace-reference.png`
2. `trackerai-setup-reference.png`
3. `trackerai-review-reference.png`
4. `trackerai-results-reference.png`
5. `trackerai-overview-help-reference.png`

These mockups should be treated as the major visual reference for future UI work. They are not pixel-perfect implementation specs, but they do define the target product direction:

1. Stage-first layouts.
2. Lower copy density.
3. Stronger navigation structure.
4. Cleaner panel rhythm.
5. Premium scientific desktop tone.
6. More obvious primary actions.
7. More trustworthy empty, loaded, and post-analysis states.

## Product Direction To Preserve

Tracker AI should feel like:

1. A premium macOS scientific application rather than an internal tool.
2. A trustworthy analysis environment where users can tell what data belongs to the active clip.
3. A guided workflow for first-time users without removing power from advanced users.
4. A publication-oriented product where review, graphs, tables, and export feel credible and deliberate.
5. A commercial app with clear hierarchy, calm spacing, and restrained but confident visual styling.

## Reference Design Principles Distilled From The New Mockups

### 1. Navigation should be structural, not decorative

The mockups consistently use a strong left navigation rail, or a very light top stepper when the page is still import-first. The current app still feels too panel-driven and too dependent on stacked headers, status pills, and dense top content.

### 2. The video or graph stage should dominate the page

In the mockups, the central stage is always the focal point:

1. Import centers the empty video stage.
2. Setup centers the loaded video with overlays.
3. Review centers the video plus timeline workbench.
4. Results centers the graph and trajectory visualizations.

The current app still spends too much vertical space on summaries before the main stage.

### 3. Inspectors should be compact and task-shaped

The mockups use narrow, clearly bounded inspector cards with short labels and light summaries. The current app is improved from earlier phases, but it still contains too many paragraph-level explanations and too many equally weighted sections.

### 4. Copy should support decisions, not narrate the interface

The new mockups use short headings, short metadata rows, and clear CTA labels. The current app still contains too many explanatory sentences, especially in Overview, Setup, Review, Results, and Help.

### 5. Each page should have one obvious job

The reference set gives each page a distinct role:

1. Import: start the workflow.
2. Setup: prepare the clip.
3. Review: resolve quality issues.
4. Results: inspect measurements and export outputs.
5. Overview/Help: orient the user and speed up common entry points.

The current app still blurs these boundaries.

## Current App vs Reference Direction

| Area | Current App State | Target Direction From Mockups | Required Change |
| --- | --- | --- | --- |
| App shell | The shell still relies on a large workspace summary, chip-like workflow cards, and a right inspector that changes by tab. | Persistent left navigation, lighter page headers, and more architectural layout zones. | Rebuild the shell so navigation feels like product chrome instead of stacked content blocks. |
| Import state | The app is truthful and import-first, but the live shell still shows more summary structure than the mockup target. | A quiet, centered, high-confidence empty stage with minimal metadata and one strong CTA. | Reduce pre-load chrome and make the empty workspace feel calmer and more premium. |
| Setup | The setup inspector is more guided than before, but still reads as a long form with too much copy and too many expanded sections. | Large video stage, compact right-side readiness cards, pinned run surface, and simple bottom guidance. | Rebuild Setup into a stage-led workspace with shorter card summaries and stronger action hierarchy. |
| Review | The current Review page is still primarily a stacked inspector experience. | A three-column quality workbench with queue, stage/timeline, and contextual correction sidebar. | Convert Review into a dedicated post-analysis operations surface. |
| Results | The current Results page is useful, but the many subtabs fragment hierarchy and reduce publication polish. | One hero graph area, a short metric strip, a strong quality/export sidebar, and a simpler graph/table mode switch. | Consolidate the information architecture of Results around fewer, stronger surfaces. |
| Overview | Current Overview is clearer than before, but still reads as a set of panels. | Workflow health, quick-start actions, recent sessions, and concise session trust markers. | Turn Overview into an operational launch dashboard instead of a descriptive summary page. |
| Help | Help is improved, but still too textual and too separated from product structure. | Short glossary/help surfaces integrated with workflow language and quick actions. | Reduce Help to concise, skimmable product guidance and glossary content. |
| Visual rhythm | Current panels are more consistent than before, but many sections still share similar visual weight. | More deliberate hierarchy, more whitespace, stronger contrast between hero surfaces and utility surfaces. | Rebalance spacing, component weight, and section density across every page. |

## Non-Negotiable UX Rules For Future Work

1. The active clip, active track, and active workflow step must always be obvious.
2. Empty states must be clearly different from loaded states.
3. Post-analysis pages must never look partially populated when results do not belong to the active clip.
4. Every page must expose one primary next action.
5. Advanced controls must stay available, but they should not dominate default layouts.
6. The app should remain light-mode first, with restrained scientific color usage rather than generic SaaS styling.
7. All major UI changes must be validated in the rebuilt native Release app bundle, not only through `swift run`.

## Execution Order

The work below should be completed in order. Later phases should not begin until the earlier layout and navigation decisions are stable enough to support them.

## Phase 1: Establish The Canonical App Shell

### Goal

Create the durable product shell that future page work will live inside.

### Target Outcome

Tracker AI should open into a shell that immediately feels like a commercial desktop application with a stable navigation pattern, consistent page headers, and less top-heavy density.

### Likely Files

1. `Sources/TrackerAIMac/Views/RootShellView.swift`
2. `Sources/TrackerAIMac/Views/Workspace/WorkspaceDeckView.swift`
3. `Sources/TrackerAIMac/Design/TrackerComponents.swift`
4. `Sources/TrackerAIMac/Design/TrackerTheme.swift`
5. `Sources/TrackerAIMac/Core/AppModel.swift`

### Subtasks

1.1 Replace the current mixed shell with a canonical navigation system.

1.2 Introduce a persistent left navigation rail for `Import`, `Overview`, `Setup`, `Review`, `Results`, and `Help`.

1.3 Define locked, available, active, and complete states for each navigation destination.

1.4 Move page identity into a shared page-header pattern instead of repeating large custom top sections across every panel.

1.5 Reduce toolbar competition by keeping only app-level actions in the macOS toolbar or menu system.

1.6 Create reusable shell components for left rail items, page headers, lock badges, and contextual status indicators.

1.7 Ensure the shell still behaves cleanly at narrower desktop widths without collapsing into unreadable side-by-side blocks.

### Definition Of Done

1. Navigation is visually stable across all pages.
2. The shell reads as product chrome, not a stack of content panels.
3. Users can tell which pages are locked, why they are locked, and what action unlocks them.

## Phase 2: Rebuild The Import-First Experience

### Goal

Make the first-run and clean-relaunch experience match the quiet, trustworthy import-first mockup.

### Target Outcome

When no clip is loaded, the app should feel calm, minimal, and honest. The stage should dominate, the CTA should be obvious, and downstream analysis surfaces should stay visually quiet.

### Likely Files

1. `Sources/TrackerAIMac/Views/Workspace/WorkspaceDeckView.swift`
2. `Sources/TrackerAIMac/Views/Panels/SetupWorkspaceView.swift`
3. `Sources/TrackerAIMac/Views/RootShellView.swift`
4. `Sources/TrackerAIMac/Core/AppModel.swift`

### Subtasks

2.1 Build a dedicated import-first workspace state with a centered empty video stage and a single primary `Open Video` action.

2.2 Reduce non-essential metadata before import so the screen does not feel pre-populated.

2.3 Move clip-less status details into a calm right-side summary card system similar to the import reference image.

2.4 Keep downstream pages visibly locked until a real clip exists, with short unlock guidance rather than long explanations.

2.5 Refine the no-project or no-workspace messaging so it reads as optional session management, not a warning-heavy blocker.

2.6 Audit all clean-launch states to confirm no stale analysis, review, or export language leaks into the import-first view.

### Definition Of Done

1. Clean relaunch opens into a visually quiet import-first state.
2. No loaded-state copy appears before a clip exists.
3. The user can immediately identify the first action without scanning multiple panels.

## Phase 3: Rebuild Setup As A Stage-Led Guided Workspace

### Goal

Move Setup away from a tall form stack and toward a premium, compact, guided preparation surface.

### Target Outcome

Setup should resemble the reference mockup: large video stage, compact readiness cards on the right, short step guidance below, and a pinned `Run Analysis` surface that never feels hidden.

### Likely Files

1. `Sources/TrackerAIMac/Views/Panels/SetupWorkspaceView.swift`
2. `Sources/TrackerAIMac/Views/Workspace/WorkspaceDeckView.swift`
3. `Sources/TrackerAIMac/Design/TrackerComponents.swift`
4. `Sources/TrackerAIMac/Core/AppModel.swift`

### Subtasks

3.1 Elevate the loaded video stage so it becomes the primary visual surface on Setup.

3.2 Convert the current long inspector sections into compact cards for `Experiment`, `Calibration`, `Target`, `Range`, and `Export`.

3.3 Replace paragraph-heavy helper copy with short status rows, edit affordances, and progressive disclosures.

3.4 Pin the `Run Analysis` card high enough that it remains visible and important during normal inspector scrolling.

3.5 Add a simple visual step strip below the stage for `Draw Scale`, `Draw Target`, and `Set Range`.

3.6 Move advanced and destructive controls into quieter secondary areas so they do not compete with required setup work.

3.7 Ensure calibration and target editing are visually tied to the stage overlays, not only to the inspector text.

3.8 Tighten all setup copy so it sounds lab-ready, concise, and user-facing.

### Definition Of Done

1. Setup looks like a guided preparation workspace rather than a form.
2. The run action is always easy to find.
3. A first-time user can identify the three required setup moves in under a few seconds.

## Phase 4: Rebuild Review Into A Dedicated Quality Workbench

### Goal

Turn Review into a true post-analysis workspace instead of a stacked inspector panel.

### Target Outcome

Review should follow the reference structure:

1. Left column for queue and triage.
2. Center column for video, overlays, and timeline.
3. Right column for the selected flagged span, correction tools, event journal, and next action.

### Likely Files

1. `Sources/TrackerAIMac/Views/Panels/ReviewJournalView.swift`
2. `Sources/TrackerAIMac/Views/Workspace/WorkspaceDeckView.swift`
3. `Sources/TrackerAIMac/Design/TrackerComponents.swift`
4. `Sources/TrackerAIMac/Core/AppModel.swift`

### Subtasks

4.1 Replace the current vertical Review stack with a three-column review workbench.

4.2 Build a compact left quality queue with severity markers, counts, filters, and an obvious `Jump To Next` action.

4.3 Expand the center stage to include the video, confidence overlays, timeline lanes, and track visibility controls in one coordinated surface.

4.4 Turn the right column into a contextual issue inspector that shows the selected span, correction tools, event journal, and the next recommended action.

4.5 Make manual correction tools feel like focused review tools rather than generic inspector buttons.

4.6 Consolidate event entry and event history so they support review work instead of acting like a separate form.

4.7 Add a clear empty reviewed-state when the queue is resolved, rather than only showing the absence of rows.

### Definition Of Done

1. Review reads as a quality-control workspace.
2. Queue navigation, correction actions, and issue context are visible without excessive scrolling.
3. The center stage becomes the visual anchor of the page.

## Phase 5: Rebuild Results Around One Hero Story

### Goal

Make Results feel publication-ready and commercially polished by reducing fragmentation and clarifying hierarchy.

### Target Outcome

Results should look like the reference image:

1. A strong header with run status and export affordance.
2. A graph-first hero surface.
3. A concise metric strip.
4. A secondary trajectory or spatial plot.
5. A quality/export sidebar.
6. A simple `Graphs` versus `Table` mode switch.

### Likely Files

1. `Sources/TrackerAIMac/Views/Panels/ResultsLabView.swift`
2. `Sources/TrackerAIMac/Design/TrackerComponents.swift`
3. `Sources/TrackerAIMac/Core/AppModel.swift`

### Subtasks

5.1 Collapse the current many-subtab structure into a smaller primary mode system centered on `Graphs` and `Table`.

5.2 Move classification, insight summaries, and run metadata into a compact header and sidebar structure.

5.3 Build a hero chart region with better typographic hierarchy and a stronger sense of scientific output quality.

5.4 Add a concise metric strip immediately below the hero chart for peak speed, path length, confidence, or similar headline outputs.

5.5 Add a dedicated secondary visualization region for trajectory, top view, pairwise motion, or equivalent follow-on evidence.

5.6 Move quality, visibility, export controls, and reproducibility details into a stable right-side inspector.

5.7 Relegate batch and lower-frequency secondary actions to overflow or secondary sections so they do not compete with export.

5.8 Ensure empty, partial, and loaded results states each feel visually intentional and trustworthy.

### Definition Of Done

1. Results can be understood at a glance.
2. The most important chart and export action are visible immediately.
3. The page feels like a scientific output lab rather than a tab collection.

## Phase 6: Rebuild Overview And Help As Operational Entry Surfaces

### Goal

Make Overview and Help useful, concise, and aligned with the shell rather than acting as text-heavy panel pages.

### Target Outcome

Overview should behave like a launch dashboard. Help should behave like contextual product guidance and glossary support.

### Likely Files

1. `Sources/TrackerAIMac/Views/Panels/OverviewDashboardView.swift`
2. `Sources/TrackerAIMac/Views/Panels/HelpCenterView.swift`
3. `Sources/TrackerAIMac/Design/TrackerComponents.swift`
4. `Sources/TrackerAIMac/Core/AppModel.swift`

### Subtasks

6.1 Rebuild Overview around workflow health, quick-start actions, recent sessions, and concise trust markers.

6.2 Replace panel-heavy readiness sections with a simpler operational summary that points users toward the next relevant page.

6.3 Create a recent sessions or recent work surface with thumbnails, short metadata, and lightweight preview signals.

6.4 Build a compact quick-start strip that links directly into import, setup, review, and results work.

6.5 Recast Help into a short glossary and contextual tips surface instead of a long descriptive page.

6.6 Move build-status or internal-sounding language out of customer-facing Help content unless it directly improves user trust.

6.7 Ensure both pages remain useful when no clip is loaded and when a fully analyzed clip is active.

### Definition Of Done

1. Overview helps users start or resume work quickly.
2. Help is skimmable in seconds.
3. Both pages feel like polished product pages, not documentation panels.

## Phase 7: Standardize The Visual System And Reduce Copy Density

### Goal

Bring every page into the same visual language and eliminate the remaining wordiness that still makes the app feel internal.

### Target Outcome

Tracker AI should have a repeatable, premium, scientific visual rhythm across every page and state.

### Likely Files

1. `Sources/TrackerAIMac/Design/TrackerTheme.swift`
2. `Sources/TrackerAIMac/Design/TrackerComponents.swift`
3. `Sources/TrackerAIMac/Views/Panels/*.swift`
4. `Sources/TrackerAIMac/Views/Workspace/WorkspaceDeckView.swift`
5. `Sources/TrackerAIMac/Core/Domain.swift`
6. `Sources/TrackerAIMac/Core/AppModel.swift`

### Subtasks

7.1 Create a stricter hierarchy for page titles, section headers, metadata rows, and helper text.

7.2 Standardize panel radius, border opacity, spacing cadence, icon scale, and CTA prominence across all pages.

7.3 Replace long descriptive paragraphs with shorter summaries, status rows, and action-oriented labels.

7.4 Introduce reusable components for compact inspector cards, glossary rows, recent-session rows, metric strips, and shell headers.

7.5 Refine semantic color usage so success, warning, lock, and review severity states remain consistent across the product.

7.6 Audit all icons and labels for scientific clarity and premium restraint.

7.7 Keep the premium light-mode lab tone and avoid sliding toward generic dashboard styling.

### Definition Of Done

1. Every page feels like it belongs to the same product family.
2. Users read less to understand more.
3. Primary actions, secondary actions, and passive metadata are clearly differentiated.

## Phase 8: Finish Trust, State, Accessibility, And Release QA

### Goal

Close the remaining commercialization risks by validating every important runtime state in the real native app bundle.

### Target Outcome

The UI should be visually coherent, truthful, accessible, and ready for broader commercial evaluation.

### Likely Files

1. All affected SwiftUI views.
2. `docs/ui_ux_commercialization_task_breakdown.md`
3. Supporting release and QA notes as needed.

### Subtasks

8.1 Perform a full native Release-app QA pass for every major state:

1. Import-first empty state.
2. Loaded but not calibrated.
3. Ready-to-run setup.
4. Running analysis.
5. Post-analysis Review.
6. Post-analysis Results with populated charts and export controls.
7. Resolved review queue.
8. Export-ready state.

8.2 Verify that every page reflects only the active clip and active track after switching clips or loading saved sessions.

8.3 Run a resize audit covering common desktop widths so no inspector or multi-column surface collapses into unreadable layouts.

8.4 Run accessibility and keyboard audits for navigation, contrast, focus, labels, and action discoverability.

8.5 Confirm that customer-facing language contains no stale internal terminology.

8.6 Refresh screenshots and documentation after the redesigned pages land so the docs match the real product.

### Definition Of Done

1. The rebuilt native app bundle passes visual QA in both empty and populated states.
2. No major stale-state or layout-break issues remain.
3. The app is meaningfully closer to App Store-grade commercial polish.

## Recommended Implementation Sequence

1. Finish Phase 1 before doing broad page-specific redesign work.
2. Land Phase 2 and Phase 3 next, because import and setup define the first-run experience.
3. Land Phase 4 and Phase 5 after the shell and setup language are stable.
4. Land Phase 6 and Phase 7 once the core workflow pages establish the new design system.
5. Use Phase 8 as the final closure pass, not as a substitute for earlier design cleanup.

## Success Criteria

This roadmap should be considered successful when the following are true:

1. A new user can open the app and identify the first required action immediately.
2. A returning user can tell whether the active clip is only loaded, fully configured, reviewed, or export-ready.
3. Setup, Review, and Results each have a distinct visual identity and a clear primary job.
4. The app feels less wordy, less panel-heavy, and more premium without losing scientific trust.
5. The Release app bundle, not only development previews, reflects the intended design consistently.
