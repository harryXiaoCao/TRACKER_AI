import Foundation

enum CalibrationProfileError: LocalizedError, Equatable {
    case invalidReferenceLength
    case invalidPixelDistance
    case invalidHomographyValueCount(Int)

    var errorDescription: String? {
        switch self {
        case .invalidReferenceLength:
            return "reference_length must be positive"
        case .invalidPixelDistance:
            return "pixel_distance must be positive"
        case .invalidHomographyValueCount:
            return "homography must contain 9 values"
        }
    }
}

struct CalibrationProfile: Hashable {
    var referenceLength: Double
    var unitLabel: String
    var pixelDistance: Double
    var mode: String = "single_line"
    var originXPx: Double = 0
    var originYPx: Double = 0
    var axisAngleDeg: Double = 0
    var invertX = false
    var invertY = false
    var homography: [Double]? = nil
    var presetName = ""

    init(
        referenceLength: Double,
        unitLabel: String,
        pixelDistance: Double,
        mode: String = "single_line",
        originXPx: Double = 0,
        originYPx: Double = 0,
        axisAngleDeg: Double = 0,
        invertX: Bool = false,
        invertY: Bool = false,
        homography: [Double]? = nil,
        presetName: String = ""
    ) throws {
        guard referenceLength > 0 else {
            throw CalibrationProfileError.invalidReferenceLength
        }
        guard pixelDistance > 0 else {
            throw CalibrationProfileError.invalidPixelDistance
        }
        if let homography, homography.count != 9 {
            throw CalibrationProfileError.invalidHomographyValueCount(homography.count)
        }

        self.referenceLength = referenceLength
        self.unitLabel = unitLabel
        self.pixelDistance = pixelDistance
        self.mode = Self.normalizedMode(mode)
        self.originXPx = originXPx
        self.originYPx = originYPx
        self.axisAngleDeg = axisAngleDeg
        self.invertX = invertX
        self.invertY = invertY
        self.homography = homography
        self.presetName = presetName
    }

    var unitsPerPixel: Double {
        referenceLength / pixelDistance
    }

    func pixelsToUnits(_ value: Double) -> Double {
        value * unitsPerPixel
    }

    func transformPoint(xPx: Double, yPx: Double) -> (Double, Double) {
        let transformedPoint: (Double, Double)
        if let homography {
            transformedPoint = perspectiveTransform(point: (xPx, yPx), homography: homography)
        } else {
            transformedPoint = (xPx, yPx)
        }

        let translatedX = transformedPoint.0 - originXPx
        let translatedY = transformedPoint.1 - originYPx
        let theta = axisAngleDeg * .pi / 180
        var rotatedX = (translatedX * cos(theta)) + (translatedY * sin(theta))
        var rotatedY = (-translatedX * sin(theta)) + (translatedY * cos(theta))
        if invertX {
            rotatedX *= -1
        }
        if invertY {
            rotatedY *= -1
        }
        return (rotatedX * unitsPerPixel, rotatedY * unitsPerPixel)
    }

    static func fromPoints(
        x1: Double,
        y1: Double,
        x2: Double,
        y2: Double,
        referenceLength: Double,
        unitLabel: String
    ) throws -> CalibrationProfile {
        let pixelDistance = hypot(x2 - x1, y2 - y1)
        return try CalibrationProfile(
            referenceLength: referenceLength,
            unitLabel: unitLabel,
            pixelDistance: pixelDistance,
            mode: "single_line",
            originXPx: x1,
            originYPx: y1
        )
    }

    static func fromAxisPoints(
        originX: Double,
        originY: Double,
        axisX: Double,
        axisY: Double,
        referenceLength: Double,
        unitLabel: String,
        invertX: Bool = false,
        invertY: Bool = false
    ) throws -> CalibrationProfile {
        let pixelDistance = hypot(axisX - originX, axisY - originY)
        let axisAngleDeg = atan2(axisY - originY, axisX - originX) * 180 / .pi
        return try CalibrationProfile(
            referenceLength: referenceLength,
            unitLabel: unitLabel,
            pixelDistance: pixelDistance,
            mode: "two_axis",
            originXPx: originX,
            originYPx: originY,
            axisAngleDeg: axisAngleDeg,
            invertX: invertX,
            invertY: invertY
        )
    }

    static func fromMarkerSize(
        markerBBoxWidthPx: Double,
        referenceLength: Double,
        unitLabel: String,
        presetName: String = ""
    ) throws -> CalibrationProfile {
        try CalibrationProfile(
            referenceLength: referenceLength,
            unitLabel: unitLabel,
            pixelDistance: markerBBoxWidthPx,
            mode: "marker_size",
            presetName: presetName
        )
    }

    static func fromHomography(
        homography: [Double],
        referenceLength: Double,
        unitLabel: String,
        pixelDistance: Double,
        originXPx: Double = 0,
        originYPx: Double = 0,
        presetName: String = ""
    ) throws -> CalibrationProfile {
        try CalibrationProfile(
            referenceLength: referenceLength,
            unitLabel: unitLabel,
            pixelDistance: pixelDistance,
            mode: "homography",
            originXPx: originXPx,
            originYPx: originYPx,
            homography: homography,
            presetName: presetName
        )
    }

    static func normalizedMode(_ mode: String) -> String {
        let trimmed = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty || trimmed == "line" {
            return "single_line"
        }
        return trimmed
    }

    private func perspectiveTransform(point: (Double, Double), homography: [Double]) -> (Double, Double) {
        let matrix = homography.map(Float.init)
        let x = Float(point.0)
        let y = Float(point.1)
        let tx = (x * matrix[0]) + (y * matrix[1]) + matrix[2]
        let ty = (x * matrix[3]) + (y * matrix[4]) + matrix[5]
        let tz = (x * matrix[6]) + (y * matrix[7]) + matrix[8]
        let divisor = max(tz, 1e-6)
        return (Double(tx / divisor), Double(ty / divisor))
    }
}

extension CalibrationSnapshot {
    func makeCalibrationProfile() throws -> CalibrationProfile {
        try CalibrationProfile(
            referenceLength: referenceLength,
            unitLabel: unitLabel,
            pixelDistance: pixelDistance,
            mode: CalibrationProfile.normalizedMode(mode ?? "single_line"),
            originXPx: originXPx ?? 0,
            originYPx: originYPx ?? 0,
            axisAngleDeg: axisAngleDeg ?? 0,
            invertX: invertX ?? false,
            invertY: invertY ?? false,
            homography: homography,
            presetName: presetName ?? ""
        )
    }

    init(profile: CalibrationProfile) {
        self.referenceLength = profile.referenceLength
        self.unitLabel = profile.unitLabel
        self.pixelDistance = profile.pixelDistance
        self.mode = profile.mode
        self.originXPx = profile.originXPx
        self.originYPx = profile.originYPx
        self.axisAngleDeg = profile.axisAngleDeg
        self.invertX = profile.invertX
        self.invertY = profile.invertY
        self.homography = profile.homography
        self.presetName = profile.presetName.isEmpty ? nil : profile.presetName
    }
}
