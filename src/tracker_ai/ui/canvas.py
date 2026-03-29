from __future__ import annotations

from dataclasses import dataclass

from PySide6.QtCore import QPointF, QRectF, Qt, Signal
from PySide6.QtGui import QBrush, QColor, QImage, QPen, QPixmap
from PySide6.QtWidgets import QGraphicsLineItem, QGraphicsPixmapItem, QGraphicsRectItem, QGraphicsScene, QGraphicsSimpleTextItem, QGraphicsView

from ..core.tracking import BBox, TrackingObservation


class VideoCanvas(QGraphicsView):
    bbox_drawn = Signal(object)
    scale_drawn = Signal(object)

    def __init__(self) -> None:
        super().__init__()
        self.setScene(QGraphicsScene(self))
        self.setRenderHints(self.renderHints())
        self.setMouseTracking(True)
        self.setAlignment(Qt.AlignCenter)
        self.setTransformationAnchor(QGraphicsView.AnchorUnderMouse)
        self.setResizeAnchor(QGraphicsView.AnchorViewCenter)
        self.setDragMode(QGraphicsView.ScrollHandDrag)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        self.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)

        self._mode = "none"
        self._frame_size = (0, 0)
        self._drag_start: QPointF | None = None
        self._zoom_level = 1.0
        self._pixmap_item = QGraphicsPixmapItem()
        self.scene().addItem(self._pixmap_item)

        self._target_item = QGraphicsRectItem()
        self._target_item.setPen(QPen(QColor("#F4B040"), 2))
        self.scene().addItem(self._target_item)

        self._reference_item = QGraphicsRectItem()
        self._reference_item.setPen(QPen(QColor("#2B6CB0"), 2))
        self.scene().addItem(self._reference_item)

        self._track_item = QGraphicsRectItem()
        self._track_item.setPen(QPen(QColor("#00C853"), 2))
        self.scene().addItem(self._track_item)

        self._scale_item = QGraphicsLineItem()
        self._scale_item.setPen(QPen(QColor("#E85D04"), 3))
        self.scene().addItem(self._scale_item)

        self._drag_rect_item = QGraphicsRectItem()
        self._drag_rect_item.setPen(QPen(QColor("#9AC5F4"), 2, Qt.DashLine))
        self.scene().addItem(self._drag_rect_item)

        self._drag_line_item = QGraphicsLineItem()
        self._drag_line_item.setPen(QPen(QColor("#9AC5F4"), 2, Qt.DashLine))
        self.scene().addItem(self._drag_line_item)

        self._status_item = QGraphicsSimpleTextItem()
        self._status_item.setBrush(QBrush(QColor("#F7F7F7")))
        self.scene().addItem(self._status_item)
        self.clear_overlays()

    def set_mode(self, mode: str) -> None:
        self._mode = mode
        self.setDragMode(QGraphicsView.NoDrag if mode in {"draw_bbox", "draw_scale"} else QGraphicsView.ScrollHandDrag)

    def set_frame(self, frame) -> None:
        rgb = frame[:, :, ::-1].copy()
        height, width, channels = rgb.shape
        self._frame_size = (width, height)
        image = QImage(rgb.data, width, height, channels * width, QImage.Format_RGB888)
        self._pixmap_item.setPixmap(QPixmap.fromImage(image.copy()))
        self.scene().setSceneRect(0, 0, width, height)
        self._status_item.setPos(12, 12)
        self.fit_to_view()

    def clear_overlays(self) -> None:
        self._target_item.hide()
        self._reference_item.hide()
        self._track_item.hide()
        self._scale_item.hide()
        self._drag_rect_item.hide()
        self._drag_line_item.hide()
        self._status_item.setText("")

    def set_target_bbox(self, bbox: BBox | None, *, correction: bool = False) -> None:
        if bbox is None:
            self._target_item.hide()
            return
        x, y, w, h = bbox.to_int_tuple()
        self._target_item.setRect(x, y, w, h)
        self._target_item.setPen(QPen(QColor("#F4B040" if correction else "#52B788"), 2))
        self._target_item.show()

    def set_reference_bbox(self, bbox: BBox | None) -> None:
        if bbox is None:
            self._reference_item.hide()
            return
        x, y, w, h = bbox.to_int_tuple()
        self._reference_item.setRect(x, y, w, h)
        self._reference_item.setPen(QPen(QColor("#2B6CB0"), 2))
        self._reference_item.show()

    def set_scale_points(self, points: tuple[float, float, float, float] | None) -> None:
        if points is None:
            self._scale_item.hide()
            return
        x1, y1, x2, y2 = points
        self._scale_item.setLine(x1, y1, x2, y2)
        self._scale_item.show()

    def set_observation(self, observation: TrackingObservation | None) -> None:
        if observation is None:
            self._track_item.hide()
            self._status_item.setText("")
            return
        x, y, w, h = observation.bbox.to_int_tuple()
        color = "#F4B040" if observation.corrected else ("#00C853" if not observation.lost else "#FF6B35")
        self._track_item.setRect(x, y, w, h)
        self._track_item.setPen(QPen(QColor(color), 2))
        self._track_item.show()
        tags = []
        if observation.corrected:
            tags.append("corrected")
        if observation.lost:
            tags.append("lost")
        if observation.state not in {"tracking"}:
            tags.append(observation.state)
        if observation.failure_reason:
            tags.append(observation.failure_reason)
        suffix = f" ({', '.join(tags)})" if tags else ""
        self._status_item.setText(f"t={observation.timestamp:.3f}s conf={observation.confidence:.2f}{suffix}")

    def _clamp_point(self, point: QPointF) -> QPointF:
        width, height = self._frame_size
        return QPointF(
            min(max(point.x(), 0.0), max(width - 1.0, 0.0)),
            min(max(point.y(), 0.0), max(height - 1.0, 0.0)),
        )

    def _event_point(self, event) -> QPointF:
        return self._clamp_point(self.mapToScene(event.position().toPoint()))

    def fit_to_view(self) -> None:
        if self.scene() is None or self.scene().sceneRect().isNull():
            return
        self.resetTransform()
        rect = self.scene().sceneRect()
        if not rect.isNull():
            self.fitInView(rect, Qt.KeepAspectRatio)
        transform = self.transform()
        self._zoom_level = max(transform.m11(), 1e-6)

    def zoom_in(self) -> None:
        self._apply_zoom(1.2)

    def zoom_out(self) -> None:
        self._apply_zoom(1 / 1.2)

    def _apply_zoom(self, factor: float) -> None:
        next_zoom = self._zoom_level * factor
        if next_zoom < 0.2 or next_zoom > 8.0:
            return
        self.scale(factor, factor)
        self._zoom_level = next_zoom

    def wheelEvent(self, event) -> None:
        if event.modifiers() & Qt.ControlModifier:
            delta = event.angleDelta().y()
            if delta > 0:
                self.zoom_in()
            elif delta < 0:
                self.zoom_out()
            event.accept()
            return
        super().wheelEvent(event)

    def mousePressEvent(self, event) -> None:
        if self._mode in {"draw_bbox", "draw_scale"} and self._frame_size != (0, 0):
            self._drag_start = self._event_point(event)
            if self._mode == "draw_bbox":
                self._drag_rect_item.setRect(self._drag_start.x(), self._drag_start.y(), 1, 1)
                self._drag_rect_item.show()
            else:
                self._drag_line_item.setLine(self._drag_start.x(), self._drag_start.y(), self._drag_start.x(), self._drag_start.y())
                self._drag_line_item.show()
            return
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event) -> None:
        if self._drag_start is None:
            super().mouseMoveEvent(event)
            return
        point = self._event_point(event)
        if self._mode == "draw_bbox":
            x1, y1 = self._drag_start.x(), self._drag_start.y()
            x2, y2 = point.x(), point.y()
            self._drag_rect_item.setRect(min(x1, x2), min(y1, y2), abs(x2 - x1), abs(y2 - y1))
        elif self._mode == "draw_scale":
            self._drag_line_item.setLine(self._drag_start.x(), self._drag_start.y(), point.x(), point.y())
        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event) -> None:
        if self._drag_start is None:
            super().mouseReleaseEvent(event)
            return
        point = self._event_point(event)
        start = self._drag_start
        self._drag_start = None
        if self._mode == "draw_bbox":
            self._drag_rect_item.hide()
            bbox = BBox(
                x=min(start.x(), point.x()),
                y=min(start.y(), point.y()),
                width=max(abs(point.x() - start.x()), 4.0),
                height=max(abs(point.y() - start.y()), 4.0),
            )
            self.bbox_drawn.emit(bbox)
        elif self._mode == "draw_scale":
            self._drag_line_item.hide()
            self.scale_drawn.emit((start.x(), start.y(), point.x(), point.y()))
        super().mouseReleaseEvent(event)
