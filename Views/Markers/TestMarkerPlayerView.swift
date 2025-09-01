import AVKit
import SwiftUI

/// A test view to debug marker playback
struct TestMarkerPlayerView: View {
  @EnvironmentObject private var appModel: AppModel
  @State private var marker: SceneMarker?
  @State private var isLoading = true
  @State private var player: AVPlayer?
  @State private var errorMessage: String?

  // Player tracking
  @State private var isPlaybackReady = false
  @State private var playbackStarted = false
  @State private var currentPosition: Double = 0

  // URL tracking for fallback handling
  @State private var directMarkerStreamUrl: String = ""
  @State private var markerPreviewUrl: String = ""
  @State private var sceneWithTimestampUrl: String = ""
  @State private var sceneStreamUrl: String = ""
  @State private var currentUrlIndex: Int = 0
  @State private var tryCount: Int = 0

  var body: some View {
    VStack {
      if isLoading {
        ProgressView("Loading test marker...")
          .padding()
      } else if let errorMessage = errorMessage {
        VStack(spacing: 16) {
          Image(systemName: "exclamationmark.circle")
            .font(.system(size: 50))
            .foregroundColor(.red)

          Text("Error: \(errorMessage)")
            .multilineTextAlignment(.center)
            .padding()

          Button("Retry") {
            Task {
              await loadTestMarker()
            }
          }
          .buttonStyle(.borderedProminent)
        }
        .padding()
      } else if let marker = marker {
        VStack(spacing: 16) {
          // Marker info
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              // Make title tappable to go to full-screen view
              Button(action: {
                // Navigate to the full scene at marker's position
                appModel.navigateToMarker(marker)
                print("🚀 Navigating to full scene at marker position: \(marker.seconds) seconds")
              }) {
                Text("Marker: \(marker.title)")
                  .font(.headline)
                  .foregroundColor(.blue)
                  .underline()
              }

              Spacer()

              Text("ID: \(marker.id)")
                .font(.caption)
                .foregroundColor(.secondary)
            }

            HStack {
              Text("Time: \(String(format: "%.2f", marker.seconds)) seconds")

              Spacer()

              if let endSeconds = marker.end_seconds {
                Text("End: \(String(format: "%.2f", endSeconds)) seconds")
              }
            }
            .font(.subheadline)

            Text("Scene: \(marker.scene.title ?? "Unknown")")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
          .padding()
          .background(Color(UIColor.secondarySystemBackground))
          .cornerRadius(8)

          // Player
          ZStack {
            if player != nil && isPlaybackReady {
              VideoPlayer(player: player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .cornerRadius(8)
            } else {
              // Placeholder while player loads
              Rectangle()
                .fill(Color.black.opacity(0.8))
                .aspectRatio(16 / 9, contentMode: .fit)
                .cornerRadius(8)
                .overlay(
                  ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                )
            }
          }

          // Playing controls
          VStack(spacing: 8) {
            // Info about playback status
            if playbackStarted {
              HStack {
                Text("Current position: \(String(format: "%.2f", currentPosition)) seconds")
                  .font(.caption)
                  .foregroundColor(.secondary)

                Spacer()

                Circle()
                  .fill(player?.timeControlStatus == .playing ? Color.green : Color.red)
                  .frame(width: 10, height: 10)

                Text(player?.timeControlStatus == .playing ? "Playing" : "Paused")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }

            // Control buttons
            HStack(spacing: 20) {
              // Play at marker position
              Button(action: {
                playAtMarkerPosition()
              }) {
                VStack {
                  Image(systemName: "play.circle")
                    .font(.system(size: 30))
                  Text("Play Marker")
                    .font(.caption)
                }
              }

              // Pause
              Button(action: {
                player?.pause()
              }) {
                VStack {
                  Image(systemName: "pause.circle")
                    .font(.system(size: 30))
                  Text("Pause")
                    .font(.caption)
                }
              }

              // Play from beginning
              Button(action: {
                player?.seek(to: .zero)
                player?.play()
              }) {
                VStack {
                  Image(systemName: "backward.end.circle")
                    .font(.system(size: 30))
                  Text("Beginning")
                    .font(.caption)
                }
              }

              // Random seek in current marker
              Button(action: {
                seekToRandomPosition()
              }) {
                VStack {
                  Image(systemName: "shuffle.circle")
                    .font(.system(size: 25))
                  Text("Random Pos")
                    .font(.caption)
                }
              }

              // Load random marker
              Button(action: {
                Task {
                  await loadRandomMarker()
                }
              }) {
                VStack {
                  Image(systemName: "dice")
                    .font(.system(size: 25))
                  Text("New Marker")
                    .font(.caption)
                }
              }
              .foregroundColor(.blue)
            }
          }
          .padding()
          .background(Color(UIColor.secondarySystemBackground))
          .cornerRadius(8)

          // URL and debugging info
          ScrollView {
            VStack(alignment: .leading, spacing: 8) {
              Text("Debug Information")
                .font(.headline)
                .padding(.bottom, 4)

              Group {
                Text("Scene ID: \(marker.scene.id)")
                Text("Marker ID: \(marker.id)")
                Text("Stream URL: \(marker.stream)")
                Text("Preview URL: \(marker.preview)")

                if let player = player, let currentItem = player.currentItem {
                  Text("Player Status: \(statusToString(currentItem.status))")
                  Text("Error: \(String(describing: currentItem.error))")
                  Text("Duration: \(currentItem.duration.seconds) seconds")
                }
              }
              .font(.caption)
              .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(8)
          }
          .frame(maxHeight: 200)
        }
        .padding()
      } else {
        VStack(spacing: 16) {
          Text("No marker loaded")
            .font(.headline)

          Button("Load Test Marker") {
            Task {
              await loadTestMarker()
            }
          }
          .buttonStyle(.borderedProminent)
        }
        .padding()
      }
    }
    .task {
      // Load marker on appear
      await loadTestMarker()
    }
    .navigationTitle("Test Marker Player")
    .onDisappear {
      // Clean up player
      player?.pause()
      player = nil
    }
  }

  // Helper to convert status to string
  private func statusToString(_ status: AVPlayerItem.Status) -> String {
    switch status {
    case .readyToPlay:
      return "Ready to Play"
    case .failed:
      return "Failed"
    case .unknown:
      return "Unknown"
    @unknown default:
      return "Unknown (\(status.rawValue))"
    }
  }

  // Try the next URL format when one fails
  private func tryNextUrlFormat() {
    // Limit retries
    tryCount += 1
    if tryCount > 4 {
      errorMessage = "Failed after trying all URL formats"
      return
    }

    // Get the next URL to try
    currentUrlIndex += 1
    let urlOptions = [
      directMarkerStreamUrl,
      sceneStreamUrl,
      markerPreviewUrl,
      sceneWithTimestampUrl
    ]

    // Make sure we have a valid index
    if currentUrlIndex >= urlOptions.count {
      currentUrlIndex = 0
    }

    // Get the URL to try
    let nextUrlString = urlOptions[currentUrlIndex]

    print("🔄 Trying URL format #\(currentUrlIndex + 1): \(nextUrlString)")

    guard let url = URL(string: nextUrlString) else {
      print("❌ Invalid URL: \(nextUrlString)")
      // Try next URL
      tryNextUrlFormat()
      return
    }

    // Set up new player with this URL
    setupPlayer(withURL: url)
  }

  // Create a player for the marker with option to specify URL
  private func setupPlayer(for marker: SceneMarker, withURL specificURL: URL? = nil) {
    // Reset tracking
    tryCount = 0
    currentUrlIndex = 0

    // Extract IDs
    let markerId = marker.id
    let sceneId = marker.scene.id

    // Clean up server address
    let baseServerURL = appModel.serverAddress.trimmingCharacters(
      in: CharacterSet(charactersIn: "/"))

    // Get API key
    let apiKey = appModel.api.apiKeyForURLs
    let apiKeySuffix = apiKey.isEmpty ? "" : "&apikey=\(apiKey)"
    let querySuffix = apiKey.isEmpty ? "" : "?apikey=\(apiKey)"

    // Create alternate URLs to test different formats
    let sceneWithTimestampUrl =
      "\(baseServerURL)/scenes/\(sceneId)?t=\(Int(marker.seconds))\(apiKeySuffix)"
    let directMarkerStreamUrl =
      "\(baseServerURL)/scene/\(sceneId)/scene_marker/\(markerId)/stream\(querySuffix)"
    let markerPreviewUrl =
      marker.preview.isEmpty
      ? "\(baseServerURL)/scene/\(sceneId)/preview\(querySuffix)"
      : marker.preview
        + (marker.preview.contains("?")
          ? "&apikey=\(apiKey)" : (apiKey.isEmpty ? "" : "?apikey=\(apiKey)"))
    let sceneStreamUrl = "\(baseServerURL)/scene/\(sceneId)/stream\(querySuffix)"

    // Store URLs as properties to access in error handlers
    self.directMarkerStreamUrl = directMarkerStreamUrl
    self.markerPreviewUrl = markerPreviewUrl
    self.sceneWithTimestampUrl = sceneWithTimestampUrl
    self.sceneStreamUrl = sceneStreamUrl

    print("🎬 URL Options:")
    print("1. Scene with timestamp: \(sceneWithTimestampUrl)")
    print("2. Direct marker stream: \(directMarkerStreamUrl)")
    print("3. Marker preview: \(markerPreviewUrl)")
    print("4. Scene stream: \(sceneStreamUrl)")

    // Choose initial URL to try
    let url: URL
    if let specificURL = specificURL {
      url = specificURL
      print("🎬 Using provided URL: \(specificURL)")
    } else {
      // Try the /scenes/ID?t=SECONDS format first as this is what works in the browser
      if let constructedUrl = URL(string: sceneWithTimestampUrl) {
        url = constructedUrl
        print("🎬 Using default URL: \(sceneWithTimestampUrl)")
      } else if let fallbackUrl = URL(string: directMarkerStreamUrl) {
        url = fallbackUrl
        print("🎬 Using fallback URL: \(directMarkerStreamUrl)")
      } else {
        print("❌ Could not create any valid URLs")
        errorMessage = "Could not create valid URLs for marker"
        return
      }
    }

    // Use the simplified setup method
    setupPlayer(withURL: url)
  }

  // Simplified method to set up a player with just a URL
  private func setupPlayer(withURL url: URL) {
    guard let marker = marker else { return }

    print("🎬 Setting up player with URL: \(url)")

    // Clean up previous player
    player?.pause()
    player = nil

    // Create HTTP headers
    let headers = [
      "Accept": "*/*",
      "Accept-Language": "en-US,en;q=0.9",
      "Connection": "keep-alive",
      "Range": "bytes=0-",
      "User-Agent":
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36"
    ]

    // Create asset with headers
    let asset = AVURLAsset(
      url: url,
      options: [
        "AVURLAssetHTTPHeaderFieldsKey": headers
      ])

    // Create player item
    let playerItem = AVPlayerItem(asset: asset)

    // Create player
    let player = AVPlayer(playerItem: playerItem)
    player.volume = 0.5

    // Add status observer - Don't use weak self as TestMarkerPlayerView is a struct
    let statusObserver = playerItem.observe(\.status) { item, _ in
      DispatchQueue.main.async {
        switch item.status {
        case .readyToPlay:
          print("✅ Player ready to play with URL: \(url)")
          self.isPlaybackReady = true
          self.errorMessage = nil

          // Seek to marker position
          self.playAtMarkerPosition()

        case .failed:
          print("❌ Player failed with URL: \(url)")
          if let error = item.error as NSError? {
            print("❌ Error: \(error.localizedDescription)")

            // If it's a format error, try another URL
            if error.domain == "AVFoundationErrorDomain" && error.code == -11828 {
              print("❌ Format not supported, trying next URL")
              self.tryNextUrlFormat()
            } else {
              self.errorMessage = "Player error: \(error.localizedDescription)"
            }
          } else {
            self.errorMessage = "Player failed with unknown error"
          }

        case .unknown:
          print("⚠️ Player status unknown")

        @unknown default:
          print("⚠️ Unknown player status")
        }
      }
    }

    // Add time observer for tracking position
    let timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
    ) { time in
      self.currentPosition = time.seconds

      if !self.playbackStarted && time.seconds > 0 {
        self.playbackStarted = true
      }
    }

    // Store observers to prevent deallocation
    if playerItem.accessibilityElements == nil {
      playerItem.accessibilityElements = [statusObserver, timeObserver]
    } else {
      playerItem.accessibilityElements =
        (playerItem.accessibilityElements ?? []) + [statusObserver, timeObserver]
    }

    // Store player
    self.player = player
  }

  // Load a random marker
  private func loadRandomMarker() async {
    isLoading = true
    errorMessage = nil

    // Clean up previous player
    player?.pause()
    player = nil
    isPlaybackReady = false
    playbackStarted = false

    do {
      // First, get total marker count
      let countQuery = """
        {
            "operationName": "FindSceneMarkers",
            "variables": {
                "filter": {
                    "page": 1,
                    "per_page": 1
                }
            },
            "query": "query FindSceneMarkers($filter: FindFilterType) { findSceneMarkers(filter: $filter) { count } }"
        }
        """

      let countData = try await appModel.api.executeGraphQLQuery(countQuery)

      struct CountResponse: Decodable {
        struct Data: Decodable {
          struct FindSceneMarkers: Decodable {
            let count: Int
          }
          let findSceneMarkers: FindSceneMarkers
        }
        let data: Data
      }

      let countResponse = try JSONDecoder().decode(CountResponse.self, from: countData)
      let totalMarkers = countResponse.data.findSceneMarkers.count

      // Generate a random marker index
      let randomIndex = Int.random(in: 0..<totalMarkers)

      print("🎲 Total markers: \(totalMarkers), selecting random index: \(randomIndex)")

      // Query to get a specific marker by index
      let query = """
        {
            "operationName": "FindSceneMarkers",
            "variables": {
                "filter": {
                    "page": \(randomIndex + 1),
                    "per_page": 1
                }
            },
            "query": "query FindSceneMarkers($filter: FindFilterType) { findSceneMarkers(filter: $filter) { count scene_markers { id title seconds end_seconds stream preview screenshot scene { id title paths { stream screenshot } } primary_tag { id name } tags { id name } } } }"
        }
        """

      print("🎲 Loading random marker at index \(randomIndex)")

      let data = try await appModel.api.executeGraphQLQuery(query)

      struct MarkerResponse: Decodable {
        struct Data: Decodable {
          struct FindSceneMarkers: Decodable {
            let count: Int
            let scene_markers: [SceneMarker]
          }
          let findSceneMarkers: FindSceneMarkers
        }
        let data: Data
      }

      let response = try JSONDecoder().decode(MarkerResponse.self, from: data)

      // Make sure we have a marker
      guard let randomMarker = response.data.findSceneMarkers.scene_markers.first else {
        throw NSError(
          domain: "TestMarkerPlayer", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "No random marker found"])
      }

      // Set the marker
      await MainActor.run {
        self.marker = randomMarker
        print("🎲 Loaded random marker: \(randomMarker.title)")
        print("🎲 Marker seconds: \(randomMarker.seconds)")
        print("🎲 Scene ID: \(randomMarker.scene.id)")
        print("🎲 Marker ID: \(randomMarker.id)")

        // Create the player
        setupPlayer(for: randomMarker)
      }
    } catch {
      print("❌ Error loading random marker: \(error)")
      await MainActor.run {
        self.errorMessage = "Failed to load random marker: \(error.localizedDescription)"
      }
    }

    await MainActor.run {
      isLoading = false
    }
  }

