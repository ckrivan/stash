import SwiftUI

struct PerformerSelectionListView: View {
  @EnvironmentObject private var appModel: AppModel
  @Environment(\.dismiss) private var dismiss
  @Binding var selectedPerformerIds: [String]
  @State private var searchText = ""
  @State private var allPerformers: [StashScene.Performer] = []
  @State private var isLoading = false

  private var columns: [GridItem] {
    // Use more columns and larger images on iPad
    if UIDevice.current.userInterfaceIdiom == .pad {
      return [
        GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 20)
      ]
    } else {
      return [
        GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 16)
      ]
    }
  }

  var body: some View {
    VStack {
      if selectedPerformerIds.isEmpty {
        Text("No performers selected")
          .foregroundColor(.secondary)
          .italic()
          .padding()
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 12) {
            ForEach(selectedPerformers) { performer in
              VStack {
                if let imagePath = performer.image_path {
                  AsyncImage(url: URL(string: imagePath)) { image in
                    image
                      .resizable()
                      .aspectRatio(contentMode: .fill)
                  } placeholder: {
                    Color.gray
                  }
                  .frame(width: 60, height: 60)
                  .clipShape(Circle())
                } else {
                  Circle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 60, height: 60)
                    .overlay(
                      Image(systemName: "person.fill")
                        .foregroundColor(.white)
                    )
                }

                Text(performer.name)
                  .font(.caption)
                  .lineLimit(1)

                Button(action: {
                  removePerformerId(performer.id)
                }) {
                  Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                }
                .buttonStyle(BorderlessButtonStyle())
              }
              .frame(width: 80)
              .padding(.vertical, 8)
            }
          }
          .padding(.horizontal)
        }
        .background(Color.secondary.opacity(0.1))
      }

      Divider()

      if isLoading {
        ProgressView()
          .scaleEffect(1.2)
          .padding()
      } else if filteredPerformers.isEmpty && !searchText.isEmpty {
        Text("No performers found")
          .foregroundColor(.secondary)
          .italic()
          .padding()
      } else {
        ScrollView {
          LazyVGrid(columns: columns, spacing: 16) {
            ForEach(filteredPerformers) { performer in
              Button(action: {
                togglePerformerId(performer.id)
              }) {
                VStack {
                  if let imagePath = performer.image_path {
                    AsyncImage(url: URL(string: imagePath)) { image in
                      image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    } placeholder: {
                      Color.gray
                    }
                    .frame(
                      width: UIDevice.current.userInterfaceIdiom == .pad ? 100 : 80,
                      height: UIDevice.current.userInterfaceIdiom == .pad ? 100 : 80
                    )
                    .clipShape(Circle())
                    .overlay(
                      Circle()
                        .stroke(
                          selectedPerformerIds.contains(performer.id) ? Color.blue : Color.clear,
                          lineWidth: 3
                        )
                    )
                  } else {
                    Circle()
                      .fill(Color.gray.opacity(0.5))
                      .frame(
                        width: UIDevice.current.userInterfaceIdiom == .pad ? 100 : 80,
                        height: UIDevice.current.userInterfaceIdiom == .pad ? 100 : 80
                      )
                      .overlay(
                        Image(systemName: "person.fill")
                          .foregroundColor(.white)
                      )
                      .overlay(
                        Circle()
                          .stroke(
                            selectedPerformerIds.contains(performer.id) ? Color.blue : Color.clear,
                            lineWidth: 3
                          )
                      )
                  }

                  Text(performer.name)
                    .font(.caption)
                    .lineLimit(1)

                  if let count = performer.scene_count {
                    Text("\(count) scenes")
                      .font(.caption2)
                      .foregroundColor(.secondary)
                  }

                  if selectedPerformerIds.contains(performer.id) {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundColor(.blue)
                      .scaleEffect(1.2)
                  }
                }
                .padding(.vertical, 8)
              }
              .buttonStyle(PlainButtonStyle())
            }
          }
          .padding()
        }
      }
    }
    .navigationTitle("Select Performers")
    .searchable(text: $searchText, prompt: "Search performers...")
    .onChange(of: searchText) { _, newValue in
      Task {
        await searchPerformers(query: newValue)
      }
    }
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button("Done") {
          dismiss()
        }
      }
    }
    .task {
      await loadPerformers()
    }
  }

  // Get the actual performer objects from the selected IDs
  private var selectedPerformers: [StashScene.Performer] {
    return allPerformers.filter { performer in
      selectedPerformerIds.contains(performer.id)
    }
  }

  private var filteredPerformers: [StashScene.Performer] {
    if searchText.isEmpty {
      return allPerformers
    } else {
      return allPerformers.filter { performer in
        performer.name.localizedCaseInsensitiveContains(searchText)
      }
    }
  }

  private func loadPerformers() async {
    isLoading = true
    await appModel.api.fetchPerformers(
      filter: .all, page: 1, appendResults: false, search: ""
    ) { result in
      switch result {
      case .success(let performers):
        self.allPerformers = performers
      case .failure(let error):
        print("Error loading performers: \(error)")
      }
      self.isLoading = false
    }
  }

  private func searchPerformers(query: String) async {
    isLoading = true

    // TODO: Implement performer search API call
    // For now, we'll just filter locally
    isLoading = false
  }

  private func togglePerformerId(_ performerId: String) {
    if selectedPerformerIds.contains(performerId) {
      selectedPerformerIds.removeAll { $0 == performerId }
    } else {
      selectedPerformerIds.append(performerId)
    }
  }

  private func removePerformerId(_ performerId: String) {
    selectedPerformerIds.removeAll { $0 == performerId }
  }
}

#Preview {
  NavigationStack {
    PerformerSelectionListView(selectedPerformerIds: .constant([]))
      .environmentObject(AppModel())
  }
}
