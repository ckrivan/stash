import AVKit
import Foundation
import SwiftUI
import UIKit

/// Utility class for handling video player URLs and requests
class VideoPlayerUtility {

  /// Codecs that iOS can play natively without transcoding
  /// These don't need HLS transcoding and can be direct played
  static let directPlayCodecs: Set<String> = [
    "h264", "avc", "avc1",           // H.264/AVC variants
    "hevc", "h265", "hev1", "hvc1",  // HEVC/H.265 variants
    "mpeg4", "mp4v",                  // MPEG-4 Part 2
    "prores"                          // ProRes (Apple devices)
  ]

  /// Check if a video codec can be direct played on iOS without HLS transcoding
  /// - Parameter codec: The video codec string from the scene file
  /// - Returns: True if the codec can be played natively
  static func canDirectPlay(codec: String?) -> Bool {
    guard let codec = codec?.lowercased() else {
      // If codec is unknown, default to HLS for safety
      return false
    }

    let canPlay = directPlayCodecs.contains(codec)
    print("🎬 Codec '\(codec)' can direct play: \(canPlay)")
    return canPlay
  }

  /// Gets the appropriate stream URL based on codec compatibility
  /// - Parameters:
  ///   - scene: The scene to get the stream URL for
  ///   - startTime: Optional start time in seconds
  /// - Returns: The best URL for playback (direct or HLS)
  static func getStreamURL(for scene: StashScene, startTime: Double? = nil) -> URL? {
    guard let streamURLString = scene.paths.stream,
          let baseURL = URL(string: streamURLString) else {
      print("❌ No stream URL available for scene \(scene.id)")
      return nil
    }

    let codec = scene.files.first?.video_codec

    if canDirectPlay(codec: codec) {
      // Use direct stream URL for compatible codecs
      print("✅ Using direct play for scene \(scene.id) with codec: \(codec ?? "unknown")")
      return getDirectStreamURL(from: baseURL, startTime: startTime)
    } else {
      // Use HLS for incompatible codecs that need transcoding
      print("🔄 Using HLS transcoding for scene \(scene.id) with codec: \(codec ?? "unknown")")
      return getHLSStreamURL(from: baseURL, startTime: startTime)
    }
  }

  /// Gets a direct stream URL (non-HLS) with proper parameters
  /// - Parameters:
  ///   - directURL: The base direct stream URL
  ///   - startTime: Optional start time in seconds
  /// - Returns: The configured direct stream URL
  static func getDirectStreamURL(from directURL: URL, startTime: Double? = nil) -> URL? {
    var urlString = directURL.absoluteString

    // Remove .m3u8 if present (in case we're converting from HLS back to direct)
    urlString = urlString.replacingOccurrences(of: "/stream.m3u8", with: "/stream")

    // Build query parameters
    var parameters = [String]()

    // Add start time if provided
    if let time = startTime, time > 0 {
      parameters.append("t=\(Int(time))")
    }

    // Add API key if present in the original URL
    if directURL.absoluteString.contains("apikey=") {
      if let apiKeyRange = directURL.absoluteString.range(of: "apikey=[^&]+", options: .regularExpression) {
        let apiKey = String(directURL.absoluteString[apiKeyRange])
        if !parameters.contains(where: { $0.starts(with: "apikey=") }) {
          parameters.append(apiKey)
        }
      }
    }

    // Add timestamp for cache busting
    let currentTimestamp = Int(Date().timeIntervalSince1970)
    parameters.append("_ts=\(currentTimestamp)")

    // Add parameters to URL
    if !parameters.isEmpty {
      // Check if URL already has query parameters
      if urlString.contains("?") {
        urlString += "&" + parameters.joined(separator: "&")
      } else {
        urlString += "?" + parameters.joined(separator: "&")
      }
    }

    print("🎬 Direct stream URL: \(urlString)")
    return URL(string: urlString)
  }
  /// Gets a thumbnail URL for a scene at a specific timestamp
  /// - Parameters:
  ///   - sceneID: The scene ID
  ///   - seconds: The timestamp in seconds to get the thumbnail for
  /// - Returns: URL for the thumbnail image
  static func getThumbnailURL(forSceneID sceneID: String, seconds: Double) -> URL? {
    guard let serverAddress = StashAPIManager.shared.api?.serverAddress else {
      return nil
    }

    var components = URLComponents(string: "\(serverAddress)/scene/\(sceneID)/screenshot")

    var queryItems = [URLQueryItem]()
    queryItems.append(URLQueryItem(name: "t", value: String(format: "%.2f", seconds)))

    // Avoid caching by adding a timestamp
    let timestamp = Int(Date().timeIntervalSince1970)
    queryItems.append(URLQueryItem(name: "_ts", value: "\(timestamp)"))

    // Add API key for authentication
    if let apiKey = StashAPIManager.shared.api?.apiKeyForURLs {
      queryItems.append(URLQueryItem(name: "apikey", value: apiKey))
    }

    components?.queryItems = queryItems
    return components?.url
  }