  // Load a test marker for debugging
  private func loadTestMarker() async {
    isLoading = true
    errorMessage = nil

    // Clean up previous player
    player?.pause()
    player = nil
    isPlaybackReady = false
    playbackStarted = false

    do {
      // Query to get a single marker
      let query = """
        {
            "operationName": "FindSceneMarkers",
            "variables": {
                "filter": {
                    "page": 1,
                    "per_page": 1
                }
            },
            "query": "query FindSceneMarkers($filter: FindFilterType) { findSceneMarkers(filter: $filter) { count scene_markers { id title seconds end_seconds stream preview screenshot scene { id title paths { stream screenshot } } primary_tag { id name } tags { id name } } } }"
        }
        """

      let data = try await appModel.api.executeGraphQLQuery(query)

      struct MarkerResponse: Decodable {
        struct Data: Decodable {
          struct FindSceneMarkers: Decodable {
            let count: Int
            let scene_markers: [SceneMarker]
          }
          let findSceneMarkers: FindSceneMarkers
        }
        let data: Data
      }

      let response = try JSONDecoder().decode(MarkerResponse.self, from: data)

      // Make sure we have a marker
      guard let firstMarker = response.data.findSceneMarkers.scene_markers.first else {
        throw NSError(
          domain: "TestMarkerPlayer", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "No markers found"])
      }

      // Set the marker
      await MainActor.run {
        self.marker = firstMarker
        print("✅ Loaded test marker: \(firstMarker.title)")
        print("🔍 Marker seconds: \(firstMarker.seconds)")
        print("🔍 Scene ID: \(firstMarker.scene.id)")
        print("🔍 Marker ID: \(firstMarker.id)")

        // Create the player
        setupPlayer(for: firstMarker)
      }
    } catch {
      print("❌ Error loading test marker: \(error)")
      await MainActor.run {
        self.errorMessage = error.localizedDescription
      }
    }

