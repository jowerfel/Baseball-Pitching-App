@preconcurrency import AVFoundation
import SwiftUI
import UIKit

struct CameraView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = CameraViewModel()

    var body: some View {
        ZStack {
            CameraPreviewRepresentable(session: viewModel.previewSession)
                .ignoresSafeArea()

            LinearGradient(
                colors: [Color.black.opacity(0.65), Color.clear, Color.black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                header
                Spacer()
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .background(Color.black)
        .navigationTitle("Record Throw")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onChange(of: viewModel.playbackSession?.id) {
            viewModel.persistPlaybackSessionIfNeeded(in: modelContext)
        }
        .alert("Camera Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.statusText)
                    .font(.headline)
                    .foregroundStyle(.white)

                if let savedVideoURL = viewModel.savedVideoURL {
                    Text(savedVideoURL.path())
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                }

                if !viewModel.processingProgressText.isEmpty {
                    Text(viewModel.processingProgressText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                }

                if !viewModel.processedLandmarks.isEmpty {
                    Text("\(viewModel.processedLandmarks.count) sampled frames populated")
                        .font(.footnote)
                        .foregroundStyle(.cyan)
                }
            }

            Spacer()

            Text(viewModel.elapsedTimeText)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.55))
                .clipShape(Capsule())
                .foregroundStyle(viewModel.isRecording ? .red : .white)
        }
    }

    private var footer: some View {
        VStack(spacing: 20) {
            if viewModel.isProcessing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }

            if let playbackSession = viewModel.playbackSession, !viewModel.isRecording, !viewModel.isProcessing {
                NavigationLink {
                    PlaybackView(session: playbackSession)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                        Text("Open Playback")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.cyan.opacity(0.9))
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Text("Slow-motion capture prefers 240 fps, then 120 fps, then 60 fps.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)

            Button {
                viewModel.toggleRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 94, height: 94)

                    Circle()
                        .strokeBorder(.white, lineWidth: 4)
                        .frame(width: 78, height: 78)

                    if viewModel.isRecording {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.red)
                            .frame(width: 30, height: 30)
                    } else {
                        Circle()
                            .fill(.red)
                            .frame(width: 56, height: 56)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start recording")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

}

private struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }
}

private final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Camera preview layer could not be created.")
        }

        return layer
    }
}
