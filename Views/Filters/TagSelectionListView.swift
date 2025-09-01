import SwiftUI

struct TagSelectionListView: View {
  @EnvironmentObject private var appModel: AppModel
  @Environment(\.dismiss) private var dismiss
  @Binding var selectedTagIds: [String]
  @State private var searchText = ""
  @State private var allTags: [StashScene.Tag] = []
  @State private var isLoading = false

  var body: some View {
    List {
      Section(header: Text("Selected Tags (\(selectedTagIds.count))")) {
        if selectedTagIds.isEmpty {
          Text("No tags selected")
            .foregroundColor(.secondary)
            .italic()
        } else {
          ForEach(allTags.filter { tag in selectedTagIds.contains(tag.id) }) { tag in
            HStack {
              Text(tag.name)
              Spacer()
              Button(action: {
                removeTagId(tag.id)
              }) {
                Image(systemName: "xmark.circle.fill")
                  .foregroundColor(.red)
              }
            }
          }
        }
      }

      if isLoading {
        Section {
          HStack {
            Spacer()
            ProgressView()
              .scaleEffect(1.2)
            Spacer()
          }
          .padding()
        }
      } else {
        Section(header: Text(searchText.isEmpty ? "All Tags" : "Search Results")) {
          ForEach(filteredTags) { tag in
            HStack {
              Text(tag.name)
              Spacer()
              if selectedTagIds.contains(tag.id) {
                Image(systemName: "checkmark")
                  .foregroundColor(.blue)
              }
            }
            .contentShape(Rectangle())
            .onTapGesture {
              toggleTagId(tag.id)
            }
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Select Tags")
    .searchable(text: $searchText, prompt: "Search tags...")
    .onChange(of: searchText) { _, newValue in
      Task {
        await searchTags(query: newValue)
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
      await loadTags()
    }
  }

  private var filteredTags: [StashScene.Tag] {
    if searchText.isEmpty {
      return allTags
    } else {
      return allTags.filter { tag in
        tag.name.localizedCaseInsensitiveContains(searchText)
      }
    }
  }

  private func loadTags() async {
    isLoading = true
    do {
      try await appModel.api.searchTags(query: "") { result in
        switch result {
        case .success(let tags):
          self.allTags = tags
        case .failure(let error):
          print("Error loading tags: \(error)")
        }
        self.isLoading = false
      }
    } catch {
      print("Error loading tags: \(error)")
      isLoading = false
    }
  }

  private func searchTags(query: String) async {
    guard !query.isEmpty else {
      return
    }

    isLoading = true
    do {
      try await appModel.api.searchTags(query: query) { result in
        switch result {
        case .success(let tags):
          self.allTags = tags
        case .failure(let error):
          print("Error searching tags: \(error)")
        }
        self.isLoading = false
      }
    } catch {
      print("Error searching tags: \(error)")
      isLoading = false
    }
  }

  private func toggleTagId(_ tagId: String) {
    if selectedTagIds.contains(tagId) {
      selectedTagIds.removeAll { $0 == tagId }
    } else {
      selectedTagIds.append(tagId)
    }
  }

  private func removeTagId(_ tagId: String) {
    selectedTagIds.removeAll { $0 == tagId }
  }
}

#Preview {
  NavigationStack {
    TagSelectionListView(selectedTagIds: .constant([]))
      .environmentObject(AppModel())
  }
}
