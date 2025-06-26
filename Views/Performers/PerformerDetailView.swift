import SwiftUI

// Import custom components for performer navigation
// No need to use module imports - they're in the same target

struct PerformerDetailView: View {
    let performer: StashScene.Performer
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedTab = 0 // 0 for scenes, 1 for markers
    @State private var markerCount: Int = 0
    @State private var performerScenes: [StashScene] = [] // Local state for scenes
    @State private var isLoadingScenes = false
    @State private var isLoadingMarkers = false

    init(performer: StashScene.Performer) {
        self.performer = performer
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Performer header
            PerformerHeaderView(performer: performer)

            // Tab picker
            Picker("View", selection: $selectedTab) {
                Text("Scenes").tag(0)
                Text("Markers").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            TabView(selection: $selectedTab) {
                // Scenes Tab
                scenesContent
                    .tag(0)
                    // Remove onAppear from tab content to prevent duplicate loading

                // Markers Tab
                markersContent
                    .tag(1)
                    // Remove onAppear from tab content to prevent duplicate loading
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationBarTitleDisplayMode(.inline) // Don't show title in navbar to avoid duplication
        .onDisappear {
            // FIXED: Only reset performer context when actually navigating away from performer entirely
            // Don't clear when just going to video player temporarily
            print("📱 PerformerDetailView disappeared")
            
            // Check if we're navigating to a video player (temporary) or actually leaving the performer
            let isNavigatingToVideo = appModel.navigationPath.count > 0 && 
                                    UserDefaults.standard.object(forKey: "isNavigatingToVideo") != nil
            
            if !isNavigatingToVideo {
                print("📱 Actually leaving performer view - clearing performer context")
                Task {
                    await MainActor.run {
                        // Clear the performer-specific scenes only when truly leaving
                        performerScenes = []
                        appModel.currentPerformer = nil
                    }

                    // Only reload default scenes if we're going back to main scenes view
                    if appModel.activeTab == .scenes {
                        Task {
                            await appModel.api.fetchScenes(page: 1, sort: "date", direction: "DESC")
                        }
                    }
                }
            } else {
                print("📱 Temporarily navigating to video - preserving performer context")
                // Remove the temporary navigation flag
                UserDefaults.standard.removeObject(forKey: "isNavigatingToVideo")
            }
        }
        .onAppear {
            // Load content immediately on appearance
            print("🚀 DETAIL - PerformerDetailView appeared for performer: \(performer.name) (ID: \(performer.id))")
            
            // CRITICAL: Set current performer context for VideoPlayerView
            appModel.currentPerformer = performer
            print("🎯 DETAIL - Set currentPerformer to: \(performer.name)")

            // Check if we're returning from a video player session
            // If so, respect the requested tab selection
            let forceScenesTab = UserDefaults.standard.bool(forKey: "forceScenesTab")
            let savedTabIndex = UserDefaults.standard.integer(forKey: "performerDetailSelectedTab")
            
            if forceScenesTab {
                print("🚀 DETAIL - Forcing scenes tab (returning from video)")
                // Set to scenes tab (index 0)
                selectedTab = 0
                // Reset the flag
                UserDefaults.standard.set(false, forKey: "forceScenesTab")
            } else if savedTabIndex >= 0 && savedTabIndex <= 1 {
                print("🚀 DETAIL - Restoring saved tab: \(savedTabIndex)")
                selectedTab = savedTabIndex
            } else {
                // Default to scenes tab (index 0)
                print("🚀 DETAIL - Using default tab (scenes)")
                selectedTab = 0
            }

            // Load content only if we don't already have it
            Task(priority: .userInitiated) {
                // Only load scenes if we don't have them already
                if performerScenes.isEmpty && appModel.api.scenes.isEmpty {
                    print("🚀 DETAIL - No scenes loaded yet, loading now")
                    await loadScenes()
                } else if performerScenes.isEmpty && !appModel.api.scenes.isEmpty {
                    // Sync API scenes to local state if needed
                    await MainActor.run {
                        performerScenes = appModel.api.scenes
                        print("✅ DETAIL - Synced \(performerScenes.count) existing scenes")
                    }
                }
                
                // Load markers in background if needed
                if selectedTab == 1 && appModel.api.markers.isEmpty {
                    await loadMarkers()
                }
                
                // Always get marker count in background
                Task.detached {
                    await self.getMarkerCount()
                }
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            // Ensure the tab content is loaded when tab changes
            Task {
                print("💫 Tab changed to: \(newValue)")

                // Save the current tab selection to UserDefaults
                // This helps with proper tab restoration when returning from video player
                UserDefaults.standard.set(newValue, forKey: "performerDetailSelectedTab")
                print("💫 Saved tab selection: \(newValue)")
                
                // Always ensure both scenes and markers are loaded, just prioritize differently
                if newValue == 0 {
                    // Scenes tab selected
                    if performerScenes.isEmpty {
                        await loadScenes()
                    } else {
                        print("💫 Not reloading scenes as we already have \(performerScenes.count) scenes")
                    }
                } else {
                    // Markers tab selected
                    if appModel.api.markers.isEmpty {
                        await loadMarkers()
                    } else {
                        print("💫 Not reloading markers as we already have \(appModel.api.markers.count) markers")
                    }
                }
            }
        }
        // Removed onChange handler for appModel.api.scenes to prevent unnecessary view updates
    }
    
    // Note: This method is now unused as we've improved the onAppear logic
    private func loadInitialContent() async {
        // Load marker count in the background
        Task {
            markerCount = await getMarkerCount()
        }

        // First load the scenes (most important)
        await loadScenes()

        // Then, if on markers tab, load markers
        if selectedTab == 1 {
            await loadMarkers()
        }
    }
    
    
    private var scenesContent: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 0) {
                // Remove debug text for production
                
                // Always show loading state at top when loading
                if appModel.api.isLoading {
                    VStack(spacing: 8) {
                        ProgressView()
                            .padding(.top, 20)
                        Text("Loading scenes for \(performer.name)...")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }

                if performerScenes.isEmpty && appModel.api.scenes.isEmpty {
                // Loading state
                VStack(spacing: 20) {
                    if !appModel.api.isLoading {
                        // Only show this if not already showing loading state
                        Spacer().frame(height: 40)
                        Image(systemName: "film")
                            .font(.system(size: 50))
                            .foregroundColor(.gray.opacity(0.5))
                            .padding()
                        
                        Text("No scenes found")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        // Add reload button
                        Button("Reload Scenes") {
                            Task {
                                print("🔄 SCENES VIEW - Manual reload requested")
                                await MainActor.run {
                                    performerScenes = []
                                    appModel.api.scenes = []
                                }
                                await loadScenes()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .padding(.top, 8)
                    }
                }
                .padding()
                // Removed onAppear to prevent duplicate loading
            } else if performerScenes.isEmpty && !appModel.api.scenes.isEmpty {
                // We have API scenes but haven't synced to local state yet
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: 16) {
                    ForEach(appModel.api.scenes) { scene in
                        // Use our custom scene row with direct navigation
                        CustomPerformerSceneRow(scene: scene)
                            .id("scene-\(scene.id)")
                    }
                }
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    // Header with scene count and shuffle button
                    HStack {
                        Text("Found \(performerScenes.count) scenes")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button(action: shuffleAndPlayScene) {
                            HStack(spacing: 4) {
                                Image(systemName: "shuffle")
                                Text("Shuffle")
                            }
                            .font(.system(size: 14, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .tint(.accentColor)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: 16) {
                        ForEach(performerScenes) { scene in
                            // Use our custom scene row with direct navigation
                            CustomPerformerSceneRow(scene: scene)
                                .id("scene-\(scene.id)")
                        }
                }
                .padding()
                } // End of VStack for scenes content
                }
            } // End of outer VStack
        }
        .id("scenesScrollView-\(performer.id)") // Add stable ID to prevent scroll reset
        }
    }
    
    private var markersContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Add debug Text to show actual markers count
                Text("Debug: \(appModel.api.markers.count) markers, \(markerCount) total")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.top, 4)

                if appModel.api.markers.isEmpty {
                // Show loading indicator if API is loading or force trigger a load
                VStack(spacing: 20) {
                    if appModel.api.isLoading {
                        ProgressView()
                            .padding()
                        Text("Loading markers...")
                            .foregroundColor(.secondary)
                    } else {
                        Text("No markers found")
                            .foregroundColor(.secondary)

                        // Add reload button
                        Button("Reload Markers") {
                            Task {
                                print("🔄 MARKERS VIEW - Manual reload requested")
                                await MainActor.run {
                                    appModel.api.markers = []
                                }
                                await loadMarkers()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                // Removed onAppear to prevent duplicate loading
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: 16) {
                    // Get markers list for this view
                    let markersList = appModel.api.markers
                    
                    ForEach(markersList) { marker in
                        MarkerRow(
                            marker: marker,
                            serverAddress: appModel.serverAddress,
                            onTitleTap: { marker in
                                appModel.navigateToMarker(marker)
                            },
                            onTagTap: { _ in },
                            onPerformerTap: { _ in
                                // The normal onPerformerTap is disabled
                                // We'll handle performer navigation with custom components
                            }
                        )
                        .id(marker.id) // Force unique ID for each marker
                        .onAppear {
                            print("🎬🎬🎬 MARKER DEBUG: Marker row appeared")
                            print("🎬 MARKER DEBUG: ID: \(marker.id), title: \(marker.title)")
                            print("🎬 MARKER DEBUG: Scene ID: \(marker.scene.id)")
                            print("🎬 MARKER DEBUG: Stream URL: \(marker.stream)")
                            print("🎬 MARKER DEBUG: Preview URL: \(marker.preview)")
                            print("🎬 MARKER DEBUG: Seconds: \(marker.seconds)")
                            
                            // Force refresh preview (this helps with stubborn previews)
                            NotificationCenter.default.post(name: Notification.Name("ForceMarkerPreview\(marker.id)"), object: nil)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                }
            } // End of outer VStack
        }
        .id("markersScrollView-\(performer.id)") // Add stable ID to prevent scroll reset
    }
    
    private func loadScenes() async {
        print("🔍 LOADSCENES - Starting load of scenes for performer: \(performer.name) (ID: \(performer.id))")

        // Check if already loading
        if isLoadingScenes {
            print("⚠️ LOADSCENES - Already loading scenes, skipping duplicate request")
            return
        }

        // First, check if we already have scenes for this performer
        if !performerScenes.isEmpty {
            print("✅ LOADSCENES - Already have \(performerScenes.count) scenes, skipping load")

            // If we already have scenes but the app doesn't know about them, update app state
            if appModel.api.scenes.isEmpty {
                await MainActor.run {
                    print("⚠️ LOADSCENES - App state missing scenes, syncing with local state")
                    appModel.api.scenes = performerScenes
                }
            }
            return
        }

        // Set loading state first thing
        await MainActor.run {
            isLoadingScenes = true
            appModel.api.isLoading = true
        }

        // Use a more direct and reliable GraphQL query approach first
        print("🔍 LOADSCENES - Using direct GraphQL query for reliability")
        
        // This is the most reliable approach - direct GraphQL query
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

        // Clear existing scenes to prevent showing incorrect data
        await MainActor.run {
            print("🧹 LOADSCENES - Clearing scenes array, current count: \(appModel.api.scenes.count)")
            appModel.api.scenes = []
            // Also clear our local state
            performerScenes = []
            print("🧹 LOADSCENES - Cleared scenes array")
        }

        // Execute the direct query first - this is more reliable
        do {
            print("🔄 LOADSCENES - Executing direct GraphQL query")
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
                
                // Add optional error handling
                struct GraphQLError: Decodable {
                    let message: String
                }
                let errors: [GraphQLError]?
            }

            let response = try JSONDecoder().decode(FindScenesResponse.self, from: data)
            
            // Check for GraphQL errors
            if let errors = response.errors, !errors.isEmpty {
                let errorMessages = errors.map { $0.message }.joined(separator: ", ")
                print("⚠️ LOADSCENES - GraphQL error: \(errorMessages)")
                throw NSError(domain: "GraphQLError", code: 500, userInfo: [NSLocalizedDescriptionKey: errorMessages])
            }

            await MainActor.run {
                // Update both state variables
                appModel.api.scenes = response.data.findScenes.scenes
                performerScenes = response.data.findScenes.scenes
                appModel.api.isLoading = false
                print("✅ LOADSCENES - Successfully loaded \(performerScenes.count) scenes via direct query")
                
                // Extra debugging for the first few scenes
                for (index, scene) in performerScenes.prefix(3).enumerated() {
                    print("🔍 LOADSCENES - Scene \(index): \(scene.title ?? "No title") (ID: \(scene.id))")
                }
            }
            
            // Reset loading flag on success
            await MainActor.run {
                isLoadingScenes = false
            }
            return // Success! Exit early
        } catch {
            print("⚠️ LOADSCENES - Direct query failed: \(error.localizedDescription)")
            
            // Continue to fallback method if direct query fails
            print("🔄 LOADSCENES - Falling back to standard API method")
        }

        // FALLBACK: Use the standard API method as a backup
        print("🔄 LOADSCENES - Calling fetchPerformerScenes fallback for performer \(performer.id)")
        await appModel.api.fetchPerformerScenes(
            performerId: performer.id,
            page: 1,
            perPage: 60, // Increased page size for better results
            sort: "date",
            direction: "DESC",
            appendResults: false
        )

        print("✅ LOADSCENES - API fallback call completed")
        print("✅ LOADSCENES - Scenes array count: \(appModel.api.scenes.count)")

        // Update our local state with the results
        await MainActor.run {
            appModel.api.isLoading = false
            if !appModel.api.scenes.isEmpty {
                performerScenes = appModel.api.scenes
                print("✅ LOADSCENES - Updated local performerScenes, count: \(performerScenes.count)")
            } else {
                print("⚠️ LOADSCENES - API returned empty scenes array")
            }
        }

        print("✅ LOADSCENES - Loaded \(performerScenes.count) scenes for performer: \(performer.name)")
        
        // Reset loading flag
        await MainActor.run {
            isLoadingScenes = false
        }
    }
    
    private func loadMarkers() async {
        print("🔍 LOADMARKERS - Starting load of markers for performer: \(performer.name) (ID: \(performer.id))")

        // Check if already loading
        if isLoadingMarkers {
            print("⚠️ LOADMARKERS - Already loading markers, skipping duplicate request")
            return
        }

        // Check if we already have markers loaded
        if !appModel.api.markers.isEmpty {
            print("✅ LOADMARKERS - Already have \(appModel.api.markers.count) markers, skipping load")
            return
        }

        // Set loading flag and clear existing markers
        await MainActor.run {
            isLoadingMarkers = true
            appModel.api.markers = []
            print("🧹 LOADMARKERS - Cleared markers array")
        }

        print("🔄 LOADMARKERS - Calling fetchPerformerMarkers for performer \(performer.id)")
        await appModel.api.fetchPerformerMarkers(performerId: performer.id, page: 1, appendResults: false)
        print("✅ LOADMARKERS - Loaded \(appModel.api.markers.count) markers for performer: \(performer.name)")
        
        // Reset loading flag
        await MainActor.run {
            isLoadingMarkers = false
        }
    }
    
    private func shuffleAndPlayScene() {
        print("🎲 Shuffle scenes for performer: \(performer.name)")
        
        // FIXED: Try both local performerScenes and appModel.api.scenes to ensure we have scenes
        let availableScenes = !performerScenes.isEmpty ? performerScenes : appModel.api.scenes
        
        if availableScenes.isEmpty {
            print("⚠️ No scenes available to shuffle - attempting to reload")
            Task {
                await loadScenes()
                // After loading, try again if we have scenes now
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if !self.performerScenes.isEmpty {
                        self.shuffleAndPlayScene()
                    }
                }
            }
            return
        }
        
        // Get a random scene from available scenes
        guard let randomScene = availableScenes.randomElement() else {
            print("⚠️ Could not get random scene")
            return
        }
        
        print("🎲 Selected random scene: \(randomScene.title ?? "Untitled") from \(availableScenes.count) available scenes")
        
        // FIXED: Ensure currentPerformer is set before navigation to maintain context
        appModel.currentPerformer = performer
        print("🎯 SHUFFLE - Set currentPerformer to: \(performer.name)")
        
        // Navigate to the scene first
        appModel.navigateToScene(randomScene)
        
        // Then jump to a random position after the player is initialized
        // This matches the behavior in SceneRow
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            // Look for the player from the registry
            if let player = VideoPlayerRegistry.shared.currentPlayer {
                print("🎲 Got player from registry, attempting to jump to random position")
                
                // Check if the player is ready
                if let currentItem = player.currentItem, currentItem.status == .readyToPlay {
                    print("🎲 Player is ready, jumping to random position")
                    VideoPlayerUtility.jumpToRandomPosition(in: player)
                } else {
                    print("🎲 Player not ready yet, will retry in 1.5 seconds")
                    
                    // Retry after another delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if let player = VideoPlayerRegistry.shared.currentPlayer,
                           let currentItem = player.currentItem,
                           currentItem.status == .readyToPlay {
                            print("🎲 Player is now ready (retry), jumping to random position")
                            VideoPlayerUtility.jumpToRandomPosition(in: player)
                        } else {
                            print("🎲 Player still not ready after retry")
                            
                            // One final attempt with a longer delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                if let player = VideoPlayerRegistry.shared.currentPlayer {
                                    print("🎲 Final attempt to jump to random position")
                                    // Force the jump even if not fully ready
                                    VideoPlayerUtility.jumpToRandomPosition(in: player)
                                }
                            }
                        }
                    }
                }
            } else {
                print("⚠️ Failed to get player from registry")
            }
        }
    }
    
    private func getMarkerCount() async -> Int {
        // Using the correct format and modifiers that match Vision Pro implementation
        let query = """
        {
            "operationName": "FindSceneMarkers",
            "variables": {
                "filter": {
                    "q": "",
                    "page": 1,
                    "per_page": 1,
                    "sort": "title",
                    "direction": "ASC"
                },
                "scene_marker_filter": {
                    "performers": {
                        "value": ["\(performer.id)"],
                        "modifier": "INCLUDES"
                    }
                }
            },
            "query": "query FindSceneMarkers($filter: FindFilterType, $scene_marker_filter: SceneMarkerFilterType) { findSceneMarkers(filter: $filter, scene_marker_filter: $scene_marker_filter) { count } }"
        }
        """

        do {
            print("📊 Fetching marker count for performer: \(performer.name) (ID: \(performer.id))")
            // Use the executeGraphQLQuery method that we've enhanced with proper auth
            let data = try await appModel.api.executeGraphQLQuery(query)

            // Debug the response
            if let responseStr = String(data: data, encoding: .utf8) {
                print("📊 Marker count raw response: \(responseStr.prefix(100))...")
            }

            struct MarkerCountResponse: Decodable {
                let data: DataResponse

                struct DataResponse: Decodable {
                    let findSceneMarkers: MarkersResponse

                    struct MarkersResponse: Decodable {
                        let count: Int
                    }
                }
            }

            let response = try JSONDecoder().decode(MarkerCountResponse.self, from: data)
            print("✅ Found \(response.data.findSceneMarkers.count) markers for performer \(performer.name)")
            return response.data.findSceneMarkers.count
        } catch {
            print("❌ Error fetching marker count: \(error)")
            // Provide detailed error info for debugging
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("Missing key: \(key) - \(context.debugDescription)")
                case .typeMismatch(let type, let context):
                    print("Type mismatch: \(type) - \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    print("Value not found: \(type) - \(context.debugDescription)")
                case .dataCorrupted(let context):
                    print("Data corrupted: \(context.debugDescription)")
                @unknown default:
                    print("Unknown decoding error")
                }
            }
            return 0
        }
    }
} 