  /// Gets the default screenshot URL for a scene
  /// - Parameter sceneID: The scene ID
  /// - Returns: URL for the screenshot image
  static func getScreenshotURL(forSceneID sceneID: String) -> URL? {
    guard let serverAddress = StashAPIManager.shared.api?.serverAddress else {
      return nil
    }

    var components = URLComponents(string: "\(serverAddress)/scene/\(sceneID)/screenshot")

    var queryItems = [URLQueryItem]()

    // Avoid caching by adding a timestamp
    let timestamp = Int(Date().timeIntervalSince1970)
    queryItems.append(URLQueryItem(name: "_ts", value: "\(timestamp)"))

    // Add API key for authentication
    if let apiKey = StashAPIManager.shared.api?.apiKeyForURLs {
      queryItems.append(URLQueryItem(name: "apikey", value: apiKey))
    }

    components?.queryItems = queryItems
    return components?.url
  }

  /// Gets a sprite image URL for a scene
  /// - Parameter sceneID: The scene ID
  /// - Returns: URL for the sprite image
  static func getSpriteURL(forSceneID sceneID: String) -> URL? {
    guard let serverAddress = StashAPIManager.shared.api?.serverAddress else {
      return nil
    }

    var components = URLComponents(string: "\(serverAddress)/scene/\(sceneID)/sprite")

    var queryItems = [URLQueryItem]()

    // Avoid caching by adding a timestamp
    let timestamp = Int(Date().timeIntervalSince1970)
    queryItems.append(URLQueryItem(name: "_ts", value: "\(timestamp)"))

    // Add API key for authentication
    if let apiKey = StashAPIManager.shared.api?.apiKeyForURLs {
      queryItems.append(URLQueryItem(name: "apikey", value: apiKey))
    }

    components?.queryItems = queryItems
    return components?.url
  }

  /// Gets a VTT file URL for a scene (for video chapters/thumbnails)
  /// - Parameter sceneID: The scene ID
  /// - Returns: URL for the VTT file
  static func getVTTURL(forSceneID sceneID: String) -> URL? {
    guard let serverAddress = StashAPIManager.shared.api?.serverAddress else {
      return nil
    }

    var components = URLComponents(string: "\(serverAddress)/scene/\(sceneID)/vtt/thumbnails")

    var queryItems = [URLQueryItem]()

    // Avoid caching by adding a timestamp
    let timestamp = Int(Date().timeIntervalSince1970)
    queryItems.append(URLQueryItem(name: "_ts", value: "\(timestamp)"))

    // Add API key for authentication
    if let apiKey = StashAPIManager.shared.api?.apiKeyForURLs {
      queryItems.append(URLQueryItem(name: "apikey", value: apiKey))
    }

    components?.queryItems = queryItems
    return components?.url
  }

