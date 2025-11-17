import Foundation

// MARK: - Saved Marker Search Model
struct SavedMarkerSearch: Codable, Identifiable, Equatable {
  let id: UUID
  let name: String
  let query: String
  let createdAt: Date

  init(id: UUID = UUID(), name: String, query: String, createdAt: Date = Date()) {
    self.id = id
    self.name = name
    self.query = query
    self.createdAt = createdAt
  }
}

// MARK: - Saved Marker Search Manager
class SavedMarkerSearchManager: ObservableObject {
  static let shared = SavedMarkerSearchManager()

  @Published var savedSearches: [SavedMarkerSearch] = []

  private let userDefaultsKey = "savedMarkerSearches"

  init() {
    loadSearches()
  }

  // MARK: - Load
  func loadSearches() {
    guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
          let searches = try? JSONDecoder().decode([SavedMarkerSearch].self, from: data) else {
      savedSearches = []
      return
    }
    savedSearches = searches.sorted { $0.createdAt > $1.createdAt }
    print("📚 Loaded \(savedSearches.count) saved marker searches")
  }

  // MARK: - Save
  func saveSearch(name: String, query: String) {
    // Check if a search with this name already exists
    if let existingIndex = savedSearches.firstIndex(where: { $0.name == name }) {
      // Update existing search
      savedSearches[existingIndex] = SavedMarkerSearch(
        id: savedSearches[existingIndex].id,
        name: name,
        query: query
      )
      print("📝 Updated existing saved search: \(name)")
    } else {
      // Create new search
      let newSearch = SavedMarkerSearch(name: name, query: query)
      savedSearches.insert(newSearch, at: 0)
      print("💾 Saved new marker search: \(name) - \(query)")
    }

    persistSearches()
  }

  // MARK: - Delete
  func deleteSearch(_ search: SavedMarkerSearch) {
    savedSearches.removeAll { $0.id == search.id }
    print("🗑️ Deleted saved search: \(search.name)")
    persistSearches()
  }

  // MARK: - Delete by ID
  func deleteSearch(id: UUID) {
    savedSearches.removeAll { $0.id == id }
    print("🗑️ Deleted saved search with id: \(id)")
    persistSearches()
  }

  // MARK: - Persist
  private func persistSearches() {
    guard let data = try? JSONEncoder().encode(savedSearches) else {
      print("❌ Failed to encode saved searches")
      return
    }
    UserDefaults.standard.set(data, forKey: userDefaultsKey)
    print("✅ Persisted \(savedSearches.count) saved searches to UserDefaults")
  }
}
