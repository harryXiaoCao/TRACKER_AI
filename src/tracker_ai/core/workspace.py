from __future__ import annotations

from dataclasses import asdict, dataclass, field
import json
from pathlib import Path


@dataclass(frozen=True)
class WorkspaceItem:
    label: str
    video_path: str
    session_path: str = ""
    notes: str = ""


@dataclass(frozen=True)
class ResearchWorkspace:
    items: tuple[WorkspaceItem, ...] = ()
    active_video_path: str = ""
    title: str = "Tracker AI Workspace"

    def save(self, output_path: str | Path) -> Path:
        path = Path(output_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "title": self.title,
            "active_video_path": self.active_video_path,
            "items": [asdict(item) for item in self.items],
        }
        path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        return path

    @classmethod
    def load(cls, input_path: str | Path) -> "ResearchWorkspace":
        payload = json.loads(Path(input_path).read_text(encoding="utf-8"))
        return cls(
            title=str(payload.get("title", "Tracker AI Workspace")),
            active_video_path=str(payload.get("active_video_path", "")),
            items=tuple(WorkspaceItem(**item) for item in payload.get("items", [])),
        )
