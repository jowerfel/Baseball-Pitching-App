import SwiftUI
import PhotosUI // Required for the native picker

struct HomeView: View {
    // State variables to handle item selection and the extracted video local URL
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedVideoURL: URL? = nil
    @State private var isProcessing = false
    @StateObject private var viewModel = CameraViewModel()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "figure.baseball")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.tint)

                    Text("BaseballPitchingApp")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    Text("Capture, review, and compare your throwing sessions on-device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                Spacer()

                // 1. Record New Throw Navigation
                NavigationLink {
                    CameraView()
                } label: {
                    HomeActionButtonLabel(title: "Record New Throw", systemImage: "video.circle.fill")
                }
                
                // 2. Upload Video Picker Button
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .videos // 🟢 ONLY ALLOWS VIDEOS TO BE SELECTED
                ) {
                    HomeActionButtonLabel(
                        title: isProcessing ? "Processing..." : "Upload Throw",
                        systemImage: "video.badge.plus"
                    )
                }
                .disabled(isProcessing)
                // Listens for picker selection changes and processes the video file
                .onChange(of: selectedItem) { _, newItem in
                    guard let newItem = newItem else { return }
                    
                    isProcessing = true
                    Task {
                        // Videos must be loaded as a temporary file movie UTType
                        if let movie = try? await newItem.loadTransferable(type: MovieTransferable.self) {
                            // Save the local URL reference
                            self.selectedVideoURL = movie.url
                            
                            // Trigger your custom function with the video URL
                            processUploadedVideo(movie.url)
                        }
                        isProcessing = false
                    }
                }

                // 3. Saved Sessions Navigation
                NavigationLink {
                    SessionListView()
                } label: {
                    HomeActionButtonLabel(title: "Saved Sessions", systemImage: "list.bullet.rectangle.portrait.fill")
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .navigationTitle("Home")
        }
    }
    
    /// Custom function that handles the video payload after upload
    private func processUploadedVideo(_ videoURL: URL) {
        print("Successfully loaded video local URL: \(videoURL)")
        viewModel.uploadedVideo(videoURL)
        // Add your video playback, CoreML analysis, or storage logic here
    }
}

// MARK: - Video Transferable Helper
/// A helper struct required by SwiftUI's Transferable protocol to securely copy
/// a video file out of the user's secure photo library into your app's temporary folder.
struct MovieTransferable: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            // Copy the file to a secure temporary directory before the system deletes the original reference
            let copyURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension)
            
            try FileManager.default.copyItem(at: received.file, to: copyURL)
            return MovieTransferable(url: copyURL)
        }
    }
}

// MARK: - Supporting Components

private struct HomeActionButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))

            Text(title)
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.tint)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}



#Preview {
    HomeView()
}
