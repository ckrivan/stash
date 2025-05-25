import SwiftUI
import AVKit
import UIKit
import Combine

// Define a top-level custom view controller for AVPlayerViewController
class CustomPlayerViewController: UIViewController {
    let playerVC: AVPlayerViewController
    
    init(playerVC: AVPlayerViewController) {
        self.playerVC = playerVC
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Add the player view controller as a child
        addChild(playerVC)
        view.addSubview(playerVC.view)
        playerVC.view.frame = view.bounds
        playerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerVC.didMove(toParent: self)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Try to find and hide the gear button by walking the view hierarchy
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.hideGearButton(in: self.playerVC.view)
        }
    }
    
    func hideGearButton(in view: UIView) {
        // For debugging purposes, check if we have a button
        for subview in view.subviews {
            if let button = subview as? UIButton {
                // Check if this might be the gear button based on image or accessibility label
                if button.accessibilityLabel?.lowercased().contains("setting") == true {
                    button.isHidden = true
                    print("🔧 Found and hid a settings button")
                }
            }
            
            // Recursively search through subviews
            hideGearButton(in: subview)
        }
    }
}

struct VideoPlayerView: View {
    let scene: StashScene
    var startTime: Double?
    var endTime: Double?
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showVideoPlayer = false
    @State private var showControls = true  // Start with controls visible
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var currentScene: StashScene
    @State private var effectiveStartTime: Double?
    @State private var effectiveEndTime: Double?
    // Store the original performer for the performer button
    @State private var originalPerformer: StashScene.Performer?
    // Store the current marker
    @State private var currentMarker: SceneMarker?
    // Track whether we're in random jump mode
    @State private var isRandomJumpMode: Bool = false
    // Track whether we're in marker shuffle mode
    @State private var isMarkerShuffleMode: Bool = false
    
    init(scene: StashScene, startTime: Double? = nil, endTime: Double? = nil) {
        self.scene = scene
        self.startTime = startTime
        self.endTime = endTime
        _currentScene = State(initialValue: scene)

        // Log important parameters for debugging
        print("📱 VideoPlayerView init - scene: \(scene.id), startTime: \(String(describing: startTime)), endTime: \(String(describing: endTime))")
        
        // Set effective start time directly in init if provided
        if let startTime = startTime {
            _effectiveStartTime = State(initialValue: startTime)
            print("⏱ Setting effectiveStartTime directly to \(startTime) in init")
        }
        
        // Set effective end time directly in init if provided
        if let endTime = endTime {
            _effectiveEndTime = State(initialValue: endTime)
            print("⏱ Setting effectiveEndTime directly to \(endTime) in init")
        }

        // Initialize the original performer if available
        if let firstPerformer = scene.performers.first {
            print("📱 Initializing original performer to: \(firstPerformer.name) (ID: \(firstPerformer.id))")
            _originalPerformer = State(initialValue: firstPerformer)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background color
                Color.black.ignoresSafeArea()

                // Full screen video player
                FullScreenVideoPlayer(
                    url: getStreamURL(),  // Use custom method to get stream URL
                    startTime: effectiveStartTime,
                    endTime: effectiveEndTime,
                    scenes: appModel.api.scenes,
                    currentIndex: appModel.api.scenes.firstIndex(of: currentScene) ?? 0,
                    appModel: appModel
                )
                .ignoresSafeArea()
                .onAppear {
                    print("📱 FullScreenVideoPlayer appeared with startTime: \(String(describing: effectiveStartTime))")
                    
                    // Verify that seeking will happen if startTime is provided
                    if let startTime = effectiveStartTime, startTime > 0 {
                        print("⏱ FullScreenVideoPlayer will seek to \(startTime) seconds")
                    }
                }

                // This transparent layer captures taps across the entire view
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        print("👆 Tap detected - toggling controls")
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showControls.toggle()
                        }

                        // Schedule auto-hide when controls are shown
                        if showControls {
                            Task {
                                await scheduleControlsHide()
                            }
                        }
                    }

                // Control overlay - only show when showControls is true
                if showControls {
                    VStack {
                        // Close button at top
                        HStack {
                            Spacer()

                            Button(action: {
                                print("🔄 Close button tapped")
                                dismiss()
                                appModel.forceCloseVideo()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding()
                                    .shadow(radius: 2)
                            }
                        }
                        .padding(.top, 50)

                        Spacer()

                        // Playback control buttons at bottom
                        HStack(spacing: 15) {
                            Spacer()

                            // Next Scene button - Skip to next scene in the queue
                            Button {
                                print("🎬 Next Scene button tapped")
                                navigateToNextScene()
                            } label: {
                                ZStack {
                                    // Background circle
                                    Circle()
                                        .fill(Color.green.opacity(0.7))
                                        .frame(width: 50, height: 50)
                                        .shadow(color: .black, radius: 4)
                                    
                                    // Icon
                                    Image(systemName: "forward.fill")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                    // Outer border
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                                        .frame(width: 50, height: 50)
                                }
                            }
                            
                            // Seek backward 30 seconds button
                            Button {
                                print("⏪ Seek backward 30 seconds")
                                seekVideo(by: -30)
                            } label: {
                                ZStack {
                                    // Background circle
                                    Circle()
                                        .fill(Color.gray.opacity(0.7))
                                        .frame(width: 50, height: 50)
                                        .shadow(color: .black, radius: 4)

                                    // Icon
                                    Image(systemName: "gobackward.30")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.white)

                                    // Outer border
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                                        .frame(width: 50, height: 50)
                                }
                            }

                            // Button 1: Library Random - Play a completely random scene from library
                            Button {
                                print("🔄 Library random button tapped")
                                handlePureRandomVideo()
                            } label: {
                                ZStack {
                                    // Background circle
                                    Circle()
                                        .fill(Color.blue.opacity(0.7))
                                        .frame(width: 60, height: 60)
                                        .shadow(color: .black, radius: 4)

                                    // Icon
                                    Image(systemName: "shuffle")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.white)

                                    // Outer border
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                                        .frame(width: 60, height: 60)
                                }
                            }
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.5)
                                    .onEnded { _ in
                                        let generator = UIImpactFeedbackGenerator(style: .medium)
                                        generator.impactOccurred()
                                        // Show info about what this button does
                                        print("Showing button info: Random Scene")
                                    }
                            )

