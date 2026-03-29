from __future__ import annotations

from pathlib import Path
import tempfile
import sys


def _ensure_runtime_dirs() -> None:
    cache_root = Path(tempfile.gettempdir()) / "tracker_ai_runtime"
    cache_root.mkdir(parents=True, exist_ok=True)
    if not cache_root.exists() or not cache_root.is_dir():
        raise RuntimeError("Unable to prepare a writable runtime directory.")


def main() -> int:
    try:
        _ensure_runtime_dirs()
    except Exception as exc:
        print(f"Startup check failed: {exc}")
        return 1
    try:
        from .ui.app import run
    except ModuleNotFoundError as exc:
        missing = exc.name or "PySide6"
        print(
            "The desktop UI dependencies are not installed. "
            f"Missing module: {missing}. Install the project dependencies and rerun."
        )
        return 1
    return run(sys.argv)


if __name__ == "__main__":
    raise SystemExit(main())
