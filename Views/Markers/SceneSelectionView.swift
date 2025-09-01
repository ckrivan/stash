import SwiftUI

struct SceneSelectionView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appModel: AppModel
  @Binding var selectedScene: StashScene?
  @State private var searchText = ""
  @State private var scenes: [StashScene] = []
  @State private var isLoading = false
  @State private var currentPage = 1
  @State private var hasMorePages = true

  private let columns = [
    GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(columns: columns, spacing: 16) {
          ForEach(scenes) { scene in
            Button(action: {
              selectedScene = scene
              dismiss()
            }) {
              SceneRow(
                scene: scene,
                onTagSelected: { _ in },
                onPerformerSelected: { _ in },
                onSceneUpdated: { _ in },
                onSceneSelected: { _ in }
              )
            }
            .buttonStyle(PlainButtonStyle())
            .onAppear {
              if scene == scenes.last && !isLoading && hasMorePages {
                Task {
                  await loadMoreScenes()
                }
              }
            }
          }

          if isLoading {
            ProgressView()
              .gridCellColumns(columns.count)
              .padding()
          }
        }
        .padding()
      }
      .searchable(text: $searchText)
      .onChange(of: searchText) { _, newValue in
        Task {
          await searchScenes(query: newValue)
        }
      }
      .navigationTitle("Select Scene")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }
      }
    }
    .task {
      await loadScenes()
    }
  }

  private func loadScenes() async {
    isLoading = true
    currentPage = 1

    // Use regular search with empty string to get all scenes
    let result = try? await appModel.api.searchScenes(query: "")
    if let foundScenes = result {
      scenes = foundScenes
    } else {
      scenes = []
    }

    isLoading = false
  }

  private func loadMoreScenes() async {
    guard !isLoading else { return }

    isLoading = true
    currentPage += 1

    // We'll simulate pagination for now
    // In a real implementation, you'd want to add page parameter to searchScenes
    let previousCount = scenes.count
    hasMorePages = false  // For simplicity, disable pagination for now
    isLoading = false
  }

  private func searchScenes(query: String) async {
    guard !query.isEmpty else {
      await loadScenes()
      return
    }

    isLoading = true

    let result = try? await appModel.api.searchScenes(query: query)
    if let foundScenes = result {
      scenes = foundScenes
    } else {
      scenes = []
    }

    isLoading = false
  }
}
