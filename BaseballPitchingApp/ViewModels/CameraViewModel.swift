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
    @Published var detectedPitches: [ThrowSession] = []

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
                statusText = "Camera ready. Record your session."
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
                detectedPitches = []
                hasPersistedPlaybackSession = false
                isRecording = true
                isProcessing = false
                processingProgressText = ""
                errorMessage = nil
                statusText = "Recording session..."
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
    func uploadedVideo(_ videoURL: URL){
        Task {
            do {
                savedVideoURL = videoURL
                elapsedTimeText = "00:00"
                errorMessage = nil
                try await processRecordedVideo(at: videoURL)
            } catch {
                errorMessage = error.localizedDescription
                statusText = "Unable to stop recording."
            }
        }

    }
    
    
    
    private func processRecordedVideo(at url: URL) async throws {
        isProcessing = true
        processingProgressText = "Processing 0%"
        statusText = "Splitting and analyzing pitches..."

        let pitchData = try await videoProcessingService.processVideo(at: url) { [weak self] progress in
            await MainActor.run {
                guard let self else { return }
                let percent = Int((progress * 100).rounded())
                self.processingProgressText = "Processing \(percent)%"
            }
        }

        self.detectedPitches = pitchData.map { data in
            ThrowSession(
                date: .now,
                videoURL: url.path(),
                metrics: data.metrics,
                landmarks: data.landmarks
            )
        }

        if let firstPitch = detectedPitches.first {
            playbackSession = firstPitch
            processedLandmarks = firstPitch.landmarks
        }

        isProcessing = false
        processingProgressText = detectedPitches.isEmpty
            ? "No pitches detected in this session."
            : "Detected \(detectedPitches.count) pitches."
        statusText = "Session analyzed."
    }

    func persistPlaybackSessionIfNeeded(in modelContext: ModelContext) {
        guard !detectedPitches.isEmpty, !hasPersistedPlaybackSession else { return }

        for session in detectedPitches {
            modelContext.insert(session)
        }

        do {
            try modelContext.save()
            hasPersistedPlaybackSession = true
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Failed to save pitches."
        }
    }

    private func startElapsedTimer() {
        recordingTask?.cancel()
        elapsedTimeText = "00:00"

        recordingTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                guard let startedAt = self.recordingStartedAt else { return }
                let elapsed = Int(Date().timeIntervalSince(startedAt))
                let minutes = elapsed / 60
                let seconds = elapsed % 60
                self.elapsedTimeText = String(format: "%02d:%02d", minutes, seconds)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
