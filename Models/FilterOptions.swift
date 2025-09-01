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

    // Resolution filter
    if let resolution = selectedResolution {
      sceneFilter["resolution"] = [
        "value": resolution,
        "modifier": "EQUALS"
      ]
    }

    // Favorites filter
    if isFavoritesOnly {
      sceneFilter["favorite"] = [
        "value": true
      ]
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

    // Tags filter
    if !selectedTagIds.isEmpty {
      sceneFilter["tags"] = [
        "value": selectedTagIds,
        "modifier": "INCLUDES"
      ]
    }

    // Performers filter
    if !selectedPerformerIds.isEmpty {
      sceneFilter["performers"] = [
        "value": selectedPerformerIds,
        "modifier": "INCLUDES"
      ]
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
