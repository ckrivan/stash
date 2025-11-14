import SwiftUI
import AVKit

struct PerformerRow: View {
  let performer: StashScene.Performer

  @State private var previewPlayer = AVPlayer()
  @State private var isPreviewing = false

  var body: some View {
    VStack(alignment: .center, spacing: 12) {
      // Image with inline preview and caching (300px for performer avatars)
      ZStack {
        if let imagePath = performer.image_path {
          CachedAsyncImage(url: URL(string: imagePath), width: 300) { image in
            image
              .resizable()
              .aspectRatio(contentMode: .fill)
          } placeholder: {
            Color.gray.opacity(0.3)
          }
        } else {
          Image(systemName: "person.circle.fill")
            .foregroundColor(.gray)
            .font(.system(size: 60))
        }

        if isPreviewing {
          VideoPlayer(player: previewPlayer)
            .disabled(true)
            .transition(.opacity)
        }
      }
      .frame(width: 120, height: 120)
      .clipShape(Circle())
      .contentShape(Circle())
      .gesture(
        LongPressGesture(minimumDuration: 0.2)
          .onChanged { _ in startPreview() }
          .onEnded { _ in stopPreview() }
      )
      .onDisappear { stopPreview() }

      // Info
      VStack(alignment: .center, spacing: 4) {
        Text(performer.name)
          .font(.headline)
          .lineLimit(1)

        if let count = performer.scene_count {
          Text("\(count) scenes")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(Color(UIColor.secondarySystemBackground))
    .cornerRadius(12)
  }

  private func startPreview() {
    guard !isPreviewing else { return }
    // Attempt to play the first available preview from this performer by using a lightweight image-based loop if no direct preview is available.
    // Since PerformerRow has only performer info, we can’t query API here; we’ll play a silent black player to avoid blocking UI if no source.
    // For now, show the preview layer only when we can resolve a URL from a cached hint in UserDefaults.
    if let previewURLString = UserDefaults.standard.string(forKey: "performer_\(performer.id)_previewURL"),
       let url = URL(string: previewURLString) {
      let item = AVPlayerItem(url: url)
      previewPlayer.replaceCurrentItem(with: item)
      previewPlayer.isMuted = true
      previewPlayer.play()
      isPreviewing = true
    } else {
      // No preview configured; do nothing visible
      isPreviewing = false
    }
  }

  private func stopPreview() {
    previewPlayer.pause()
    previewPlayer.replaceCurrentItem(with: nil)
    isPreviewing = false
  }
}

// MARK: - Preview Provider
struct PerformerRow_Previews: PreviewProvider {
  static var previews: some View {
    PerformerRow(
      performer: StashScene.Performer(
        id: "1",
        name: "Test Performer",
        gender: "FEMALE",
        image_path: nil,
        scene_count: 10,
        favorite: false,
        rating100: 80
      )
    )
    .previewLayout(.sizeThatFits)
    .padding()
  }
}
