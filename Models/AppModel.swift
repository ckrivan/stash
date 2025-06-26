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
        
        // IMPORTANT: Only kill audio if NOT in any shuffle mode to prevent stopping the active player
        if !isMarkerShuffle && !isTagShuffle {
            print("🔇 Killing audio for regular navigation")
            killAllAudio()
        } else {
            print("🎲 Skipping audio kill - in shuffle mode (marker: \(isMarkerShuffle), tag: \(isTagShuffle))")
        }
        
        // Store both scene and timestamp in properties
        currentScene = scene
        
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
        
        // Regular navigation - just append to path
        print("⏱ Adding scene to navigation path")
        navigationPath.append(scene)
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

        // Step 3: Clear existing scenes/state to force redraw and prevent stale data
        api.scenes = []
        api.markers = []
        print("🧹 NAVIGATION - Cleared existing data")
        
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
        
        // Check if we're in a marker shuffle context (avoid navigation stack changes)
        let isMarkerShuffle = UserDefaults.standard.bool(forKey: "isMarkerShuffleContext")
        
        // IMPORTANT: Only kill audio if NOT in marker shuffle mode to prevent stopping the active player
        if !isMarkerShuffle {
            print("🔇 Killing audio for regular navigation")
            killAllAudio()
        } else {
            print("🎲 Skipping audio kill - in marker shuffle mode")
        }
        
        print("🔍 navigateToMarker: Starting more explicit marker navigation")
        
        // Only save navigation state if not in shuffle context
        if !isMarkerShuffle {
            savePreviousNavigationState()
        }
        
        currentMarker = marker
        
        // Make sure the marker navigation flag is set
        UserDefaults.standard.set(true, forKey: "scene_\(marker.scene.id)_isMarkerNavigation")
        
        // For direct marker playback, we actually want to navigate to the scene
        // with the marker's timestamp as the start position
        Task {
            // Use marker's scene info to fetch the full scene
            if let fullScene = try? await api.fetchScene(byID: marker.scene.id) {
                print("✅ Found full scene for marker: \(marker.title)")
                // Important: Convert float seconds to Double for startSeconds parameter
                let startSeconds = Double(marker.seconds)
                print("ℹ️ Setting startSeconds parameter to \(startSeconds) for scene \(fullScene.id)")
                
                // Add support for end_seconds if available
                var endSeconds: Double? = nil
                if let markerEndSeconds = marker.end_seconds {
                    endSeconds = Double(markerEndSeconds)
                    print("ℹ️ Setting endSeconds parameter to \(endSeconds!) for scene \(fullScene.id)")
                }
                
                // Make sure the VideoPlayerViewModel is set up with the end time
                if let endSeconds = endSeconds {
                    if let playerViewModel = self.playerViewModel as? VideoPlayerViewModel {
                        print("⏱ Setting endSeconds in existing playerViewModel")
                        playerViewModel.endSeconds = endSeconds
                    } else {
                        print("⏱ Creating new playerViewModel with endSeconds")
                        let viewModel = VideoPlayerViewModel()
                        viewModel.endSeconds = endSeconds
                        self.playerViewModel = viewModel
                    }
                }
                
                // Store the exact HLS URL format directly in UserDefaults
                let apiKey = self.apiKey
                let baseServerURL = serverAddress.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let sceneId = fullScene.id
                let markerSeconds = Int(marker.seconds)
                let currentTimestamp = Int(Date().timeIntervalSince1970)
                
                // Format: http://192.168.86.100:9999/scene/3174/stream.m3u8?apikey=KEY&resolution=ORIGINAL&t=2132&_ts=1747330385
                let hlsStreamURL = "\(baseServerURL)/scene/\(sceneId)/stream.m3u8?apikey=\(apiKey)&resolution=ORIGINAL&t=\(markerSeconds)&_ts=\(currentTimestamp)"
                print("🎬 Using exact HLS format: \(hlsStreamURL)")
                
                // Save HLS format URL and preferences for VideoPlayerView to use
                UserDefaults.standard.set(hlsStreamURL, forKey: "scene_\(fullScene.id)_hlsURL")
                UserDefaults.standard.set(true, forKey: "scene_\(fullScene.id)_preferHLS")
                UserDefaults.standard.set(true, forKey: "scene_\(fullScene.id)_isMarkerNavigation")
                UserDefaults.standard.set(Double(marker.seconds), forKey: "scene_\(fullScene.id)_startTime")
                UserDefaults.standard.set(true, forKey: "scene_\(fullScene.id)_forcePlay")
                
                // REMOVED URL validation causing freezes
                
                if let endSeconds = endSeconds {
                    UserDefaults.standard.set(endSeconds, forKey: "scene_\(fullScene.id)_endTime")
                } else {
                    // Clear any previous end time
                    UserDefaults.standard.removeObject(forKey: "scene_\(fullScene.id)_endTime")
                }
                
                print("🎬 Starting navigation to scene with marker timestamp - should trigger immediate playback")
                
                // Use direct player update for marker shuffle to avoid navigation flicker
                if isMarkerShuffle && !navigationPath.isEmpty {
                    print("🔄 MARKER SHUFFLE CONTEXT: Using direct player update to avoid screen flicker")
                    
                    // Update the current scene reference without navigation
                    self.currentScene = fullScene
                    
                    // Set up all the UserDefaults that VideoPlayerView needs
                    UserDefaults.standard.set(hlsStreamURL, forKey: "scene_\(fullScene.id)_hlsURL")
                    UserDefaults.standard.set(true, forKey: "scene_\(fullScene.id)_preferHLS")
                    UserDefaults.standard.set(true, forKey: "scene_\(fullScene.id)_isMarkerNavigation")
                    UserDefaults.standard.set(startSeconds, forKey: "scene_\(fullScene.id)_startTime")
                    UserDefaults.standard.set(true, forKey: "scene_\(fullScene.id)_forcePlay")
                    
                    if let endSeconds = endSeconds {
                        UserDefaults.standard.set(endSeconds, forKey: "scene_\(fullScene.id)_endTime")
                    } else {
                        UserDefaults.standard.removeObject(forKey: "scene_\(fullScene.id)_endTime")
                    }
                    
                    // Post a notification to update the current VideoPlayerView instead of navigating
                    NotificationCenter.default.post(
                        name: NSNotification.Name("UpdateVideoPlayerForMarkerShuffle"),
                        object: nil,
                        userInfo: [
                            "scene": fullScene,
                            "startSeconds": startSeconds,
                            "endSeconds": endSeconds as Any,
                            "hlsURL": hlsStreamURL
                        ]
                    )
                    
                    print("🔄 Posted notification to update current video player instead of navigation")
                    return
                }
                
                // Normal case: Navigate to the scene with the marker timestamp directly as a parameter
                // This passes startTime and endTime directly to VideoPlayerView's initializer
                
                // Important: Check if we need to preserve marker shuffle context
                if isMarkerShuffle {
                    print("🔄 Preserving marker shuffle context in standard navigation")
                    // Ensure we maintain the marker shuffle flag even when using standard navigation
                    UserDefaults.standard.set(true, forKey: "isMarkerShuffleMode")
                    
                    // We don't clear isMarkerShuffleContext here to maintain consistent shuffle state
                    navigateToScene(fullScene, startSeconds: startSeconds, endSeconds: endSeconds)
                    
                    // Re-set the context after navigation to ensure it persists
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        UserDefaults.standard.set(true, forKey: "isMarkerShuffleContext")
                    }
                } else {
                    navigateToScene(fullScene, startSeconds: startSeconds, endSeconds: endSeconds)
                }
            } else {
                // If we can't fetch the scene, fall back to direct marker navigation
                print("⚠️ Could not find full scene for marker, using fallback navigation")
                navigationPath.append(marker)
            }
        }
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
    @Published var shuffleSearchQuery: String? = nil
    
    /// Start marker shuffle for a specific tag - loads ALL markers from API for comprehensive shuffle
    func startMarkerShuffle(forTag tagId: String, tagName: String, displayedMarkers: [SceneMarker]) {
        print("🎲 Starting marker shuffle for tag: \(tagName) - loading ALL markers from API")
        
        // Set shuffle context
        isMarkerShuffleMode = true
        shuffleTagFilter = tagId
        shuffleSearchQuery = nil
        UserDefaults.standard.set(true, forKey: "isMarkerShuffleContext")
        
        // Set loading state
        api.isLoading = true
        
        Task {
            await loadAllMarkersForTag(tagId: tagId, tagName: tagName)
        }
    }
    
    /// Start marker shuffle for search results - loads ALL markers from API for comprehensive shuffle
    func startMarkerShuffle(forSearchQuery query: String, displayedMarkers: [SceneMarker]) {
        print("🎲 Starting marker shuffle for search: \(query) - loading ALL markers from API")
        
        // Set shuffle context
        isMarkerShuffleMode = true
        shuffleSearchQuery = query
        shuffleTagFilter = nil
        UserDefaults.standard.set(true, forKey: "isMarkerShuffleContext")
        
        // Set loading state
        api.isLoading = true
        
        Task {
            await loadAllMarkersForSearch(query: query)
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
    
    /// Get next marker in shuffle queue
    func nextMarkerInShuffle() -> SceneMarker? {
        guard isMarkerShuffleMode && !markerShuffleQueue.isEmpty else {
            return nil
        }
        
        // Move to next marker
        currentShuffleIndex = (currentShuffleIndex + 1) % markerShuffleQueue.count
        let nextMarker = markerShuffleQueue[currentShuffleIndex]
        
        print("🎲 Next marker in shuffle: \(nextMarker.title) (index \(currentShuffleIndex) of \(markerShuffleQueue.count))")
        return nextMarker
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
        print("🎲 markerShuffleQueue.count: \(markerShuffleQueue.count)")
        print("🎲 currentShuffleIndex: \(currentShuffleIndex)")
        
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
        navigateToMarker(nextMarker)
    }
    
    /// Jump to previous marker in shuffle  
    func shuffleToPreviousMarker() {
        guard let previousMarker = previousMarkerInShuffle() else {
            print("⚠️ No previous marker available in shuffle")
            return
        }
        
        print("🎲 Shuffling to previous marker: \(previousMarker.title)")
        navigateToMarker(previousMarker)
    }
    
    /// Start marker shuffle with provided markers (simple version)
    func startMarkerShuffle(withMarkers markers: [SceneMarker]) {
        print("🎲 Starting simple marker shuffle with \(markers.count) markers")
        
        // Set shuffle context
        isMarkerShuffleMode = true
        shuffleTagFilter = nil
        shuffleSearchQuery = "direct_markers"
        UserDefaults.standard.set(true, forKey: "isMarkerShuffleContext")
        
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
}

// MARK: - Types
extension AppModel {
    enum Tab: String, CaseIterable {
        case scenes = "Scenes"
        case performers = "Performers"
        
        var icon: String {
            switch self {
            case .scenes: return "film"
            case .performers: return "person.2"
            }
        }
    }
}