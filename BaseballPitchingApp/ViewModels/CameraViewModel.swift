@preconcurrency import AVFoundation
import Combine
import Foundation
import SwiftData

@MainActor
final class CameraViewModel: ObservableObject {
    @Published var errorMessage: String?
    @Published private(set) var statusText = "Preparing camera..."
    @Published private(set) var elapsedTimeText = "00:00"
    @Published private(set) var isRecording = false
    @Published private(set) var isProcessing = false
    @Published private(set) var processingProgressText = ""
    @Published private(set) var savedVideoURL: URL?
    @Published private(set) var processedLandmarks: [PerFrameLandmarks] = []
    @Published var playbackSession: ThrowSession?

    let cameraService: CameraService
    let previewSession: AVCaptureSession

    private var recordingTask: Task<Void, Never>?
    private var recordingStartedAt: Date?
    private let videoProcessingService: VideoProcessingService
    private var hasPersistedPlaybackSession = false

    init(
        cameraService: CameraService = CameraService(),
        videoProcessingService: VideoProcessingService = VideoProcessingService()
    ) {
        self.cameraService = cameraService
        self.previewSession = cameraService.previewSession
        self.videoProcessingService = videoProcessingService
    }

    deinit {
        recordingTask?.cancel()
    }

    func onAppear() {
        Task {
            do {
                try await cameraService.prepareSession()
                await cameraService.startSession()
                statusText = "Camera ready. Record a throw."
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                statusText = "Camera unavailable."
            }
        }
    }

    func onDisappear() {
        recordingTask?.cancel()
        recordingTask = nil
        isRecording = false
        isProcessing = false
        elapsedTimeText = "00:00"

        Task {
            await cameraService.stopSession()
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        Task {
            do {
                try await cameraService.startRecording()
                recordingStartedAt = Date()
                savedVideoURL = nil
                processedLandmarks = []
                playbackSession = nil
                hasPersistedPlaybackSession = false
                isRecording = true
                isProcessing = false
                processingProgressText = ""
                errorMessage = nil
                statusText = "Recording..."
                startElapsedTimer()
            } catch {
                errorMessage = error.localizedDescription
                statusText = "Unable to start recording."
            }
        }
    }

    private func stopRecording() {
        Task {
            do {
                let url = try await cameraService.stopRecording()
                recordingTask?.cancel()
                recordingTask = nil
                isRecording = false
                savedVideoURL = url
                elapsedTimeText = "00:00"
                errorMessage = nil
                try await processRecordedVideo(at: url)
            } catch {
                errorMessage = error.localizedDescription
                statusText = "Unable to stop recording."
            }
        }
    }

    private func processRecordedVideo(at url: URL) async throws {
        isProcessing = true
        processingProgressText = "Processing 0%"
        statusText = "Analyzing recorded throw..."

        let landmarks = try await videoProcessingService.processVideo(at: url) { [weak self] progress in
            await MainActor.run {
                guard let self else {
                    return
                }

                let percent = Int((progress * 100).rounded())
                self.processingProgressText = "Processing \(percent)%"
            }
        }

        processedLandmarks = landmarks.landmarks
        playbackSession = ThrowSession(
            date: .now,
            videoURL: url.path(),
            metrics: landmarks.metrics,
            landmarks: landmarks.landmarks
        )
        isProcessing = false
        processingProgressText = landmarks.landmarks.isEmpty
            ? "Processing complete with no landmarks detected."
            : "Processing complete: \(landmarks.landmarks.count) sampled frames analyzed."
        statusText = "Saved to \(url.lastPathComponent)"
    }

    func persistPlaybackSessionIfNeeded(in modelContext: ModelContext) {
        guard let playbackSession, !hasPersistedPlaybackSession else {
            return
        }

        modelContext.insert(playbackSession)

        do {
            try modelContext.save()
            hasPersistedPlaybackSession = true
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Failed to save session."
        }
    }

    private func startElapsedTimer() {
        recordingTask?.cancel()
        elapsedTimeText = "00:00"

        recordingTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                guard let startedAt = self.recordingStartedAt else {
                    return
                }

                let elapsed = Int(Date().timeIntervalSince(startedAt))
                let minutes = elapsed / 60
                let seconds = elapsed % 60
                self.elapsedTimeText = String(format: "%02d:%02d", minutes, seconds)

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
