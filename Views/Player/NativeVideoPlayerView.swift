import AVKit
import Combine
import SwiftUI
import UIKit

// MARK: - Native AVPlayerViewController host
//
// A thin UIViewControllerRepresentable around a plain AVPlayerViewController.
// The system owns ALL transport chrome (play/pause, scrubber, PiP, AirPlay,
// volume, fullscreen). No subview spelunking, no gear-button hiding, no
// custom overlay buttons. App-specific actions live in the SwiftUI toolbar
// provided by NativeVideoPlayerView.
struct NativePlayerHost: UIViewControllerRepresentable {
  let url: URL
  let startTime: Double?
  let endTime: Double?
  let sceneID: String

  final class Coordinator {
    var player: AVPlayer?
    var statusToken: NSKeyValueObservation?
    var recoveryToken: NSKeyValueObservation?
    var endTimeReached = false

    deinit {
      statusToken?.invalidate()
      recoveryToken?.invalidate()
      player = nil
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIViewController(context: Context) -> AVPlayerViewController {
    print("🎬 [Native] Creating AVPlayerViewController for URL: \(url.absoluteString)")

    // Clean up any existing player BEFORE creating a new one (prevents audio overlap)
    if let existingPlayer = VideoPlayerRegistry.shared.currentPlayer {
      print("🧹 [Native] Cleaning up existing player before creating new one")
      VideoPlayerRegistry.shared.cleanupObservers()
      existingPlayer.pause()
      existingPlayer.replaceCurrentItem(with: nil)
      VideoPlayerRegistry.shared.currentPlayer = nil
    }

    let headers = ["User-Agent": "StashApp/iOS"]
    let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    let playerItem = AVPlayerItem(asset: asset)
    playerItem.preferredForwardBufferDuration = 5.0

    let player = AVPlayer(playerItem: playerItem)
    player.automaticallyWaitsToMinimizeStalling = true

    let playerVC = AVPlayerViewController()
    playerVC.player = player
    playerVC.showsPlaybackControls = true
    playerVC.allowsPictureInPicturePlayback = true
    playerVC.canStartPictureInPictureAutomaticallyFromInline = true
    playerVC.videoGravity = .resizeAspect
    playerVC.updatesNowPlayingInfoCenter = true

    // Register with the shared registry so AppModel-driven flows
    // (marker shuffle, tag shuffle, etc.) keep working unchanged.
    VideoPlayerRegistry.shared.currentPlayer = player
    VideoPlayerRegistry.shared.playerViewController = playerVC
    context.coordinator.player = player

    let explicitStartTime = startTime
    let markerEndTime = endTime

    // Wait for readyToPlay before starting playback / seeking
    let token = playerItem.observe(\.status, options: [.new]) { item, _ in
      if item.status == .readyToPlay {
        print("✅ [Native] Player item ready to play")

        DispatchQueue.main.async {
          do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [])
            try audioSession.setActive(true)
          } catch {
            print("⚠️ [Native] Failed to configure audio session: \(error)")
          }

          player.play()
          NotificationCenter.default.post(
            name: NSNotification.Name("VideoLoadingSuccess"), object: nil)

          // Seek to the requested start time once playback has begun
          if let t = explicitStartTime, t > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
              let cmTime = CMTime(seconds: t, preferredTimescale: 1000)
              print("⏱ [Native] Seeking to start time \(t)s")
              player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                player.play()
              }
            }
          }

          // Detect "audio only / no video track" direct-play failures and fall back to HLS
          DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard let currentItem = player.currentItem else { return }
            let urlString = url.absoluteString
            guard !urlString.contains("stream.m3u8") else { return }

            let videoTracks = currentItem.asset.tracks(withMediaType: .video)
            let hasValidVideo = videoTracks.first.map { track in
              let size = track.naturalSize
              return size.width > 0 && size.height > 0
            } ?? false

