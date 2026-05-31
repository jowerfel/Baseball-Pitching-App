@preconcurrency import AVFoundation
import Combine
import Foundation

@MainActor
final class ComparisonViewModel: ObservableObject {
    enum SessionSlot {
        case sessionA
        case sessionB
    }

    @Published var errorMessage: String?
    @Published private(set) var sessionA: ThrowSession?
    @Published private(set) var sessionB: ThrowSession?
    @Published private(set) var currentLandmarksA: [BodyLandmark] = []
    @Published private(set) var currentLandmarksB: [BodyLandmark] = []
    @Published private(set) var normalizedProgress: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var wasPlayingBeforeScrub = false
    @Published private(set) var durationA: Double = 1
    @Published private(set) var durationB: Double = 1

    let playerA = AVPlayer()
    let playerB = AVPlayer()

    private var timeObserver: Any?
    private var isSeeking = false
    private var masterSlot: SessionSlot = .sessionA

    init(sessionA: ThrowSession? = nil, sessionB: ThrowSession? = nil) {
        self.sessionA = sessionA
        self.sessionB = sessionB
    }

    var emptyStateMessage: String {
        if sessionA == nil || sessionB == nil {
            return "Choose two processed throws to compare their mechanics side by side."
        }

        return "Playback is synchronized across both clips so timing and metrics line up on one shared scrubber."
    }

    var hasTwoSessionsSelected: Bool {
        sessionA != nil && sessionB != nil
    }

    var masterDuration: Double {
        max(durationA, durationB, 0.1)
    }

    var currentTimeA: Double {
        normalizedProgress * durationA
    }

    var currentTimeB: Double {
        normalizedProgress * durationB
    }

    func prepareSessions(from sessions: [ThrowSession]) {
        if sessionA == nil {
            sessionA = sessions.first
        }

        if sessionB == nil {
            sessionB = sessions.first(where: { $0.id != sessionA?.id })
        }

        configurePlayers()
    }

    func selectSession(withID id: UUID, for slot: SessionSlot) {
        switch slot {
        case .sessionA:
            guard sessionA?.id != id else { return }
        case .sessionB:
            guard sessionB?.id != id else { return }
        }

        let currentPeerID: UUID? = {
            switch slot {
            case .sessionA:
                sessionB?.id
            case .sessionB:
                sessionA?.id
            }
        }()

        if currentPeerID == id {
            return
        }

        switch slot {
        case .sessionA:
            sessionA = nil
        case .sessionB:
            sessionB = nil
        }
    }

    func updateSession(_ session: ThrowSession, for slot: SessionSlot) {
        switch slot {
        case .sessionA:
            guard sessionA?.id != session.id else { return }
            sessionA = session
        case .sessionB:
            guard sessionB?.id != session.id else { return }
            sessionB = session
        }

        normalizedProgress = 0
        configurePlayers()
    }

    func togglePlayback() {
        guard hasTwoSessionsSelected else {
            return
        }

        if isPlaying {
            pausePlayers()
            return
        }

        if normalizedProgress >= 0.999 {
            seek(to: 0)
        }

        playPlayers()
    }

    func beginScrubbing() {
        wasPlayingBeforeScrub = isPlaying

        if isPlaying {
            pausePlayers()
        }
    }

    func seek(to progress: Double) {
        let clampedProgress = min(max(progress, 0), 1)
        normalizedProgress = clampedProgress
        isSeeking = true

        let timeA = CMTime(seconds: clampedProgress * durationA, preferredTimescale: 600)
        let timeB = CMTime(seconds: clampedProgress * durationB, preferredTimescale: 600)

        playerA.seek(to: timeA, toleranceBefore: .zero, toleranceAfter: .zero)
        playerB.seek(to: timeB, toleranceBefore: .zero, toleranceAfter: .zero)

        updateCurrentLandmarks()
        isSeeking = false
    }

    func endScrubbing() {
        guard wasPlayingBeforeScrub else {
            return
        }

        wasPlayingBeforeScrub = false
        playPlayers()
    }

    func teardown() {
        if let timeObserver {
            activeMasterPlayer.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        pausePlayers()
        playerA.replaceCurrentItem(with: nil)
        playerB.replaceCurrentItem(with: nil)
    }

    private var activeMasterPlayer: AVPlayer {
        masterSlot == .sessionA ? playerA : playerB
    }

    private func configurePlayers() {
        pausePlayers()

        if let timeObserver {
            activeMasterPlayer.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        configurePlayer(playerA, with: sessionA)
        configurePlayer(playerB, with: sessionB)
        updateCurrentLandmarks()

        Task {
            await loadDurations()
            await MainActor.run {
                self.attachTimeObserver()
                self.seek(to: self.normalizedProgress)
            }
        }
    }

    private func configurePlayer(_ player: AVPlayer, with session: ThrowSession?) {
        guard let session else {
            player.replaceCurrentItem(with: nil)
            return
        }

        let url = URL(fileURLWithPath: session.videoURL)
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }

    private func loadDurations() async {
        async let loadedDurationA = loadDuration(for: playerA.currentItem?.asset)
        async let loadedDurationB = loadDuration(for: playerB.currentItem?.asset)

        let resolvedDurationA = await loadedDurationA
        let resolvedDurationB = await loadedDurationB

        await MainActor.run {
            durationA = resolvedDurationA
            durationB = resolvedDurationB
            masterSlot = resolvedDurationB > resolvedDurationA ? .sessionB : .sessionA
        }
    }

    private func loadDuration(for asset: AVAsset?) async -> Double {
        guard let asset else {
            return 1
        }

        do {
            let duration = try await asset.load(.duration)
            let seconds = duration.seconds
            return seconds.isFinite ? max(seconds, 0.1) : 1
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
            return 1
        }
    }

    private func attachTimeObserver() {
        if let timeObserver {
            activeMasterPlayer.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = activeMasterPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else {
                return
            }

            Task { @MainActor [weak self] in
                guard let self, !self.isSeeking else {
                    return
                }

                let rawSeconds = time.seconds.isFinite ? time.seconds : 0
                self.normalizedProgress = min(max(rawSeconds / self.masterDuration, 0), 1)
                self.updateCurrentLandmarks()

                if self.normalizedProgress >= 0.999 {
                    self.pausePlayers()
                    self.normalizedProgress = 1
                    self.updateCurrentLandmarks()
                }
            }
        }
    }

    private func playPlayers() {
        guard hasTwoSessionsSelected else {
            return
        }

        isPlaying = true
        wasPlayingBeforeScrub = false

        let rateA = Float(durationA / masterDuration)
        let rateB = Float(durationB / masterDuration)
        playerA.playImmediately(atRate: max(rateA, 0.05))
        playerB.playImmediately(atRate: max(rateB, 0.05))
    }

    private func pausePlayers() {
        playerA.pause()
        playerB.pause()
        isPlaying = false
    }

    private func updateCurrentLandmarks() {
        currentLandmarksA = landmarks(for: sessionA, at: currentTimeA)
        currentLandmarksB = landmarks(for: sessionB, at: currentTimeB)
    }

    private func landmarks(for session: ThrowSession?, at time: Double) -> [BodyLandmark] {
        guard let session else {
            return []
        }

        let frames = session.landmarks
        guard !frames.isEmpty else {
            return []
        }

        let closestFrame = frames.min { lhs, rhs in
            abs(lhs.timestamp - time) < abs(rhs.timestamp - time)
        }

        return closestFrame?.landmarks ?? []
    }
}