  /// Gets a preview video URL for a scene
  /// - Parameter sceneID: The scene ID
  /// - Returns: URL for the preview video
  static func getPreviewURL(forSceneID sceneID: String) -> URL? {
    guard let serverAddress = StashAPIManager.shared.api?.serverAddress else {
      return nil
    }

    var components = URLComponents(string: "\(serverAddress)/scene/\(sceneID)/preview")

    var queryItems = [URLQueryItem]()

    // Avoid caching by adding a timestamp
    let timestamp = Int(Date().timeIntervalSince1970)
    queryItems.append(URLQueryItem(name: "_ts", value: "\(timestamp)"))

    // Add API key for authentication
    if let apiKey = StashAPIManager.shared.api?.apiKeyForURLs {
      queryItems.append(URLQueryItem(name: "apikey", value: apiKey))
    }

    components?.queryItems = queryItems
    return components?.url
  }

  /// Utility method to convert a direct stream URL to an HLS stream URL
  /// - Parameters:
  ///   - directURL: The direct stream URL
  ///   - startTime: Optional start time in seconds to include in the URL
  /// - Returns: The corresponding HLS stream URL
  static func getHLSStreamURL(from directURL: URL, startTime: Double? = nil) -> URL? {
    var urlString = directURL.absoluteString
    print("🔍 Converting direct URL to HLS: \(urlString)")

    // If we already have an HLS URL, just ensure it has the correct parameters
    if urlString.contains("stream.m3u8") {
      print("✅ URL is already in HLS format: \(urlString)")

      // Make sure we have the required parameters
      var parameters = [String]()

      // Add resolution parameter if missing
      if !urlString.contains("resolution=") {
        parameters.append("resolution=ORIGINAL")
      }

      // Add t parameter if we have a start time and URL doesn't already have it
      if let time = startTime, time > 0, !urlString.contains("t=") {
        parameters.append("t=\(Int(time))")
      }

      // Add timestamp parameter (_ts) for cache busting if missing
      if !urlString.contains("_ts=") {
        let currentTimestamp = Int(Date().timeIntervalSince1970)
        parameters.append("_ts=\(currentTimestamp)")
      }

      // Add parameters to URL if we have any to add
      if !parameters.isEmpty {
        if urlString.contains("?") {
          urlString += "&" + parameters.joined(separator: "&")
        } else {
          urlString += "?" + parameters.joined(separator: "&")
        }
      }

      print("✅ Enhanced HLS URL: \(urlString)")
      return URL(string: urlString)
    }

    // If the URL is not in HLS format yet, convert it
    if urlString.contains("/stream") {
      urlString = urlString.replacingOccurrences(of: "/stream", with: "/stream.m3u8")

      // Build query parameters with all needed values
      var parameters = ["resolution=ORIGINAL"]

      // Add start time parameter if provided
      if let time = startTime, time > 0 {
        parameters.append("t=\(Int(time))")
        print("🎯 Using start time: t=\(Int(time))")
      }

      // Add API key if present in the original URL
      if directURL.absoluteString.contains("apikey=") {
        // Extract the apikey from the original URL
        if let apiKeyRange = directURL.absoluteString.range(of: "apikey=[^&]+") {
          let apiKey = String(directURL.absoluteString[apiKeyRange])
          parameters.append(apiKey)
        }
      }

      // Add current timestamp parameter (_ts) for cache busting
      let currentTimestamp = Int(Date().timeIntervalSince1970)
      parameters.append("_ts=\(currentTimestamp)")

      // Add all parameters to URL
      if urlString.contains("?") {
        urlString += "&" + parameters.joined(separator: "&")
      } else {
        urlString += "?" + parameters.joined(separator: "&")
      }

      print("🔄 Converted to HLS URL: \(urlString)")
      return URL(string: urlString)
    }

    // If we can't determine the HLS URL, return nil
    print("⚠️ Unable to convert to HLS URL")
    return nil
  }

