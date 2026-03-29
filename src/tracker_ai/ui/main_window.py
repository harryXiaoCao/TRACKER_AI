from __future__ import annotations

from pathlib import Path
import sys

import numpy as np
from PySide6.QtCore import QObject, QRunnable, Qt, QThreadPool, Signal
from PySide6.QtGui import QAction, QKeySequence
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QComboBox,
    QFrame,
    QFileDialog,
    QFormLayout,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QScrollArea,
    QSlider,
    QSplitter,
    QTabWidget,
    QTableWidget,
    QTableWidgetItem,
    QTextEdit,
    QPlainTextEdit,
    QVBoxLayout,
    QWidget,
)

from ..core.analysis import AnalysisConfig, AnalysisResult, analyze_track, summarize_window
from ..core.calibration import CalibrationProfile
from ..core.experiment import apply_reference_motion_correction, run_experiment_analysis, run_multi_object_experiment
from ..core.export import build_reproduce_command, export_multi_object_bundle, export_result_bundle
from ..core.reporting import build_analysis_summary, build_analyzer_report, build_quality_report
from ..core.session import EventMarker, ExportPreferences, ExperimentMetadata, ProjectSession, ProvenanceMetadata, SessionReviewState
from ..core.tracking import (
    BBox,
    CorrectionAnchor,
    TrackResult,
    TrackedObject,
    TrackingConfig,
    TrackingObservation,
    TrackingProfile,
    merge_track_results,
    run_single_object_tracking,
)
from ..core.video import VideoMetadata, VideoSource
from ..core.workspace import ResearchWorkspace, WorkspaceItem
from .canvas import VideoCanvas
from .research_presets import PRESETS, PRESET_BY_KEY, ResearchPreset

try:
    import pyqtgraph as pg
except ModuleNotFoundError:
    pg = None


class WorkerSignals(QObject):
    finished = Signal(object)
    failed = Signal(str)


class AnalysisWorker(QRunnable):
    def __init__(
        self,
        video_path: str,
        primary_bbox: BBox,
        objects: list[TrackedObject],
        reference_bbox: BBox | None,
        calibration: CalibrationProfile,
        config: AnalysisConfig,
        tracking_config: TrackingConfig,
        *,
        start_frame: int,
        end_frame: int,
        corrected: bool,
    ) -> None:
        super().__init__()
        self.video_path = video_path
        self.primary_bbox = primary_bbox
        self.objects = objects
        self.reference_bbox = reference_bbox
        self.calibration = calibration
        self.config = config
        self.tracking_config = tracking_config
        self.start_frame = start_frame
        self.end_frame = end_frame
        self.corrected = corrected
        self.signals = WorkerSignals()

    def run(self) -> None:
        try:
            with VideoSource(self.video_path) as video:
                if len(self.objects) > 1 and not self.corrected:
                    multi = run_multi_object_experiment(
                        video,
                        self.objects,
                        self.calibration,
                        self.config,
                        self.tracking_config,
                        start_frame=self.start_frame,
                        end_frame=self.end_frame,
                        reference_bbox=self.reference_bbox,
                        corrected=self.corrected,
                        primary_track_id="primary",
                    )
                    payload = {
                        "display_track": multi.display_tracks["primary"],
                        "track_result": multi.analysis_tracks["primary"],
                        "reference_track": multi.reference_track,
                        "analysis": multi.analyses["primary"],
                        "multi_result": multi,
                        "start_frame": self.start_frame,
                        "corrected": self.corrected,
                    }
                else:
                    experiment = run_experiment_analysis(
                        video,
                        primary_bbox=self.primary_bbox,
                        reference_bbox=self.reference_bbox,
                        calibration=self.calibration,
                        analysis_config=self.config,
                        tracking_config=self.tracking_config,
                        start_frame=self.start_frame,
                        end_frame=self.end_frame,
                        corrected=self.corrected,
                    )
                    payload = {
                        "display_track": experiment.display_track,
                        "track_result": experiment.analysis_track,
                        "reference_track": experiment.reference_track,
                        "analysis": experiment.analysis,
                        "multi_result": None,
                        "start_frame": self.start_frame,
                        "corrected": self.corrected,
                    }
            self.signals.finished.emit(payload)
        except Exception as exc:  # pragma: no cover
            self.signals.failed.emit(str(exc))


