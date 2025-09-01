import Foundation

/// Scene filter type for Stash API requests
struct SceneFilterType {
  /// Tag IDs to filter by
  var tags: [String]?
  /// Tag IDs to exclude
  var excludedTags: [String]?
  /// Performer IDs to filter by
  var performers: [String]?
  /// Studio IDs to filter by
  var studios: [String]?
  /// Search term for filtering scenes
  var searchTerm: String?
  /// Minimum duration in seconds
  var minDuration: Int?
  /// Maximum duration in seconds
  var maxDuration: Int?
  /// Minimum rating (0-100)
  var minRating: Int?
  /// Whether to only include favorites
  var favoritesOnly: Bool?

  init(
    tags: [String]? = nil,
    excludedTags: [String]? = ["vr"],  // Default to excluding VR tag
    performers: [String]? = nil,
    studios: [String]? = nil,
    searchTerm: String? = nil,
    minDuration: Int? = nil,
    maxDuration: Int? = nil,
    minRating: Int? = nil,
    favoritesOnly: Bool? = nil
  ) {
    self.tags = tags
    self.excludedTags = excludedTags
    self.performers = performers
    self.studios = studios
    self.searchTerm = searchTerm
    self.minDuration = minDuration
    self.maxDuration = maxDuration
    self.minRating = minRating
    self.favoritesOnly = favoritesOnly
  }

  /// Converts FilterOptions to SceneFilterType
  static func fromFilterOptions(_ options: FilterOptions) -> SceneFilterType {
    return SceneFilterType(
      tags: options.selectedTagIds.isEmpty ? nil : options.selectedTagIds,
      excludedTags: ["vr"],  // Always exclude VR content
      performers: options.selectedPerformerIds.isEmpty ? nil : options.selectedPerformerIds,
      minDuration: options.minimumDuration,
      maxDuration: options.maximumDuration,
      minRating: options.minimumRating,
      favoritesOnly: options.isFavoritesOnly ? true : nil
    )
  }

  /// Helper method to create a filter that excludes VR content
  static func withoutVR() -> SceneFilterType {
    return SceneFilterType(excludedTags: ["vr"])
  }
}
