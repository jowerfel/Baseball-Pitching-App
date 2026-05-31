import AVKit
import SwiftUI

struct PlaybackView: View {
    let session: ThrowSession?

    @StateObject private var viewModel = ThrowViewModel()
    @State private var isShowingComparison = false

    init(session: ThrowSession? = nil) {
        self.session = session
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.black.opacity(0.92))

                    if viewModel.selectedSession != nil {
                        VideoPlayer(player: viewModel.player)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay {
                                GeometryReader { geometry in
                                    Canvas { context, size in
                                        SkeletonRenderer.drawSkeleton(
                                            for: viewModel.currentLandmarks,
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
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(height: 260)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Timeline")
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

                        Text(viewModel.currentLandmarks.isEmpty ? "No landmarks for this frame" : "Skeleton synced to current frame")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { min(viewModel.currentTime, viewModel.duration) },
                            set: { viewModel.seek(to: $0) }
                        ),
                        in: 0...max(viewModel.duration, 0.1),
                        onEditingChanged: { isEditing in
                            if isEditing {
                                viewModel.beginScrubbing()
                            } else {
                                viewModel.endScrubbing()
                            }
                        }
                    )

                    HStack {
                        Text(timeLabel(viewModel.currentTime))
                        Spacer()
                        Text(timeLabel(viewModel.duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Playback")
                        .font(.title2.bold())

                    Text(sessionSummary)
                        .font(.body)
                        .foregroundStyle(.secondary)

                    if let selectedSession = viewModel.selectedSession {
                        Text("\(selectedSession.landmarks.count) sampled pose frames available")
                            .font(.footnote)
                            .foregroundStyle(.cyan)
                    }
                }

                if let metrics = viewModel.selectedSession?.metrics {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metricCard(title: "Relative Stride", value: metrics.relativeStrideDisplayValue)
                        metricCard(title: "Release Height", value: metrics.releasePointHeightDisplayValue)
                        metricCard(title: "Shoulder Angle", value: metrics.shoulderAngleDisplayValue)
                        metricCard(title: "Arm Slot", value: metrics.armSlotLabel)
                    }
                }

                if viewModel.selectedSession != nil {
                    Button {
                        isShowingComparison = true
                    } label: {
                        Label("Compare", systemImage: "square.split.2x1.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .navigationTitle("Playback")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isShowingComparison) {
            ComparisonView(preselectedSession: viewModel.selectedSession)
        }
        .task(id: session?.id) {
            if let session {
                viewModel.show(session: session)
            }
        }
        .onDisappear {
            viewModel.teardown()
        }
    }

    private var sessionSummary: String {
        guard let session else {
            return "A processed session will appear here once recording and analysis are implemented."
        }

        return "Session from \(session.date.formatted(date: .abbreviated, time: .shortened)) is ready for playback."
    }

    private func timeLabel(_ value: Double) -> String {
        let clampedValue = max(0, value)
        let minutes = Int(clampedValue) / 60
        let seconds = Int(clampedValue) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
