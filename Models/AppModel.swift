import Foundation
import SwiftUI
import Combine
import AVKit
import UIKit

// Import local model types
@_exported import struct Foundation.URL

class AppModel: ObservableObject {
    // MARK: - Connection State
    @Published var isConnected: Bool = false
    @Published var serverAddress: String = UserDefaults.standard.string(forKey: "serverAddress") ?? ""
    @Published var apiKey: String = UserDefaults.standard.string(forKey: "apiKey") ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1aWQiOiJjayIsInN1YiI6IkFQSUtleSIsImlhdCI6MTczMTgwOTM2Mn0.7AOyZqTzyDsSnuDx__RBhuIIkoPg2btebToAlpK1zXo"
    @Published var isAttemptingConnection: Bool = false
    @Published var connectionError: String?
    
    // MARK: - Content State
    @Published var currentScene: StashScene?
    @Published var currentPerformer: StashScene.Performer?
    @Published var currentMarker: SceneMarker?
    @Published var performerScenes: [StashScene] = [] // Separate array for performer scenes
    @Published var lastWatchedScene: StashScene? // Track the last scene that was actually watched
    @Published var watchHistory: [StashScene] = [] // Track the sequence of scenes watched in current session
    
    // MARK: - Performer Detail View Context
    @Published var performerDetailViewPerformer: StashScene.Performer? // Dedicated performer for PerformerDetailView shuffle context
    
    // MARK: - UI State
    @Published var activeTab: Tab = .scenes
    @Published var searchQuery: String = ""
    @Published var isSearching: Bool = false
    @Published var showingFilterOptions: Bool = false
    @Published var playerViewModel: AnyObject?
    
    // MARK: - Navigation
    @Published var navigationPath = NavigationPath()
    
    // MARK: - API
    @Published private(set) var api: StashAPI
    private var cancellables = Set<AnyCancellable>()
    
    // Map to track API instances
    private static var sharedAPIs: [String: StashAPI] = [:]
    
    // MARK: - API Connection Status
    var isConnectionOK: Bool {
        api.connectionStatus == .connected
    }
    
    // MARK: - Navigation State
    @Published var navigationState: [String: Any] = [:]
    @Published var previousView: String = ""
    
    // MARK: - Lifecycle
    init() {
        // Default API key
        let savedAPIKey = UserDefaults.standard.string(forKey: "apiKey") ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1aWQiOiJjayIsInN1YiI6IkFQSUtleSIsImlhdCI6MTczMTgwOTM2Mn0.7AOyZqTzyDsSnuDx__RBhuIIkoPg2btebToAlpK1zXo"
        
        // Default server address
        let savedAddress = UserDefaults.standard.string(forKey: "serverAddress") ?? "http://192.168.86.100:9999"
        
        // Create or get shared API instance
        let cacheKey = "\(savedAddress)_\(savedAPIKey)"
        if let existingAPI = AppModel.sharedAPIs[cacheKey] {
            print("♻️ Reusing existing StashAPI instance")
            self.api = existingAPI
        } else {
            print("🆕 Creating new StashAPI instance")
            let newAPI = StashAPI(serverAddress: savedAddress, apiKey: savedAPIKey)
            AppModel.sharedAPIs[cacheKey] = newAPI
            self.api = newAPI
        }
        
        setupBindings()
        checkForSavedConnection()
    }
    
    // Preview initializer for SwiftUI previews
    init(isConnected: Bool) {
        // Default values for API key and server address
        let savedAPIKey = "preview_api_key"
        let savedAddress = "http://preview.example.com:9999"
        
        // Create API instance for preview
        self.api = StashAPI(serverAddress: savedAddress, apiKey: savedAPIKey)
        
        // Set connection state
        self.isConnected = isConnected
        
        // Setup bindings but skip connection check
        setupBindings()
    }
    
