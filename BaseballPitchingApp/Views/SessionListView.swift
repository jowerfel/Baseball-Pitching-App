@preconcurrency import AVFoundation
import SwiftData
import SwiftUI

struct SessionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ThrowSession.date, order: .reverse) private var sessions: [ThrowSession]

    var body: some View {
        List {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No Saved Sessions",
                    systemImage: "baseball",
                    description: Text("Recorded throws will appear here after Step 6 adds persistence wiring.")
                )
            } else {
                ForEach(sessions) { session in
                    NavigationLink {
                        PlaybackView(session: session)
                    } label: {
                        SessionRowView(session: session)
                    }
                }
                .onDelete(perform: deleteSessions)
            }
        }
        .navigationTitle("Saved Sessions")
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = sessions[index]
            let videoURL = URL(fileURLWithPath: session.videoURL)

            modelContext.delete(session)

            if FileManager.default.fileExists(atPath: videoURL.path()) {
                try? FileManager.default.removeItem(at: videoURL)
            }
        }

        try? modelContext.save()
    }
}

private struct SessionRowView: View {
    let session: ThrowSession

    var body: some View {
        HStack(spacing: 14) {
            SessionThumbnailView(videoPath: session.videoURL)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(session.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.headline)
                    
                    if let pitchNumber = session.metrics.pitchNumber {
                        Text("Pitch #\(pitchNumber)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }

                Text("\(session.metrics.armSlotLabel) • \(session.metrics.estimatedPitchSpeedDisplayValue)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Stride: \(session.metrics.relativeStrideDisplayValue)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SessionThumbnailView: View {
    let videoPath: String

    @State private var thumbnailImage: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.85))

            if let thumbnailImage {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "video")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: videoPath) {
            thumbnailImage = await generateThumbnail(for: videoPath)
        }
    }

    private func generateThumbnail(for path: String) async -> UIImage? {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 240, height: 240)

            do {
                let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
                return UIImage(cgImage: cgImage)
            } catch {
                return nil
            }
        }.value
    }
}