  /// Jumps to a random position in the provided AVPlayer
  /// - Parameter player: The AVPlayer to jump to a random position in
  /// - Returns: True if the jump was successful, false otherwise
  @discardableResult
  static func jumpToRandomPosition(in player: AVPlayer) -> Bool {
    // Get the current item and check status
    guard let currentItem = player.currentItem else {
      print("⚠️ Cannot jump to random position - no current item")
      return false
    }

    // When video first loads, duration might not be available or fully loaded
    let duration: Double

    // Handle different states of video loading
    if currentItem.status == .readyToPlay && currentItem.duration.isValid
      && !currentItem.duration.seconds.isNaN && currentItem.duration.seconds > 0 {
      // Normal case - video is ready with valid duration
      duration = currentItem.duration.seconds
      print("🎲 Current video duration: \(duration) seconds")
    } else {
      // Fallback case - try to use a reasonable default duration if not fully loaded
      // This allows jumping to work even if the video is still loading
      print("⚠️ Video duration not fully loaded yet, using estimated duration")

      // Try to get duration from file information if available
      if let loadedTimeRanges = currentItem.loadedTimeRanges.first {
        let timeRange = loadedTimeRanges.timeRangeValue
        let loadedDuration = timeRange.duration.seconds

        if loadedDuration > 0 {
          print("🎲 Using loaded time range: \(loadedDuration) seconds")
          duration = loadedDuration
        } else {
          // If no loaded time range, use a reasonable default (typical video length)
          duration = 1800  // 30 minutes as a fallback
          print("🎲 Using default duration: \(duration) seconds (30 minutes)")
        }
      } else {
        // No loaded time ranges, use a reasonable default
        duration = 1800  // 30 minutes as a fallback
        print("🎲 Using default duration: \(duration) seconds (30 minutes)")
      }
    }

    // Current time for logging
    let currentSeconds =
      currentItem.currentTime().seconds.isNaN ? 0 : currentItem.currentTime().seconds
    print("🎲 Current position: \(currentSeconds) seconds")

    // Calculate a random position between 20 seconds and 90% of the duration
    // For very short videos, ensure at least some meaningful jump
    let minPosition = max(20, duration * 0.05)  // At least 20 seconds or 5% in
    let maxPosition = min(duration - 5, duration * 0.9)  // At most 90% through the video

    if minPosition >= maxPosition {
      print("⚠️ Video too short or invalid duration range: \(minPosition) >= \(maxPosition)")
      // Still try to jump to a reasonable position
      let defaultPosition = max(20, min(300, duration / 2))
      print("🎲 Using default position: \(defaultPosition) seconds")

      let time = CMTime(seconds: defaultPosition, preferredTimescale: 1000)
      player.seek(to: time)
      return true
    }

    // Generate random position
    let randomPosition = Double.random(in: minPosition...maxPosition)
    let minutes = Int(randomPosition / 60)
    let seconds = Int(randomPosition) % 60

    print(
      "🎲 Jumping to random position: \(randomPosition) seconds (\(minutes):\(String(format: "%02d", seconds)))"
    )

    // Create time with higher precision timescale
    let time = CMTime(seconds: randomPosition, preferredTimescale: 1000)

    // Set tolerances for more precise seeking
    let toleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 1000)
    let toleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 1000)

    // Perform the seek operation
    print("🎲 Seeking to new position...")
    player.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter) {
      success in
      if success {
        print("✅ Successfully jumped to \(minutes):\(String(format: "%02d", seconds))")

        // Provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Make sure playback continues
        if player.timeControlStatus != .playing {
          player.play()
        }
      } else {
        print("❌ Seek operation failed, attempting simplified seek")
        // Try a simplified seek without tolerances as a fallback
        player.seek(to: time)

        // Make sure playback continues
        if player.timeControlStatus != .playing {
          player.play()
        }
      }
    }

    return true
  }
}

