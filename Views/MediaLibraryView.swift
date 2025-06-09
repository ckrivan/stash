import SwiftUI
import AVKit
import Foundation

struct MediaLibraryToolbar: View {
    let onShowFilters: () -> Void
    let onRefresh: () -> Void
    
    var body: some View {
        Menu {
            Button(action: onShowFilters) {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
            }
            
            Button(action: onRefresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}

struct MediaLibraryView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedScene: StashScene?
    @State private var showingFilters = false
    @State private var currentPage = 1
    @State private var isLoadingMore = false
    @State private var hasMorePages = true
    @State private var selectedTag: StashScene.Tag?
    @State private var selectedPerformer: StashScene.Performer?
    @State private var filterOptions = FilterOptions()
    @State private var currentFilter: String = "default"
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchScope = UniversalSearchView.SearchScope.scenes
    @State private var searchedMarkers: [SceneMarker] = []
    @State private var totalMarkerCount: Int = 0
    @State private var searchedTag: (id: String, name: String)? = nil
    @State private var viewRefreshId = UUID()  // Add view refresh trigger
    
    private var columns: [GridItem] {
        // Use different column sizes on iPad vs iPhone
        if UIDevice.current.userInterfaceIdiom == .pad {
            return [
                GridItem(.adaptive(minimum: 350, maximum: 450), spacing: 20)
            ]
        } else {
            // Much smaller minimum for iPhone to fit screen properly
            return [
                GridItem(.adaptive(minimum: 280, maximum: 350), spacing: 12)
            ]
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Universal search bar
            UniversalSearchView(
                searchText: $searchText,
                isSearching: $isSearching,
                searchScope: $searchScope,
                onSearch: { query, scope in
                    Task {
                        await performSearch(query: query, scope: scope)
                    }
                },
                // Pass filter actions for iOS inline button
                currentFilter: $currentFilter,
                onDefaultSelected: {
                    print("📱 iPhone: Default filter selected")
                    Task {
                        await filterAction(filter: "default", sort: "file_mod_time", direction: "DESC")
                    }
                },
                onNewestSelected: {
                    print("📱 iPhone: Newest filter selected")
                    Task {
                        await filterAction(filter: "newest", sort: "date", direction: "DESC")
                    }
                },
                onOCounterSelected: {
                    print("📱 iPhone: Most Played filter selected")
                    Task {
                        await filterAction(filter: "o_counter", sort: "o_counter", direction: "DESC")
                    }
                },
                onRandomSelected: {
                    print("📱 iPhone: Random filter selected")
                    Task {
                        await filterAction(filter: "random", sort: "random", direction: "DESC")
                    }
                },
                onAdvancedFilters: {
                    showingFilters = true
                },
                onReload: {
                    Task {
                        await resetAndReload()
                    }
                },
                onShuffleMostPlayed: {
                    print("🎯 iPhone: Shuffle Most Played tapped")
                    shuffleMostPlayedScenes()
                }
            )
            .padding(.vertical, 10)
            
            Group {
                if appModel.api.isLoading && currentPage == 1 {
                    VStack {
                        ProgressView("Loading media...")
                            .scaleEffect(1.2)

                        Text("Loading your media library...")
                            .foregroundColor(.secondary)
                            .padding(.top)
                    }
                } else if let error = appModel.api.error, currentFilter == "search" {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                            .padding(.top, 40)
                        
                        Text("Search Error")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(error.localizedDescription)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Try Again") {
                            Task {
                                await performSearch(query: searchText, scope: searchScope)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 10)
                    }
                    .padding(.top, 40)
                } else {
                    scenesContent
                        .id(viewRefreshId)  // Force refresh when search results change
                }
            }
        }
        .sheet(item: $selectedTag) { tag in
            NavigationStack {
                TaggedScenesView(tag: tag)
                    .environmentObject(appModel)
            }
        }
        .sheet(isPresented: $showingFilters) {
            FilterOptionsView(
                filterOptions: $filterOptions,
                onApply: {
                    Task {
                        currentFilter = "custom"
                        await appModel.api.fetchScenes(page: 1, filterOptions: filterOptions)
                    }
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowAdvancedFilters"))) { _ in
            showingFilters = true
        }
    }
    
    private var scenesContent: some View {
        ScrollView {
            // Debug state
            let _ = print("🎯 scenesContent - filter: \(currentFilter), scope: \(searchScope), markers: \(searchedMarkers.count), scenes: \(appModel.api.scenes.count)")
            
            if !searchedMarkers.isEmpty && searchScope == .markers && currentFilter == "search" {
                // Show marker search results
                let _ = print("📍 Showing marker search results: \(searchedMarkers.count) markers (total: \(totalMarkerCount))")
                VStack {
                    MarkersSearchResultsView(markers: searchedMarkers, totalCount: totalMarkerCount) { marker in
                        // Automatic pagination is disabled - users can manually load more with the button
                        // This prevents performance issues from loading too many markers automatically
                    }
                    
                    // Show load more button if we have more markers available
                    if searchedMarkers.count >= 50 {
                        VStack(spacing: 12) {
                            if totalMarkerCount > 0 && searchedMarkers.count < totalMarkerCount {
                                // Show load more button when there are more markers available
                                Button(action: {
                                    Task {
                                        await loadMoreMarkersManually()
                                    }
                                }) {
                                    HStack {
                                        if isLoadingMore {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                                .padding(.trailing, 8)
                                        } else {
                                            Image(systemName: "arrow.down.circle.fill")
                                                .font(.title2)
                                                .padding(.trailing, 8)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(isLoadingMore ? "Loading..." : "Load More Markers")
                                                .font(.headline)
                                                .fontWeight(.semibold)
                                            Text("Showing \(searchedMarkers.count) of \(totalMarkerCount) total")
                                                .font(.caption)
                                                .opacity(0.8)
                                        }
                                        
                                        Spacer()
                                    }
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(
                                        LinearGradient(
                                            colors: [Color.blue, Color.purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(12)
                                    .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                                }
                                .disabled(isLoadingMore)
                                .padding(.horizontal)
                            } else {
                                // Show completion message when all markers are loaded
                                VStack(spacing: 8) {
                                    Text("✅ All \(searchedMarkers.count) markers loaded")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.green)
                                    Text("Use more specific search terms to narrow results")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .environmentObject(appModel)
            } else if searchedTag != nil && searchScope == .tags && currentFilter == "search" && !appModel.api.scenes.isEmpty {
                // Show tag search results
                let _ = print("🏷️ Showing tag search results: \(appModel.api.scenes.count) scenes for tag: \(searchedTag!.name)")
                TagSearchResultsView(scenes: appModel.api.scenes, tagName: searchedTag!.name, tagId: searchedTag!.id)
                    .environmentObject(appModel)
            } else if appModel.api.scenes.isEmpty && !appModel.api.isLoading {
                VStack(spacing: 20) {
                    Image(systemName: "film")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
                    
                    Text("No media found")
                        .font(.title2)
                    
                    Text("Try refreshing or check your connection")
                        .foregroundColor(.secondary)
                    
                    Button("Refresh") {
                        Task {
                            await resetAndReload()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 10)
                }
                .padding(.top, 40)
            } else {
                ScenesGrid(
                    scenes: appModel.api.scenes,
                    columns: columns,
                    onSceneSelected: { scene in
                        appModel.navigateToScene(scene)
                    },
                    onTagSelected: { selectedTag = $0 },
                    onPerformerSelected: { performer in
                        print("🔍 MediaLibraryView: Performer selected: \(performer.name) (ID: \(performer.id))")
                        appModel.navigateToPerformer(performer)
                    },
                    onSceneAppear: { scene in
                        if scene == appModel.api.scenes.last && !isLoadingMore && hasMorePages {
                            Task {
                                await loadMoreScenes()
                            }
                        }
                    },
                    onSceneUpdated: { updatedScene in
                        if let index = appModel.api.scenes.firstIndex(where: { $0.id == updatedScene.id }) {
                            appModel.api.scenes[index] = updatedScene
                        }
                    },
                    isLoadingMore: isLoadingMore
                )
            }
        }
        .refreshable {
            await resetAndReload()
        }
        .navigationTitle("Media Library")
        .toolbar {
            // Only show toolbar buttons on iPad - iOS uses inline filter button only  
            if UIDevice.current.userInterfaceIdiom == .pad {
                let _ = print("🎯 iPad Toolbar - currentFilter: \(currentFilter)")
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button {
                            Task {
                                await resetAndReload()
                            }
                        } label: {
                            Image(systemName: "shuffle")
                        }
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5)
                                .onEnded { _ in
                                    playRandomScene()
                                }
                        )
                        .contextMenu {
                            Button {
                                Task {
                                    await resetAndReload()
                                }
                            } label: {
                                Label("Shuffle List", systemImage: "shuffle")
                            }
                            
                            Button {
                                playRandomScene()
                            } label: {
                                Label("Shuffle Play", systemImage: "play.fill")
                            }
                            
                            if currentFilter == "o_counter" {
                                Divider()
                                Button {
                                    shuffleMostPlayedScenes()
                                } label: {
                                    Label("Shuffle Most Played", systemImage: "number.circle.fill")
                                }
                            }
                        }
                        
                        FilterMenuView(
                            currentFilter: $currentFilter,
                            onDefaultSelected: {
                                Task {
                                    await filterAction(filter: "default", sort: "file_mod_time", direction: "DESC")
                                }
                            },
                            onNewestSelected: {
                                Task {
                                    await filterAction(filter: "newest", sort: "date", direction: "DESC")
                                }
                            },
                            onOCounterSelected: {
                                Task {
                                    await filterAction(filter: "o_counter", sort: "o_counter", direction: "DESC")
                                }
                            },
                            onRandomSelected: {
                                Task {
                                    await filterAction(filter: "random", sort: "random", direction: "DESC")
                                }
                            },
                            onAdvancedFilters: {
                                showingFilters = true
                            },
                            onReload: {
                                Task {
                                    await resetAndReload()
                                }
                            }
                        )
                    }
                }
            }
        }
        .task {
            // Always attempt to load on appearance, but not when searching
            if appModel.api.scenes.isEmpty && currentFilter != "search" && searchedMarkers.isEmpty && !isSearching {
                print("🔄 MediaLibraryView .task triggered - loading initial scenes")
                Task {
                    await initialLoad()
                    print("🔄 Loaded scenes in MediaLibraryView: \(appModel.api.scenes.count)")
                }
            }
        }
        .onAppear {
            // Fallback to ensure scenes load even if .task doesn't fire
            if appModel.api.scenes.isEmpty && currentFilter != "search" && searchedMarkers.isEmpty && !isSearching {
                print("🔄 MediaLibraryView .onAppear fallback - loading initial scenes")
                Task {
                    await initialLoad()
                    print("🔄 Loaded scenes in MediaLibraryView (onAppear): \(appModel.api.scenes.count)")
                }
            }
        }
    }
    
    private func initialLoad() async {
        print("📱 initialLoad() called - currentFilter: \(currentFilter)")
        currentPage = 1
        hasMorePages = true
        appModel.api.scenes = []
        await loadScenes()
    }
    
    private func resetAndReload() async {
        searchedMarkers = []  // Clear any searched markers
        searchedTag = nil     // Clear any searched tag
        currentFilter = "default"  // Reset filter to default
        searchScope = .scenes  // Reset scope to scenes
        await initialLoad()
    }
    
    private func filterAction(filter: String, sort: String, direction: String) async {
        print("📱 filterAction called - filter: \(filter), sort: \(sort), direction: \(direction)")
        print("📱 currentFilter before: \(currentFilter)")
        
        // Set currentFilter to keep UI in sync
        await MainActor.run {
            currentFilter = filter
        }
        
        print("📱 currentFilter after: \(currentFilter)")
        currentPage = 1
        hasMorePages = true
        
        // Clear scenes to show loading state and force UI refresh
        let previousScenes = appModel.api.scenes
        await MainActor.run {
            appModel.api.scenes = []
            appModel.objectWillChange.send()
        }
        print("📱 About to call fetchScenes with sort: \(sort)")
        
        do {
            await appModel.api.fetchScenes(page: 1, sort: sort, direction: direction)
            print("📱 fetchScenes completed successfully, scenes count: \(appModel.api.scenes.count)")
            await MainActor.run {
                appModel.objectWillChange.send()
            }
        } catch {
            // If API call fails, restore previous scenes
            await MainActor.run {
                appModel.api.scenes = previousScenes
                appModel.objectWillChange.send()
            }
            print("❌ Filter action failed, restored previous scenes. Error: \(error)")
        }
    }
    
    private func loadScenes() async {
        print("📤 loadScenes called - currentFilter: \(currentFilter), searchScope: \(searchScope), markers count: \(searchedMarkers.count)")
        
        // Don't load scenes if we're showing marker search results
        if currentFilter == "search" && searchScope == .markers && !searchedMarkers.isEmpty {
            print("⚠️ Skipping scene load - showing marker search results")
            return
        }
        
        // Use different sorting based on the current filter
        switch currentFilter {
        case "newest":
            await appModel.api.fetchScenes(page: currentPage, sort: "date", direction: "DESC", appendResults: false)
        case "o_counter":
            await appModel.api.fetchScenes(page: currentPage, sort: "o_counter", direction: "DESC", appendResults: false)
        case "random":
            await appModel.api.fetchScenes(page: currentPage, sort: "random", direction: "DESC", appendResults: false)
        case "custom":
            await appModel.api.fetchScenes(page: currentPage, sort: "date", direction: "DESC", appendResults: false, filterOptions: filterOptions)
        default:
            await appModel.api.fetchScenes(page: currentPage, sort: "file_mod_time", direction: "DESC", appendResults: false)
        }
    }
    
    private func loadMoreScenes() async {
        guard hasMorePages && !isLoadingMore else { return }

        isLoadingMore = true
        currentPage += 1

        print("🔥 Loading more scenes (page \(currentPage))")
        let previousCount = appModel.api.scenes.count

        // Use different sorting based on the current filter for loading more
        switch currentFilter {
        case "newest":
            await appModel.api.fetchScenes(page: currentPage, sort: "date", direction: "DESC", appendResults: true)
        case "o_counter":
            await appModel.api.fetchScenes(page: currentPage, sort: "o_counter", direction: "DESC", appendResults: true)
        case "random":
            await appModel.api.fetchScenes(page: currentPage, sort: "random", direction: "DESC", appendResults: true)
        case "custom":
            await appModel.api.fetchScenes(page: currentPage, sort: "date", direction: "DESC", appendResults: true, filterOptions: filterOptions)
        default:
            await appModel.api.fetchScenes(page: currentPage, sort: "file_mod_time", direction: "DESC", appendResults: true)
        }

        hasMorePages = appModel.api.scenes.count > previousCount
        isLoadingMore = false
    }
    
    private func loadMoreMarkers() async {
        guard hasMorePages && !isLoadingMore && searchScope == .markers && !searchText.isEmpty else { return }
        
        // Limit total markers to prevent app from becoming unusable
        guard searchedMarkers.count < 50 else {
            print("⚠️ Reached marker limit (50) - stopping automatic pagination")
            hasMorePages = false
            return
        }

        isLoadingMore = true
        currentPage += 1

        print("🔥 Loading more markers (page \(currentPage)) for query: '\(searchText)' (current: \(searchedMarkers.count))")
        let previousCount = searchedMarkers.count

        do {
            let newMarkers = try await appModel.api.searchMarkers(query: searchText, page: currentPage, perPage: 50)
            print("📊 Found \(newMarkers.count) additional markers on page \(currentPage)")
            
            await MainActor.run {
                // Filter out duplicates before appending
                let uniqueNewMarkers = newMarkers.filter { newMarker in
                    !searchedMarkers.contains { $0.id == newMarker.id }
                }
                
                searchedMarkers.append(contentsOf: uniqueNewMarkers)
                hasMorePages = uniqueNewMarkers.count >= 50
                
                print("✅ Added \(uniqueNewMarkers.count) new markers (total: \(searchedMarkers.count), hasMorePages: \(hasMorePages))")
            }
        } catch {
            print("❌ Error loading more markers: \(error)")
            await MainActor.run {
                hasMorePages = false
            }
        }

        isLoadingMore = false
    }
    
    private func loadMoreMarkersManually() async {
        guard !isLoadingMore && searchScope == .markers && !searchText.isEmpty else { return }

        isLoadingMore = true
        currentPage += 1

        print("🔥 Manual loading more markers (page \(currentPage)) for query: '\(searchText)' (current: \(searchedMarkers.count))")
        let previousCount = searchedMarkers.count

        do {
            let newMarkers = try await appModel.api.searchMarkers(query: searchText, page: currentPage, perPage: 50)
            print("📊 Found \(newMarkers.count) additional markers on page \(currentPage)")
            
            await MainActor.run {
                // Filter out duplicates before appending
                let uniqueNewMarkers = newMarkers.filter { newMarker in
                    !searchedMarkers.contains { $0.id == newMarker.id }
                }
                
                searchedMarkers.append(contentsOf: uniqueNewMarkers)
                hasMorePages = uniqueNewMarkers.count >= 50
                
                print("✅ Added \(uniqueNewMarkers.count) new markers (total: \(searchedMarkers.count), hasMorePages: \(hasMorePages))")
            }
        } catch {
            print("❌ Error loading more markers: \(error)")
            await MainActor.run {
                hasMorePages = false
            }
        }

        isLoadingMore = false
    }
    
    private func playRandomScene() {
        guard let randomScene = appModel.api.scenes.randomElement() else { return }
        appModel.navigateToScene(randomScene)
    }
    
    private func shuffleMostPlayedScenes() {
        print("🎯 Starting most played shuffle from MediaLibraryView")
        
        // Use the AppModel's new most played shuffle system
        appModel.startMostPlayedShuffle(from: appModel.api.scenes)
    }
    
    private func performSearch(query: String, scope: UniversalSearchView.SearchScope) async {
        if query.isEmpty {
            // Reset to default view
            currentFilter = "default"
            searchedMarkers = [] // Clear markers
            await resetAndReload()
            return
        }
        
        // Set search state immediately before starting the search
        await MainActor.run {
            currentFilter = "search"
            currentPage = 1
            hasMorePages = (scope == .markers) // Enable pagination for marker searches, disable for others
            searchScope = scope  // Ensure scope is set correctly
            
            // Clear previous search results based on scope
            if scope != .markers {
                searchedMarkers = []
            }
            if scope != .tags {
                searchedTag = nil
            }
        }
        
        do {
            switch scope {
            case .scenes:
                // Search scenes
                print("🔍 Searching scenes with query: '\(query)'")
                let searchResults = try await appModel.api.searchScenes(query: query)
                print("📊 Search results count: \(searchResults.count)")
                if !searchResults.isEmpty {
                    print("📊 First result: ID=\(searchResults[0].id), Title='\(searchResults[0].title ?? "no title")'")
                }
                await MainActor.run {
                    appModel.api.scenes = searchResults
                    appModel.api.totalSceneCount = searchResults.count
                    // Explicitly trigger UI update
                    appModel.objectWillChange.send()
                }
                
            case .performers:
                // Search performers and directly query for scenes
                print("🔍 Searching performers with query: '\(query)'")
                
                // Perform a custom search without filters
                let escapedQuery = query
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                
                let graphQLQuery = """
                {
                    "operationName": "FindPerformers",
                    "variables": {
                        "filter": {
                            "q": "\(escapedQuery)",
                            "page": 1,
                            "per_page": 20,
                            "sort": "name",
                            "direction": "ASC"
                        }
                    },
                    "query": "query FindPerformers($filter: FindFilterType) { findPerformers(filter: $filter) { count performers { id name gender scene_count favorite } } }"
                }
                """
                
                do {
                    let data = try await appModel.api.executeGraphQLQueryAsync(graphQLQuery)
                    
                    // Decode the response
                    struct PerformersSearchResponse: Decodable {
                        let data: DataWrapper
                        
                        struct DataWrapper: Decodable {
                            let findPerformers: FindPerformersResult
                        }
                        
                        struct FindPerformersResult: Decodable {
                            let count: Int
                            let performers: [StashScene.Performer]
                        }
                    }
                    
                    let response = try JSONDecoder().decode(PerformersSearchResponse.self, from: data)
                    let performers = response.data.findPerformers.performers
                    
                    print("📊 Found \(performers.count) performers matching '\(query)'")
                    
                    // Get scenes from the first performer
                    if let firstPerformer = performers.first {
                        print("📊 Fetching scenes for performer: \(firstPerformer.name)")
                        await appModel.api.fetchPerformerScenes(performerId: firstPerformer.id, page: 1, appendResults: false)
                        
                        // Small delay to ensure UI updates
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        
                        await MainActor.run {
                            print("✅ Found \(appModel.api.scenes.count) scenes for performer: \(firstPerformer.name)")
                            // Explicitly trigger UI update
                            appModel.objectWillChange.send()
                        }
                    } else {
                        await MainActor.run {
                            appModel.api.scenes = []
                            appModel.api.totalSceneCount = 0
                            appModel.objectWillChange.send()
                        }
                    }
                } catch {
                    print("❌ Performer search error: \(error)")
                    await MainActor.run {
                        appModel.api.error = error
                        appModel.api.scenes = []
                        appModel.api.totalSceneCount = 0
                    }
                }
                
            case .tags:
                // Search tags and then find scenes with those tags
                do {
                    print("🔍 Searching tags with query: '\(query)'")
                    let tags = try await appModel.api.searchTags(query: query)
                    print("📊 Found \(tags.count) tags matching '\(query)'")
                    
                    if let firstTag = tags.first {
                        print("🔍 Found tag: \(firstTag.name) with ID: \(firstTag.id)")
                        let sceneFilter = SceneFilterType(tags: [firstTag.id])
                        let (scenes, count) = try await appModel.api.findScenes(filter: sceneFilter)
                        await MainActor.run {
                            searchedTag = (id: firstTag.id, name: firstTag.name)
                            appModel.api.scenes = scenes
                            appModel.api.totalSceneCount = count
                            print("✅ Found \(count) scenes with tag: \(firstTag.name)")
                            // Explicitly trigger UI update
                            appModel.objectWillChange.send()
                        }
                    } else {
                        print("⚠️ No tags found matching: \(query)")
                        await MainActor.run {
                            searchedTag = nil
                            appModel.api.scenes = []
                            appModel.api.totalSceneCount = 0
                            // Explicitly trigger UI update
                            appModel.objectWillChange.send()
                        }
                    }
                } catch {
                    print("❌ Tag search error: \(error)")
                    throw error
                }
                
            case .markers:
                // Search markers with pagination support and total count
                print("🔍 Searching markers with query: '\(query)' (page 1)")
                let (markers, totalCount) = try await appModel.api.searchMarkersWithCount(query: query, page: 1, perPage: 50)
                print("📊 Found \(markers.count) markers matching '\(query)' on page 1 (total: \(totalCount))")
                
                // Debug - print first few marker titles
                for (index, marker) in markers.prefix(5).enumerated() {
                    print("  Marker \(index): '\(marker.title)' (ID: \(marker.id))")
                }
                
                await MainActor.run {
                    searchedMarkers = markers
                    totalMarkerCount = totalCount
                    appModel.api.scenes = []  // Clear scenes since we're showing markers
                    appModel.api.totalSceneCount = 0
                    currentFilter = "search"  // Ensure we stay in search mode
                    searchScope = .markers    // Ensure scope is set to markers
                    
                    // IMPORTANT: Store the search query in app model for shuffle functionality
                    appModel.searchQuery = query
                    print("📝 Stored search query in appModel: '\(query)'")
                    
                    // Enable pagination if we got a full page of results
                    hasMorePages = markers.count >= 50
                    
                    viewRefreshId = UUID()   // Force view refresh
                    print("✅ Stored \(markers.count) marker results (total: \(totalCount)) - filter: \(currentFilter), scope: \(searchScope), hasMorePages: \(hasMorePages)")
                    // Explicitly trigger UI update
                    appModel.objectWillChange.send()
                }
            }
        } catch {
            await MainActor.run {
                appModel.api.error = error
                appModel.api.scenes = []
                appModel.api.totalSceneCount = 0
            }
        }
    }
} 