import Foundation
import SwiftUI

/// Entry in the session history
struct HistoryEntry: Identifiable, Equatable {
  let id = UUID()
  var scene: StashScene
  let timestamp: Date
  let startSeconds: Double?
  let markerTitle: String?

  static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool {
    lhs.id == rhs.id
  }
}

/// Manages the session history of viewed videos
@MainActor
class SessionHistoryManager: ObservableObject {
  static let shared = SessionHistoryManager()

  @Published private(set) var entries: [HistoryEntry] = []

  private init() {}

  /// Add a scene to history
  func addEntry(scene: StashScene, startSeconds: Double? = nil, markerTitle: String? = nil) {
    // Don't add duplicate if it's the same scene as the last entry
    if let lastEntry = entries.first, lastEntry.scene.id == scene.id {
      // Update the timestamp of the existing entry instead
      entries[0] = HistoryEntry(
        scene: scene,
        timestamp: Date(),
        startSeconds: startSeconds,
        markerTitle: markerTitle
      )
      print("📜 History: Updated existing entry for '\(scene.title ?? "Untitled")'")
      return
    }

    let entry = HistoryEntry(
      scene: scene,
      timestamp: Date(),
      startSeconds: startSeconds,
      markerTitle: markerTitle
    )

    // Insert at the beginning (most recent first)
    entries.insert(entry, at: 0)

    // Limit history to last 100 entries
    if entries.count > 100 {
      entries = Array(entries.prefix(100))
    }

    print("📜 History: Added '\(scene.title ?? "Untitled")' (total: \(entries.count))")
  }

  /// Update the stored scene for any matching history entries (e.g. after an o-counter
  /// increment) so the history view reflects the new value live.
  func updateScene(_ updated: StashScene) {
    // Mutate the scene in place so the entry's identity (id) is preserved and the
    // history card updates without re-creating/flickering.
    for index in entries.indices where entries[index].scene.id == updated.id {
      entries[index].scene = updated
    }
  }

  /// Clear all history
  func clearHistory() {
    entries.removeAll()
    print("📜 History: Cleared")
  }

  /// Remove a specific entry
  func removeEntry(_ entry: HistoryEntry) {
    entries.removeAll { $0.id == entry.id }
  }

  /// Get unique scenes (no duplicates based on scene ID)
  var uniqueScenes: [HistoryEntry] {
    var seenIds = Set<String>()
    return entries.filter { entry in
      if seenIds.contains(entry.scene.id) {
        return false
      }
      seenIds.insert(entry.scene.id)
      return true
    }
  }
}
