import SwiftUI

struct PerformerHeaderView: View {
  let performer: StashScene.Performer

  var body: some View {
    VStack(spacing: 16) {
      if let imagePath = performer.image_path {
        CachedAsyncImage(url: URL(string: imagePath), width: 400) { image in
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } placeholder: {
          Color.gray.opacity(0.2)
        }
        .frame(width: 200, height: 200)
        .clipShape(Circle())
      }

      VStack(spacing: 8) {
        Text(performer.name)
          .font(.title)

        if let sceneCount = performer.scene_count {
          Text("\(sceneCount) scenes")
            .foregroundColor(.secondary)
        }

        if let rating = performer.rating100 {
          HStack {
            ForEach(0..<5) { index in
              Image(systemName: index < rating / 20 ? "star.fill" : "star")
                .foregroundColor(.yellow)
            }
          }
        }
      }
    }
  }
}