            if !hasValidVideo {
              print("⚠️ [Native] No valid video track after 2s - switching to HLS")
              var hlsString = urlString.replacingOccurrences(of: "/stream?", with: "/stream.m3u8?")
              hlsString = hlsString.replacingOccurrences(of: "/stream&", with: "/stream.m3u8&")
              if hlsString == urlString {
                hlsString = urlString.replacingOccurrences(of: "/stream", with: "/stream.m3u8")
              }
              if !hlsString.contains("resolution=") {
                hlsString += "&resolution=ORIGINAL"
              }
              if let hlsURL = URL(string: hlsString) {
                let hlsItem = AVPlayerItem(url: hlsURL)
                player.replaceCurrentItem(with: hlsItem)
                player.play()
              }
            }
          }
        }

        // Marker end-time observer: pause when the marker segment finishes
        if let endTime = markerEndTime {
          print("⏱ [Native] Installing marker end-time observer at \(endTime)s")
          let endTimeObs = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
          ) { [weak player] time in
            guard !context.coordinator.endTimeReached else { return }
            if time.seconds >= endTime {
              print("🎬 [Native] Reached marker end time \(endTime), pausing")
              player?.pause()
              context.coordinator.endTimeReached = true
              UINotificationFeedbackGenerator().notificationOccurred(.success)
              NotificationCenter.default.post(
                name: Notification.Name("MarkerEndReached"), object: nil)
            }
          }
          VideoPlayerRegistry.shared.registerTimeObserver(endTimeObs, for: player)
        }

        // Persist watch progress every 5 seconds (used for resume elsewhere in the app)
        let progressSceneID = self.sceneID
        let progressObs = player.addPeriodicTimeObserver(
          forInterval: CMTime(seconds: 5, preferredTimescale: 1),
          queue: .main
        ) { time in
          let seconds = CMTimeGetSeconds(time)
          if seconds > 0, !progressSceneID.isEmpty {
            UserDefaults.standard.setVideoProgress(seconds, for: progressSceneID)
          }
        }
        VideoPlayerRegistry.shared.registerTimeObserver(progressObs, for: player)
      } else if item.status == .failed {
        let errorDesc = item.error?.localizedDescription ?? "Unknown error"
        print("⚫ [Native] Player item FAILED: \(errorDesc)")
        print("   📍 URL: \(url.absoluteString)")

        // Recovery: direct stream failed -> try HLS; HLS failed -> try direct
        let urlString = url.absoluteString
        var recoveryURL: URL?

        if !urlString.contains("stream.m3u8") {
          var hlsString = urlString.replacingOccurrences(of: "/stream?", with: "/stream.m3u8?")
          hlsString = hlsString.replacingOccurrences(of: "/stream&", with: "/stream.m3u8&")
          if hlsString == urlString {
            hlsString = urlString.replacingOccurrences(of: "/stream", with: "/stream.m3u8")
          }
          if !hlsString.contains("resolution=") {
            hlsString += "&resolution=ORIGINAL"
          }
          recoveryURL = URL(string: hlsString)
          print("🔄 [Native] RECOVERY: direct play failed - attempting HLS: \(hlsString)")
        } else {
          let directString =
            urlString
            .replacingOccurrences(of: "stream.m3u8", with: "stream")
            .replacingOccurrences(of: "&resolution=ORIGINAL", with: "")
          recoveryURL = URL(string: directString)
          print("🔄 [Native] RECOVERY: HLS failed - attempting direct stream: \(directString)")
        }

        if let recoveryURL = recoveryURL {
          let recoveryItem = AVPlayerItem(url: recoveryURL)
          player.replaceCurrentItem(with: recoveryItem)
          let seekTime = explicitStartTime

          let recoveryToken = recoveryItem.observe(\.status, options: [.new]) {
            [weak player] recoveryItem, _ in
            guard let player = player else { return }
            if recoveryItem.status == .readyToPlay {
              print("✅ [Native] RECOVERY SUCCESS")
              NotificationCenter.default.post(
                name: NSNotification.Name("VideoLoadingSuccess"), object: nil)
              if let timeToSeek = seekTime, timeToSeek > 0 {
                let cmTime = CMTime(seconds: timeToSeek, preferredTimescale: 1000)
                player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                  player.play()
                }
              } else {
                player.play()
              }
            } else if recoveryItem.status == .failed {
              print("⚫ [Native] RECOVERY ALSO FAILED: \(recoveryItem.error?.localizedDescription ?? "Unknown")")
            }
          }
          context.coordinator.recoveryToken = recoveryToken
          player.play()
        }
      }
    }
    context.coordinator.statusToken = token
    VideoPlayerRegistry.shared.registerObservationToken(token)

    return playerVC
  }

  func updateUIViewController(_ playerVC: AVPlayerViewController, context: Context) {
    // Keep the registry pointed at this controller; content changes are driven
    // through the registry's player by AppModel notification flows.
    if VideoPlayerRegistry.shared.playerViewController !== playerVC {
      VideoPlayerRegistry.shared.playerViewController = playerVC
      VideoPlayerRegistry.shared.currentPlayer = playerVC.player
    }
  }
}

// MARK: - NativeVideoPlayerView
//
// Native replacement for the custom-drawn VideoPlayerView. AVPlayerViewController
// owns transport (play/pause/scrub/PiP/AirPlay); app-specific actions are
// re-homed into the navigation toolbar with native button/menu styles.
struct NativeVideoPlayerView: View {
  let scene: StashScene
  var startTime: Double?
  var endTime: Double?

  @EnvironmentObject private var appModel: AppModel
  @Environment(\.dismiss) private var dismiss

  @State private var currentScene: StashScene
  @State private var effectiveStartTime: Double?
  @State private var effectiveEndTime: Double?
  @State private var originalPerformer: StashScene.Performer?
  @State private var currentMarker: SceneMarker?
  @State private var isRandomJumpMode: Bool = false
  // Shuffled, no-repeat walk of the current context for random-jump "next"
  @State private var randomShuffleQueue: [StashScene] = []
  @State private var randomShuffleIndex: Int = 0
  @State private var randomShuffleContextSignature: String = ""
  @State private var isPerformerShuffleInProgress: Bool = false
  @State private var videoLoadingTimer: Timer?
  @State private var isManualExit: Bool = false
  @State private var hasRegisteredNotificationObservers: Bool = false
  @State private var oCount: Int = 0
  @State private var isIncrementingOCounter: Bool = false
  @FocusState private var isVideoPlayerFocused: Bool
  // Toolbar auto-hide: mirrors the visionOS ornament rhythm — hide 4 s after
  // playback starts, reappear whenever paused/buffering.

