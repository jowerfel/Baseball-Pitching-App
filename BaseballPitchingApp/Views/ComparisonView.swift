import AVKit
import SwiftData
import SwiftUI

struct ComparisonView: View {
    @Query(sort: \ThrowSession.date, order: .reverse) private var sessions: [ThrowSession]
    @StateObject private var viewModel: ComparisonViewModel

    init(preselectedSession: ThrowSession? = nil) {
        _viewModel = StateObject(wrappedValue: ComparisonViewModel(sessionA: preselectedSession))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    comparisonPane(
                        title: "Session A",
                        session: viewModel.sessionA,
                        player: viewModel.playerA,
                        landmarks: viewModel.currentLandmarksA,
                        selectionAction: { session in
                            viewModel.updateSession(session, for: .sessionA)
                        }
                    )

                    comparisonPane(
                        title: "Session B",
                        session: viewModel.sessionB,
                        player: viewModel.playerB,
                        landmarks: viewModel.currentLandmarksB,
                        selectionAction: { session in
                            viewModel.updateSession(session, for: .sessionB)
                        }
                    )
                }
                .frame(height: 320)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Synchronized Timeline")
                        .font(.headline)

                    HStack(spacing: 12) {
                        Button {
                            viewModel.togglePlayback()
                        } label: {
                            Label(
                                viewModel.isPlaying ? "Pause" : "Play",
                                systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill"
                            )
                            .frame(minWidth: 96)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.hasTwoSessionsSelected)

                        Text(viewModel.emptyStateMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { viewModel.normalizedProgress },
                            set: { viewModel.seek(to: $0) }
                        ),
                        in: 0...1,
                        onEditingChanged: { isEditing in
                            if isEditing {
                                viewModel.beginScrubbing()
                            } else {
                                viewModel.endScrubbing()
                            }
                        }
                    )
                    .disabled(!viewModel.hasTwoSessionsSelected)

                    HStack {
                        timePill(title: "A", value: timeLabel(viewModel.currentTimeA), accent: .cyan)
                        Spacer()
                        timePill(title: "B", value: timeLabel(viewModel.currentTimeB), accent: .orange)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Metric Comparison")
                        .font(.title3.bold())

                    if let sessionA = viewModel.sessionA, let sessionB = viewModel.sessionB {
                        VStack(spacing: 10) {
                            metricDeltaRow(
                                title: "Relative Stride",
                                valueA: sessionA.metrics.relativeStrideDisplayValue,
                                valueB: sessionB.metrics.relativeStrideDisplayValue,
                                delta: numericDelta(
                                    from: sessionA.metrics.relativeStridePixels,
                                    to: sessionB.metrics.relativeStridePixels,
                                    suffix: "px"
                                )
                            )

                            metricDeltaRow(
                                title: "Release Height",
                                valueA: sessionA.metrics.releasePointHeightDisplayValue,
                                valueB: sessionB.metrics.releasePointHeightDisplayValue,
                                delta: numericDelta(
                                    from: sessionA.metrics.releasePointHeight,
                                    to: sessionB.metrics.releasePointHeight,
                                    suffix: ""
                                )
                            )

                            metricDeltaRow(
                                title: "Shoulder Angle",
                                valueA: sessionA.metrics.shoulderAngleDisplayValue,
                                valueB: sessionB.metrics.shoulderAngleDisplayValue,
                                delta: numericDelta(
                                    from: sessionA.metrics.shoulderAngleDegrees,
                                    to: sessionB.metrics.shoulderAngleDegrees,
                                    suffix: "deg"
                                )
                            )

                            metricDeltaRow(
                                title: "Arm Slot",
                                valueA: sessionA.metrics.armSlotLabel,
                                valueB: sessionB.metrics.armSlotLabel,
                                delta: armSlotDelta(sessionA.metrics.armSlotLabel, sessionB.metrics.armSlotLabel)
                            )
                        }
                    } else {
                        ContentUnavailableView(
                            "Select Two Sessions",
                            systemImage: "square.split.2x1",
                            description: Text("Pick a saved session for each side to unlock the side-by-side metric table.")
                        )
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: sessions.map(\.id)) {
            viewModel.prepareSessions(from: sessions)
        }
        .onDisappear {
            viewModel.teardown()
        }
    }

    private func comparisonPane(
        title: String,
        session: ThrowSession?,
        player: AVPlayer,
        landmarks: [BodyLandmark],
        selectionAction: @escaping (ThrowSession) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)

                Spacer()

                Menu {
                    ForEach(availableSessions(excluding: oppositeSessionID(for: title))) { candidate in
                        Button(candidate.date.formatted(date: .abbreviated, time: .shortened)) {
                            selectionAction(candidate)
                        }
                    }
                } label: {
                    Label("Pick Session", systemImage: "list.bullet")
                        .font(.caption.weight(.semibold))
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.92))

                if session != nil {
                    VideoPlayer(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay {
                            GeometryReader { geometry in
                                Canvas { context, size in
                                    SkeletonRenderer.drawSkeleton(
                                        for: landmarks,
                                        in: context,
                                        canvasSize: size
                                    )
                                }
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .allowsHitTesting(false)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        }
                } else {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if let session {
                    Text(session.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline.weight(.semibold))

                    Text(session.metrics.armSlotLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No session selected")
                        .font(.subheadline.weight(.semibold))

                    Text("Choose a saved throw to compare.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func availableSessions(excluding otherSessionID: UUID?) -> [ThrowSession] {
        sessions.filter { $0.id != otherSessionID }
    }

    private func oppositeSessionID(for title: String) -> UUID? {
        if title == "Session A" {
            return viewModel.sessionB?.id
        }

        return viewModel.sessionA?.id
    }

    private func timePill(title: String, value: String, accent: Color) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(accent)
                .clipShape(Capsule())

            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func timeLabel(_ value: Double) -> String {
        let clampedValue = max(0, value)
        let minutes = Int(clampedValue) / 60
        let seconds = Int(clampedValue) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func metricDeltaRow(title: String, valueA: String, valueB: String, delta: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(valueA)
                .font(.footnote.monospacedDigit())
                .frame(width: 90, alignment: .trailing)

            Text(valueB)
                .font(.footnote.monospacedDigit())
                .frame(width: 90, alignment: .trailing)

            Text(delta)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func numericDelta(from first: Double?, to second: Double?, suffix: String) -> String {
        guard let first, let second else {
            return "Delta: N/A"
        }

        let delta = second - first
        let sign = delta > 0 ? "+" : ""
        let formatted = delta.formatted(.number.precision(.fractionLength(0...2)))
        return suffix.isEmpty ? "Delta: \(sign)\(formatted)" : "Delta: \(sign)\(formatted) \(suffix)"
    }

    private func armSlotDelta(_ first: String, _ second: String) -> String {
        first == second ? "Match" : "Changed"
    }
}
