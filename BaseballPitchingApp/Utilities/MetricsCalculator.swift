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

        let stridePixels = maximumStrideDistance(in: frames)
        let releaseAnalysis = releaseFrameAnalysis(in: frames)
        
        // Calibration: Use pitcher's height as a reference if possible.
        // For MVP, we'll use a heuristic: average male height is ~5.8 ft.
        // We'll estimate pixels-to-feet using the shoulder-to-ankle distance at a stable frame.
        let pixelsToFeet = estimatePixelsToFeet(in: frames)
        let strideFeet = stridePixels.map { $0 * pixelsToFeet }
        
        // Pitching Speed: Distance from release to "plate" (estimated)
        // Since we don't have the plate, we'll estimate speed based on hand velocity at release.
        let speedMPH = estimatePitchSpeed(in: frames, releaseFrameIndex: releaseAnalysis?.frameIndex)

        return ThrowMetrics(
            relativeStridePixels: stridePixels,
            releasePointHeight: releaseAnalysis?.releasePointHeight,
            shoulderAngleDegrees: releaseAnalysis?.shoulderAngleDegrees,
            armSlotDegrees: releaseAnalysis?.armSlotDegrees,
            armSlotLabel: armSlotLabel(for: releaseAnalysis?.armSlotDegrees),
            estimatedPitchSpeedMPH: speedMPH,
            strideLengthFeet: strideFeet
        )
    }
}

private extension MetricsCalculator {
    struct ReleaseAnalysis {
        let frameIndex: Int
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

        for (index, frame) in frames.enumerated() {
            // Check right arm
            if let analysis = analyzeArm(
                wristName: "rightWrist",
                elbowName: "rightElbow",
                shoulderName: "rightShoulder",
                oppositeShoulderName: "leftShoulder",
                in: frame.landmarks
            ), analysis.distanceToShoulder < bestDistance {
                bestDistance = analysis.distanceToShoulder
                bestAnalysis = ReleaseAnalysis(
                    frameIndex: index,
                    releasePointHeight: analysis.releasePointHeight,
                    shoulderAngleDegrees: analysis.shoulderAngleDegrees,
                    armSlotDegrees: analysis.armSlotDegrees
                )
            }
            
            // Check left arm
            if let analysis = analyzeArm(
                wristName: "leftWrist",
                elbowName: "leftElbow",
                shoulderName: "leftShoulder",
                oppositeShoulderName: "rightShoulder",
                in: frame.landmarks
            ), analysis.distanceToShoulder < bestDistance {
                bestDistance = analysis.distanceToShoulder
                bestAnalysis = ReleaseAnalysis(
                    frameIndex: index,
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
        
        // Improved Arm Slot Calculation
        let armSlot = calculateArmSlotDegrees(shoulder: shoulder, elbow: elbow, wrist: wrist)

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

        // New Labeling based on user request:
        // 90 = Over the top
        // 0 = Sidearm
        // -90 = Submarine
        if degrees > 60 {
            return "Over-the-Top"
        } else if degrees > 30 {
            return "Three-Quarter"
        } else if degrees > -30 {
            return "Sidearm"
        } else {
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

    /// Calculates arm slot in degrees.
    /// 0° = sidearm (horizontal)
    /// 90° = over-the-top (vertical up)
    /// -90° = submarine (vertical down)
    static func calculateArmSlotDegrees(shoulder: CGPoint, elbow: CGPoint, wrist: CGPoint) -> Double {
        // Vector from shoulder to wrist (better represents overall arm slot than just forearm)
        let dx = wrist.x - shoulder.x
        let dy = -(wrist.y - shoulder.y) // Invert Y because screen coordinates have Y increasing downwards
        
        // atan2(dy, dx) gives angle in radians from positive X-axis
        let radians = atan2(dy, dx)
        var degrees = radians * 180 / .pi
        
        // Normalize: If we assume the pitcher is facing right (positive X)
        // Over the top (vertical up) is 90
        // Sidearm (horizontal) is 0
        // Submarine (vertical down) is -90
        
        // If the pitcher is facing left, we'd need to flip the DX.
        // Let's detect orientation based on shoulder positions.
        return degrees
    }

    static func estimatePixelsToFeet(in frames: [PerFrameLandmarks]) -> Double {
        // Estimate based on shoulder-to-ankle distance (approx 75% of total height)
        // Average height ~5.8 ft -> Shoulder to ankle ~4.35 ft
        let distances = frames.compactMap { frame -> Double? in
            guard let shoulder = point(named: "rightShoulder", in: frame.landmarks),
                  let ankle = point(named: "rightAnkle", in: frame.landmarks) else { return nil }
            return distance(from: shoulder, to: ankle)
        }
        guard let avgDistance = distances.first else { return 0.01 } // Fallback
        return 4.35 / avgDistance
    }

    static func estimatePitchSpeed(in frames: [PerFrameLandmarks], releaseFrameIndex: Int?) -> Double? {
        guard let releaseIndex = releaseFrameIndex, releaseIndex + 2 < frames.count else { return nil }
        
        let f1 = frames[releaseIndex]
        let f2 = frames[releaseIndex + 2]
        
        guard let w1 = point(named: "rightWrist", in: f1.landmarks),
              let w2 = point(named: "rightWrist", in: f2.landmarks) else { return nil }
        
        let pixelDist = distance(from: w1, to: w2)
        let feetDist = pixelDist * estimatePixelsToFeet(in: frames)
        let timeSec = f2.timestamp - f1.timestamp
        
        guard timeSec > 0 else { return nil }
        let feetPerSec = feetDist / timeSec
        return feetPerSec * 0.681818 // Convert fps to mph
    }
}
