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
    @State private var showingMarkerTagSelector = false  // Control tag selector from parent
    @State private var markerTagSelectorTags: [SceneMarker.Tag] = []  // Tags for selector
    
    // Locked tags system for progressive tag search
    @State private var lockedTags: [(name: String, count: Int)] = []  // Tags that are locked in
    @State private var isValidatingTag = false  // Loading state for tag validation
    @State private var lastValidatedTag: String? = nil  // Track which tag was just validated
    
    // Tag suggestion system for disambiguation  
    @State private var suggestedTags: [StashScene.Tag] = []
    @State private var showingTagSuggestions = false
    @State private var originalSearchQuery = ""
    
    
    // Show watch history when we have watched scenes and the flag is set (returning from video)
    private var shouldShowWatchHistory: Bool {
        return !appModel.watchHistory.isEmpty && 
               UserDefaults.standard.bool(forKey: "showWatchHistory") &&
               currentFilter == "default" && 
               !isSearching && 
               searchScope == .scenes &&
               searchText.isEmpty
    }
    
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
    
    // MARK: - Filter Action Closures
    private var onDefaultSelected: () -> Void {
        {
            print("📱 iPhone: Default filter selected")
            Task {
                await filterAction(filter: "default", sort: "file_mod_time", direction: "DESC")
            }
        }
    }
    
    private var onNewestSelected: () -> Void {
        {
            print("📱 iPhone: Newest filter selected")
            Task {
                await filterAction(filter: "newest", sort: "date", direction: "DESC")
            }
        }
    }
    
    private var onOCounterSelected: () -> Void {
        {
            print("📱 iPhone: Most Played filter selected")
            Task {
                await filterAction(filter: "o_counter", sort: "o_counter", direction: "DESC")
            }
        }
    }
    
    private var onRandomSelected: () -> Void {
        {
            print("📱 iPhone: Random filter selected")
            Task {
                await filterAction(filter: "random", sort: "random", direction: "DESC")
            }
        }
    }
    
    private var onAdvancedFilters: () -> Void {
        {
            showingFilters = true
        }
    }
    
    private var onReload: () -> Void {
        {
            Task {
                await resetAndReload()
            }
        }
    }
    
    private var onShuffleMostPlayed: () -> Void {
        {
            print("🎯 iPhone: Shuffle Most Played tapped")
            shuffleMostPlayedScenes()
        }
    }
    
    @ViewBuilder
    private var searchBarView: some View {
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
            onDefaultSelected: onDefaultSelected,
            onNewestSelected: onNewestSelected,
            onOCounterSelected: onOCounterSelected,
            onRandomSelected: onRandomSelected,
            onAdvancedFilters: onAdvancedFilters,
            onReload: onReload,
            onShuffleMostPlayed: onShuffleMostPlayed
        )
    }
    
    var body: some View {
        mainView
            .sheet(item: $selectedTag) { tag in
                taggedScenesSheetContent(tag: tag)
            }
            .sheet(isPresented: $showingFilters) {
                filtersSheetContent
            }
            .sheet(isPresented: $showingMarkerTagSelector) {
                markerTagSelectorSheetContent
            }
            .sheet(isPresented: $showingTagSuggestions) {
                tagSuggestionsSheetContent
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowAdvancedFilters"))) { _ in
                showingFilters = true
            }
    }
    
    @ViewBuilder
    private var mainView: some View {
        VStack(spacing: 0) {
            // Universal search bar
            searchBarView
            .padding(.vertical, 10)
            
            // Locked tags UI - only show for marker searches
            if searchScope == .markers && (!lockedTags.isEmpty || isValidatingTag) {
                lockedTagsView
            }
            
            mainContentView
        }
    }
    
    // MARK: - Sheet Content
    @ViewBuilder
    private func taggedScenesSheetContent(tag: StashScene.Tag) -> some View {
        NavigationStack {
            TaggedScenesView(tag: tag)
                .environmentObject(appModel)
        }
    }
    
    @ViewBuilder
    private var filtersSheetContent: some View {
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
    
    @ViewBuilder
    private var markerTagSelectorSheetContent: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("🎯 PARENT SHEET IS WORKING!")
                    .font(.title)
                    .foregroundColor(.green)
                
                Text("Available Tags: \(markerTagSelectorTags.count)")
                    .font(.headline)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                    ForEach(markerTagSelectorTags.prefix(10), id: \.id) { tag in
                        Button(tag.name) {
                            print("🏷️ Tag selected: \(tag.name)")
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
                .padding()
                
                Spacer()
            }
            .navigationTitle("Test Tag Selector")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        showingMarkerTagSelector = false
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var tagSuggestionsSheetContent: some View {
        NavigationView {
            tagSuggestionsList
                .navigationTitle("Choose Tag")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            print("🏷️ Tag suggestions cancelled")
                            showingTagSuggestions = false
                        }
                        .foregroundColor(.secondary)
                    }
                }
        }
    }
    
    @ViewBuilder
    private var tagSuggestionsList: some View {
        VStack(spacing: 20) {
            tagSuggestionsHeader
            tagSuggestionsGrid
            Spacer()
        }
    }
    
    @ViewBuilder
    private var tagSuggestionsHeader: some View {
        VStack(spacing: 12) {
            Text("🏷️ Multiple Tags Found")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Found \(suggestedTags.count) tags similar to '\(originalSearchQuery)'")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text("Which tag would you like to use?")
                .font(.headline)
                .padding(.top, 8)
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var tagSuggestionsGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 16) {
                ForEach(suggestedTags, id: \.id) { tag in
                    tagSuggestionButton(tag: tag)
                }
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private func tagSuggestionButton(tag: StashScene.Tag) -> some View {
        Button(action: {
            print("🏷️ Selected suggested tag: \(tag.name)")
            showingTagSuggestions = false
            searchText = tag.name
            Task {
                await performSearch(query: tag.name, scope: .markers)
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                Text(tag.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                
                HStack {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                    Text("Tag")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.purple, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var lockedTagsView: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("🔒 Locked Tags")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if isValidatingTag {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.leading, 8)
                }
                
                Spacer()
                
                if !lockedTags.isEmpty {
                    Button("Clear All") {
                        clearLockedTags()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            
            // Locked tags display
            if !lockedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(lockedTags.enumerated()), id: \.offset) { index, tag in
                            HStack(spacing: 6) {
                                Text(tag.name)
                                    .font(.system(size: 15, weight: .medium))
                                Text("(\(tag.count))")
                                    .font(.system(size: 13))
                                    .opacity(0.8)
                                
                                Button(action: {
                                    removeLockedTag(at: index)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(
                                    colors: [Color.green, Color.blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                        }
                        
                        // Combine all button
                        if lockedTags.count > 1 {
                            Button(action: {
                                combineAllLockedTags()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 14))
                                    Text("Search All")
                                        .font(.system(size: 15, weight: .medium))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(20)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            // Instructions
            if lockedTags.isEmpty && !isValidatingTag {
                Text("Search for a tag above to lock it in, then search for more to combine them")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator))
                .opacity(0.5),
            alignment: .bottom
        )
    }
    
    private var scenesContent: some View {
        ScrollView {
            // Debug state
            let _ = print("🎯 scenesContent - filter: \(currentFilter), scope: \(searchScope), markers: \(searchedMarkers.count), scenes: \(appModel.api.scenes.count)")
            
            if !searchedMarkers.isEmpty && searchScope == .markers && currentFilter == "search" {
                // Show marker search results
                let _ = print("📍 Showing marker search results: \(searchedMarkers.count) markers (total: \(totalMarkerCount))")
                VStack {
                    MarkersSearchResultsView(markers: searchedMarkers, totalCount: totalMarkerCount, onMarkerAppear: { marker in
                        // Automatic pagination is disabled - users can manually load more with the button
                        // This prevents performance issues from loading too many markers automatically
                    }, onOpenTagSelector: { tags in
                        print("🏷️ PARENT: Received callback with \(tags.count) tags")
                        print("🏷️ PARENT: Tag names: \(tags.map { $0.name })")
                        markerTagSelectorTags = tags
                        showingMarkerTagSelector = true
                        print("🏷️ PARENT: Set showingMarkerTagSelector = true")
                    })
                    
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
            } else if searchScope == .markers && currentFilter != "search" {
                // Show markers interface with default popular markers
                let _ = print("📍 Showing markers interface for tag combination")
                VStack {
                    MarkersSearchResultsView(markers: searchedMarkers, totalCount: totalMarkerCount, onMarkerAppear: { marker in
                        // Empty callback for initial state
                    }, onOpenTagSelector: { tags in
                        print("🏷️ PARENT: Received callback with \(tags.count) tags")
                        print("🏷️ PARENT: Tag names: \(tags.map { $0.name })")
                        markerTagSelectorTags = tags
                        showingMarkerTagSelector = true
                        print("🏷️ PARENT: Set showingMarkerTagSelector = true")
                    })
                }
                .environmentObject(appModel)
                .onAppear {
                    // Load some default popular markers when first appearing
                    if searchedMarkers.isEmpty {
                        Task {
                            await performSearch(query: "blowjob", scope: .markers)
                        }
                    }
                }
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
                // Show watch history if we have it and user is returning from video session
                let displayScenes = shouldShowWatchHistory ? appModel.watchHistory : appModel.api.scenes
                
                if shouldShowWatchHistory && !appModel.watchHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recently Watched")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            Button("Clear History") {
                                appModel.watchHistory.removeAll()
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.secondary)
                            
                            Button("Show All") {
                                // Clear watch history flag and return to normal view
                                UserDefaults.standard.removeObject(forKey: "showWatchHistory")
                                Task {
                                    await resetAndReload()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        
                        Text("\(appModel.watchHistory.count) scenes in your watch session")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                }
                
                ScenesGrid(
                    scenes: displayScenes,
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
        
        // Clear watch history flag when user explicitly changes filters
        UserDefaults.standard.removeObject(forKey: "showWatchHistory")
        
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
            if filter == "recently_added" {
                print("📱 Using VR exclusion fetch for recently added")
                await appModel.api.fetchScenesExcludingVR(page: 1, sort: sort, direction: direction)
            } else {
                await appModel.api.fetchScenes(page: 1, sort: sort, direction: direction)
            }
            print("📱 Fetch completed successfully, scenes count: \(appModel.api.scenes.count)")
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
            await MainActor.run {
                currentFilter = "default"
                searchedMarkers = [] // Clear markers
                isValidatingTag = false // Clear validation state
            }
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
                // Parse combined tag search (e.g., "blowjob +anal" or "panties to the side +cowgirl")
                let searchQuery = query.isEmpty ? "blowjob" : query // Default to popular search if empty
                
                // Split by + to get separate tag phrases (handles multi-word tags properly)
                let tagPhrases = searchQuery.components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                let mainTerm = tagPhrases.first ?? "blowjob"
                let additionalTerms = Array(tagPhrases.dropFirst())
                
                print("🔍 Parsing marker search: '\(searchQuery)'")
                print("🔍 Main term: '\(mainTerm)', Additional terms: \(additionalTerms)")
                
                if additionalTerms.isEmpty {
                    // Simple single-tag search with tag locking
                    print("🔍 Single tag search for: '\(mainTerm)'")
                    
                    // Set validation state
                    await MainActor.run {
                        isValidatingTag = true
                    }
                    
                    // First validate if this is a real marker tag
                    let (tagExists, tagCount) = try await appModel.api.validateMarkerTag(tagName: mainTerm)
                    
                    if tagExists {
                        // Use exact tag search for display (keep 20 for performance)
                        let markers = try await appModel.api.searchMarkers(query: "#\(mainTerm)", page: 1, perPage: 20, randomize: true)
                        let totalCount = tagCount // Use the count from validation
                        print("📊 Found \(markers.count) markers using EXACT tag search for '\(mainTerm)' (total estimated: \(totalCount))")
                        
                        await MainActor.run {
                            isValidatingTag = false
                            
                            // Lock the validated tag
                            lockTagIfValid(mainTerm, count: totalCount)
                            
                            searchedMarkers = markers
                            totalMarkerCount = totalCount
                            appModel.searchQuery = query.isEmpty ? "" : query
                            updateMarkerResults(markers, totalCount)
                        }
                    } else {
                        print("⚠️ Tag '\(mainTerm)' does not exist in marker system - searching for similar tags")
                        
                        // Search for similar tags
                        await searchForSimilarTags(searchTerm: mainTerm, originalQuery: query)
                    }
                } else {
                    // Multi-tag combination search - COMBINE separate marker collections
                    print("🔍 Multi-tag search: '\(mainTerm)' + \(additionalTerms.joined(separator: ", "))")
                    print("🔍 This will combine ALL markers from each tag search (not intersection)")
                    
                    // Set validation state for multi-tag search
                    await MainActor.run {
                        isValidatingTag = true
                    }
                    
                    var allMarkers = Set<SceneMarker>()
                    var combinedTotalCount = 0
                    
                    // Search for main term - display subset only (keep 20 for performance)
                    let mainMarkers = try await appModel.api.searchMarkers(query: "#\(mainTerm)", page: 1, perPage: 20, randomize: true)
                    print("📊 Main term '\(mainTerm)' (EXACT): \(mainMarkers.count) markers for display")
                    allMarkers.formUnion(mainMarkers)
                    
                    // Get actual counts for each tag for total estimation
                    let (_, mainTagCount) = try await appModel.api.validateMarkerTag(tagName: mainTerm)
                    combinedTotalCount += mainTagCount
                    
                    // Search for each additional term - display subset only (keep 20 for performance)
                    for additionalTerm in additionalTerms {
                        let additionalMarkers = try await appModel.api.searchMarkers(query: "#\(additionalTerm)", page: 1, perPage: 20, randomize: true)
                        let (_, additionalTagCount) = try await appModel.api.validateMarkerTag(tagName: additionalTerm)
                        print("📊 Additional term '\(additionalTerm)' (EXACT): \(additionalMarkers.count) markers for display")
                        allMarkers.formUnion(additionalMarkers)
                        combinedTotalCount += additionalTagCount
                        print("📊 Combined pool now has \(allMarkers.count) unique markers for display")
                    }
                    
                    let finalMarkers = Array(allMarkers).shuffled() // Randomize the combined results
                    print("📊 Final combined results: \(finalMarkers.count) unique markers from \(1 + additionalTerms.count) tag searches")
                    print("📊 Total estimated server count: \(combinedTotalCount) (with duplicates)")
                    
                    await MainActor.run {
                        isValidatingTag = false
                        
                        searchedMarkers = finalMarkers
                        totalMarkerCount = finalMarkers.count // Use unique count for display
                        appModel.searchQuery = query.isEmpty ? "" : query
                        updateMarkerResults(finalMarkers, finalMarkers.count)
                    }
                }
            }
        } catch {
            await MainActor.run {
                // Clear validation state on error
                isValidatingTag = false
                
                appModel.api.error = error
                appModel.api.scenes = []
                appModel.api.totalSceneCount = 0
            }
        }
    }
    
    private func updateMarkerResults(_ markers: [SceneMarker], _ count: Int) {
        appModel.api.scenes = []  // Clear scenes since we're showing markers
        appModel.api.totalSceneCount = 0
        currentFilter = "search"  // Ensure we stay in search mode
        searchScope = .markers    // Ensure scope is set to markers
        
        // Enable pagination if we got a full page of results
        hasMorePages = markers.count >= 50
        
        viewRefreshId = UUID()   // Force view refresh
        print("✅ Stored \(markers.count) marker results (total: \(count)) - filter: \(currentFilter), scope: \(searchScope), hasMorePages: \(hasMorePages)")
        // Explicitly trigger UI update
        appModel.objectWillChange.send()
    }
    
    // MARK: - Locked Tags Functions
    
    private func clearLockedTags() {
        lockedTags.removeAll()
        lastValidatedTag = nil
        print("🔒 Cleared all locked tags")
    }
    
    private func removeLockedTag(at index: Int) {
        guard index < lockedTags.count else { return }
        let removedTag = lockedTags.remove(at: index)
        print("🔒 Removed locked tag: \(removedTag.name)")
    }
    
    private func combineAllLockedTags() {
        guard !lockedTags.isEmpty else { return }
        
        let combinedQuery = lockedTags.map { $0.name }.joined(separator: " +")
        print("🔒 Combining all locked tags: \(combinedQuery)")
        
        // Add randomization by clearing existing results and forcing a fresh search
        searchedMarkers = []
        totalMarkerCount = 0
        
        // Set the search text and trigger search
        searchText = combinedQuery
        Task {
            await performSearch(query: combinedQuery, scope: .markers)
        }
    }
    
    private func lockTagIfValid(_ tagName: String, count: Int) {
        // Check if tag already exists
        if !lockedTags.contains(where: { $0.name.lowercased() == tagName.lowercased() }) {
            lockedTags.append((name: tagName, count: count))
            lastValidatedTag = tagName
            print("🔒 Locked tag: \(tagName) with \(count) markers")
        } else {
            print("🔒 Tag \(tagName) already locked")
        }
    }
    
    private func searchForSimilarTags(searchTerm: String, originalQuery: String) async {
        do {
            // Search for tags containing the search term
            let allTags = try await appModel.api.searchTags(query: searchTerm)
            let similarTags = allTags.filter { tag in
                tag.name.lowercased().contains(searchTerm.lowercased())
            }
            
            await MainActor.run {
                isValidatingTag = false
                
                if similarTags.count > 1 {
                    // Multiple similar tags found - show suggestions
                    print("🏷️ Found \(similarTags.count) similar tags: \(similarTags.map { $0.name })")
                    suggestedTags = similarTags
                    originalSearchQuery = originalQuery
                    showingTagSuggestions = true
                } else if similarTags.count == 1 {
                    // Single similar tag found - use it automatically
                    let suggestedTag = similarTags[0]
                    print("🏷️ Auto-selecting similar tag: \(suggestedTag.name)")
                    searchText = suggestedTag.name
                    Task {
                        await performSearch(query: suggestedTag.name, scope: .markers)
                    }
                } else {
                    // No similar tags found
                    print("⚠️ No similar tags found for '\(searchTerm)'")
                    searchedMarkers = []
                    totalMarkerCount = 0
                    appModel.searchQuery = originalQuery
                    updateMarkerResults([], 0)
                }
            }
        } catch {
            await MainActor.run {
                isValidatingTag = false
                searchedMarkers = []
                totalMarkerCount = 0
                appModel.searchQuery = originalQuery
                updateMarkerResults([], 0)
            }
        }
    }
    
    @ViewBuilder
    private var mainContentView: some View {
        Group {
            if appModel.api.isLoading && currentPage == 1 {
                loadingView
            } else if let error = appModel.api.error, currentFilter == "search" {
                errorView(error: error)
            } else {
                scenesContent
                    .id(viewRefreshId)
            }
        }
    }
    
    private var loadingView: some View {
        VStack {
            ProgressView("Loading media...")
                .scaleEffect(1.2)

            Text("Loading your media library...")
                .foregroundColor(.secondary)
                .padding(.top)
        }
    }
    
    private func errorView(error: Error) -> some View {
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
    }
} 