    await MainActor.run {
      isLoading = false
    }
  }

  // Play from marker position
  private func playAtMarkerPosition() {
    guard let marker = marker, let player = player else { return }

    print("▶️ Playing marker at position: \(marker.seconds) seconds")

    // Seek to marker position
    let seekTime = CMTime(seconds: Double(marker.seconds), preferredTimescale: 600)

    // Use precise seeking
    player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { success in
      print("⏱️ Seek result: \(success ? "success" : "failed")")

      // Start playback
      player.play()

      // Check position after a moment
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        print("📍 Position after seek: \(player.currentTime().seconds) seconds")
      }
    }
  }

  // Seek to random position
  private func seekToRandomPosition() {
    guard let player = player, let marker = marker,
      let duration = player.currentItem?.duration.seconds, duration > 0
    else { return }

    // Generate random position within the first half of the video
    let maxPosition = min(duration * 0.5, 30.0)  // Max 30 seconds or half the video
    let randomPosition = Double.random(in: 0...maxPosition)

    print("🔀 Seeking to random position: \(randomPosition) seconds")

    let seekTime = CMTime(seconds: randomPosition, preferredTimescale: 600)
    player.seek(to: seekTime)
    player.play()
  }
}

struct TestMarkerPlayerView_Previews: PreviewProvider {
  static var previews: some View {
    NavigationStack {
      TestMarkerPlayerView()
        .environmentObject(AppModel())
    }
  }
}
