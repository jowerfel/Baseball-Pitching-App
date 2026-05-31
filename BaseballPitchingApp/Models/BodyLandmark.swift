import CoreGraphics
import Foundation

struct BodyLandmark: Codable, Hashable, Sendable {
    var jointName: String
    var x: CGFloat
    var y: CGFloat
    var confidence: Float
}

extension BodyLandmark {
    static let supportedJointNames: [String] = [
        "leftShoulder",
        "rightShoulder",
        "leftElbow",
        "rightElbow",
        "leftWrist",
        "rightWrist",
        "leftHip",
        "rightHip",
        "leftKnee",
        "rightKnee",
        "leftAnkle",
        "rightAnkle",
    ]
}

struct PerFrameLandmarks: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var frameIndex: Int
    var timestamp: TimeInterval
    var landmarks: [BodyLandmark]

    init(
        id: UUID = UUID(),
        frameIndex: Int,
        timestamp: TimeInterval,
        landmarks: [BodyLandmark]
    ) {
        self.id = id
        self.frameIndex = frameIndex
        self.timestamp = timestamp
        self.landmarks = landmarks
    }
}
