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

        // 1. Stride Length: Farthest distance between ankle nodes
        let stridePixels = maximumStrideDistance(in: frames)
        let pixelsToFeet = estimatePixelsToFeet(in: frames)
        let strideFeet = stridePixels.map { $0 * pixelsToFeet }

        // 2. Release Point & Speed: Max wrist velocity frame
        let speedAnalysis = calculateSpeedAndRelease(in: frames, pixelsToFeet: pixelsToFeet)
        
        // 3. Arm Slot: Angle between wrist and non-dominant shoulder at release
        let armSlotAnalysis = calculateArmSlotAtRelease(in: frames, releaseIndex: speedAnalysis.releaseIndex)

        return ThrowMetrics(
            relativeStridePixels: stridePixels,
            releasePointHeight: armSlotAnalysis.releaseHeight,
            shoulderAngleDegrees: armSlotAnalysis.shoulderAngle,
            armSlotDegrees: armSlotAnalysis.armSlotDegrees,
            armSlotLabel: armSlotLabel(for: armSlotAnalysis.armSlotDegrees),
            estimatedPitchSpeedMPH: speedAnalysis.speedMPH,
            strideLengthFeet: strideFeet,
            releaseFrameIndex: speedAnalysis.releaseIndex
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

    static func calculateSpeedAndRelease(in frames: [PerFrameLandmarks], pixelsToFeet: Double) -> (speedMPH: Double?, releaseIndex: Int?) {
        var maxVelocity = 0.0
        var releaseIndex: Int? = nil
        
        // Determine which wrist is moving faster to identify throwing arm
        let isRightHanded = detectIfRightHanded(in: frames)
        let wristName = isRightHanded ? "rightWrist" : "leftWrist"
        
        for i in 0..<(frames.count - 1) {
            guard let w1 = point(named: wristName, in: frames[i].landmarks),
                  let w2 = point(named: wristName, in: frames[i+1].landmarks) else { continue }
            
            let dist = distance(from: w1, to: w2)
            let time = frames[i+1].timestamp - frames[i].timestamp
            guard time > 0 else { continue }
            
            let velocity = dist / time
            if velocity > maxVelocity {
                maxVelocity = velocity
                releaseIndex = i
            }
        }
        
        guard let idx = releaseIndex, idx + 1 < frames.count else { return (nil, nil) }
        
        // Calculate speed using release frame and the one after
        guard let wStart = point(named: wristName, in: frames[idx].landmarks),
              let wEnd = point(named: wristName, in: frames[idx+1].landmarks) else { return (nil, idx) }
        
        let pixelDist = distance(from: wStart, to: wEnd)
        let feetDist = pixelDist * pixelsToFeet
        let timeSec = frames[idx+1].timestamp - frames[idx].timestamp
        
        let speedMPH = (feetDist / timeSec) * 0.681818
        return (speedMPH, idx)
    }

    static func calculateArmSlotAtRelease(in frames: [PerFrameLandmarks], releaseIndex: Int?) -> (armSlotDegrees: Double?, releaseHeight: Double?, shoulderAngle: Double?) {
        guard let idx = releaseIndex else { return (nil, nil, nil) }
        let frame = frames[idx]
        
        let isRightHanded = detectIfRightHanded(in: frames)
        let throwingWristName = isRightHanded ? "rightWrist" : "leftWrist"
        let nonDominantShoulderName = isRightHanded ? "leftShoulder" : "rightShoulder"
        let dominantShoulderName = isRightHanded ? "rightShoulder" : "leftShoulder"
        
        guard let wrist = point(named: throwingWristName, in: frame.landmarks),
              let nonDomShoulder = point(named: nonDominantShoulderName, in: frame.landmarks),
              let domShoulder = point(named: dominantShoulderName, in: frame.landmarks) else {
            return (nil, nil, nil)
        }
        
        // Arm Slot: Angle of line between wrist and non-dominant shoulder
        // 0 = sidearm (horizontal), 90 = over-the-top (vertical up), -90 = submarine (vertical down)
        let dx = wrist.x - nonDomShoulder.x
        let dy = -(wrist.y - nonDomShoulder.y) // Invert Y for standard Cartesian
        
        // Adjust for handedness: if right-handed, sidearm is positive X. If left-handed, sidearm is negative X.
        let adjustedDx = isRightHanded ? dx : -dx
        let radians = atan2(dy, abs(adjustedDx))
        let degrees = radians * 180 / .pi
        
        let shoulderAngle = angleFromHorizontal(from: domShoulder, to: nonDomShoulder)
        
        return (degrees, Double(wrist.y), shoulderAngle)
    }

    static func detectIfRightHanded(in frames: [PerFrameLandmarks]) -> Bool {
        // Simple heuristic: which wrist travels further in X direction?
        var rightXDist = 0.0
        var leftXDist = 0.0
        
        guard let firstFrame = frames.first, let lastFrame = frames.last else { return true }
        
        if let r1 = point(named: "rightWrist", in: firstFrame.landmarks),
           let r2 = point(named: "rightWrist", in: lastFrame.landmarks) {
            rightXDist = abs(r2.x - r1.x)
        }
        
        if let l1 = point(named: "leftWrist", in: firstFrame.landmarks),
           let l2 = point(named: "leftWrist", in: lastFrame.landmarks) {
            leftXDist = abs(l2.x - l1.x)
        }
        
        return rightXDist >= leftXDist
    }

    static func armSlotLabel(for degrees: Double?) -> String {
        guard let degrees else {
            return "Not Calculated"
        }

        // Labeling based on user request convention:
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
}