                            // Button 2: Random Position - Jump to random position in current video
                            Button {
                                print("🎲 Random position button tapped")
                                handleRandomVideo() // Uses playNextScene() which jumps within current video
                            } label: {
                                ZStack {
                                    // Background circle
                                    Circle()
                                        .fill(Color.purple.opacity(0.8))
                                        .frame(width: 60, height: 60)
                                        .shadow(color: .black, radius: 4)

                                    // Icon
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.white)

                                    // Outer border
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                                        .frame(width: 60, height: 60)
                                }
                            }
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.5)
                                    .onEnded { _ in
                                        let generator = UIImpactFeedbackGenerator(style: .medium)
                                        generator.impactOccurred()
                                        // Show info about what this button does
                                        print("Showing button info: Jump to Random Position")
                                    }
                            )

                            // Button 3: Performer Jump - Play a different scene with the same performer
                            Button {
                                print("👤 Performer random scene button tapped")
                                handlePerformerRandomVideo()
                            } label: {
                                ZStack {
                                    // Background circle
                                    Circle()
                                        .fill(Color.purple.opacity(0.8))
                                        .frame(width: 60, height: 60)
                                        .shadow(color: .black, radius: 4)

                                    // Icon - using a simpler icon and making it larger and more visible
                                    Image(systemName: "person.fill.and.arrow.left.and.arrow.right")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.white)

                                    // Outer border
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                                        .frame(width: 60, height: 60)
                                }
                            }
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.5)
                                    .onEnded { _ in
                                        let generator = UIImpactFeedbackGenerator(style: .medium)
                                        generator.impactOccurred()
                                        // Show info about what this button does
                                        print("Showing button info: Play Different Scene with Same Performer")
                                    }
                            )

                            // Seek forward 60 seconds button
                            Button {
                                print("⏩ Seek forward 60 seconds")
                                seekVideo(by: 60)
                            } label: {
                                ZStack {
                                    // Background circle
                                    Circle()
                                        .fill(Color.gray.opacity(0.7))
                                        .frame(width: 50, height: 50)
                                        .shadow(color: .black, radius: 4)

                                    // Icon
                                    Image(systemName: "goforward.60")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.white)

                                    // Outer border
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                                        .frame(width: 50, height: 50)
                                }
                            }
                        }
                        .padding(.bottom, 30)
                        .padding(.trailing, 20)
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: showControls)
                }
            }
            .navigationBarHidden(true) // Hide the navigation bar completely
            .statusBarHidden(true)     // Hide the status bar for full immersion
            .ignoresSafeArea(.all)     // Ignore all safe areas for true full screen
            .onAppear {
                print("📱 VideoPlayerView appeared")
                appModel.currentScene = scene

                // Check if this is a marker navigation
                let isMarkerNavigation = UserDefaults.standard.bool(forKey: "scene_\(scene.id)_isMarkerNavigation")
                
                // Get direct startTime parameter value as priority
                if let startTime = startTime {
                    print("📱 Using provided startTime parameter: \(startTime)")
                    effectiveStartTime = startTime
                } else if isMarkerNavigation {
                    // For marker navigation, try to get the start time from UserDefaults
                    let storedStartTime = UserDefaults.standard.double(forKey: "scene_\(scene.id)_startTime")
                    if storedStartTime > 0 {
                        print("📱 Using stored startTime from UserDefaults for marker: \(storedStartTime)")
                        effectiveStartTime = storedStartTime
                    }
                }
                
                // Get direct endTime parameter value if provided
                if let endTime = endTime {
                    print("📱 Using provided endTime parameter: \(endTime)")
                    effectiveEndTime = endTime
                } else {
                    // Check if there's a stored end time for this scene in UserDefaults
                    let storedEndTime = UserDefaults.standard.double(forKey: "scene_\(scene.id)_endTime")
                    if storedEndTime > 0 {
                        print("📱 Using stored endTime from UserDefaults: \(storedEndTime)")
                        effectiveEndTime = storedEndTime
                    }
                }

                // Enhanced performer context preservation
                // First check if there's a currentPerformer from PerformerDetailView context
                if let currentPerformer = appModel.currentPerformer,
                   scene.performers.contains(where: { $0.id == currentPerformer.id }) {
                    print("📱 Initializing original performer from PerformerDetailView context: \(currentPerformer.name)")
                    originalPerformer = currentPerformer
                } else {
                    // Default to female performers when no specific performer context (from SceneView)
                    let femalePerformer = scene.performers.first { $0.gender == "FEMALE" }
                    let selectedPerformer = femalePerformer ?? scene.performers.first
                    if let selectedPerformer = selectedPerformer {
                        print("📱 Setting original performer to: \(selectedPerformer.name) (gender: \(selectedPerformer.gender ?? "unknown"))")
                        originalPerformer = selectedPerformer
                    }
                }

                // Show controls initially, then hide after delay
                showControls = true
                Task {
                    await scheduleControlsHide()
                }
                
                // Listen for marker shuffle updates to avoid navigation flicker
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("UpdateVideoPlayerForMarkerShuffle"),
                    object: nil,
                    queue: .main
                ) { notification in
                    print("🔄 Received marker shuffle update notification")
                    if let userInfo = notification.userInfo,
                       let newScene = userInfo["scene"] as? StashScene,
                       let startSeconds = userInfo["startSeconds"] as? Double,
                       let hlsURL = userInfo["hlsURL"] as? String {
                        
                        print("🔄 Updating VideoPlayerView to new scene: \(newScene.id) at \(startSeconds)s")
                        
                        // Update the current scene and times
                        currentScene = newScene
                        effectiveStartTime = startSeconds
                        
                        if let endSeconds = userInfo["endSeconds"] as? Double {
                            effectiveEndTime = endSeconds
                        }
                        
                        // Update the current player with new content
                        if let player = getCurrentPlayer() {
                            print("🔄 Updating player with new content")
                            
                            // Create new player item with the HLS URL
                            if let url = URL(string: hlsURL) {
                                let headers = ["User-Agent": "StashApp/iOS"]
                                let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                                let playerItem = AVPlayerItem(asset: asset)
                                
                                // Replace current item
                                player.replaceCurrentItem(with: playerItem)
                                
                                // Seek to start time
                                let cmTime = CMTime(seconds: startSeconds, preferredTimescale: 1000)
                                player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                                    player.play()
                                }
                            }
                        }
                    }
                }
                
                // Listen for tag shuffle updates
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("UpdateVideoPlayerForTagShuffle"),
                    object: nil,
                    queue: .main
                ) { notification in
                    print("🔄 Received tag shuffle update notification")
                    if let userInfo = notification.userInfo,
                       let newScene = userInfo["scene"] as? StashScene,
                       let hlsURL = userInfo["hlsURL"] as? String {
                        
                        print("🔄 Updating VideoPlayerView to new tag scene: \(newScene.id)")
                        
                        // Update the current scene - tag shuffle doesn't use start/end times
                        currentScene = newScene
                        effectiveStartTime = nil
                        effectiveEndTime = nil
                        
                        // Update the current player with new content
                        if let player = getCurrentPlayer() {
                            print("🔄 Updating player with new tag scene content")
                            
                            // Create new player item with the HLS URL
                            if let url = URL(string: hlsURL) {
                                let headers = ["User-Agent": "StashApp/iOS"]
                                let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                                let playerItem = AVPlayerItem(asset: asset)
                                
                                // Replace current item
                                player.replaceCurrentItem(with: playerItem)
                                
                                // Start playing from the beginning
                                player.seek(to: .zero) { _ in
                                    player.play()
                                }
                            }
                        }
                    }
                }
            }
            .onDisappear {
                print("📱 VideoPlayerView disappeared - cleaning up video player")
                appModel.currentScene = nil
                // Cancel any pending hide task when view disappears
                hideControlsTask?.cancel()
                
                // Check if we're in shuffle mode - if so, let navigation handle cleanup
                let isMarkerShuffle = UserDefaults.standard.bool(forKey: "isMarkerShuffleContext")
                let isTagShuffle = UserDefaults.standard.bool(forKey: "isTagSceneShuffleContext")
                
                // Only clean up video player for non-shuffle navigation
                if !isMarkerShuffle && !isTagShuffle {
                    if let player = VideoPlayerRegistry.shared.currentPlayer {
                        print("🔇 Disposing of video player on view disappear (non-shuffle)")
                        player.pause()
                        player.replaceCurrentItem(with: nil)
                    }
                    VideoPlayerRegistry.shared.currentPlayer = nil
                    VideoPlayerRegistry.shared.playerViewController = nil
                } else {
                    print("🎲 Skipping video player cleanup - in shuffle mode")
                }
            }
            // Add emergency exit gesture at bottom of screen
            .gesture(
                TapGesture(count: 2)
                    .onEnded { _ in
                        print("👋 Emergency exit gesture detected")
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        
                        // Force dismiss and navigation cleanup
                        dismiss()
                        appModel.forceCloseVideo()
                        
                        // Clear the video player
                        VideoPlayerRegistry.shared.currentPlayer?.pause()
                        VideoPlayerRegistry.shared.currentPlayer = nil
                        VideoPlayerRegistry.shared.playerViewController = nil
                        
                        // Pop navigation if possible
                        if !appModel.navigationPath.isEmpty {
                            appModel.navigationPath.removeLast()
                        }
                    }
            )
        }
    }
    
    // Function to hide controls after a delay
    private func scheduleControlsHide() async {
        // Cancel any existing hide task
        hideControlsTask?.cancel()

        // Create a new task to hide controls after delay
        hideControlsTask = Task {
            do {
                // Wait 5 seconds before hiding controls
                try await Task.sleep(nanoseconds: 5_000_000_000)

                // Check if task was cancelled
                if !Task.isCancelled {
                    // Add a small delay for animation
                    try await Task.sleep(nanoseconds: UInt64(0.3 * 1_000_000_000))

                    // Check again if task was cancelled
                    if !Task.isCancelled {
                        // Update UI on main thread
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showControls = false
                            }
                        }
                    }
                }
            } catch {
                // Task was cancelled, do nothing
            }
        }
    }
    
    private func handlePureRandomVideo() {
        withAnimation(.easeOut(duration: 0.2)) {
            showControls = false
        }
        
        playPureRandomVideo()
    }
    
    private func handlePerformerRandomVideo() {
        withAnimation(.easeOut(duration: 0.2)) {
            showControls = false
        }
        
        playPerformerRandomVideo()
    }
    
    private func handleRandomVideo() {
        withAnimation(.easeOut(duration: 0.2)) {
            showControls = false
        }
        
        playNextScene()
    }

    // Helper to get the correct stream URL with HLS format when available
    private func getStreamURL() -> URL {
        let sceneId = currentScene.id
        
        // First check if we have a saved direct HLS URL format
        if let savedHlsUrlString = UserDefaults.standard.string(forKey: "scene_\(sceneId)_hlsURL"),
           let savedHlsUrl = URL(string: savedHlsUrlString) {
            print("📱 Using saved HLS URL format: \(savedHlsUrlString)")
            // Force update effectiveStartTime if it's included in the URL
            if savedHlsUrlString.contains("t=") {
                if let tRange = savedHlsUrlString.range(of: "t=\\d+", options: .regularExpression),
                   let tValue = Int(savedHlsUrlString[tRange].replacingOccurrences(of: "t=", with: "")) {
                    print("📱 Extracted timestamp from URL: \(tValue)")
                    // Only update if not already set
                    if effectiveStartTime == nil {
                        effectiveStartTime = Double(tValue)
                        print("📱 Updated effectiveStartTime to \(tValue) from URL")
                    }
                }
            }
            return savedHlsUrl
        }
        
        // If no saved URL and we have a start time, construct a proper HLS URL
        if let startTime = effectiveStartTime {
            let apiKey = appModel.apiKey
            let baseServerURL = appModel.serverAddress.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let markerSeconds = Int(startTime)
            let currentTimestamp = Int(Date().timeIntervalSince1970)
            
            // Format exactly like the example
            let hlsStreamURL = "\(baseServerURL)/scene/\(sceneId)/stream.m3u8?apikey=\(apiKey)&resolution=ORIGINAL&t=\(markerSeconds)&_ts=\(currentTimestamp)"
            print("🎬 Constructing HLS URL on-demand: \(hlsStreamURL)")
            
            // Save for future use
            UserDefaults.standard.set(hlsStreamURL, forKey: "scene_\(sceneId)_hlsURL")
            
            if let url = URL(string: hlsStreamURL) {
                return url
            }
        }
        
        // Otherwise use the default URL
        return URL(string: currentScene.paths.stream)!
    }
}

