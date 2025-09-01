import SwiftUI

/// A customized version of SceneRow specifically for the PerformerDetailView
/// with direct performer navigation
struct CustomPerformerSceneRow: View {
  let scene: StashScene
  let performer: StashScene.Performer  // Add performer context
  @EnvironmentObject private var appModel: AppModel

  var body: some View {
    VStack(alignment: .leading) {
      // Thumbnail section - similar to SceneRow
      GeometryReader { _ in
        AsyncImage(url: URL(string: scene.paths.screenshot)) { image in
          image
            .resizable()
            .aspectRatio(16 / 9, contentMode: .fill)
        } placeholder: {
          Rectangle()
            .fill(Color.gray.opacity(0.2))
        }
        .onTapGesture {
          // Set performer context before navigation
          appModel.currentPerformer = performer
          print("🎯 PERFORMER CONTEXT: Set currentPerformer to \(performer.name) before navigation")
          appModel.navigateToScene(scene)
        }
      }
      .frame(height: 180)
      .clipShape(RoundedRectangle(cornerRadius: 8))

      // Info section
      VStack(alignment: .leading, spacing: 8) {
        // Title
        Button(action: {
          // Set performer context before navigation
          appModel.currentPerformer = performer
          print("🎯 PERFORMER CONTEXT: Set currentPerformer to \(performer.name) before navigation")
          appModel.navigateToScene(scene)
        }) {
          Text(scene.title ?? "Untitled")
            .font(.headline)
            .foregroundColor(.purple)
            .underline()
            .lineLimit(2)
        }

        // Performers - Using our direct navigation buttons
        if !scene.performers.isEmpty {
          HStack {
            ForEach(scene.performers) { performer in
              // ULTRA DIRECT APPROACH: use a button with delay for visual feedback
              Button {
                print("🚀🚀🚀 ULTRA DIRECT: Navigation to \(performer.name)")
                // Do something that will definitely cause a redraw
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()

                // Delay to ensure UI update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                  print("FORCING NAVIGATION TO \(performer.name)")
                  // Force navigation through multiple methods
                  appModel.api.scenes = []  // Clear scenes to force redraw
                  appModel.navigateToPerformer(performer)
                }
              } label: {
                Text(performer.name)
                  .font(.title3)  // Much larger font
                  .bold()  // Make it bolder
                  .foregroundColor(.blue)
                  .padding(.vertical, 8)
                  .padding(.horizontal, 8)
                  .background(Color.blue.opacity(0.1))  // Add background
                  .cornerRadius(8)  // Round corners
                  .contentShape(Rectangle())
              }
              .buttonStyle(PlainButtonStyle())

              if performer != scene.performers.last {
                Text("·")
                  .font(.subheadline)
                  .foregroundColor(.secondary)
                  .padding(.horizontal, 2)
              }
            }
          }
          .lineLimit(1)
        }

        // Tags - simplified
        if !scene.tags.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
              ForEach(scene.tags) { tag in
                Text(tag.name)
                  .font(.caption)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 4)
                  .background(Color.secondary.opacity(0.15))
                  .cornerRadius(12)
              }
            }
          }
        }
      }
      .padding(8)
    }
    .background(Color(UIColor.secondarySystemBackground))
    .cornerRadius(12)
    .shadow(radius: 2)
  }
}
