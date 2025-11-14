import SwiftUI

/// A specialized button component for performer names that uses NavigationLink directly
/// instead of relying on callbacks, ensuring navigation works in all contexts.
struct PerformerButton: View {
  let performer: StashScene.Performer
  @EnvironmentObject private var appModel: AppModel
  @State private var isPressed = false

  var body: some View {
    Button(action: {
      print("🚀 PerformerButton: Direct navigation to \(performer.name)")
      isPressed = true

      // Use a slight delay to ensure the visual feedback registers
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        appModel.navigateToPerformer(performer)
      }
    }) {
      Text(performer.name)
        .font(.subheadline)
        .foregroundColor(isPressed ? .purple : .blue)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .background(Color.blue.opacity(0.05))
        .cornerRadius(4)
    }
    .buttonStyle(PlainButtonStyle())
  }
}

/// A more visual button for performers with avatar image
struct PerformerAvatarButton: View {
  let performer: StashScene.Performer
  let serverAddress: String
  @EnvironmentObject private var appModel: AppModel

  var body: some View {
    Button(action: {
      print("🚀 PerformerAvatarButton: Direct navigation to \(performer.name)")

      // Use a slight delay to ensure the visual feedback registers
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        appModel.navigateToPerformer(performer)
      }
    }) {
      HStack(spacing: 4) {
        // Performer avatar with caching (40px for small avatars)
        if let imagePath = performer.image_path, !imagePath.isEmpty {
          CachedAsyncImage(url: URL(string: "\(serverAddress)\(imagePath)"), width: 40) { image in
            image
              .resizable()
              .aspectRatio(contentMode: .fill)
          } placeholder: {
            Circle()
              .fill(Color.gray.opacity(0.2))
          }
          .frame(width: 20, height: 20)
          .clipShape(Circle())
        } else {
          Image(systemName: "person.circle.fill")
            .resizable()
            .frame(width: 20, height: 20)
            .foregroundColor(.gray)
        }

        Text(performer.name)
          .font(.caption)
          .foregroundColor(.blue)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 8)
      .background(Color.blue.opacity(0.1))
      .cornerRadius(12)
      .contentShape(Rectangle())
    }
    .buttonStyle(PlainButtonStyle())
  }
}