// MARK: - Video Controls
extension VideoPlayerView {
    /// Seeks the video forward or backward by the specified number of seconds
    private func seekVideo(by seconds: Double) {
        // Get the current player
        guard let player = getCurrentPlayer() else {
            print("⚠️ Cannot seek - player not found")
            return
        }

        print("⏱ Seeking video by \(seconds) seconds")

        // Get current time
        guard let currentItem = player.currentItem else {
            print("⚠️ Cannot seek - no current item")
            return
        }

        let currentTime = currentItem.currentTime()
        let targetTime = CMTimeAdd(currentTime, CMTime(seconds: seconds, preferredTimescale: 1000))

        // Make sure we don't seek past beginning or end
        let duration = currentItem.duration
        let zeroTime = CMTime.zero

        // Only apply limits if we have valid duration
        if duration.isValid && !duration.seconds.isNaN {
            if targetTime.seconds < 0 {
                // Don't seek before beginning
                player.seek(to: zeroTime, toleranceBefore: .zero, toleranceAfter: .zero)
                print("⏱ Seeking to beginning of video")
                return
            } else if targetTime.seconds > duration.seconds {
                // Don't seek past end
                player.seek(to: duration, toleranceBefore: .zero, toleranceAfter: .zero)
                print("⏱ Seeking to end of video")
                return
            }
        }

        // Perform the normal seek
        print("⏱ Seeking to \(targetTime.seconds) seconds")
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { success in
            if success {
                print("✅ Successfully seeked by \(seconds) seconds")

                // Provide haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()

                // Make sure playback continues
                if player.timeControlStatus != .playing {
                    player.play()
                }
            } else {
                print("❌ Seek operation failed")
            }
        }
    }