// MARK: - Global Video Manager
class GlobalVideoManager {
  static let shared = GlobalVideoManager()

  private var activePlayers = Set<AVPlayer>()
  private var observationTokens = [AVPlayer: Any]()

  private init() {}

  func registerPlayer(_ player: AVPlayer) {
    DispatchQueue.main.async {
      self.activePlayers.insert(player)
      print("🎬 GlobalVideoManager: Registered player, total active: \(self.activePlayers.count)")
    }
  }

  func unregisterPlayer(_ player: AVPlayer) {
    DispatchQueue.main.async {
      self.activePlayers.remove(player)
      if let token = self.observationTokens[player] {
        self.observationTokens.removeValue(forKey: player)
      }
      print("🎬 GlobalVideoManager: Unregistered player, total active: \(self.activePlayers.count)")
    }
  }

  func stopAllPreviews() {
    DispatchQueue.main.async {
      print(
        "🎬 GlobalVideoManager: Stopping and cleaning up all \(self.activePlayers.count) active preview players"
      )
      for player in self.activePlayers {
        // More aggressive cleanup to prevent audio overlap
        player.pause()
        player.isMuted = true  // Immediately mute to stop audio
        player.replaceCurrentItem(with: nil)  // Clear the item completely
      }
    }
  }

  func pauseAllExcept(_ player: AVPlayer) {
    DispatchQueue.main.async {
      print("🎬 GlobalVideoManager: Pausing all players except the current one")
      for activePlayer in self.activePlayers {
        if activePlayer != player {
          // More aggressive pause to prevent audio overlap
          if activePlayer.timeControlStatus == .playing {
            activePlayer.pause()
          }
          activePlayer.isMuted = true  // Mute to be extra sure
        }
      }
    }
  }

  func cleanupAllPlayers() {
    DispatchQueue.main.async {
      print("🧹 GlobalVideoManager: Cleaning up all \(self.activePlayers.count) active players")
      for player in self.activePlayers {
        player.pause()
        player.replaceCurrentItem(with: nil)
      }
      self.activePlayers.removeAll()
      self.observationTokens.removeAll()
    }
  }
}

// MARK: - Player Manager
class VideoPlayerManager: ObservableObject {
  @Published var useHLS: Bool = true
  @Published var isPlaying: Bool = false
  @Published var isBuffering: Bool = false
  @Published var currentTime: Double = 0
  @Published var duration: Double = 0

  init(useHLS: Bool = true) {
    self.useHLS = useHLS
  }

  func toggleHLS() {
    useHLS.toggle()
  }
}

// MARK: - Singleton API Manager
class StashAPIManager {
  static let shared = StashAPIManager()
  var api: StashAPI?

  private init() {}
}

