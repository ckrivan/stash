import AVKit
import SwiftUI

class VideoPlayerViewModel: NSObject, ObservableObject {
    let player = AVPlayer()
    @Published var isLoading = true
    @Published var error: String?
    @Published var useHLS = true
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var bufferingProgress: Double = 0
    
    // Properties to track start and end times for marker playback
    var endSeconds: Double? = nil
    var explicitStartSeconds: Double? = nil
    private var markerEndTimeObserver: Any?

    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var bufferingObserver: NSKeyValueObservation?
    private var playerItem: AVPlayerItem?
    private var playToEndObserver: NSObjectProtocol?
    private var failedToPlayObserver: NSObjectProtocol?

    override init() {
        super.init()
        setupPlayer()

        // Register with GlobalVideoManager
        GlobalVideoManager.shared.registerPlayer(player)
    }

    private func setupPlayer() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        player.automaticallyWaitsToMinimizeStalling = true

        // Add periodic time observer
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            self.isLoading = false
            self.currentTime = time.seconds

            // Update isPlaying state based on player state
            self.isPlaying = self.player.timeControlStatus == .playing
            
            // Check if we've reached the marker end time
            if let endSeconds = self.endSeconds, self.currentTime >= endSeconds, self.isPlaying {
                print("🎬 Reached marker end time \(endSeconds), pausing playback")
                self.player.pause()
                self.isPlaying = false
                
                // Optionally, add a visual indicator that the marker has ended
                NotificationCenter.default.post(name: Notification.Name("MarkerEndReached"), object: nil)
            }
        }

        // Add play to end notification observer
        playToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.isPlaying = false

            // Seek back to beginning
            self.player.seek(to: .zero) { _ in
                self.isPlaying = false
            }
        }

        // Add failed to play notification observer
        failedToPlayObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                self.error = error.localizedDescription
                print("❌ Failed to play: \(error.localizedDescription)")
            }
        }
    }

    func setupPlayerItem(with url: URL) {
        // Create new player item
        let options = [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "Accept": "*/*",
                "Accept-Language": "en-US,en;q=0.9",
                "Connection": "keep-alive",
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
                "Accept-Encoding": "identity",  // Request uncompressed content
            ],
            "AVURLAssetHTTPUserAgentKey": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"
        ] as [String : Any]

        let asset = AVURLAsset(url: url, options: options)
        playerItem = AVPlayerItem(asset: asset)

        // Configure for better streaming
        playerItem?.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        playerItem?.preferredForwardBufferDuration = 10

        // Observe player item status
        statusObserver = playerItem?.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            guard let self = self else { return }

            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.duration = item.duration.seconds
                    self.error = nil
                    print("✅ Player ready to play")

                case .failed:
                    self.isLoading = false
                    self.error = item.error?.localizedDescription ?? "Unknown error"
                    print("❌ Player item failed: \(self.error ?? "Unknown error")")

                case .unknown:
                    self.isLoading = true
                    print("⏳ Player item status unknown")

                @unknown default:
                    self.isLoading = false
                }
            }
        }

        // Observe buffering progress
        bufferingObserver = playerItem?.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }

            // Calculate buffering progress
            if let timeRange = item.loadedTimeRanges.first?.timeRangeValue,
               item.duration.seconds > 0 {
                let bufferedSeconds = timeRange.start.seconds + timeRange.duration.seconds
                let progress = bufferedSeconds / item.duration.seconds
                self.bufferingProgress = min(max(0, progress), 1.0)
            }
        }

        // Replace current item
        player.replaceCurrentItem(with: playerItem)
    }

    func play() {
        player.play()
        isPlaying = true

        // Pause other players
        GlobalVideoManager.shared.pauseAllExcept(player)
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func mute(_ muted: Bool) {
        player.isMuted = muted
    }

    func cleanup() {
        player.pause()

        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Clear marker timestamps and observer
        endSeconds = nil
        explicitStartSeconds = nil
        if let observer = markerEndTimeObserver {
            player.removeTimeObserver(observer)
            markerEndTimeObserver = nil
        }

        // Remove KVO observers
        statusObserver?.invalidate()
        statusObserver = nil

        bufferingObserver?.invalidate()
        bufferingObserver = nil

        // Remove notification observers
        if let playToEndObserver = playToEndObserver {
            NotificationCenter.default.removeObserver(playToEndObserver)
            self.playToEndObserver = nil
        }

        if let failedToPlayObserver = failedToPlayObserver {
            NotificationCenter.default.removeObserver(failedToPlayObserver)
            self.failedToPlayObserver = nil
        }

        // Remove player item
        playerItem = nil
        player.replaceCurrentItem(with: nil)

        // Unregister from GlobalVideoManager
        GlobalVideoManager.shared.unregisterPlayer(player)
    }

    deinit {
        cleanup()
    }
} 