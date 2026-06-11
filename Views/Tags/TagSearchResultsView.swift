import SwiftUI

struct TagSearchResultsView: View {
  let scenes: [StashScene]
  let tagName: String
  let tagId: String
  @EnvironmentObject private var appModel: AppModel
  @State private var isShufflePressed = false

  private var columns: [GridItem] {
    if UIDevice.current.userInterfaceIdiom == .pad {
      return [GridItem(.adaptive(minimum: 350, maximum: 450), spacing: 20)]
    } else {
      return [GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)]
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      // ALWAYS show shuffle button when there are scenes
      if !scenes.isEmpty {
        prominentShuffleButton
      }

      ScrollView {
        LazyVGrid(columns: columns, spacing: 20) {
          ForEach(scenes, id: \.id) { scene in
            SceneRow(
              scene: scene,
              onTagSelected: { tag in
                appModel.navigateToTag(tag)
              },
              onPerformerSelected: { performer in
                appModel.navigateToPerformer(performer)
              },
              onSceneUpdated: { updatedScene in
                if let index = appModel.api.scenes.firstIndex(where: { $0.id == updatedScene.id }) {
                  appModel.api.scenes[index] = updatedScene
                }
              },
              onSceneSelected: { scene in
                appModel.navigateToScene(scene)
              }
            )
            .onTapGesture {
              appModel.navigateToScene(scene)
            }
          }
        }
        .padding(.horizontal)
      }
    }
  }

  private var prominentShuffleButton: some View {
    VStack(spacing: 8) {
      // Big prominent shuffle button
      Button(action: {
        print("🏷️ PROMINENT SHUFFLE BUTTON TAPPED - TAG: \(tagName)")
        print("🏷️ Current displayed scenes: \(scenes.count)")
        print("🏷️ Loading ALL scenes with tag '\(tagName)' from server...")

        // Visual feedback
        isShufflePressed = true

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Save the search context
        appModel.searchQuery = tagName

        // Start the shuffle
        appModel.startTagSceneShuffle(forTag: tagId, tagName: tagName, displayedScenes: scenes)

        // Reset button state after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          isShufflePressed = false
        }
      }) {
        HStack(spacing: 12) {
          Image(systemName: "shuffle.circle.fill")
            .font(.system(size: 24, weight: .bold))

          VStack(alignment: .leading, spacing: 2) {
            Text("Shuffle All \(tagName)")
              .font(.title2)
              .fontWeight(.bold)
            Text("\(scenes.count) scenes shown • Load ALL from server")
              .font(.caption)
              .opacity(0.9)
          }

          Spacer()

          Image(systemName: "chevron.right")
            .font(.system(size: 16, weight: .semibold))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassEffect(.regular.tint(.pink.opacity(0.7)).interactive())
      }
      .scaleEffect(isShufflePressed ? 0.95 : 1.0)
      .animation(.spring(response: 0.3), value: isShufflePressed)

      // Active shuffle status
      if appModel.isTagSceneShuffleMode {
        HStack(spacing: 8) {
          Image(systemName: "play.circle.fill")
            .foregroundColor(.green)
          Text("Shuffle Active • \(appModel.tagSceneShuffleQueue.count) in queue")
            .font(.caption)
            .fontWeight(.medium)

          Spacer()

          Button("Stop") {
            appModel.stopTagSceneShuffle()
          }
          .font(.caption)
          .foregroundColor(.red)
          .padding(.horizontal, 12)
          .padding(.vertical, 4)
          .background(Color.red.opacity(0.1))
          .cornerRadius(8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
        .transition(.opacity)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(Color(.systemBackground))
  }
}
