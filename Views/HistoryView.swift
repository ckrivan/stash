import SwiftUI

struct HistoryView: View {
  @EnvironmentObject private var appModel: AppModel

  private var columns: [GridItem] {
    if UIDevice.current.userInterfaceIdiom == .pad {
      return [GridItem(.adaptive(minimum: 350, maximum: 450), spacing: 20)]
    } else {
      return [GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)]
    }
  }

  var body: some View {
    ScrollView {
      if appModel.watchHistory.isEmpty {
        VStack(spacing: 20) {
          Spacer().frame(height: 100)

          Image(systemName: "clock.arrow.circlepath")
            .font(.system(size: 80))
            .foregroundColor(.gray.opacity(0.5))

          Text("No Watch History")
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)

          Text("Videos you watch will appear here")
            .font(.body)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)

          Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
      } else {
        VStack(alignment: .leading, spacing: 20) {
          // Header with count and clear button
          HStack {
            Text("Watch History")
              .font(.largeTitle)
              .fontWeight(.bold)

            Spacer()

            Button(action: {
              appModel.watchHistory.removeAll()
            }) {
              Label("Clear History", systemImage: "trash")
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.red)
          }
          .padding(.horizontal)
          .padding(.top)

          // History grid
          LazyVGrid(columns: columns, spacing: 20) {
            ForEach(appModel.watchHistory.reversed()) { scene in
              SceneRow(
                scene: scene,
                onTagSelected: { tag in
                  // Navigate to tag view
                  appModel.navigationPath.append(tag)
                },
                onPerformerSelected: { performer in
                  // Navigate to performer view
                  appModel.navigationPath.append(performer)
                },
                onSceneUpdated: { updatedScene in
                  // Update the scene in history if needed
                  if let index = appModel.watchHistory.firstIndex(where: {
                    $0.id == updatedScene.id
                  }) {
                    appModel.watchHistory[index] = updatedScene
                  }
                },
                onSceneSelected: { selectedScene in
                  // Navigate to video player
                  appModel.navigationPath.append(selectedScene)
                }
              )
            }
          }
          .padding(.horizontal)
          .padding(.bottom, 100)  // Extra padding for tab bar
        }
      }
    }
    .background(Color(.systemBackground))
  }
}

#Preview {
  HistoryView()
    .environmentObject(AppModel())
}
