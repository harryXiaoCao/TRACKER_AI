# PyInstaller spec for the macOS Tracker AI release candidate.

from pathlib import Path

project_root = Path.cwd()

datas = [
    (str(project_root / "README.md"), "."),
    (str(project_root / "environment.yml"), "."),
]

hiddenimports = [
    "PySide6.QtCore",
    "PySide6.QtGui",
    "PySide6.QtWidgets",
    "pyqtgraph",
]

a = Analysis(
    ["src/tracker_ai/main.py"],
    pathex=[str(project_root / "src")],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="TrackerAI",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    name="TrackerAI",
)
app = BUNDLE(
    coll,
    name="TrackerAI.app",
    icon=None,
    bundle_identifier="ai.tracker.releasecandidate",
)

