import CoreGraphics
import Foundation

enum MetricsCalculator {
    static func defaultMetrics() -> ThrowMetrics {
        ThrowMetrics()
    }

    static func calculateMetrics(from frames: [PerFrameLandmarks]) -> ThrowMetrics {
        guard !frames.isEmpty else {
            return ThrowMetrics()
        }

        let stride = maximumStrideDistance(in: frames)
        let releaseAnalysis = releaseFrameAnalysis(in: frames)

        return ThrowMetrics(
            relativeStridePixels: stride,
            releasePointHeight: releaseAnalysis?.releasePointHeight,
            shoulderAngleDegrees: releaseAnalysis?.shoulderAngleDegrees,
            armSlotDegrees: releaseAnalysis?.armSlotDegrees,
            armSlotLabel: armSlotLabel(for: releaseAnalysis?.armSlotDegrees)
        )
    }
}

private extension MetricsCalculator {
    struct ReleaseAnalysis {
        let releasePointHeight: Double?
        let shoulderAngleDegrees: Double?
        let armSlotDegrees: Double?
    }

    static func maximumStrideDistance(in frames: [PerFrameLandmarks]) -> Double? {
        frames.compactMap { frame in
            guard
                let leftAnkle = point(named: "leftAnkle", in: frame.landmarks),
                let rightAnkle = point(named: "rightAnkle", in: frame.landmarks)
            else {
                return nil
            }

            return distance(from: leftAnkle, to: rightAnkle)
        }
        .max()
    }

    static func releaseFrameAnalysis(in frames: [PerFrameLandmarks]) -> ReleaseAnalysis? {
        var bestDistance = Double.greatestFiniteMagnitude
        var bestAnalysis: ReleaseAnalysis?

        for frame in frames {
            if let analysis = analyzeArm(
                wristName: "leftWrist",
                elbowName: "leftElbow",
                shoulderName: "leftShoulder",
                oppositeShoulderName: "rightShoulder",
                in: frame.landmarks
            ), analysis.distanceToShoulder < bestDistance {
                bestDistance = analysis.distanceToShoulder
                bestAnalysis = ReleaseAnalysis(
                    releasePointHeight: analysis.releasePointHeight,
                    shoulderAngleDegrees: analysis.shoulderAngleDegrees,
                    armSlotDegrees: analysis.armSlotDegrees
                )
            }

            if let analysis = analyzeArm(
                wristName: "rightWrist",
                elbowName: "rightElbow",
                shoulderName: "rightShoulder",
                oppositeShoulderName: "leftShoulder",
                in: frame.landmarks
            ), analysis.distanceToShoulder < bestDistance {
                bestDistance = analysis.distanceToShoulder
                bestAnalysis = ReleaseAnalysis(
                    releasePointHeight: analysis.releasePointHeight,
                    shoulderAngleDegrees: analysis.shoulderAngleDegrees,
                    armSlotDegrees: analysis.armSlotDegrees
                )
            }
        }

        return bestAnalysis
    }

    static func analyzeArm(
        wristName: String,
        elbowName: String,
        shoulderName: String,
        oppositeShoulderName: String,
        in landmarks: [BodyLandmark]
    ) -> (distanceToShoulder: Double, releasePointHeight: Double, shoulderAngleDegrees: Double, armSlotDegrees: Double)? {
        guard
            let wrist = point(named: wristName, in: landmarks),
            let elbow = point(named: elbowName, in: landmarks),
            let shoulder = point(named: shoulderName, in: landmarks),
            let oppositeShoulder = point(named: oppositeShoulderName, in: landmarks)
        else {
            return nil
        }

        let wristToShoulderDistance = distance(from: wrist, to: shoulder)
        let shoulderAngle = angleFromHorizontal(from: shoulder, to: oppositeShoulder)
        let armSlot = forearmAngleRelativeToVertical(from: elbow, to: wrist)

        return (
            distanceToShoulder: wristToShoulderDistance,
            releasePointHeight: Double(wrist.y),
            shoulderAngleDegrees: shoulderAngle,
            armSlotDegrees: armSlot
        )
    }

    static func armSlotLabel(for degrees: Double?) -> String {
        guard let degrees else {
            return "Not Calculated"
        }

        switch degrees {
        case ..<15:
            return "Over-the-Top"
        case 15..<45:
            return "Three-Quarter"
        case 45..<75:
            return "Sidearm"
        default:
            return "Submarine"
        }
    }

    static func point(named jointName: String, in landmarks: [BodyLandmark]) -> CGPoint? {
        guard let landmark = landmarks.first(where: { $0.jointName == jointName }) else {
            return nil
        }

        return CGPoint(x: landmark.x, y: landmark.y)
    }

    static func distance(from start: CGPoint, to end: CGPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return Double((dx * dx + dy * dy).squareRoot())
    }

    static func angleFromHorizontal(from start: CGPoint, to end: CGPoint) -> Double {
        let radians = atan2(end.y - start.y, end.x - start.x)
        return abs(Double(radians) * 180 / .pi)
    }

    static func forearmAngleRelativeToVertical(from elbow: CGPoint, to wrist: CGPoint) -> Double {
        let dx = wrist.x - elbow.x
        let dy = wrist.y - elbow.y
        let radians = atan2(dx, -dy)
        return abs(Double(radians) * 180 / .pi)
    }
}
