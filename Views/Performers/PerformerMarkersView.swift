import SwiftUI
import Combine
import os.log

/// A view that displays markers for a specific performer
struct PerformerMarkersView: View {
    // MARK: - Environment
    @EnvironmentObject private var appModel: AppModel
    
    // MARK: - State
    @State private var currentPage = 1
    @State private var isLoadingMore = false
    @State private var hasMorePages = true
    @State private var selectedPerformer: StashScene.Performer?
    @State private var isInitialLoad = true
    @State private var selectedTag: StashScene.Tag?
    @State private var searchText = ""
    @State private var showFilterMenu = false
    @State private var sortOption: MarkerSortOption = .timestamp
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var totalCount = 0
    @State private var performersWithMarkerCount: [PerformerWithMarkerCount] = []
    @State private var isSortingByMarkers = true
    // We no longer track visibility externally, handled by MarkerRow itself
    
    // MARK: - Constants
    private static let logger = Logger(subsystem: "com.ck.test.stash", category: "PerformerMarkersView")
    
    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)
    ]
    
    private let performerColumns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]
    
    // MARK: - Types
    struct PerformerWithMarkerCount: Identifiable, Hashable {
        let id: String
        let performer: StashScene.Performer
        let markerCount: Int

        static func == (lhs: PerformerWithMarkerCount, rhs: PerformerWithMarkerCount) -> Bool {
            return lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
    
    // MARK: - Computed Properties
    /// Returns filtered markers for the selected performer
    private func filteredMarkersForSelectedPerformer() -> [SceneMarker] {
        // No need to filter again as the API already returns only markers for the selected performer
        var markers = appModel.api.markers
        
        // Apply search filter if text is provided
        if !searchText.isEmpty {
            Self.logger.debug("Filtering by search text: \(searchText)")
            markers = markers.filter { marker in
                marker.title.localizedCaseInsensitiveContains(searchText) ||
                marker.primary_tag.name.localizedCaseInsensitiveContains(searchText) ||
                marker.tags.contains { $0.name.localizedCaseInsensitiveContains(searchText) } ||
                marker.scene.title?.localizedCaseInsensitiveContains(searchText) ?? false
            }
            Self.logger.debug("After text search: \(markers.count) markers remain")
        }
        
        // Apply tag filter if a tag is selected
        if let selectedTag = selectedTag {
            Self.logger.debug("Filtering by tag: \(selectedTag.name) (ID: \(selectedTag.id))")
            markers = markers.filter { marker in
                marker.primary_tag.id == selectedTag.id ||
                marker.tags.contains { $0.id == selectedTag.id }
            }
            Self.logger.debug("After tag filter: \(markers.count) markers remain")
        }
        
        return markers
    }
    
    // MARK: - View Body
    var body: some View {
        ZStack {
            ScrollView {
                if isInitialLoad {
                    loadingView
                } else if selectedPerformer == nil {
                    performerSelectionView
                } else if appModel.api.isLoading {
                    markerLoadingView
                } else if appModel.api.markers.isEmpty {
                    emptyMarkersView
                } else {
                    // Get filtered markers once for better performance
                    let markers = filteredMarkersForSelectedPerformer()
                    
                    // Header section
                    VStack(spacing: 16) {
                        // Header with performer info, back button
                        HStack {
                            Button(action: {
                                // Stop all preview players before navigating back
                                GlobalVideoManager.shared.stopAllPreviews()
                                
                                selectedPerformer = nil
                                appModel.api.markers = []
                                searchText = ""
                                selectedTag = nil
                            }) {
                                HStack {
                                    Image(systemName: "chevron.left")
                                    Text("Back")
                                }
                            }
                            Spacer()
                            
                            if let performer = selectedPerformer {
                                Text("\(performer.name)'s Markers (\(markers.count))")
                                    .font(.headline)
                            }
                            
                            Spacer()
                            
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Search bar
                        if !appModel.api.markers.isEmpty {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                
                                TextField("Search markers", text: $searchText)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                                if !searchText.isEmpty {
                                    Button(action: { searchText = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        }
                        
                        // Tag filter section
                        if let tag = selectedTag {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    HStack {
                                        Text(tag.name)
                                            .font(.caption)
                                            .padding(.leading, 8)
                                            .padding(.trailing, 4)
                                            .padding(.vertical, 4)
                                        
                                        Button(action: { selectedTag = nil }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                        }
                                        .padding(.trailing, 8)
                                    }
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(12)
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // Marker grid
                        LazyVGrid(columns: columns, spacing: 16) {
                            // Show each marker row
                            ForEach(markers) { marker in
                                MarkerRow(
                                    marker: marker,
                                    serverAddress: appModel.serverAddress,
                                    onTitleTap: { marker in
                                        // Stop all preview players before starting full-screen video
                                        print("📱 PerformerMarkersView: Stopping all previews before navigating to full-screen")
                                        GlobalVideoManager.shared.stopAllPreviews()
                                        
                                        // Set HLS preference first
                                        setHLSPreference(for: marker)
                                        // Use more reliable direct navigation method
                                        DispatchQueue.main.async {
                                            print("📱 PerformerMarkersView: Title tap detected for marker: \(marker.title)")
                                            appModel.navigateToMarker(marker)
                                        }
                                    },
                                    onTagTap: { tagName in
                                        if let tag = appModel.api.markers.flatMap({ [$0.primary_tag] + $0.tags }).first(where: { $0.name == tagName }) {
                                            withAnimation {
                                                selectedTag = StashScene.Tag(id: tag.id, name: tag.name)
                                            }
                                            Self.logger.debug("Set tag filter: \(tag.name)")
                                        } else {
                                            showErrorMessage("Could not find tag: \(tagName)")
                                        }
                                    },
                                    onPerformerTap: { performer in
                                        // Navigate to a performer when tapped in a marker
                                        print("📱 PerformerMarkersView: Performer tap detected for: \(performer.name)")
                                        
                                        // Set this performer as selected
                                        selectedPerformer = performer
                                        
                                        // Then load their markers
                                        Task {
                                            await loadPerformerMarkers(performer: performer)
                                        }
                                    }
                                )
                                .frame(maxWidth: .infinity)
                                .onTapGesture(count: 2) {
                                    // Stop all preview players before double-tap navigation
                                    GlobalVideoManager.shared.stopAllPreviews()
                                    
                                    // Double tap should also set preference and navigate
                                    setHLSPreference(for: marker)
                                    // Use async for more reliable navigation
                                    DispatchQueue.main.async {
                                        appModel.navigateToMarker(marker)
                                    }
                                }
                                .onAppear {
                                    // Load more markers if needed
                                    if marker.id == markers.last?.id && !isLoadingMore && hasMorePages {
                                        Task {
                                            await loadMoreMarkers()
                                        }
                                    }
                                }
                            }
                            
                            // Loading indicator
                            if isLoadingMore {
                                ProgressView()
                                    .padding()
                            }
                        }
                        .padding()
                    }
                }
            }
            .refreshable {
                await refreshContent()
            }
            .navigationTitle(selectedPerformer?.name ?? "Performer Markers")
            
            // Error alert
            if showError {
                VStack {
                    Spacer()
                    
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation {
                                showError = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 5)
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(1)
            }
        }
        .task {
            // Show loading indicator at initial load
            isInitialLoad = true
            
            // Load initial performers if needed
            if appModel.api.performers.isEmpty {
                await loadPerformers()
            }
            
            // Load performers with marker counts
            await loadPerformerCounts()
            
            isInitialLoad = false
        }
        .toolbar {
            if selectedPerformer != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    filterMenu
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Stop all preview players before navigating back
                        GlobalVideoManager.shared.stopAllPreviews()
                        
                        // Clear the selection and return to performer selection
                        withAnimation {
                            selectedPerformer = nil
                            appModel.api.markers = []
                            searchText = ""
                            selectedTag = nil
                        }
                    }) {
                        Image(systemName: "arrow.left")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .sheet(item: $selectedTag) { tag in
            NavigationStack {
                TaggedScenesView(tag: tag)
                    .environmentObject(appModel)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Close") {
                                selectedTag = nil
                            }
                        }
                    }
            }
        }
        .onDisappear {
            // Cleanup all video players when the view disappears
            print("📱 PerformerMarkersView disappeared - cleaning up all video players")
            GlobalVideoManager.shared.stopAllPreviews()
        }
    }
    
    // MARK: - Subviews
    
    /// Loading view for initial content load
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.5)
                .padding()
            
            Text("Loading performers and marker counts...")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 100)
        .frame(maxWidth: .infinity)
    }
    
    /// View for selecting a performer
    private var performerSelectionView: some View {
        VStack {
            // Sort toggle and count indicator
            HStack {
                Toggle("Sort by marker count", isOn: $isSortingByMarkers)
                
                Spacer()
                
                Text("\(performersWithMarkerCount.count) performers found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            if performersWithMarkerCount.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                        .padding()
                    
                    Text("No performers found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        Task {
                            await loadPerformers()
                            await loadPerformerCounts()
                        }
                    }) {
                        Text("Refresh")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding(.vertical, 100)
                .frame(maxWidth: .infinity)
            } else {
                // Performer selection grid with marker counts
                
                // Sort the performers first to avoid complex expression in ForEach
                let sortedPerformers = performersWithMarkerCount.sorted { item1, item2 in
                    if isSortingByMarkers {
                        return item1.markerCount > item2.markerCount
                    } else {
                        return item1.performer.name < item2.performer.name
                    }
                }
                
                LazyVGrid(columns: performerColumns, spacing: 16) {
                    ForEach(sortedPerformers) { item in
                        Button(action: {
                            selectedPerformer = item.performer
                            if let performer = selectedPerformer {
                                Task {
                                    await loadPerformerMarkers(performer: performer)
                                }
                            }
                        }) {
                            VStack {
                                // Performer avatar or placeholder
                                if let imagePath = item.performer.image_path, !imagePath.isEmpty {
                                    AsyncImage(url: URL(string: "\(appModel.serverAddress)\(imagePath)")) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.2))
                                    }
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 120, height: 120)
                                        .foregroundColor(.gray)
                                }
                                
                                // Performer name
                                Text(item.performer.name)
                                    .font(.headline)
                                    .lineLimit(1)
                                
                                // Marker count badge
                                Text("\(item.markerCount) markers")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
        }
    }
    
    /// Loading view for marker content
    private var markerLoadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.5)
                .padding()

            Text("Loading markers for \(selectedPerformer?.name ?? "performer")...")
                .foregroundColor(.secondary)
            
            // Add cancel button
            Button("Cancel") {
                // Cancel loading
                appModel.api.isLoading = false
                selectedPerformer = nil
            }
            .padding(.top, 16)
        }
        .padding(.vertical, 100)
        .frame(maxWidth: .infinity)
    }
    
    /// Empty state view for when no markers are found
    private var emptyMarkersView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
                .padding()

            Text("No markers found for \(selectedPerformer?.name ?? "performer")")
                .font(.headline)
                .foregroundColor(.secondary)

            if searchText.isNotEmpty {
                Text("Try clearing your search or filter")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if let selectedTag = selectedTag {
                Text("Filter active: \(selectedTag.name)")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                
                Button("Clear Tag Filter") {
                    withAnimation {
                        self.selectedTag = nil
                        Self.logger.debug("Tag filter cleared from empty state view")
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.vertical, 4)
            }

            if let performer = selectedPerformer {
                Text("ID: \(performer.id)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let error = appModel.api.error {
                Text("Error: \(error.localizedDescription)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
                
                Button("Retry") {
                    if let performer = selectedPerformer {
                        Task {
                            await loadPerformerMarkers(performer: performer)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .padding(.vertical, 4)
            }

            HStack(spacing: 16) {
                Button("Select Different Performer") {
                    selectedPerformer = nil
                    appModel.api.markers = []
                    searchText = ""
                    selectedTag = nil
                }
                .buttonStyle(.bordered)
                
                if let performer = selectedPerformer {
                    Button("Reload Markers") {
                        Task {
                            await loadPerformerMarkers(performer: performer)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .padding()
    }
    
    /// Filter menu with sorting options and filter settings
    private var filterMenu: some View {
        Menu {
            Section("Sort By") {
                ForEach(MarkerSortOption.allCases) { option in
                    Button(action: {
                        sortOption = option
                        sortMarkers()
                    }) {
                        HStack {
                            Text(option.label)
                            if sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            if let performer = selectedPerformer {
                Section("Tags") {
                    // Get unique tags from markers
                    let allTags = Array(Set(appModel.api.markers.flatMap { [$0.primary_tag] + $0.tags }))
                    let sortedTags = allTags.sorted { $0.name < $1.name }
                    
                    // Option to show all (clear filter)
                    Button(action: {
                        selectedTag = nil
                    }) {
                        HStack {
                            Text("All Tags")
                            if selectedTag == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    // Tag options
                    ForEach(sortedTags) { tag in
                        Button(action: {
                            // Convert to StashScene.Tag with proper animation
                            withAnimation {
                                Self.logger.debug("Setting tag filter from menu: \(tag.name) (ID: \(tag.id))")
                                selectedTag = StashScene.Tag(id: tag.id, name: tag.name)
                            }
                        }) {
                            HStack {
                                Text(tag.name)
                                if selectedTag?.id == tag.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                // Refresh option
                Section {
                    Button(action: {
                        Task {
                            await loadPerformerMarkers(performer: performer)
                        }
                    }) {
                        Label("Refresh Markers", systemImage: "arrow.clockwise")
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }
    
    // MARK: - Methods
    
    /// Load performers from the API
    private func loadPerformers() async {
        do {
            await appModel.api.fetchPerformers(completion: { result in
                switch result {
                case .success(let performers):
                    Self.logger.info("Successfully loaded \(performers.count) performers")
                case .failure(let error):
                    Self.logger.error("Error loading performers: \(error.localizedDescription)")
                    showErrorMessage("Failed to load performers: \(error.localizedDescription)")
                }
            })
        } catch {
            Self.logger.error("Error loading performers: \(error.localizedDescription)")
            showErrorMessage("Failed to load performers: \(error.localizedDescription)")
        }
    }
    
    /// Load performer marker counts
    private func loadPerformerCounts() async {
        Self.logger.info("Loading marker counts for \(appModel.api.performers.count) performers")
        performersWithMarkerCount = []
        
        // Use Batch API methods
        await withTaskGroup(of: PerformerWithMarkerCount?.self) { group in
            for performer in appModel.api.performers {
                group.addTask {
                    let count = await getMarkerCount(for: performer)
                    return PerformerWithMarkerCount(
                        id: performer.id,
                        performer: performer,
                        markerCount: count
                    )
                }
            }
            
            for await result in group {
                if let result = result {
                    await MainActor.run {
                        performersWithMarkerCount.append(result)
                    }
                }
            }
        }
        
        // Sort by marker count by default
        await MainActor.run {
            performersWithMarkerCount.sort { $0.markerCount > $1.markerCount }
        }
    }
    
    /// Get marker count for a performer
    private func getMarkerCount(for performer: StashScene.Performer) async -> Int {
        // Using the updated format that matches Vision Pro and fixed JSON format
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

        // Use the StashAPI's executeGraphQLQuery method
        do {
            Self.logger.debug("Fetching marker count for performer: \(performer.name) (ID: \(performer.id))")
            let data = try await appModel.api.executeGraphQLQuery(query)

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
            Self.logger.debug("Found \(response.data.findSceneMarkers.count) markers for performer \(performer.name)")
            return response.data.findSceneMarkers.count
        } catch {
            Self.logger.error("Error fetching marker count for \(performer.name): \(error.localizedDescription)")
            return 0
        }
    }
    
    /// Load markers for a performer
    private func loadPerformerMarkers(performer: StashScene.Performer) async {
        Self.logger.info("Loading markers for performer: \(performer.name) (ID: \(performer.id))")
        currentPage = 1
        hasMorePages = true
        isLoadingMore = false
        searchText = ""
        selectedTag = nil
        
        // Show loading state
        await MainActor.run {
            appModel.api.isLoading = true
            appModel.api.markers = []
            appModel.api.error = nil
        }

        do {
            // Use the async/await version of fetchPerformerMarkers
            let markers = try await appModel.api.fetchPerformerMarkers(performerId: performer.id, page: currentPage)
            
            await MainActor.run {
                // Update marker data
                appModel.api.markers = markers
                appModel.api.isLoading = false
                
                // Track total and check for more pages
                totalCount = markers.count
                hasMorePages = markers.count >= 20 // Assuming default page size is 20
                
                // Apply sorting
                sortMarkers()
            }
            
            Self.logger.info("Successfully loaded \(markers.count) markers for performer \(performer.name)")
        } catch {
            Self.logger.error("Error loading markers: \(error.localizedDescription)")
            await MainActor.run {
                appModel.api.error = error
                appModel.api.isLoading = false
                showErrorMessage("Failed to load markers: \(error.localizedDescription)")
            }
        }
    }
    
    /// Load more markers (pagination)
    private func loadMoreMarkers() async {
        guard !isLoadingMore, let performer = selectedPerformer else { return }

        Self.logger.info("Loading more markers for performer: \(performer.name) (page \(currentPage + 1))")
        isLoadingMore = true
        currentPage += 1

        // Remember the previous count for comparison
        let previousCount = appModel.api.markers.count

        do {
            // Use the async/await version to load more markers
            let newMarkers = try await appModel.api.fetchPerformerMarkers(performerId: performer.id, page: currentPage)
            
            await MainActor.run {
                // Append new markers to existing ones, avoiding duplicates
                let uniqueNewMarkers = newMarkers.filter { newMarker in
                    !appModel.api.markers.contains { $0.id == newMarker.id }
                }
                appModel.api.markers.append(contentsOf: uniqueNewMarkers)
                
                // Update tracking for more pages
                hasMorePages = !newMarkers.isEmpty && newMarkers.count >= 20 // Assuming default page size is 20
                
                // Apply current sorting to keep consistency
                sortMarkers()
            }
            
            // Log results
            let newCount = appModel.api.markers.count
            let addedCount = newCount - previousCount
            Self.logger.info("Added \(addedCount) markers (total now: \(newCount))")
        } catch {
            Self.logger.error("Error loading more markers: \(error.localizedDescription)")
            await MainActor.run {
                appModel.api.error = error
                showErrorMessage("Failed to load more markers: \(error.localizedDescription)")
            }
        }

        // Update loading state
        hasMorePages = appModel.api.markers.count > previousCount
        isLoadingMore = false
    }
    
    /// Sort markers based on current sort option
    private func sortMarkers() {
        Self.logger.debug("Sorting markers using option: \(sortOption.rawValue)")
        
        // Sort markers array based on current sort option
        switch sortOption {
        case .timestamp:
            appModel.api.markers.sort { $0.seconds < $1.seconds }
        case .title:
            appModel.api.markers.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .createdAtDesc:
            // Sort by ID as fallback for creation order
            appModel.api.markers.sort { $0.id > $1.id }
        case .createdAtAsc:
            // Sort by ID as fallback for creation order
            appModel.api.markers.sort { $0.id < $1.id }
        case .sceneTitleAsc:
            appModel.api.markers.sort { ($0.scene.title ?? "").localizedCaseInsensitiveCompare($1.scene.title ?? "") == .orderedAscending }
        case .sceneTitleDesc:
            appModel.api.markers.sort { ($0.scene.title ?? "").localizedCaseInsensitiveCompare($1.scene.title ?? "") == .orderedDescending }
        }
        
        Self.logger.debug("Sorted \(appModel.api.markers.count) markers")
    }
    
    /// Display error message
    private func showErrorMessage(_ message: String) {
        withAnimation {
            errorMessage = message
            showError = true
            
            // Auto-hide error after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation {
                    if self.errorMessage == message {
                        self.showError = false
                    }
                }
            }
        }
    }
    
    /// Refresh content based on current view state
    private func refreshContent() async {
        if let performer = selectedPerformer {
            await loadPerformerMarkers(performer: performer)
        } else {
            await loadPerformers()
            await loadPerformerCounts()
        }
    }
    
    // MARK: - Helper Methods
    
    // Helper method to set HLS streaming preference
    private func setHLSPreference(for marker: SceneMarker) {
        print("🎬 PerformerMarkersView: Setting HLS preference for marker: \(marker.title)")
        
        // Set preference for HLS streaming
        UserDefaults.standard.set(true, forKey: "scene_\(marker.scene.id)_preferHLS")
        UserDefaults.standard.set(true, forKey: "scene_\(marker.scene.id)_isMarkerNavigation")
        
        // Save timestamp for player to use - make sure this is a Double
        let markerSeconds = Double(marker.seconds)
        UserDefaults.standard.set(markerSeconds, forKey: "scene_\(marker.scene.id)_startTime")
        
        // Add support for end_seconds if available
        if let markerEndSeconds = marker.end_seconds {
            let endSeconds = Double(markerEndSeconds)
            UserDefaults.standard.set(endSeconds, forKey: "scene_\(marker.scene.id)_endTime")
            print("⏱ PerformerMarkersView: Setting end time for marker: \(endSeconds)")
        } else {
            // Clear any previous end time
            UserDefaults.standard.removeObject(forKey: "scene_\(marker.scene.id)_endTime")
        }
        
        // Get API key for authentication
        let apiKey = appModel.apiKey
        let baseServerURL = appModel.serverAddress.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let sceneId = marker.scene.id
        
        // Current timestamp (similar to _ts parameter in the URL)
        let currentTimestamp = Int(Date().timeIntervalSince1970)
        
        // Format exactly like the example URL:
        // http://192.168.86.100:9999/scene/3174/stream.m3u8?apikey=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1aWQiOiJjayIsInN1YiI6IkFQSUtleSIsImlhdCI6MTczMTgwOTM2Mn0.7AOyZqTzyDsSnuDx__RBhuIIkoPg2btebToAlpK1zXo&resolution=ORIGINAL&t=2132&_ts=1747330385
        let hlsStreamURL = "\(baseServerURL)/scene/\(sceneId)/stream.m3u8?apikey=\(apiKey)&resolution=ORIGINAL&t=\(Int(markerSeconds))&_ts=\(currentTimestamp)"
        
        print("🎬 PerformerMarkersView: Setting exact HLS URL format: \(hlsStreamURL)")
        UserDefaults.standard.set(hlsStreamURL, forKey: "scene_\(marker.scene.id)_hlsURL")
        
        // Force immediate playback flag
        UserDefaults.standard.set(true, forKey: "scene_\(marker.scene.id)_forcePlay")
    }
}

// MARK: - String Extensions
extension String {
    var isNotEmpty: Bool {
        !self.isEmpty
    }
}

// Using MarkerSortOption from MarkerViewModel.swift

// MARK: - Preview
struct PerformerMarkersView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PerformerMarkersView()
                .environmentObject(AppModel())
        }
    }
}