import SwiftUI

struct HomeView: View {
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

                NavigationLink {
                    CameraView()
                } label: {
                    HomeActionButtonLabel(title: "Record New Throw", systemImage: "video.circle.fill")
                }

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
}

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
