import SwiftUI

struct TagSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appModel: AppModel
    @Binding var selectedTagId: String
    @Binding var selectedTagName: String
    @State private var searchText = ""
    @State private var tags: [StashScene.Tag] = []
    @State private var recentTags: [StashScene.Tag] = []
    @State private var isLoading = false
    var onTagSelected: (String, String) -> Void = { _, _ in }
    
    var body: some View {
        List {
            if !recentTags.isEmpty && searchText.isEmpty {
                Section("Recent Tags") {
                    ForEach(recentTags) { tag in
                        Button(action: {
                            selectTag(tag)
                        }) {
                            Text(tag.name)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                removeFromRecents(tag)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            
            Section(searchText.isEmpty ? "All Tags" : "Search Results") {
                ForEach(tags) { tag in
                    Button(action: {
                        selectTag(tag)
                    }) {
                        Text(tag.name)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                }
            }
        }
        .preferredColorScheme(colorScheme)
        .searchable(text: $searchText)
        .onChange(of: searchText) { _, newValue in
            Task {
                await searchTags(query: newValue)
            }
        }
        .navigationTitle("Select Tag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .task {
            print("🏷️ Initial load of TagSelectionView")
            await loadRecentTags()
            await searchTags(query: "")
        }
    }
    
    private func selectTag(_ tag: StashScene.Tag) {
        print("🏷️ Selected tag: \(tag.name) (\(tag.id))")
        selectedTagId = tag.id
        selectedTagName = tag.name
        onTagSelected(tag.id, tag.name)
        
        // Save to recent tags and increment usage
        var tagUsage = UserDefaults.standard.dictionary(forKey: "tagUsageCounts") as? [String: Int] ?? [:]
        let currentCount = (tagUsage[tag.id] ?? 0) + 1
        tagUsage[tag.id] = currentCount
        UserDefaults.standard.set(tagUsage, forKey: "tagUsageCounts")
        print("🏷️ Updated usage count for \(tag.name) to \(currentCount)")
        
        // Save to recent tags if used 2+ times
        if currentCount >= 2 {
            print("🏷️ Adding \(tag.name) to recent tags (used \(currentCount) times)")
            saveRecentTagSync(tag)
        } else {
            print("🏷️ Not adding \(tag.name) to recent tags yet (only used \(currentCount) time(s))")
        }
        
        dismiss()
    }
    
    private func saveRecentTagSync(_ tag: StashScene.Tag) {
        var recentTagIds = UserDefaults.standard.array(forKey: "recentTags") as? [String] ?? []
        print("🏷️ Current recent tags: \(recentTagIds)")
        
        // Remove if already exists
        recentTagIds.removeAll { $0 == tag.id }
        
        // Add to front
        recentTagIds.insert(tag.id, at: 0)
        
        // Keep only last 5 tags
        if recentTagIds.count > 5 {
            recentTagIds = Array(recentTagIds.prefix(5))
        }
        
        UserDefaults.standard.set(recentTagIds, forKey: "recentTags")
        print("🏷️ Saved recent tags: \(recentTagIds)")
        
        // Update the view immediately with what we have
        recentTags = recentTagIds.compactMap { tagId in
            tags.first { $0.id == tagId }
        }
    }
    
    private func loadRecentTags() async {
        let tagUsage = UserDefaults.standard.dictionary(forKey: "tagUsageCounts") as? [String: Int] ?? [:]
        let recentTagIds = UserDefaults.standard.array(forKey: "recentTags") as? [String] ?? []

        print("🏷️ Found \(recentTagIds.count) recent tag IDs: \(recentTagIds)")
        print("🏷️ Tag usage counts: \(tagUsage)")

        // Fetch any missing recent tags
        let missingTagIds = recentTagIds.filter { tagId in
            !tags.contains { $0.id == tagId }
        }

        if !missingTagIds.isEmpty {
            print("🏷️ Fetching \(missingTagIds.count) missing tags")
            do {
                for tagId in missingTagIds {
                    try await appModel.api.findTag(id: tagId) { result in
                        if case .success(let tag) = result {
                            self.tags.append(tag)
                        }
                    }
                }
            } catch {
                print("❌ Error fetching missing tags: \(error)")
            }
        }
        
        print("🏷️ Available tags: \(tags.map { "\($0.name) (\($0.id))" }.joined(separator: ", "))")
        
        // Only show tags used 2+ times
        recentTags = recentTagIds.compactMap { tagId in
            if let usageCount = tagUsage[tagId], usageCount >= 2 {
                if let tag = tags.first(where: { $0.id == tagId }) {
                    print("🏷️ Including recent tag: \(tag.name) (ID: \(tag.id), used \(usageCount) times)")
                    return tag
                } else {
                    print("🏷️ Could not find tag with ID: \(tagId) in available tags")
                }
            } else {
                print("🏷️ Tag \(tagId) has insufficient usage count: \(tagUsage[tagId] ?? 0)")
            }
            return nil
        }
        
        print("🏷️ Final recent tags: \(recentTags.map { "\($0.name) (\($0.id))" }.joined(separator: ", "))")
    }
    
    private func searchTags(query: String) async {
        do {
            try await appModel.api.searchTags(query: query) { result in
                switch result {
                case .success(let foundTags):
                    self.tags = foundTags
                    print("🏷️ Loaded \(self.tags.count) tags from search")
                    Task {
                        await self.loadRecentTags()
                    }
                case .failure(let error):
                    print("❌ Error searching tags: \(error)")
                }
            }
        } catch {
            print("❌ Error searching tags: \(error)")
        }
    }
    
    private func removeFromRecents(_ tag: StashScene.Tag) {
        print("🏷️ Removing \(tag.name) from recent tags")
        
        // Remove from UserDefaults
        var recentTagIds = UserDefaults.standard.array(forKey: "recentTags") as? [String] ?? []
        recentTagIds.removeAll { $0 == tag.id }
        UserDefaults.standard.set(recentTagIds, forKey: "recentTags")
        
        // Remove from usage counts
        var tagUsage = UserDefaults.standard.dictionary(forKey: "tagUsageCounts") as? [String: Int] ?? [:]
        tagUsage.removeValue(forKey: tag.id)
        UserDefaults.standard.set(tagUsage, forKey: "tagUsageCounts")
        
        // Update the view
        recentTags.removeAll { $0.id == tag.id }
    }
} 