import Foundation
import SwiftUI

class FilterOptions: ObservableObject {
  @Published var minimumRating: Int?
  @Published var selectedResolution: String?
  @Published var isFavoritesOnly: Bool = false
  @Published var minimumDuration: Int?
  @Published var maximumDuration: Int?
  @Published var selectedTagIds: [String] = []
  @Published var selectedPerformerIds: [String] = []
  @Published var sortField: String = "date"
  @Published var sortDirection: String = "DESC"

  // Generate filter for GraphQL query
  func generateSceneFilter() -> [String: Any] {
    var sceneFilter: [String: Any] = [:]

    // Rating filter
    if let rating = minimumRating {
      sceneFilter["rating100"] = [
        "value": rating,
        "modifier": "GREATER_THAN"
      ]
    }

    // Resolution filter — map display strings to Stash ResolutionEnum values
    if let resolution = selectedResolution {
      let enumValue: String
      switch resolution {
      case "240p": enumValue = "LOW"
      case "480p": enumValue = "STANDARD"
      case "720p": enumValue = "STANDARD_HD"
      case "1080p": enumValue = "FULL_HD"
      case "4K": enumValue = "FOUR_K"
      default: enumValue = "FULL_HD"
      }
      sceneFilter["resolution"] = [
        "value": enumValue,
        "modifier": "EQUALS"
      ]
    }

    // Favorites filter — performer_favorite is a bare Boolean in SceneFilterType
    if isFavoritesOnly {
      sceneFilter["performer_favorite"] = true
    }

    // Duration filter
    if let minDuration = minimumDuration {
      sceneFilter["duration"] = [
        "value": minDuration,
        "modifier": "GREATER_THAN"
      ]
    }

    if let maxDuration = maximumDuration {
      sceneFilter["duration"] = [
        "value": maxDuration,
        "modifier": "LESS_THAN"
      ]
    }

    // Tags filter — HierarchicalMultiCriterionInput
    if !selectedTagIds.isEmpty {
      sceneFilter["tags"] = [
        "value": selectedTagIds,
        "excludes": [] as [String],
        "modifier": "INCLUDES_ALL"
      ] as [String: Any]
    }

    // Performers filter — MultiCriterionInput
    if !selectedPerformerIds.isEmpty {
      sceneFilter["performers"] = [
        "value": selectedPerformerIds,
        "excludes": [] as [String],
        "modifier": "INCLUDES_ALL"
      ] as [String: Any]
    }

    return sceneFilter
  }

  // Reset all filters
  func reset() {
    minimumRating = nil
    selectedResolution = nil
    isFavoritesOnly = false
    minimumDuration = nil
    maximumDuration = nil
    selectedTagIds = []
    selectedPerformerIds = []
    sortField = "date"
    sortDirection = "DESC"
  }
}
