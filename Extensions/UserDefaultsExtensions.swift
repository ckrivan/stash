import Foundation

extension UserDefaults {
  func setVideoProgress(_ progress: Double, for sceneId: String) {
    set(progress, forKey: "video_progress_\(sceneId)")
  }

  func getVideoProgress(for sceneId: String) -> Double {
    return double(forKey: "video_progress_\(sceneId)")
  }
}
