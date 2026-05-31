@preconcurrency import CoreGraphics
@preconcurrency import CoreMedia
import Foundation
import MediaPipeTasksVision
import UIKit

actor PoseDetectionService {
    enum PoseDetectionError: LocalizedError {
        case modelMissing
        case landmarkerInitializationFailed

        var errorDescription: String? {
            switch self {
            case .modelMissing:
                return "The MediaPipe pose model is missing from the app bundle."
            case .landmarkerInitializationFailed:
                return "MediaPipe Pose Landmarker could not be initialized."
            }
        }
    }

    struct SendableCGImage: @unchecked Sendable {
        let image: CGImage
    }

    private let minimumConfidence: Float = 0.5
    private var poseLandmarker: PoseLandmarker?

    private let supportedJoints: [(index: Int, label: String)] = [
        (11, "leftShoulder"),
        (12, "rightShoulder"),
        (13, "leftElbow"),
        (14, "rightElbow"),
        (15, "leftWrist"),
        (16, "rightWrist"),
        (23, "leftHip"),
        (24, "rightHip"),
        (25, "leftKnee"),
        (26, "rightKnee"),
        (27, "leftAnkle"),
        (28, "rightAnkle"),
    ]

    func detectLandmarks(
        in image: SendableCGImage,
        frameIndex: Int,
        timestamp: CMTime
    ) throws -> PerFrameLandmarks {
        let landmarker = try landmarker()
        let mediaPipeImage = try MPImage(uiImage: UIImage(cgImage: image.image))
        let timestampMilliseconds = Int(timestamp.seconds * 1_000)
        let result = try landmarker.detect(videoFrame: mediaPipeImage, timestampInMilliseconds: timestampMilliseconds)

        guard let pose = result.landmarks.first else {
            return PerFrameLandmarks(
                frameIndex: frameIndex,
                timestamp: timestamp.seconds,
                landmarks: []
            )
        }

        let landmarks = supportedJoints.compactMap { joint -> BodyLandmark? in
            guard pose.indices.contains(joint.index) else {
                return nil
            }

            let landmark = pose[joint.index]
            let confidence = confidenceScore(for: landmark)
            guard confidence >= minimumConfidence else {
                return nil
            }

            return BodyLandmark(
                jointName: joint.label,
                x: CGFloat(landmark.x),
                y: CGFloat(landmark.y),
                confidence: confidence
            )
        }

        return PerFrameLandmarks(
            frameIndex: frameIndex,
            timestamp: timestamp.seconds,
            landmarks: landmarks
        )
    }

    private func landmarker() throws -> PoseLandmarker {
        if let poseLandmarker {
            return poseLandmarker
        }

        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker_heavy", ofType: "task") else {
            throw PoseDetectionError.modelMissing
        }

        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .video
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.5
        options.minPosePresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5

        guard let landmarker = try? PoseLandmarker(options: options) else {
            throw PoseDetectionError.landmarkerInitializationFailed
        }

        poseLandmarker = landmarker
        return landmarker
    }

    private func confidenceScore(for landmark: NormalizedLandmark) -> Float {
        let visibility = landmark.visibility?.floatValue ?? 1
        let presence = landmark.presence?.floatValue ?? 1
        return min(visibility, presence)
    }
}
