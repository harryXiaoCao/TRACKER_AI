import SwiftUI

struct ReadinessRow: View {
    let title: String
    let complete: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(complete ? TrackerTheme.success : TrackerTheme.panelStroke)
                .frame(width: 10, height: 10)
            Text(title)
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Text(complete ? "Complete" : "Waiting")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(complete ? TrackerTheme.success : TrackerTheme.muted)
        }
    }
}

struct MacFormRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 120, alignment: .leading)
            content
        }
    }
}

struct NumericGrid: View {
    @Binding var box: BoundingBoxDraft
    @Binding var scale: ScaleLineDraft
    private let mode: String

    init(box: Binding<BoundingBoxDraft>) {
        _box = box
        _scale = .constant(ScaleLineDraft())
        mode = "box"
    }

    init(scale: Binding<ScaleLineDraft>) {
        _scale = scale
        _box = .constant(BoundingBoxDraft())
        mode = "scale"
    }

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            if mode == "box" {
                GridRow {
                    TextField("x", text: $box.x)
                    TextField("y", text: $box.y)
                }
                GridRow {
                    TextField("width", text: $box.width)
                    TextField("height", text: $box.height)
                }
            } else {
                GridRow {
                    TextField("x1", text: $scale.x1)
                    TextField("y1", text: $scale.y1)
                }
                GridRow {
                    TextField("x2", text: $scale.x2)
                    TextField("y2", text: $scale.y2)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
    }
}

struct AdditionalObjectGrid: View {
    @Binding var object: AdditionalObjectDraft

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                TextField("track_id", text: $object.trackID)
                TextField("display name", text: $object.name)
            }
            GridRow {
                TextField("kind", text: $object.kind)
                Spacer()
            }
            GridRow {
                TextField("x", text: $object.x)
                TextField("y", text: $object.y)
            }
            GridRow {
                TextField("width", text: $object.width)
                TextField("height", text: $object.height)
            }
        }
        .textFieldStyle(.roundedBorder)
    }
}
