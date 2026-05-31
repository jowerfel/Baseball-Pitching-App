@preconcurrency import AVFoundation
import AVKit
import Combine
import Foundation

@MainActor
final class ThrowViewModel: ObservableObject {
    @Published var errorMessage: String?
    @Published private(set) var selectedSession: ThrowSession?
    @Published private(set) var currentLandmarks: [BodyLandmark] = []
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 1
    @Published private(set) var isPlaying = false
    @Published private(set) var wasPlayingBeforeScrub = false

    let player = AVPlayer()

    private var timeObserver: Any?
    private var isSeeking = false

    func show(session: ThrowSession) {
        selectedSession = session
        configurePlayer(for: session)
        updateCurrentLandmarks(for: 0, in: session.landmarks)
    }

    func teardown() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        player.pause()
        isPlaying = false
        wasPlayingBeforeScrub = false
    }

    func seek(to time: Double) {
        guard let session = selectedSession else {
            return
        }

        isSeeking = true
        currentTime = time
        updateCurrentLandmarks(for: time, in: session.landmarks)

        let targetTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.isSeeking = false
            }
        }
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func beginScrubbing() {
        wasPlayingBeforeScrub = isPlaying

        if isPlaying {
            player.pause()
            isPlaying = false
        }
    }

    func endScrubbing() {
        guard wasPlayingBeforeScrub else {
            return
        }

        player.play()
        isPlaying = true
        wasPlayingBeforeScrub = false
    }

    private func configurePlayer(for session: ThrowSession) {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        let url = URL(fileURLWithPath: session.videoURL)
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)

        let asset = item.asset
        Task {
            do {
                let durationTime = try await asset.load(.duration)
                let loadedDuration = max(durationTime.seconds, 0.1)
                duration = loadedDuration
            } catch {
                duration = 1
                errorMessage = error.localizedDescription
            }
        }

        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else {
                return
            }

            Task { @MainActor [weak self] in
                guard let self, let selectedSession = self.selectedSession, !self.isSeeking else {
                    return
                }

                let seconds = time.seconds.isFinite ? time.seconds : 0
                self.currentTime = seconds
                self.updateCurrentLandmarks(for: seconds, in: selectedSession.landmarks)

                if let currentItem = self.player.currentItem,
                   currentItem.status == .readyToPlay,
                   currentItem.duration.seconds.isFinite,
                   seconds >= currentItem.duration.seconds {
                    self.isPlaying = false
                }
            }
        }
    }

    private func updateCurrentLandmarks(for time: Double, in frames: [PerFrameLandmarks]) {
        guard !frames.isEmpty else {
            currentLandmarks = []
            return
        }

        let closestFrame = frames.min { lhs, rhs in
            abs(lhs.timestamp - time) < abs(rhs.timestamp - time)
        }

        currentLandmarks = closestFrame?.landmarks ?? []
    }
}
