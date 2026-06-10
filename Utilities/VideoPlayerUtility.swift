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

  /// Container formats that iOS can play natively
  /// MKV/Matroska, AVI, WMV etc. need HLS transcoding even with compatible codecs
  static let directPlayContainers: Set<String> = [
    "mp4", "mov", "m4v", "qt",       // Apple/QuickTime containers
    "3gp", "3g2"                      // Mobile video containers
  ]

  /// Maximum frame rate iOS can reliably hardware decode for HEVC
  /// M4 chips can handle 120fps+ without issues
  /// Only limit extremely high frame rates that might cause issues
  static let maxDirectPlayFrameRate: Float = 240.0

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

  /// Check if codec, container format, AND frame rate can be direct played
  /// iOS requires compatible codec AND container - MKV with h264 still needs transcoding
  /// High frame rate content (>60fps) also requires HLS transcoding
  /// - Parameters:
  ///   - codec: The video codec string
  ///   - format: The container format string (optional - if nil, only codec is checked)
  ///   - frameRate: The frame rate (optional - SVP files have 60fps/120fps)
  /// - Returns: True if codec, container, and frame rate are all iOS-compatible
  static func canDirectPlayWithFormat(codec: String?, format: String?, frameRate: Float? = nil) -> Bool {
    guard let codec = codec?.lowercased() else {
      print("🎬 Unknown codec - defaulting to HLS")
      return false
    }

    let codecOK = directPlayCodecs.contains(codec)

    // Check container format - if unknown, be conservative and use HLS
    let formatOK: Bool
    if let format = format?.lowercased() {
      formatOK = directPlayContainers.contains(format)
      if !formatOK {
        print("🎬 Container '\(format)' requires transcoding (even with compatible codec)")
      }
    } else {
      // Unknown format - default to HLS for safety
      // Direct play fails silently with black screen if container is incompatible (e.g., MKV)
      print("🎬 Unknown container format - defaulting to HLS for safety")
      formatOK = false
    }

    // Check frame rate - SVP files with high frame rates need HLS transcoding
    let frameRateOK: Bool
    if let fps = frameRate, fps > maxDirectPlayFrameRate {
      print("🎬 Frame rate \(fps)fps exceeds max \(maxDirectPlayFrameRate)fps - using HLS (likely SVP file)")
      frameRateOK = false
    } else {
      frameRateOK = true
      if let fps = frameRate {
        print("🎬 Frame rate \(fps)fps is within direct play limit")
      }
    }

    let canPlay = codecOK && formatOK && frameRateOK
    print("🎬 Codec '\(codec)' + Container '\(format ?? "unknown")' + FPS '\(frameRate.map { String(format: "%.1f", $0) } ?? "unknown")' can direct play: \(canPlay)")
    return canPlay
  }

  /// Gets the appropriate stream URL based on codec, container, AND frame rate compatibility
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
    let format = scene.files.first?.format
    let frameRate = scene.files.first?.frame_rate

    // Check codec, container format, AND frame rate for direct play compatibility
    if canDirectPlayWithFormat(codec: codec, format: format, frameRate: frameRate) {
      // Use direct stream URL for compatible codec, container, AND frame rate
      print("✅ Using direct play for scene \(scene.id) with codec: \(codec ?? "unknown"), format: \(format ?? "unknown"), fps: \(frameRate.map { String(format: "%.1f", $0) } ?? "unknown")")
      return getDirectStreamURL(from: baseURL, startTime: startTime)
    } else {
      // Use HLS for incompatible codec, container, OR high frame rate (e.g., SVP 120fps files)
      print("🔄 Using HLS transcoding for scene \(scene.id) with codec: \(codec ?? "unknown"), format: \(format ?? "unknown"), fps: \(frameRate.map { String(format: "%.1f", $0) } ?? "unknown")")
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

    // Add API key to parameters ONLY if URL doesn't already have a query string
    // (If URL already has ?, apikey is already in the query string - don't add again)
    if !urlString.contains("?") && directURL.absoluteString.contains("apikey=") {
      if let apiKeyRange = directURL.absoluteString.range(of: "apikey=[^&]+", options: .regularExpression) {
        let apiKey = String(directURL.absoluteString[apiKeyRange])
        parameters.append(apiKey)
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

    // Only allow random jump when we have a valid duration
    // This prevents seeking to positions that don't exist in the video
    guard currentItem.status == .readyToPlay,
          currentItem.duration.isValid,
          !currentItem.duration.seconds.isNaN,
          currentItem.duration.seconds > 0 else {
      print("⚠️ Cannot jump to random position - video duration not ready yet")
      print("   Status: \(currentItem.status.rawValue), Duration valid: \(currentItem.duration.isValid)")
      return false
    }

    let duration = currentItem.duration.seconds
    print("🎲 Current video duration: \(duration) seconds")

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
      if self.observationTokens[player] != nil {
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
