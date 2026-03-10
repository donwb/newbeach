import SwiftUI

/// Webcam image section showing a live beach camera feed.
struct WebcamView: View {
    let webcamURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Beach Webcam", systemImage: "video.fill")
                .font(.headline)

            if let url = webcamURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                    case .failure:
                        webcamPlaceholder(message: "Unable to load webcam")

                    case .empty:
                        ProgressView()
                            .frame(height: 200)
                            .frame(maxWidth: .infinity)

                    @unknown default:
                        webcamPlaceholder(message: "Webcam unavailable")
                    }
                }
            } else {
                webcamPlaceholder(message: "No webcam configured")
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.cardBackground)
        }
    }

    private func webcamPlaceholder(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "video.slash")
                .font(.largeTitle)
                .foregroundStyle(AppColors.secondaryText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppColors.secondaryText)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.cardBackground)
        }
    }
}
