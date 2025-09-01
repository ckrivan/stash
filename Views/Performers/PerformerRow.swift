import SwiftUI

struct PerformerRow: View {
  let performer: StashScene.Performer

  var body: some View {
    VStack(alignment: .center, spacing: 12) {
      // Image
      if let imagePath = performer.image_path {
        AsyncImage(url: URL(string: imagePath)) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .aspectRatio(contentMode: .fill)
          case .failure:
            Image(systemName: "person.circle.fill")
              .foregroundColor(.gray)
              .font(.system(size: 60))
          case .empty:
            Color.gray.opacity(0.3)
          @unknown default:
            Color.gray.opacity(0.3)
          }
        }
        .frame(width: 120, height: 120)
        .clipShape(Circle())
      } else {
        Image(systemName: "person.circle.fill")
          .foregroundColor(.gray)
          .font(.system(size: 60))
          .frame(width: 120, height: 120)
      }

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
