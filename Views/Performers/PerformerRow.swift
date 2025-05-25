import SwiftUI

struct PerformerRow: View {
    let performer: StashScene.Performer
    
    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            // Image
            if let imagePath = performer.image_path {
                AsyncImage(url: URL(string: imagePath)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
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
        PerformerRow(performer: StashScene.Performer(
            id: "1",
            name: "Test Performer",
            gender: "FEMALE",
            image_path: nil,
            scene_count: 10,
            favorite: false,
            rating100: 80
        ))
        .previewLayout(.sizeThatFits)
        .padding()
    }
}