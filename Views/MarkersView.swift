import SwiftUI
import Foundation

// Preference key to get width without affecting layout
private struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct MarkersView: View {
    // Dependencies
    @EnvironmentObject private var appModel: AppModel

    // State for loading
    @State private var currentPage = 1
    @State private var isLoadingMore = false
    @State private var hasMorePages = true
    @State private var allMarkers: [SceneMarker] = []
    @State private var isLoading = false

    // State for filtering and UI
    @State private var selectedTagId: String? = nil
    @State private var showingCreateMarker = false
    @State private var availableWidth: CGFloat = 1200 // Default width estimate
    @State private var visibleMarkers: Set<String> = []
    @State private var displayedMarkers: [SceneMarker] = []

    // Always return 3 columns for markers view to match scenes grid
    private func getColumnCount(for width: CGFloat) -> Int {
        return 3 // Fixed 3 columns for consistency with scenes view
    }

    // Tag filter helpers
    private func shouldIncludeMarker(_ marker: SceneMarker, tagId: String) -> Bool {
        return marker.primary_tag.id == tagId ||
        marker.tags.contains(where: { $0.id == tagId })
    }
    
    // Debug function to show count of markers
    private func logMarkerCounts(source: String) {
        print("🏷️ \(source) - Total markers: \(allMarkers.count), Displayed: \(displayedMarkers.count)")
        if let tagId = selectedTagId {
            let tagName = displayedMarkers.first?.primary_tag.name ?? "Unknown"
            print("🏷️ Filtered by tag: \(tagName) (ID: \(tagId))")
        }
    }

    private func updateDisplayedMarkers() {
        if let tagId = selectedTagId {
            // Filter markers by selected tag
            displayedMarkers = allMarkers.filter { marker in
                shouldIncludeMarker(marker, tagId: tagId)
            }
        } else {
            // Show all markers
            displayedMarkers = allMarkers
        }
        
        // Log marker counts for debugging
        logMarkerCounts(source: "updateDisplayedMarkers")
    }

    private func clearFilter() {
        selectedTagId = nil
        Task {
            currentPage = 1
            await initialLoad()
        }
    }

    private func handleTagSelection(_ tag: SceneMarker.Tag) {
        print("🔍 Setting tag filter: \(tag.name) (ID: \(tag.id))")
        selectedTagId = tag.id
        currentPage = 1
        Task {
            await loadMarkersForTag(tag.id)
        }
    }

    private var filterHeader: some View {
        Group {
            if let selectedTagId = selectedTagId,
               let marker = displayedMarkers.first(where: {
                   $0.primary_tag.id == selectedTagId ||
                   $0.tags.contains(where: { $0.id == selectedTagId })
               }),
               let tagName = (marker.primary_tag.id == selectedTagId ?
                            marker.primary_tag.name :
                            marker.tags.first(where: { $0.id == selectedTagId })?.name) {
                HStack {
                    Text("Filtered by tag: ")
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)

                    Text(tagName)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(12)
                        .fontWeight(.semibold)

                    Spacer()

                    Button(action: clearFilter) {
                        HStack(spacing: 4) {
                            Text("Clear Filter")
                                .font(.subheadline)
                            Image(systemName: "xmark.circle.fill")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.top)
            }
        }
    }

    private var markerGrid: some View {
        // Fixed 3-column grid to match scenes view
        let columns = [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ]

        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(displayedMarkers) { marker in
                // Using our improved MarkerRow component
                MarkerRow(
                    marker: marker,
                    serverAddress: appModel.serverAddress,
                    onTitleTap: { marker in
                        print("🎬 MarkersView: Handling marker title tap via onTitleTap")
                        // Directly navigate from parent component
                        appModel.navigateToMarker(marker)
                    },
                    onTagTap: { tagName in
                        // Find tag by name and apply filter
                        if tagName == marker.primary_tag.name {
                            handleTagSelection(marker.primary_tag)
                        } else if let tag = marker.tags.first(where: { $0.name == tagName }) {
                            handleTagSelection(tag)
                        }
                    },
                    onPerformerTap: { performer in
                        // Navigate to performer when tapped
                        print("👤 MarkersView: Navigating to performer: \(performer.name)")
                        appModel.navigateToPerformer(performer)
                    },
                    onShuffleTap: { tagId in
                        // Handle shuffle from individual marker row
                        print("🎲 Individual marker shuffle for tag ID: \(tagId)")
                        let tagName = marker.primary_tag.name
                        appModel.startMarkerShuffle(forTag: tagId, tagName: tagName, displayedMarkers: displayedMarkers)
                    }
                )
                .contextMenu {
                    Button(action: {
                        appModel.navigateToMarker(marker)
                    }) {
                        Label("Play Marker", systemImage: "play.fill")
                    }
                    
                    Button(action: {
                        // Copy marker URL to clipboard
                        UIPasteboard.general.string = "\(appModel.serverAddress)/markers/\(marker.id)"
                    }) {
                        Label("Copy Link", systemImage: "link")
                    }
                    
                    if let scene = appModel.api.scenes.first(where: { $0.id == marker.scene.id }) {
                        Button(action: {
                            appModel.currentScene = scene
                            appModel.navigationPath.append(scene)
                        }) {
                            Label("Go to Scene", systemImage: "film")
                        }
                    }
                }
                // Add animations to match SceneRow
                .slideIn(from: .bottom, delay: Double(displayedMarkers.firstIndex(where: { $0.id == marker.id }) ?? 0) * 0.05, duration: 0.4)
                .onAppear {
                    visibleMarkers.insert(marker.id)

                    // Check if this is near the end of the list
                    checkLoadMore(marker)
                }
                .onDisappear {
                    visibleMarkers.remove(marker.id)
                }
            }

            if isLoadingMore {
                ProgressView()
                    .gridCellColumns(3) // Fixed to 3 columns
                    .frame(height: 50)
                    .padding()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private var universalShuffleButton: some View {
        Group {
            // Only show shuffle button when there are filtered results
            if (!appModel.searchQuery.isEmpty && !displayedMarkers.isEmpty) || 
               (selectedTagId != nil && !displayedMarkers.isEmpty) {
                
                VStack(spacing: 12) {
                    HStack {
                        // Info about what we're shuffling
                        VStack(alignment: .leading, spacing: 4) {
                            if !appModel.searchQuery.isEmpty {
                                Text("Shuffle search results for '\(appModel.searchQuery)'")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            } else if let selectedTagId = selectedTagId,
                                      let marker = displayedMarkers.first(where: {
                                          $0.primary_tag.id == selectedTagId ||
                                          $0.tags.contains(where: { $0.id == selectedTagId })
                                      }),
                                      let tagName = (marker.primary_tag.id == selectedTagId ?
                                                   marker.primary_tag.name :
                                                   marker.tags.first(where: { $0.id == selectedTagId })?.name) {
                                Text("Shuffle all '\(tagName)' markers")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                            
                            Text("Found \(displayedMarkers.count) markers")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Shuffle button
                        Button(action: {
                            print("🎲 UNIVERSAL SHUFFLE BUTTON TAPPED")
                            // Start marker shuffle based on current filter
                            if !appModel.searchQuery.isEmpty {
                                print("🎲 Starting shuffle for search: \(appModel.searchQuery) with \(displayedMarkers.count) markers")
                                appModel.startMarkerShuffle(forSearchQuery: appModel.searchQuery, displayedMarkers: displayedMarkers)
                            } else if let tagId = selectedTagId,
                                      let marker = displayedMarkers.first(where: {
                                          $0.primary_tag.id == tagId ||
                                          $0.tags.contains(where: { $0.id == tagId })
                                      }),
                                      let tagName = (marker.primary_tag.id == tagId ?
                                                   marker.primary_tag.name :
                                                   marker.tags.first(where: { $0.id == tagId })?.name) {
                                print("🎲 Starting shuffle for tag: \(tagName) with \(displayedMarkers.count) markers")
                                appModel.startMarkerShuffle(forTag: tagId, tagName: tagName, displayedMarkers: displayedMarkers)
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "shuffle")
                                    .font(.title2)
                                Text("Shuffle Play")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
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
                        .scaleEffect(appModel.isMarkerShuffleMode ? 0.95 : 1.0)
                        .animation(.spring(response: 0.3), value: appModel.isMarkerShuffleMode)
                    }
                    
                    // Show shuffle status if active
                    if appModel.isMarkerShuffleMode {
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "play.circle.fill")
                                    .foregroundColor(.green)
                                Text("Shuffle Active")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                            }
                            
                            Text("•")
                                .foregroundColor(.secondary)
                            
                            Text("\(appModel.markerShuffleQueue.count) in queue")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button("Stop Shuffle") {
                                appModel.stopMarkerShuffle()
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private func checkLoadMore(_ marker: SceneMarker) {
        // Check if this is one of the last few markers displayed
        let visibleIndex = displayedMarkers.firstIndex(where: { $0.id == marker.id }) ?? 0
        let threshold = max(0, displayedMarkers.count - 6) // Load more when we're 6 items from the end
        
        // More aggressive debugging for pagination trigger
        if visibleIndex >= threshold - 2 {
            print("📊 Scroll position: marker \(visibleIndex) of \(displayedMarkers.count) (threshold: \(threshold))")
        }

        if visibleIndex >= threshold && !isLoadingMore && hasMorePages {
            print("📊 LOADING MORE MARKERS at index \(visibleIndex) of \(displayedMarkers.count)")
            print("📊 Search state: query='\(appModel.searchQuery)', hasMorePages=\(hasMorePages)")
            
            Task {
                if !appModel.searchQuery.isEmpty {
                    print("📊 Calling loadMoreSearchResults() for query: '\(appModel.searchQuery)'")
                    await loadMoreSearchResults()
                } else if let tagId = selectedTagId {
                    print("📊 Calling loadMoreMarkersForTag() for tag: \(tagId)")
                    await loadMoreMarkersForTag(tagId)
                } else {
                    print("📊 Calling loadMoreMarkers() for all markers")
                    await loadMoreMarkers()
                }
            }
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Filter header if applicable
                filterHeader
                
                // Universal shuffle button for filtered results
                universalShuffleButton

                if isLoading && allMarkers.isEmpty {
                    // Initial loading state
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.5)

                        Text("Loading markers... (up to 500)")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else if displayedMarkers.isEmpty {
                    // Empty state with refresh button
                    VStack(spacing: 20) {
                        Image(systemName: "bookmark.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)

                        Text(appModel.searchQuery.isEmpty ? "No markers found" : "No results found")
                            .font(.title2)
                            .foregroundColor(.secondary)

                        if !appModel.searchQuery.isEmpty {
                            Text("Try a different search")
                                .foregroundColor(.secondary)
                        } else {
                            Button(action: {
                                Task {
                                    await initialLoad()
                                }
                            }) {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else {
                    // Markers grid with scrolling
                    ScrollView(.vertical, showsIndicators: true) {
                        // Gets the width without affecting layout
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: WidthPreferenceKey.self, value: geo.size.width)
                        }
                        .frame(height: 1) // Minimal height so it doesn't affect layout

                        markerGrid
                            .padding(.bottom, 40) // Add extra padding at bottom for safe scrolling
                    }
                    .onPreferenceChange(WidthPreferenceKey.self) { width in
                        if abs(availableWidth - width) > 50 {
                            // Only update on significant changes
                            availableWidth = width
                        }
                    }
                    .contentShape(Rectangle()) // Make sure the whole area is tappable
                    .onTapGesture {
                        // Stop all playing videos when tapping the background
                        GlobalVideoManager.shared.stopAllPreviews()
                    }
                }
            }

            // Overlay loading indicator for subsequent loads
            if isLoading && !allMarkers.isEmpty {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                    .frame(width: 60, height: 60)
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
            }
        }
        .navigationTitle("Markers")
        .searchable(text: $appModel.searchQuery, prompt: "Search markers...")
        .onChange(of: appModel.searchQuery) { _, newValue in
            Task {
                if !newValue.isEmpty {
                    print("🔍 Search text changed to: '\(newValue)'")
                    appModel.isSearching = true
                    await searchMarkers(query: newValue)
                    updateDisplayedMarkers()
                } else {
                    print("🔍 Search cleared, restoring original markers")
                    appModel.isSearching = false
                    await initialLoad()
                    updateDisplayedMarkers()
                }
            }
        }
        .sheet(isPresented: $showingCreateMarker) {
            CreateMarkerView(initialSeconds: "", sceneID: "")
                .environmentObject(appModel)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingCreateMarker = true
                }) {
                    Label("Create Marker", systemImage: "plus")
                }
            }
        }
        .task {
            print("🔍 Initial load of markers - View appeared")
            if allMarkers.isEmpty {
                print("🔍 Initial load of markers - No existing markers, fetching")
                await initialLoad()
                updateDisplayedMarkers() // Update after loading
            }
        }
        .refreshable {
            await initialLoad()
            updateDisplayedMarkers() // Update after refreshing
        }
    }

    private func searchMarkers(query: String) async {
        print("🔍 Searching markers with query: '\(query)'")
        isLoading = true
        
        // Reset pagination state
        currentPage = 1
        hasMorePages = true

        // Determine if this is a tag search or general text search
        // Use tag search for queries that look like tag names (no spaces, short words)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLikelyTagSearch = !trimmedQuery.contains(" ") && trimmedQuery.count <= 20 && trimmedQuery.count > 2
        
        if isLikelyTagSearch {
            print("🏷️ Using tag-based search for query: '\(trimmedQuery)'")
            await appModel.api.searchMarkersByTagName(tagName: trimmedQuery)
        } else {
            print("🔍 Using general text search for query: '\(trimmedQuery)'")
            await appModel.api.updateMarkersFromSearch(query: trimmedQuery, page: 1, appendResults: false)
        }
        
        // Get search results and log count
        allMarkers = appModel.api.markers
        print("🔍 Search returned \(allMarkers.count) markers for query: '\(query)'")
        
        // Perform additional logging to understand returned data
        if let first = allMarkers.first {
            print("🔍 First result: \(first.title) (ID: \(first.id), Tag: \(first.primary_tag.name))")
        }
        
        // Set hasMorePages based on search type and results
        if isLikelyTagSearch {
            // Tag searches load all results at once, so no more pages
            hasMorePages = false
            print("🏷️ Tag search complete: found \(allMarkers.count) markers")
        } else {
            // Text searches are paginated
            hasMorePages = allMarkers.count >= 500
            print("🔍 Has more pages: \(hasMorePages ? "Yes" : "No"), found \(allMarkers.count) markers (of max 500)")
        }
        
        isLoading = false
    }

    private func loadMoreSearchResults() async {
        guard !isLoadingMore && hasMorePages else { 
            print("⚠️ Skipping loadMoreSearchResults: isLoadingMore=\(isLoadingMore), hasMorePages=\(hasMorePages)")
            return
        }

        // Check if this is a tag search - if so, skip pagination since tag searches load all results
        let trimmedQuery = appModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLikelyTagSearch = !trimmedQuery.contains(" ") && trimmedQuery.count <= 20 && trimmedQuery.count > 2
        
        if isLikelyTagSearch {
            print("🏷️ Skipping pagination for tag search - all results already loaded")
            hasMorePages = false
            isLoadingMore = false
            return
        }

        isLoadingMore = true
        currentPage += 1
        
        print("🔄 Loading more search results for query '\(appModel.searchQuery)' (page \(currentPage))")

        // Preserve current marker count for comparison
        let previousCount = allMarkers.count
        let previousIds = Set(allMarkers.map { $0.id })
        
        // Use pagination parameter for fetching next page
        await appModel.api.updateMarkersFromSearch(query: appModel.searchQuery, page: currentPage, appendResults: true)

        // Update with newly loaded markers
        let newMarkers = appModel.api.markers.filter { !previousIds.contains($0.id) }
        print("🔄 New unique markers found: \(newMarkers.count)")
        
        // Add new markers to our local collection
        if !newMarkers.isEmpty {
            allMarkers.append(contentsOf: newMarkers)
        }
        
        // Check if more markers were actually added
        let foundNewMarkers = !newMarkers.isEmpty
        hasMorePages = foundNewMarkers && newMarkers.count >= 50 // If we got at least 50 new markers, there might be more (with 500 batch size)
        
        if foundNewMarkers {
            print("✅ Successfully loaded more search results - Page \(currentPage), Added \(newMarkers.count) new markers (total now: \(allMarkers.count))")
        } else {
            print("⚠️ No more search results available for query '\(appModel.searchQuery)'")
            hasMorePages = false
        }
        
        isLoadingMore = false
        updateDisplayedMarkers() // Update displayed markers after loading more
    }

    private func initialLoad() async {
        print("📊 MarkersView initialLoad started")
        isLoading = true
        currentPage = 1
        hasMorePages = true
        allMarkers = []
        visibleMarkers.removeAll()
        selectedTagId = nil

        // Debug: Print server connection information
        print("📊 MarkersView server address: \(appModel.serverAddress)")
        print("📊 MarkersView auth status: \(appModel.api.isAuthenticated ? "Authenticated" : "Not authenticated")")
        print("📊 MarkersView connection status: \(appModel.api.connectionStatusMessage)")
        print("📊 MarkersView API key: \(appModel.api.apiKeyForURLs.prefix(5))...")

        // Force reconnection to ensure auth is current
        if !appModel.api.isAuthenticated {
            print("📊 Forcing authentication before fetching markers")
            do {
                try await appModel.api.checkServerConnection()
                print("📊 Connection status after check: \(appModel.api.connectionStatusMessage)")
            } catch {
                print("❌ Failed to authenticate: \(error)")
            }
        }

        // Try to fetch markers with more detailed logging
        print("📊 MarkersView attempting to fetch markers...")
        await appModel.api.fetchMarkers(page: currentPage, appendResults: false)
        print("📊 MarkersView markers fetch completed, received: \(appModel.api.markers.count)")

        // Print first marker details if available for debugging
        if let firstMarker = appModel.api.markers.first {
            print("📊 First marker details:")
            print("  ID: \(firstMarker.id)")
            print("  Title: \(firstMarker.title)")
            print("  Scene ID: \(firstMarker.scene.id)")
            print("  Primary tag: \(firstMarker.primary_tag.name)")

            if let performers = firstMarker.scene.performers, !performers.isEmpty {
                print("  Has performers: Yes (\(performers.count))")
                print("  First performer: \(performers[0].name)")
            } else {
                print("  Has performers: No")
            }

            print("  Screenshot URL: \(firstMarker.screenshot)")
            print("  Stream URL: \(firstMarker.stream)")
        } else {
            print("❌ No markers returned from API")

            // Additional debug if markers are empty
            print("📊 Checking API error state: \(appModel.api.error?.localizedDescription ?? "No error")")
            print("📊 Is API loading: \(appModel.api.isLoading ? "Yes" : "No")")
        }

        await MainActor.run {
            // Update on the main thread to avoid UI issues
            allMarkers = appModel.api.markers
            updateDisplayedMarkers() // Update displayed markers after loading
            isLoading = false
            print("📊 MarkersView allMarkers updated with \(allMarkers.count) items")
        }

        // Preload the next page in the background for smoother scrolling
        if hasMorePages {
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // Wait 0.5 seconds before pre-fetching
                await preloadNextPage()
            }
        }
    }

    private func preloadNextPage() async {
        guard !isLoadingMore && hasMorePages else { return }

        print("Preloading next page of markers")
        let tempLoadingFlag = isLoadingMore
        isLoadingMore = true

        let nextPage = currentPage + 1
        let previousCount = allMarkers.count

        if let tagId = selectedTagId {
            await appModel.api.fetchMarkersByTag(tagId: tagId, page: nextPage, appendResults: true)
        } else {
            await appModel.api.fetchMarkers(page: nextPage, appendResults: true)
        }

        // Add new markers without duplicates
        let newMarkers = appModel.api.markers.filter { marker in
            !allMarkers.contains(where: { $0.id == marker.id })
        }

        if !newMarkers.isEmpty {
            allMarkers.append(contentsOf: newMarkers)
            updateDisplayedMarkers()
            print("Preloaded \(newMarkers.count) markers for smooth scrolling")

            // Only update current page if we successfully preloaded data
            currentPage = nextPage
            hasMorePages = true
        } else {
            hasMorePages = false
        }

        isLoadingMore = tempLoadingFlag
    }

    private func loadMoreMarkers() async {
        guard !isLoadingMore else { return }

        isLoadingMore = true
        currentPage += 1

        print("🔥 Loading more markers (page \(currentPage))")
        let previousCount = allMarkers.count
        await appModel.api.fetchMarkers(page: currentPage, appendResults: true)

        // Add new markers without duplicates
        let newMarkers = appModel.api.markers.filter { marker in
            !allMarkers.contains(where: { $0.id == marker.id })
        }
        allMarkers.append(contentsOf: newMarkers)

        hasMorePages = !newMarkers.isEmpty
        isLoadingMore = false

        updateDisplayedMarkers() // Update displayed markers after loading more
    }

    private func loadMarkersForTag(_ tagId: String) async {
        isLoading = true
        currentPage = 1
        hasMorePages = true
        allMarkers = []
        visibleMarkers.removeAll()

        print("🏷️ Loading markers for tag ID: \(tagId)")
        await appModel.api.fetchMarkersByTag(tagId: tagId, page: currentPage, appendResults: false)

        await MainActor.run {
            allMarkers = appModel.api.markers
            updateDisplayedMarkers()

            // Sort markers by newest first (assuming IDs are sequential)
            displayedMarkers.sort { marker1, marker2 in
                // For equal titles, sort by id (most recent first)
                return marker1.id > marker2.id
            }

            print("🏷️ Displaying \(displayedMarkers.count) markers with tag ID: \(tagId)")
            isLoading = false
        }
    }

    /// Format duration into mm:ss or hh:mm:ss format
    private func formatDuration(_ seconds: Float) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    private func loadMoreMarkersForTag(_ tagId: String) async {
        guard !isLoadingMore else { return }

        isLoadingMore = true
        currentPage += 1

        print("🏷️ Loading more markers for tag ID: \(tagId) (page \(currentPage))")
        await appModel.api.fetchMarkersByTag(tagId: tagId, page: currentPage, appendResults: true)

        // Filter results to avoid duplicates
        let newMarkers = appModel.api.markers.filter { marker in
            !allMarkers.contains(where: { $0.id == marker.id })
        }

        print("🏷️ Retrieved \(newMarkers.count) new markers for tag ID: \(tagId)")

        await MainActor.run {
            if !newMarkers.isEmpty {
                // Add new markers
                allMarkers.append(contentsOf: newMarkers)
                updateDisplayedMarkers()

                // Re-sort with newest first
                displayedMarkers.sort { marker1, marker2 in
                    return marker1.id > marker2.id
                }

                print("🏷️ Added \(newMarkers.count) new markers (total: \(displayedMarkers.count))")
            }

            // If we got any new results, there might be more pages
            hasMorePages = !newMarkers.isEmpty
            isLoadingMore = false
        }
    }
} 