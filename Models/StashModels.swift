import Foundation

// MARK: - Models
struct StashScene: Identifiable, Decodable, Equatable, Hashable {
  let id: String
  let title: String?
  let details: String?
  let paths: ScenePaths
  let files: [SceneFile]
  let performers: [Performer]
  let tags: [Tag]
  let rating100: Int?
  let o_counter: Int?

  static func == (lhs: StashScene, rhs: StashScene) -> Bool {
    return lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  struct ScenePaths: Decodable, Equatable {
    let screenshot: String
    let preview: String?
    let stream: String
  }

  struct SceneFile: Decodable, Equatable {
    let size: Int?
    let duration: Float?
    let video_codec: String?
    let width: Int?
    let height: Int?

    var formattedSize: String {
      guard let size = size else { return "Unknown" }
      let bytes = Double(size)
      let units = ["B", "KB", "MB", "GB"]
      var level = 0
      var value = bytes

      while value > 1024 && level < units.count - 1 {
        value /= 1024
        level += 1
      }

      return String(format: "%.1f %@", value, units[level])
    }
  }

  struct Performer: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let name: String
    let gender: String?
    let image_path: String?
    let scene_count: Int?
    let favorite: Bool?
    let rating100: Int?

    func hash(into hasher: inout Hasher) {
      hasher.combine(id)
    }

    static func == (lhs: Performer, rhs: Performer) -> Bool {
      return lhs.id == rhs.id
    }
  }

  struct Tag: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let name: String

    func hash(into hasher: inout Hasher) {
      hasher.combine(id)
    }
  }
}

// Removed duplicate GraphQL response types

struct SceneMarker: Identifiable, Decodable, Equatable, Hashable {
  let id: String
  let title: String
  let seconds: Float
  let end_seconds: Float?
  let stream: String
  let preview: String
  let screenshot: String
  let scene: MarkerScene
  let primary_tag: Tag
  let tags: [Tag]

  // Computed property to format the time
  var formattedTime: String {
    let totalSeconds = Int(seconds)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%02d:%02d", minutes, seconds)
    }
  }

  struct MarkerScene: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let title: String?
    let paths: ScenePaths?
    let performers: [StashScene.Performer]?
    let files: [VideoFile]?

    // For backward compatibility
    enum CodingKeys: String, CodingKey {
      case id
      case title
      case paths
      case performers
      case files
    }

    // Default initializer that only requires id
    init(id: String) {
      self.id = id
      self.title = nil
      self.paths = nil
      self.performers = nil
      self.files = nil
    }

    // Full initializer for when we have all data
    init(
      id: String, title: String?, paths: ScenePaths?, performers: [StashScene.Performer]?,
      files: [VideoFile]? = nil
    ) {
      self.id = id
      self.title = title
      self.paths = paths
      self.performers = performers
      self.files = files
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      id = try container.decode(String.self, forKey: .id)
      title = try container.decodeIfPresent(String.self, forKey: .title)
      paths = try container.decodeIfPresent(ScenePaths.self, forKey: .paths)
      performers = try container.decodeIfPresent([StashScene.Performer].self, forKey: .performers)
      files = try container.decodeIfPresent([VideoFile].self, forKey: .files)
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(id)
    }

    struct ScenePaths: Decodable, Equatable {
      let screenshot: String?
      let preview: String?
      let stream: String?
    }

    struct VideoFile: Decodable, Equatable, Hashable {
      let width: Int?
      let height: Int?
      let path: String?
    }
  }

  struct Tag: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let name: String

    func hash(into hasher: inout Hasher) {
      hasher.combine(id)
    }
  }

  static func == (lhs: SceneMarker, rhs: SceneMarker) -> Bool {
    return lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

struct SceneMarkersResponse: Decodable {
  let findSceneMarkers: FindSceneMarkersResult

  struct FindSceneMarkersResult: Decodable {
    let scene_markers: [SceneMarker]
    let count: Int
  }
}

struct SceneMarkerTagsResponse: Decodable {
  let sceneMarkerTags: [SceneMarkerTag]

  struct SceneMarkerTag: Decodable {
    let tag: Tag
    let scene_markers: [SceneMarker]

    struct Tag: Decodable {
      let id: String
      let name: String
    }
  }
}

struct TagCreateResponse: Decodable {
  let tagCreate: StashScene.Tag?
}

struct SceneUpdateResponse: Decodable {
  let sceneUpdate: StashScene?
}
