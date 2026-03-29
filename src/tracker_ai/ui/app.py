from __future__ import annotations

from PySide6.QtWidgets import QApplication

from .main_window import MainWindow


def run(argv: list[str]) -> int:
    app = QApplication(argv)
    window = MainWindow()
    window.show()
    return app.exec()