// MARK: - Player Creation Methods
extension VideoPlayerUtility {
  /// Seek to a specific time in a player with robust error handling
  /// - Parameters:
  ///   - player: The AVPlayer to seek
  ///   - time: The time in seconds to seek to
  /// - Returns: True if seek was initiated successfully
  static func seekToTime(player: AVPlayer, time: Double) -> Bool {
    print("⏱ Seeking to time: \(time) seconds")

    // Add a quick log to confirm startTime > 0
    if time > 0 {
      print("✓ Confirmed startTime (\(time)) is greater than 0")
    }

    // Create precise time value with high timescale for accuracy
    let cmTime = CMTime(seconds: time, preferredTimescale: 600)

    // Use zero tolerances for precise seeking with marker positions
    player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { success in
      if success {
        print("✅ Successfully sought to \(time) seconds")

        // Ensure playback continues after seeking
        if player.timeControlStatus != .playing {
          player.play()
        }
      } else {
        print("⚠️ Precise seek failed, trying standard seek")

        // Try standard seek without tolerance specifications as fallback
        player.seek(to: cmTime) { innerSuccess in
          if innerSuccess {
            print("✅ Standard seek succeeded to \(time) seconds")
            if player.timeControlStatus != .playing {
              player.play()
            }
          } else {
            print("❌ All seek attempts failed to \(time) seconds")
          }
        }
      }
    }

    return true
  }
  /// Creates and configures an AVPlayerViewController for playing video content
  /// - Parameters:
  ///   - url: URL of the video to play
  ///   - startTime: Optional starting time in seconds
  ///   - scenes: Optional array of scenes for playlist functionality
  ///   - currentIndex: The index of the current scene in the scenes array
  ///   - appModel: The app model
  /// - Returns: A configured AVPlayerViewController
  static func createPlayerViewController(
    url: URL,
    startTime: Double? = nil,
    scenes: [StashScene] = [],
    currentIndex: Int = 0,
    appModel: AppModel
  ) -> AVPlayerViewController {
    // First check if the URL already includes .m3u8 for HLS
    let isAlreadyHLS = url.absoluteString.contains("stream.m3u8")

    // Convert the direct URL to an HLS URL if it's not already HLS
    let finalURL: URL
    if isAlreadyHLS {
      print("🎬 Using provided HLS URL: \(url.absoluteString)")
      finalURL = url
    } else {
      // Try to convert to HLS
      if let hlsURL = getHLSStreamURL(from: url) {
        print("🎬 Converted to HLS URL: \(hlsURL.absoluteString)")
        finalURL = hlsURL
      } else {
        print("⚠️ Could not convert to HLS, using original URL: \(url.absoluteString)")
        finalURL = url
      }
    }

    // Create player and custom view controller (enables consistent hotkeys)
    let player = AVPlayer(url: finalURL)

    // Derive a scene ID for CustomVideoPlayer
    let resolvedSceneID: String
    if scenes.indices.contains(currentIndex) {
      resolvedSceneID = scenes[currentIndex].id
    } else if let currentSceneID = appModel.currentScene?.id {
      resolvedSceneID = currentSceneID
    } else {
      resolvedSceneID = ""
    }

    let playerViewController = CustomVideoPlayer(
      scenes: scenes,
      currentIndex: currentIndex,
      sceneID: resolvedSceneID,
      appModel: appModel
    )

    // Assign player to playerViewController
    playerViewController.player = player

    // Let AVPlayer handle stalling naturally for smooth playback
    player.automaticallyWaitsToMinimizeStalling = true  // Let player handle buffering
    if let currentItem = player.currentItem {
      currentItem.preferredForwardBufferDuration = 5.0  // More buffer for stable playback
    }

    // Configure player options
    playerViewController.allowsPictureInPicturePlayback = true
    playerViewController.showsPlaybackControls = true

    // Set start time if provided
    if let startTime = startTime {
      print("⏱ Setting start time to \(startTime) seconds")
      // Use the consolidated seeking method for consistency
      _ = seekToTime(player: player, time: startTime)
    } else {
      print("ℹ️ No start time provided, starting from beginning")
    }

    // Add observer for playback progress
    if let sceneId = appModel.currentScene?.id {
      print("📊 Adding playback progress observer for scene ID: \(sceneId)")
      let interval = CMTime(seconds: 5, preferredTimescale: 1)
      player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
        let seconds = CMTimeGetSeconds(time)
        if seconds > 0 {
          UserDefaults.standard.setVideoProgress(seconds, for: sceneId)
        }
      }
    }

    // Register with VideoPlayerRegistry for consistent access
    print("📝 Registering player with VideoPlayerRegistry in createPlayerViewController")
    VideoPlayerRegistry.shared.currentPlayer = player
    VideoPlayerRegistry.shared.playerViewController = playerViewController

    // Also register with GlobalVideoManager
    GlobalVideoManager.shared.registerPlayer(player)

    // Start playback
    print("▶️ Starting playback")
    player.play()

    return playerViewController
  }
}
