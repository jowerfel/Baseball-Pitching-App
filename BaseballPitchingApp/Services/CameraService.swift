@preconcurrency import AVFoundation
import Foundation

actor CameraService {
    enum CameraServiceError: LocalizedError {
        case cameraAccessDenied
        case microphoneAccessDenied
        case unavailableCameraDevice
        case unableToCreateInput
        case unableToAddInput
        case unableToAddOutput
        case failedToConfigureFrameRate
        case sessionNotConfigured
        case recordingAlreadyInProgress
        case recordingNotInProgress
        case recordingFailed

        var errorDescription: String? {
            switch self {
            case .cameraAccessDenied:
                return "Camera access was denied. Enable camera access in Settings to record throws."
            case .microphoneAccessDenied:
                return "Microphone access was denied. Enable microphone access in Settings to record audio with each throw."
            case .unavailableCameraDevice:
                return "No suitable back camera is available on this device."
            case .unableToCreateInput:
                return "The camera inputs could not be created."
            case .unableToAddInput:
                return "The capture session could not add the required inputs."
            case .unableToAddOutput:
                return "The capture session could not add the movie output."
            case .failedToConfigureFrameRate:
                return "The camera could not be configured for 240, 120, or 60 fps recording."
            case .sessionNotConfigured:
                return "The camera session is not ready yet."
            case .recordingAlreadyInProgress:
                return "A recording is already in progress."
            case .recordingNotInProgress:
                return "There is no active recording to stop."
            case .recordingFailed:
                return "The recording could not be saved."
            }
        }
    }

    nonisolated let previewSession: AVCaptureSession

    private let controller: CaptureController

    init() {
        let controller = CaptureController()
        self.controller = controller
        self.previewSession = controller.session
    }

    func prepareSession() async throws {
        try await controller.prepareSession()
    }

    func startSession() async {
        await controller.startSession()
    }

    func stopSession() async {
        await controller.stopSession()
    }

    func startRecording() async throws {
        try await controller.startRecording()
    }

    func stopRecording() async throws -> URL {
        try await controller.stopRecording()
    }
}

private final class CaptureController: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.yourname.BaseballPitchingApp.camera.session")
    private let movieOutput = AVCaptureMovieFileOutput()
    private var isConfigured = false
    private var isPreparing = false
    private var activeVideoInput: AVCaptureDeviceInput?
    private var activeAudioInput: AVCaptureDeviceInput?
    private var recordingContinuation: CheckedContinuation<URL, Error>?
    private var currentOutputURL: URL?

    func prepareSession() async throws {
        if isConfigured || isPreparing {
            return
        }

        isPreparing = true
        defer { isPreparing = false }

        let cameraAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        guard cameraAuthorized else {
            throw CameraService.CameraServiceError.cameraAccessDenied
        }

        let microphoneAuthorized = await AVCaptureDevice.requestAccess(for: .audio)
        guard microphoneAuthorized else {
            throw CameraService.CameraServiceError.microphoneAccessDenied
        }

        let configuration = try await sessionQueueResult { [weak self] in
            guard let self else {
                throw CameraService.CameraServiceError.sessionNotConfigured
            }

            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                throw CameraService.CameraServiceError.unavailableCameraDevice
            }

            guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
                throw CameraService.CameraServiceError.unableToCreateInput
            }

            let videoInput: AVCaptureDeviceInput
            let audioInput: AVCaptureDeviceInput

            do {
                videoInput = try AVCaptureDeviceInput(device: videoDevice)
                audioInput = try AVCaptureDeviceInput(device: audioDevice)
            } catch {
                throw CameraService.CameraServiceError.unableToCreateInput
            }

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            defer {
                self.session.commitConfiguration()
            }

            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }

            guard self.session.canAddInput(videoInput), self.session.canAddInput(audioInput) else {
                throw CameraService.CameraServiceError.unableToAddInput
            }

            self.session.addInput(videoInput)
            self.session.addInput(audioInput)

            guard self.session.canAddOutput(self.movieOutput) else {
                throw CameraService.CameraServiceError.unableToAddOutput
            }

            self.session.addOutput(self.movieOutput)

            let selectedFrameRate = try self.configurePreferredFrameRate(for: videoDevice)

            if let connection = self.movieOutput.connection(with: .video), connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }

            self.activeVideoInput = videoInput
            self.activeAudioInput = audioInput
            self.isConfigured = true

            return selectedFrameRate
        }

        _ = configuration
    }

    func startSession() async {
        guard isConfigured else {
            return
        }

        await sessionQueueAsync { [weak self] in
            guard let self, !self.session.isRunning else {
                return
            }

            self.session.startRunning()
        }
    }

    func stopSession() async {
        await sessionQueueAsync { [weak self] in
            guard let self else {
                return
            }

            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }

            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func startRecording() async throws {
        guard isConfigured else {
            throw CameraService.CameraServiceError.sessionNotConfigured
        }

        let outputURL = try makeOutputURL()

        try await sessionQueueResult { [weak self] in
            guard let self else {
                throw CameraService.CameraServiceError.sessionNotConfigured
            }

            guard !self.movieOutput.isRecording else {
                throw CameraService.CameraServiceError.recordingAlreadyInProgress
            }

            self.currentOutputURL = outputURL
            self.movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        }
    }

    func stopRecording() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraService.CameraServiceError.recordingNotInProgress)
                    return
                }

                guard self.movieOutput.isRecording else {
                    continuation.resume(throwing: CameraService.CameraServiceError.recordingNotInProgress)
                    return
                }

                self.recordingContinuation = continuation
                self.movieOutput.stopRecording()
            }
        }
    }

    private func configurePreferredFrameRate(for device: AVCaptureDevice) throws -> Int {
        let preferredRates = [240, 120, 60]

        for rate in preferredRates {
            if let format = device.formats.first(where: { format in
                format.videoSupportedFrameRateRanges.contains { range in
                    range.minFrameRate <= Double(rate) && range.maxFrameRate >= Double(rate)
                }
            }) {
                do {
                    try device.lockForConfiguration()
                    device.activeFormat = format
                    let duration = CMTime(value: 1, timescale: CMTimeScale(rate))
                    device.activeVideoMinFrameDuration = duration
                    device.activeVideoMaxFrameDuration = duration
                    device.unlockForConfiguration()
                    return rate
                } catch {
                    continue
                }
            }
        }

        throw CameraService.CameraServiceError.failedToConfigureFrameRate
    }

    private func makeOutputURL() throws -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let documentsURL else {
            throw CameraService.CameraServiceError.recordingFailed
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "throw_\(formatter.string(from: Date())).mov"
        let outputURL = documentsURL.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: outputURL.path()) {
            try FileManager.default.removeItem(at: outputURL)
        }

        return outputURL
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        let continuation = recordingContinuation
        recordingContinuation = nil
        currentOutputURL = nil

        if let error {
            continuation?.resume(throwing: error)
            return
        }

        continuation?.resume(returning: outputFileURL)
    }

    private func sessionQueueAsync(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                work()
                continuation.resume()
            }
        }
    }

    private func sessionQueueResult<T>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