  init(scene: StashScene, startTime: Double? = nil, endTime: Double? = nil) {
    self.scene = scene
    self.startTime = startTime
    self.endTime = endTime
    _currentScene = State(initialValue: scene)
    _oCount = State(initialValue: scene.o_counter ?? 0)

    if let startTime = startTime {
      _effectiveStartTime = State(initialValue: startTime)
    }
    if let endTime = endTime {
      _effectiveEndTime = State(initialValue: endTime)
    }

    // Initialize the original performer with female preference
    let femalePerformer = scene.performers.first { Self.isLikelyFemale($0) }
    if let selected = femalePerformer ?? scene.performers.first {
      _originalPerformer = State(initialValue: selected)
    }
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      NativePlayerHost(
        url: streamURL(),
        startTime: effectiveStartTime,
        endTime: effectiveEndTime,
        sceneID: currentScene.id
      )
      .ignoresSafeArea()
    }
    .navigationTitle(currentScene.title ?? "")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.black.opacity(0.6), for: .navigationBar)
    .toolbarColorScheme(.dark, for: .navigationBar)
    .toolbar { playerToolbar }
    .statusBarHidden(true)
    .focused($isVideoPlayerFocused)
    .onKeyPress(phases: .down) { keyPress in
      handleKeyPress(keyPress)
    }
    .onAppear { handleAppear() }
    .onDisappear { handleDisappear() }
  }

  // MARK: - Toolbar  }

  // MARK: - Toolbar (app actions re-homed from the custom chrome)

  @ToolbarContentBuilder
  private var playerToolbar: some ToolbarContent {
    ToolbarItemGroup(placement: .topBarTrailing) {
      // O-counter
      Button {
        incrementOCounter()
      } label: {
        Label(oCount > 0 ? "O \(oCount)" : "O", systemImage: "heart.fill")
      }
      .disabled(isIncrementingOCounter)
      .accessibilityLabel("Increment O counter")

      // Marker queue controls (only meaningful in marker shuffle mode)
      if appModel.isMarkerShuffleMode && !appModel.markerShuffleQueue.isEmpty {
        Menu {
          Section("Marker Queue (\(appModel.currentShuffleIndex + 1)/\(appModel.markerShuffleQueue.count))") {
            Button {
              appModel.shuffleToNextMarker()
            } label: {
              Label("Next Marker", systemImage: "forward.fill")
            }
            Button {
              appModel.shuffleToPreviousMarker()
            } label: {
              Label("Previous Marker", systemImage: "backward.fill")
            }
            Button {
              appModel.reshuffleMarkerQueue()
              UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            } label: {
              Label("Re-shuffle Queue", systemImage: "shuffle.circle.fill")
            }
          }
        } label: {
          Label("Markers", systemImage: "bookmark.circle")
        }
        .accessibilityLabel("Marker queue actions")
      }

      // Shuffle / jump actions
      Menu {
        Button {
          libraryRandomShuffle()
        } label: {
          Label("Random Scene (Library)", systemImage: "shuffle")
        }
        Button {
          performerRandomScene()
        } label: {
          Label("Random Scene (Performer)", systemImage: "person.crop.circle")
        }
        Button {
          jumpToRandomPosition()
        } label: {
          Label("Jump to Random Position", systemImage: "arrow.triangle.2.circlepath")
        }
        Divider()
        Button {
          restartFromBeginning()
        } label: {
          Label("Restart from Beginning", systemImage: "gobackward")
        }
        Divider()
        Menu {
          Button("Fit") { setAspect(.resizeAspect) }
          Button("Fill") { setAspect(.resizeAspectFill) }
          Button("Stretch") { setAspect(.resize) }
        } label: {
          Label("Aspect Ratio", systemImage: "aspectratio")
        }
      } label: {
        Label("Shuffle", systemImage: "shuffle.circle")
      }
      .accessibilityLabel("Shuffle and playback actions")

      // Universal next (same behavior as the X key)
      Button {
        universalNext()
      } label: {
        Label("Next", systemImage: "forward.end.fill")
      }
      .accessibilityLabel("Next scene")

    }
  }

  // MARK: - Lifecycle

  private func handleAppear() {
    print("📱 [Native] NativeVideoPlayerView appeared for scene \(scene.id)")

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      isVideoPlayerFocused = true
    }

    currentScene = scene
    appModel.currentScene = scene
    oCount = scene.o_counter ?? 0

    // Reset performer context: only keep it when valid for the current scene
    originalPerformer = nil
    if let detailPerformer = appModel.performerDetailViewPerformer,
      scene.performers.contains(where: { $0.id == detailPerformer.id }) {
      originalPerformer = detailPerformer
    } else if let currentPerformer = appModel.currentPerformer,
      scene.performers.contains(where: { $0.id == currentPerformer.id }) {
      originalPerformer = currentPerformer
    } else {
      let femalePerformer = scene.performers.first { Self.isLikelyFemale($0) }
      originalPerformer = femalePerformer ?? scene.performers.first
    }

    startVideoLoadingTimeout()
    addToWatchHistory()

    // Resolve start time (explicit parameter wins, then marker navigation stash)
    let isMarkerNavigation = UserDefaults.standard.bool(
      forKey: "scene_\(scene.id)_isMarkerNavigation")
    if let startTime = startTime {
      effectiveStartTime = startTime
    } else if isMarkerNavigation {
      let storedStartTime = UserDefaults.standard.double(forKey: "scene_\(scene.id)_startTime")
      if storedStartTime > 0 {
        effectiveStartTime = storedStartTime
      }
    }

    if let endTime = endTime {
      effectiveEndTime = endTime
    } else {
      let storedEndTime = UserDefaults.standard.double(forKey: "scene_\(scene.id)_endTime")
      if storedEndTime > 0 {
        effectiveEndTime = storedEndTime
      }
    }

    // Stop preview players
    NotificationCenter.default.post(name: Notification.Name("MainVideoPlayerStarted"), object: nil)

    registerNotificationObservers()
  }

  private func handleDisappear() {
    print("📱 [Native] NativeVideoPlayerView disappeared - cleaning up")
    appModel.currentScene = nil

    videoLoadingTimer?.invalidate()
    videoLoadingTimer = nil

    let isMarkerShuffle = UserDefaults.standard.bool(forKey: "isMarkerShuffleContext")
    let isTagShuffle = UserDefaults.standard.bool(forKey: "isTagSceneShuffleContext")
    let isMostPlayedShuffle = UserDefaults.standard.bool(forKey: "isMostPlayedShuffleMode")
    let isPerformerShuffle = appModel.isPerformerShuffleMode

    if (!isMarkerShuffle && !isTagShuffle && !isMostPlayedShuffle && !isPerformerShuffle)
      || isManualExit {
      // Clean up time observers BEFORE disposing the player
      VideoPlayerRegistry.shared.cleanupObservers()

      if let player = VideoPlayerRegistry.shared.currentPlayer {
        print("🔇 [Native] Disposing of video player on view disappear")
        player.pause()
        player.replaceCurrentItem(with: nil)
      }
      VideoPlayerRegistry.shared.currentPlayer = nil
      VideoPlayerRegistry.shared.playerViewController = nil

      if isManualExit {
        appModel.killAllAudio()
        appModel.isPerformerShuffleMode = false
        appModel.performerShufflePerformer = nil

        Task {
          await appModel.api.fetchScenesExcludingVR(
            page: 1, sort: "random", direction: "DESC", appendResults: false)
        }
      }
    } else {
      print("🎲 [Native] Skipping player cleanup - in shuffle mode (automatic navigation)")
      // BUT: if no replacement scene takes over shortly, this was a real back-exit
      // (the toolbar X used to handle this) — dispose so audio can't leak.
      let oldPlayer = VideoPlayerRegistry.shared.currentPlayer
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        if VideoPlayerRegistry.shared.currentPlayer === oldPlayer {
          print("🔇 [Native] No replacement player after shuffle-exit — disposing")
          oldPlayer?.pause()
          oldPlayer?.replaceCurrentItem(with: nil)
          VideoPlayerRegistry.shared.currentPlayer = nil
          appModel.killAllAudio()
        }
      }
    }
  }

  // MARK: - Notification plumbing (drives in-player content replacement)

  private func registerNotificationObservers() {
    guard !hasRegisteredNotificationObservers else { return }
    hasRegisteredNotificationObservers = true

    let center = NotificationCenter.default

    center.addObserver(
      forName: NSNotification.Name("UpdateVideoPlayerForMarkerShuffle"),
      object: nil, queue: .main
    ) { notification in
      guard let userInfo = notification.userInfo,
        let newScene = userInfo["scene"] as? StashScene,
        let startSeconds = userInfo["startSeconds"] as? Double,
        let hlsURL = userInfo["hlsURL"] as? String
      else { return }

      currentScene = newScene
      appModel.currentScene = newScene
      oCount = newScene.o_counter ?? 0
      effectiveStartTime = startSeconds
      effectiveEndTime = userInfo["endSeconds"] as? Double
      updateOriginalPerformer(for: newScene)
      replacePlayerContent(urlString: hlsURL, startSeconds: startSeconds)
    }

    center.addObserver(
      forName: NSNotification.Name("UpdateVideoPlayerWithMarker"),
      object: nil, queue: .main
    ) { notification in
      guard let userInfo = notification.userInfo,
        let marker = userInfo["marker"] as? SceneMarker,
        let newScene = userInfo["scene"] as? StashScene
      else { return }

      let startTime: Double
      if let intTime = userInfo["startTime"] as? Int {
        startTime = Double(intTime)
      } else if let floatTime = userInfo["startTime"] as? Float {
        startTime = Double(floatTime)
      } else if let doubleTime = userInfo["startTime"] as? Double {
        startTime = doubleTime
      } else {
        return
      }

      currentScene = newScene
      appModel.currentScene = newScene
      oCount = newScene.o_counter ?? 0
      currentMarker = marker
      effectiveStartTime = startTime
      effectiveEndTime = nil
      updateOriginalPerformer(for: newScene)

      guard let streamURL = VideoPlayerUtility.getStreamURL(for: newScene, startTime: startTime)
      else {
        print("❌ [Native] Failed to construct stream URL for marker scene")
        return
      }
      replacePlayerContent(urlString: streamURL.absoluteString, startSeconds: startTime)
    }

    center.addObserver(
      forName: NSNotification.Name("UpdateVideoPlayerForTagShuffle"),
      object: nil, queue: .main
    ) { notification in
      guard let userInfo = notification.userInfo,
        let newScene = userInfo["scene"] as? StashScene,
        let hlsURL = userInfo["hlsURL"] as? String
      else { return }

      currentScene = newScene
      appModel.currentScene = newScene
      oCount = newScene.o_counter ?? 0
      effectiveStartTime = nil
      effectiveEndTime = nil
      replacePlayerContent(urlString: hlsURL, startSeconds: nil)
    }

    center.addObserver(
      forName: NSNotification.Name("UpdateVideoPlayerForMostPlayedShuffle"),
      object: nil, queue: .main
    ) { notification in
      guard let userInfo = notification.userInfo,
        let newScene = userInfo["scene"] as? StashScene,
        let hlsURL = userInfo["hlsURL"] as? String
      else { return }

      currentScene = newScene
      appModel.currentScene = newScene
      oCount = newScene.o_counter ?? 0
      effectiveStartTime = nil
      effectiveEndTime = nil
      replacePlayerContent(urlString: hlsURL, startSeconds: nil)
    }

    // Keyboard shortcuts forwarded from menu commands (Mac Catalyst fallback)
    center.addObserver(
      forName: NSNotification.Name("VideoPlayerKeyboardShortcut"),
      object: nil, queue: .main
    ) { notification in
      if let keyCodeRaw = notification.userInfo?["keyCode"] as? CFIndex,
        let keyCode = UIKeyboardHIDUsage(rawValue: keyCodeRaw) {
        handleMenuKeyboardShortcut(keyCode)
      }
    }

    center.addObserver(
      forName: NSNotification.Name("XKeyPressed"),
      object: nil, queue: .main
    ) { _ in
      universalNext()
    }

    center.addObserver(
      forName: NSNotification.Name("VideoLoadingTimeout"),
      object: nil, queue: .main
    ) { _ in
      if let currentPlayer = VideoPlayerRegistry.shared.currentPlayer {
        currentPlayer.pause()
        currentPlayer.seek(to: .zero)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          appModel.shuffleToNextMarker()
        }
      } else {
        appModel.shuffleToNextMarker()
      }
    }

    center.addObserver(
      forName: NSNotification.Name("VideoLoadingSuccess"),
      object: nil, queue: .main
    ) { _ in
      cancelVideoLoadingTimeout()
    }
  }

  /// Replace the current player item in-place (no navigation flicker)
  private func replacePlayerContent(urlString: String, startSeconds: Double?) {
    guard let player = VideoPlayerRegistry.shared.currentPlayer,
      let url = URL(string: urlString)
    else {
      print("❌ [Native] No current player or invalid URL for content replacement")
      return
    }

    player.pause()

    let headers = ["User-Agent": "StashApp/iOS"]
    let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    let playerItem = AVPlayerItem(asset: asset)
    playerItem.preferredForwardBufferDuration = 5.0
    player.automaticallyWaitsToMinimizeStalling = true
    player.replaceCurrentItem(with: playerItem)

    var statusObserver: NSKeyValueObservation?
    statusObserver = playerItem.observe(\.status, options: [.new]) { item, _ in
      if item.status == .readyToPlay {
        statusObserver?.invalidate()
        if let startSeconds = startSeconds, startSeconds > 0 {
          let cmTime = CMTime(seconds: startSeconds, preferredTimescale: 1000)
          player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            player.play()
            cancelVideoLoadingTimeout()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
              isVideoPlayerFocused = true
            }
          }
        } else {
          player.play()
          cancelVideoLoadingTimeout()
        }
      } else if item.status == .failed {
        statusObserver?.invalidate()
        print("⚫ [Native] Content replacement failed: \(item.error?.localizedDescription ?? "unknown")")
      }
    }
  }

  private func updateOriginalPerformer(for newScene: StashScene) {
    let femalePerformer = newScene.performers.first { Self.isLikelyFemale($0) }
    if let newPerformer = femalePerformer ?? newScene.performers.first {
      originalPerformer = newPerformer
    }
  }

  // MARK: - Stream URL selection (codec-aware: direct play vs HLS transcode)

  private func streamURL() -> URL {
    let sceneId = currentScene.id

    // In marker shuffle, clear cached stream URLs for OTHER scenes
    let isMarkerShuffle = UserDefaults.standard.bool(forKey: "isMarkerShuffleContext")
    if isMarkerShuffle {
      let defaults = UserDefaults.standard
      for key in defaults.dictionaryRepresentation().keys
      where (key.contains("_hlsURL") || key.contains("_streamURL"))
        && !key.contains("scene_\(sceneId)_") {
        defaults.removeObject(forKey: key)
      }
    }

    // Check for saved URLs from marker navigation (direct first, then HLS)
    if let savedStreamUrlString = UserDefaults.standard.string(
      forKey: "scene_\(sceneId)_streamURL"),
      savedStreamUrlString.contains("/scene/\(sceneId)/"),
      let savedStreamUrl = URL(string: savedStreamUrlString) {
      print("📱 [Native] Using saved direct stream URL: \(savedStreamUrlString)")
      return savedStreamUrl
    }

    let videoCodec = currentScene.files.first?.video_codec
    let containerFormat = currentScene.files.first?.format
    let frameRate = currentScene.files.first?.frame_rate
    let canDirectPlay = VideoPlayerUtility.canDirectPlayWithFormat(
      codec: videoCodec, format: containerFormat, frameRate: frameRate)

    let apiKey = appModel.apiKey
    let baseServerURL = appModel.serverAddress.trimmingCharacters(
      in: CharacterSet(charactersIn: "/"))
    let currentTimestamp = Int(Date().timeIntervalSince1970)

    if canDirectPlay {
      var streamURL =
        "\(baseServerURL)/scene/\(sceneId)/stream?apikey=\(apiKey)&_ts=\(currentTimestamp)"
      if let startTime = effectiveStartTime {
        streamURL += "&t=\(Int(startTime))"
      }
      print("✅ [Native] Direct play URL: \(streamURL)")
      if let url = URL(string: streamURL) {
        return url
      }
    } else {
      // HLS transcode path - reuse a saved HLS URL when valid for this scene
      if let savedHlsUrlString = UserDefaults.standard.string(forKey: "scene_\(sceneId)_hlsURL"),
        savedHlsUrlString.contains("/scene/\(sceneId)/"),
        let savedHlsUrl = URL(string: savedHlsUrlString) {
        print("📱 [Native] Using saved HLS URL: \(savedHlsUrlString)")
        if effectiveStartTime == nil,
          let tRange = savedHlsUrlString.range(of: "t=\\d+", options: .regularExpression),
          let tValue = Int(savedHlsUrlString[tRange].replacingOccurrences(of: "t=", with: "")) {
          effectiveStartTime = Double(tValue)
        }
        return savedHlsUrl
      }
      UserDefaults.standard.removeObject(forKey: "scene_\(sceneId)_hlsURL")

      var hlsStreamURL =
        "\(baseServerURL)/scene/\(sceneId)/stream.m3u8?apikey=\(apiKey)&resolution=ORIGINAL"
      if let startTime = effectiveStartTime {
        hlsStreamURL += "&t=\(Int(startTime))"
      }
      hlsStreamURL += "&_ts=\(currentTimestamp)"
      print("🔄 [Native] HLS URL: \(hlsStreamURL)")
      UserDefaults.standard.set(hlsStreamURL, forKey: "scene_\(sceneId)_hlsURL")
      if let url = URL(string: hlsStreamURL) {
        return url
      }
    }

    // Absolute fallback
    if let stream = currentScene.paths.stream, let url = URL(string: stream) {
      return url
    }
    print("❌ [Native] Critical: no stream URL for scene \(currentScene.id)")
    return URL(string: "about:blank")!
  }

  // MARK: - App actions

  /// Universal next - same priority order as the X key in the legacy player
  private func universalNext() {
    isRandomJumpMode = isRandomJumpMode || UserDefaults.standard.bool(forKey: "isRandomJumpMode")

    // Marker shuffle gets first priority when active (matches V-key/queue behavior)
    if appModel.isMarkerShuffleMode && !appModel.markerShuffleQueue.isEmpty {
      appModel.shuffleToNextMarker()
      return
    }
    if appModel.isTagSceneShuffleMode && !appModel.tagSceneShuffleQueue.isEmpty {
      appModel.shuffleToNextTagScene()
      return
    }
    if appModel.isMostPlayedShuffleMode && !appModel.mostPlayedShuffleQueue.isEmpty {
      appModel.shuffleToNextMostPlayedScene()
      return
    }
    if appModel.isPerformerShuffleMode {
      performerRandomScene()
      return
    }
    if isRandomJumpMode {
      nextSceneWithRandomJump()
      return
    }
    nextSceneSequential()
  }

  /// The list the user actually started playback from
  private var navigationContextScenes: [StashScene] {
    let pb = appModel.playbackScenes
    let display = appModel.api.scenes
    if pb.contains(where: { $0.id == currentScene.id }) { return pb }
    if display.contains(where: { $0.id == currentScene.id }) { return display }
    return pb.isEmpty ? display : pb
  }

  private func nextSceneSequential() {
    let contextScenes = navigationContextScenes
    let currentIndex = contextScenes.firstIndex(of: currentScene) ?? -1

    if currentIndex >= 0 && currentIndex < contextScenes.count - 1 {
      playScene(contextScenes[currentIndex + 1])
    } else if let firstScene = contextScenes.first {
      playScene(firstScene)
    } else {
      print("⚠️ [Native] No scenes available for sequential navigation")
    }
  }

  private func nextSceneWithRandomJump() {
    Task {
      var context = navigationContextScenes
      if context.isEmpty {
        context = await fetchFreshRandomScenes()
      }

      await MainActor.run {
        guard let nextScene = nextRandomShuffleScene(in: context) else {
          print("⚠️ [Native] No scenes available for random jump navigation")
          return
        }
        playScene(nextScene)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
          if let player = VideoPlayerRegistry.shared.currentPlayer {
            VideoPlayerUtility.jumpToRandomPosition(in: player)
          }
        }
      }
    }
  }

  /// Shuffled, no-repeat walk of the context (every scene plays once before repeats)
  private func nextRandomShuffleScene(in context: [StashScene]) -> StashScene? {
    let pool = context.filter { !$0.isVR }
    guard !pool.isEmpty else { return nil }

    let signature = "\(pool.count):\(pool.first?.id ?? "")-\(pool.last?.id ?? "")"
    let needsRebuild =
      randomShuffleQueue.isEmpty
      || randomShuffleContextSignature != signature
      || randomShuffleIndex >= randomShuffleQueue.count

    if needsRebuild {
      var shuffled = pool.shuffled()
      if shuffled.count > 1, shuffled.first?.id == currentScene.id {
        shuffled.swapAt(0, shuffled.count - 1)
      }
      randomShuffleQueue = shuffled
      randomShuffleContextSignature = signature
      randomShuffleIndex = 0
    }

    let next = randomShuffleQueue[randomShuffleIndex]
    randomShuffleIndex += 1
    return next
  }

  /// Library random: completely random (female-preferenced, VR-excluded) scene
  private func libraryRandomShuffle() {
    Task {
      await MainActor.run {
        // Clear performer context so subsequent performer shuffles use the NEW scene
        appModel.currentPerformer = nil
        originalPerformer = nil
      }

      let scenes = await fetchFreshRandomScenes()
      guard let randomScene = scenes.randomElement() else {
        print("⚠️ [Native] Library shuffle: no scenes returned")
        return
      }

      await MainActor.run {
        appModel.playbackScenes = scenes
        isRandomJumpMode = true
        UserDefaults.standard.set(true, forKey: "isRandomJumpMode")
        updateOriginalPerformer(for: randomScene)
        playScene(randomScene)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
          if let player = VideoPlayerRegistry.shared.currentPlayer {
            VideoPlayerUtility.jumpToRandomPosition(in: player)
          }
        }
      }
    }
  }

  /// Performer shuffle: play a different scene featuring the same performer
  private func performerRandomScene() {
    guard !isPerformerShuffleInProgress else { return }
    isPerformerShuffleInProgress = true

    // Failsafe reset
    DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
      isPerformerShuffleInProgress = false
    }

    // Sync scene from appModel if a marker/shuffle flow updated it behind our back
    if let appModelScene = appModel.currentScene, appModelScene.id != currentScene.id {
      currentScene = appModelScene
    }

    // Leaving marker shuffle for performer shuffle clears the marker context
    if appModel.isMarkerShuffleMode {
      appModel.isMarkerShuffleMode = false
      appModel.markerShuffleQueue = []
      appModel.currentShuffleIndex = 0
      appModel.shuffleTagFilter = nil
      appModel.shuffleSearchQuery = nil
      UserDefaults.standard.set(false, forKey: "isMarkerShuffleContext")
      appModel.currentPerformer = nil
      appModel.performerDetailViewPerformer = nil
      appModel.performerShufflePerformer = nil
      appModel.isPerformerShuffleMode = false
      originalPerformer = nil
      currentMarker = nil
    }

    // Performer selection priority (mirrors the legacy player):
    // stored shuffle performer -> detail-view performer -> current performer in scene
    // -> original performer in scene -> female performer of current scene
    var selectedPerformer: StashScene.Performer?

    if appModel.isPerformerShuffleMode,
      let shufflePerformer = appModel.performerShufflePerformer,
      currentScene.performers.contains(where: { $0.id == shufflePerformer.id })
        || appModel.performerDetailViewPerformer?.id == shufflePerformer.id {
      selectedPerformer = shufflePerformer
    }
    if selectedPerformer == nil, let detailPerformer = appModel.performerDetailViewPerformer {
      if currentScene.performers.contains(where: { $0.id == detailPerformer.id }) {
        selectedPerformer = detailPerformer
      } else {
        let sameGender = currentScene.performers.first { $0.gender == detailPerformer.gender }
        selectedPerformer = sameGender ?? currentScene.performers.first
      }
    }
    if selectedPerformer == nil, let currentPerf = appModel.currentPerformer,
      currentScene.performers.contains(where: { $0.id == currentPerf.id }) {
      selectedPerformer = currentPerf
    }
    if selectedPerformer == nil, let originalPerf = originalPerformer,
      currentScene.performers.contains(where: { $0.id == originalPerf.id }) {
      selectedPerformer = originalPerf
    }
    if selectedPerformer == nil {
      let femalePerformer = currentScene.performers.first { Self.isLikelyFemale($0) }
      selectedPerformer = femalePerformer ?? currentScene.performers.first
      originalPerformer = selectedPerformer
    }

    guard let performer = selectedPerformer else {
      print("⚠️ [Native] No performers in current scene - jumping to random position instead")
      isPerformerShuffleInProgress = false
      jumpToRandomPosition()
      return
    }

    appModel.isPerformerShuffleMode = true
    appModel.performerShufflePerformer = performer
    appModel.currentPerformer = performer

    Task {
      defer {
        Task { @MainActor in
          isPerformerShuffleInProgress = false
        }
      }

      let query = """
        {
            "operationName": "FindScenes",
            "variables": {
                "filter": {
                    "page": 1,
                    "per_page": 100,
                    "sort": "random",
                    "direction": "DESC"
                },
                "scene_filter": {
                    "performers": {
                        "value": ["\(performer.id)"],
                        "modifier": "INCLUDES"
                    }
                }
            },
            "query": "query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) { findScenes(filter: $filter, scene_filter: $scene_filter) { count scenes { id title details paths { screenshot preview stream } files { size duration video_codec width height format frame_rate } performers { id name gender scene_count } tags { id name } rating100 } } }"
        }
        """

      do {
        let data = try await appModel.api.executeGraphQLQuery(query)

        struct FindScenesResponse: Decodable {
          struct DataField: Decodable {
            struct FindScenes: Decodable {
              let count: Int
              let scenes: [StashScene]
            }
            let findScenes: FindScenes
          }
          let data: DataField
        }

        let response = try JSONDecoder().decode(FindScenesResponse.self, from: data)
        let performerScenes = response.data.findScenes.scenes.filter { !$0.isVR }

        await MainActor.run {
          let otherScenes = performerScenes.filter { $0.id != currentScene.id }
          guard let randomScene = otherScenes.randomElement() ?? performerScenes.first else {
            print("⚠️ [Native] No scenes found for performer \(performer.name)")
            return
          }

          print("🎭 [Native] Performer shuffle -> \(randomScene.title ?? "Untitled")")
          appModel.playbackScenes = performerScenes
          playScene(randomScene)

          DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let player = VideoPlayerRegistry.shared.currentPlayer {
              VideoPlayerUtility.jumpToRandomPosition(in: player)
            }
          }
        }
      } catch {
        print("❌ [Native] Performer shuffle query failed: \(error)")
      }
    }
  }

  /// Fresh batch of random, female-preferenced, VR-excluded library scenes
  private func fetchFreshRandomScenes() async -> [StashScene] {
    let query = """
      {
          "operationName": "FindScenes",
          "variables": {
              "filter": {
                  "page": 1,
                  "per_page": 100,
                  "sort": "random",
                  "direction": "ASC"
              },
              "scene_filter": {
                  "performer_gender": {
                      "value": ["FEMALE"],
                      "modifier": "INCLUDES"
                  }
              }
          },
          "query": "query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) { findScenes(filter: $filter, scene_filter: $scene_filter) { count scenes { id title details paths { screenshot preview stream } files { size duration video_codec width height format frame_rate } performers { id name gender scene_count } tags { id name } rating100 } } }"
      }
      """

    do {
      let data = try await appModel.api.executeGraphQLQuery(query)

      struct FindScenesResponse: Decodable {
        struct DataField: Decodable {
          struct FindScenes: Decodable {
            let count: Int
            let scenes: [StashScene]
          }
          let findScenes: FindScenes
        }
        let data: DataField
      }

      let response = try JSONDecoder().decode(FindScenesResponse.self, from: data)
      return response.data.findScenes.scenes.filter { scene in
        !scene.tags.contains { $0.name.lowercased() == "vr" }
      }
    } catch {
      print("⚠️ [Native] fetchFreshRandomScenes failed: \(error.localizedDescription)")
      return []
    }
  }

  /// Plays a scene in the current player (no navigation flicker)
  private func playScene(_ newScene: StashScene) {
    currentScene = newScene
    appModel.currentScene = newScene
    oCount = newScene.o_counter ?? 0
    SessionHistoryManager.shared.addEntry(scene: newScene)

    guard let player = VideoPlayerRegistry.shared.currentPlayer else {
      print("⚠️ [Native] Cannot play scene - player not found")
      return
    }
    guard let streamURL = VideoPlayerUtility.getStreamURL(for: newScene) else {
      print("❌ [Native] No stream URL for scene \(newScene.id)")
      return
    }

    let headers = ["User-Agent": "StashApp/iOS"]
    let asset = AVURLAsset(url: streamURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    let playerItem = AVPlayerItem(asset: asset)
    playerItem.preferredForwardBufferDuration = 5.0

    player.pause()
    player.replaceCurrentItem(with: playerItem)
    player.play()
  }

  private func jumpToRandomPosition() {
    guard let player = VideoPlayerRegistry.shared.currentPlayer else { return }
    VideoPlayerUtility.jumpToRandomPosition(in: player)
  }

  private func restartFromBeginning() {
    guard let player = VideoPlayerRegistry.shared.currentPlayer else { return }
    player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
      player.play()
    }
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
  }

  private func togglePlayPause() {
    guard let player = VideoPlayerRegistry.shared.currentPlayer else { return }
    if player.timeControlStatus == .playing {
      player.pause()
    } else {
      player.play()
    }
  }

  private func seekToPercentage(_ percentage: Double) {
    guard let player = VideoPlayerRegistry.shared.currentPlayer,
      let currentItem = player.currentItem,
      currentItem.duration.isValid,
      !currentItem.duration.seconds.isNaN,
      currentItem.duration.seconds > 0
    else { return }

    let targetSeconds = currentItem.duration.seconds * (percentage / 100.0)
    let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 1000)
    player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { success in
      if success {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if player.timeControlStatus != .playing {
          player.play()
        }
      }
    }
  }

  private func setAspect(_ gravity: AVLayerVideoGravity) {
    VideoPlayerRegistry.shared.playerViewController?.videoGravity = gravity
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  private func incrementOCounter() {
    guard !isIncrementingOCounter else { return }
    isIncrementingOCounter = true
    let previousCount = oCount
    oCount += 1  // Optimistic update

    Task {
      do {
        let updatedScene = try await appModel.api.incrementSceneOCounter(
          sceneID: currentScene.id, currentValue: previousCount)
        await MainActor.run {
          oCount = updatedScene.o_counter ?? (previousCount + 1)
          isIncrementingOCounter = false
          UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
      } catch {
        print("❌ [Native] Failed to increment O counter: \(error)")
        await MainActor.run {
          oCount = previousCount
          isIncrementingOCounter = false
        }
      }
    }
  }

  private func addToWatchHistory() {
    if appModel.skipNextHistoryAdd {
      appModel.skipNextHistoryAdd = false
      return
    }
    SessionHistoryManager.shared.addEntry(scene: currentScene)
  }

  // MARK: - Loading timeout (auto-advance in marker shuffle)

  private func startVideoLoadingTimeout() {
    videoLoadingTimer?.invalidate()
    videoLoadingTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { _ in
      let isMarkerShuffle = UserDefaults.standard.bool(forKey: "isMarkerShuffleContext")
      if isMarkerShuffle {
        print("⚫ [Native] Video loading timeout - auto-advancing to next marker")
        DispatchQueue.main.async {
          NotificationCenter.default.post(
            name: NSNotification.Name("VideoLoadingTimeout"), object: nil)
        }
      }
    }
  }

  private func cancelVideoLoadingTimeout() {
    videoLoadingTimer?.invalidate()
    videoLoadingTimer = nil
  }

  // MARK: - Keyboard shortcuts (same mapping as the legacy player)

  private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
    let key = keyPress.key
    let character = key.character

    switch character.lowercased() {
    case "v":
      // V: next marker when in marker shuffle mode
      if appModel.isMarkerShuffleMode && !appModel.markerShuffleQueue.isEmpty {
        if let nextMarker = appModel.nextMarkerInShuffle() {
          appModel.navigateToMarker(nextMarker)
        }
      }
      return .handled
    case "x":
      universalNext()
      return .handled
    case "b":
      VideoPlayerRegistry.shared.seek(by: -30)
      return .handled
    case "n":
      jumpToRandomPosition()
      return .handled
    case "m":
      performerRandomScene()
      return .handled
    case "<", ",":
      libraryRandomShuffle()
      return .handled
    case "r":
      restartFromBeginning()
      return .handled
    case "a":
      cycleAspectRatio()
      return .handled
    case "1": seekToPercentage(10); return .handled
    case "2": seekToPercentage(20); return .handled
    case "3": seekToPercentage(30); return .handled
    case "4": seekToPercentage(40); return .handled
    case "5": seekToPercentage(50); return .handled
    case "6": seekToPercentage(60); return .handled
    case "7": seekToPercentage(70); return .handled
    case "8": seekToPercentage(80); return .handled
    case "9": seekToPercentage(90); return .handled
    case "0": seekToPercentage(95); return .handled
    default:
      break
    }

    if key == .leftArrow {
      VideoPlayerRegistry.shared.seek(by: -30)
      return .handled
    }
    if key == .rightArrow {
      VideoPlayerRegistry.shared.seek(by: 30)
      return .handled
    }
    if key == .space {
      togglePlayPause()
      return .handled
    }

    return .ignored
  }

  private func handleMenuKeyboardShortcut(_ keyCode: UIKeyboardHIDUsage) {
    switch keyCode {
    case .keyboardV:
      if appModel.isMarkerShuffleMode && !appModel.markerShuffleQueue.isEmpty {
        appModel.shuffleToNextMarker()
      } else {
        universalNext()
      }
    case .keyboardB, .keyboardLeftArrow:
      VideoPlayerRegistry.shared.seek(by: -30)
    case .keyboardRightArrow:
      VideoPlayerRegistry.shared.seek(by: 30)
    case .keyboardN:
      jumpToRandomPosition()
    case .keyboardM:
      performerRandomScene()
    case .keyboardComma:
      libraryRandomShuffle()
    case .keyboardR:
      restartFromBeginning()
    case .keyboardX:
      universalNext()
    case .keyboardA:
      cycleAspectRatio()
    case .keyboardSpacebar:
      togglePlayPause()
    default:
      break
    }
  }

  private func cycleAspectRatio() {
    guard let playerVC = VideoPlayerRegistry.shared.playerViewController else { return }
    switch playerVC.videoGravity {
    case .resizeAspect:
      playerVC.videoGravity = .resizeAspectFill
    case .resizeAspectFill:
      playerVC.videoGravity = .resize
    default:
      playerVC.videoGravity = .resizeAspect
    }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  // MARK: - Helpers

  private static func isLikelyFemale(_ performer: StashScene.Performer) -> Bool {
    if performer.gender == "FEMALE" { return true }
    if performer.gender == "MALE" { return false }
    return true  // Default to female for unknown gender
  }
}