class GraphPanel(QWidget):
    def __init__(self) -> None:
        super().__init__()
        self._analysis: AnalysisResult | None = None
        self._primary_measure = "x"
        self._secondary_measure = "y"
        layout = QVBoxLayout(self)
        title = QLabel("Kinematics")
        title.setStyleSheet("font-size: 16px; font-weight: 600;")
        layout.addWidget(title)

        if pg is None:
            self._placeholder = QTextEdit()
            self._placeholder.setReadOnly(True)
            self._placeholder.setPlainText("Install pyqtgraph to enable interactive plots.")
            layout.addWidget(self._placeholder)
            self.plot_tabs = None
            return

        nav_panel = QFrame()
        nav_panel.setObjectName("resultsNavPanel")
        nav_panel.setProperty("panel", True)
        nav_layout = QGridLayout(nav_panel)
        nav_layout.setContentsMargins(8, 8, 8, 8)
        nav_layout.setHorizontalSpacing(8)
        nav_layout.setVerticalSpacing(8)
        self.plot_nav_buttons: dict[str, QPushButton] = {}
        for index, (key, label) in enumerate(
            (
                ("compare", "Compare"),
                ("velocity", "Velocity"),
                ("speed", "Speed"),
                ("acceleration", "Acceleration"),
                ("path", "Path"),
                ("phase", "Phase"),
                ("histogram", "Histogram"),
                ("confidence", "Confidence"),
            )
        ):
            button = QPushButton(label)
            button.setProperty("variant", "nav")
            button.clicked.connect(lambda _checked=False, page=key: self._set_plot_page(page))
            nav_layout.addWidget(button, index // 4, index % 4)
            self.plot_nav_buttons[key] = button
        layout.addWidget(nav_panel)

        self.plot_tabs = QTabWidget()
        self.plot_tabs.tabBar().hide()
        self.compare_plot = self._build_plot("Measurement Compare", "Measurement")
        self.velocity_plot = self._build_plot("Velocity", "Velocity")
        self.speed_plot = self._build_plot("Speed", "Speed")
        self.accel_plot = self._build_plot("Acceleration", "Acceleration")
        self.path_plot = self._build_plot("Path", "Y Position")
        self.phase_plot = self._build_plot("Phase Space", "Velocity")
        self.histogram_plot = self._build_plot("Speed Histogram", "Count")
        self.confidence_plot = self._build_plot("Confidence", "Confidence")
        self.plot_tabs.addTab(self.compare_plot, "Compare")
        self.plot_tabs.addTab(self.velocity_plot, "Velocity")
        self.plot_tabs.addTab(self.speed_plot, "Speed")
        self.plot_tabs.addTab(self.accel_plot, "Acceleration")
        self.plot_tabs.addTab(self.path_plot, "Path")
        self.plot_tabs.addTab(self.phase_plot, "Phase")
        self.plot_tabs.addTab(self.histogram_plot, "Histogram")
        self.plot_tabs.addTab(self.confidence_plot, "Confidence")
        self.plot_tabs.currentChanged.connect(lambda _index: self._refresh_plot_nav_states())
        layout.addWidget(self.plot_tabs)
        self._cursor_lines = []
        self._refresh_plot_nav_states()

    def _build_plot(self, title: str, ylabel: str):
        plot = pg.PlotWidget()
        plot.setMinimumHeight(220)
        plot.showGrid(x=True, y=True, alpha=0.22)
        plot.addLegend()
        plot.setTitle(title)
        plot.setLabel("bottom", "Time (s)")
        plot.setLabel("left", ylabel)
        plot.setBackground("w")
        return plot

    def update_analysis(self, analysis: AnalysisResult) -> None:
        if pg is None or self.plot_tabs is None:
            self._placeholder.setPlainText(f"Loaded {len(analysis.time_s)} samples.")
            return

        plots = (
            self.compare_plot,
            self.velocity_plot,
            self.speed_plot,
            self.accel_plot,
            self.path_plot,
            self.phase_plot,
            self.histogram_plot,
            self.confidence_plot,
        )
        self._cursor_lines = []
        for plot in plots:
            if plot.plotItem.legend is not None:
                plot.plotItem.legend.clear()
            plot.clear()
        self._analysis = analysis
        t = analysis.time_s
        self._update_compare_plot()
        self.velocity_plot.plot(t, analysis.x_velocity, pen=pg.mkPen("#DC2626", width=2), name="vx")
        self.velocity_plot.plot(t, analysis.y_velocity, pen=pg.mkPen("#FB923C", width=2), name="vy")
        self.speed_plot.plot(t, analysis.speed, pen=pg.mkPen("#059669", width=2), name="speed")
        self.accel_plot.plot(t, analysis.acceleration_magnitude, pen=pg.mkPen("#111827", width=2), name="|a|")
        self.path_plot.plot(analysis.x_units, analysis.y_units, pen=pg.mkPen("#7C3AED", width=2), name="path")
        self.path_plot.setLabel("bottom", "X Position")
        self.phase_plot.plot(analysis.x_units, analysis.x_velocity, pen=pg.mkPen("#BE123C", width=2), name="x-vx")
        self.phase_plot.plot(analysis.y_units, analysis.y_velocity, pen=pg.mkPen("#0369A1", width=2), name="y-vy")
        self.phase_plot.setLabel("bottom", "Position")
        counts, edges = np.histogram(analysis.speed, bins=min(12, max(4, len(analysis.speed) // 2)))
        centers = (edges[:-1] + edges[1:]) / 2.0
        widths = np.diff(edges)
        self.histogram_plot.setLabel("bottom", "Speed")
        self.histogram_plot.setLabel("left", "Count")
        histogram_item = pg.BarGraphItem(
            x=centers,
            height=counts,
            width=widths * 0.88,
            brush=(22, 163, 74, 120),
            pen=pg.mkPen("#15803D", width=1.5),
        )
        self.histogram_plot.addItem(histogram_item)
        self.confidence_plot.plot(t, analysis.confidence, pen=pg.mkPen("#475569", width=2), name="tracker")
        self.confidence_plot.plot(t, analysis.scientific_confidence, pen=pg.mkPen("#16A34A", width=2), name="scientific")
        for plot in (self.compare_plot, self.velocity_plot, self.speed_plot, self.accel_plot, self.confidence_plot):
            cursor = pg.InfiniteLine(angle=90, movable=False, pen=pg.mkPen("#9CA3AF", width=1, style=Qt.DashLine))
            plot.addItem(cursor)
            self._cursor_lines.append(cursor)

    def set_measurements(self, primary_key: str, secondary_key: str) -> None:
        self._primary_measure = primary_key
        self._secondary_measure = secondary_key
        self._update_compare_plot()

    def _update_compare_plot(self) -> None:
        if pg is None or self._analysis is None:
            return
        plot = self.compare_plot
        if plot.plotItem.legend is not None:
            plot.plotItem.legend.clear()
        plot.clear()
        t = self._analysis.time_s
        series = self._analysis.measurement_series()
        primary = series.get(self._primary_measure)
        secondary = series.get(self._secondary_measure)
        if primary is not None:
            plot.plot(t, primary, pen=pg.mkPen("#1D4ED8", width=2), name=AnalysisResult.measurement_label(self._primary_measure))
        if secondary is not None and self._secondary_measure != self._primary_measure:
            plot.plot(t, secondary, pen=pg.mkPen("#D97706", width=2), name=AnalysisResult.measurement_label(self._secondary_measure))
        raw_map = {"x": "x_raw", "y": "y_raw"}
        raw_key = raw_map.get(self._primary_measure)
        if raw_key is not None and raw_key in series:
            plot.plot(t, series[raw_key], pen=pg.mkPen("#93C5FD", width=1.5, style=Qt.DashLine), name=AnalysisResult.measurement_label(raw_key))
        plot.setTitle(f"{AnalysisResult.measurement_label(self._primary_measure)} vs {AnalysisResult.measurement_label(self._secondary_measure)}")
        plot.setLabel("bottom", "Time (s)")
        plot.setLabel("left", "Measurement")

    def set_frame_cursor(self, timestamp_s: float) -> None:
        if pg is None:
            return
        for line in self._cursor_lines:
            line.setValue(timestamp_s)

    def _set_plot_page(self, page_name: str) -> None:
        index_by_name = {
            "compare": 0,
            "velocity": 1,
            "speed": 2,
            "acceleration": 3,
            "path": 4,
            "phase": 5,
            "histogram": 6,
            "confidence": 7,
        }
        index = index_by_name.get(page_name, 0)
        self.plot_tabs.setCurrentIndex(index)
        self._refresh_plot_nav_states()

    def _refresh_plot_nav_states(self) -> None:
        current = {
            0: "compare",
            1: "velocity",
            2: "speed",
            3: "acceleration",
            4: "path",
            5: "phase",
            6: "histogram",
            7: "confidence",
        }.get(self.plot_tabs.currentIndex() if self.plot_tabs is not None else 0, "compare")
        for key, button in getattr(self, "plot_nav_buttons", {}).items():
            button.setProperty("active", "true" if key == current else "false")
            button.style().unpolish(button)
            button.style().polish(button)


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Tracker AI")
        self.thread_pool = QThreadPool.globalInstance()

        self.video_path: str | None = None
        self.video_metadata: VideoMetadata | None = None
        self.current_frame = None
        self.current_frame_index = 0
        self.selected_start_frame = 0
        self.selected_end_frame: int | None = None
        self.current_bbox: BBox | None = None
        self.reference_bbox: BBox | None = None
        self.pending_correction_bbox: BBox | None = None
        self.scale_points: tuple[float, float, float, float] | None = None
        self.corrections: list[CorrectionAnchor] = []
        self.additional_objects: list[TrackedObject] = []
        self.manual_event_markers: list[EventMarker] = []
        self.awaiting_correction = False
        self.awaiting_reference = False
        self.awaiting_additional_object = False
        self.display_track_result: TrackResult | None = None
        self.reference_track_result: TrackResult | None = None
        self.track_result: TrackResult | None = None
        self.analysis_result: AnalysisResult | None = None
        self.multi_result = None
        self.display_tracks_by_id: dict[str, TrackResult] = {}
        self.analysis_tracks_by_id: dict[str, TrackResult] = {}
        self.analyses_by_id: dict[str, AnalysisResult] = {}
        self.active_track_id = "primary"
        self.debug_tracking = False
        self.advanced_mode = False
        self.dismissed_review_frames: set[int] = set()
        self.selected_window_start: int | None = None
        self.selected_window_end: int | None = None
        self.workspace_items: list[WorkspaceItem] = []
        self.latest_export_bundle: dict[str, object] | None = None
        self.active_preset_key = "general"

        self._build_ui()
        self._build_menu()
        self._apply_theme()
        self._fit_to_screen()
        self._set_advanced_mode(False)
        self._refresh_nav_button_states()
        self._refresh_workflow_summary()

    def _build_ui(self) -> None:
        root = QSplitter(Qt.Horizontal)
        root.addWidget(self._build_video_panel())
        root.addWidget(self._build_right_panel())
        root.setChildrenCollapsible(False)
        root.setStretchFactor(0, 7)
        root.setStretchFactor(1, 5)
        root.setSizes([900, 540])
        self.setCentralWidget(root)

    def _build_menu(self) -> None:
        file_menu = self.menuBar().addMenu("File")
        open_action = QAction("Open Video", self)
        open_action.setShortcut(QKeySequence.Open)
        open_action.triggered.connect(self.open_video)
        file_menu.addAction(open_action)

        load_session_action = QAction("Load Session", self)
        load_session_action.triggered.connect(self.load_session)
        file_menu.addAction(load_session_action)

        open_workspace_action = QAction("Open Workspace", self)
        open_workspace_action.triggered.connect(self.load_workspace)
        file_menu.addAction(open_workspace_action)

        save_workspace_action = QAction("Save Workspace", self)
        save_workspace_action.triggered.connect(self.save_workspace)
        file_menu.addAction(save_workspace_action)

        export_action = QAction("Export Bundle", self)
        export_action.setShortcut(QKeySequence.Save)
        export_action.triggered.connect(self.export_results)
        file_menu.addAction(export_action)

        review_menu = self.menuBar().addMenu("Review")
        next_problem_action = QAction("Next Problem", self)
        next_problem_action.setShortcut(QKeySequence("N"))
        next_problem_action.triggered.connect(self._jump_to_next_problem_frame)
        review_menu.addAction(next_problem_action)

        next_correction_action = QAction("Next Correction", self)
        next_correction_action.setShortcut(QKeySequence("Shift+N"))
        next_correction_action.triggered.connect(self._jump_to_next_correction_frame)
        review_menu.addAction(next_correction_action)

        accept_correction_action = QAction("Draw Correction", self)
        accept_correction_action.setShortcut(QKeySequence("C"))
        accept_correction_action.triggered.connect(self._begin_draw_correction)
        review_menu.addAction(accept_correction_action)

        dismiss_action = QAction("Dismiss Current Review Frame", self)
        dismiss_action.setShortcut(QKeySequence("D"))
        dismiss_action.triggered.connect(self._dismiss_current_review_frame)
        review_menu.addAction(dismiss_action)

    def _apply_theme(self) -> None:
        self.setStyleSheet(
            """
            QMainWindow { background: #F5F1EA; color: #112132; }
            QWidget { font-family: "Avenir Next", "Helvetica Neue", sans-serif; color: #112132; }
            QLabel[role="heading"] { font-size: 16px; font-weight: 700; color: #16324A; }
            QLabel[role="hero"] { font-size: 25px; font-weight: 800; color: #FFF8F0; letter-spacing: 0.35px; }
            QLabel[role="panel"] { font-size: 11px; font-weight: 700; color: #607283; text-transform: uppercase; }
            QLabel[role="subtle"] { color: #395169; font-size: 12px; }
            QLabel[role="metric_value"] { font-size: 18px; font-weight: 700; color: #112132; }
            QLabel[role="metric_label"] { font-size: 10px; color: #607283; text-transform: uppercase; }
            QPushButton {
                background: #193A52; color: #FFF8F0; border: none; border-radius: 12px;
                padding: 9px 13px; font-weight: 600; min-height: 32px;
            }
            QPushButton:hover { background: #285674; }
            QPushButton[variant="ghost"] {
                background: rgba(255,255,255,0.74); color: #17344B; border: 1px solid rgba(24,52,78,0.12);
            }
            QPushButton[variant="ghost"]:hover { background: rgba(231,239,246,0.98); }
            QPushButton[variant="nav"] {
                background: rgba(255,255,255,0.42); color: #607283; border: 1px solid transparent; border-radius: 14px;
                padding: 8px 12px; text-align: left; min-width: 88px;
            }
            QPushButton[variant="nav"][active="true"] {
                background: #193A52; color: #FFF8F0; border: 1px solid rgba(24,52,78,0.18);
            }
            QPushButton[variant="nav"]:hover { background: rgba(225,234,241,0.95); color: #17344B; }
            QLineEdit, QTextEdit, QPlainTextEdit, QTableWidget, QComboBox, QTabWidget::pane, QListWidget {
                background: rgba(255,250,245,0.96);
                border: 1px solid rgba(24,52,78,0.12);
                border-radius: 12px;
                padding: 6px;
                color: #112132;
                selection-background-color: #DDE8F0;
            }
            QTableWidget { gridline-color: rgba(24,52,78,0.06); alternate-background-color: rgba(244,247,250,0.96); }
            QHeaderView::section {
                background: rgba(224,232,239,0.88);
                color: #17344B;
                border: none;
                border-bottom: 1px solid rgba(24,52,78,0.10);
                padding: 7px;
                font-weight: 700;
            }
            QMenuBar { background: rgba(250,246,239,0.92); color: #112132; }
            QMenuBar::item:selected { background: rgba(220,231,240,0.96); }
            QMenu { background: #FFF8F0; color: #112132; border: 1px solid rgba(24,52,78,0.10); }
            QMenu::item:selected { background: rgba(220,231,240,0.96); }
            QFrame[panel="true"] {
                background: rgba(255,248,240,0.88);
                border: 1px solid rgba(24,52,78,0.08);
                border-radius: 18px;
            }
            QFrame#heroPanel {
                background: qlineargradient(x1:0, y1:0, x2:1, y2:1, stop:0 #17344B, stop:0.55 #27506A, stop:1 #A95B34);
                border: 1px solid rgba(24,52,78,0.14);
                border-radius: 22px;
            }
            QFrame#navPanel, QFrame#resultsNavPanel, QFrame#workspacePanel, QFrame#inspectorPanel {
                background: rgba(251,247,241,0.90);
                border: 1px solid rgba(24,52,78,0.10);
                border-radius: 18px;
            }
            QComboBox { min-width: 180px; padding-right: 18px; }
            QComboBox QAbstractItemView {
                background: #FFF8F0;
                color: #112132;
                selection-background-color: #DCE7F0;
                border: 1px solid rgba(24,52,78,0.12);
            }
            QListWidget::item {
                padding: 9px 10px;
                color: #17344B;
            }
            QListWidget::item:selected {
                background: #DCE7F0;
                color: #112132;
            }
            QCheckBox { color: #17344B; spacing: 8px; }
            """
        )

    def _fit_to_screen(self) -> None:
        screen = QApplication.primaryScreen()
        if screen is None:
            self.resize(1360, 860)
            return
        available = screen.availableGeometry()
        width = min(1480, max(1220, int(available.width() * 0.88)))
        height = min(920, max(760, int(available.height() * 0.84)))
        self.resize(width, height)

    def _wrap_scroll(self, widget: QWidget) -> QScrollArea:
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        scroll.setWidget(widget)
        return scroll

    def _dialog_options(self) -> QFileDialog.Option:
        options = QFileDialog.Option(0)
        if sys.platform == "darwin":
            options |= QFileDialog.DontUseNativeDialog
        return options

    def _open_file_dialog(self, title: str, file_filter: str) -> tuple[str, str]:
        return QFileDialog.getOpenFileName(self, title, "", file_filter, options=self._dialog_options())

    def _save_file_dialog(self, title: str, file_filter: str) -> tuple[str, str]:
        return QFileDialog.getSaveFileName(self, title, "", file_filter, options=self._dialog_options())

    def _directory_dialog(self, title: str) -> str:
        return QFileDialog.getExistingDirectory(self, title, "", options=self._dialog_options())

    def _build_video_panel(self) -> QWidget:
        panel = QWidget()
        layout = QVBoxLayout(panel)
        layout.setContentsMargins(8, 8, 8, 8)
        layout.setSpacing(8)

        hero = QFrame()
        hero.setObjectName("heroPanel")
        hero.setProperty("panel", True)
        hero_layout = QVBoxLayout(hero)
        hero_title = QLabel("Tracker AI")
        hero_title.setProperty("role", "hero")
        hero_subtitle = QLabel("Video-first motion analysis for real lab work.")
        hero_subtitle.setProperty("role", "subtle")
        hero_subtitle.setStyleSheet("color: rgba(255, 248, 240, 0.82);")
        hero_actions = QHBoxLayout()
        self.upload_button = QPushButton("Upload Video")
        self.upload_button.clicked.connect(self.open_video)
        self.upload_button.setMinimumWidth(160)
        self.upload_button.setProperty("variant", "primary")
        self.quick_load_button = QPushButton("Load Saved Session")
        self.quick_load_button.clicked.connect(self.load_session)
        self.quick_load_button.setProperty("variant", "ghost")
        self.advanced_mode_toggle = QCheckBox("Advanced Mode")
        self.advanced_mode_toggle.toggled.connect(self._set_advanced_mode)
        self.quick_load_button.setToolTip("Open a saved Tracker AI session to restore your setup, review state, and export settings.")
        self.advanced_mode_toggle.setToolTip("Show deeper review, QC, and export controls for researcher workflows.")
        self.advanced_mode_toggle.setStyleSheet("color: #FFF8F0; font-weight: 600;")
        hero_actions.addWidget(self.upload_button)
        hero_actions.addWidget(self.quick_load_button)
        hero_actions.addWidget(self.advanced_mode_toggle)
        hero_actions.addStretch(1)
        hero_layout.addWidget(hero_title)
        hero_layout.addWidget(hero_subtitle)
        hero_layout.addLayout(hero_actions)
        layout.addWidget(hero)

        context_strip = QHBoxLayout()
        context_strip.setSpacing(8)

        workspace_panel = QFrame()
        workspace_panel.setObjectName("workspacePanel")
        workspace_panel.setProperty("panel", True)
        workspace_layout = QVBoxLayout(workspace_panel)
        workspace_title = QLabel("Workspace")
        workspace_title.setProperty("role", "panel")
        workspace_hint = QLabel("Keep multiple videos in one active workspace and switch without reopening each file.")
        workspace_hint.setWordWrap(True)
        workspace_hint.setProperty("role", "subtle")
        workspace_actions = QHBoxLayout()
        self.workspace_add_button = QPushButton("Add Video")
        self.workspace_add_button.setProperty("variant", "ghost")
        self.workspace_add_button.clicked.connect(self.open_video)
        self.workspace_list = QListWidget()
        self.workspace_list.setMaximumHeight(120)
        self.workspace_list.itemClicked.connect(self._activate_workspace_item)
        workspace_actions.addWidget(self.workspace_add_button)
        workspace_actions.addStretch(1)
        workspace_layout.addWidget(workspace_title)
        workspace_layout.addWidget(workspace_hint)
        workspace_layout.addLayout(workspace_actions)
        workspace_layout.addWidget(self.workspace_list)
        context_strip.addWidget(workspace_panel, 3)

        trial_panel = QFrame()
        trial_panel.setObjectName("heroPanel")
        trial_panel.setProperty("panel", True)
        trial_layout = QVBoxLayout(trial_panel)
        trial_title = QLabel("Current Trial")
        trial_title.setProperty("role", "panel")
        trial_title.setStyleSheet("color: rgba(255, 248, 240, 0.82);")
        self.trial_summary_label = QLabel("No active trial yet.")
        self.trial_summary_label.setWordWrap(True)
        self.trial_summary_label.setStyleSheet("font-size: 22px; font-weight: 800; color: #FFF8F0;")
        self.trial_context_label = QLabel("Load a video or session to see the live experiment summary.")
        self.trial_context_label.setWordWrap(True)
        self.trial_context_label.setStyleSheet("color: rgba(255, 248, 240, 0.84); font-size: 12px;")
        trial_layout.addWidget(trial_title)
        trial_layout.addWidget(self.trial_summary_label)
        trial_layout.addWidget(self.trial_context_label)
        context_strip.addWidget(trial_panel, 2)

        layout.addLayout(context_strip)

        workflow_rail = QFrame()
        workflow_rail.setProperty("panel", True)
        workflow_layout = QHBoxLayout(workflow_rail)
        workflow_layout.setContentsMargins(14, 10, 14, 10)
        self.workflow_steps = {}
        for key, label in (("video", "1 Video"), ("range", "2 Range"), ("scale", "3 Scale"), ("target", "4 Target"), ("analysis", "5 Review")):
            item = QLabel(label)
            item.setProperty("role", "panel")
            workflow_layout.addWidget(item)
            self.workflow_steps[key] = item
        workflow_layout.addStretch(1)
        layout.addWidget(workflow_rail)

        canvas_shell = QFrame()
        canvas_shell.setProperty("panel", True)
        canvas_shell.setObjectName("workspacePanel")
        canvas_shell_layout = QVBoxLayout(canvas_shell)
        canvas_shell_layout.setContentsMargins(18, 18, 18, 18)
        canvas_shell_layout.setSpacing(10)

        self.canvas = VideoCanvas()
        self.canvas.setMinimumWidth(520)
        self.canvas.bbox_drawn.connect(self._on_bbox_drawn)
        self.canvas.scale_drawn.connect(self._on_scale_drawn)
        canvas_controls = QHBoxLayout()
        canvas_controls.setSpacing(8)
        canvas_label = QLabel("Live Video Workspace")
        canvas_label.setProperty("role", "panel")
        self.zoom_in_button = QPushButton("Zoom In")
        self.zoom_in_button.setProperty("variant", "ghost")
        self.zoom_in_button.clicked.connect(self.canvas.zoom_in)
        self.zoom_out_button = QPushButton("Zoom Out")
        self.zoom_out_button.setProperty("variant", "ghost")
        self.zoom_out_button.clicked.connect(self.canvas.zoom_out)
        self.zoom_fit_button = QPushButton("Fit")
        self.zoom_fit_button.setProperty("variant", "ghost")
        self.zoom_fit_button.clicked.connect(self.canvas.fit_to_view)
        zoom_hint = QLabel("Ctrl + wheel to zoom. Drag to pan whenever drawing tools are inactive.")
        zoom_hint.setProperty("role", "subtle")
        canvas_controls.addWidget(canvas_label)
        canvas_controls.addStretch(1)
        canvas_controls.addWidget(self.zoom_out_button)
        canvas_controls.addWidget(self.zoom_in_button)
        canvas_controls.addWidget(self.zoom_fit_button)
        canvas_shell_layout.addLayout(canvas_controls)
        canvas_shell_layout.addWidget(self.canvas, stretch=1)
        canvas_shell_layout.addWidget(zoom_hint)
        layout.addWidget(canvas_shell, stretch=1)

        hud_panel = QFrame()
        hud_panel.setProperty("panel", True)
        hud_layout = QGridLayout(hud_panel)
        self.hud_frame = QLabel("--")
        self.hud_timestamp = QLabel("--")
        self.hud_confidence = QLabel("--")
        self.hud_state = QLabel("--")
        self.hud_bbox = QLabel("--")
        self.hud_reference = QLabel("--")
        self.hud_velocity = QLabel("--")
        self.hud_acceleration = QLabel("--")
        for index, (label, widget) in enumerate(
            (
                ("Frame", self.hud_frame),
                ("Time", self.hud_timestamp),
                ("Confidence", self.hud_confidence),
                ("State", self.hud_state),
                ("BBox", self.hud_bbox),
                ("Reference", self.hud_reference),
                ("Speed", self.hud_velocity),
                ("Accel", self.hud_acceleration),
            )
        ):
            row = index // 4
            column = (index % 4) * 2
            hud_layout.addWidget(QLabel(label), row, column)
            hud_layout.addWidget(widget, row, column + 1)
        action_strip = QFrame()
        action_strip.setObjectName("workspacePanel")
        action_strip.setProperty("panel", True)
        strip_layout = QVBoxLayout(action_strip)
        strip_layout.setContentsMargins(14, 12, 14, 12)
        workspace_label = QLabel("Range + Review Controls")
        workspace_label.setProperty("role", "panel")
        transport_controls = QHBoxLayout()
        range_controls = QHBoxLayout()
        self.prev_button = QPushButton("Prev")
        self.prev_button.setProperty("variant", "ghost")
        self.prev_button.clicked.connect(lambda: self._step_frame(-1))
        self.next_button = QPushButton("Next")
        self.next_button.setProperty("variant", "ghost")
        self.next_button.clicked.connect(lambda: self._step_frame(1))
        self.start_here_button = QPushButton("Use This Frame")
        self.start_here_button.setProperty("variant", "ghost")
        self.start_here_button.clicked.connect(self._set_start_frame_here)
        self.end_here_button = QPushButton("Use As End")
        self.end_here_button.setProperty("variant", "ghost")
        self.end_here_button.clicked.connect(self._set_end_frame_here)
        self.next_problem_button = QPushButton("Next Problem")
        self.next_problem_button.setProperty("variant", "ghost")
        self.next_problem_button.clicked.connect(self._jump_to_next_problem_frame)
        self.window_start_button = QPushButton("Window Start")
        self.window_start_button.setProperty("variant", "ghost")
        self.window_start_button.clicked.connect(self._set_window_start_here)
        self.window_end_button = QPushButton("Window End")
        self.window_end_button.setProperty("variant", "ghost")
        self.window_end_button.clicked.connect(self._set_window_end_here)
        self.window_full_button = QPushButton("Full Window")
        self.window_full_button.setProperty("variant", "ghost")
        self.window_full_button.clicked.connect(self._set_window_full_range)
        transport_controls.addWidget(self.prev_button)
        transport_controls.addWidget(self.next_button)
        transport_controls.addWidget(self.start_here_button)
        transport_controls.addWidget(self.end_here_button)
        transport_controls.addWidget(self.next_problem_button)
        transport_controls.addStretch(1)
        range_controls.addWidget(self.window_start_button)
        range_controls.addWidget(self.window_end_button)
        range_controls.addWidget(self.window_full_button)
        range_controls.addStretch(1)
        strip_layout.addWidget(workspace_label)
        strip_layout.addLayout(transport_controls)
        strip_layout.addLayout(range_controls)
        instrumentation_row = QHBoxLayout()
        instrumentation_row.setSpacing(8)
        instrumentation_row.addWidget(hud_panel, 3)
        instrumentation_row.addWidget(action_strip, 4)
        layout.addLayout(instrumentation_row)

        timeline_panel = QFrame()
        timeline_panel.setProperty("panel", True)
        timeline_panel.setObjectName("workspacePanel")
        timeline_layout = QVBoxLayout(timeline_panel)
        timeline_layout.setContentsMargins(14, 12, 14, 12)
        timeline_title = QLabel("Timeline")
        timeline_title.setProperty("role", "panel")
        self.frame_label = QLabel("Frame: 0 / 0")
        self.frame_label.setProperty("role", "subtle")
        self.selection_label = QLabel("Draw a scale and target to begin.")
        self.selection_label.setProperty("role", "subtle")
        self.status_label = QLabel("No video loaded.")
        self.status_label.setProperty("role", "subtle")
        self.timeline_slider = QSlider(Qt.Horizontal)
        self.timeline_slider.setEnabled(False)
        self.timeline_slider.valueChanged.connect(self._on_timeline_changed)
        self.timeline_summary = QLabel("Timeline markers will appear after analysis.")
        self.timeline_summary.setWordWrap(True)
        self.timeline_summary.setProperty("role", "subtle")
        timeline_layout.addWidget(timeline_title)
        timeline_layout.addWidget(self.frame_label)
        timeline_layout.addWidget(self.selection_label)
        timeline_layout.addWidget(self.status_label)
        timeline_layout.addWidget(self.timeline_slider)
        timeline_layout.addWidget(self.timeline_summary)
        layout.addWidget(timeline_panel)
        return panel

    def _build_right_panel(self) -> QWidget:
        container = QWidget()
        layout = QVBoxLayout(container)
        layout.setContentsMargins(8, 8, 8, 8)
        layout.setSpacing(8)

        nav_panel = QFrame()
        nav_panel.setObjectName("navPanel")
        nav_panel.setProperty("panel", True)
        nav_layout = QHBoxLayout(nav_panel)
        nav_layout.setContentsMargins(10, 10, 10, 10)
        nav_layout.setSpacing(8)
        self.workflow_nav_buttons: dict[str, QPushButton] = {}
        for key, label in (("overview", "Overview"), ("setup", "Setup"), ("review", "Review"), ("results", "Results"), ("help", "Help")):
            button = QPushButton(label)
            button.setProperty("variant", "nav")
            button.clicked.connect(lambda _checked=False, page=key: self._set_workflow_page(page))
            nav_layout.addWidget(button)
            self.workflow_nav_buttons[key] = button
        nav_layout.addStretch(1)
        layout.addWidget(nav_panel)

        self.workflow_pages = QTabWidget()
        self.workflow_pages.setDocumentMode(True)
        self.workflow_pages.tabBar().hide()
        self.workflow_pages.addTab(self._wrap_scroll(self._build_overview_page()), "Overview")
        self.workflow_pages.addTab(self._wrap_scroll(self._build_setup_page()), "Setup")
        self.workflow_pages.addTab(self._wrap_scroll(self._build_review_page()), "Review")
        self.workflow_pages.addTab(self._wrap_scroll(self._build_results_page()), "Results")
        self.workflow_pages.addTab(self._wrap_scroll(self._build_help_page()), "Help")
        self.workflow_pages.currentChanged.connect(lambda _index: self._refresh_nav_button_states())
        layout.addWidget(self.workflow_pages, stretch=1)
        return container

    def _build_overview_page(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(2, 2, 2, 2)
        layout.setSpacing(8)

        mission_panel = QFrame()
        mission_panel.setObjectName("heroPanel")
        mission_panel.setProperty("panel", True)
        mission_layout = QVBoxLayout(mission_panel)
        mission_title = QLabel("Research Mission Control")
        mission_title.setProperty("role", "hero")
        mission_subtitle = QLabel("A Mac-first cockpit for setup, tracking review, annotation, and reproducible exports.")
        mission_subtitle.setProperty("role", "subtle")
        mission_subtitle.setStyleSheet("color: rgba(255, 248, 240, 0.82);")
        mission_layout.addWidget(mission_title)
        mission_layout.addWidget(mission_subtitle)
        self.overview_snapshot = QLabel("Load a video to generate an experiment snapshot.")
        self.overview_snapshot.setWordWrap(True)
        self.overview_snapshot.setProperty("role", "subtle")
        mission_layout.addWidget(self.overview_snapshot)
        quick_actions = QHBoxLayout()
        self.jump_to_setup_button = QPushButton("Prepare Trial")
        self.jump_to_setup_button.setProperty("variant", "ghost")
        self.jump_to_setup_button.clicked.connect(lambda: self._show_workflow_page("setup"))
        self.jump_to_review_button = QPushButton("Review Frames")
        self.jump_to_review_button.setProperty("variant", "ghost")
        self.jump_to_review_button.clicked.connect(lambda: self._show_workflow_page("review"))
        self.jump_to_results_button = QPushButton("Inspect Results")
        self.jump_to_results_button.setProperty("variant", "ghost")
        self.jump_to_results_button.clicked.connect(lambda: self._show_workflow_page("results"))
        quick_actions.addWidget(self.jump_to_setup_button)
        quick_actions.addWidget(self.jump_to_review_button)
        quick_actions.addWidget(self.jump_to_results_button)
        quick_actions.addStretch(1)
        mission_layout.addLayout(quick_actions)
        layout.addWidget(mission_panel)

        preset_panel = QFrame()
        preset_panel.setProperty("panel", True)
        preset_layout = QVBoxLayout(preset_panel)
        preset_title = QLabel("Experiment Presets")
        preset_title.setProperty("role", "panel")
        preset_hint = QLabel("Apply a research-specific starting configuration instead of tuning every control manually.")
        preset_hint.setWordWrap(True)
        preset_hint.setProperty("role", "subtle")
        preset_controls = QHBoxLayout()
        self.preset_selector = QComboBox()
        for preset in PRESETS:
            self.preset_selector.addItem(preset.title, preset.key)
        self.preset_selector.currentIndexChanged.connect(self._refresh_preset_summary)
        self.apply_preset_button = QPushButton("Apply Preset")
        self.apply_preset_button.setProperty("variant", "ghost")
        self.apply_preset_button.clicked.connect(self._apply_selected_preset)
        preset_controls.addWidget(self.preset_selector)
        preset_controls.addWidget(self.apply_preset_button)
        preset_controls.addStretch(1)
        self.preset_summary = QLabel("")
        self.preset_summary.setWordWrap(True)
        self.preset_summary.setProperty("role", "subtle")
        preset_layout.addWidget(preset_title)
        preset_layout.addWidget(preset_hint)
        preset_layout.addLayout(preset_controls)
        preset_layout.addWidget(self.preset_summary)
        layout.addWidget(preset_panel)

        readiness_panel = QFrame()
        readiness_panel.setProperty("panel", True)
        readiness_layout = QVBoxLayout(readiness_panel)
        readiness_title = QLabel("Readiness Board")
        readiness_title.setProperty("role", "panel")
        self.readiness_summary = QTextEdit()
        self.readiness_summary.setReadOnly(True)
        self.readiness_summary.setPlainText("Load a clip to see setup readiness, review priorities, and export guidance.")
        readiness_layout.addWidget(readiness_title)
        readiness_layout.addWidget(self.readiness_summary)
        layout.addWidget(readiness_panel)

        protocol_panel = QFrame()
        protocol_panel.setProperty("panel", True)
        protocol_layout = QVBoxLayout(protocol_panel)
        protocol_title = QLabel("Protocol Notes")
        protocol_title.setProperty("role", "panel")
        self.protocol_notes = QTextEdit()
        self.protocol_notes.setReadOnly(True)
        self.protocol_notes.setPlainText("Protocol hints, reproducibility notes, and export recommendations will appear here.")
        protocol_layout.addWidget(protocol_title)
        protocol_layout.addWidget(self.protocol_notes)
        layout.addWidget(protocol_panel, stretch=1)

        self._refresh_preset_summary()
        return page

    def _build_setup_page(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(2, 2, 2, 2)
        layout.setSpacing(8)

        instruction_panel = QFrame()
        instruction_panel.setProperty("panel", True)
        instruction_layout = QVBoxLayout(instruction_panel)
        instruction_title = QLabel("Workflow")
        instruction_title.setProperty("role", "panel")
        self.workflow_summary = QLabel(
            "Open a video, set the frame range, draw the scale and target, optionally add a reference marker, then run analysis and review suspect frames."
        )
        self.workflow_summary.setWordWrap(True)
        self.workflow_summary.setProperty("role", "subtle")
        instruction_layout.addWidget(instruction_title)
        instruction_layout.addWidget(self.workflow_summary)
        layout.addWidget(instruction_panel)

        setup_panel = QFrame()
        setup_panel.setProperty("panel", True)
        setup_layout = QVBoxLayout(setup_panel)
        setup_title = QLabel("Experiment Setup")
        setup_title.setProperty("role", "panel")
        setup_layout.addWidget(setup_title)

        metadata_form = QFormLayout()
        self.experiment_label_input = QLineEdit()
        self.trial_id_input = QLineEdit()
        self.operator_input = QLineEdit()
        self.tags_input = QLineEdit()
        self.notes_input = QLineEdit()
        metadata_form.addRow("Experiment", self.experiment_label_input)
        metadata_form.addRow("Trial ID", self.trial_id_input)
        metadata_form.addRow("Operator", self.operator_input)
        metadata_form.addRow("Tags", self.tags_input)
        metadata_form.addRow("Notes", self.notes_input)
        setup_layout.addLayout(metadata_form)

        form = QFormLayout()
        self.reference_length_input = QLineEdit("1.0")
        self.unit_input = QLineEdit("m")
        self.window_input = QLineEdit("7")
        self.polyorder_input = QLineEdit("2")
        self.reference_length_input.setToolTip("Real-world length of the calibration stick or known distance.")
        self.unit_input.setToolTip("Unit label used in exports, such as m, cm, or mm.")
        self.window_input.setToolTip("Odd number of frames used for smoothing. Larger windows reduce jitter but can blur fast events.")
        self.polyorder_input.setToolTip("Curve flexibility inside the smoothing window. Keep it low unless motion is dense and smooth.")
        self.profile_input = QComboBox()
        for profile in TrackingProfile:
            self.profile_input.addItem(profile.value.title(), profile.value)
        self.profile_input.setToolTip("Auto chooses marker mode when the object has a strong visual marker.")
        self.profile_input.setMinimumContentsLength(14)
        self.profile_input.setSizeAdjustPolicy(QComboBox.AdjustToContents)
        self.robust_recovery_input = QCheckBox("Robust recovery")
        self.robust_recovery_input.setChecked(True)
        self.robust_recovery_input.setToolTip("Use wider search and recovery passes when confidence drops.")
        self.bidirectional_input = QCheckBox("Bidirectional refine")
        self.bidirectional_input.setChecked(True)
        self.bidirectional_input.setToolTip("Run a backward refinement pass for better offline accuracy.")
        self.debug_tracking_input = QCheckBox("Debug tracking export")
        self.debug_tracking_input.setToolTip("Include per-frame candidate scores in exports and QC bundles.")
        self.include_overlay_input = QCheckBox("Export overlay video")
        self.include_overlay_input.setChecked(True)
        self.include_plots_input = QCheckBox("Export plot images")
        self.include_plots_input.setChecked(True)
        self.report_template_input = QComboBox()
        self.report_template_input.addItem("Research", "research")
        self.report_template_input.addItem("Guided Lab", "guided")
        self.report_template_input.addItem("Compact", "compact")
        self.report_template_input.setToolTip("Choose the exported report style: detailed research notes, guided lab notes, or a concise compact summary.")
        self.report_template_input.setMinimumContentsLength(14)
        self.report_template_input.setSizeAdjustPolicy(QComboBox.AdjustToContents)
        form.addRow("Reference length", self.reference_length_input)
        form.addRow("Unit", self.unit_input)
        form.addRow("Smooth window", self.window_input)
        form.addRow("Smooth polyorder", self.polyorder_input)
        form.addRow("Tracking profile", self.profile_input)
        form.addRow("Report template", self.report_template_input)
        form.addRow("", self.robust_recovery_input)
        form.addRow("", self.bidirectional_input)
        form.addRow("", self.debug_tracking_input)
        form.addRow("", self.include_overlay_input)
        form.addRow("", self.include_plots_input)
        setup_layout.addLayout(form)

        self.setup_help = QLabel(
            "Use a smaller `Smooth window` for short impacts or fast launches. Increase it only when the path jitters frame to frame. `Smooth polyorder` controls how curved the smoothing fit can be; `2` is the safest general setting."
        )
        self.setup_help.setWordWrap(True)
        self.setup_help.setProperty("role", "subtle")
        setup_layout.addWidget(self.setup_help)

        object_panel = QFrame()
        object_panel.setProperty("panel", True)
        object_layout = QVBoxLayout(object_panel)
        object_title = QLabel("Additional Objects")
        object_title.setProperty("role", "panel")
        object_hint = QLabel("Optional: add extra tracked objects for pairwise distance, relative velocity, and collision-style analysis.")
        object_hint.setWordWrap(True)
        object_hint.setProperty("role", "subtle")
        object_form = QFormLayout()
        self.object_name_input = QLineEdit("Secondary Object")
        self.object_kind_input = QComboBox()
        self.object_kind_input.addItem("Secondary", "secondary")
        self.object_kind_input.addItem("Launcher", "launcher")
        self.object_kind_input.addItem("Pivot", "pivot")
        self.object_kind_input.addItem("Marker", "marker")
        object_form.addRow("Object name", self.object_name_input)
        object_form.addRow("Object kind", self.object_kind_input)
        object_actions = QHBoxLayout()
        self.add_object_button = QPushButton("Add Object")
        self.add_object_button.setProperty("variant", "ghost")
        self.add_object_button.clicked.connect(self._begin_additional_object)
        self.clear_objects_button = QPushButton("Clear Objects")
        self.clear_objects_button.setProperty("variant", "ghost")
        self.clear_objects_button.clicked.connect(self._clear_additional_objects)
        object_actions.addWidget(self.add_object_button)
        object_actions.addWidget(self.clear_objects_button)
        self.object_list = QListWidget()
        object_layout.addWidget(object_title)
        object_layout.addWidget(object_hint)
        object_layout.addLayout(object_form)
        object_layout.addLayout(object_actions)
        object_layout.addWidget(self.object_list)
        setup_layout.addWidget(object_panel)

        calibration_panel = QFrame()
        calibration_panel.setObjectName("inspectorPanel")
        calibration_panel.setProperty("panel", True)
        calibration_layout = QVBoxLayout(calibration_panel)
        calibration_title = QLabel("Calibration Controls")
        calibration_title.setProperty("role", "panel")
        calibration_hint = QLabel("Use a simple line for fast work, or switch to an axis-aware calibration when you need a lab coordinate frame.")
        calibration_hint.setWordWrap(True)
        calibration_hint.setProperty("role", "subtle")
        calibration_form = QFormLayout()
        self.calibration_mode_input = QComboBox()
        self.calibration_mode_input.addItem("Single line", "single_line")
        self.calibration_mode_input.addItem("Axis aligned", "two_axis")
        self.calibration_mode_input.addItem("Marker size", "marker_size")
        self.calibration_mode_input.addItem("Homography preset", "homography")
        self.origin_x_input = QLineEdit("0")
        self.origin_y_input = QLineEdit("0")
        self.axis_angle_input = QLineEdit("0")
        self.marker_size_input = QLineEdit("20")
        self.calibration_preset_input = QLineEdit("")
        self.homography_input = QLineEdit("")
        self.invert_x_input = QCheckBox("Invert X axis")
        self.invert_y_input = QCheckBox("Invert Y axis")
        calibration_form.addRow("Mode", self.calibration_mode_input)
        calibration_form.addRow("Origin X", self.origin_x_input)
        calibration_form.addRow("Origin Y", self.origin_y_input)
        calibration_form.addRow("Axis angle", self.axis_angle_input)
        calibration_form.addRow("Marker size px", self.marker_size_input)
        calibration_form.addRow("Preset name", self.calibration_preset_input)
        calibration_form.addRow("Homography (9 vals)", self.homography_input)
        calibration_form.addRow("", self.invert_x_input)
        calibration_form.addRow("", self.invert_y_input)
        calibration_layout.addWidget(calibration_title)
        calibration_layout.addWidget(calibration_hint)
        calibration_layout.addLayout(calibration_form)
        setup_layout.addWidget(calibration_panel)

        tool_row = QHBoxLayout()
        self.draw_scale_button = QPushButton("Draw Scale")
        self.draw_scale_button.setProperty("variant", "ghost")
        self.draw_scale_button.clicked.connect(self._begin_draw_scale)
        self.draw_target_button = QPushButton("Draw Target")
        self.draw_target_button.setProperty("variant", "ghost")
        self.draw_target_button.clicked.connect(self._begin_draw_target)
        self.draw_reference_button = QPushButton("Draw Reference")
        self.draw_reference_button.setProperty("variant", "ghost")
        self.draw_reference_button.clicked.connect(self._begin_draw_reference)
        tool_row.addWidget(self.draw_scale_button)
        tool_row.addWidget(self.draw_target_button)
        tool_row.addWidget(self.draw_reference_button)
        setup_layout.addLayout(tool_row)

        action_row = QHBoxLayout()
        self.analyze_button = QPushButton("Run Analysis")
        self.analyze_button.clicked.connect(self.run_analysis)
        self.export_button = QPushButton("Export Bundle")
        self.export_button.setProperty("variant", "ghost")
        self.export_button.clicked.connect(self.export_results)
        action_row.addWidget(self.analyze_button)
        action_row.addWidget(self.export_button)
        setup_layout.addLayout(action_row)
        layout.addWidget(setup_panel)
        layout.addStretch(1)
        return page

    def _build_review_page(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(2, 2, 2, 2)
        layout.setSpacing(8)

        review_panel = QFrame()
        review_panel.setProperty("panel", True)
        review_layout = QVBoxLayout(review_panel)
        review_title = QLabel("Review And Fix")
        review_title.setProperty("role", "panel")
        self.review_guidance = QLabel(
            "Use `Next Problem` under the video to jump between suspect frames. If the box drifts, redraw it on that frame and click `Apply Correction`."
        )
        self.review_guidance.setWordWrap(True)
        self.review_guidance.setProperty("role", "subtle")
        self.draw_correction_button = QPushButton("Draw Correction")
        self.draw_correction_button.setProperty("variant", "ghost")
        self.draw_correction_button.clicked.connect(self._begin_draw_correction)
        self.apply_correction_button = QPushButton("Apply Correction")
        self.apply_correction_button.setProperty("variant", "ghost")
        self.apply_correction_button.clicked.connect(self.apply_correction)
        review_layout.addWidget(review_title)
        review_layout.addWidget(self.review_guidance)
        review_layout.addWidget(self.draw_correction_button)
        review_layout.addWidget(self.apply_correction_button)
        layout.addWidget(review_panel)

        queue_panel = QFrame()
        queue_panel.setProperty("panel", True)
        queue_layout = QVBoxLayout(queue_panel)
        queue_title = QLabel("Review Queue")
        queue_title.setProperty("role", "panel")
        self.review_queue = QListWidget()
        self.review_queue.itemClicked.connect(self._jump_from_review_queue)
        queue_layout.addWidget(queue_title)
        queue_layout.addWidget(self.review_queue)
        layout.addWidget(queue_panel)

        event_panel = QFrame()
        event_panel.setProperty("panel", True)
        event_layout = QVBoxLayout(event_panel)
        event_title = QLabel("Manual Event Journal")
        event_title.setProperty("role", "panel")
        event_hint = QLabel("Mark release, impact, trigger, or other researcher-defined moments at the current frame.")
        event_hint.setWordWrap(True)
        event_hint.setProperty("role", "subtle")
        event_form = QFormLayout()
        self.manual_event_name_input = QLineEdit("release")
        self.manual_event_note_input = QLineEdit("")
        self.manual_event_value_input = QLineEdit("")
        self.manual_event_unit_input = QLineEdit("")
        event_form.addRow("Event", self.manual_event_name_input)
        event_form.addRow("Note", self.manual_event_note_input)
        event_form.addRow("Value", self.manual_event_value_input)
        event_form.addRow("Unit", self.manual_event_unit_input)
        event_actions = QHBoxLayout()
        self.add_event_marker_button = QPushButton("Mark Current Frame")
        self.add_event_marker_button.setProperty("variant", "ghost")
        self.add_event_marker_button.clicked.connect(self._add_manual_event_marker)
        self.remove_event_marker_button = QPushButton("Remove Selected")
        self.remove_event_marker_button.setProperty("variant", "ghost")
        self.remove_event_marker_button.clicked.connect(self._remove_selected_manual_event_marker)
        event_actions.addWidget(self.add_event_marker_button)
        event_actions.addWidget(self.remove_event_marker_button)
        self.manual_events_list = QListWidget()
        event_layout.addWidget(event_title)
        event_layout.addWidget(event_hint)
        event_layout.addLayout(event_form)
        event_layout.addLayout(event_actions)
        event_layout.addWidget(self.manual_events_list)
        layout.addWidget(event_panel)

        metrics_panel = QFrame()
        metrics_panel.setProperty("panel", True)
        metrics_layout = QVBoxLayout(metrics_panel)
        metrics_title = QLabel("Key Metrics")
        metrics_title.setProperty("role", "panel")
        metrics_layout.addWidget(metrics_title)
        metrics_grid = QGridLayout()
        self.metric_avg_conf = self._make_metric_widget(metrics_grid, 0, 0, "Avg confidence", "--")
        self.metric_peak_speed = self._make_metric_widget(metrics_grid, 0, 1, "Peak speed", "--")
        self.metric_peak_accel = self._make_metric_widget(metrics_grid, 1, 0, "Peak accel", "--")
        self.metric_path = self._make_metric_widget(metrics_grid, 1, 1, "Path length", "--")
        metrics_layout.addLayout(metrics_grid)
        layout.addWidget(metrics_panel)

        self.state_summary = QTextEdit()
        self.state_summary.setReadOnly(True)
        self.state_summary.setPlainText("Tracker state will appear here.")
        layout.addWidget(self.state_summary, stretch=1)
        return page

    def _build_results_page(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(2, 2, 2, 2)
        layout.setSpacing(8)

        results_note = QFrame()
        results_note.setProperty("panel", True)
        note_layout = QVBoxLayout(results_note)
        note_title = QLabel("Results")
        note_title.setProperty("role", "panel")
        note_body = QLabel("Move between insights, graphs, events, QC, and reproducibility without losing the active track context.")
        note_body.setWordWrap(True)
        note_body.setProperty("role", "subtle")
        self.results_track_selector = QComboBox()
        self.results_track_selector.currentIndexChanged.connect(self._on_active_track_changed)
        self.results_pair_selector = QComboBox()
        self.results_pair_selector.currentIndexChanged.connect(self._refresh_pairwise_summary)
        self.graph_primary_selector = QComboBox()
        self.graph_secondary_selector = QComboBox()
        self.table_column_selector = QComboBox()
        measurement_options = (
            ("X Position", "x"),
            ("Y Position", "y"),
            ("Raw X Position", "x_raw"),
            ("Raw Y Position", "y_raw"),
            ("Vx", "vx"),
            ("Vy", "vy"),
            ("|v|", "speed"),
            ("Ax", "ax"),
            ("Ay", "ay"),
            ("|a|", "acceleration_magnitude"),
            ("Angle", "angle_deg"),
            ("Tracker Confidence", "tracker_confidence"),
            ("Scientific Confidence", "scientific_confidence"),
            ("Position Uncertainty", "position_uncertainty"),
            ("Velocity Uncertainty", "velocity_uncertainty"),
            ("Acceleration Uncertainty", "acceleration_uncertainty"),
        )
        for label, value in measurement_options:
            self.graph_primary_selector.addItem(label, value)
            self.graph_secondary_selector.addItem(label, value)
        self.graph_primary_selector.setCurrentIndex(self.graph_primary_selector.findData("x"))
        self.graph_secondary_selector.setCurrentIndex(self.graph_secondary_selector.findData("y"))
        self.graph_primary_selector.currentIndexChanged.connect(self._refresh_measurement_views)
        self.graph_secondary_selector.currentIndexChanged.connect(self._refresh_measurement_views)
        self.table_column_selector.addItem("Core Table", "core")
        self.table_column_selector.addItem("Velocity Focus", "velocity")
        self.table_column_selector.addItem("Acceleration Focus", "acceleration")
        self.table_column_selector.addItem("Confidence + QC", "confidence")
        self.table_column_selector.addItem("All Variables", "all")
        self.table_column_selector.currentIndexChanged.connect(self._populate_table)
        selector_grid = QGridLayout()
        selector_grid.addWidget(QLabel("Track"), 0, 0)
        selector_grid.addWidget(self.results_track_selector, 0, 1)
        selector_grid.addWidget(QLabel("Pair"), 0, 2)
        selector_grid.addWidget(self.results_pair_selector, 0, 3)
        selector_grid.addWidget(QLabel("Compare"), 1, 0)
        selector_grid.addWidget(self.graph_primary_selector, 1, 1)
        selector_grid.addWidget(QLabel("Against"), 1, 2)
        selector_grid.addWidget(self.graph_secondary_selector, 1, 3)
        selector_grid.addWidget(QLabel("Table"), 2, 0)
        selector_grid.addWidget(self.table_column_selector, 2, 1)
        note_layout.addWidget(note_title)
        note_layout.addWidget(note_body)
        note_layout.addLayout(selector_grid)
        layout.addWidget(results_note)

        results_nav = QFrame()
        results_nav.setObjectName("resultsNavPanel")
        results_nav.setProperty("panel", True)
        results_nav_layout = QGridLayout(results_nav)
        results_nav_layout.setContentsMargins(10, 10, 10, 10)
        results_nav_layout.setHorizontalSpacing(8)
        results_nav_layout.setVerticalSpacing(8)
        self.results_nav_buttons: dict[str, QPushButton] = {}
        for index, (key, label) in enumerate(
            (
                ("insights", "Insights"),
                ("graphs", "Graphs"),
                ("window", "Window Stats"),
                ("events", "Events"),
                ("quality", "Quality"),
                ("pairwise", "Pairwise"),
                ("table", "Table"),
                ("reproduce", "Reproduce"),
            )
        ):
            button = QPushButton(label)
            button.setProperty("variant", "nav")
            button.clicked.connect(lambda _checked=False, page=key: self._set_results_page(page))
            results_nav_layout.addWidget(button, index // 4, index % 4)
            self.results_nav_buttons[key] = button
        layout.addWidget(results_nav)

        self.results_tabs = QTabWidget()
        self.results_tabs.setDocumentMode(True)
        self.results_tabs.tabBar().hide()
        self.insights_summary = QTextEdit()
        self.insights_summary.setReadOnly(True)
        self.insights_summary.setPlainText("Analysis insights will appear after you run a trial.")
        self.results_tabs.addTab(self.insights_summary, "Insights")

        self.graph_panel = GraphPanel()
        self.results_tabs.addTab(self.graph_panel, "Graphs")

        self.window_summary = QTextEdit()
        self.window_summary.setReadOnly(True)
        self.window_summary.setPlainText("Window statistics will appear after analysis.")
        self.results_tabs.addTab(self.window_summary, "Window Stats")

        self.events_table = QTableWidget(0, 7)
        self.events_table.setHorizontalHeaderLabels(["event", "origin", "frame", "time", "value", "unit", "note"])
        self.events_table.setAlternatingRowColors(True)
        self.events_table.verticalHeader().setVisible(False)
        self.events_table.horizontalHeader().setStretchLastSection(True)
        self.results_tabs.addTab(self.events_table, "Events")

        self.quality_summary = QTextEdit()
        self.quality_summary.setReadOnly(True)
        self.quality_summary.setPlainText("Quality report will appear after analysis.")
        self.results_tabs.addTab(self.quality_summary, "Quality")

        self.pairwise_summary = QTextEdit()
        self.pairwise_summary.setReadOnly(True)
        self.pairwise_summary.setPlainText("Pairwise metrics will appear when multiple objects are tracked.")
        self.results_tabs.addTab(self.pairwise_summary, "Pairwise")

        self.table = QTableWidget(0, 12)
        self.table.setHorizontalHeaderLabels(["frame", "t", "x", "y", "vx", "vy", "speed", "|a|", "conf", "state", "reason", "flags"])
        self.table.setAlternatingRowColors(True)
        self.table.verticalHeader().setVisible(False)
        self.table.horizontalHeader().setStretchLastSection(True)
        self.results_tabs.addTab(self.table, "Table")

        reproduce_panel = QWidget()
        reproduce_layout = QVBoxLayout(reproduce_panel)
        reproduce_layout.setContentsMargins(0, 0, 0, 0)
        reproduce_layout.setSpacing(8)
        self.reproduce_summary = QTextEdit()
        self.reproduce_summary.setReadOnly(True)
        self.reproduce_summary.setPlainText("Reproducibility notes will appear after analysis.")
        self.reproduce_command = QPlainTextEdit()
        self.reproduce_command.setReadOnly(True)
        self.reproduce_command.setPlainText("tracker-ai analyze ...")
        reproduce_layout.addWidget(self.reproduce_summary)
        reproduce_layout.addWidget(self.reproduce_command)
        self.results_tabs.addTab(reproduce_panel, "Reproduce")
        self.results_tabs.currentChanged.connect(lambda _index: self._refresh_nav_button_states())
        layout.addWidget(self.results_tabs, stretch=1)
        return page

    def _build_help_page(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(2, 2, 2, 2)
        layout.setSpacing(8)

        intro_panel = QFrame()
        intro_panel.setProperty("panel", True)
        intro_layout = QVBoxLayout(intro_panel)
        intro_title = QLabel("How To Use Tracker AI")
        intro_title.setProperty("role", "panel")
        intro_body = QLabel(
            "Tracker AI works best when you move in order: open a video, define the analysis range, draw a scale, draw the target, run analysis, then review suspect frames before exporting."
        )
        intro_body.setWordWrap(True)
        intro_body.setProperty("role", "subtle")
        intro_layout.addWidget(intro_title)
        intro_layout.addWidget(intro_body)
        layout.addWidget(intro_panel)

        help_text = QPlainTextEdit()
        help_text.setReadOnly(True)
        help_text.setPlainText(
            "Quick Start\n"
            "1. Overview: pick a research preset so Tracker AI starts with sensible smoothing and reporting defaults.\n"
            "2. Upload Video: open a new clip from disk or switch clips from the workspace rail.\n"
            "3. Use This Frame / Use As End: choose the frame range you want to analyze.\n"
            "4. Draw Scale: drag along a known real-world distance.\n"
            "5. Draw Target: drag a box around the moving object.\n"
            "6. Draw Reference: optional; use this when the apparatus or camera may move.\n"
            "7. Run Analysis: track the object and compute motion variables.\n"
            "8. Review: jump through suspect or lost frames, redraw corrections when needed, and mark manual events such as release or impact.\n"
            "9. Results: inspect insights, graphs, QC, pairwise data, and the reproduce command before export.\n"
            "10. Export Bundle: save reports, tables, plots, QC outputs, the session, and the manifest for reproducibility.\n\n"
            "What Advanced Mode Adds\n"
            "- deeper QC and confidence views\n"
            "- event review and richer export options\n"
            "- selected-window statistics for focused measurements\n"
            "- debug-oriented settings for researcher workflows\n\n"
            "When To Load A Saved Session\n"
            "- when you want to continue reviewing a previous run\n"
            "- when you want to compare export settings without redrawing boxes\n"
            "- when you want a reproducible record of how a result was created"
        )
        layout.addWidget(help_text, stretch=1)
        return page

    def _make_metric_widget(self, grid: QGridLayout, row: int, column: int, label: str, value: str) -> QLabel:
        wrapper = QVBoxLayout()
        value_label = QLabel(value)
        value_label.setProperty("role", "metric_value")
        label_label = QLabel(label)
        label_label.setProperty("role", "metric_label")
        frame = QFrame()
        frame.setProperty("panel", True)
        frame_layout = QVBoxLayout(frame)
        frame_layout.setContentsMargins(12, 12, 12, 12)
        frame_layout.addWidget(value_label)
        frame_layout.addWidget(label_label)
        grid.addWidget(frame, row, column)
        return value_label

    def _selected_preset(self) -> ResearchPreset:
        preset_key = self.preset_selector.currentData() if hasattr(self, "preset_selector") else self.active_preset_key
        return PRESET_BY_KEY.get(str(preset_key or self.active_preset_key), PRESET_BY_KEY["general"])

    def _refresh_preset_summary(self, _index: int = 0) -> None:
        preset = self._selected_preset()
        self.active_preset_key = preset.key
        if hasattr(self, "preset_summary"):
            self.preset_summary.setText(
                f"{preset.description}\nRecommended profile: {preset.tracking_profile} | "
                f"Smooth window: {preset.smoothing_window} | Polyorder: {preset.polyorder}\n"
                f"Review focus: {preset.review_focus}\n"
                f"Tip: {preset.setup_tip}"
            )

    def _apply_selected_preset(self) -> None:
        preset = self._selected_preset()
        self.window_input.setText(str(preset.smoothing_window))
        self.polyorder_input.setText(str(preset.polyorder))
        profile_index = self.profile_input.findData(preset.tracking_profile)
        if profile_index >= 0:
            self.profile_input.setCurrentIndex(profile_index)
        report_index = self.report_template_input.findData(preset.report_template)
        if report_index >= 0:
            self.report_template_input.setCurrentIndex(report_index)
        self.active_preset_key = preset.key
        self.status_label.setText(f"Applied preset: {preset.title}")
        self.selection_label.setText(preset.review_focus)
        self.setup_help.setText(
            f"{preset.setup_tip}\n"
            f"Preset review guidance: {preset.review_focus}"
        )
        self._refresh_overview_dashboard()

    def _frame_timestamp_seconds(self, frame_index: int) -> float:
        if self.video_metadata is None:
            return 0.0
        return frame_index / max(self.video_metadata.fps, 1e-6)

    def _combined_event_markers(self) -> tuple[EventMarker, ...]:
        derived_events = tuple(
            EventMarker(
                name=event.name,
                frame_index=event.frame_index,
                time_s=event.time_s,
                value=event.value,
                unit_label=event.unit_label,
                axis=event.axis,
                note=event.note,
                origin=event.origin,
            )
            for event in (self.analysis_result.events if self.analysis_result is not None else ())
        )
        manual_events = tuple(sorted(self.manual_event_markers, key=lambda marker: (marker.frame_index, marker.name)))
        return derived_events + manual_events

    def _refresh_manual_event_list(self) -> None:
        if not hasattr(self, "manual_events_list"):
            return
        self.manual_events_list.clear()
        for marker in sorted(self.manual_event_markers, key=lambda item: (item.frame_index, item.name)):
            label = f"{marker.name} @ frame {marker.frame_index}"
            if marker.note:
                label += f" — {marker.note}"
            item = QListWidgetItem(label)
            item.setData(Qt.UserRole, marker.frame_index)
            self.manual_events_list.addItem(item)
        if hasattr(self, "remove_event_marker_button"):
            self.remove_event_marker_button.setEnabled(bool(self.manual_event_markers))

    def _refresh_overview_dashboard(self) -> None:
        preset = PRESET_BY_KEY.get(self.active_preset_key, PRESET_BY_KEY["general"])
        video_name = Path(self.video_path).name if self.video_path else "No video selected"
        frame_range = (
            f"{self.selected_start_frame} → {self.selected_end_frame}"
            if self.video_metadata is not None and self.selected_end_frame is not None
            else "Set an analysis range"
        )
        track_state = self.current_bbox is not None
        scale_state = self.scale_points is not None
        review_count = len(self.track_result.quality.suspect_spans) if self.track_result is not None else 0
        manual_count = len(self.manual_event_markers)
        workspace_count = len(self.workspace_items)
        snapshot_lines = [
            f"Video: {video_name}",
            f"Range: {frame_range}",
            f"Preset: {preset.title}",
            f"Scale: {'ready' if scale_state else 'missing'} | Target: {'ready' if track_state else 'missing'}",
            f"Workspace clips: {workspace_count} | Manual events: {manual_count}",
        ]
        if hasattr(self, "overview_snapshot"):
            self.overview_snapshot.setText("\n".join(snapshot_lines))

        readiness_lines = [
            f"1. Video import: {'complete' if self.video_path else 'waiting'}",
            f"2. Range selection: {'complete' if self.selected_end_frame is not None else 'waiting'}",
            f"3. Calibration: {'complete' if scale_state else 'waiting'}",
            f"4. Target boxing: {'complete' if track_state else 'waiting'}",
            f"5. Analysis: {'complete' if self.analysis_result is not None else 'waiting'}",
            f"6. Review queue: {review_count} suspect spans",
            f"7. Manual journal entries: {manual_count}",
        ]
        if hasattr(self, "readiness_summary"):
            self.readiness_summary.setPlainText("\n".join(readiness_lines))

        protocol_lines = [
            f"Preset rationale: {preset.description}",
            f"Tracking strategy: {preset.tracking_profile}",
            f"Review focus: {preset.review_focus}",
            f"Setup tip: {preset.setup_tip}",
            "",
            "Reproducibility checklist:",
            "- Save the session after drawing calibration and target boxes.",
            "- Mark release/impact/contact frames in the review journal.",
            "- Export the research bundle together with the reproduce command.",
        ]
        if self.analysis_result is not None and self.track_result is not None:
            protocol_lines.extend(
                [
                    "",
                    f"Current QC badge: {build_quality_report(self.analysis_result, self.track_result, self._current_calibration()).qc_badge}",
                    f"Detected events: {len(self.analysis_result.events)}",
                    f"Additional tracked objects: {len(self.additional_objects)}",
                ]
            )
        if hasattr(self, "protocol_notes"):
            self.protocol_notes.setPlainText("\n".join(protocol_lines))
        self._refresh_trial_summary()

    def _refresh_trial_summary(self) -> None:
        if not hasattr(self, "trial_summary_label"):
            return
        preset = PRESET_BY_KEY.get(self.active_preset_key, PRESET_BY_KEY["general"])
        if self.video_path is None:
            self.trial_summary_label.setText("No active trial yet.")
            self.trial_context_label.setText("Load a video or session to see the live experiment summary.")
            return
        video_name = Path(self.video_path).stem
        status = "Ready for analysis"
        if self.analysis_result is not None and self.track_result is not None:
            status = f"{self.track_result.track_name} | QC {build_quality_report(self.analysis_result, self.track_result, self._current_calibration()).qc_badge}"
        elif self.current_bbox is None or self.scale_points is None:
            status = "Setup in progress"
        frame_range = f"{self.selected_start_frame} → {self.selected_end_frame}" if self.selected_end_frame is not None else str(self.selected_start_frame)
        self.trial_summary_label.setText(f"{video_name}\n{status}")
        self.trial_context_label.setText(
            f"Preset: {preset.title}\nFrame range: {frame_range}\n"
            f"Manual events: {len(self.manual_event_markers)} | Extra objects: {len(self.additional_objects)}"
        )

    def _add_manual_event_marker(self) -> None:
        if self.video_metadata is None:
            QMessageBox.warning(self, "No video", "Load a video before marking manual events.")
            return
        event_name = self.manual_event_name_input.text().strip() or "manual_event"
        note = self.manual_event_note_input.text().strip()
        unit_label = self.manual_event_unit_input.text().strip()
        raw_value = self.manual_event_value_input.text().strip()
        try:
            value = float(raw_value) if raw_value else 0.0
        except ValueError:
            QMessageBox.warning(self, "Invalid value", "Manual event value must be numeric when provided.")
            return
        marker = EventMarker(
            name=event_name,
            frame_index=self.current_frame_index,
            time_s=self._frame_timestamp_seconds(self.current_frame_index),
            value=value,
            unit_label=unit_label,
            note=note,
            origin="manual",
        )
        self.manual_event_markers.append(marker)
        self.manual_event_markers.sort(key=lambda item: (item.frame_index, item.name))
        self._refresh_manual_event_list()
        self._populate_events_table()
        self._populate_review_queue()
        self._refresh_timeline_summary()
        if self.analysis_result is not None and self.track_result is not None:
            self._refresh_state_summary()
        self._refresh_overview_dashboard()
        self.status_label.setText(f"Marked `{event_name}` at frame {self.current_frame_index}.")

    def _remove_selected_manual_event_marker(self) -> None:
        item = self.manual_events_list.currentItem() if hasattr(self, "manual_events_list") else None
        if item is None:
            return
        frame_index = int(item.data(Qt.UserRole))
        label = item.text()
        self.manual_event_markers = [
            marker
            for marker in self.manual_event_markers
            if not (marker.frame_index == frame_index and f"{marker.name} @ frame {marker.frame_index}" in label)
        ]
        self._refresh_manual_event_list()
        self._populate_events_table()
        self._populate_review_queue()
        self._refresh_timeline_summary()
        if self.analysis_result is not None and self.track_result is not None:
            self._refresh_state_summary()
        self._refresh_overview_dashboard()
        self.status_label.setText("Removed the selected manual event.")

    def _current_config(self) -> AnalysisConfig:
        return AnalysisConfig(
            smoothing_window=int(self.window_input.text()),
            smoothing_polyorder=int(self.polyorder_input.text()),
        )

    def _current_tracking_config(self) -> TrackingConfig:
        selected_profile = self.profile_input.currentData() or TrackingProfile.AUTO.value
        self.debug_tracking = self.debug_tracking_input.isChecked()
        return TrackingConfig(
            profile=TrackingProfile(selected_profile),
            robust_recovery=self.robust_recovery_input.isChecked(),
            bidirectional_refinement=self.bidirectional_input.isChecked(),
            debug_tracking=self.debug_tracking,
        )

    def _current_calibration(self) -> CalibrationProfile:
        mode = self.calibration_mode_input.currentData() or "single_line"
        reference_length = float(self.reference_length_input.text())
        unit_label = self.unit_input.text().strip() or "m"
        origin_x = float(self.origin_x_input.text() or "0")
        origin_y = float(self.origin_y_input.text() or "0")
        axis_angle = float(self.axis_angle_input.text() or "0")
        preset_name = self.calibration_preset_input.text().strip()
        invert_x = self.invert_x_input.isChecked()
        invert_y = self.invert_y_input.isChecked()
        if mode == "marker_size":
            return CalibrationProfile.from_marker_size(
                float(self.marker_size_input.text() or "20"),
                reference_length=reference_length,
                unit_label=unit_label,
                preset_name=preset_name,
            )
        if mode == "homography":
            homography_values = [float(value) for value in self.homography_input.text().replace(",", " ").split() if value.strip()]
            if len(homography_values) != 9:
                raise ValueError("Homography mode requires 9 numeric values.")
            pixel_distance = float(self.marker_size_input.text() or "20")
            return CalibrationProfile.from_homography(
                homography_values,
                reference_length=reference_length,
                unit_label=unit_label,
                pixel_distance=pixel_distance,
                origin_x_px=origin_x,
                origin_y_px=origin_y,
                preset_name=preset_name,
            )
        if mode == "two_axis":
            if self.scale_points is None:
                raise ValueError("Draw a scale line on the video first.")
            x1, y1, x2, y2 = self.scale_points
            calibration = CalibrationProfile.from_axis_points(
                x1,
                y1,
                x2,
                y2,
                reference_length=reference_length,
                unit_label=unit_label,
                invert_x=invert_x,
                invert_y=invert_y,
            )
            return CalibrationProfile(
                reference_length=calibration.reference_length,
                unit_label=calibration.unit_label,
                pixel_distance=calibration.pixel_distance,
                mode=calibration.mode,
                origin_x_px=origin_x if origin_x or origin_y else calibration.origin_x_px,
                origin_y_px=origin_y if origin_x or origin_y else calibration.origin_y_px,
                axis_angle_deg=axis_angle if self.axis_angle_input.text().strip() else calibration.axis_angle_deg,
                invert_x=invert_x,
                invert_y=invert_y,
                preset_name=preset_name,
            )
        if self.scale_points is None:
            raise ValueError("Draw a scale line on the video first.")
        calibration = CalibrationProfile.from_points(
            *self.scale_points,
            reference_length=reference_length,
            unit_label=unit_label,
        )
        return CalibrationProfile(
            reference_length=calibration.reference_length,
            unit_label=calibration.unit_label,
            pixel_distance=calibration.pixel_distance,
            mode="single_line",
            origin_x_px=origin_x,
            origin_y_px=origin_y,
            axis_angle_deg=axis_angle,
            invert_x=invert_x,
            invert_y=invert_y,
            preset_name=preset_name,
        )

    def _refresh_workflow_summary(self) -> None:
        video_ready = self.video_path is not None
        range_ready = self.selected_end_frame is not None and self.video_metadata is not None
        scale_ready = self.scale_points is not None
        target_ready = self.current_bbox is not None
        analysis_ready = self.analysis_result is not None
        reference_state = "Reference marker ready." if self.reference_bbox is not None else "Reference marker optional."
        steps = [
            ("Video", video_ready, "Open a clip"),
            ("Range", range_ready, "Set start and end frames"),
            ("Scale", scale_ready, "Draw the calibration line"),
            ("Target", target_ready, "Draw the object box"),
        ]
        checklist = "  ".join([f"{'OK' if done else 'TODO'} {label}" for label, done, _ in steps])
        guidance = "Ready to analyze." if all(done for _, done, _ in steps) else next(detail for _, done, detail in steps if not done)
        self.workflow_summary.setText(
            f"{checklist}\n{reference_state} {guidance}\nTip: keep `Smooth window` low for short, fast events; raise it only when the raw track is visibly jittery."
        )
        palette = {True: "#17354C", False: "#9CA3AF"}
        statuses = {
            "video": video_ready,
            "range": range_ready,
            "scale": scale_ready,
            "target": target_ready,
            "analysis": analysis_ready,
        }
        for key, label in getattr(self, "workflow_steps", {}).items():
            done = statuses.get(key, False)
            label.setStyleSheet(f"color: {palette[done]}; font-weight: {'700' if done else '500'};")
        self._refresh_action_states()
        self._refresh_overview_dashboard()

    def _refresh_action_states(self) -> None:
        video_ready = self.video_path is not None and self.video_metadata is not None
        scale_ready = self.scale_points is not None
        target_ready = self.current_bbox is not None
        analysis_ready = self.analysis_result is not None and self.track_result is not None
        correction_ready = self.pending_correction_bbox is not None
        for widget, enabled in (
            (self.prev_button, video_ready),
            (self.next_button, video_ready),
            (self.start_here_button, video_ready),
            (self.end_here_button, video_ready),
            (self.draw_scale_button, video_ready),
            (self.draw_target_button, video_ready),
            (self.draw_reference_button, video_ready),
            (self.add_object_button, video_ready),
            (self.clear_objects_button, video_ready and bool(self.additional_objects)),
            (self.analyze_button, video_ready and scale_ready and target_ready),
            (self.export_button, analysis_ready),
            (self.next_problem_button, analysis_ready),
            (self.draw_correction_button, analysis_ready),
            (self.apply_correction_button, analysis_ready and correction_ready),
            (self.window_start_button, analysis_ready),
            (self.window_end_button, analysis_ready),
            (self.window_full_button, analysis_ready),
            (self.add_event_marker_button, video_ready),
            (self.remove_event_marker_button, bool(getattr(self, "manual_event_markers", []))),
        ):
            widget.setEnabled(enabled)
        self.timeline_slider.setEnabled(video_ready)

    def _show_workflow_page(self, page_name: str) -> None:
        index_by_name = {"overview": 0, "setup": 1, "review": 2, "results": 3, "help": 4}
        index = index_by_name.get(page_name)
        if index is None or not hasattr(self, "workflow_pages"):
            return
        self._set_workflow_page(page_name)

    def _set_workflow_page(self, page_name: str) -> None:
        index_by_name = {"overview": 0, "setup": 1, "review": 2, "results": 3, "help": 4}
        index = index_by_name.get(page_name)
        if index is None:
            return
        self.workflow_pages.setCurrentIndex(index)
        self._refresh_nav_button_states()

    def _set_results_page(self, page_name: str) -> None:
        index_by_name = {"insights": 0, "graphs": 1, "window": 2, "events": 3, "quality": 4, "pairwise": 5, "table": 6, "reproduce": 7}
        index = index_by_name.get(page_name)
        if index is None:
            return
        self.results_tabs.setCurrentIndex(index)
        self._refresh_nav_button_states()

    def _refresh_nav_button_states(self) -> None:
        workflow_active = {0: "overview", 1: "setup", 2: "review", 3: "results", 4: "help"}.get(self.workflow_pages.currentIndex(), "overview")
        for key, button in getattr(self, "workflow_nav_buttons", {}).items():
            button.setProperty("active", "true" if key == workflow_active else "false")
            button.style().unpolish(button)
            button.style().polish(button)
        results_index = self.results_tabs.currentIndex() if hasattr(self, "results_tabs") else 0
        results_active = {0: "insights", 1: "graphs", 2: "window", 3: "events", 4: "quality", 5: "pairwise", 6: "table", 7: "reproduce"}.get(results_index, "insights")
        for key, button in getattr(self, "results_nav_buttons", {}).items():
            button.setProperty("active", "true" if key == results_active else "false")
            button.style().unpolish(button)
            button.style().polish(button)

    def open_video(self) -> None:
        path, _ = self._open_file_dialog("Open Video", "Video Files (*.mp4 *.mov *.avi *.mkv);;All Files (*)")
        if not path:
            return
        self._load_video_path(path, add_to_workspace=True)

    def _sync_workspace_list(self, *, active_path: str | None = None) -> None:
        self.workspace_list.blockSignals(True)
        self.workspace_list.clear()
        active = active_path or self.video_path or ""
        for item in self.workspace_items:
            label = item.label
            if item.session_path:
                label += "  [session]"
            widget_item = QListWidgetItem(label)
            widget_item.setData(Qt.UserRole, item.video_path)
            self.workspace_list.addItem(widget_item)
            if item.video_path == active:
                widget_item.setSelected(True)
        self.workspace_list.blockSignals(False)

    def _add_video_to_workspace(self, path: str, *, session_path: str = "") -> None:
        resolved = str(Path(path).resolve())
        updated = False
        next_items: list[WorkspaceItem] = []
        for item in self.workspace_items:
            if str(Path(item.video_path).resolve()) == resolved:
                next_items.append(
                    WorkspaceItem(
                        label=Path(path).stem,
                        video_path=path,
                        session_path=session_path or item.session_path,
                        notes=item.notes,
                    )
                )
                updated = True
            else:
                next_items.append(item)
        if not updated:
            next_items.append(WorkspaceItem(label=Path(path).stem, video_path=path, session_path=session_path))
        self.workspace_items = next_items
        self._sync_workspace_list(active_path=path)
        self._refresh_overview_dashboard()

    def _activate_workspace_item(self, item: QListWidgetItem) -> None:
        path = item.data(Qt.UserRole)
        if not path:
            return
        self._load_video_path(str(path), add_to_workspace=False)
        self.status_label.setText(f"Switched workspace clip to {Path(str(path)).name}")

    def save_workspace(self) -> None:
        path, _ = self._save_file_dialog("Save Workspace", "Workspace Files (*.json);;All Files (*)")
        if not path:
            return
        workspace = ResearchWorkspace(
            items=tuple(self.workspace_items),
            active_video_path=self.video_path or "",
            title=self.experiment_label_input.text().strip() or "Tracker AI Workspace",
        )
        workspace.save(path)
        self.status_label.setText(f"Saved workspace to {Path(path).name}")

    def load_workspace(self) -> None:
        path, _ = self._open_file_dialog("Open Workspace", "Workspace Files (*.json);;All Files (*)")
        if not path:
            return
        workspace = ResearchWorkspace.load(path)
        self.workspace_items = list(workspace.items)
        self._sync_workspace_list(active_path=workspace.active_video_path)
        self._refresh_overview_dashboard()
        target_path = workspace.active_video_path or (workspace.items[0].video_path if workspace.items else "")
        if target_path:
            self._load_video_path(target_path, add_to_workspace=False)
        self.status_label.setText(f"Loaded workspace {Path(path).name}")

    def _load_video_path(self, path: str, *, add_to_workspace: bool) -> None:
        self.video_path = path
        with VideoSource(path) as video:
            self.video_metadata = video.metadata
        self.current_frame_index = 0
        self.selected_start_frame = 0
        self.selected_end_frame = self.video_metadata.frame_count - 1 if self.video_metadata.frame_count else 0
        self.current_bbox = None
        self.reference_bbox = None
        self.pending_correction_bbox = None
        self.scale_points = None
        self.corrections = []
        self.additional_objects = []
        self.manual_event_markers = []
        self.display_track_result = None
        self.reference_track_result = None
        self.track_result = None
        self.analysis_result = None
        self.multi_result = None
        self.latest_export_bundle = None
        self.display_tracks_by_id = {}
        self.analysis_tracks_by_id = {}
        self.analyses_by_id = {}
        self.active_track_id = "primary"
        self.dismissed_review_frames.clear()
        self.selected_window_start = None
        self.selected_window_end = None
        self.experiment_label_input.clear()
        self.trial_id_input.clear()
        self.operator_input.clear()
        self.tags_input.clear()
        self.notes_input.clear()
        self._show_frame(0)
        self.status_label.setText(f"Loaded {Path(path).name}")
        self.selection_label.setText("Upload complete. Pick a clean frame, draw the scale, then draw the target.")
        self.state_summary.setPlainText("Video loaded. Waiting for calibration and target selection.")
        self.timeline_slider.setEnabled(True)
        self.timeline_slider.blockSignals(True)
        self.timeline_slider.setRange(0, max(self.video_metadata.frame_count - 1, 0))
        self.timeline_slider.setValue(0)
        self.timeline_slider.blockSignals(False)
        self.review_queue.clear()
        self.object_list.clear()
        self._refresh_manual_event_list()
        self.results_track_selector.clear()
        self.results_pair_selector.clear()
        self.insights_summary.setPlainText("Analysis insights will appear after you run a trial.")
        self.reproduce_summary.setPlainText("Reproducibility notes will appear after analysis.")
        self.reproduce_command.setPlainText("tracker-ai analyze ...")
        self.window_summary.setPlainText("Window statistics will appear after analysis.")
        self.quality_summary.setPlainText("Quality report will appear after analysis.")
        self.pairwise_summary.setPlainText("Pairwise metrics will appear when multiple objects are tracked.")
        self.events_table.setRowCount(0)
        self._refresh_workflow_summary()
        self._show_workflow_page("overview")
        if add_to_workspace:
            self._add_video_to_workspace(path)
        else:
            self._sync_workspace_list(active_path=path)

    def _show_frame(self, frame_index: int) -> None:
        if not self.video_path or self.video_metadata is None:
            return
        frame_index = max(0, min(frame_index, max(self.video_metadata.frame_count - 1, 0)))
        with VideoSource(self.video_path) as video:
            frame = video.read_frame(frame_index)
        self.current_frame = frame
        self.current_frame_index = frame_index
        self.canvas.set_frame(frame)
        self.canvas.set_scale_points(self.scale_points)
        self.canvas.set_reference_bbox(self.reference_bbox)

        display_bbox = self.pending_correction_bbox if self.awaiting_correction and self.pending_correction_bbox else self.current_bbox
        self.canvas.set_target_bbox(display_bbox, correction=self.awaiting_correction)
        self.canvas.set_observation(self._current_observation())
        self.timeline_slider.blockSignals(True)
        self.timeline_slider.setValue(frame_index)
        self.timeline_slider.blockSignals(False)
        self._refresh_frame_hud()
        self.frame_label.setText(
            f"Frame: {self.current_frame_index} / {max((self.video_metadata.frame_count - 1), 0)} | range: {self.selected_start_frame} -> {self.selected_end_frame}"
        )
        if self.video_path:
            self.status_label.setText(f"{Path(self.video_path).name} | frame {self.current_frame_index}")
        if self.video_metadata is not None:
            self.graph_panel.set_frame_cursor(self.current_frame_index / max(self.video_metadata.fps, 1e-6))
        self._refresh_pairwise_summary()

    def _step_frame(self, delta: int) -> None:
        if self.video_metadata is None:
            return
        self._show_frame(self.current_frame_index + delta)

    def _on_timeline_changed(self, frame_index: int) -> None:
        if self.video_metadata is None:
            return
        self._show_frame(frame_index)

    def _set_window_start_here(self) -> None:
        self.selected_window_start = self.current_frame_index
        if self.selected_window_end is not None and self.selected_window_end < self.selected_window_start:
            self.selected_window_end = self.selected_window_start
        self._refresh_window_summary()
        self._refresh_timeline_summary()
        self.status_label.setText(f"Selected window start set to frame {self.selected_window_start}.")

    def _set_window_end_here(self) -> None:
        self.selected_window_end = self.current_frame_index
        if self.selected_window_start is not None and self.selected_window_end < self.selected_window_start:
            self.selected_window_start = self.selected_window_end
        self._refresh_window_summary()
        self._refresh_timeline_summary()
        self.status_label.setText(f"Selected window end set to frame {self.selected_window_end}.")

    def _set_window_full_range(self) -> None:
        self.selected_window_start = self.selected_start_frame
        self.selected_window_end = self.selected_end_frame
        self._refresh_window_summary()
        self._refresh_timeline_summary()
        self.status_label.setText("Selected window reset to the full analysis range.")

    def _set_start_frame_here(self) -> None:
        self.selected_start_frame = self.current_frame_index
        self.frame_label.setText(
            f"Frame: {self.current_frame_index} / {max((self.video_metadata.frame_count - 1), 0)} | range: {self.selected_start_frame} -> {self.selected_end_frame}"
        )
        self.status_label.setText(f"Start frame set to {self.selected_start_frame}")
        self.selection_label.setText("Start frame saved. Set the end frame or keep the full range before analysis.")
        self._refresh_workflow_summary()

    def _set_end_frame_here(self) -> None:
        if self.video_metadata is None:
            return
        self.selected_end_frame = self.current_frame_index
        if self.selected_end_frame < self.selected_start_frame:
            self.selected_start_frame = self.selected_end_frame
        self.frame_label.setText(
            f"Frame: {self.current_frame_index} / {max((self.video_metadata.frame_count - 1), 0)} | range: {self.selected_start_frame} -> {self.selected_end_frame}"
        )
        self.status_label.setText(f"End frame set to {self.selected_end_frame}")
        self.selection_label.setText("End frame saved. The analysis will stop at this frame.")
        self._refresh_workflow_summary()

    def _begin_draw_scale(self) -> None:
        if self.current_frame is None:
            QMessageBox.warning(self, "No frame", "Open a video before drawing the scale.")
            return
        self.awaiting_correction = False
        self.canvas.set_mode("draw_scale")
        self.selection_label.setText("Drag on the frame to define the calibration line.")
        self._show_workflow_page("setup")

    def _begin_draw_target(self) -> None:
        if self.current_frame is None:
            QMessageBox.warning(self, "No frame", "Open a video before drawing the target.")
            return
        self.awaiting_correction = False
        self.awaiting_reference = False
        self.pending_correction_bbox = None
        self.canvas.set_mode("draw_bbox")
        self.selection_label.setText("Drag on the frame to define the target object.")
        self._show_workflow_page("setup")

    def _begin_draw_reference(self) -> None:
        if self.current_frame is None:
            QMessageBox.warning(self, "No frame", "Open a video before drawing the reference.")
            return
        self.awaiting_correction = False
        self.awaiting_reference = True
        self.awaiting_additional_object = False
        self.pending_correction_bbox = None
        self.canvas.set_mode("draw_bbox")
        self.selection_label.setText("Drag on the frame to define the reference marker.")
        self._show_workflow_page("setup")

    def _begin_additional_object(self) -> None:
        if self.current_frame is None:
            QMessageBox.warning(self, "No frame", "Open a video before drawing an additional object.")
            return
        self.awaiting_correction = False
        self.awaiting_reference = False
        self.awaiting_additional_object = True
        self.pending_correction_bbox = None
        self.canvas.set_mode("draw_bbox")
        self.selection_label.setText(f"Drag on the frame to define `{self.object_name_input.text().strip() or 'Secondary Object'}`.")
        self._show_workflow_page("setup")

    def _clear_additional_objects(self) -> None:
        self.additional_objects = []
        self.object_list.clear()
        self.status_label.setText("Cleared additional objects.")

    def _begin_draw_correction(self) -> None:
        if self.track_result is None:
            QMessageBox.warning(self, "No analysis", "Run an analysis before drawing a correction.")
            return
        self.awaiting_correction = True
        self.awaiting_reference = False
        self.pending_correction_bbox = None
        self.canvas.set_mode("draw_bbox")
        self.selection_label.setText(f"Draw the corrected object box for frame {self.current_frame_index}.")
        self._show_workflow_page("review")

    def _on_scale_drawn(self, points: tuple[float, float, float, float]) -> None:
        self.scale_points = points
        self.canvas.set_scale_points(points)
        self.selection_label.setText("Scale captured. Now draw the target box.")
        self.status_label.setText("Calibration line captured.")
        self._refresh_workflow_summary()

    def _on_bbox_drawn(self, bbox: BBox) -> None:
        if self.awaiting_correction:
            self.pending_correction_bbox = bbox
            self.canvas.set_target_bbox(bbox, correction=True)
            self.selection_label.setText(f"Correction ready for frame {self.current_frame_index}. Click Apply Correction.")
            self.status_label.setText(f"Correction staged at frame {self.current_frame_index}.")
        elif self.awaiting_reference:
            self.reference_bbox = bbox
            self.awaiting_reference = False
            self.canvas.set_reference_bbox(bbox)
            self.selection_label.setText("Reference marker captured. Run analysis to stabilize against apparatus motion.")
            self.status_label.setText("Reference marker box captured.")
            self._refresh_workflow_summary()
        elif self.awaiting_additional_object:
            self.awaiting_additional_object = False
            track_id = f"object_{len(self.additional_objects) + 1}"
            track_name = self.object_name_input.text().strip() or f"Object {len(self.additional_objects) + 1}"
            track_kind = self.object_kind_input.currentData() or "secondary"
            self.additional_objects.append(TrackedObject(track_id=track_id, name=track_name, bbox=bbox, kind=track_kind))
            self.object_list.addItem(f"{track_name} [{track_kind}]")
            self.selection_label.setText(f"Added `{track_name}`. Add another object or run analysis.")
            self.status_label.setText(f"Additional object `{track_name}` captured.")
        else:
            self.current_bbox = bbox
            self.canvas.set_target_bbox(bbox, correction=False)
            self.selection_label.setText("Target captured. Run analysis when ready.")
            self.status_label.setText("Target box captured.")
            self._refresh_workflow_summary()

    def _current_observation(self) -> TrackingObservation | None:
        active_display_track = self.display_tracks_by_id.get(self.active_track_id, self.display_track_result)
        if active_display_track is None:
            return None
        return active_display_track.observation_by_frame().get(self.current_frame_index)

    def _set_active_track(self, track_id: str) -> None:
        if track_id not in self.analysis_tracks_by_id:
            return
        self.active_track_id = track_id
        self.track_result = self.analysis_tracks_by_id[track_id]
        self.display_track_result = self.display_tracks_by_id.get(track_id, self.track_result)
        self.analysis_result = self.analyses_by_id[track_id]
        self.graph_panel.update_analysis(self.analysis_result)
        self._refresh_measurement_views()
        self._populate_table()
        self._populate_events_table()
        self._refresh_state_summary()
        self._refresh_window_summary()
        self._refresh_timeline_summary()
        self._show_frame(self.current_frame_index)

    def _on_active_track_changed(self, _index: int) -> None:
        track_id = self.results_track_selector.currentData()
        if track_id is None:
            return
        self._set_active_track(str(track_id))

    def _refresh_track_selectors(self) -> None:
        self.results_track_selector.blockSignals(True)
        self.results_track_selector.clear()
        for track_id, track in self.analysis_tracks_by_id.items():
            self.results_track_selector.addItem(f"{track.track_name} [{track.track_kind}]", track_id)
        index = self.results_track_selector.findData(self.active_track_id)
        if index >= 0:
            self.results_track_selector.setCurrentIndex(index)
        self.results_track_selector.blockSignals(False)

        self.results_pair_selector.blockSignals(True)
        self.results_pair_selector.clear()
        self.results_pair_selector.addItem("No pair selected", "")
        if self.multi_result is not None:
            for metric in self.multi_result.pairwise_metrics:
                label = f"{metric.primary_track_id} <-> {metric.secondary_track_id}"
                self.results_pair_selector.addItem(label, f"{metric.primary_track_id}|{metric.secondary_track_id}")
        self.results_pair_selector.blockSignals(False)

    def _refresh_measurement_views(self, _index: int = 0) -> None:
        primary_key = self.graph_primary_selector.currentData() if hasattr(self, "graph_primary_selector") else "x"
        secondary_key = self.graph_secondary_selector.currentData() if hasattr(self, "graph_secondary_selector") else "y"
        self.graph_panel.set_measurements(str(primary_key or "x"), str(secondary_key or "y"))
        if self.analysis_result is not None and self.track_result is not None:
            self._populate_table()

    def _refresh_pairwise_summary(self) -> None:
        if self.multi_result is None or not self.multi_result.pairwise_metrics:
            self.pairwise_summary.setPlainText("Pairwise metrics will appear when multiple objects are tracked.")
            return
        selected_key = self.results_pair_selector.currentData()
        metric = None
        if selected_key:
            for candidate in self.multi_result.pairwise_metrics:
                if f"{candidate.primary_track_id}|{candidate.secondary_track_id}" == selected_key:
                    metric = candidate
                    break
        if metric is None:
            metric = self.multi_result.pairwise_metrics[0]
        self.pairwise_summary.setPlainText(
            "\n".join(
                [
                    f"Pair: {metric.primary_track_id} <-> {metric.secondary_track_id}",
                    f"Samples: {len(metric.samples)}",
                    f"Minimum separation: {metric.minimum_separation:.4f} {self.unit_input.text().strip() or 'm'}",
                    f"Peak relative speed: {metric.peak_relative_speed:.4f} {(self.unit_input.text().strip() or 'm')}/s",
                    f"Collision frame: {metric.collision_frame if metric.collision_frame is not None else 'not detected'}",
                    "",
                    *[
                        f"Frame {sample.frame_index}: distance {sample.distance_units:.4f}, rel speed {sample.relative_speed_units_s:.4f}"
                        for sample in metric.samples[:12]
                    ],
                ]
            )
        )

    def _refresh_frame_hud(self) -> None:
        observation = self._current_observation()
        self.hud_frame.setText(str(self.current_frame_index))
        timestamp = 0.0
        if self.video_metadata is not None:
            timestamp = self.current_frame_index / max(self.video_metadata.fps, 1e-6)
        self.hud_timestamp.setText(f"{timestamp:.3f} s")
        if observation is None:
            self.hud_confidence.setText("--")
            self.hud_state.setText("--")
            self.hud_bbox.setText("--")
            self.hud_reference.setText("ready" if self.reference_bbox is not None else "off")
            self.hud_velocity.setText("--")
            self.hud_acceleration.setText("--")
            return
        self.hud_confidence.setText(f"{observation.confidence:.2f}")
        self.hud_state.setText(observation.state)
        self.hud_bbox.setText(f"{observation.bbox.width:.0f}x{observation.bbox.height:.0f}px")
        self.hud_reference.setText("enabled" if self.reference_bbox is not None else "off")
        velocity = "--"
        acceleration = "--"
        if self.analysis_result is not None:
            analysis_frame_to_index = {obs.frame_index: idx for idx, obs in enumerate(self.track_result.observations)} if self.track_result else {}
            idx = analysis_frame_to_index.get(self.current_frame_index)
            if idx is not None:
                velocity = f"{self.analysis_result.speed[idx]:.3f}"
                acceleration = f"{self.analysis_result.acceleration_magnitude[idx]:.3f}"
        self.hud_velocity.setText(velocity)
        self.hud_acceleration.setText(acceleration)

    def _current_session(self) -> ProjectSession:
        if self.video_path is None or self.current_bbox is None:
            raise ValueError("Video and target box must be set.")
        return ProjectSession(
            video_path=self.video_path,
            initial_bbox=self.current_bbox,
            reference_bbox=self.reference_bbox,
            calibration=self._current_calibration(),
            analysis_config=self._current_config(),
            tracking_config=self.track_result.tracking_config if self.track_result else self._current_tracking_config(),
            metadata=ExperimentMetadata(
                experiment_label=self.experiment_label_input.text().strip(),
                trial_id=self.trial_id_input.text().strip(),
                operator_name=self.operator_input.text().strip(),
                notes=self.notes_input.text().strip(),
                tags=tuple(tag.strip() for tag in self.tags_input.text().split(",") if tag.strip()),
            ),
            selected_start_frame=self.selected_start_frame,
            selected_end_frame=self.selected_end_frame,
            scale_points=self.scale_points,
            corrections=self.corrections,
            track_quality=self.track_result.quality if self.track_result else None,
            advanced_mode=self.advanced_mode,
            review_state=SessionReviewState(
                last_frame_index=self.current_frame_index,
                selected_window_start=self.selected_window_start,
                selected_window_end=self.selected_window_end,
                dismissed_review_frames=tuple(sorted(self.dismissed_review_frames)),
            ),
            event_markers=self._combined_event_markers(),
            export_preferences=ExportPreferences(
                include_overlay=self.include_overlay_input.isChecked(),
                include_debug_tracking=self.debug_tracking_input.isChecked(),
                include_plots=self.include_plots_input.isChecked(),
                report_template=self.report_template_input.currentData() or ("research" if self.advanced_mode else "guided"),
            ),
            provenance=ProvenanceMetadata(video_path_snapshot=self.video_path),
            additional_objects=tuple(self.additional_objects),
        )

    def run_analysis(self) -> None:
        if self.video_path is None:
            QMessageBox.warning(self, "No video", "Open a video before running analysis.")
            return
        if self.current_bbox is None:
            QMessageBox.warning(self, "No target", "Draw the initial target box first.")
            return
        try:
            calibration = self._current_calibration()
            config = self._current_config()
            tracking_config = self._current_tracking_config()
        except Exception as exc:
            QMessageBox.warning(self, "Invalid setup", str(exc))
            return
        self.status_label.setText("Running analysis...")
        self._refresh_action_states()
        worker = AnalysisWorker(
            self.video_path,
            self.current_bbox,
            [TrackedObject(track_id="primary", name="Primary Object", bbox=self.current_bbox, kind="primary"), *self.additional_objects],
            self.reference_bbox,
            calibration,
            config,
            tracking_config,
            start_frame=self.selected_start_frame,
            end_frame=self.selected_end_frame if self.selected_end_frame is not None else self.selected_start_frame,
            corrected=False,
        )
        worker.signals.finished.connect(self._analysis_finished)
        worker.signals.failed.connect(self._analysis_failed)
        self.thread_pool.start(worker)

    def apply_correction(self) -> None:
        if self.video_path is None or self.track_result is None:
            QMessageBox.warning(self, "No analysis", "Run an analysis first.")
            return
        if self.pending_correction_bbox is None:
            QMessageBox.warning(self, "No correction", "Draw a correction box first.")
            return
        try:
            calibration = self._current_calibration()
            config = self._current_config()
            tracking_config = self._current_tracking_config()
        except Exception as exc:
            QMessageBox.warning(self, "Invalid setup", str(exc))
            return
        self.status_label.setText(f"Applying correction from frame {self.current_frame_index}...")
        self._refresh_action_states()
        worker = AnalysisWorker(
            self.video_path,
            self.pending_correction_bbox,
            [TrackedObject(track_id="primary", name="Primary Object", bbox=self.pending_correction_bbox, kind="primary")],
            self.reference_bbox,
            calibration,
            config,
            tracking_config,
            start_frame=self.current_frame_index,
            end_frame=self.selected_end_frame if self.selected_end_frame is not None else self.current_frame_index,
            corrected=True,
        )
        worker.signals.finished.connect(self._analysis_finished)
        worker.signals.failed.connect(self._analysis_failed)
        self.thread_pool.start(worker)

    def _analysis_finished(self, payload: dict[str, object]) -> None:
        try:
            calibration = self._current_calibration()
            config = self._current_config()
        except Exception as exc:
            self._analysis_failed(str(exc))
            return

        segment_display_track = payload["display_track"]
        segment_track = payload["track_result"]
        segment_reference_track = payload["reference_track"]
        if payload["corrected"] and self.track_result is not None:
            base_display = self.display_track_result or self.track_result
            self.display_track_result = merge_track_results(base_display, segment_display_track)
            if self.reference_track_result is not None:
                self.track_result = apply_reference_motion_correction(self.display_track_result, self.reference_track_result)
            else:
                self.track_result = merge_track_results(self.track_result, segment_track)
            self.analysis_result = analyze_track(self.track_result, calibration, config)
            assert self.pending_correction_bbox is not None
            self.corrections.append(CorrectionAnchor(frame_index=int(payload["start_frame"]), bbox=self.pending_correction_bbox))
            self.pending_correction_bbox = None
            self.awaiting_correction = False
            self.status_label.setText(f"Correction applied from frame {payload['start_frame']}.")
            self._show_workflow_page("review")
        else:
            multi_result = payload.get("multi_result")
            if multi_result is not None:
                self.multi_result = multi_result
                self.display_tracks_by_id = dict(multi_result.display_tracks)
                self.analysis_tracks_by_id = dict(multi_result.analysis_tracks)
                self.analyses_by_id = dict(multi_result.analyses)
                self.active_track_id = multi_result.primary_track_id
            else:
                self.multi_result = None
                self.display_tracks_by_id = {"primary": segment_display_track}
                self.analysis_tracks_by_id = {"primary": segment_track}
                self.analyses_by_id = {"primary": payload["analysis"]}
                self.active_track_id = "primary"
            self.display_track_result = self.display_tracks_by_id[self.active_track_id]
            self.track_result = self.analysis_tracks_by_id[self.active_track_id]
            self.reference_track_result = segment_reference_track
            self.analysis_result = self.analyses_by_id[self.active_track_id]
            if multi_result is not None:
                self.status_label.setText(
                    f"Tracked {len(multi_result.analysis_tracks)} objects across {len(self.track_result.observations)} frames. "
                    f"Pairwise metrics: {len(multi_result.pairwise_metrics)}"
                )
            else:
                self.status_label.setText(
                    f"Tracked {len(self.track_result.observations)} frames with average confidence "
                    f"{self.track_result.average_confidence:.2f}"
                )

        if self.analysis_result is None or self.track_result is None:
            return
        if self.selected_window_start is None:
            self.selected_window_start = self.selected_start_frame
        if self.selected_window_end is None:
            self.selected_window_end = self.selected_end_frame
        self._refresh_track_selectors()
        self.graph_panel.update_analysis(self.analysis_result)
        self._refresh_measurement_views()
        self._populate_table()
        self._populate_events_table()
        self._refresh_state_summary()
        self._populate_review_queue()
        self._refresh_timeline_summary()
        self._refresh_window_summary()
        self._refresh_pairwise_summary()
        self._refresh_workflow_summary()
        self._show_frame(self.current_frame_index)
        self._show_workflow_page("results")

    def _analysis_failed(self, message: str) -> None:
        self.status_label.setText("Analysis failed.")
        self._refresh_action_states()
        QMessageBox.critical(self, "Analysis failed", message)

    def _populate_table(self) -> None:
        if self.analysis_result is None or self.track_result is None:
            return
        rows = self.analysis_result.to_rows()[:250]
        observations = self.track_result.observations[:250]
        preset = self.table_column_selector.currentData() if hasattr(self, "table_column_selector") else "core"
        definitions = {
            "core": [
                ("frame", lambda row, observation: observation.frame_index),
                ("t", lambda row, observation: row["time_s"]),
                ("x", lambda row, observation: row["x_units"]),
                ("y", lambda row, observation: row["y_units"]),
                ("|v|", lambda row, observation: row["speed"]),
                ("angle", lambda row, observation: row["angle_deg"]),
                ("conf", lambda row, observation: row["confidence"]),
                ("state", lambda row, observation: observation.state),
                ("flags", lambda row, observation: "corrected" if observation.corrected else ("lost" if observation.lost else observation.source)),
            ],
            "velocity": [
                ("frame", lambda row, observation: observation.frame_index),
                ("t", lambda row, observation: row["time_s"]),
                ("vx", lambda row, observation: row["vx"]),
                ("vy", lambda row, observation: row["vy"]),
                ("|v|", lambda row, observation: row["speed"]),
                ("angle", lambda row, observation: row["angle_deg"]),
                ("state", lambda row, observation: observation.state),
            ],
            "acceleration": [
                ("frame", lambda row, observation: observation.frame_index),
                ("t", lambda row, observation: row["time_s"]),
                ("ax", lambda row, observation: row["ax"]),
                ("ay", lambda row, observation: row["ay"]),
                ("|a|", lambda row, observation: row["acceleration_magnitude"]),
                ("pos unc", lambda row, observation: row["position_uncertainty"]),
                ("vel unc", lambda row, observation: row["velocity_uncertainty"]),
                ("acc unc", lambda row, observation: row["acceleration_uncertainty"]),
            ],
            "confidence": [
                ("frame", lambda row, observation: observation.frame_index),
                ("t", lambda row, observation: row["time_s"]),
                ("tracker", lambda row, observation: row["confidence"]),
                ("scientific", lambda row, observation: row["scientific_confidence"]),
                ("state", lambda row, observation: observation.state),
                ("reason", lambda row, observation: observation.failure_reason or ""),
                ("source", lambda row, observation: observation.source),
                ("flags", lambda row, observation: "interp" if observation.is_interpolated else ("inferred" if observation.is_inferred else "")),
            ],
            "all": [
                ("frame", lambda row, observation: observation.frame_index),
                ("t", lambda row, observation: row["time_s"]),
                ("raw x", lambda row, observation: row["raw_x_units"]),
                ("raw y", lambda row, observation: row["raw_y_units"]),
                ("x", lambda row, observation: row["x_units"]),
                ("y", lambda row, observation: row["y_units"]),
                ("vx", lambda row, observation: row["vx"]),
                ("vy", lambda row, observation: row["vy"]),
                ("|v|", lambda row, observation: row["speed"]),
                ("ax", lambda row, observation: row["ax"]),
                ("ay", lambda row, observation: row["ay"]),
                ("|a|", lambda row, observation: row["acceleration_magnitude"]),
                ("angle", lambda row, observation: row["angle_deg"]),
                ("tracker", lambda row, observation: row["confidence"]),
                ("scientific", lambda row, observation: row["scientific_confidence"]),
                ("pos unc", lambda row, observation: row["position_uncertainty"]),
                ("vel unc", lambda row, observation: row["velocity_uncertainty"]),
                ("acc unc", lambda row, observation: row["acceleration_uncertainty"]),
                ("state", lambda row, observation: observation.state),
                ("reason", lambda row, observation: observation.failure_reason or ""),
                ("source", lambda row, observation: observation.source),
                ("flags", lambda row, observation: "corrected" if observation.corrected else ("interp" if observation.is_interpolated else ("lost" if observation.lost else ""))),
            ],
        }
        columns = definitions.get(str(preset), definitions["core"])
        self.table.setColumnCount(len(columns))
        self.table.setHorizontalHeaderLabels([label for label, _getter in columns])
        self.table.setRowCount(len(rows))
        for r, (row, observation) in enumerate(zip(rows, observations, strict=False)):
            for c, (_label, getter) in enumerate(columns):
                value = getter(row, observation)
                item = QTableWidgetItem(f"{value}" if isinstance(value, str) else f"{value:.4f}")
                self.table.setItem(r, c, item)

    def _populate_events_table(self) -> None:
        markers = self._combined_event_markers()
        if not markers:
            self.events_table.setRowCount(0)
            return
        rows = [
            {
                "name": marker.name,
                "origin": marker.origin,
                "frame_index": marker.frame_index,
                "time_s": marker.time_s,
                "value": marker.value,
                "unit_label": marker.unit_label,
                "note": marker.note,
            }
            for marker in markers
        ]
        self.events_table.setRowCount(len(rows))
        for row_index, row in enumerate(rows):
            values = [row["name"], row["origin"], row["frame_index"], row["time_s"], row["value"], row["unit_label"], row["note"]]
            for column, value in enumerate(values):
                if isinstance(value, str):
                    text = value
                elif isinstance(value, int):
                    text = str(value)
                else:
                    text = f"{float(value):.4f}"
                self.events_table.setItem(row_index, column, QTableWidgetItem(text))

    def _populate_review_queue(self) -> None:
        self.review_queue.clear()
        if self.track_result is None:
            return
        for span in self.track_result.quality.suspect_spans:
            item = QListWidgetItem(f"Suspect {span.start_frame} -> {span.end_frame} ({span.reason})")
            item.setData(Qt.UserRole, span.start_frame)
            self.review_queue.addItem(item)
        for span in self.track_result.quality.lost_spans:
            item = QListWidgetItem(f"Lost {span.start_frame} -> {span.end_frame} ({span.reason})")
            item.setData(Qt.UserRole, span.start_frame)
            self.review_queue.addItem(item)
        for correction in self.corrections:
            item = QListWidgetItem(f"Correction @ frame {correction.frame_index}")
            item.setData(Qt.UserRole, correction.frame_index)
            self.review_queue.addItem(item)
        for marker in self._combined_event_markers():
            item = QListWidgetItem(f"Event {marker.name} [{marker.origin}] @ frame {marker.frame_index}")
            item.setData(Qt.UserRole, marker.frame_index)
            self.review_queue.addItem(item)

    def _refresh_timeline_summary(self) -> None:
        if self.track_result is None or self.analysis_result is None:
            self.timeline_summary.setText("Timeline markers will appear after analysis.")
            return
        markers: list[str] = [f"start {self.selected_start_frame}", f"end {self.selected_end_frame}"]
        if self.selected_window_start is not None and self.selected_window_end is not None:
            markers.append(f"window {self.selected_window_start}-{self.selected_window_end}")
        markers.extend(f"suspect {span.start_frame}-{span.end_frame}" for span in self.track_result.quality.suspect_spans[:3])
        markers.extend(f"lost {span.start_frame}-{span.end_frame}" for span in self.track_result.quality.lost_spans[:3])
        markers.extend(f"correction {correction.frame_index}" for correction in self.corrections[:3])
        combined_markers = list(self._combined_event_markers())
        markers.extend(f"event {event.name}@{event.frame_index}" for event in combined_markers[:6])
        self.timeline_summary.setText(" | ".join(markers))

    def _refresh_window_summary(self) -> None:
        if self.analysis_result is None:
            self.window_summary.setPlainText("Window statistics will appear after analysis.")
            return
        start = self.selected_window_start if self.selected_window_start is not None else self.selected_start_frame
        if self.selected_end_frame is not None:
            default_end = self.selected_end_frame
        else:
            default_end = self.selected_start_frame
        end = self.selected_window_end if self.selected_window_end is not None else default_end
        window = summarize_window(self.analysis_result, start, end)
        if window is None:
            self.window_summary.setPlainText("Choose a wider frame window to compute regional statistics.")
            return
        self.window_summary.setPlainText(
            "\n".join(
                [
                    f"Window frames: {window.start_frame} -> {window.end_frame}",
                    f"Duration: {window.duration_s:.3f} s",
                    f"Displacement: {window.displacement:.4f} {self.unit_input.text().strip() or 'm'}",
                    f"Mean speed: {window.mean_speed:.4f} {(self.unit_input.text().strip() or 'm')}/s",
                    f"Max speed: {window.max_speed:.4f} {(self.unit_input.text().strip() or 'm')}/s",
                    f"Max acceleration: {window.max_acceleration:.4f} {(self.unit_input.text().strip() or 'm')}/s^2",
                ]
            )
        )

    def _jump_from_review_queue(self, item: QListWidgetItem) -> None:
        frame_index = item.data(Qt.UserRole)
        if frame_index is None:
            return
        self._show_frame(int(frame_index))
        self._show_workflow_page("review")

    def _jump_to_next_correction_frame(self) -> None:
        for correction in sorted(self.corrections, key=lambda item: item.frame_index):
            if correction.frame_index > self.current_frame_index:
                self._show_frame(correction.frame_index)
                self.status_label.setText(f"Jumped to correction frame {correction.frame_index}.")
                self._show_workflow_page("review")
                return
        self.status_label.setText("No later correction frame was found.")

    def _dismiss_current_review_frame(self) -> None:
        self.dismissed_review_frames.add(self.current_frame_index)
        self.status_label.setText(f"Dismissed frame {self.current_frame_index} from the review queue for this session.")

    def _set_advanced_mode(self, enabled: bool) -> None:
        self.advanced_mode = enabled
        self.debug_tracking_input.setVisible(enabled)
        self.include_plots_input.setVisible(enabled)
        self.report_template_input.setVisible(True)
        self.calibration_mode_input.setVisible(True)
        self.origin_x_input.setVisible(enabled)
        self.origin_y_input.setVisible(enabled)
        self.axis_angle_input.setVisible(enabled)
        self.marker_size_input.setVisible(enabled)
        self.calibration_preset_input.setVisible(enabled)
        self.homography_input.setVisible(enabled)
        self.invert_x_input.setVisible(enabled)
        self.invert_y_input.setVisible(enabled)
        self.window_summary.setVisible(enabled)
        self.quality_summary.setVisible(enabled)
        self.events_table.setVisible(True)
        self.pairwise_summary.setVisible(True)
        self.results_pair_selector.setVisible(True)
        self.status_label.setText("Advanced mode enabled." if enabled else "Advanced mode disabled.")

    def _refresh_state_summary(self) -> None:
        if self.analysis_result is None or self.track_result is None:
            self.state_summary.setPlainText("Tracker state will appear here.")
            self.insights_summary.setPlainText("Analysis insights will appear after you run a trial.")
            self.reproduce_summary.setPlainText("Reproducibility notes will appear after analysis.")
            self.reproduce_command.setPlainText("tracker-ai analyze ...")
            return
        calibration = self._current_calibration()
        summary = build_analysis_summary(self.analysis_result, self.track_result, calibration)
        quality_report = build_quality_report(self.analysis_result, self.track_result, calibration)
        analyzer_results = build_analyzer_report(
            self.analysis_result,
            self.track_result,
            calibration,
            pairwise_metrics=(self.multi_result.pairwise_metrics if self.multi_result is not None else None),
        )
        self.metric_avg_conf.setText(f"{summary.average_confidence:.3f}")
        self.metric_peak_speed.setText(f"{summary.peak_speed:.3f}")
        self.metric_peak_accel.setText(f"{summary.peak_acceleration:.3f}")
        self.metric_path.setText(f"{summary.total_path_length:.3f}")
        self.state_summary.setPlainText(
            "\n".join(
                [
                    f"Experiment: {self.experiment_label_input.text().strip() or 'unspecified'}",
                    f"Track: {self.track_result.track_name} [{self.track_result.track_kind}]",
                    f"Trial ID: {self.trial_id_input.text().strip() or 'unspecified'}",
                    f"Start frame: {summary.start_frame}",
                    f"End frame: {summary.end_frame}",
                    f"Frames analyzed: {summary.frame_count}",
                    f"Duration: {summary.duration_seconds:.3f} s",
                    f"Average confidence: {summary.average_confidence:.3f}",
                    f"Low-confidence frames: {summary.low_confidence_frame_count}",
                    f"Suspect spans: {summary.suspect_span_count}",
                    f"Lost spans: {len(self.track_result.quality.lost_spans)}",
                    f"Reacquisitions: {summary.reacquisition_count}",
                    f"Tracking profile: {self.track_result.tracking_config.profile.value}",
                    f"Robust recovery: {self.track_result.tracking_config.robust_recovery}",
                    f"Bidirectional refine: {self.track_result.tracking_config.bidirectional_refinement}",
                    f"Reference marker: {'enabled' if self.reference_bbox is not None else 'off'}",
                    f"Corrections: {len(self.corrections)}",
                    f"Path length: {summary.total_path_length:.4f} {summary.unit_label}",
                    f"Net displacement: {summary.net_displacement:.4f} {summary.unit_label}",
                    f"Mean speed: {summary.mean_speed:.4f} {summary.unit_label}/s",
                    f"Mean acceleration: {summary.mean_acceleration:.4f} {summary.unit_label}/s^2",
                    f"Scientific confidence: {summary.scientific_confidence_mean:.3f}",
                    f"QC badge: {summary.qc_badge}",
                    f"Calibration confidence: {quality_report.calibration_confidence:.3f}",
                    f"Drift sensitivity: {quality_report.drift_sensitivity:.3f}",
                    f"Peak position uncertainty: {summary.peak_position_uncertainty:.4f} {summary.unit_label}",
                    f"Events detected: {summary.event_count}",
                    f"Experiment modules: {len(analyzer_results)}",
                    f"Review recommended: {summary.review_recommended}",
                    f"QC notes: {'; '.join(quality_report.notes)}",
                ]
            )
        )
        self.quality_summary.setPlainText(
            "\n".join(
                [
                    f"QC badge: {quality_report.qc_badge}",
                    f"Tracker confidence mean: {quality_report.tracker_confidence_mean:.3f}",
                    f"Scientific confidence mean: {quality_report.scientific_confidence_mean:.3f}",
                    f"Calibration confidence: {quality_report.calibration_confidence:.3f}",
                    f"Drift sensitivity: {quality_report.drift_sensitivity:.3f}",
                    f"Low-confidence frames: {quality_report.low_confidence_frames}",
                    f"Lost frames: {quality_report.lost_frame_count}",
                    f"Corrected frames: {quality_report.corrected_frame_count}",
                    f"Interpolation burden: {quality_report.interpolated_burden_ratio:.3f}",
                    f"Peak position uncertainty: {quality_report.peak_position_uncertainty:.4f}",
                    f"Peak velocity uncertainty: {quality_report.peak_velocity_uncertainty:.4f}",
                    "",
                    "Experiment modules:",
                    *[
                        f"- {result.title}: "
                        + ", ".join(f"{metric.key}={metric.value:.4f} {metric.unit_label}".strip() for metric in result.metrics)
                        for result in analyzer_results
                    ],
                    "",
                    *[f"- {note}" for note in quality_report.notes],
                ]
            )
        )
        insight_lines = [
            f"QC badge: {summary.qc_badge}",
            f"Scientific confidence: {summary.scientific_confidence_mean:.3f}",
            f"Detected events: {summary.event_count}",
            f"Manual journal entries: {len(self.manual_event_markers)}",
            "",
            "Experiment modules:",
            *[
                f"- {result.title} ({result.confidence:.2f}): "
                + ", ".join(f"{metric.key}={metric.value:.4f} {metric.unit_label}".strip() for metric in result.metrics)
                for result in analyzer_results
            ],
            "",
            "Recommended next actions:",
            f"- {PRESET_BY_KEY.get(self.active_preset_key, PRESET_BY_KEY['general']).review_focus}",
            "- Export the research bundle once the review queue is clear.",
        ]
        self.insights_summary.setPlainText("\n".join(insight_lines))
        session = self._current_session()
        self.reproduce_summary.setPlainText(
            "\n".join(
                [
                    f"Export template: {session.export_preferences.report_template}",
                    f"Overlay export: {session.export_preferences.include_overlay}",
                    f"Plot export: {session.export_preferences.include_plots}",
                    f"Debug tracking: {session.export_preferences.include_debug_tracking}",
                    f"Session event count: {len(session.event_markers)}",
                    "",
                    "Bundle contents include summary, QC, session, manifest, reproduce command, and tables.",
                ]
            )
        )
        self.reproduce_command.setPlainText(build_reproduce_command(session))
        self._refresh_overview_dashboard()

    def export_results(self) -> None:
        if self.video_path is None or self.track_result is None or self.analysis_result is None:
            QMessageBox.warning(self, "Nothing to export", "Run an analysis first.")
            return
        output_dir = self._directory_dialog("Choose Export Directory")
        if not output_dir:
            return
        try:
            session = self._current_session()
        except Exception as exc:
            QMessageBox.critical(self, "Export failed", str(exc))
            return
        if self.multi_result is not None and len(self.analysis_tracks_by_id) > 1:
            bundle = export_multi_object_bundle(self.multi_result, session.calibration, session, output_dir)
            report_target = bundle["pairwise_metrics"]
        else:
            bundle = export_result_bundle(
                video_path=self.video_path,
                analysis=self.analysis_result,
                track_result=self.track_result,
                calibration=session.calibration,
                session=session,
                output_dir=output_dir,
                include_overlay=session.export_preferences.include_overlay,
                include_debug_tracking=session.tracking_config.debug_tracking,
                overlay_track_result=self.display_track_result,
                reference_track=self.reference_track_result,
            )
            report_target = bundle["report"]
        self.latest_export_bundle = bundle
        self.status_label.setText(f"Exported bundle to {output_dir}")
        self.selection_label.setText(f"Saved output to {report_target}")
        if self.latest_export_bundle is not None:
            self.reproduce_summary.setPlainText(
                "\n".join(
                    [
                        f"Export directory: {output_dir}",
                        f"Report: {self.latest_export_bundle.get('report')}",
                        f"Session: {self.latest_export_bundle.get('session')}",
                        f"Manifest: {self.latest_export_bundle.get('manifest')}",
                        f"Reproduce command: {self.latest_export_bundle.get('reproduce')}",
                    ]
                )
            )

    def load_session(self) -> None:
        path, _ = self._open_file_dialog("Load Session", "Session Files (*.json);;All Files (*)")
        if not path:
            return
        try:
            session = ProjectSession.load(path)
        except Exception as exc:
            QMessageBox.critical(self, "Load failed", str(exc))
            return
        self.video_path = session.video_path
        self.current_bbox = session.initial_bbox
        self.reference_bbox = session.reference_bbox
        self.scale_points = session.scale_points
        self.selected_start_frame = session.selected_start_frame
        self.selected_end_frame = session.selected_end_frame if session.selected_end_frame is not None else session.selected_start_frame
        self.corrections = session.corrections or []
        self.additional_objects = list(session.additional_objects)
        self.manual_event_markers = [marker for marker in session.event_markers if marker.origin == "manual"]
        self.latest_export_bundle = None
        self.object_list.clear()
        for item in self.additional_objects:
            self.object_list.addItem(f"{item.name} [{item.kind}]")
        self._refresh_manual_event_list()
        self.experiment_label_input.setText(session.metadata.experiment_label)
        self.trial_id_input.setText(session.metadata.trial_id)
        self.operator_input.setText(session.metadata.operator_name)
        self.tags_input.setText(", ".join(session.metadata.tags))
        self.notes_input.setText(session.metadata.notes)
        self.reference_length_input.setText(str(session.calibration.reference_length))
        self.unit_input.setText(session.calibration.unit_label)
        calibration_mode_index = self.calibration_mode_input.findData(session.calibration.mode)
        if calibration_mode_index >= 0:
            self.calibration_mode_input.setCurrentIndex(calibration_mode_index)
        self.origin_x_input.setText(str(session.calibration.origin_x_px))
        self.origin_y_input.setText(str(session.calibration.origin_y_px))
        self.axis_angle_input.setText(str(session.calibration.axis_angle_deg))
        self.marker_size_input.setText(str(session.calibration.pixel_distance))
        self.calibration_preset_input.setText(session.calibration.preset_name)
        self.homography_input.setText(" ".join(str(value) for value in (session.calibration.homography or ())))
        self.invert_x_input.setChecked(session.calibration.invert_x)
        self.invert_y_input.setChecked(session.calibration.invert_y)
        self.window_input.setText(str(session.analysis_config.smoothing_window))
        self.polyorder_input.setText(str(session.analysis_config.smoothing_polyorder))
        profile_index = self.profile_input.findData(session.tracking_config.profile.value)
        if profile_index >= 0:
            self.profile_input.setCurrentIndex(profile_index)
        self.robust_recovery_input.setChecked(session.tracking_config.robust_recovery)
        self.bidirectional_input.setChecked(session.tracking_config.bidirectional_refinement)
        self.debug_tracking = session.tracking_config.debug_tracking
        self.debug_tracking_input.setChecked(session.tracking_config.debug_tracking)
        self.include_overlay_input.setChecked(session.export_preferences.include_overlay)
        self.include_plots_input.setChecked(session.export_preferences.include_plots)
        report_index = self.report_template_input.findData(session.export_preferences.report_template)
        if report_index >= 0:
            self.report_template_input.setCurrentIndex(report_index)
        self.advanced_mode_toggle.setChecked(session.advanced_mode)
        self.dismissed_review_frames = set(session.review_state.dismissed_review_frames)
        self.selected_window_start = session.review_state.selected_window_start
        self.selected_window_end = session.review_state.selected_window_end
        with VideoSource(self.video_path) as video:
            self.video_metadata = video.metadata
        self.timeline_slider.setEnabled(True)
        self.timeline_slider.blockSignals(True)
        self.timeline_slider.setRange(0, max(self.video_metadata.frame_count - 1, 0))
        self.timeline_slider.setValue(session.review_state.last_frame_index or self.selected_start_frame)
        self.timeline_slider.blockSignals(False)
        self._show_frame(session.review_state.last_frame_index or self.selected_start_frame)
        self.track_result = None
        self.display_track_result = None
        self.reference_track_result = None
        self.analysis_result = None
        self.multi_result = None
        self.display_tracks_by_id = {}
        self.analysis_tracks_by_id = {}
        self.analyses_by_id = {}
        self.active_track_id = "primary"
        self.review_queue.clear()
        self.results_track_selector.clear()
        self.results_pair_selector.clear()
        self._refresh_timeline_summary()
        self._refresh_window_summary()
        self._refresh_state_summary()
        self.quality_summary.setPlainText("Quality report will appear after analysis.")
        self.pairwise_summary.setPlainText("Pairwise metrics will appear when multiple objects are tracked.")
        self.insights_summary.setPlainText("Analysis insights will appear after you run a trial.")
        self.reproduce_summary.setPlainText("Reproducibility notes will appear after analysis.")
        self.reproduce_command.setPlainText("tracker-ai analyze ...")
        self.events_table.setRowCount(0)
        self._refresh_workflow_summary()
        self.status_label.setText(
            f"Loaded session from {Path(path).name}. Re-run analysis to restore {len(self.corrections)} correction anchor(s)."
        )
        self._add_video_to_workspace(session.video_path, session_path=path)
        self._refresh_measurement_views()
        self._show_workflow_page("overview")

    def _jump_to_next_problem_frame(self) -> None:
        if self.track_result is None:
            return
        observations = self.track_result.observations
        for observation in observations:
            if observation.frame_index <= self.current_frame_index:
                continue
            if observation.frame_index in self.dismissed_review_frames:
                continue
            if observation.lost or observation.state != "tracking" or observation.confidence < 0.35:
                self._show_frame(observation.frame_index)
                self.status_label.setText(f"Jumped to review frame {observation.frame_index}.")
                self._show_workflow_page("review")
                return
        self.status_label.setText("No later suspect or lost frame was found.")
