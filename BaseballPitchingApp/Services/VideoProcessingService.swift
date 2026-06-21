@preconcurrency import AVFoundation
import Foundation

actor VideoProcessingService {
    struct ProcessedThrowData: Sendable {
        let landmarks: [PerFrameLandmarks]
        let metrics: ThrowMetrics
    }

    enum VideoProcessingError: LocalizedError {
        case missingVideoTrack
        case frameExtractionFailed
        case processingCancelled

        var errorDescription: String? {
            switch self {
            case .missingVideoTrack:
                return "The recorded file does not contain a readable video track."
            case .frameExtractionFailed:
                return "The recorded file could not be converted into upright frames for pose tracking."
            case .processingCancelled:
                return "Video processing was cancelled."
            }
        }
    }

    private let poseDetectionService: PoseDetectionService
    private let maximumSampleRate: Double = 60
    private let minimumSampleRate: Double = 30

    init(poseDetectionService: PoseDetectionService = PoseDetectionService()) {
        self.poseDetectionService = poseDetectionService
    }

    func processVideo(
        at url: URL,
        progress: (@Sendable (Double) async -> Void)? = nil
    ) async throws -> [ProcessedThrowData] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)

        guard let videoTrack = tracks.first else {
            throw VideoProcessingError.missingVideoTrack
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let sampleTimes = try await sampleTimes(for: videoTrack, duration: duration)
        var allFrames: [PerFrameLandmarks] = []
        allFrames.reserveCapacity(sampleTimes.count)

        // 1. Initial Pose Detection for the entire video
        for (index, time) in sampleTimes.enumerated() {
            try Task.checkCancellation()

            let cgImage: CGImage
            do {
                cgImage = try await generateCGImage(with: generator, at: time)
            } catch {
                continue
            }

            let landmarks = try await poseDetectionService.detectLandmarks(
                in: PoseDetectionService.SendableCGImage(image: cgImage),
                frameIndex: index,
                timestamp: time
            )
            allFrames.append(landmarks)

            if let progress, durationSeconds.isFinite, durationSeconds > 0 {
                let normalized = min(max(time.seconds / durationSeconds, 0), 1)
                await progress(normalized * 0.8) // Use 80% for initial detection
            }
        }

        if Task.isCancelled {
            throw VideoProcessingError.processingCancelled
        }

        // 2. Split into individual pitches
        let pitchSegments = detectPitchSegments(in: allFrames)
        var results: [ProcessedThrowData] = []
        
        for (index, segment) in pitchSegments.enumerated() {
            let metrics = MetricsCalculator.calculateMetrics(from: segment)
            var updatedMetrics = metrics
            updatedMetrics.pitchNumber = index + 1
            results.append(ProcessedThrowData(landmarks: segment, metrics: updatedMetrics))
        }

        if let progress {
            await progress(1.0)
        }

        return results
    }

    private func detectPitchSegments(in frames: [PerFrameLandmarks]) -> [[PerFrameLandmarks]] {
        // A pitch segment is defined by high wrist velocity
        // We look for peaks in velocity and take a window around them
        let velocityThreshold = 5.0 // Heuristic for "action"
        var segments: [[PerFrameLandmarks]] = []
        var currentSegment: [PerFrameLandmarks] = []
        var framesSinceAction = 0
        let maxGap = 30 // frames of inactivity to end a segment
        
        let isRightHanded = MetricsCalculator.detectIfRightHanded(in: frames)
        let wristName = isRightHanded ? "rightWrist" : "leftWrist"
        
        for i in 0..<(frames.count - 1) {
            let f1 = frames[i]
            let f2 = frames[i+1]
            
            guard let w1 = MetricsCalculator.point(named: wristName, in: f1.landmarks),
                  let w2 = MetricsCalculator.point(named: wristName, in: f2.landmarks) else {
                if !currentSegment.isEmpty {
                    framesSinceAction += 1
                    currentSegment.append(f1)
                }
                continue
            }
            
            let dist = MetricsCalculator.distance(from: w1, to: w2)
            let time = f2.timestamp - f1.timestamp
            let velocity = time > 0 ? dist / time : 0
            
            if velocity > velocityThreshold {
                if currentSegment.isEmpty {
                    // Start segment a bit before the action (wind-up)
                    let startIdx = max(0, i - 15)
                    currentSegment = Array(frames[startIdx...i])
                } else {
                    currentSegment.append(f1)
                }
                framesSinceAction = 0
            } else {
                if !currentSegment.isEmpty {
                    currentSegment.append(f1)
                    framesSinceAction += 1
                    
                    if framesSinceAction > maxGap {
                        // End segment
                        if currentSegment.count > 20 { // Minimum pitch duration
                            segments.append(currentSegment)
                        }
                        currentSegment = []
                        framesSinceAction = 0
                    }
                }
            }
        }
        
        // Handle last segment
        if !currentSegment.isEmpty && currentSegment.count > 20 {
            segments.append(currentSegment)
        }
        
        return segments
    }

    private func sampleTimes(for videoTrack: AVAssetTrack, duration: CMTime) async throws -> [CMTime] {
        let durationSeconds = duration.seconds
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            return []
        }

        let nominalFrameRate = Double(try await videoTrack.load(.nominalFrameRate))
        let sampleRate = min(max(nominalFrameRate / 3, minimumSampleRate), maximumSampleRate)
        let frameCount = max(Int((durationSeconds * sampleRate).rounded(.up)), 1)

        return (0..<frameCount).map { frameIndex in
            CMTime(seconds: Double(frameIndex) / sampleRate, preferredTimescale: 600)
        }
    }

    private func generateCGImage(with generator: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? VideoProcessingError.frameExtractionFailed)
                }
            }
        }
    }
}