    /// Plays a random scene from the media library directly in the current player
    private func playPureRandomVideo() {
        Task {
            print("🔄 Starting random video selection with female performer preference")
            
            // Fetch a random scene with female performers using direct GraphQL query
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
                "query": "query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) { findScenes(filter: $filter, scene_filter: $scene_filter) { count scenes { id title details paths { screenshot preview stream } files { size duration video_codec width height } performers { id name gender scene_count } tags { id name } rating100 } } }"
            }
            """
            
            do {
                print("🔄 Executing GraphQL query for female performer scenes")
                let data = try await appModel.api.executeGraphQLQuery(query)
                
                struct FindScenesResponse: Decodable {
                    struct Data: Decodable {
                        struct FindScenes: Decodable {
                            let count: Int
                            let scenes: [StashScene]
                        }
                        let findScenes: FindScenes
                    }
                    let data: Data
                }
                
                let response = try JSONDecoder().decode(FindScenesResponse.self, from: data)
                let femaleScenes = response.data.findScenes.scenes
                
                print("🔄 Found \(femaleScenes.count) scenes with female performers")
                
                // The API should filter out VR tags automatically, but let's double-check
                let filteredScenes = femaleScenes.filter { scene in
                    // Filter out VR scenes
                    !scene.tags.contains { tag in
                        tag.name.lowercased() == "vr"
                    }
                }
                
                print("🔄 Additional VR scene check: \(femaleScenes.count - filteredScenes.count) VR scenes would be removed")
                
                if let randomScene = filteredScenes.randomElement() {
                    print("✅ Selected random scene with female performer: \(randomScene.title ?? "Untitled")")
                    
                    // Update the current scene reference
                    await MainActor.run {
                        print("🔄 Updating current scene reference")
                        currentScene = randomScene
                        appModel.currentScene = randomScene
                        
                        // When shuffling to a new scene, update the original performer to first female performer
                        // But ONLY if we don't already have an original performer set
                        if originalPerformer == nil {
                            if let femalePerformer = randomScene.performers.first(where: { $0.gender == "FEMALE" }) {
                                print("🔄 Setting original performer to female: \(femalePerformer.name) (ID: \(femalePerformer.id))")
                                originalPerformer = femalePerformer
                            } else if let anyPerformer = randomScene.performers.first {
                                print("🔄 No female performer found, using first performer: \(anyPerformer.name)")
                                originalPerformer = anyPerformer
                            } else {
                                print("⚠️ No performers in new scene, clearing original performer")
                                originalPerformer = nil
                            }
                        } else {
                            print("🔄 Keeping original performer set: \(originalPerformer!.name)")
                        }
                    }
                    
                    // Get the player from the current view controller
                    if let player = getCurrentPlayer() {
                        print("✅ Got player reference, preparing to play new content")
                        
                        // Create a new player item for the random scene using HLS streaming
                        let directURL = URL(string: randomScene.paths.stream)!
                        let hlsURL = VideoPlayerUtility.getHLSStreamURL(from: directURL) ?? directURL
                        print("🔄 Created HLS URL for random scene: \(hlsURL.absoluteString)")
                        let playerItem = AVPlayerItem(url: hlsURL)
                        
                        print("🔄 Creating new player item with URL: \(hlsURL.absoluteString)")
                        
                        // Replace the current item in the player
                        player.replaceCurrentItem(with: playerItem)
                        player.play()
                        
                        print("▶️ Started playing random scene: \(randomScene.title ?? "Untitled")")
                        
                        // Add observer for playback progress
                        let interval = CMTime(seconds: 5, preferredTimescale: 1)
                        player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                            let seconds = CMTimeGetSeconds(time)
                            if seconds > 0 {
                                UserDefaults.standard.setVideoProgress(seconds, for: randomScene.id)
                            }
                        }
                        
                        // Reset the controls visibility
                        await MainActor.run {
                            showControls = true
                            Task {
                                await scheduleControlsHide()
                            }
                        }
                    } else {
                        print("⚠️ Failed to get player reference")
                    }
                } else {
                    print("⚠️ No female performer scenes available, falling back to any scene")
                    
                    // Fallback to any scene if no female performer scenes were found
                    await fallbackToAnyScene()
                }
            } catch {
                print("⚠️ Error fetching female performer scenes: \(error.localizedDescription)")
                
                // Fallback to any scene if query failed
                await fallbackToAnyScene()
            }
        }
    }
    private func navigateToNextScene() {
        // Load state flags from UserDefaults (to handle view recreations)
        if !isRandomJumpMode {
            isRandomJumpMode = UserDefaults.standard.bool(forKey: "isRandomJumpMode")
        }
        if !isMarkerShuffleMode {
            isMarkerShuffleMode = UserDefaults.standard.bool(forKey: "isMarkerShuffleMode")
        }
        
        print("▶️ Starting next scene navigation - Modes: \(isRandomJumpMode ? "RANDOM JUMP" : "") \(isMarkerShuffleMode ? "MARKER SHUFFLE" : "") \(!isRandomJumpMode && !isMarkerShuffleMode ? "SEQUENTIAL" : "")")
        
        // Check if we're currently viewing a marker
        let isMarkerContext = currentMarker != nil || effectiveStartTime != nil
        print("📊 Current context: \(isMarkerContext ? "MARKER" : "REGULAR SCENE")")
        
        // If we're in tag scene shuffle mode, use the tag shuffle system
        if appModel.isTagSceneShuffleMode {
            print("🏷️ In tag scene shuffle mode")
            print("🏷️ Queue size: \(appModel.tagSceneShuffleQueue.count)")
            print("🏷️ Current index: \(appModel.currentTagShuffleIndex)")
            
            if !appModel.tagSceneShuffleQueue.isEmpty {
                print("🏷️ ✅ Using tag scene shuffle queue - going to next scene")
                appModel.shuffleToNextTagScene()
                return
            } else {
                print("🏷️ ❌ Tag scene shuffle queue empty")
            }
        }
        
        // If we're in marker shuffle mode, use the NEW shuffle queue system
        if isMarkerShuffleMode || appModel.isMarkerShuffleMode {
            print("🎲 In marker shuffle mode - using NEW queue system")
            print("🎲 Queue size: \(appModel.markerShuffleQueue.count)")
            print("🎲 Current index: \(appModel.currentShuffleIndex)")
            print("🎲 appModel.isMarkerShuffleMode: \(appModel.isMarkerShuffleMode)")
            
            // If we have a shuffle queue, use it
            if !appModel.markerShuffleQueue.isEmpty {
                print("🎲 ✅ Using AppModel shuffle queue - going to next marker")
                appModel.shuffleToNextMarker()
                return
            } else {
                print("🎲 ❌ AppModel shuffle queue empty - falling back to old system")
                // Fallback to old system if queue is empty
                if let currentMarker = currentMarker {
                    handleMarkerShuffle()
                    return
                } 
                // If we don't have a current marker but we're in a search context, try to find markers
                else if let savedQuery = UserDefaults.standard.string(forKey: "lastMarkerSearchQuery"), !savedQuery.isEmpty {
                    print("🔍 Using saved search query for marker shuffle: '\(savedQuery)'")
                    Task {
                        await shuffleToRandomMarkerFromSearch(query: savedQuery)
                    }
                    return
                }
            }
        }
        
        // Add more aggressive logging to debug
        print("📊 navigateToNextScene - current marker: \(String(describing: currentMarker))")
        print("📊 navigateToNextScene - appModel.currentMarker: \(String(describing: appModel.currentMarker))")
        print("📊 navigateToNextScene - effectiveStartTime: \(String(describing: effectiveStartTime))")
        print("📊 navigateToNextScene - isRandomJumpMode: \(isRandomJumpMode)")
        print("📊 navigateToNextScene - isMarkerShuffleMode: \(isMarkerShuffleMode)")
        
        withAnimation(.easeOut(duration: 0.2)) {
            showControls = false
        }
        
        // Get scenes from the app model - these represent the current context
        // (could be from a search, performer, tag, etc.)
        let contextScenes = appModel.api.scenes
        
        // Get current index in the context's scene array
        let currentIndex = contextScenes.firstIndex(of: currentScene) ?? -1
        print("📊 Current scene index: \(currentIndex) out of \(contextScenes.count)")
        
        // If current scene is in the list and there's a next one, go to it
        if currentIndex >= 0 && currentIndex < contextScenes.count - 1 {
            // Get the next scene
            let nextScene = contextScenes[currentIndex + 1]
            print("🎬 Navigating to next scene: \(nextScene.title ?? "Untitled")")
            
            // Update current scene reference
            currentScene = nextScene
            appModel.currentScene = nextScene
            
            if isRandomJumpMode {
                print("🎲 Continuing in RANDOM JUMP mode - will perform random jump in the next scene")
                
                // Play the scene first
                playScene(nextScene)
                
                // Then perform a random jump within that scene
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if let player = self.getCurrentPlayer() {
                        // Get current duration to calculate a random position
                        guard let currentItem = player.currentItem else { return }
                        
                        // Define the check duration function as a recursive function
                        func checkDuration() {
                            let duration = currentItem.duration.seconds
                            if duration.isFinite && duration > 10 {
                                // Generate a random position (10% to 90% of the video)
                                let minPosition = max(5, duration * 0.1)
                                let maxPosition = min(duration - 10, duration * 0.9)
                                let randomPosition = Double.random(in: minPosition...maxPosition)
                                
                                print("🎲 Random jumping to \(Int(randomPosition)) seconds in next scene")
                                
                                // Set position and play
                                let time = CMTime(seconds: randomPosition, preferredTimescale: 1000)
                                player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                                player.play()
                            } else {
                                // Try again after a delay if duration isn't ready
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    checkDuration()
                                }
                            }
                        }
                        
                        // Start the duration check
                        checkDuration()
                    }
                }
            } else {
                // Normal sequential playback
                playScene(nextScene)
            }
        } else {
            // We're at the end of the current context's list
            print("📊 Reached the end of the current context list")
            
            // Check if we're in a marker context
            if isMarkerContext {
                print("🏷️ In marker context, attempting to find next marker")
                
                // Make sure currentMarker is set in appModel if it's only set locally
                if appModel.currentMarker == nil && currentMarker != nil {
                    print("🔄 Syncing current marker to appModel")
                    appModel.currentMarker = currentMarker
                }
                
                // If we have effectiveStartTime but no marker, try to create one
                if appModel.currentMarker == nil && effectiveStartTime != nil {
                    print("🔄 Creating temporary marker from effectiveStartTime")
                    
                    // Try to get the primary tag from UserDefaults
                    let sceneId = currentScene.id
                    let isMarkerNavigation = UserDefaults.standard.bool(forKey: "scene_\(sceneId)_isMarkerNavigation")
                    
                    // Use TagAPI to get a default tag
                    Task {
                        do {
                            // Get default tag for fallback (first tag in system)
                            let tagsQuery = """
                            {
                                "operationName": "FindTags",
                                "variables": {
                                    "filter": {
                                        "page": 1,
                                        "per_page": 1
                                    }
                                },
                                "query": "query FindTags($filter: FindFilterType) { findTags(filter: $filter) { count tags { id name } } }"
                            }
                            """
                            
                            let tagData = try await appModel.api.executeGraphQLQuery(tagsQuery)
                            
                            struct TagsResponseData: Decodable {
                                let data: TagData
                                
                                struct TagData: Decodable {
                                    let findTags: TagsPayload
                                    
                                    struct TagsPayload: Decodable {
                                        let count: Int
                                        let tags: [SceneMarker.Tag]
                                    }
                                }
                            }
                            
                            let tagResponse = try JSONDecoder().decode(TagsResponseData.self, from: tagData)
                            
                            if let firstTag = tagResponse.data.findTags.tags.first {
                                print("✅ Found default tag: \(firstTag.name)")
                                
                                // Create temporary marker
                                let tempMarker = SceneMarker(
                                    id: UUID().uuidString,
                                    title: "Temporary marker at \(Int(effectiveStartTime!))",
                                    seconds: Float(effectiveStartTime!),
                                    end_seconds: effectiveEndTime != nil ? Float(effectiveEndTime!) : nil,
                                    stream: "",
                                    preview: "",
                                    screenshot: "",
                                    scene: SceneMarker.MarkerScene(id: currentScene.id),
                                    primary_tag: firstTag,
                                    tags: []
                                )
                                
                                // Set as current marker
                                currentMarker = tempMarker
                                appModel.currentMarker = tempMarker
                                
                                // Now find next marker
                                let foundNextMarker = await findNextMarkerInSameTag()
                                if !foundNextMarker {
                                    print("⚠️ No next marker available with temp marker, staying on current scene")
                                    await MainActor.run {
                                        showControls = true
                                        Task {
                                            await scheduleControlsHide()
                                        }
                                    }
                                }
                            }
                        } catch {
                            print("❌ Error fetching tags: \(error)")
                        }
                    }
                } else {
                    // Use the regular find next marker approach
                    Task {
                        let foundNextMarker = await findNextMarkerInSameTag()
                        if !foundNextMarker {
                            print("⚠️ No next marker available, staying on current scene")
                            // Return to UI controls, don't switch scenes
                            await MainActor.run {
                                showControls = true
                                Task {
                                    await scheduleControlsHide()
                                }
                            }
                        }
                    }
                }
            } else {
                print("⚠️ At end of context list, looping back to beginning")
                // Loop back to the first item in the list if we have scenes
                if !contextScenes.isEmpty {
                    let firstScene = contextScenes[0]
                    print("🔄 Looping back to first scene: \(firstScene.title ?? "Untitled")")
                    currentScene = firstScene
                    appModel.currentScene = firstScene
                    
                    if isRandomJumpMode {
                        print("🎲 Continuing in RANDOM JUMP mode - will perform random jump in the looped scene")
                        
                        // Play the scene first
                        playScene(firstScene)
                        
                        // Then perform a random jump within that scene
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            if let player = self.getCurrentPlayer() {
                                // Get current duration to calculate a random position
                                guard let currentItem = player.currentItem else { return }
                                
                                // Define the check duration function as a recursive function
                                func checkDuration() {
                                    let duration = currentItem.duration.seconds
                                    if duration.isFinite && duration > 10 {
                                        // Generate a random position (10% to 90% of the video)
                                        let minPosition = max(5, duration * 0.1)
                                        let maxPosition = min(duration - 10, duration * 0.9)
                                        let randomPosition = Double.random(in: minPosition...maxPosition)
                                        
                                        print("🎲 Random jumping to \(Int(randomPosition)) seconds in looped scene")
                                        
                                        // Set position and play
                                        let time = CMTime(seconds: randomPosition, preferredTimescale: 1000)
                                        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                                        player.play()
                                    } else {
                                        // Try again after a delay if duration isn't ready
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            checkDuration()
                                        }
                                    }
                                }
                                
                                // Start the duration check
                                checkDuration()
                            }
                        }
                    } else {
                        // Normal sequential playback
                        playScene(firstScene)
                    }
                }
            }
        }
    }
    
    /// Fallback method to fetch any scene when female performer filtering fails
    private func fallbackToAnyScene() async {
        print("🔄 Falling back to fetch any scene")
        
        // Fetch any scene using the API's random sort
        await appModel.api.fetchScenes(page: 1, sort: "random", direction: "DESC")
        
        // Filter out VR scenes
        let filteredScenes = appModel.api.scenes.filter { scene in
            !scene.tags.contains { tag in
                tag.name.lowercased() == "vr"
            }
        }
        
        if let randomScene = filteredScenes.randomElement() {
            print("✅ Selected fallback random scene: \(randomScene.title ?? "Untitled")")
            
            // Update the current scene reference
            await MainActor.run {
                currentScene = randomScene
                appModel.currentScene = randomScene
                
                // When shuffling to a new scene, update the original performer
                if let newPerformer = randomScene.performers.first {
                    print("🔄 Updating original performer to: \(newPerformer.name)")
                    originalPerformer = newPerformer
                }
            }
            
            // Get the player and play the scene
            if let player = getCurrentPlayer() {
                let directURL = URL(string: randomScene.paths.stream)!
                let hlsURL = VideoPlayerUtility.getHLSStreamURL(from: directURL) ?? directURL
                let playerItem = AVPlayerItem(url: hlsURL)
                
                player.replaceCurrentItem(with: playerItem)
                player.play()
                
                // Add observer for playback progress
                let interval = CMTime(seconds: 5, preferredTimescale: 1)
                player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                    let seconds = CMTimeGetSeconds(time)
                    if seconds > 0 {
                        UserDefaults.standard.setVideoProgress(seconds, for: randomScene.id)
                    }
                }
                
                // Reset controls visibility
                await MainActor.run {
                    showControls = true
                    Task {
                        await scheduleControlsHide()
                    }
                }
            }
        } else {
            print("⚠️ No scenes available at all")
        }
    }
    
    /// Plays a different scene featuring the same performer from current scene
    private func playPerformerRandomVideo() {
        print("🎯 PERFORMER BUTTON: Starting performer random video function")

        print("🎯 PERFORMER BUTTON: Current scene: \(currentScene.title ?? "Untitled") (ID: \(currentScene.id))")
        
        // Determine which performer to use
        var selectedPerformer: StashScene.Performer?
        
        // First try to use the original performer if available
        if let originalPerf = originalPerformer {
            print("🎯 PERFORMER BUTTON: Original performer is: \(originalPerf.name) (ID: \(originalPerf.id))")
            
            // Check if the original performer is in the current scene
            if currentScene.performers.contains(where: { $0.id == originalPerf.id }) {
                // If yes, use the original performer
                selectedPerformer = originalPerf
                print("🎯 PERFORMER BUTTON: Using original performer (found in current scene)")
            } else {
                // If original performer isn't in current scene, use the first performer from current scene
                selectedPerformer = currentScene.performers.first
                print("🎯 PERFORMER BUTTON: Original performer not in current scene, using first performer from current scene")
                
                // Update the originalPerformer to match this new performer
                originalPerformer = selectedPerformer
            }
        } else {
            // If no original performer is set, use the first performer from the current scene
            selectedPerformer = currentScene.performers.first
            print("🎯 PERFORMER BUTTON: No original performer stored, using first performer from current scene")
            
            // Set this as the original performer
            originalPerformer = selectedPerformer
        }

        // Make sure we have a performer to work with
        guard let selectedPerformer = selectedPerformer else {
            print("⚠️ PERFORMER BUTTON: No performers in the current scene, cannot shuffle")
            
            // Just play a random position in current scene instead
            playNextScene()
            return
        }

        print("🎯 PERFORMER BUTTON: Selected performer: \(selectedPerformer.name) (ID: \(selectedPerformer.id))")
        print("🎯 PERFORMER BUTTON: Current scene ID: \(currentScene.id), title: \(currentScene.title ?? "Untitled")")

        // Start a task to find and play another scene with this performer
        Task {
            print("🎯 PERFORMER BUTTON: Fetching scenes with performer ID: \(selectedPerformer.id)")

            // Use direct API method to find scenes with this performer
            // Modified to include gender filter for female performers
            let query = """
            {
                "operationName": "FindScenes",
                "variables": {
                    "filter": {
                        "page": 1,
                        "per_page": 100,
                        "sort": "date",
                        "direction": "DESC"
                    },
                    "scene_filter": {
                        "performers": {
                            "value": ["\(selectedPerformer.id)"],
                            "modifier": "INCLUDES"
                        }
                    }
                },
                "query": "query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) { findScenes(filter: $filter, scene_filter: $scene_filter) { count scenes { id title details paths { screenshot preview stream } files { size duration video_codec width height } performers { id name gender scene_count } tags { id name } rating100 } } }"
            }
            """

            do {
                print("🎯 PERFORMER BUTTON: Executing GraphQL query for performer scenes")
                let data = try await appModel.api.executeGraphQLQuery(query)

                struct FindScenesResponse: Decodable {
                    struct Data: Decodable {
                        struct FindScenes: Decodable {
                            let count: Int
                            let scenes: [StashScene]
                        }
                        let findScenes: FindScenes
                    }
                    let data: Data
                }

                let response = try JSONDecoder().decode(FindScenesResponse.self, from: data)
                let performerScenes = response.data.findScenes.scenes

                print("🎯 PERFORMER BUTTON: Found \(performerScenes.count) scenes with performer \(selectedPerformer.name)")

                // Filter out the current scene and VR scenes (API should already filter VR, but double-check)
                let otherScenes = performerScenes.filter { scene in
                    // Filter out the current scene
                    if scene.id == currentScene.id {
                        return false
                    }

                    // Double-check for VR tag filtering
                    if scene.tags.contains(where: { $0.name.lowercased() == "vr" }) {
                        print("⚠️ PERFORMER BUTTON: Found VR scene despite filtering: \(scene.id)")
                        return false
                    }

                    return true
                }

                print("🎯 PERFORMER BUTTON: Current scene and VR filtering: \(performerScenes.count - otherScenes.count) scenes excluded")
                print("🎯 PERFORMER BUTTON: After filtering current scene, found \(otherScenes.count) other scenes")

                // Get a random scene from this performer's scenes
                if let randomScene = otherScenes.randomElement() ?? (performerScenes.count > 0 ? performerScenes[0] : nil) {
                    print("🎯 PERFORMER BUTTON: Selected scene: \(randomScene.title ?? "Untitled") (ID: \(randomScene.id))")

                    // Update the current scene reference
                    await MainActor.run {
                        print("🎯 PERFORMER BUTTON: Updating current scene reference")
                        currentScene = randomScene
                        appModel.currentScene = randomScene
                    }

                    // Get the player from the current view controller
                    if let player = getCurrentPlayer() {
                        print("🎯 PERFORMER BUTTON: Got player reference, preparing to play new content")

                        // Create a new player item for the random scene using HLS streaming
                        let directURL = URL(string: randomScene.paths.stream)!
                        let hlsURL = VideoPlayerUtility.getHLSStreamURL(from: directURL) ?? directURL
                        print("🎯 PERFORMER BUTTON: Created HLS URL: \(hlsURL.absoluteString)")
                        let playerItem = AVPlayerItem(url: hlsURL)

                        print("🎯 PERFORMER BUTTON: Creating new player item with URL: \(hlsURL.absoluteString)")

                        // Replace the current item in the player
                        player.replaceCurrentItem(with: playerItem)
                        player.play()

                        print("🎯 PERFORMER BUTTON: Started playing random scene with performer: \(selectedPerformer.name)")

                        // Generate a random position to seek to (between 20% and 80% of video)
                        // Use a longer delay to make sure the video loads properly
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            print("🎯 PERFORMER BUTTON: First delayed seek timer fired")

                            guard let player = getCurrentPlayer(),
                                  let currentItem = player.currentItem else {
                                print("⚠️ PERFORMER BUTTON: Player or item is nil in delayed seek")
                                return
                            }

                            print("🎯 PERFORMER BUTTON: Current item status: \(currentItem.status.rawValue)")

                            // Helper function to handle the actual seek
                            func attemptSeek(with player: AVPlayer, item: AVPlayerItem, isRetry: Bool = false) {
                                // Use VideoPlayerUtility to handle the seek with full fallback logic
                                // This will work even if the player isn't fully loaded
                                let success = VideoPlayerUtility.jumpToRandomPosition(in: player)
                                if success {
                                    print("✅ PERFORMER BUTTON: Successfully jumped to random position using utility")
                                } else if !isRetry {
                                    print("⚠️ PERFORMER BUTTON: Failed to jump, will retry in 2 seconds")

                                    // Last resort retry
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        guard let player = getCurrentPlayer(),
                                              let currentItem = player.currentItem else { return }

                                        print("🎯 PERFORMER BUTTON: Final retry for seeking")
                                        attemptSeek(with: player, item: currentItem, isRetry: true)
                                    }
                                }
                            }

                            // If the player is ready, use its duration
                            if currentItem.status == .readyToPlay {
                                let duration = currentItem.duration.seconds
                                if !duration.isNaN && duration.isFinite && duration > 0 {
                                    print("🎯 PERFORMER BUTTON: Player ready with duration: \(duration) seconds")
                                    attemptSeek(with: player, item: currentItem)
                                } else {
                                    print("⚠️ PERFORMER BUTTON: Player ready but duration not valid: \(duration), will still attempt seek")
                                    attemptSeek(with: player, item: currentItem)
                                }
                            } else {
                                print("⚠️ PERFORMER BUTTON: Player not ready for seeking, status: \(currentItem.status.rawValue)")
                                print("🎯 PERFORMER BUTTON: Will retry after additional delay")

                                // Try again after a slightly longer delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    print("🎯 PERFORMER BUTTON: Retry delayed seek timer fired")
                                    guard let player = getCurrentPlayer(),
                                          let currentItem = player.currentItem else { return }

                                    print("🎯 PERFORMER BUTTON: Retry - current item status: \(currentItem.status.rawValue)")
                                    attemptSeek(with: player, item: currentItem)
                                }
                            }
                        }

                        // Add observer for playback progress
                        let interval = CMTime(seconds: 5, preferredTimescale: 1)
                        player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                            let seconds = CMTimeGetSeconds(time)
                            if seconds > 0 {
                                UserDefaults.standard.setVideoProgress(seconds, for: randomScene.id)
                            }
                        }

                        // Provide haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()

                        // Reset the controls visibility
                        await MainActor.run {
                            showControls = true
                            Task {
                                await scheduleControlsHide()
                            }
                        }
                    } else {
                        print("⚠️ PERFORMER BUTTON: Failed to get player reference")
                    }
                } else {
                    print("⚠️ PERFORMER BUTTON: No other scenes found with performer \(selectedPerformer.name), trying broader search for the same performer")
                    
                    // First try a broader search for the same performer (different query parameters)
                    let fallbackQuery = """
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
                                "performers": {
                                    "value": ["\(selectedPerformer.id)"],
                                    "modifier": "INCLUDES"
                                }
                            }
                        },
                        "query": "query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) { findScenes(filter: $filter, scene_filter: $scene_filter) { count scenes { id title details paths { screenshot preview stream } files { size duration video_codec width height } performers { id name gender scene_count } tags { id name } rating100 } } }"
                    }
                    """
                    
                    do {
                        print("🎯 PERFORMER BUTTON: Executing broader fallback query for same performer")
                        let fallbackData = try await appModel.api.executeGraphQLQuery(fallbackQuery)
                        
                        let fallbackResponse = try JSONDecoder().decode(FindScenesResponse.self, from: fallbackData)
                        let performerScenes = fallbackResponse.data.findScenes.scenes
                        
                        print("🎯 PERFORMER BUTTON: Found \(performerScenes.count) scenes with performer using broader query")
                        
                        // Filter out the current scene and VR scenes
                        let otherPerformerScenes = performerScenes.filter { scene in
                            // Filter out the current scene
                            if scene.id == currentScene.id {
                                return false
                            }
                            
                            // Double-check for VR tag filtering
                            if scene.tags.contains(where: { $0.name.lowercased() == "vr" }) {
                                return false
                            }
                            
                            return true
                        }
                        
                        if let randomScene = otherPerformerScenes.randomElement() {
                            print("🎯 PERFORMER BUTTON: Selected scene with same performer: \(randomScene.title ?? "Untitled") (ID: \(randomScene.id))")
                            
                            // Update the current scene reference
                            await MainActor.run {
                                print("🎯 PERFORMER BUTTON: Updating current scene reference")
                                currentScene = randomScene
                                appModel.currentScene = randomScene
                                
                                // IMPORTANT: Keep the original performer reference unchanged
                                print("🎯 PERFORMER BUTTON (FALLBACK): Keeping original performer: \(selectedPerformer.name)")
                            }
                            
                            // Play the scene using same method as above
                            if let player = getCurrentPlayer() {
                                let directURL = URL(string: randomScene.paths.stream)!
                                let hlsURL = VideoPlayerUtility.getHLSStreamURL(from: directURL) ?? directURL
                                let playerItem = AVPlayerItem(url: hlsURL)
                                
                                player.replaceCurrentItem(with: playerItem)
                                player.play()
                                
                                // Add same delayed seeking as the main function
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    VideoPlayerUtility.jumpToRandomPosition(in: player)
                                }
                                
                                // Provide haptic feedback
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                                
                                // Reset the controls visibility
                                await MainActor.run {
                                    showControls = true
                                    Task {
                                        await scheduleControlsHide()
                                    }
                                }
                            }
                        } else {
                            // If no other scenes with this performer exist at all, just keep playing current scene
                            print("⚠️ PERFORMER BUTTON: No scenes at all found with performer \(selectedPerformer.name), staying with current scene")
                            
                            // Jump to a random position in the current scene instead
                            playNextScene()
                            
                            // Show a hint to the user that no other scenes found
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.warning)
                        }
                    } catch {
                        print("⚠️ PERFORMER BUTTON: Error fetching scenes: \(error.localizedDescription)")
                        
                        // Jump to a random position in the current scene instead
                        playNextScene()
                    }
                }
            } catch {
                print("⚠️ PERFORMER BUTTON: Error fetching performer scenes: \(error)")
                print("⚠️ PERFORMER BUTTON: Falling back to regular API method")

                // Fall back to regular API method
                await appModel.api.fetchPerformerScenes(performerId: selectedPerformer.id)

                // Continue with the same flow as before - filter out current scene and VR scenes
                let otherScenes = appModel.api.scenes.filter { scene in
                    // Filter out the current scene
                    if scene.id == currentScene.id {
                        return false
                    }

                    // Double-check for VR tag filtering (API should already filter it)
                    if scene.tags.contains(where: { $0.name.lowercased() == "vr" }) {
                        print("⚠️ PERFORMER BUTTON: Found VR scene despite API filtering: \(scene.id)")
                        return false
                    }

                    return true
                }
                print("🎯 PERFORMER BUTTON: Found \(otherScenes.count) scenes with performer using fallback method")

                if let randomScene = otherScenes.randomElement() ?? appModel.api.scenes.first {
                    // Update scene and play it (same implementation as above)
                    await MainActor.run {
                        currentScene = randomScene
                        appModel.currentScene = randomScene
                    }

                    if let player = getCurrentPlayer() {
                        let directURL = URL(string: randomScene.paths.stream)!
                        let hlsURL = VideoPlayerUtility.getHLSStreamURL(from: directURL) ?? directURL
                        print("🎯 PERFORMER BUTTON (FALLBACK): Created HLS URL: \(hlsURL.absoluteString)")
                        let playerItem = AVPlayerItem(url: hlsURL)
                        player.replaceCurrentItem(with: playerItem)
                        player.play()

                        // Add delayed seek to random position
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            print("🎯 PERFORMER BUTTON (FALLBACK): Attempting to seek to random position")
                            if let player = getCurrentPlayer() {
                                // Use the improved utility method which handles all edge cases
                                let success = VideoPlayerUtility.jumpToRandomPosition(in: player)
                                if success {
                                    print("✅ PERFORMER BUTTON (FALLBACK): Jumped to random position using utility")
                                } else {
                                    print("⚠️ PERFORMER BUTTON (FALLBACK): Failed initial jump, will retry")

                                    // One more try after a delay
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        if let player = getCurrentPlayer() {
                                            VideoPlayerUtility.jumpToRandomPosition(in: player)
                                        }
                                    }
                                }
                            }
                        }

                        // Provide haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()

                        // Reset controls visibility
                        Task {
                            await MainActor.run {
                                showControls = true
                                Task {
                                    await scheduleControlsHide()
                                }
                            }
                        }
                    }
                } else {
                    // If no other scenes with this performer exist, just go to a random spot in current scene
                    print("⚠️ PERFORMER BUTTON: No scenes at all found with performer \(selectedPerformer.name), staying with current scene")
                    
                    // Jump to a random position in the current scene instead
                    playNextScene()
                    
                    // Show a hint to the user that no other scenes found
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.warning)
                }
            }
        }
    }
    
    /// Jumps to a random position in the current video
    private func playNextScene() {
        // Get the current player
        guard let player = getCurrentPlayer() else {
            print("⚠️ Cannot jump to random position - player not found")
            return
        }

        // Check if we have a valid duration to work with
        guard let currentItem = player.currentItem,
              currentItem.status == .readyToPlay,
              currentItem.duration.isValid,
              !currentItem.duration.seconds.isNaN,
              currentItem.duration.seconds > 0 else {
            print("⚠️ Cannot jump to random position - invalid duration")
            return
        }

        let duration = currentItem.duration.seconds
        print("🎲 Current video duration: \(duration) seconds")

        // Current time for logging
        let currentSeconds = currentItem.currentTime().seconds
        print("🎲 Current position: \(currentSeconds) seconds")

        // Calculate a random position between 5 minutes and 90% of the duration
        // Ensure we don't go too close to the beginning or end
        let minPosition = max(300, duration * 0.1) // At least 5 minutes (300 seconds) or 10% in
        let maxPosition = min(duration - 10, duration * 0.9) // At most 90% through the video

        if minPosition >= maxPosition {
            print("⚠️ Video too short for meaningful random jump")
            return
        }

        // Generate random position
        let randomPosition = Double.random(in: minPosition...maxPosition)
        let minutes = Int(randomPosition / 60)
        let seconds = Int(randomPosition) % 60

        print("🎲 Jumping to random position: \(randomPosition) seconds (\(minutes):\(String(format: "%02d", seconds)))")

        // Create time with higher precision timescale
        let time = CMTime(seconds: randomPosition, preferredTimescale: 1000)

        // Set tolerances for more precise seeking
        let toleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 1000)
        let toleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 1000)

        // Perform the seek operation
        print("🎲 Seeking to new position...")
        player.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter) { success in
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
                print("❌ Seek operation failed")
            }
        }
    }
    
    /// Helper method to get the current player
    private func getCurrentPlayer() -> AVPlayer? {
        // First try to get the player from our registry
        if let player = VideoPlayerRegistry.shared.currentPlayer {
            print("▶️ Retrieved player from registry")
            return player
        }

        // Fallback to searching for player in view hierarchy
        if let playerVC = UIApplication.shared.windows.first?.rootViewController?.presentedViewController as? AVPlayerViewController {
            // Register this player for future use
            VideoPlayerRegistry.shared.currentPlayer = playerVC.player
            VideoPlayerRegistry.shared.playerViewController = playerVC
            print("▶️ Retrieved player from presented view controller")
            return playerVC.player
        }

        // Alternative approach if the above doesn't work
        if let playerVC = findPlayerViewController() {
            // Register this player for future use
            VideoPlayerRegistry.shared.currentPlayer = playerVC.player
            VideoPlayerRegistry.shared.playerViewController = playerVC
            print("▶️ Retrieved player using findPlayerViewController")
            return playerVC.player
        }

        print("⚠️ Failed to find player")
        return nil
    }

    /// Helper method to find the AVPlayerViewController in the view hierarchy
    private func findPlayerViewController() -> AVPlayerViewController? {
        // Try to find the player view controller in the parent hierarchy
        var parentController = UIApplication.shared.windows.first?.rootViewController
        while parentController != nil {
            if let playerVC = parentController as? AVPlayerViewController {
                return playerVC
            }
            if let presentedVC = parentController?.presentedViewController as? AVPlayerViewController {
                return presentedVC
            }
            parentController = parentController?.presentedViewController
        }
        return nil
    }

    /// Helper method to play a random scene
    private func playRandomScene(_ scene: StashScene) {
        print("🎯 Playing random scene: \(scene.title ?? "Untitled") (ID: \(scene.id))")
        
        // Update the current scene reference
        Task {
            await MainActor.run {
                print("🎯 Updating current scene reference")
                currentScene = scene
                appModel.currentScene = scene
                
                // Do NOT update the original performer - keep it intact for performer button
                // This ensures that even after shuffling scenes, the performer button stays with the original performer
            }
            
            // Get the player from the current view controller
            if let player = getCurrentPlayer() {
                let directURL = URL(string: scene.paths.stream)!
                let hlsURL = VideoPlayerUtility.getHLSStreamURL(from: directURL) ?? directURL
                let playerItem = AVPlayerItem(url: hlsURL)
                
                player.replaceCurrentItem(with: playerItem)
                player.play()
                
                // Add delayed seeking to random position
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    VideoPlayerUtility.jumpToRandomPosition(in: player)
                }
                
                // Provide haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                
                // Reset the controls visibility
                await MainActor.run {
                    showControls = true
                    Task {
                        await scheduleControlsHide()
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Functions for Next Scene Navigation
    
    private func findNextMarkerInSameTag() async -> Bool {
        print("🔍 Finding next marker with same tag")
        guard let currentMarker = appModel.currentMarker else {
            print("⚠️ No current marker found in appModel")
            return false
        }
        
        // Get the current primary tag
        let primaryTagId = currentMarker.primary_tag.id
        print("🏷️ Looking for next marker with tag ID: \(primaryTagId)")
        
        do {
            // Use the existing fetchMarkersByTagAllPages method
            let sameTagMarkers = try await appModel.api.fetchMarkersByTagAllPages(tagId: primaryTagId)
            print("✅ Found \(sameTagMarkers.count) markers with the same primary tag")
            
            // Find the current marker's index in this array
            if let currentIndex = sameTagMarkers.firstIndex(where: { $0.id == currentMarker.id }) {
                print("📊 Current marker index: \(currentIndex) out of \(sameTagMarkers.count)")
                
                // If we're not at the end, go to the next marker
                if currentIndex < sameTagMarkers.count - 1 {
                    let nextMarker = sameTagMarkers[currentIndex + 1]
                    print("🎬 Navigating to next marker: \(nextMarker.title)")
                    
                    await MainActor.run {
                        appModel.navigateToMarker(nextMarker)
                    }
                    return true
                } else {
                    // We're at the end, loop back to the first marker
                    print("🔄 At end of markers list, looping back to first")
                    let firstMarker = sameTagMarkers[0]
                    await MainActor.run {
                        appModel.navigateToMarker(firstMarker)
                    }
                    return true
                }
            }
        } catch {
            print("❌ Error finding markers with same tag: \(error)")
        }
        
        return false
    }
    
    private func handleMarkerShuffle() {
        print("🔄 Starting marker shuffle functionality")
        
        // Set marker shuffle mode
        isMarkerShuffleMode = true
        UserDefaults.standard.set(true, forKey: "isMarkerShuffleMode")
        
        // If we have a current marker, shuffle to another marker with same tag
        if let currentMarker = currentMarker {
            Task {
                await findNextMarkerInSameTag()
            }
        } else {
            // No current marker, try to use search query
            if let savedQuery = UserDefaults.standard.string(forKey: "lastMarkerSearchQuery"), !savedQuery.isEmpty {
                print("🔍 Using saved search query for marker shuffle: '\(savedQuery)'")
                Task {
                    await shuffleToRandomMarkerFromSearch(query: savedQuery)
                }
            }
        }
    }
    
    private func shuffleToRandomMarkerFromSearch(query: String) async {
        print("🔄 Starting marker shuffle from search query: '\(query)'")
        
        do {
            // Search for markers
            let markers = try await appModel.api.searchMarkers(query: query)
            
            if !markers.isEmpty {
                // Pick a random marker
                let randomMarker = markers.randomElement()!
                print("🎯 Selected random marker: \(randomMarker.title)")
                
                await MainActor.run {
                    appModel.navigateToMarker(randomMarker)
                }
            } else {
                print("⚠️ No markers found for query: '\(query)'")
            }
        } catch {
            print("❌ Error searching markers: \(error)")
        }
    }
    
    private func playScene(_ scene: StashScene) {
        // Get the player from the current view controller
        guard let player = getCurrentPlayer() else {
            print("⚠️ Cannot play scene - player not found")
            return
        }
        
        // Create URL for the scene
        let directURL = URL(string: scene.paths.stream)!
        let hlsURL = VideoPlayerUtility.getHLSStreamURL(from: directURL) ?? directURL
        
        // Create asset with HTTP headers to ensure proper authorization
        let headers = ["User-Agent": "StashApp/iOS"]
        let asset = AVURLAsset(url: hlsURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let playerItem = AVPlayerItem(asset: asset)
        
        // Replace current item and play
        player.replaceCurrentItem(with: playerItem)
        player.play()
        
        // Reset controls
        Task {
            await MainActor.run {
                showControls = true
                Task {
                    await scheduleControlsHide()
                }
            }
        }
    }
    
}

// MARK: - FullScreenVideoPlayer
struct FullScreenVideoPlayer: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController  // Changed from AVPlayerViewController to UIViewController

    let url: URL
    let startTime: Double?
    let endTime: Double?
    let scenes: [StashScene]
    let currentIndex: Int
    let appModel: AppModel

    // Add coordinator to store persistent reference to player
    class Coordinator: NSObject {
        var player: AVPlayer?
        var observationToken: NSKeyValueObservation?
        var timeObserver: Any?
        var endTimeReached = false
        var timeStatusObserver: NSKeyValueObservation?
        var progressObserver: Any?

        deinit {
            // Clean up resources
            observationToken?.invalidate()
            timeStatusObserver?.invalidate()
            
            // Remove time observer if it exists
            if let timeObserver = timeObserver, let player = player {
                player.removeTimeObserver(timeObserver)
            }
            
            // Remove progress observer if it exists
            if let progressObserver = progressObserver, let player = player {
                player.removeTimeObserver(progressObserver)
            }
            
            player?.pause()
            player = nil
            timeObserver = nil
            progressObserver = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        print("🎬 Creating video player for URL: \(url.absoluteString)")
        
        // Create player with the correct URL
        let finalUrl: URL
        var explicitStartTime: Double? = startTime
        
        // Always check if we can extract the scene ID from the URL to use the saved HLS format
        if let sceneId = extractSceneId(from: url.absoluteString),
           let savedHlsUrlString = UserDefaults.standard.string(forKey: "scene_\(sceneId)_hlsURL"),
           let savedHlsUrl = URL(string: savedHlsUrlString) {
            print("📱 Using saved exact HLS URL format: \(savedHlsUrlString)")
            finalUrl = savedHlsUrl
            
            // Extract timestamp from URL if present
            if let tRange = savedHlsUrlString.range(of: "t=(\\d+)", options: .regularExpression),
               let tValue = Int(savedHlsUrlString[tRange].replacingOccurrences(of: "t=", with: "")) {
                print("📱 Extracted timestamp from URL: \(tValue)")
                
                // Create player with forced seek
                explicitStartTime = Double(tValue)
            }
        } else {
            // If no saved URL, use the provided URL but make sure it's in HLS format with t parameter
            let urlString = url.absoluteString
            
            // Check if this is already an HLS URL
            if urlString.contains("stream.m3u8") {
                // If URL doesn't have the t parameter but has startTime, add it
                if !urlString.contains("&t=") && !urlString.contains("?t=") && startTime != nil {
                    // Add t parameter to the URL
                    var modifiedUrlString = urlString
                    let timeParam = "t=\(Int(startTime!))"
                    if modifiedUrlString.contains("?") {
                        modifiedUrlString += "&\(timeParam)"
                    } else {
                        modifiedUrlString += "?\(timeParam)"
                    }
                    
                    // Add timestamp parameter if missing
                    if !modifiedUrlString.contains("_ts=") {
                        let currentTimestamp = Int(Date().timeIntervalSince1970)
                        modifiedUrlString += "&_ts=\(currentTimestamp)"
                    }
                    
                    print("🔄 Modified URL to include t parameter: \(modifiedUrlString)")
                    
                    if let modifiedUrl = URL(string: modifiedUrlString) {
                        finalUrl = modifiedUrl
                    } else {
                        finalUrl = url
                    }
                } else {
                    finalUrl = url
                    
                    // Extract t parameter if it exists in the URL
                    if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
                       let queryItems = urlComponents.queryItems,
                       let tItem = queryItems.first(where: { $0.name == "t" }),
                       let tValue = tItem.value,
                       let tSeconds = Double(tValue) {
                        print("📱 Extracted t parameter from URL: \(tSeconds)")
                        explicitStartTime = tSeconds
                    }
                }
            } else {
                // Not an HLS URL, convert it
                if let hlsUrl = VideoPlayerUtility.getHLSStreamURL(from: url, isMarkerURL: startTime != nil) {
                    print("🔄 Converted to HLS URL: \(hlsUrl.absoluteString)")
                    finalUrl = hlsUrl
                } else {
                    finalUrl = url
                }
            }
        }
        
        print("🎬 Final URL being used: \(finalUrl.absoluteString)")
        print("⏱ Explicit start time to use: \(String(describing: explicitStartTime))")
        
        // Create asset with HTTP headers if needed (helps with authorization issues)
        let headers = ["User-Agent": "StashApp/iOS"]
        let asset = AVURLAsset(url: finalUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        
        print("🎬 Creating player item with AVURLAsset")
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        let playerVC = AVPlayerViewController()
        playerVC.player = player
        
        // Configure player options
        playerVC.allowsPictureInPicturePlayback = true
        playerVC.showsPlaybackControls = true
        
        // Create our custom wrapper
        let customVC = CustomPlayerViewController(playerVC: playerVC)
        
        // CRITICAL: Force playback to start immediately
        print("▶️ Attempting to force immediate playback")
        player.play()
        
        // Add timeControlStatus observer for debugging
        let timeObserver = player.observe(\.timeControlStatus, options: [.new]) { player, change in
            switch player.timeControlStatus {
            case .playing:
                print("✅ Player status: PLAYING")
            case .paused:
                print("⚠️ Player status: PAUSED")
            case .waitingToPlayAtSpecifiedRate:
                print("⏳ Player status: WAITING TO PLAY - \(player.reasonForWaitingToPlay?.rawValue ?? "Unknown reason")")
            @unknown default:
                print("❓ Player status: UNKNOWN")
            }
        }
        context.coordinator.timeStatusObserver = timeObserver
        
        // If an end time is specified, set it on the player view model
        if let endTime = endTime, let playerViewModel = appModel.playerViewModel as? VideoPlayerViewModel {
            print("⏱ Setting end time on player view model: \(endTime) seconds")
            playerViewModel.endSeconds = endTime
        }
        
        // FORCE INITIAL SEEK if we have an explicit start time
        if let timeToSeek = explicitStartTime, timeToSeek > 0 {
            print("⏱ CRITICAL: Performing immediate seek to \(timeToSeek) seconds")
            let cmTime = CMTime(seconds: timeToSeek, preferredTimescale: 1000)
            player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
            
            // Also register a delayed seek in case the initial one doesn't work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                print("⏱ CRITICAL: Performing delayed seek to \(timeToSeek) seconds")
                let cmTime = CMTime(seconds: timeToSeek, preferredTimescale: 1000)
                player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { success in
                    print("⏱ Delayed seek completed with result: \(success)")
                    player.play()
                }
            }
        }
        
        // Add observer for readyToPlay status
        let token = playerItem.observe(\.status, options: [.new, .old]) { item, change in
            print("🎬 Player item status changed to: \(item.status.rawValue)")
            
            if item.status == .readyToPlay {
                print("🎬 Player item is ready to play")
                
                // Check if URL already has t parameter - if yes, we don't need to seek manually
                let urlString = finalUrl.absoluteString
                let hasTimeParameter = urlString.contains("&t=") || urlString.contains("?t=")
                
                // CRITICAL: Force play again regardless of time parameter
                player.play()
                print("▶️ Forcing play after ready status")
                
                // Only handle seeking if we need to
                if let t = explicitStartTime, t > 0 {
                    // Create a very precise time value with high timescale
                    let cmTime = CMTime(seconds: t, preferredTimescale: 1000)
                    
                    print("⏱ CRITICAL: Seeking to explicit time \(t) seconds after ready status")
                    
                    // Use precise seeking with tolerances
                    player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { success in
                        print("⏱ Seek to \(t) completed with result: \(success)")
                        
                        // Resume playback
                        player.play()
                        print("▶️ CRITICAL: Playback forced after seeking")
                    }
                } else if hasTimeParameter {
                    print("⏱ URL already has t parameter, ensuring playback")
                    player.play()
                    print("▶️ CRITICAL: Playback forced with t parameter")
                }
                
                // Set up coordinator
                context.coordinator.player = player
                VideoPlayerRegistry.shared.currentPlayer = player
                VideoPlayerRegistry.shared.playerViewController = playerVC
                
                // Set up end time observer if needed
                if let endTime = endTime {
                    print("⏱ Setting up marker end time observer at \(endTime) seconds")
                    
                    // Create a video player view model if not already set
                    if appModel.playerViewModel == nil {
                        let viewModel = VideoPlayerViewModel()
                        viewModel.endSeconds = endTime
                        appModel.playerViewModel = viewModel
                    }
                    
                    // Create a precise time observer for the end time
                    context.coordinator.timeObserver = player.addPeriodicTimeObserver(
                        forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
                        queue: .main
                    ) { [weak player] time in
                        guard !context.coordinator.endTimeReached else { return }
                        
                        if time.seconds >= endTime {
                            print("🎬 Reached marker end time \(endTime), pausing playback")
                            player?.pause()
                            context.coordinator.endTimeReached = true
                            
                            // Provide feedback
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                            
                            // Post notification for UI to respond
                            NotificationCenter.default.post(
                                name: Notification.Name("MarkerEndReached"),
                                object: nil
                            )
                        }
                    }
                }
                
                // Add periodic time observer to monitor actual playback progress
                context.coordinator.progressObserver = player.addPeriodicTimeObserver(
                    forInterval: CMTime(seconds: 1.0, preferredTimescale: 10),
                    queue: .main
                ) { time in
                    print("⏱ Current playback position: \(time.seconds) seconds")
                }
            } else if item.status == .failed {
                print("❌ Player item failed: \(item.error?.localizedDescription ?? "Unknown error")")
                
                // Try to recover by creating a new player with direct URL
                if let directURL = URL(string: url.absoluteString.replacingOccurrences(of: "stream.m3u8", with: "stream")) {
                    print("🔄 Attempting recovery with direct URL: \(directURL)")
                    player.replaceCurrentItem(with: AVPlayerItem(url: directURL))
                    player.play()
                    
                    // If we have an explicit start time, seek to it
                    if let timeToSeek = explicitStartTime, timeToSeek > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            print("⏱ CRITICAL: Performing recovery seek to \(timeToSeek) seconds")
                            let cmTime = CMTime(seconds: timeToSeek, preferredTimescale: 1000)
                            player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { success in
                                player.play()
                            }
                        }
                    }
                }
            }
        }
        
        // Store token in context for memory management
        context.coordinator.observationToken = token
        
        // Register with VideoPlayerRegistry for consistent access
        VideoPlayerRegistry.shared.currentPlayer = player
        VideoPlayerRegistry.shared.playerViewController = playerVC
        
        // Store reference to the player
        context.coordinator.player = player
        
        return customVC
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Check if we have our custom view controller
        if let customVC = uiViewController as? CustomPlayerViewController {
            let playerVC = customVC.playerVC
            
            // Check if we need to update player reference
            if VideoPlayerRegistry.shared.playerViewController !== playerVC {
                print("🔄 Updating registry with current player reference")
                VideoPlayerRegistry.shared.playerViewController = playerVC
                VideoPlayerRegistry.shared.currentPlayer = playerVC.player
            }
            
            // Try to hide the gear button again
            DispatchQueue.main.async {
                customVC.hideGearButton(in: customVC.view)
            }
        }
    }

    // Helper method to extract scene ID from URL
    private func extractSceneId(from urlString: String) -> String? {
        // Extract scene ID from URLs like http://server/scene/{id}/stream...
        if let range = urlString.range(of: "/scene/([^/]+)/", options: .regularExpression) {
            let sceneIdWithSlashes = String(urlString[range])
            // Remove "/scene/" and trailing slash
            let sceneId = sceneIdWithSlashes.replacingOccurrences(of: "/scene/", with: "").replacingOccurrences(of: "/", with: "")
            print("📱 Extracted scene ID: \(sceneId)")
            return sceneId
        }
        return nil
    }
}

// Add a global singleton to store the current player
class VideoPlayerRegistry {
    static let shared = VideoPlayerRegistry()

    var currentPlayer: AVPlayer?
    var playerViewController: AVPlayerViewController?

    private init() {}
}