    private func setupBindings() {
        $serverAddress
            .dropFirst()
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .sink { [weak self] newAddress in
                guard let self = self else { return }
                if !newAddress.isEmpty {
                    // Create or get shared API instance
                    let cacheKey = "\(newAddress)_\(self.apiKey)"
                    if let existingAPI = AppModel.sharedAPIs[cacheKey] {
                        print("♻️ Reusing existing StashAPI instance for: \(newAddress)")
                        self.api = existingAPI
                    } else {
                        print("🆕 Creating new StashAPI instance for: \(newAddress)")
                        let newAPI = StashAPI(serverAddress: newAddress, apiKey: self.apiKey)
                        AppModel.sharedAPIs[cacheKey] = newAPI
                        self.api = newAPI
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func checkForSavedConnection() {
        // Load saved server address
        if let savedAddress = UserDefaults.standard.string(forKey: "serverAddress"), !savedAddress.isEmpty {
            serverAddress = savedAddress
            isConnected = true
            
            // Load saved API key
            let savedAPIKey = UserDefaults.standard.string(forKey: "apiKey") ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1aWQiOiJjayIsInN1YiI6IkFQSUtleSIsImlhdCI6MTczMTgwOTM2Mn0.7AOyZqTzyDsSnuDx__RBhuIIkoPg2btebToAlpK1zXo"
            apiKey = savedAPIKey
            
            // Initialize API with saved settings - already done in init
        }
    }
    
    // MARK: - Connection Management
    func attemptConnection() {
        guard !serverAddress.isEmpty else { return }
        
        var address = serverAddress
        if !address.hasPrefix("http://") && !address.hasPrefix("https://") {
            address = "http://" + address
        }
        if !address.contains(":9999") && !address.contains(":443") {
            if address.hasSuffix("/") {
                address.removeLast()
            }
            address += ":9999"
        }
        
        isAttemptingConnection = true
        connectionError = nil
        
        // Update server address
        UserDefaults.standard.set(address, forKey: "serverAddress")
        self.serverAddress = address
        
        // Save API key
        UserDefaults.standard.set(apiKey, forKey: "apiKey")
        
        // Create or get shared API instance
        let cacheKey = "\(address)_\(apiKey)"
        if let existingAPI = AppModel.sharedAPIs[cacheKey] {
            print("♻️ Reusing existing StashAPI instance for connection")
            self.api = existingAPI
        } else {
            print("🆕 Creating new StashAPI instance for connection")
            let newAPI = StashAPI(serverAddress: address, apiKey: apiKey)
            AppModel.sharedAPIs[cacheKey] = newAPI
            self.api = newAPI
        }
        
        // Check connection using the new API
        Task {
            // Check connection
            do {
                try await api.checkServerConnection()
            } catch {
                print("Connection check failed: \(error)")
            }
            
            // Update UI based on connection status
            await MainActor.run {
                switch api.connectionStatus {
                case .connected:
                    self.isConnected = true
                    self.connectionError = nil
                    print("✅ Connection successful")
                    
                case .authenticationFailed:
                    self.isConnected = false
                    self.connectionError = "Authentication failed - check API key"
                    
                case .disconnected:
                    self.isConnected = false
                    self.connectionError = "Could not connect to server"
                    
                case .failed(let error):
                    self.isConnected = false
                    self.connectionError = error.localizedDescription
                    
                case .unknown:
                    self.isConnected = false
                    self.connectionError = "Unknown connection status"
                }
                
                self.isAttemptingConnection = false
            }
        }
    }
    
    func disconnect() {
        isConnected = false
    }
    
    // MARK: - Navigation
    func navigateToScene(_ scene: StashScene, startSeconds: Double? = nil, endSeconds: Double? = nil) {
        print("🚀 NAVIGATION - Navigating to scene: \(scene.title ?? "Untitled") with startSeconds: \(String(describing: startSeconds)), endSeconds: \(String(describing: endSeconds))")
        
        // FIXED: Set flag to indicate we're navigating to video (temporary navigation)
        // This helps PerformerDetailView know not to clear performer context
        UserDefaults.standard.set(true, forKey: "isNavigatingToVideo")
        print("🎯 NAVIGATION - Set flag for temporary video navigation")
        
        // Notify that a main video is starting - this will stop all preview videos
        NotificationCenter.default.post(name: Notification.Name("MainVideoPlayerStarted"), object: nil)
        
        // Check if we're in any shuffle context to handle audio properly
        let isMarkerShuffle = UserDefaults.standard.bool(forKey: "isMarkerShuffleContext")
        let isTagShuffle = UserDefaults.standard.bool(forKey: "isTagSceneShuffleContext")
        
        // ALWAYS kill audio to prevent stacking during navigation
        print("🔇 Killing audio for navigation (marker: \(isMarkerShuffle), tag: \(isTagShuffle))")
        killAllAudio()
        
        // Store both scene and timestamp in properties
        currentScene = scene
        
        // FIXED: Track this as the last watched scene for return navigation
        lastWatchedScene = scene
        print("🎯 HISTORY - Set lastWatchedScene to: \(scene.title ?? "Untitled")")
        
        // Add to watch history (avoid duplicates of consecutive same scene)
        if watchHistory.last?.id != scene.id {
            watchHistory.append(scene)
            // Keep history to reasonable size (last 20 scenes)
            if watchHistory.count > 20 {
                watchHistory = Array(watchHistory.suffix(20))
            }
            print("🎯 HISTORY - Added to watch history: \(scene.title ?? "Untitled") (history count: \(watchHistory.count))")
            print("🎯 HISTORY - Full history: \(watchHistory.map { $0.title ?? "Untitled" })")
        } else {
            print("🎯 HISTORY - Skipping duplicate scene: \(scene.title ?? "Untitled") (last in history: \(watchHistory.last?.title ?? "None"))")
        }
        
        // Critical: Clear any stale scene data before setting new scene
        UserDefaults.standard.removeObject(forKey: "lastNavigatedSceneId")
        UserDefaults.standard.set(scene.id, forKey: "lastNavigatedSceneId")
        print("🎯 Set lastNavigatedSceneId to: \(scene.id)")
        
        // Store startSeconds directly in the model for VideoPlayerView to access
        if let startSeconds = startSeconds {
            print("⏱ Setting current timestamp to: \(startSeconds) seconds")
            UserDefaults.standard.set(startSeconds, forKey: "scene_\(scene.id)_startTime")
        }
        
        // Store endSeconds if provided
        if let endSeconds = endSeconds {
            print("⏱ Setting end timestamp to: \(endSeconds) seconds")
            UserDefaults.standard.set(endSeconds, forKey: "scene_\(scene.id)_endTime")
        } else {
            // Clear any previous endSeconds when not provided
            UserDefaults.standard.removeObject(forKey: "scene_\(scene.id)_endTime")
        }
        
        // Check if we're in shuffle mode and need to replace current video
        if (isMarkerShuffleMode || isServerSideShuffle) && !navigationPath.isEmpty {
            print("⏱ Shuffle mode: Popping current video and navigating to new one")
            // Pop the current video
            _ = navigationPath.removeLast()
            // Small delay to let the pop complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.navigationPath.append(scene)
            }
        } else {
            // Regular navigation - just append to path
            print("⏱ Adding scene to navigation path")
            navigationPath.append(scene)
        }
    }
    
    func navigateToPerformer(_ performer: StashScene.Performer) {
        print("🚀 NAVIGATION - Navigating to performer: \(performer.name) (ID: \(performer.id))")
        print("🔍 NAVIGATION - Current stack: \(navigationPath)")

        // This is a CRITICAL function - ensure we ALWAYS navigate properly
        
        // Step 1: Perform force feedback to indicate navigation action
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        // Step 2: Set current performer (for context and consistency)
        currentPerformer = performer

        // Step 3: Clear existing scenes to force redraw and prevent stale data
        // NOTE: Don't clear markers here - let PerformerDetailView handle its own marker loading
        api.scenes = []
        print("🧹 NAVIGATION - Cleared existing scenes (markers will be handled by detail view)")
        
        // Step 4: Reset any markers or performer-specific flags
        // to ensure clean navigation
        UserDefaults.standard.removeObject(forKey: "performerDetailSelectedTab")
        
        // Step 5: Set loading state to show immediate UI feedback
        api.isLoading = true

        // Step 6: Actually perform the navigation action
        // We do this last to ensure all state is reset
        navigationPath.append(performer)
        print("🏁 NAVIGATION - Navigation completed to performer: \(performer.name)")
        
        // Immediately start loading scenes to ensure they're ready
        Task(priority: .userInitiated) {
            print("🔄 NAVIGATION - Starting scene load for performer")
            
            // Try the more reliable direct GraphQL query approach first
            do {
                print("🔄 NAVIGATION - Using direct GraphQL query for performer scenes")
                
                // More reliable direct GraphQL query
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
                                "value": ["\(performer.id)"],
                                "modifier": "INCLUDES"
                            }
                        }
                    },
                    "query": "query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) { findScenes(filter: $filter, scene_filter: $scene_filter) { count scenes { id title details paths { screenshot preview stream } files { size duration video_codec width height } performers { id name gender scene_count } tags { id name } rating100 } } }"
                }
                """
                
                let data = try await api.executeGraphQLQuery(query)
                
                // Define struct for decoding
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
                
                // Set scenes to the API
                await MainActor.run {
                    api.scenes = response.data.findScenes.scenes
                    api.isLoading = false
                    print("✅ NAVIGATION - Scene load completed with \(api.scenes.count) scenes via direct GraphQL")
                }
                
                return // Exit early on success
            } catch {
                print("⚠️ NAVIGATION - GraphQL query failed: \(error)")
                print("⚠️ NAVIGATION - Falling back to standard API method")
                
                // Continue to fallback method
            }
            
            // Fallback to standard method
            await api.fetchPerformerScenes(
                performerId: performer.id,
                page: 1,
                perPage: 60, // Increased page size
                sort: "date", 
                direction: "DESC",
                appendResults: false
            )
            
            await MainActor.run {
                api.isLoading = false
                print("✅ NAVIGATION - Scene load completed with \(api.scenes.count) scenes via standard API")
            }
        }
    }
    
    func navigateToMarker(_ marker: SceneMarker) {
        print("🚀 NAVIGATION - Navigating to marker: \(marker.title) at \(marker.seconds) seconds in scene \(marker.scene.id)")
        print("🎲 NAVIGATION DEBUG - isMarkerShuffleMode: \(isMarkerShuffleMode), navigationPath.isEmpty: \(navigationPath.isEmpty), navigationPath.count: \(navigationPath.count)")
        
        // Check if we're already in a video player and in shuffle mode
        if isMarkerShuffleMode && !navigationPath.isEmpty {
            print("🎲 Already in video player during shuffle - updating current player instead of navigating")
            updateVideoPlayerWithMarker(marker)
            return
        }
        
        // Create a StashScene from the marker data
        let markerScene = StashScene(
            id: marker.scene.id,
            title: marker.title.isEmpty ? marker.scene.title : marker.title,
            details: nil,
            paths: StashScene.ScenePaths(
                screenshot: marker.screenshot,
                preview: marker.preview,
                stream: marker.stream
            ),
            files: [],
            performers: marker.scene.performers ?? [],
            tags: [],
            rating100: nil,
            o_counter: nil
        )
        
        // Store marker info for the video player
        currentMarker = marker
        
        // Set marker navigation flag so VideoPlayerView knows to use stored timestamp
        UserDefaults.standard.set(true, forKey: "scene_\(marker.scene.id)_isMarkerNavigation")
        print("📱 Set marker navigation flag for scene \(marker.scene.id)")
        
        // Navigate exactly like a scene, but with the marker's timestamp
        navigateToScene(markerScene, startSeconds: Double(marker.seconds))
    }

    // Helper method to save navigation state before entering video
    private func savePreviousNavigationState() {
        // Store the current view
        if !navigationPath.isEmpty {
            // Just use the string representation of the navigationPath itself
            previousView = "\(navigationPath)"
            print("📍 Saving previous view: \(previousView)")
        } else {
            previousView = "main"
            print("📍 No previous view found, using main")
        }
    }
    
    // Helper method to restore previous navigation state
    func restorePreviousNavigationState() {
        print("📍 Attempting to restore to previous view: \(previousView)")
        
        // Don't try to navigate if we don't have a previous state
        if previousView.isEmpty || previousView == "main" {
            // If we're at the root view, clear the navigation path
            navigationPath = NavigationPath()
            return
        }
        
        // Important! If currentPerformer is set, this means we came from a performer detail view
        // and need to maintain the performer context even after closing the video
        let cameFromPerformerDetail = currentPerformer != nil
        
        // Check if we're in a performer's marker detail view
        if previousView.contains("PerformerMarkersView") || 
           previousView.contains("PerformerDetailView") {
            // For performer-related views, pop back one level
            // This will return from the video to the performer view
            if !navigationPath.isEmpty {
                print("📍 Returning to performer view")
                
                // Before removing from navigation, ensure we're not losing the performer context
                if cameFromPerformerDetail {
                    print("📍 Preserving performer context for: \(currentPerformer?.name ?? "unknown")")
                    
                    // Important: We want to preserve the selected tab in PerformerDetailView
                    // If we were looking at scenes (most common), ensure we return to that
                    // We use UserDefaults to communicate this to PerformerDetailView
                    UserDefaults.standard.set(0, forKey: "performerDetailSelectedTab")
                    UserDefaults.standard.set(true, forKey: "forceScenesTab")
                }
                
                navigationPath.removeLast()
            }
        } else {
            // For other cases, just pop back once
            if !navigationPath.isEmpty {
                navigationPath.removeLast()
            }
        }
        
        // Clear the previous view reference after restoration
        previousView = ""
    }

    func navigateToTag(_ tag: StashScene.Tag) {
        print("🚀 NAVIGATION - Navigating to tag: \(tag.name) (ID: \(tag.id))")

        // Clear existing scenes first to avoid showing incorrect data temporarily
        api.scenes = []
        print("🧹 NAVIGATION - Cleared existing scenes for tag view")

        // Navigate to the tag
        navigationPath.append(tag)
        print("🏁 NAVIGATION - Navigation completed to tag: \(tag.name)")

        // Let the TaggedScenesView handle loading scenes through its onAppear method
    }
    
    // MARK: - Model References
    // These are included to help with type resolution during compilation
    func modelReferences() {
        // This function is never called - it just helps link the types
        let _ = StashScene(
            id: "",
            title: nil,
            details: nil,
            paths: StashScene.ScenePaths(screenshot: "", preview: nil, stream: ""),
            files: [],
            performers: [],
            tags: [],
            rating100: nil,
            o_counter: nil
        )
        
        let _ = SceneMarker(
            id: "",
            title: "",
            seconds: 0,
            end_seconds: nil,
            stream: "",
            preview: "",
            screenshot: "",
            scene: SceneMarker.MarkerScene(id: ""),
            primary_tag: SceneMarker.Tag(id: "", name: ""),
            tags: []
        )
    }
    
    func popNavigation() {
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }
    
    func clearNavigation() {
        navigationPath = NavigationPath()
    }
    
    // Force close the current video and clean up resources
    func forceCloseVideo(manualExit: Bool = true) {
        print("📱 Force closing video player (manual exit: \(manualExit))")
        
        if manualExit {
            // Always kill audio on manual exit regardless of shuffle mode
            killAllAudio()
        } else {
            // Check if we're in shuffle mode before killing audio (for programmatic navigation)
            let isMarkerShuffle = UserDefaults.standard.bool(forKey: "isMarkerShuffleContext")
            let isTagShuffle = UserDefaults.standard.bool(forKey: "isTagSceneShuffleContext")
            
            if !isMarkerShuffle && !isTagShuffle {
                killAllAudio()
            } else {
                print("🎲 Skipping audio kill in forceCloseVideo - in shuffle mode (marker: \(isMarkerShuffle), tag: \(isTagShuffle))")
            }
        }
        
        // Store current scene ID before clearing for potential restoration
        let currentSceneId = currentScene?.id
        
        // Clear current scene reference
        currentScene = nil
        
        // Clear any video-related UserDefaults if needed
        if let sceneId = currentSceneId {
            UserDefaults.standard.removeObject(forKey: "scene_\(sceneId)_hlsURL")
            UserDefaults.standard.removeObject(forKey: "scene_\(sceneId)_isMarkerNavigation")
        }
        
        // FIXED: Clear the temporary navigation flag since we're returning from video
        UserDefaults.standard.removeObject(forKey: "isNavigatingToVideo")
        print("🎯 NAVIGATION - Cleared temporary video navigation flag")
        
        // If we have a navigation path and the last item is likely a video, remove it
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
            print("📱 Removed last navigation item, remaining path count: \(navigationPath.count)")
        }
        
        // FIXED: Navigate back to last watched scene in scenes view if we're returning to scenes tab
        if manualExit && activeTab == .scenes && lastWatchedScene != nil {
            print("🎯 HISTORY - Manual exit to scenes tab, will show watch history")
            // Set a flag that MediaLibraryView can use to show watch history
            if !watchHistory.isEmpty {
                UserDefaults.standard.set(true, forKey: "showWatchHistory")
                print("🎯 HISTORY - Set flag to show watch history (\(watchHistory.count) scenes)")
                
                // Also set scroll target for the first scene in history
                if let firstScene = watchHistory.first {
                    UserDefaults.standard.set(firstScene.id, forKey: "scrollToSceneId")
                    print("🎯 HISTORY - Set scrollToSceneId to first in history: \(firstScene.id)")
                }
            }
        }
    }
    
    // New method specifically to kill all audio and players
    func killAllAudio() {
        print("🔇 AGGRESSIVE AUDIO CLEANUP: Killing all audio")
        
        // Try to find and kill every possible player
        
        // Method 1: Check VideoPlayerRegistry
        if let player = VideoPlayerRegistry.shared.currentPlayer {
            print("🔇 Stopping VideoPlayerRegistry player")
            player.isMuted = true
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        VideoPlayerRegistry.shared.currentPlayer = nil
        VideoPlayerRegistry.shared.playerViewController = nil
        
        // Method 2: Use GlobalVideoManager
        print("🔇 Stopping all preview players via GlobalVideoManager")
        GlobalVideoManager.shared.stopAllPreviews()
        GlobalVideoManager.shared.cleanupAllPlayers()
        
        // Method 3: Check for AVAudioSession and forcibly pause it
        print("🔇 Forcibly interrupting AVAudioSession")
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ Error deactivating audio session: \(error)")
        }
        
        // Method 4: Hunt down all possible players in the view hierarchy
        print("🔇 Finding all AVPlayers in view hierarchy")
        let allPlayers = getAllPreviewPlayers()
        for (index, player) in allPlayers.enumerated() {
            print("🔇 Stopping player \(index+1) of \(allPlayers.count)")
            player.isMuted = true
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        
        // Method 5: Try with system audio
        let audioSession = AVAudioSession.sharedInstance()
        if audioSession.isOtherAudioPlaying {
            print("🔇 Detected other audio playing, attempting to interrupt")
            do {
                try audioSession.setCategory(.ambient, mode: .default, options: [])
                try audioSession.setActive(false)
                try audioSession.setActive(true)
                try audioSession.setActive(false)
            } catch {
                print("⚠️ Error manipulating audio session: \(error)")
            }
        }
        
        // Final cleanup
        print("🔇 Final cleanup")
        GlobalVideoManager.shared.cleanupAllPlayers()
    }
    
    
    // Helper to find all AVPlayers that might be playing in the app
    private func getAllPreviewPlayers() -> [AVPlayer] {
        var players: [AVPlayer] = []
        
        // This is a hack to find preview players that might be playing
        // Look through all windows and view controllers for AVPlayers
        for window in UIApplication.shared.windows {
            players.append(contentsOf: findPlayers(in: window.rootViewController))
        }
        
        return players
    }
    
    // Recursively find all players in the view hierarchy
    private func findPlayers(in viewController: UIViewController?) -> [AVPlayer] {
        var players: [AVPlayer] = []
        
        guard let vc = viewController else { return players }
        
        // Check if this is an AVPlayerViewController
        if let playerVC = vc as? AVPlayerViewController {
            if let player = playerVC.player {
                players.append(player)
            }
        }
        
        // Check presented view controllers
        if let presented = vc.presentedViewController {
            players.append(contentsOf: findPlayers(in: presented))
        }
        
        // Check child view controllers
        for child in vc.children {
            players.append(contentsOf: findPlayers(in: child))
        }
        
        return players
    }
    
    // MARK: - Tab Management
    func selectTab(_ tab: Tab) {
        activeTab = tab
        clearNavigation()
    }
    
    // MARK: - Marker Shuffle System
    @Published var markerShuffleQueue: [SceneMarker] = []
    @Published var currentShuffleIndex: Int = 0
    @Published var isMarkerShuffleMode: Bool = false
    @Published var shuffleTagFilter: String? = nil
    @Published var shuffleTagFilters: [String] = [] // For multi-tag shuffling
    @Published var shuffleSearchQuery: String? = nil
    
    // Server-side shuffle tracking
    @Published var shuffleTagNames: [String] = [] // Tags to shuffle from
    @Published var shuffleTotalMarkerCount: Int = 0 // Total available markers on server
    @Published var isServerSideShuffle: Bool = false // Use server-side random selection
    private var currentShuffleTag: String = "" // Track current tag being played
    private var currentTagPlayCount: Int = 0 // Track how many times current tag has played
    
    // MARK: - Balanced Tag Rotation Variables
    private var tagMarkerGroups: [String: [SceneMarker]] = [:] // Groups markers by tag name
    private var recentMarkerIds: Set<String> = [] // Track recently played markers for repeat prevention
    private var tagRotationOrder: [String] = [] // Ordered list of tags for round-robin rotation
    private var currentTagIndex: Int = 0 // Current position in tag rotation
    
    /// Start marker shuffle for a specific tag - uses server-side random selection
    func startMarkerShuffle(forTag tagId: String, tagName: String, displayedMarkers: [SceneMarker]) {
        print("🎲 Starting SERVER-SIDE marker shuffle for tag: \(tagName)")
        
        // Set shuffle context immediately for UI responsiveness
        isMarkerShuffleMode = true
        isServerSideShuffle = true
        shuffleTagNames = [tagName]
        shuffleTagFilter = tagId
        shuffleTagFilters = [] // Clear multi-tag filters
        shuffleSearchQuery = nil
        UserDefaults.standard.set(true, forKey: "isMarkerShuffleContext")
        UserDefaults.standard.set(true, forKey: "isMarkerShuffleMode")
        
        // Reset balanced tag rotation tracking
        resetBalancedTagRotation()
        
        // Play first marker immediately if available
        if let firstMarker = displayedMarkers.randomElement() {
            print("🎯 Starting with random marker from displayed: \(firstMarker.title)")
            navigateToMarker(firstMarker)
        } else {
            // No displayed markers, fetch one from server
            Task {
                await playNextServerSideMarker()
            }
        }
    }
    
    /// Load all markers for a tag with optimization to prevent freezing
    private func loadOptimizedMarkersForTag(tagId: String, tagName: String, displayedMarkers: [SceneMarker]) async {
        print("🔄 Loading optimized markers for tag: \(tagName)")
        
        var allMarkers = displayedMarkers // Start with what we have
        var currentPage = 1
        let maxPages = 5 // Reduced to prevent freezing
        let maxMarkers = 1000 // Cap at 1000 markers for performance
        
        while currentPage <= maxPages && allMarkers.count < maxMarkers {
            print("🔄 Loading page \(currentPage) for tag: \(tagName)")
            
            // Use smaller batch size for better responsiveness
            await api.fetchMarkersByTag(tagId: tagId, page: currentPage, appendResults: false, perPage: 200)
            let newMarkers = api.markers
            
            if newMarkers.isEmpty {
                print("📄 No more markers found on page \(currentPage), stopping")
                break
            }
            
            // Add unique markers to avoid duplicates
            let uniqueMarkers = newMarkers.filter { newMarker in
                !allMarkers.contains { $0.id == newMarker.id }
            }
            allMarkers.append(contentsOf: uniqueMarkers)
            
            print("📊 Page \(currentPage): Found \(newMarkers.count) markers, \(uniqueMarkers.count) unique (Total: \(allMarkers.count))")
            
            // If we got less than the full page size, we're done
            if newMarkers.count < 200 {
                break
            }
            
            currentPage += 1
            
            // Add small delay to prevent overwhelming the server
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            
            // Update queue with expanded results every page
            await MainActor.run {
                self.markerShuffleQueue = allMarkers.shuffled()
                print("🔄 Updated shuffle queue with \(self.markerShuffleQueue.count) markers")
            }
        }
        
        await MainActor.run {
            // Final update with all markers
            self.markerShuffleQueue = allMarkers.shuffled()
            self.api.isLoading = false
            print("✅ Optimized shuffle queue created with \(self.markerShuffleQueue.count) total markers for tag: \(tagName)")
        }
    }
    
    /// Load all markers for multiple tags with optimization to prevent freezing
    private func loadOptimizedMarkersForMultipleTags(tagIds: [String], tagNames: [String], displayedMarkers: [SceneMarker]) async {
        print("🔄 Loading ALL markers for combined tags: \(tagNames.joined(separator: ", "))")
        
        var allMarkers = Set<SceneMarker>() // Use Set to avoid duplicates
        
        // Add displayed markers first
        displayedMarkers.forEach { allMarkers.insert($0) }
        
        // For combined tags, we want ALL markers, not just search results
        // Load markers for each tag name using search
        for tagName in tagNames {
            print("🏷️ Loading ALL markers for tag: \(tagName)")
            
            var currentPage = 1
            let maxPages = 10 // Load more pages to get ALL markers
            
            while currentPage <= maxPages {
                do {
                    // Use searchMarkers to avoid interfering with the main API state
                    let searchedMarkers = try await api.searchMarkers(query: tagName, page: currentPage, perPage: 100)
                    
                    if searchedMarkers.isEmpty {
                        print("📊 No more markers for tag \(tagName) at page \(currentPage)")
                        break
                    }
                    
                    // Add all markers that match the tag
                    let matchingMarkers = searchedMarkers.filter { marker in
                        marker.primary_tag.name.lowercased() == tagName.lowercased()
                    }
                    
                    matchingMarkers.forEach { allMarkers.insert($0) }
                    
                    print("📊 Tag \(tagName) page \(currentPage): Found \(searchedMarkers.count) markers, \(matchingMarkers.count) matching")
                    
                    if searchedMarkers.count < 100 {
                        break // No more pages
                    }
                    
                    currentPage += 1
                    
                    // Small delay to avoid overwhelming the server
                    try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
                } catch {
                    print("❌ Error loading markers for tag \(tagName): \(error)")
                    break
                }
            }
            
            print("🏷️ Total markers for tag \(tagName): \(allMarkers.count)")
        }
        
        await MainActor.run {
            // Final update with all markers
            let shuffledMarkers = Array(allMarkers).shuffled()
            self.markerShuffleQueue = shuffledMarkers
            self.api.isLoading = false
            print("✅ Multi-tag shuffle queue created with \(shuffledMarkers.count) total unique markers from \(tagNames.count) tags")
        }
    }
    
    /// Start marker shuffle for multiple tags - uses client-side shuffle with loaded markers
    func startMarkerShuffle(forMultipleTags tagIds: [String], tagNames: [String], displayedMarkers: [SceneMarker]) {
        print("🎲 Starting LARGE POOL multi-tag shuffle with \(tagNames.count) tags: \(tagNames.joined(separator: ", "))")
        print("🎲 DEBUG - Tag IDs: \(tagIds)")
        print("🎲 DEBUG - Tag Names: \(tagNames)")
        print("🎲 DEBUG - Displayed Markers Count: \(displayedMarkers.count)")
        
        // Set shuffle context
        isMarkerShuffleMode = true
        isServerSideShuffle = false  // Use client-side shuffle with the large combined pool
        shuffleTagNames = tagNames
        shuffleTagFilters = tagIds
        shuffleTagFilter = nil
        shuffleSearchQuery = nil
        
        // Reset balanced tag rotation tracking
        resetBalancedTagRotation()
        
        // Set loading state
        api.isLoading = true
        
        // Temporary fallback to old method while debugging compilation issues
        markerShuffleQueue = displayedMarkers.shuffled()
        currentShuffleIndex = 0
        
        print("✅ Created shuffle queue with \(markerShuffleQueue.count) combined markers")
        
        // Reset the tag rotation tracking
        currentShuffleTag = ""
        currentTagPlayCount = 0
        UserDefaults.standard.set(true, forKey: "isMarkerShuffleContext")
        UserDefaults.standard.set(true, forKey: "isMarkerShuffleMode")
        
        // Play first marker immediately if available
        if let firstMarker = markerShuffleQueue.first {
            print("🎯 Starting with first marker from shuffled queue: \(firstMarker.title)")
            navigateToMarker(firstMarker)
        } else {
            print("❌ No markers available to shuffle")
            stopMarkerShuffle()
        }
    }
    
    /*
    /// Load large marker pool by querying each tag separately from database
    @MainActor
    private func loadLargeMarkerPoolForTags(tagNames: [String]) async {
        print("🎲 LARGE POOL: Loading markers for each tag separately...")
        
        var allCombinedMarkers = Set<SceneMarker>()
        var tagCounts: [String: Int] = [:]
        
        do {
            for tagName in tagNames {
                print("🎲 LARGE POOL: Querying tag '\(tagName)'...")
                
                // First get the total count for this tag to determine how many to fetch
                let totalCount = try await api.getMarkerCountForTag(tagName: tagName)
                print("🎲 LARGE POOL: Tag '\(tagName)' has \(totalCount) total markers")
                
                // Determine how many markers to fetch based on tag size
                let markersToFetch: Int
                if totalCount <= 10 {
                    // Small tags: get all markers
                    markersToFetch = totalCount
                    print("🎲 LARGE POOL: Small tag - fetching all \(markersToFetch) markers")
                } else if totalCount <= 100 {
                    // Medium tags: get most markers
                    markersToFetch = min(80, totalCount)
                    print("🎲 LARGE POOL: Medium tag - fetching \(markersToFetch) markers")
                } else {
                    // Large tags: get substantial sample
                    markersToFetch = min(250, totalCount)
                    print("🎲 LARGE POOL: Large tag - fetching \(markersToFetch) markers")
                }
                
                // Fetch markers for this tag with random sort
                let tagMarkers = try await api.searchMarkers(query: "#\(tagName)", page: 1, perPage: markersToFetch, sort: "random")
                
                // Filter to only exact matches for this tag
                let exactMatches = tagMarkers.filter { marker in
                    marker.primary_tag.name.lowercased() == tagName.lowercased() ||
                    marker.tags.contains { $0.name.lowercased() == tagName.lowercased() }
                }
                
                print("🎲 LARGE POOL: Tag '\(tagName)' - fetched \(tagMarkers.count), exact matches: \(exactMatches.count)")
                tagCounts[tagName] = exactMatches.count
                
                // Add to combined set (Set automatically handles duplicates)
                for marker in exactMatches {
                    allCombinedMarkers.insert(marker)
                }
            }
            
            // Convert to array and shuffle
            markerShuffleQueue = Array(allCombinedMarkers).shuffled()
            currentShuffleIndex = 0
            
            print("🎲 LARGE POOL: Final combined pool:")
            for (tagName, count) in tagCounts {
                print("🎲   - \(tagName): \(count) markers")
            }
            print("🎲 LARGE POOL: Total unique markers: \(markerShuffleQueue.count)")
            
            // Reset the tag rotation tracking
            currentShuffleTag = ""
            currentTagPlayCount = 0
            UserDefaults.standard.set(true, forKey: "isMarkerShuffleContext")
            UserDefaults.standard.set(true, forKey: "isMarkerShuffleMode")
            
            // Clear loading state
            api.isLoading = false
            
            // Play first marker immediately if available
            if let firstMarker = markerShuffleQueue.first {
                print("🎯 LARGE POOL: Starting with first marker from pool: \(firstMarker.title) [tag: \(firstMarker.primary_tag.name)]")
                navigateToMarker(firstMarker)
            } else {
                print("❌ LARGE POOL: No markers available to shuffle")
                stopMarkerShuffle()
            }
            
        } catch {
            print("❌ LARGE POOL: Error loading markers: \(error)")
            api.isLoading = false
            stopMarkerShuffle()
        }
    }
    */

    /// Start marker shuffle for search results - loads ALL markers from API for comprehensive shuffle
    func startMarkerShuffle(forSearchQuery query: String, displayedMarkers: [SceneMarker]) {
        print("🎲 Starting marker shuffle for search: \(query) - loading ALL markers from API")
        
        // Set shuffle context
        isMarkerShuffleMode = true
        shuffleSearchQuery = query
        shuffleTagFilter = nil
        shuffleTagFilters = []
        UserDefaults.standard.set(true, forKey: "isMarkerShuffleContext")
        
        // Reset balanced tag rotation tracking
        resetBalancedTagRotation()
        
        // Set loading state
        api.isLoading = true
        
        Task {
            await loadAllMarkersForSearch(query: query)
        }
    }
    
    // MARK: - Server-Side Shuffle Functions
    
    /// Play next marker using server-side random selection
    func playNextServerSideMarker() async {
        print("🎲 Fetching random marker from server for tags: \(shuffleTagNames.joined(separator: ", "))")
        
        // For multi-tag shuffle, implement rotation logic (max 5 from same tag)
        if shuffleTagNames.count > 1 {
            print("🎲 Multi-tag mode: \(shuffleTagNames.count) tags available")
            
            var selectedTag: String
            
            // Check if we need to switch tags
            if currentTagPlayCount >= 5 || currentShuffleTag.isEmpty || !shuffleTagNames.contains(currentShuffleTag) {
                // Switch to a different tag
                let otherTags = shuffleTagNames.filter { $0 != currentShuffleTag }
                selectedTag = otherTags.randomElement() ?? shuffleTagNames.randomElement()!
                currentShuffleTag = selectedTag
                currentTagPlayCount = 1
                print("🎲 Switching to new tag: '\(selectedTag)'")
            } else {
                // 70% chance to stay with current tag, 30% chance to switch
                if Int.random(in: 1...10) <= 7 {
                    selectedTag = currentShuffleTag
                    currentTagPlayCount += 1
                    print("🎲 Continuing with current tag: '\(selectedTag)' (count: \(currentTagPlayCount))")
                } else {
                    // Switch to a different tag
                    let otherTags = shuffleTagNames.filter { $0 != currentShuffleTag }
                    selectedTag = otherTags.randomElement() ?? currentShuffleTag
                    if selectedTag != currentShuffleTag {
                        currentShuffleTag = selectedTag
                        currentTagPlayCount = 1
                        print("🎲 Randomly switching to tag: '\(selectedTag)'")
                    } else {
                        currentTagPlayCount += 1
                    }
                }
            }
            
            print("🎲 Selected tag: '\(selectedTag)' (play count: \(currentTagPlayCount)/5)")
            
            // Now fetch a random marker from the selected tag
            await fetchRandomMarkerForTag(selectedTag)
        } else {
            // Single tag shuffle
            guard let randomTag = shuffleTagNames.first else {
                print("❌ No tags available for server-side shuffle")
                return
            }
            
            print("🎲 Single tag shuffle - tag: '\(randomTag)'")
            await fetchRandomMarkerForTag(randomTag)
        }
    }
    
    /// Helper function to fetch a random marker for a specific tag
    private func fetchRandomMarkerForTag(_ tagName: String) async {
        print("🎲 Fetching random marker for tag: '\(tagName)'")
        
        do {
            // Get a truly random page - estimate ~100 markers per page, pick from first 20 pages
            let randomPage = Int.random(in: 1...20)
            print("🎲 Fetching page \(randomPage) for tag '\(tagName)'")
            
            let markers = try await api.searchMarkers(query: tagName, page: randomPage, perPage: 100)
            
            // Debug: Print first few markers to see what we're getting
            print("🎲 DEBUG: Retrieved \(markers.count) markers from search")
            if !markers.isEmpty {
                for (index, marker) in markers.prefix(3).enumerated() {
                    print("🎲 DEBUG: Marker \(index + 1) - Tag: '\(marker.primary_tag.name)' vs Search: '\(tagName)'")
                }
            }
            
            // Filter to exact tag matches (case-insensitive)
            let matchingMarkers = markers.filter { marker in
                marker.primary_tag.name.lowercased() == tagName.lowercased()
            }
            
            print("🎲 Found \(matchingMarkers.count) markers on page \(randomPage)")
            
            // Pick a random marker from the results
            if let randomMarker = matchingMarkers.randomElement() {
                print("🎯 Selected random marker: \(randomMarker.title) from tag: \(tagName)")
                await MainActor.run {
                    navigateToMarker(randomMarker)
                }
                return
            } else if randomPage > 1 {
                // If no markers on this page, try page 1 as fallback
                print("⚠️ No markers on page \(randomPage), trying page 1")
                let fallbackMarkers = try await api.searchMarkers(query: tagName, page: 1, perPage: 100)
                let fallbackMatching = fallbackMarkers.filter { marker in
                    marker.primary_tag.name.lowercased() == tagName.lowercased()
                }
                
                if let randomMarker = fallbackMatching.randomElement() {
                    print("🎯 Fallback: Selected random marker: \(randomMarker.title)")
                    await MainActor.run {
                        navigateToMarker(randomMarker)
                    }
                    return
                }
            }
        } catch {
            print("❌ Error fetching markers for tag '\(tagName)': \(error)")
        }
    }
    
    /// Load all markers for a search query with pagination
    private func loadAllMarkersForSearch(query: String) async {
        print("🔄 Loading ALL markers for search: '\(query)'")
        
        var allMarkers: [SceneMarker] = []
        var currentPage = 1
        let maxPages = 5 // Reduced to prevent performance issues
        
        while currentPage <= maxPages {
            print("🔄 Loading page \(currentPage) for search: '\(query)'")
            
            // Use the existing search API method with larger batch size for shuffle
            await api.updateMarkersFromSearch(query: query, page: currentPage, appendResults: false, perPage: 500)
            let newMarkers = api.markers
            
            print("📊 Page \(currentPage): API returned \(newMarkers.count) markers")
            
            // Debug: Print first few markers to verify they match the search
            if !newMarkers.isEmpty {
                let sampleMarkers = Array(newMarkers.prefix(3))
                for (index, marker) in sampleMarkers.enumerated() {
                    let matchesQuery = marker.title.lowercased().contains(query.lowercased()) ||
                                     marker.primary_tag.name.lowercased().contains(query.lowercased()) ||
                                     marker.tags.contains { $0.name.lowercased().contains(query.lowercased()) }
                    print("📊 Sample marker \(index + 1): '\(marker.title)' - Tag: '\(marker.primary_tag.name)' - Matches '\(query)': \(matchesQuery)")
                }
            }
            
            if newMarkers.isEmpty {
                print("📄 No more markers found on page \(currentPage), stopping")
                break
            }
            
            // Filter out duplicates and add new markers
            let uniqueNewMarkers = newMarkers.filter { newMarker in
                !allMarkers.contains { $0.id == newMarker.id }
            }
            
            allMarkers.append(contentsOf: uniqueNewMarkers)
            print("🔄 Page \(currentPage): Added \(uniqueNewMarkers.count) unique markers (total: \(allMarkers.count))")
            
            // If we got fewer than 500 markers, we've reached the end
            if newMarkers.count < 500 {
                print("📄 Got \(newMarkers.count) markers (less than 500), reached end of results")
                break
            }
            
            currentPage += 1
        }
        
        await MainActor.run {
            self.api.isLoading = false
            
            if allMarkers.isEmpty {
                print("⚠️ No markers found for search: '\(query)'")
                self.stopMarkerShuffle()
                return
            }
            
            // Debug: Final verification that all markers match the query
            print("🔍 Final verification of shuffle queue for query: '\(query)'")
            let matchingMarkers = allMarkers.filter { marker in
                marker.title.lowercased().contains(query.lowercased()) ||
                marker.primary_tag.name.lowercased().contains(query.lowercased()) ||
                marker.tags.contains { $0.name.lowercased().contains(query.lowercased()) }
            }
            print("🔍 Total markers: \(allMarkers.count), Matching query: \(matchingMarkers.count)")
            
            if matchingMarkers.count != allMarkers.count {
                print("⚠️ WARNING: Not all markers match the search query!")
                // Use only the matching markers
                self.markerShuffleQueue = matchingMarkers.shuffled()
            } else {
                self.markerShuffleQueue = allMarkers.shuffled()
            }
            
            self.currentShuffleIndex = 0
            
            print("✅ Created shuffle queue with \(self.markerShuffleQueue.count) markers for search: '\(query)'")
            
            // Start playing first marker
            if let firstMarker = self.markerShuffleQueue.first {
                print("🎬 Starting playback with first shuffled marker: \(firstMarker.title)")
                print("🎬 Current navigation path count: \(self.navigationPath.count)")
                
                // Check if we're already in a video player context
                if !self.navigationPath.isEmpty {
                    print("🔄 Already in navigation context - using direct marker update instead of navigation")
                    self.currentMarker = firstMarker
                    
                    // Set marker context flags
                    UserDefaults.standard.set(true, forKey: "scene_\(firstMarker.scene.id)_isMarkerNavigation")
                    UserDefaults.standard.set(Double(firstMarker.seconds), forKey: "scene_\(firstMarker.scene.id)_startTime")
                    if let endSeconds = firstMarker.end_seconds {
                        UserDefaults.standard.set(Double(endSeconds), forKey: "scene_\(firstMarker.scene.id)_endTime")
                    }
                    
                    // Update the current scene in navigation path instead of adding new one
                    self.navigateToMarker(firstMarker)                } else {
                    self.navigateToMarker(firstMarker)
                }
            }
        }
    }
    
    /// Load all markers for a tag with pagination
    private func loadAllMarkersForTag(tagId: String, tagName: String) async {
        print("🔄 Loading ALL markers for tag: \(tagName)")
        
        var allMarkers: [SceneMarker] = []
        var currentPage = 1
        let maxPages = 10 // Reasonable limit to prevent infinite loops
        
        while currentPage <= maxPages {
            print("🔄 Loading page \(currentPage) for tag: \(tagName)")
            
            // Use the existing tag API method with larger batch size for shuffle
            await api.fetchMarkersByTag(tagId: tagId, page: currentPage, appendResults: false, perPage: 500)
            let newMarkers = api.markers
            
            if newMarkers.isEmpty {
                print("📄 No more markers found on page \(currentPage), stopping")
                break
            }
            
            // Filter out duplicates and add new markers
            let uniqueNewMarkers = newMarkers.filter { newMarker in
                !allMarkers.contains { $0.id == newMarker.id }
            }
            
            allMarkers.append(contentsOf: uniqueNewMarkers)
            print("🔄 Page \(currentPage): Added \(uniqueNewMarkers.count) unique markers (total: \(allMarkers.count))")
            
            // Stop if we're getting API errors (no new unique markers)
            if uniqueNewMarkers.isEmpty {
                print("📄 No new unique markers added (API error or end of results), stopping")
                break
            }
            
            // If we got fewer than 500 markers, we've reached the end
            if newMarkers.count < 500 {
                print("📄 Got \(newMarkers.count) markers (less than 500), reached end of results")
                break
            }
            
            currentPage += 1
        }
        
        await MainActor.run {
            self.api.isLoading = false
            
            if allMarkers.isEmpty {
                print("⚠️ No markers found for tag: \(tagName)")
                self.stopMarkerShuffle()
                return
            }
            
            // Verify markers actually match the expected tag
            let matchingMarkers = allMarkers.filter { marker in
                marker.primary_tag.id == tagId || marker.tags.contains { $0.id == tagId }
            }
            
            print("🔍 Total markers retrieved: \(allMarkers.count)")
            print("🔍 Markers matching tag '\(tagName)': \(matchingMarkers.count)")
            
            if matchingMarkers.count != allMarkers.count {
                print("⚠️ WARNING: API returned markers that don't match the tag filter!")
                // Use only the matching markers
                self.markerShuffleQueue = matchingMarkers.shuffled()
            } else {
                self.markerShuffleQueue = allMarkers.shuffled()
            }
            
            self.currentShuffleIndex = 0
            
            print("✅ Created shuffle queue with \(self.markerShuffleQueue.count) markers for tag: \(tagName)")
            
            // Start playing first marker
            if let firstMarker = self.markerShuffleQueue.first {
                print("🎬 Starting playback with first shuffled marker: \(firstMarker.title) (tag: \(firstMarker.primary_tag.name))")
                print("🎬 Current navigation path count: \(self.navigationPath.count)")
                
                // Check if we're already in a video player context
                if !self.navigationPath.isEmpty {
                    print("🔄 Already in navigation context - using direct marker update instead of navigation")
                    self.currentMarker = firstMarker
                    
                    // Set marker context flags
                    UserDefaults.standard.set(true, forKey: "scene_\(firstMarker.scene.id)_isMarkerNavigation")
                    UserDefaults.standard.set(Double(firstMarker.seconds), forKey: "scene_\(firstMarker.scene.id)_startTime")
                    if let endSeconds = firstMarker.end_seconds {
                        UserDefaults.standard.set(Double(endSeconds), forKey: "scene_\(firstMarker.scene.id)_endTime")
                    }
                    
                    self.navigateToMarker(firstMarker)
                } else {
                    self.navigateToMarker(firstMarker)
                }
            }
        }
    }
    
    /// Get next marker in shuffle queue with balanced tag rotation
    func nextMarkerInShuffle() -> SceneMarker? {
        print("🎲 DEBUG: nextMarkerInShuffle() called")
        print("🎲 DEBUG: isMarkerShuffleMode = \(isMarkerShuffleMode)")
        print("🎲 DEBUG: markerShuffleQueue.count = \(markerShuffleQueue.count)")
        
        guard isMarkerShuffleMode && !markerShuffleQueue.isEmpty else {
            print("🎲 DEBUG: Guard failed - returning nil")
            return nil
        }
        
        // Group markers by tag if not already done
        if tagMarkerGroups.isEmpty {
            print("🎲 DEBUG: tagMarkerGroups is empty, calling groupMarkersByTag()")
            groupMarkersByTag()
        } else {
            print("🎲 DEBUG: tagMarkerGroups already has \(tagMarkerGroups.count) tag groups")
        }
        
        // If we only have one tag or no tag groups, fall back to true random
        if tagMarkerGroups.count <= 1 {
            print("🎲 DEBUG: Only \(tagMarkerGroups.count) tag group(s) - using true random")
            let randomIndex = Int.random(in: 0..<markerShuffleQueue.count)
            let nextMarker = markerShuffleQueue[randomIndex]
            print("🎲 Single tag shuffle - random marker: \(nextMarker.title)")
            updateRecentMarkers(nextMarker)
            return nextMarker
        }
        
        // BALANCED TAG ROTATION: Use round-robin to ensure fair tag distribution
        if tagRotationOrder.isEmpty {
            // Initialize rotation order (sorted for consistency)
            tagRotationOrder = Array(tagMarkerGroups.keys).sorted()
            currentTagIndex = 0
            print("🎲 Initialized tag rotation order: \(tagRotationOrder.joined(separator: " -> "))")
        }
        
        let selectedTag = tagRotationOrder[currentTagIndex]
        let markersForTag = tagMarkerGroups[selectedTag]!
        
        // Advance to next tag for next time (round-robin)
        currentTagIndex = (currentTagIndex + 1) % tagRotationOrder.count
        print("🎲 Selected tag '\(selectedTag)' (round-robin index: \(currentTagIndex - 1)), next will be '\(tagRotationOrder[currentTagIndex])'")
        
        // Determine repeat prevention based on tag size - enhanced for large pools
        let tagSize = markersForTag.count
        let maxRecentMarkers: Int
        if tagSize <= 10 {
            // Small tags: allow repeats after 2-3 selections
            maxRecentMarkers = max(2, tagSize / 2)
        } else if tagSize <= 50 {
            // Medium tags: avoid repeats for 10-15 selections  
            maxRecentMarkers = min(15, tagSize / 3)
        } else if tagSize <= 150 {
            // Large tags: avoid repeats for 25-30 selections
            maxRecentMarkers = min(30, tagSize / 5)
        } else {
            // Very large tags: avoid repeats for 40-50 selections
            maxRecentMarkers = min(50, tagSize / 8)
        }
        
        print("🎲 Tag '\(selectedTag)' (size: \(tagSize)) using maxRecentMarkers: \(maxRecentMarkers)")
        
        // Filter out recently played markers for this tag based on the calculated limit
        let availableMarkers = markersForTag.filter { marker in
            !recentMarkerIds.contains(marker.id)
        }
        
        print("🎲 Tag '\(selectedTag)': \(markersForTag.count) total, \(availableMarkers.count) available, \(recentMarkerIds.count) recent")
        
        let nextMarker: SceneMarker
        
        if availableMarkers.isEmpty {
            // All markers have been played recently, pick any marker from the tag
            nextMarker = markersForTag.randomElement()!
            print("🎲 All markers recently played for tag '\(selectedTag)' (size: \(tagSize)) - selecting any: \(nextMarker.title)")
            // Reset recent markers for this tag to start fresh
            let tagMarkerIds = Set(markersForTag.map { $0.id })
            recentMarkerIds = recentMarkerIds.subtracting(tagMarkerIds)
        } else {
            // Pick from available (non-recent) markers
            nextMarker = availableMarkers.randomElement()!
            print("🎲 Balanced tag '\(selectedTag)' (size: \(tagSize), available: \(availableMarkers.count)): \(nextMarker.title) [tag: \(nextMarker.primary_tag.name)]")
        }
        
        // Update recent markers tracking
        updateRecentMarkers(nextMarker)
        
        return nextMarker
    }
    
    /// Group markers in shuffle queue by their primary tag
    private func groupMarkersByTag() {
        tagMarkerGroups.removeAll()
        
        for marker in markerShuffleQueue {
            let tagName = marker.primary_tag.name
            if tagMarkerGroups[tagName] == nil {
                tagMarkerGroups[tagName] = []
            }
            tagMarkerGroups[tagName]?.append(marker)
        }
        
        print("🎲 Grouped \(markerShuffleQueue.count) markers into \(tagMarkerGroups.count) tags:")
        for (tagName, markers) in tagMarkerGroups.sorted(by: { $0.value.count > $1.value.count }) {
            print("  - \(tagName): \(markers.count) markers")
        }
    }
    
    /// Update recent markers tracking with smart cleanup
    private func updateRecentMarkers(_ marker: SceneMarker) {
        recentMarkerIds.insert(marker.id)
        
        // Determine the tag size for this marker's tag using the same smart logic as nextMarkerInShuffle
        let tagName = marker.primary_tag.name
        let tagSize = tagMarkerGroups[tagName]?.count ?? 1
        let maxRecentMarkers: Int
        if tagSize <= 10 {
            maxRecentMarkers = max(2, tagSize / 2)
        } else if tagSize <= 50 {
            maxRecentMarkers = min(15, tagSize / 3)
        } else if tagSize <= 150 {
            maxRecentMarkers = min(30, tagSize / 5)
        } else {
            maxRecentMarkers = min(50, tagSize / 8)
        }
        
        // Calculate total allowed recent markers across all tags
        let totalMaxRecent = tagMarkerGroups.values.reduce(0) { total, markers in
            let tagSize = markers.count
            let tagMaxRecent: Int
            if tagSize <= 10 {
                tagMaxRecent = max(2, tagSize / 2)
            } else if tagSize <= 50 {
                tagMaxRecent = min(15, tagSize / 3)
            } else if tagSize <= 150 {
                tagMaxRecent = min(30, tagSize / 5)
            } else {
                tagMaxRecent = min(50, tagSize / 8)
            }
            return total + tagMaxRecent
        }
        
        // If we have too many recent markers, remove the oldest ones
        if recentMarkerIds.count > totalMaxRecent {
            // Remove roughly 1/3 of the recent markers to free up space
            let removeCount = recentMarkerIds.count / 3
            let markersToRemove = Array(recentMarkerIds.prefix(removeCount))
            for markerId in markersToRemove {
                recentMarkerIds.remove(markerId)
            }
            print("🎲 Cleaned up recent markers - removed \(removeCount), now tracking \(recentMarkerIds.count) (max: \(totalMaxRecent))")
        }
        
        print("🎲 Added marker '\(marker.title)' to recent list (tag: \(tagName), size: \(tagSize), maxRecent: \(maxRecentMarkers))")
    }
    
    /// Reset balanced tag rotation tracking for new shuffle
    private func resetBalancedTagRotation() {
        tagMarkerGroups.removeAll()
        recentMarkerIds.removeAll()
        tagRotationOrder.removeAll()
        currentTagIndex = 0
        print("🎲 Reset balanced tag rotation tracking")
    }
    
    /// Get previous marker in shuffle queue
    func previousMarkerInShuffle() -> SceneMarker? {
        guard isMarkerShuffleMode && !markerShuffleQueue.isEmpty else {
            return nil
        }
        
        // Move to previous marker
        currentShuffleIndex = currentShuffleIndex > 0 ? currentShuffleIndex - 1 : markerShuffleQueue.count - 1
        let previousMarker = markerShuffleQueue[currentShuffleIndex]
        
        print("🎲 Previous marker in shuffle: \(previousMarker.title) (index \(currentShuffleIndex) of \(markerShuffleQueue.count))")
        return previousMarker
    }
    
    /// Jump to next marker in shuffle
    func shuffleToNextMarker() {
        print("🎲 shuffleToNextMarker called - current state:")
        print("🎲 isMarkerShuffleMode: \(isMarkerShuffleMode)")
        print("🎲 isServerSideShuffle: \(isServerSideShuffle)")
        print("🎲 markerShuffleQueue.count: \(markerShuffleQueue.count)")
        print("🎲 currentShuffleIndex: \(currentShuffleIndex)")
        
        // Check if we're using server-side shuffle
        if isServerSideShuffle {
            print("🎲 Using SERVER-SIDE shuffle - fetching random marker from server")
            Task {
                await playNextServerSideMarker()
            }
            return
        }
        
        // Original client-side shuffle logic
        guard let nextMarker = nextMarkerInShuffle() else {
            print("⚠️ No next marker available in shuffle")
            return
        }
        
        print("🎲 Shuffling to next marker: \(nextMarker.title)")
        print("🎲 Debug: Tag: \(nextMarker.primary_tag.name), Search Query: \(shuffleSearchQuery ?? "none")")
        if let query = shuffleSearchQuery {
            let matchesQuery = nextMarker.title.lowercased().contains(query.lowercased()) ||
                             nextMarker.primary_tag.name.lowercased().contains(query.lowercased()) ||
                             nextMarker.tags.contains { $0.name.lowercased().contains(query.lowercased()) }
            print("🎲 Debug: Marker matches search '\(query)': \(matchesQuery)")
        }
        
        // Update current video player instead of navigating to new view
        updateVideoPlayerWithMarker(nextMarker)
    }
    
    /// Jump to previous marker in shuffle  
    func shuffleToPreviousMarker() {
        guard let previousMarker = previousMarkerInShuffle() else {
            print("⚠️ No previous marker available in shuffle")
            return
        }
        
        print("🎲 Shuffling to previous marker: \(previousMarker.title)")
        
        // Update current video player instead of navigating to new view
        updateVideoPlayerWithMarker(previousMarker)
    }
    
    /// Start marker shuffle with provided markers (simple version)
    func startMarkerShuffle(withMarkers markers: [SceneMarker]) {
        print("🎲 Starting simple marker shuffle with \(markers.count) markers")
        
        // Set shuffle context
        isMarkerShuffleMode = true
        shuffleTagFilter = nil
        shuffleSearchQuery = "direct_markers"
        UserDefaults.standard.set(true, forKey: "isMarkerShuffleContext")
        
        // Reset balanced tag rotation tracking
        resetBalancedTagRotation()
        
        // Create shuffled queue immediately
        markerShuffleQueue = markers.shuffled()
        currentShuffleIndex = 0
        
        print("✅ Created shuffle queue with \(markerShuffleQueue.count) markers")
        
        // Start playing first marker
        if let firstMarker = markerShuffleQueue.first {
            print("🎬 Starting playback with first shuffled marker: \(firstMarker.title)")
            print("🎬 Current navigation path count: \(navigationPath.count)")
            
            // Check if we're already in a video player context
            if !navigationPath.isEmpty {
                print("🔄 Already in navigation context - using direct marker update instead of navigation")
                currentMarker = firstMarker
                
                // Set marker context flags
                UserDefaults.standard.set(true, forKey: "scene_\(firstMarker.scene.id)_isMarkerNavigation")
                UserDefaults.standard.set(Double(firstMarker.seconds), forKey: "scene_\(firstMarker.scene.id)_startTime")
                if let endSeconds = firstMarker.end_seconds {
                    UserDefaults.standard.set(Double(endSeconds), forKey: "scene_\(firstMarker.scene.id)_endTime")
                }
                
                navigateToMarker(firstMarker)
            } else {
                navigateToMarker(firstMarker)
            }
        } else {
            print("⚠️ No markers to shuffle")
            stopMarkerShuffle()
        }
    }
    
    /// Stop marker shuffle mode
    func stopMarkerShuffle() {
        print("🛑 Stopping marker shuffle mode")
        isMarkerShuffleMode = false
        markerShuffleQueue.removeAll()
        currentShuffleIndex = 0
        shuffleTagFilter = nil
        shuffleSearchQuery = nil
        UserDefaults.standard.set(false, forKey: "isMarkerShuffleContext")
        UserDefaults.standard.set(false, forKey: "isMarkerShuffleMode")
        UserDefaults.standard.removeObject(forKey: "currentShuffleTagNames")
        UserDefaults.standard.removeObject(forKey: "currentShuffleSearchQuery")
        
        // Reset balanced tag rotation tracking
        resetBalancedTagRotation()
    }
    
    /// Simple marker shuffle that relies on server-side GraphQL calls
    func startSimpleMarkerShuffle(tagNames: [String]? = nil, searchQuery: String? = nil) {
        print("🎲 Starting simple marker shuffle")
        
        // Enable shuffle mode
        isMarkerShuffleMode = true
        currentShuffleIndex = 0
        markerShuffleQueue.removeAll()
        
        // Reset balanced tag rotation tracking
        resetBalancedTagRotation()
        
        // Store the shuffle context for server-side calls
        if let tagNames = tagNames {
            print("🎲 Simple shuffle for tags: \(tagNames.joined(separator: ", "))")
            // For multi-tag shuffle, we'll use the first tag as primary and store others for server calls
            shuffleTagFilter = tagNames.first
            UserDefaults.standard.set(tagNames, forKey: "currentShuffleTagNames")
        } else if let searchQuery = searchQuery {
            print("🎲 Simple shuffle for search: '\(searchQuery)'")
            shuffleSearchQuery = searchQuery
            UserDefaults.standard.set(searchQuery, forKey: "currentShuffleSearchQuery")
        }
        
        UserDefaults.standard.set(true, forKey: "isMarkerShuffleMode")
        
        // Start by fetching first batch of markers from server
        Task {
            await fetchNextShuffleMarker()
        }
    }
    
    /// Fetch the next marker from server using GraphQL
    private func fetchNextShuffleMarker() async {
        guard isMarkerShuffleMode else { return }
        
        print("🎲 Fetching next shuffle marker from server")
        
        do {
            let markers: [SceneMarker]
            
            // Check if we have stored tag names or search query
            if let tagNames = UserDefaults.standard.array(forKey: "currentShuffleTagNames") as? [String], !tagNames.isEmpty {
                // Multi-tag shuffle - combine all selected tags
                print("🎲 Fetching markers for ALL tags: \(tagNames.joined(separator: ", "))")
                
                var allCombinedMarkers = Set<SceneMarker>()
                
                // Fetch markers for each tag and combine them
                for tagName in tagNames {
                    print("🎲 Fetching markers for tag: \(tagName)")
                    // Use exact tag search to only get markers that are actually tagged with this tag
                    let tagMarkers = try await api.searchMarkers(query: "#\(tagName)", page: 1, perPage: 100)
                    
                    // Filter to ONLY markers that have this tag as their PRIMARY marker tag
                    // This excludes scenes that are tagged with this tag but don't have markers for it
                    let exactMatches = tagMarkers.filter { marker in
                        // Only match if this tag is the marker's primary tag OR in the marker's tag list
                        // This ensures we only get actual MARKERS for this tag, not scenes tagged with it
                        marker.primary_tag.name.lowercased() == tagName.lowercased() ||
                        marker.tags.contains { $0.name.lowercased() == tagName.lowercased() }
                    }
                    
                    print("🎲 Found \(tagMarkers.count) total results for '\(tagName)', filtered to \(exactMatches.count) actual marker matches")
                    
                    print("🎲 Found \(exactMatches.count) exact matches for tag '\(tagName)'")
                    
                    for marker in exactMatches {
                        allCombinedMarkers.insert(marker)
                    }
                }
                
                markers = Array(allCombinedMarkers)
                print("🎲 Combined total: \(markers.count) unique markers from \(tagNames.count) tags")
            } else if let searchQuery = UserDefaults.standard.string(forKey: "currentShuffleSearchQuery") {
                print("🎲 Fetching markers for search query: '\(searchQuery)'")
                markers = try await api.searchMarkers(query: searchQuery, page: 1, perPage: 50)
            } else {
                print("🎲 No shuffle context found, stopping shuffle")
                await MainActor.run {
                    stopMarkerShuffle()
                }
                return
            }
            
            await MainActor.run {
                // Shuffle the markers and start with the first one
                markerShuffleQueue = markers.shuffled()
                print("🎲 Fetched and shuffled \(markerShuffleQueue.count) markers")
                
                // Debug: Show first few markers in queue
                print("🎲 DEBUG: First 3 markers in shuffle queue:")
                for (index, marker) in markerShuffleQueue.prefix(3).enumerated() {
                    print("  [\(index)] '\(marker.title)' (Scene: \(marker.scene.id), Tag: \(marker.primary_tag.name), Time: \(marker.seconds)s)")
                }
                
                if let firstMarker = markerShuffleQueue.first {
                    print("🎲 Starting shuffle with first marker: \(firstMarker.title)")
                    
                    // For the first marker in a new shuffle, use navigation to start the video player
                    // But for subsequent markers, we'll use updateVideoPlayerWithMarker
                    navigateToMarker(firstMarker)
                } else {
                    print("🎲 No markers found for shuffle")
                    stopMarkerShuffle()
                }
            }
        } catch {
            print("❌ Error fetching shuffle markers: \(error)")
            await MainActor.run {
                stopMarkerShuffle()
            }
        }
    }
    
    /// Update current video player with new marker without navigation
    func updateVideoPlayerWithMarker(_ marker: SceneMarker) {
        print("🎲 PLAYER UPDATE - Updating current video player with marker: \(marker.title)")
        print("🎲 DEBUG MARKER DATA:")
        print("  - Title: '\(marker.title)'")
        print("  - Scene ID: \(marker.scene.id)")
        print("  - Timestamp: \(marker.seconds)s")
        print("  - Primary Tag: '\(marker.primary_tag.name)'")
        print("  - Stream URL: '\(marker.stream ?? "nil")'")
        print("  - Screenshot: '\(marker.screenshot ?? "nil")'")
        
        // Update current marker state
        currentMarker = marker
        
        // Create scene data for the marker
        let markerScene = StashScene(
            id: marker.scene.id,
            title: marker.title.isEmpty ? marker.scene.title : marker.title,
            details: nil,
            paths: StashScene.ScenePaths(
                screenshot: marker.screenshot,
                preview: marker.preview,
                stream: marker.stream
            ),
            files: [],
            performers: marker.scene.performers ?? [],
            tags: [],
            rating100: nil,
            o_counter: nil
        )
        
        // Update current scene without navigation
        currentScene = markerScene
        
        // DON'T kill audio here - let the video player handle the transition
        // killAllAudio() was destroying the player before the notification could update it
        
        // Send notification to update the video player with new content
        let notificationInfo = [
            "marker": marker,
            "scene": markerScene,
            "startTime": marker.seconds
        ] as [String : Any]
        
        // Use a small delay to ensure the notification is processed after any cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(
                name: Notification.Name("UpdateVideoPlayerWithMarker"), 
                object: nil, 
                userInfo: notificationInfo
            )
            print("🎲 PLAYER UPDATE - Sent notification to update video player with scene \(markerScene.id) at \(marker.seconds) seconds")
        }
    }
    
    /// Auto-start marker shuffle when navigating to a marker from search
    private func startAutoMarkerShuffle(for marker: SceneMarker) async {
        let tagId = marker.primary_tag.id
        let tagName = marker.primary_tag.name
        
        print("🎲 Auto-starting marker shuffle - fetching markers for tag: \(tagName)")
        
        // Set shuffle context first
        await MainActor.run {
            isMarkerShuffleMode = true
            shuffleTagFilter = tagId
            shuffleSearchQuery = nil
            UserDefaults.standard.set(true, forKey: "isMarkerShuffleContext")
            UserDefaults.standard.set(true, forKey: "isMarkerShuffleMode")
        }
        
        // Fetch markers for this tag from server (limited for performance)
        do {
            var allTagMarkers: [SceneMarker] = []
            var currentPage = 1
            let maxPages = 5 // Reduced from 20 to prevent freezing
            let maxMarkers = 1000 // Cap at 1000 markers for performance
            
            while currentPage <= maxPages && allTagMarkers.count < maxMarkers {
                print("🔄 Loading page \(currentPage) for tag: \(tagName)")
                
                // Use smaller batch size for better responsiveness
                await api.fetchMarkersByTag(tagId: tagId, page: currentPage, appendResults: false, perPage: 200)
                let newMarkers = api.markers
                
                if newMarkers.isEmpty {
                    print("📄 No more markers found on page \(currentPage), stopping")
                    break
                }
                
                // Add unique markers to avoid duplicates
                let uniqueMarkers = newMarkers.filter { newMarker in
                    !allTagMarkers.contains { $0.id == newMarker.id }
                }
                allTagMarkers.append(contentsOf: uniqueMarkers)
                
                print("📊 Page \(currentPage): Found \(newMarkers.count) markers, \(uniqueMarkers.count) unique (Total: \(allTagMarkers.count))")
                
                // If we got less than the full page size, we're done
                if newMarkers.count < 200 {
                    break
                }
                
                currentPage += 1
                
                // Add small delay to prevent overwhelming the server
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
            
            await MainActor.run {
                // Create shuffled queue
                self.markerShuffleQueue = allTagMarkers.shuffled()
                
                // Find the current marker in the queue and set that as starting point
                if let currentIndex = self.markerShuffleQueue.firstIndex(where: { $0.id == marker.id }) {
                    self.currentShuffleIndex = currentIndex
                    print("🎯 Found current marker at shuffled index \(currentIndex)")
                } else {
                    self.currentShuffleIndex = 0
                    print("⚠️ Current marker not found in queue, starting at index 0")
                }
                
                print("✅ Auto-shuffle queue created with \(self.markerShuffleQueue.count) total markers for tag: \(tagName)")
            }
            
        } catch {
            print("❌ Error auto-starting marker shuffle: \(error)")
            await MainActor.run {
                // Reset shuffle state if failed
                self.stopMarkerShuffle()
            }
        }
    }
    
    /// Re-shuffle the current queue
    func reshuffleMarkerQueue() {
        guard isMarkerShuffleMode && !markerShuffleQueue.isEmpty else { return }
        
        print("🔀 Re-shuffling marker queue")
        markerShuffleQueue = markerShuffleQueue.shuffled()
        currentShuffleIndex = 0
        
        // Start playing the first marker from the newly shuffled queue 
        if let firstMarker = markerShuffleQueue.first {
            navigateToMarker(firstMarker)
        }
    }
    
    // MARK: - Tag Scene Shuffle System
    @Published var tagSceneShuffleQueue: [StashScene] = []
    @Published var currentTagShuffleIndex: Int = 0
    @Published var isTagSceneShuffleMode: Bool = false
    @Published var shuffleTagId: String? = nil
    
    // MARK: - Most Played Shuffle System
    @Published var mostPlayedShuffleQueue: [StashScene] = []
    @Published var currentMostPlayedShuffleIndex: Int = 0
    @Published var isMostPlayedShuffleMode: Bool = false
    
    /// Start tag scene shuffle for a specific tag
    func startTagSceneShuffle(forTag tagId: String, tagName: String, displayedScenes: [StashScene]) {
        print("🎲 Starting tag scene shuffle for tag: \(tagName)")
        
        // Set shuffle context
        isTagSceneShuffleMode = true
        shuffleTagId = tagId
        UserDefaults.standard.set(true, forKey: "isTagSceneShuffleContext")
        
        // Set loading state
        api.isLoading = true
        
        Task {
            await loadAllScenesForTag(tagId: tagId, tagName: tagName)
        }
    }
    
    /// Load all scenes for a tag with pagination
    private func loadAllScenesForTag(tagId: String, tagName: String) async {
        print("🔄 Loading ALL scenes for tag: '\(tagName)'")
        
        var allScenes: [StashScene] = []
        var currentPage = 1
        let maxPages = 10 // Limit to prevent performance issues
        
        while currentPage <= maxPages {
            print("🔄 Loading page \(currentPage) for tag: '\(tagName)'")
            
            do {
                let scenes = try await api.fetchTaggedScenes(tagId: tagId, page: currentPage, perPage: 100)
                
                print("📊 Page \(currentPage): API returned \(scenes.count) scenes")
                
                if scenes.isEmpty {
                    print("📄 No more scenes found on page \(currentPage), stopping")
                    break
                }
                
                // Filter out duplicates and add new scenes
                let uniqueNewScenes = scenes.filter { newScene in
                    !allScenes.contains { $0.id == newScene.id }
                }
                
                allScenes.append(contentsOf: uniqueNewScenes)
                print("🔄 Page \(currentPage): Added \(uniqueNewScenes.count) unique scenes (total: \(allScenes.count))")
                
                // If we got fewer than the per_page amount, we've reached the end
                if scenes.count < 100 { // Now checking against 100 per page
                    print("📄 Reached the end of results (got \(scenes.count) scenes)")
                    break
                }
                
                currentPage += 1
            } catch {
                print("❌ Error loading scenes for tag: \(error)")
                break
            }
        }
        
        print("✅ Loaded total of \(allScenes.count) scenes for tag '\(tagName)'")
        
        // Create shuffled queue
        await MainActor.run {
            // Show success message briefly
            if allScenes.count > 0 {
                print("✅ Successfully loaded \(allScenes.count) scenes for shuffle")
            }
            tagSceneShuffleQueue = allScenes.shuffled()
            currentTagShuffleIndex = 0
            api.isLoading = false
            
            // Start playing first scene
            if let firstScene = tagSceneShuffleQueue.first {
                print("🎬 Starting playback with first shuffled scene: \(firstScene.title ?? "Untitled")")
                print("🎬 Scene ID: \(firstScene.id)")
                print("🎬 Total scenes in shuffle queue: \(tagSceneShuffleQueue.count)")
                
                // Ensure we're setting the shuffle mode flag
                UserDefaults.standard.set(true, forKey: "isTagSceneShuffleMode")
                
                // Clear any search UI state to ensure clean navigation
                self.searchQuery = ""
                
                // Small delay to ensure UI is ready and search UI is dismissed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    print("🎬 Navigating to scene now...")
                    self.navigateToScene(firstScene)
                }
            } else {
                print("⚠️ No scenes to shuffle")
                stopTagSceneShuffle()
            }
        }
    }
    
    /// Get next scene in shuffle
    private func nextSceneInShuffle() -> StashScene? {
        guard isTagSceneShuffleMode && !tagSceneShuffleQueue.isEmpty else {
            return nil
        }
        
        currentTagShuffleIndex = (currentTagShuffleIndex + 1) % tagSceneShuffleQueue.count
        return tagSceneShuffleQueue[currentTagShuffleIndex]
    }
    
    /// Get previous scene in shuffle
    private func previousSceneInShuffle() -> StashScene? {
        guard isTagSceneShuffleMode && !tagSceneShuffleQueue.isEmpty else {
            return nil
        }
        
        currentTagShuffleIndex = currentTagShuffleIndex > 0 ? currentTagShuffleIndex - 1 : tagSceneShuffleQueue.count - 1
        return tagSceneShuffleQueue[currentTagShuffleIndex]
    }
    
    /// Jump to next scene in shuffle
    func shuffleToNextTagScene() {
        print("🎲 shuffleToNextTagScene called")
        
        guard let nextScene = nextSceneInShuffle() else {
            print("⚠️ No next scene available in shuffle")
            return
        }
        
        print("🎲 Shuffling to next scene: \(nextScene.title)")
        
        print("🎲 Preparing for tag shuffle - updating current video player")
        
        // Use the same approach as marker shuffle - update the existing VideoPlayerView instead of navigating
        // Convert to HLS URL format
        let hlsStreamURL = nextScene.paths.stream
            .replacingOccurrences(of: "/stream?", with: "/stream.m3u8?")
            .appending("&resolution=ORIGINAL&_ts=\(Int(Date().timeIntervalSince1970))")
        
        print("🎲 Tag shuffle HLS URL: \(hlsStreamURL)")
        
        // Post a notification to update the current VideoPlayerView instead of navigating
        NotificationCenter.default.post(
            name: NSNotification.Name("UpdateVideoPlayerForTagShuffle"),
            object: nil,
            userInfo: [
                "scene": nextScene,
                "hlsURL": hlsStreamURL
            ]
        )
        
        print("🔄 Posted notification to update current video player for tag shuffle")
    }
    
    /// Jump to previous scene in shuffle
    func shuffleToPreviousTagScene() {
        guard let previousScene = previousSceneInShuffle() else {
            print("⚠️ No previous scene available in shuffle")
            return
        }
        
        print("🎲 Shuffling to previous scene: \(previousScene.title)")
        
        print("🎲 Preparing for tag shuffle to previous - updating current video player")
        
        // Use the same approach as marker shuffle - update the existing VideoPlayerView instead of navigating
        // Convert to HLS URL format
        let hlsStreamURL = previousScene.paths.stream
            .replacingOccurrences(of: "/stream?", with: "/stream.m3u8?")
            .appending("&resolution=ORIGINAL&_ts=\(Int(Date().timeIntervalSince1970))")
        
        print("🎲 Tag shuffle previous HLS URL: \(hlsStreamURL)")
        
        // Post a notification to update the current VideoPlayerView instead of navigating
        NotificationCenter.default.post(
            name: NSNotification.Name("UpdateVideoPlayerForTagShuffle"),
            object: nil,
            userInfo: [
                "scene": previousScene,
                "hlsURL": hlsStreamURL
            ]
        )
        
        print("🔄 Posted notification to update current video player for tag shuffle previous")
    }
    
    /// Stop tag scene shuffle mode
    func stopTagSceneShuffle() {
        print("🛑 Stopping tag scene shuffle mode")
        isTagSceneShuffleMode = false
        tagSceneShuffleQueue.removeAll()
        currentTagShuffleIndex = 0
        shuffleTagId = nil
        UserDefaults.standard.set(false, forKey: "isTagSceneShuffleContext")
        UserDefaults.standard.set(false, forKey: "isTagSceneShuffleMode")
    }
    
    // MARK: - Most Played Shuffle Functions
    
    /// Start most played shuffle mode with all scenes that have o_counter > 0
    func startMostPlayedShuffle(from allScenes: [StashScene]) {
        print("🎯 Starting most played shuffle mode")
        
        // Filter to only scenes with o_counter > 0
        let mostPlayedScenes = allScenes.filter { scene in
            if let oCounter = scene.o_counter, oCounter > 0 {
                return true
            }
            return false
        }
        
        guard !mostPlayedScenes.isEmpty else {
            print("⚠️ No scenes with play count found")
            return
        }
        
        // Set shuffle context
        isMostPlayedShuffleMode = true
        UserDefaults.standard.set(true, forKey: "isMostPlayedShuffleMode")
        UserDefaults.standard.set(true, forKey: "isRandomJumpMode")
        
        // Create shuffled queue
        mostPlayedShuffleQueue = mostPlayedScenes.shuffled()
        currentMostPlayedShuffleIndex = 0
        
        print("✅ Created most played shuffle queue with \(mostPlayedShuffleQueue.count) scenes")
        
        // Start playing first scene
        if let firstScene = mostPlayedShuffleQueue.first {
            print("🎯 Starting playback with first most played scene: \(firstScene.title ?? "Untitled") (o_counter: \(firstScene.o_counter ?? 0))")
            navigateToScene(firstScene)
            
            // Jump to random position after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if let player = VideoPlayerRegistry.shared.currentPlayer {
                    VideoPlayerUtility.jumpToRandomPosition(in: player)
                }
            }
        }
    }
    
    /// Get next scene in most played shuffle
    private func nextMostPlayedScene() -> StashScene? {
        guard isMostPlayedShuffleMode && !mostPlayedShuffleQueue.isEmpty else {
            return nil
        }
        
        currentMostPlayedShuffleIndex = (currentMostPlayedShuffleIndex + 1) % mostPlayedShuffleQueue.count
        return mostPlayedShuffleQueue[currentMostPlayedShuffleIndex]
    }
    
    /// Get previous scene in most played shuffle
    private func previousMostPlayedScene() -> StashScene? {
        guard isMostPlayedShuffleMode && !mostPlayedShuffleQueue.isEmpty else {
            return nil
        }
        
        currentMostPlayedShuffleIndex = currentMostPlayedShuffleIndex > 0 ? currentMostPlayedShuffleIndex - 1 : mostPlayedShuffleQueue.count - 1
        return mostPlayedShuffleQueue[currentMostPlayedShuffleIndex]
    }
    
    /// Jump to next scene in most played shuffle
    func shuffleToNextMostPlayedScene() {
        print("🎯 shuffleToNextMostPlayedScene called")
        
        guard let nextScene = nextMostPlayedScene() else {
            print("⚠️ No next scene available in most played shuffle")
            return
        }
        
        print("🎯 Shuffling to next most played scene: \(nextScene.title ?? "Untitled") (o_counter: \(nextScene.o_counter ?? 0))")
        
        // Use the same approach as tag shuffle - update the existing VideoPlayerView
        let hlsStreamURL = nextScene.paths.stream
            .replacingOccurrences(of: "/stream?", with: "/stream.m3u8?")
            .appending("&resolution=ORIGINAL&_ts=\(Int(Date().timeIntervalSince1970))")
        
        print("🎯 Most played shuffle HLS URL: \(hlsStreamURL)")
        
        // Post notification to update current video player
        NotificationCenter.default.post(
            name: NSNotification.Name("UpdateVideoPlayerForMostPlayedShuffle"),
            object: nil,
            userInfo: [
                "scene": nextScene,
                "hlsURL": hlsStreamURL
            ]
        )
        
        // Jump to random position after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if let player = VideoPlayerRegistry.shared.currentPlayer {
                VideoPlayerUtility.jumpToRandomPosition(in: player)
            }
        }
        
        print("🔄 Posted notification to update current video player for most played shuffle")
    }
    
    /// Jump to previous scene in most played shuffle
    func shuffleToPreviousMostPlayedScene() {
        guard let previousScene = previousMostPlayedScene() else {
            print("⚠️ No previous scene available in most played shuffle")
            return
        }
        
        print("🎯 Shuffling to previous most played scene: \(previousScene.title ?? "Untitled")")
        
        // Use same approach as next scene
        let hlsStreamURL = previousScene.paths.stream
            .replacingOccurrences(of: "/stream?", with: "/stream.m3u8?")
            .appending("&resolution=ORIGINAL&_ts=\(Int(Date().timeIntervalSince1970))")
        
        NotificationCenter.default.post(
            name: NSNotification.Name("UpdateVideoPlayerForMostPlayedShuffle"),
            object: nil,
            userInfo: [
                "scene": previousScene,
                "hlsURL": hlsStreamURL
            ]
        )
        
        // Jump to random position after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if let player = VideoPlayerRegistry.shared.currentPlayer {
                VideoPlayerUtility.jumpToRandomPosition(in: player)
            }
        }
    }
    
    /// Stop most played shuffle mode
    func stopMostPlayedShuffle() {
        print("🛑 Stopping most played shuffle mode")
        isMostPlayedShuffleMode = false
        mostPlayedShuffleQueue.removeAll()
        currentMostPlayedShuffleIndex = 0
        UserDefaults.standard.set(false, forKey: "isMostPlayedShuffleMode")
        UserDefaults.standard.set(false, forKey: "isRandomJumpMode")
    }
    
    // MARK: - Gender-Aware Performer Shuffle
    
    /// Shuffle scenes with gender-aware filtering
    /// Defaults to female performers unless explicitly on a male performer's page
    func shufflePerformerScenes(fromScenes scenes: [StashScene], currentPerformer: StashScene.Performer? = nil) {
        print("🎭 Starting gender-aware performer shuffle")
        
        // Determine if we should default to female performers
        let shouldDefaultToFemale = shouldDefaultToFemalePerformers(currentPerformer: currentPerformer)
        let targetGender = shouldDefaultToFemale ? "FEMALE" : nil
        
        print("🎭 Gender filtering - shouldDefaultToFemale: \(shouldDefaultToFemale), targetGender: \(targetGender ?? "any")")
        print("🎭 Current performer context: \(currentPerformer?.name ?? "none") (gender: \(currentPerformer?.gender ?? "unknown"))")
        
        // Filter scenes based on performer gender preference
        let filteredScenes: [StashScene]
        if let gender = targetGender {
            filteredScenes = scenes.filter { scene in
                scene.performers.contains { performer in
                    performer.gender?.uppercased() == gender
                }
            }
            print("🎭 Filtered to \(filteredScenes.count) scenes with \(gender.lowercased()) performers (from \(scenes.count) total)")
        } else {
            // If we're explicitly on a performer's page, use their scenes
            filteredScenes = scenes
            print("🎭 Using all \(scenes.count) scenes (performer-specific context)")
        }
        
        guard !filteredScenes.isEmpty else {
            print("⚠️ No scenes found matching gender criteria")
            // Fallback to all scenes if gender filtering produces no results
            performBasicSceneShuffle(fromScenes: scenes)
            return
        }
        
        // Perform the shuffle
        performBasicSceneShuffle(fromScenes: filteredScenes)
    }
    
    /// Determine if we should default to female performers based on context
    private func shouldDefaultToFemalePerformers(currentPerformer: StashScene.Performer?) -> Bool {
        // If we have a current performer context, check their gender
        if let performer = currentPerformer ?? performerDetailViewPerformer {
            let performerGender = performer.gender?.uppercased()
            let isMalePerformer = performerGender == "MALE"
            
            print("🎭 Performer context detected: \(performer.name) (gender: \(performerGender ?? "unknown"))")
            print("🎭 Is male performer: \(isMalePerformer)")
            
            // Only default to male if we're explicitly on a male performer's page
            return !isMalePerformer
        }
        
        // No specific performer context - default to female
        print("🎭 No performer context - defaulting to female performers")
        return true
    }
    
    /// Basic scene shuffle logic (extracted for reuse)
    private func performBasicSceneShuffle(fromScenes scenes: [StashScene]) {
        guard let randomScene = scenes.randomElement() else {
            print("⚠️ Could not get random scene from \(scenes.count) scenes")
            return
        }
        
        print("🎲 Selected random scene: \(randomScene.title ?? "Untitled") from \(scenes.count) available scenes")
        
        // Set random jump mode for future navigation
        UserDefaults.standard.set(true, forKey: "isRandomJumpMode")
        print("🎲 Enabled random jump mode for future navigation")
        
        // Navigate to the scene
        navigateToScene(randomScene)
        
        // Jump to random position after player initialization
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if let player = VideoPlayerRegistry.shared.currentPlayer {
                print("🎲 Jumping to random position in shuffled scene")
                VideoPlayerUtility.jumpToRandomPosition(in: player)
            } else {
                print("⚠️ No player available for random jump")
            }
        }
    }
}

// MARK: - Types
extension AppModel {
    enum Tab: String, CaseIterable {
        case scenes = "Scenes"
        case performers = "Performers"
        case history = "History"
        
        var icon: String {
            switch self {
            case .scenes: return "film"
            case .performers: return "person.2"
            case .history: return "clock.arrow.circlepath"
            }
        }
    }
}