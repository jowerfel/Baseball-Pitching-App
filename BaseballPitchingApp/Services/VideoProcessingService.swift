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
    ) async throws -> ProcessedThrowData {
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

        let sampleTimes = sampleTimes(for: videoTrack, duration: duration)
        var processedFrames: [PerFrameLandmarks] = []
        processedFrames.reserveCapacity(sampleTimes.count)

        for (index, time) in sampleTimes.enumerated() {
            try Task.checkCancellation()

            let cgImage: CGImage
            do {
                cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            } catch {
                continue
            }

            let landmarks = try await poseDetectionService.detectLandmarks(
                in: PoseDetectionService.SendableCGImage(image: cgImage),
                frameIndex: index,
                timestamp: time
            )
            processedFrames.append(landmarks)

            if let progress, durationSeconds.isFinite, durationSeconds > 0 {
                let normalized = min(max(time.seconds / durationSeconds, 0), 1)
                await progress(normalized)
            }
        }

        if Task.isCancelled {
            throw VideoProcessingError.processingCancelled
        }

        if let progress {
            await progress(1)
        }

        guard !sampleTimes.isEmpty, !processedFrames.isEmpty else {
            throw VideoProcessingError.frameExtractionFailed
        }

        return ProcessedThrowData(
            landmarks: processedFrames,
            metrics: MetricsCalculator.calculateMetrics(from: processedFrames)
        )
    }

    private func sampleTimes(for videoTrack: AVAssetTrack, duration: CMTime) -> [CMTime] {
        let durationSeconds = duration.seconds
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            return []
        }

        let nominalFrameRate = Double(videoTrack.nominalFrameRate)
        let sampleRate = min(max(nominalFrameRate / 3, minimumSampleRate), maximumSampleRate)
        let frameCount = max(Int((durationSeconds * sampleRate).rounded(.up)), 1)

        return (0..<frameCount).map { frameIndex in
            CMTime(seconds: Double(frameIndex) / sampleRate, preferredTimescale: 600)
        }
    }
}
