import SwiftUI

struct TagEditorView: View {
    let scene: StashScene
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedTags: Set<String>
    @State private var newTagName = ""
    @State private var showingNewTagAlert = false
    @State private var isLoading = false
    @State private var currentTags: [StashScene.Tag]
    @State private var searchText = ""
    @State private var searchResults: [StashScene.Tag] = []
    @State private var errorMessage: String?
    @State private var showingError = false
    var onTagsUpdated: (StashScene) -> Void
    
    init(scene: StashScene, onTagsUpdated: @escaping (StashScene) -> Void = { _ in }) {
        self.scene = scene
        self.onTagsUpdated = onTagsUpdated
        _selectedTags = State(initialValue: Set(scene.tags.map { $0.id }))
        _currentTags = State(initialValue: scene.tags)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Search", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(UIColor.systemGray6))
                    
                    // Content
                    List {
                        if !currentTags.isEmpty {
                            Section(header: Text("CURRENT TAGS").foregroundColor(.gray)) {
                                ForEach(currentTags) { tag in
                                    HStack {
                                        Text(tag.name)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .onDelete { indexSet in
                                    for index in indexSet {
                                        let tag = currentTags[index]
                                        selectedTags.remove(tag.id)
                                        currentTags.remove(at: index)
                                    }
                                }
                            }
                        }
                        
                        if !searchResults.isEmpty {
                            Section(header: Text("AVAILABLE TAGS").foregroundColor(.gray)) {
                                ForEach(searchResults) { tag in
                                    HStack {
                                        Text(tag.name)
                                            .foregroundColor(.white)
                                        Spacer()
                                        if selectedTags.contains(tag.id) {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        toggleTag(tag)
                                    }
                                }
                            }
                        }
                        
                        Section {
                            Button(action: { showingNewTagAlert = true }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add New Tag")
                                }
                                .foregroundColor(.blue)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Edit Tags")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            isLoading = true
                            do {
                                let updatedScene = try await appModel.api.updateSceneTags(sceneID: scene.id, tagIDs: Array(selectedTags))
                                isLoading = false
                                onTagsUpdated(updatedScene)
                                dismiss()
                            } catch {
                                print("Error updating tags: \(error)")
                                isLoading = false
                            }
                        }
                    }
                    .disabled(isLoading)
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            searchTags(query: newValue)
        }
        .alert("Add New Tag", isPresented: $showingNewTagAlert) {
            TextField("Tag Name", text: $newTagName)
            Button("Cancel", role: .cancel) { }
            Button("Add") {
                Task {
                    do {
                        let newTag = try await appModel.api.createTag(name: newTagName)
                        selectedTags.insert(newTag.id)
                        currentTags.append(newTag)
                        newTagName = ""
                    } catch {
                        print("Error creating tag: \(error)")
                    }
                }
            }
        }
    }
    
    private func searchTags(query: String) {
        Task {
            if !query.isEmpty {
                do {
                    searchResults = try await appModel.api.searchTags(query: query)
                } catch {
                    print("Error searching tags: \(error)")
                }
            } else {
                searchResults = []
            }
        }
    }
    
    private func toggleTag(_ tag: StashScene.Tag) {
        if selectedTags.contains(tag.id) {
            selectedTags.remove(tag.id)
            currentTags.removeAll { $0.id == tag.id }
        } else {
            selectedTags.insert(tag.id)
            currentTags.append(tag)
        }
    }
} 