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
        
        // Store both scene and timestamp in properties - ensure main thread for @Published
        DispatchQueue.main.async {
            self.currentScene = scene
            
            // FIXED: Track this as the last watched scene for return navigation
            self.lastWatchedScene = scene
        }
        print("🎯 HISTORY - Set lastWatchedScene to: \(scene.title ?? "Untitled")")
        
        // Add to watch history (avoid duplicates of consecutive same scene) - ensure main thread for @Published
        DispatchQueue.main.async {
            if self.watchHistory.last?.id != scene.id {
                self.watchHistory.append(scene)
                // Keep history to reasonable size (last 20 scenes)
                if self.watchHistory.count > 20 {
                    self.watchHistory = Array(self.watchHistory.suffix(20))
                }
                print("🎯 HISTORY - Added to watch history: \(scene.title ?? "Untitled") (history count: \(self.watchHistory.count))")
                print("🎯 HISTORY - Full history: \(self.watchHistory.map { $0.title ?? "Untitled" })")
            } else {
                print("🎯 HISTORY - Skipping duplicate scene: \(scene.title ?? "Untitled") (last in history: \(self.watchHistory.last?.title ?? "None"))")
            }
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
            print("⏱ Shuffle mode: Replacing current video with new one")
            // Kill all audio before navigation to prevent stacking
            killAllAudio()
            
            // ATOMIC navigation update to prevent race conditions
            DispatchQueue.main.async {
                if !self.navigationPath.isEmpty {
                    _ = self.navigationPath.removeLast()
                }
                // Immediately append new scene without delay to prevent race conditions
                self.navigationPath.append(scene)
                print("⏱ Navigation updated atomically: replaced current video")
            }
        } else {
            // Regular navigation - just append to path - ensure main thread for @Published
            print("⏱ Adding scene to navigation path")
            // Kill audio before any navigation to prevent stacking
            killAllAudio()
            
            DispatchQueue.main.async {
                self.navigationPath.append(scene)
            }
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
        DispatchQueue.main.async {
            self.currentPerformer = performer
        }

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
        // We do this last to ensure all state is reset - ensure main thread for @Published
        // Kill audio before performer navigation
        killAllAudio()
        
        DispatchQueue.main.async {
            self.navigationPath.append(performer)
            print("🏁 NAVIGATION - Navigation completed to performer: \(performer.name)")
        }
        
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
        
        // Prevent multiple simultaneous navigations
        guard !isNavigatingToMarker else {
            print("⚠️ NAVIGATION - Already navigating to a marker, skipping duplicate navigation")
            return
        }
        
        DispatchQueue.main.async {
            self.isNavigatingToMarker = true
        }
        
        // Reset flag after a delay to allow navigation to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isNavigatingToMarker = false
        }
        
        // Check if we're in a marker shuffle context (avoid navigation stack changes)
        let isMarkerShuffle = UserDefaults.standard.bool(forKey: "isMarkerShuffleContext")
        
        // ALWAYS kill audio to prevent stacking - marker navigation requires clean audio state
        print("🔇 Killing all audio for marker navigation (shuffle mode: \(isMarkerShuffle))")
        killAllAudio()
        
        // Emergency cleanup: Clear navigation stack if too many views are stacked
        if navigationPath.count > 6 {
            print("🚨 EMERGENCY: Too many navigation items (\(navigationPath.count)), clearing stack")
            DispatchQueue.main.async {
                // Only remove items if we have more than 1 item in the path
                let itemsToRemove = self.navigationPath.count - 1
                if itemsToRemove > 0 {
                    self.navigationPath.removeLast(itemsToRemove)
                }
            }
            
            // Gentle cleanup: Only kill audio, preserve shuffle contexts
            print("🔧 CLEANUP: Killing audio but preserving shuffle state")
            killAllAudio()
            
            // Only clear problematic cached URLs, not shuffle contexts
            let defaults = UserDefaults.standard
            let keys = defaults.dictionaryRepresentation().keys
            for key in keys {
                if key.contains("scene_") && (key.contains("_hlsURL") || key.contains("_startTime") || key.contains("_endTime") || key.contains("_forcePlay") || key.contains("_preferHLS")) {
                    defaults.removeObject(forKey: key)
                }
            }
            
            // Preserve shuffle contexts during emergency cleanup
            // Note: NOT clearing isMarkerShuffleContext or isTagSceneShuffleContext
        }
        
        print("🔍 navigateToMarker: Starting more explicit marker navigation")
        
        // Only save navigation state if not in shuffle context
        if !isMarkerShuffle {
            savePreviousNavigationState()
        }
        
        DispatchQueue.main.async {
            self.currentMarker = marker
        }
        
        // Auto-start marker shuffle if navigating from search (not already in shuffle mode)
        // Do this AFTER navigation to avoid blocking video playback
        if !isMarkerShuffle && !isMarkerShuffleMode {
            print("🎲 Scheduling auto-shuffle for tag: \(marker.primary_tag.name) (will start after video loads)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                Task {
                    await self.startAutoMarkerShuffle(for: marker)
                }
            }
        }
        
        // Make sure the marker navigation flag is set
        UserDefaults.standard.set(true, forKey: "scene_\(marker.scene.id)_isMarkerNavigation")
        
        // For direct marker playback, we actually want to navigate to the scene
        // with the marker's timestamp as the start position
        Task {
            // Use marker's scene info to fetch the full scene
            do {
                guard let fullScene = try await api.fetchScene(byID: marker.scene.id) else {
                    throw NSError(domain: "AppModel", code: 404, userInfo: [NSLocalizedDescriptionKey: "Scene not found"])
                }
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
                
                // Make sure the VideoPlayerViewModel is set up with the end time - ensure main thread for @Published
                if let endSeconds = endSeconds {
                    DispatchQueue.main.async {
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
                }
                
                // Store the exact HLS URL format directly in UserDefaults
                let apiKey = self.apiKey
                let baseServerURL = serverAddress.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let sceneId = fullScene.id
                let markerSeconds = Int(marker.seconds)
                let currentTimestamp = Int(Date().timeIntervalSince1970)
                
                // Format: http://192.168.86.100:9999/scene/3174/stream.m3u8?apikey=KEY&resolution=ORIGINAL&t=2132&_ts=1747330385
                let hlsStreamURL = "\(baseServerURL)/scene/\(sceneId)/stream.m3u8?apikey=\(apiKey)&resolution=ORIGINAL&t=\(markerSeconds)&_ts=\(currentTimestamp)"
                print("🎬 MARKER NAVIGATION: Using exact HLS format with timestamp t=\(markerSeconds): \(hlsStreamURL)")
                
                // Clear all cached HLS URLs first to prevent using wrong scene's URL
                if isMarkerShuffle {
                    print("🧹 Clearing all cached HLS URLs for marker shuffle")
                    let defaults = UserDefaults.standard
                    let keys = defaults.dictionaryRepresentation().keys
                    for key in keys {
                        if key.contains("_hlsURL") {
                            defaults.removeObject(forKey: key)
                        }
                    }
                }
                
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
                if isServerSideShuffle && !navigationPath.isEmpty && false { // Disabled - just use normal navigation
                    print("🔄 MARKER SHUFFLE CONTEXT: Using direct player update to avoid screen flicker")
                    
                    // Update the current scene reference without navigation
                    await MainActor.run {
                        self.currentScene = fullScene
                    }
                    
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
                        name: Notification.Name("MarkerSwitchRequest"),
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        UserDefaults.standard.set(true, forKey: "isMarkerShuffleContext")
                    }
                } else {
                    navigateToScene(fullScene, startSeconds: startSeconds, endSeconds: endSeconds)
                }
            } catch {
                // If we can't fetch the scene, log the error and try alternative navigation
                print("❌ Error fetching full scene for marker: \(error)")
                print("⚠️ Using marker scene data directly for navigation")
                
                // Reset navigation lock on error
                self.isNavigatingToMarker = false
                
                // Create a minimal scene from marker data
                let markerScene = StashScene(
                    id: marker.scene.id,
                    title: marker.scene.title,
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
                
                // Navigate to the scene with marker timestamp
                let startSeconds = Double(marker.seconds)
                navigateToScene(markerScene, startSeconds: startSeconds)
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
            DispatchQueue.main.async {
                self.navigationPath = NavigationPath()
            }
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
                
                DispatchQueue.main.async {
                    if !self.navigationPath.isEmpty {
                        self.navigationPath.removeLast()
                    }
                }
            }
        } else {
            // For other cases, just pop back once
            if !navigationPath.isEmpty {
                DispatchQueue.main.async {
                    self.navigationPath.removeLast()
                }
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

        // Navigate to the tag - ensure main thread for @Published
        // Kill audio before tag navigation
        killAllAudio()
        
        DispatchQueue.main.async {
            self.navigationPath.append(tag)
            print("🏁 NAVIGATION - Navigation completed to tag: \(tag.name)")
        }

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
        DispatchQueue.main.async {
            if !self.navigationPath.isEmpty {
                self.navigationPath.removeLast()
            }
        }
    }
    
    func clearNavigation() {
        DispatchQueue.main.async {
            self.navigationPath = NavigationPath()
        }
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
        DispatchQueue.main.async {
            self.currentScene = nil
        }
        
        // Clear any video-related UserDefaults if needed
        if let sceneId = currentSceneId {
            UserDefaults.standard.removeObject(forKey: "scene_\(sceneId)_hlsURL")
            UserDefaults.standard.removeObject(forKey: "scene_\(sceneId)_isMarkerNavigation")
        }
        
        // FIXED: Clear the temporary navigation flag since we're returning from video
        UserDefaults.standard.removeObject(forKey: "isNavigatingToVideo")
        print("🎯 NAVIGATION - Cleared temporary video navigation flag")
        
        // If we have a navigation path and the last item is likely a video, remove it
        DispatchQueue.main.async {
            if !self.navigationPath.isEmpty {
                self.navigationPath.removeLast()
                print("📱 Removed last navigation item, remaining path count: \(self.navigationPath.count)")
            }
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
    
    // Nuclear reset function for when app gets completely stuck
    func emergencyReset() {
        print("🚨🚨🚨 EMERGENCY RESET TRIGGERED 🚨🚨🚨")
        
        // 1. Clear navigation completely
        DispatchQueue.main.async {
            self.navigationPath = NavigationPath()
            self.currentScene = nil
            self.currentMarker = nil
        }
        
        // 2. Kill all audio aggressively
        killAllAudio()
        
        // 3. Clear all video-related UserDefaults
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys
        for key in keys {
            if key.contains("scene_") || key.contains("Shuffle") || key.contains("marker") {
                defaults.removeObject(forKey: key)
            }
        }
        
        // 4. Reset all shuffle modes
        DispatchQueue.main.async {
            self.isMarkerShuffleMode = false
            self.markerShuffleQueue = []
            self.currentShuffleIndex = 0
        }
        tagSceneShuffleQueue = []
        currentTagShuffleIndex = 0
        
        // 5. Force UI refresh
        DispatchQueue.main.async {
            self.activeTab = .scenes
        }
        
        print("🚨 Emergency reset complete - app should be clean now")
    }
    
    // Helper to find all AVPlayers that might be playing in the app
    private func getAllPreviewPlayers() -> [AVPlayer] {
        var players: [AVPlayer] = []
        
        // ALL UI operations must happen on main thread to avoid Main Thread Checker warnings
        let getPlayersOnMainThread = {
            for window in UIApplication.shared.windows {
                players.append(contentsOf: self.findPlayers(in: window.rootViewController))
            }
        }
        
        if Thread.isMainThread {
            getPlayersOnMainThread()
        } else {
            DispatchQueue.main.sync {
                getPlayersOnMainThread()
            }
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
    
    // MARK: - Helper Methods
    
    /// Set HLS streaming preference for marker playback (copied from PerformerMarkersView)
    private func setHLSPreferenceForMarker(_ marker: SceneMarker) {
        print("🎬 AppModel: Setting HLS preference for marker: \(marker.title)")
        
        // Set preference for HLS streaming
        UserDefaults.standard.set(true, forKey: "scene_\(marker.scene.id)_preferHLS")
        UserDefaults.standard.set(true, forKey: "scene_\(marker.scene.id)_isMarkerNavigation")
        
        // Save timestamp for player to use - make sure this is a Double
        let markerSeconds = Double(marker.seconds)
        UserDefaults.standard.set(markerSeconds, forKey: "scene_\(marker.scene.id)_startTime")
        print("⏱ AppModel: Setting start time for marker: \(markerSeconds)s")
        
        // Add support for end_seconds if available
        if let markerEndSeconds = marker.end_seconds {
            let endSeconds = Double(markerEndSeconds)
            UserDefaults.standard.set(endSeconds, forKey: "scene_\(marker.scene.id)_endTime")
            print("⏱ AppModel: Setting end time for marker: \(endSeconds)s")
        } else {
            // Clear any previous end time
            UserDefaults.standard.removeObject(forKey: "scene_\(marker.scene.id)_endTime")
        }
        
        // Set force play flag
        UserDefaults.standard.set(true, forKey: "scene_\(marker.scene.id)_forcePlay")
    }
    
    // MARK: - Marker Shuffle System
    @Published var markerShuffleQueue: [SceneMarker] = []
    @Published var currentShuffleIndex: Int = 0
    @Published var isMarkerShuffleMode: Bool = false
    @Published var shuffleTagFilter: String? = nil
    @Published var shuffleTagFilters: [String] = [] // For multi-tag shuffling
    @Published var shuffleSearchQuery: String? = nil
    private var isNavigatingToMarker: Bool = false // Prevent multiple simultaneous navigations
    
    // Balanced tag rotation properties
    private var markersByTag: [String: [SceneMarker]] = [:] // Markers grouped by tag
    private var recentMarkersByTag: [String: [String]] = [:] // Recent marker IDs per tag for repeat prevention
    
    // Server-side shuffle tracking
    @Published var shuffleTagNames: [String] = [] // Tags to shuffle from
    @Published var shuffleTotalMarkerCount: Int = 0 // Total available markers on server
    @Published var isServerSideShuffle: Bool = false // Use server-side random selection
    private var currentShuffleTag: String = "" // Track current tag being played
    private var currentTagPlayCount: Int = 0 // Track how many times current tag has played
    
    /// Start marker shuffle for a specific tag - uses server-side random selection
    func startMarkerShuffle(forTag tagId: String, tagName: String, displayedMarkers: [SceneMarker]) {
        print("🎲 Starting SERVER-SIDE marker shuffle for tag: \(tagName)")
        
        // Set shuffle context immediately for UI responsiveness
        DispatchQueue.main.async {
            self.isMarkerShuffleMode = true
            self.isServerSideShuffle = true
            self.shuffleTagNames = [tagName]
        }
        shuffleTagFilter = tagId
        shuffleTagFilters = [] // Clear multi-tag filters
        shuffleSearchQuery = nil
        UserDefaults.standard.set(true, forKey: "isMarkerShuffleContext")
        UserDefaults.standard.set(true, forKey: "isMarkerShuffleMode")
        
        // Play first marker immediately if available
        if let firstMarker = displayedMarkers.randomElement() {
            print("🎯 Starting with random marker from displayed: \(firstMarker.title)")
            // Stop all preview players before starting shuffle (like PerformerMarkersView)
            GlobalVideoManager.shared.stopAllPreviews()
            setHLSPreferenceForMarker(firstMarker)
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
            
            // Use larger batch size to reduce marker cap
            await api.fetchMarkersByTag(tagId: tagId, page: currentPage, appendResults: false, perPage: 2000)
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
            if newMarkers.count < 2000 {
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
        print("🎲 Starting multi-tag shuffle with \(tagNames.count) tags: \(tagNames.joined(separator: ", "))")
        print("🎲 DEBUG - Tag IDs: \(tagIds)")
        print("🎲 DEBUG - Tag Names: \(tagNames)")
        print("🎲 DEBUG - Displayed Markers Count: \(displayedMarkers.count)")
        
        // Set shuffle context  
        DispatchQueue.main.async {
            self.isMarkerShuffleMode = true
            self.isServerSideShuffle = true  // Use SERVER-side shuffle to get random markers from ALL available
            self.shuffleTagNames = tagNames
        }
        shuffleTagFilters = tagIds
        shuffleTagFilter = nil
        shuffleSearchQuery = nil
        
        // Group markers by tag for balanced rotation
        markersByTag.removeAll()
        recentMarkersByTag.removeAll()
        
        for marker in displayedMarkers {
            let tagName = marker.primary_tag.name
            if markersByTag[tagName] == nil {
                markersByTag[tagName] = []
                recentMarkersByTag[tagName] = []
            }
            markersByTag[tagName]?.append(marker)
        }
        
        // Log the distribution
        for (tagName, markers) in markersByTag {
            print("🎲 Tag '\(tagName)': \(markers.count) markers")
        }
        
        // Still keep the combined queue for backwards compatibility, but use balanced selection
        markerShuffleQueue = displayedMarkers.shuffled()
        DispatchQueue.main.async {
            self.currentShuffleIndex = 0
        }
        
        print("✅ Created balanced tag rotation with \(markersByTag.count) tags, total \(displayedMarkers.count) markers")
        
        // Reset the tag rotation tracking
        currentShuffleTag = ""
        currentTagPlayCount = 0
        UserDefaults.standard.set(true, forKey: "isMarkerShuffleContext")
        UserDefaults.standard.set(true, forKey: "isMarkerShuffleMode")
        
        // Play first marker immediately if available
        if let firstMarker = markerShuffleQueue.first {
            print("🎯 Starting with first marker from shuffled queue: \(firstMarker.title)")
            // Stop all preview players before starting shuffle (like PerformerMarkersView)
            GlobalVideoManager.shared.stopAllPreviews()
            setHLSPreferenceForMarker(firstMarker)
            navigateToMarker(firstMarker)
        } else {
            print("❌ No markers available to shuffle")
            stopMarkerShuffle()
        }
    }
    
    /// Start marker shuffle for search results - loads ALL markers from API for comprehensive shuffle
    func startMarkerShuffle(forSearchQuery query: String, displayedMarkers: [SceneMarker]) {
        print("🎲 Starting marker shuffle for search: \(query) - using server-side random from ALL available markers")
        
        // Set shuffle context
        DispatchQueue.main.async {
            self.isMarkerShuffleMode = true
            self.isServerSideShuffle = true  // Use SERVER-side shuffle to get random markers from ALL available
        }
        shuffleSearchQuery = query
        shuffleTagFilter = nil
        shuffleTagFilters = []
        UserDefaults.standard.set(true, forKey: "isMarkerShuffleContext")
        
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
        
        // Check if we have any tags for server-side shuffle
        guard !shuffleTagNames.isEmpty else {
            print("❌ No tags available for server-side shuffle - falling back to client-side shuffle")
            DispatchQueue.main.async {
                // Fall back to client-side shuffle using existing queue
                if let nextMarker = self.nextMarkerInShuffle() {
                    print("🎲 Fallback: Using client-side shuffle queue")
                    GlobalVideoManager.shared.stopAllPreviews()
                    self.setHLSPreferenceForMarker(nextMarker)
                    self.navigateToMarker(nextMarker)
                } else {
                    print("⚠️ No markers available in fallback queue either")
                }
            }
            return
        }
        
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
            // Single tag shuffle (we already checked that shuffleTagNames is not empty)
            let randomTag = shuffleTagNames.first!
            print("🎲 Single tag shuffle - tag: '\(randomTag)'")
            await fetchRandomMarkerForTag(randomTag)
        }
    }
    
    /// Helper function to fetch a random marker for a specific tag using optimized shuffle search
    private func fetchRandomMarkerForTag(_ tagName: String) async {
        print("🎲 Fetching server-side random marker for tag: '\(tagName)' using shuffle-optimized search")
        
        do {
            // Use the shuffle-optimized search to get a random selection from ALL markers
            let shuffleMarkers = try await api.searchMarkersByExactTagForShuffle(tagName: tagName, maxMarkers: 100)
            
            print("🎲 Shuffle search returned \(shuffleMarkers.count) random markers for tag '\(tagName)'")
            
            // Pick a random marker from the shuffle results
            if let randomMarker = shuffleMarkers.randomElement() {
                print("🎯 Selected random marker: \(randomMarker.title) from tag: \(tagName)")
                await MainActor.run {
                    navigateToMarker(randomMarker)
                }
                return
            }
            
            print("⚠️ No markers found for tag '\(tagName)'")
        } catch {
            print("❌ Error fetching markers for tag '\(tagName)': \(error)")
        }
    }
    
    /// Load all markers for a search query with pagination
    private func loadAllMarkersForSearch(query: String) async {
        print("🔄 Loading ALL markers for search: '\(query)'")
        
        // Check if this is a multi-tag query (contains +)
        if query.contains(" +") {
            print("🔄 Multi-tag shuffle query detected, using combination logic")
            await loadAllMarkersForMultiTagSearch(query: query)
            return
        }
        
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
                    DispatchQueue.main.async {
                        self.currentMarker = firstMarker
                    }
                    
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
    
    /// Load all markers for a multi-tag search query (handles + syntax)
    private func loadAllMarkersForMultiTagSearch(query: String) async {
        print("🔄 Loading markers for multi-tag shuffle: '\(query)'")
        
        // Parse the query - same logic as in MediaLibraryView
        let terms = query.split(separator: " +").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let mainTerm = terms.first, terms.count > 1 else {
            print("❌ Invalid multi-tag query format")
            return
        }
        
        let additionalTerms = Array(terms.dropFirst())
        print("🔄 Shuffle combining: '\(mainTerm)' + [\(additionalTerms.joined(separator: ", "))]")
        
        do {
            var allMarkers = Set<SceneMarker>()
            
            // Load markers for main term
            let mainMarkers = try await api.searchMarkers(query: "#\(mainTerm)", page: 1, perPage: 500)
            print("🔄 Shuffle main term '\(mainTerm)': \(mainMarkers.count) markers")
            allMarkers.formUnion(mainMarkers)
            
            // Load markers for each additional term
            for additionalTerm in additionalTerms {
                let additionalMarkers = try await api.searchMarkers(query: "#\(additionalTerm)", page: 1, perPage: 500)
                print("🔄 Shuffle additional term '\(additionalTerm)': \(additionalMarkers.count) markers")
                allMarkers.formUnion(additionalMarkers)
            }
            
            let finalMarkers = Array(allMarkers)
            print("🔄 Shuffle combined total: \(finalMarkers.count) unique markers")
            
            // Update the shuffle queue with combined markers
            await MainActor.run {
                self.markerShuffleQueue = finalMarkers.shuffled()
                self.api.isLoading = false
                print("🎲 Shuffle queue populated with \(self.markerShuffleQueue.count) markers")
                
                // Start the shuffle by playing the first marker
                if let firstMarker = self.markerShuffleQueue.first {
                    print("🎲 Starting shuffle with first marker: \(firstMarker.title)")
                    self.navigateToMarker(firstMarker)
                } else {
                    print("❌ No markers available for shuffle")
                }
            }
            
        } catch {
            print("❌ Error loading multi-tag shuffle markers: \(error)")
            await MainActor.run {
                self.api.isLoading = false
            }
        }
    }
    
    /// Load markers optimized for shuffle system (can access more markers efficiently)
    private func loadAllMarkersForTag(tagId: String, tagName: String) async {
        print("🔄 Loading markers for shuffle system - tag: \(tagName)")
        
        do {
            // Use the shuffle-optimized search that can load more markers efficiently
            let allMarkers = try await api.searchMarkersByExactTagForShuffle(tagName: tagName, maxMarkers: 1000)
            print("🎲 Loaded \(allMarkers.count) markers for shuffle from tag: \(tagName)")
            
            guard !allMarkers.isEmpty else {
                print("⚠️ No markers found for tag: \(tagName)")
                await MainActor.run {
                    self.api.isLoading = false
                    self.stopMarkerShuffle()
                }
                return
            }
            
            await MainActor.run {
                self.api.isLoading = false
                
                // Store markers for shuffle (randomized by the API)
                self.markerShuffleQueue = allMarkers
                self.currentShuffleIndex = 0
                self.isMarkerShuffleMode = true
                
                print("🎯 Marker shuffle ready: \(self.markerShuffleQueue.count) markers available")
                
                // Navigate to first marker
                if let firstMarker = allMarkers.first {
                    print("🎲 Starting with first shuffled marker: \(firstMarker.title)")
                    self.setHLSPreferenceForMarker(firstMarker)
                    self.navigateToMarker(firstMarker)
                }
            }
        } catch {
            print("❌ Error loading shuffle markers for tag \(tagName): \(error)")
            await MainActor.run {
                self.api.isLoading = false
                self.stopMarkerShuffle()
            }
        }
    }
    
    /// Get next marker in shuffle queue
    func nextMarkerInShuffle() -> SceneMarker? {
        guard isMarkerShuffleMode && !markerShuffleQueue.isEmpty else {
            return nil
        }
        
        // Use balanced tag rotation if we have multiple tags
        if markersByTag.count > 1 {
            return nextMarkerWithBalancedTagRotation()
        }
        
        // Fallback to random selection for single tag or legacy mode
        let randomIndex = Int.random(in: 0..<markerShuffleQueue.count)
        let nextMarker = markerShuffleQueue[randomIndex]
        
        print("🎲 Next marker in TRUE RANDOM shuffle: \(nextMarker.title) (random index \(randomIndex) of \(markerShuffleQueue.count))")
        return nextMarker
    }
    
    /// Balanced tag rotation: ensures equal representation from all tags
    private func nextMarkerWithBalancedTagRotation() -> SceneMarker? {
        guard !markersByTag.isEmpty else { return nil }
        
        // Weight tags by their marker count to prevent small tags from dominating
        // Larger tags get higher probability of being selected
        let tagWeights = markersByTag.mapValues { markers in
            max(1, Int(sqrt(Double(markers.count)))) // Square root weighting
        }
        
        let totalWeight = tagWeights.values.reduce(0, +)
        let randomValue = Int.random(in: 0..<totalWeight)
        
        var currentWeight = 0
        var selectedTag: String = ""
        for (tag, weight) in tagWeights {
            currentWeight += weight
            if randomValue < currentWeight {
                selectedTag = tag
                break
            }
        }
        
        // Fallback to random if weighting fails
        if selectedTag.isEmpty {
            selectedTag = Array(markersByTag.keys).randomElement()!
        }
        
        guard let tagMarkers = markersByTag[selectedTag], !tagMarkers.isEmpty else {
            return nil
        }
        
        // Get recent markers for this tag to avoid immediate repeats
        let recentMarkerIds = recentMarkersByTag[selectedTag] ?? []
        let maxRecentCount = min(tagMarkers.count / 2, 15) // Remember last 1/2 or max 15 markers
        
        // Try to find a marker that wasn't recently played
        var availableMarkers = tagMarkers.filter { !recentMarkerIds.contains($0.id) }
        
        // For small tag pools (≤5 markers), only reset when ALL markers have been played
        // For larger tag pools, reset when 90% have been played
        let resetThreshold = tagMarkers.count <= 5 ? 0 : max(1, tagMarkers.count / 10)
        
        if availableMarkers.count <= resetThreshold {
            availableMarkers = tagMarkers
            recentMarkersByTag[selectedTag] = []
            let resetReason = tagMarkers.count <= 5 ? "all played" : "90% played"
            print("🎲 Reset recent markers for tag '\(selectedTag)' - \(resetReason), all available again")
        }
        
        // Pick a random marker from available ones
        let selectedMarker = availableMarkers.randomElement()!
        
        // Update recent markers list
        var updatedRecent = recentMarkersByTag[selectedTag] ?? []
        updatedRecent.append(selectedMarker.id)
        if updatedRecent.count > maxRecentCount {
            updatedRecent.removeFirst()
        }
        recentMarkersByTag[selectedTag] = updatedRecent
        
        // Add weight info to the debug log
        let weight = tagWeights[selectedTag] ?? 1
        print("🎲 BALANCED ROTATION: Selected '\(selectedMarker.title)' from tag '\(selectedTag)' (\(tagMarkers.count) total, \(availableMarkers.count) available, weight: \(weight))")
        
        return selectedMarker
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
        // Stop all preview players before navigating (like PerformerMarkersView)
        GlobalVideoManager.shared.stopAllPreviews()
        setHLSPreferenceForMarker(nextMarker)
        navigateToMarker(nextMarker)
    }
    
    /// Jump to previous marker in shuffle  
    func shuffleToPreviousMarker() {
        guard let previousMarker = previousMarkerInShuffle() else {
            print("⚠️ No previous marker available in shuffle")
            return
        }
        
        print("🎲 Shuffling to previous marker: \(previousMarker.title)")
        // Stop all preview players before navigating (like PerformerMarkersView)
        GlobalVideoManager.shared.stopAllPreviews()
        setHLSPreferenceForMarker(previousMarker)
        navigateToMarker(previousMarker)
    }
    
    /// Start marker shuffle with provided markers (simple version)
    func startMarkerShuffle(withMarkers markers: [SceneMarker]) {
        print("🎲 Starting simple marker shuffle with \(markers.count) markers")
        
        // Set shuffle context
        DispatchQueue.main.async {
            self.isMarkerShuffleMode = true
        }
        shuffleTagFilter = nil
        shuffleSearchQuery = "direct_markers"
        UserDefaults.standard.set(true, forKey: "isMarkerShuffleContext")
        
        // Create shuffled queue immediately
        markerShuffleQueue = markers.shuffled()
        DispatchQueue.main.async {
            self.currentShuffleIndex = 0
        }
        
        print("✅ Created shuffle queue with \(markerShuffleQueue.count) markers")
        
        // Start playing first marker
        if let firstMarker = markerShuffleQueue.first {
            print("🎬 Starting playback with first shuffled marker: \(firstMarker.title)")
            print("🎬 Current navigation path count: \(navigationPath.count)")
            
            // Check if we're already in a video player context
            if !navigationPath.isEmpty {
                print("🔄 Already in navigation context - using direct marker update instead of navigation")
                DispatchQueue.main.async {
                    self.currentMarker = firstMarker
                }
                
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
        DispatchQueue.main.async {
            self.isMarkerShuffleMode = false
        }
        DispatchQueue.main.async {
            self.markerShuffleQueue.removeAll()
        }
        DispatchQueue.main.async {
            self.currentShuffleIndex = 0
        }
        shuffleTagFilter = nil
        shuffleSearchQuery = nil
        
        // Clear balanced rotation data
        markersByTag.removeAll()
        recentMarkersByTag.removeAll()
        
        UserDefaults.standard.set(false, forKey: "isMarkerShuffleContext")
        UserDefaults.standard.set(false, forKey: "isMarkerShuffleMode")
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
                
                // Use larger batch size to reduce marker cap
                await api.fetchMarkersByTag(tagId: tagId, page: currentPage, appendResults: false, perPage: 2000)
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
                if newMarkers.count < 2000 {
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
        DispatchQueue.main.async {
            self.currentShuffleIndex = 0
        }
        
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
