import SwiftUI

struct MarkersSearchResultsView: View {
    let markers: [SceneMarker]
    let totalCount: Int?
    let onMarkerAppear: ((SceneMarker) -> Void)?
    @EnvironmentObject private var appModel: AppModel
    
    @State private var selectedTagIds: Set<String> = []
    @State private var selectedTagNames: Set<String> = []
    @State private var selectedSearchTerms: Set<String> = []
    @State private var pendingTagSelections: Set<String> = []
    @State private var isMultiTagMode: Bool = false
    @State private var showingTagSelector = false
    @State private var availableTags: [SceneMarker.Tag] = []
    @State private var markerSearchText: String = ""
    @State private var combinedMarkers: [SceneMarker] = []
    @State private var isLoadingCombined = false
    @State private var searchResults: [SceneMarker] = []
    @State private var isSearching = false
    @State private var combinedTotalCount: Int = 0
    
    init(markers: [SceneMarker], totalCount: Int? = nil, onMarkerAppear: ((SceneMarker) -> Void)? = nil) {
        self.markers = markers
        self.totalCount = totalCount
        self.onMarkerAppear = onMarkerAppear
    }
    
    private var columns: [GridItem] {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return [GridItem(.adaptive(minimum: 350, maximum: 450), spacing: 20)]
        } else {
            return [GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)]
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ALWAYS show shuffle button when there are markers, but show Add More button always
            if !markers.isEmpty {
                prominentShuffleButton
            } else {
                // Show just the Add More button when no markers are loaded
                VStack(spacing: 16) {
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            print("🏷️🏷️🏷️ Add More button tapped in empty markers view!")
                            extractAvailableTags()
                            DispatchQueue.main.async {
                                showingTagSelector = true
                                isMultiTagMode = true
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 24, weight: .bold))
                                Text("Add More")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .background(Color.green)
                            .cornerRadius(16)
                            .shadow(color: .green.opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                        
                        Spacer()
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
            }
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(markers, id: \.id) { marker in
                        MarkerRowWrapper(marker: marker)
                            .environmentObject(appModel)
                            .onAppear {
                                // Only trigger pagination when we're near the end of the list
                                if let markerIndex = markers.firstIndex(where: { $0.id == marker.id }),
                                   markerIndex >= markers.count - 10 { // Trigger when within last 10 items
                                    onMarkerAppear?(marker)
                                }
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // Multi-tag helper functions
    private func extractAvailableTags() {
        print("🏷️ extractAvailableTags called - markers.count: \(markers.count)")
        if !markers.isEmpty {
            // Get tags from current search results
            let currentTags = Set(markers.flatMap { marker in
                [marker.primary_tag] + marker.tags
            })
            
            availableTags = Array(currentTags).sorted { $0.name.lowercased() < $1.name.lowercased() }
            print("🏷️ Available tags from current results: \(availableTags.count)")
        } else {
            // If no markers loaded, fetch popular tags to start with
            print("🏷️ No markers available, fetching popular tags to start combination")
            Task {
                await fetchPopularTags()
            }
        }
    }
    
    private func fetchPopularTags() async {
        do {
            // Search for a few popular markers to get their tags
            let popularQueries = ["blowjob", "anal", "creampie", "deepthroat", "missionary"]
            var allTags = Set<SceneMarker.Tag>()
            
            for query in popularQueries {
                let searchMarkers = try await appModel.api.searchMarkers(query: query, page: 1, perPage: 10)
                let tags: Set<SceneMarker.Tag> = Set(searchMarkers.flatMap { marker in
                    [marker.primary_tag] + marker.tags
                })
                allTags.formUnion(tags)
            }
            
            await MainActor.run {
                availableTags = Array(allTags).sorted { $0.name.lowercased() < $1.name.lowercased() }
                print("🏷️ Fetched \(availableTags.count) popular tags for combination")
            }
        } catch {
            print("❌ Failed to fetch popular tags: \(error)")
        }
    }
    
    
    private func searchForTags(_ query: String) async {
        guard !query.isEmpty else { return }
        
        isSearching = true
        print("🔍 Searching for tags matching: '\(query)'")
        
        // Use a separate API call that doesn't interfere with current markers
        do {
            let searchedMarkers = try await appModel.api.searchMarkers(query: query, page: 1, perPage: 2000)
            
            await MainActor.run {
                // Get unique tags from the search results (preserve original case)
                let uniqueTags = Set(searchedMarkers.map { $0.primary_tag.name })
                
                // Filter to tags that contain our search query and aren't already selected
                let matchingTags = uniqueTags.filter { tagName in
                    tagName.lowercased().contains(query.lowercased()) && !selectedSearchTerms.contains(tagName)
                }
                
                // Create results using real markers that have matching tags
                searchResults = Array(matchingTags.prefix(10).compactMap { tagName in
                    // Find a real marker with this tag to use
                    searchedMarkers.first(where: { $0.primary_tag.name == tagName })
                })
                
                isSearching = false
                print("🔍 Found \(matchingTags.count) unique tags matching '\(query)': \(matchingTags.sorted())")
            }
        } catch {
            await MainActor.run {
                print("🔍 Error searching for tags: \(error)")
                searchResults = []
                isSearching = false
            }
        }
    }
    
    private func loadCombinedMarkers() async {
        // Always allow combination - if no additional terms selected, just use current markers
        if selectedSearchTerms.isEmpty {
            await MainActor.run {
                combinedMarkers = markers
                isLoadingCombined = false
            }
            return
        }
        
        print("🔄 Loading combined markers for current search + selected search terms")
        await MainActor.run {
            isLoadingCombined = true
        }
        
        var allCombinedMarkers = Set<SceneMarker>()
        var totalEstimatedCount = 0
        
        // Start with current search results
        for marker in markers {
            allCombinedMarkers.insert(marker)
        }
        print("🔄 Added \(markers.count) markers from current search")
        
        // Get the actual total count for each tag from the server
        // We'll show the count but only load first page for UI responsiveness
        for searchTerm in selectedSearchTerms {
            print("🔄 Getting total count for search term: '\(searchTerm)'")
            
            do {
                // First get the total count by fetching just 1 marker
                let countQuery = """
                {
                    "operationName": "FindSceneMarkers",
                    "variables": {
                        "filter": {
                            "q": "\(searchTerm)",
                            "page": 1,
                            "per_page": 1,
                            "sort": "title",
                            "direction": "ASC"
                        }
                    },
                    "query": "query FindSceneMarkers($filter: FindFilterType) { findSceneMarkers(filter: $filter) { count } }"
                }
                """
                
                let countData = try await appModel.api.executeGraphQLQuery(countQuery)
                
                struct CountResponse: Decodable {
                    struct Data: Decodable {
                        struct FindSceneMarkers: Decodable {
                            let count: Int
                        }
                        let findSceneMarkers: FindSceneMarkers
                    }
                    let data: Data
                }
                
                let response = try JSONDecoder().decode(CountResponse.self, from: countData)
                let tagCount = response.data.findSceneMarkers.count
                totalEstimatedCount += tagCount
                print("🔄 Tag '\(searchTerm)' has \(tagCount) total markers")
                
                // Now load first page of actual markers for UI display
                let searchMarkers = try await appModel.api.searchMarkers(query: searchTerm, page: 1, perPage: 2000)
                
                // Filter to exact matches only
                let exactMatches = searchMarkers.filter { marker in
                    marker.primary_tag.name.lowercased() == searchTerm.lowercased()
                }
                
                for marker in exactMatches {
                    allCombinedMarkers.insert(marker)
                }
                print("🔄 Added \(exactMatches.count) exact match markers for display")
            } catch {
                print("❌ Error loading markers for '\(searchTerm)': \(error)")
            }
        }
        
        // Add current search count if available
        if let currentTotalCount = totalCount {
            totalEstimatedCount += currentTotalCount
        }
        
        await MainActor.run {
            combinedMarkers = Array(allCombinedMarkers)
            combinedTotalCount = totalEstimatedCount
            isLoadingCombined = false
            
            // Store the estimated total for display
            // Note: This is the TRUE total from server, not just what we loaded
            print("✅ Combined estimated total: \(totalEstimatedCount) markers from \(1 + selectedSearchTerms.count) searches")
            print("✅ Loaded \(combinedMarkers.count) unique markers for UI display")
        }
    }
    
    private func toggleTagSelection(_ tag: SceneMarker.Tag) {
        if selectedTagIds.contains(tag.id) {
            selectedTagIds.remove(tag.id)
        } else {
            selectedTagIds.insert(tag.id)
        }
        print("🏷️ Selected tags: \(selectedTagIds.count)")
    }

    private var prominentShuffleButton: some View {
        VStack(spacing: 8) {
            // Button row with Shuffle All and Add Tags
            HStack(spacing: 12) {
                // Big prominent shuffle button
                Button(action: {
                print("🎲 PROMINENT SHUFFLE BUTTON TAPPED - LOADING ALL MARKERS FROM API")
                print("🎲 Current displayed markers: \(markers.count)")
                
                // Check if we're in multi-search mode
                if isMultiTagMode {
                    print("🎲 Multi-search shuffle mode: \(selectedSearchTerms.count) additional searches selected: \(Array(selectedSearchTerms))")
                    print("🎲 Using \(combinedMarkers.count) combined markers")
                    
                    // Create combined search terms and tag IDs for shuffle
                    var allSearchTerms: [String] = []
                    var allTagIds: [String] = []
                    
                    // Extract actual tag names and IDs from the current markers (preserve original case)
                    let currentTags = Set(markers.map { $0.primary_tag })
                    let currentTagNames = currentTags.map { $0.name }
                    let currentTagIds = currentTags.map { $0.id }
                    
                    allSearchTerms.append(contentsOf: currentTagNames)
                    allTagIds.append(contentsOf: currentTagIds)
                    print("🎲 DEBUG - Current tags from markers: \(currentTagNames) with IDs: \(currentTagIds)")
                    
                    // Add selected search terms (these are tag names from user selection)
                    allSearchTerms.append(contentsOf: selectedSearchTerms)
                    
                    // For selected search terms, we need to find their corresponding tag IDs from the combined markers
                    for searchTerm in selectedSearchTerms {
                        if let matchingMarker = combinedMarkers.first(where: { $0.primary_tag.name.lowercased() == searchTerm.lowercased() }) {
                            allTagIds.append(matchingMarker.primary_tag.id)
                            print("🎲 DEBUG - Found tag ID '\(matchingMarker.primary_tag.id)' for search term '\(searchTerm)'")
                        } else {
                            print("⚠️ Could not find tag ID for search term '\(searchTerm)'")
                        }
                    }
                    
                    let searchTermsArray = Array(Set(allSearchTerms)) // Remove duplicates
                    let tagIdsArray = Array(Set(allTagIds)) // Remove duplicates
                    print("🎲 Combining tags for shuffle: \(searchTermsArray.joined(separator: " + "))")
                    print("🎲 DEBUG - Final tag names: \(searchTermsArray)")
                    print("🎲 DEBUG - Final tag IDs: \(tagIdsArray)")
                    
                    // Use the multi-tag shuffle function with combined markers
                    print("🎲 Starting shuffle with \(combinedMarkers.count) combined markers")
                    
                    // Ensure we have markers to shuffle
                    let markersToShuffle = !combinedMarkers.isEmpty ? combinedMarkers : markers
                    
                    if !markersToShuffle.isEmpty {
                        print("🎲 Shuffling \(markersToShuffle.count) markers for tags: \(searchTermsArray.joined(separator: ", "))")
                        
                        // Debug: Print first few markers to verify they belong to the expected tags
                        for (index, marker) in markersToShuffle.prefix(3).enumerated() {
                            print("🎲 DEBUG - Sample marker \(index + 1): '\(marker.title)' - Tag: '\(marker.primary_tag.name)' (ID: \(marker.primary_tag.id))")
                        }
                        
                        // Start the multi-tag shuffle with proper tag IDs and names
                        print("🎲 Calling startMarkerShuffle with tagIds: \(tagIdsArray) and tagNames: \(searchTermsArray)")
                        appModel.startMarkerShuffle(forMultipleTags: tagIdsArray, tagNames: searchTermsArray, displayedMarkers: markersToShuffle)
                    } else {
                        print("❌ No markers available to shuffle!")
                    }
                } else if !markers.isEmpty {
                    // Original single-tag/search logic
                    print("🎲 Marker search results detected - treating as text search")
                    
                    // Try to get search query from app model first
                    if !appModel.searchQuery.isEmpty {
                        print("🎲 Using appModel.searchQuery: '\(appModel.searchQuery)'")
                        appModel.startMarkerShuffle(forSearchQuery: appModel.searchQuery, displayedMarkers: markers)
                    } else if let currentShuffleQuery = appModel.shuffleSearchQuery {
                        print("🎲 Using existing shuffleSearchQuery: '\(currentShuffleQuery)'")
                        appModel.startMarkerShuffle(forSearchQuery: currentShuffleQuery, displayedMarkers: markers)
                    } else {
                        // If no search query in app model, check if all markers share the same primary tag
                        let firstTag = markers[0].primary_tag
                        let allSameTag = markers.allSatisfy { $0.primary_tag.id == firstTag.id }
                        
                        if allSameTag {
                            // All markers have same tag - treat as tag search
                            print("🎲 All markers share tag '\(firstTag.name)' - using tag-based shuffle")
                            appModel.startMarkerShuffle(forTag: firstTag.id, tagName: firstTag.name, displayedMarkers: markers)
                        } else {
                            // Mixed tags - try to infer search term from marker titles/tags
                            print("🎲 Mixed marker results - using displayed markers only as fallback")
                            appModel.startMarkerShuffle(withMarkers: markers)
                        }
                    }
                } else {
                    // Fallback to simple shuffle if no markers
                    print("🎲 No markers available - cannot start shuffle")
                    appModel.startMarkerShuffle(withMarkers: markers)
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "shuffle.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        if isMultiTagMode {
                            Text("Shuffle Combined")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            // Show original search + selected search terms
                            let displayTerms = {
                                var terms: [String] = []
                                if !appModel.searchQuery.isEmpty {
                                    terms.append(appModel.searchQuery)
                                }
                                terms.append(contentsOf: selectedSearchTerms)
                                return terms
                            }()
                            
                            let displayText = displayTerms.isEmpty ? "Current Tag" : displayTerms.joined(separator: " + ")
                            Text(displayText)
                                .font(.caption)
                                .opacity(0.9)
                                .lineLimit(2)
                            
                            if isLoadingCombined {
                                Text("Loading combined results...")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            } else if combinedTotalCount > 0 {
                                Text("\(combinedTotalCount) total markers")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        } else {
                            Text("Shuffle All")
                                .font(.title2)
                                .fontWeight(.bold)
                            if let totalCount = totalCount {
                                Text("Load ALL \(totalCount) matching markers from server")
                                    .font(.caption)
                                    .opacity(0.9)
                            } else {
                                Text("Load ALL matching markers from server")
                                    .font(.caption)
                                    .opacity(0.9)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.purple, Color.blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: .purple.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .scaleEffect(appModel.isMarkerShuffleMode ? 0.95 : 1.0)
                .animation(.spring(response: 0.3), value: appModel.isMarkerShuffleMode)
                
                // Add Tags button  
                Button(action: {
                    print("🏷️🏷️🏷️ Add More button tapped in prominent shuffle section!")
                    extractAvailableTags()
                    DispatchQueue.main.async {
                        showingTagSelector = true
                        isMultiTagMode = true
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24, weight: .bold))
                        Text(selectedSearchTerms.isEmpty ? "Add More" : "Added (\(selectedSearchTerms.count))")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(selectedSearchTerms.isEmpty ? Color.green : Color.blue)
                    .cornerRadius(16)
                    .shadow(color: .green.opacity(0.4), radius: 8, x: 0, y: 4)
                }
            }
            
            // Active shuffle status
            if appModel.isMarkerShuffleMode {
                HStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .foregroundColor(.green)
                    Text("Shuffle Active • \(appModel.markerShuffleQueue.count) in queue")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Button("Stop") {
                        appModel.stopMarkerShuffle()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .onAppear {
            extractAvailableTags()
        }
        .sheet(isPresented: $showingTagSelector) {
            tagSelectorView
        }
    }
    
    private var tagSelectorView: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Search section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Search for tags to add:")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    TextField("Type tag name (e.g., missionary)", text: $markerSearchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.body)
                        .onChange(of: markerSearchText) { _, newValue in
                            if !newValue.isEmpty && newValue.count > 1 {
                                Task {
                                    await searchForTags(newValue)
                                }
                            } else {
                                searchResults = []
                            }
                        }
                }
                .padding(.horizontal)
                
                // Search results or loading
                if isSearching {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .scaleEffect(1.2)
                        Text("Searching...")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 40)
                } else if !searchResults.isEmpty && !markerSearchText.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Tap tags to select (\(pendingTagSelections.count) selected):")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                            ForEach(searchResults.prefix(20), id: \.id) { marker in
                                let tagName = marker.primary_tag.name
                                let isSelected = pendingTagSelections.contains(tagName)
                                
                                Button(action: {
                                    if isSelected {
                                        pendingTagSelections.remove(tagName)
                                    } else {
                                        pendingTagSelections.insert(tagName)
                                    }
                                }) {
                                    Text(tagName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .frame(minWidth: 100)
                                        .background(isSelected ? Color.blue : Color(.systemGray5))
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                } else if !markerSearchText.isEmpty {
                    Text("No tags found matching '\(markerSearchText)'")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 40)
                } else if !availableTags.isEmpty {
                    // Show popular tags when sheet first opens
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Popular tags to combine (\(pendingTagSelections.count) selected):")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                            ForEach(availableTags.prefix(20), id: \.id) { tag in
                                let tagName = tag.name
                                let isSelected = pendingTagSelections.contains(tagName)
                                
                                Button(action: {
                                    if isSelected {
                                        pendingTagSelections.remove(tagName)
                                    } else {
                                        pendingTagSelections.insert(tagName)
                                    }
                                }) {
                                    Text(tagName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .frame(minWidth: 100)
                                        .background(isSelected ? Color.blue : Color(.systemGray5))
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                } else {
                    // Show while fetching initial tags
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .green))
                            .scaleEffect(1.2)
                        Text("Loading popular tags...")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 40)
                }
                
                Spacer()
                
                // Add Selected button
                if !pendingTagSelections.isEmpty {
                    Button("Add Selected (\(pendingTagSelections.count))") {
                        // Move pending selections to selected search terms
                        for tagName in pendingTagSelections {
                            selectedSearchTerms.insert(tagName)
                        }
                        print("🎲 Added \(pendingTagSelections.count) tags. Total selected: \(selectedSearchTerms)")
                        pendingTagSelections.removeAll()
                        
                        // Set multi-tag mode and load combined markers
                        isMultiTagMode = true
                        Task {
                            await loadCombinedMarkers()
                        }
                        
                        // Clear search and results
                        markerSearchText = ""
                        searchResults = []
                        showingTagSelector = false
                    }
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                // Show currently added tags
                if !selectedSearchTerms.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Currently added (\(selectedSearchTerms.count)):")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                            ForEach(Array(selectedSearchTerms), id: \.self) { searchTerm in
                                HStack(spacing: 4) {
                                    Text(searchTerm)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    
                                    Button(action: {
                                        selectedSearchTerms.remove(searchTerm)
                                        Task {
                                            await loadCombinedMarkers()
                                        }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                    }
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green)
                                .cornerRadius(6)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Add More Markers (\(selectedSearchTerms.count) added)")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    showingTagSelector = false
                }
                .foregroundColor(.blue)
                .font(.body)
                .fontWeight(.semibold)
            )
        }
    }
    
    private var universalShuffleButton: some View {
        VStack(spacing: 12) {
            HStack {
                // Info about what we're shuffling
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shuffle search results for '\(appModel.searchQuery)'")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    Text("Found \(markers.count) markers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Shuffle button
                Button(action: {
                    print("🎲 UNIVERSAL SHUFFLE BUTTON TAPPED IN SEARCH RESULTS")
                    print("🎲 Starting shuffle for search: \(appModel.searchQuery) with \(markers.count) markers")
                    appModel.startMarkerShuffle(forSearchQuery: appModel.searchQuery, displayedMarkers: markers)
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
        .padding(.top, 8)
    }
}

struct MarkerRowWrapper: View {
    let marker: SceneMarker
    @EnvironmentObject private var appModel: AppModel
    
    var body: some View {
        MarkerRow(
            marker: marker,
            serverAddress: appModel.serverAddress,
            onTitleTap: { selectedMarker in
                handleMarkerNavigation(selectedMarker)
            },
            onTagTap: { tagName in
                handleTagTap(tagName)
            },
            onPerformerTap: { performer in
                appModel.navigateToPerformer(performer)
            },
            onShuffleTap: { tagId in
                // Handle shuffle from individual marker row in search results
                print("🎲 Individual marker shuffle button tapped for tag ID: \(tagId)")
                let tagName = marker.primary_tag.name
                print("🎲 Starting shuffle for tag: \(tagName) (ID: \(tagId))")
                appModel.startMarkerShuffle(forTag: tagId, tagName: tagName, displayedMarkers: [marker])
            }
        )
        .frame(maxWidth: .infinity)
    }
    
    private func handleMarkerNavigation(_ selectedMarker: SceneMarker) {
        // Use the proper navigateToMarker method which handles timestamps correctly
        print("⏱ MarkersSearchResultsView: Navigating to marker \(selectedMarker.title) at \(selectedMarker.seconds) seconds")
        appModel.navigateToMarker(selectedMarker)
    }
    
    private func handleTagTap(_ tagName: String) {
        // Start shuffling markers for the tapped tag
        print("🏷️ Tag tapped in search results: '\(tagName)' - starting tag-based shuffle")
        
        // Find the tag in either primary_tag or tags array
        let primaryTag = marker.primary_tag
        if primaryTag.name == tagName {
            // Use primary tag for shuffle
            print("🎲 Starting shuffle for primary tag: \(primaryTag.name) (ID: \(primaryTag.id))")
            appModel.startMarkerShuffle(forTag: primaryTag.id, tagName: primaryTag.name, displayedMarkers: [marker])
        } else if let foundTag = marker.tags.first(where: { $0.name == tagName }) {
            // Use found tag for shuffle
            print("🎲 Starting shuffle for secondary tag: \(foundTag.name) (ID: \(foundTag.id))")
            appModel.startMarkerShuffle(forTag: foundTag.id, tagName: foundTag.name, displayedMarkers: [marker])
        } else {
            print("⚠️ Could not find tag '\(tagName)' in marker tags")
        }
    }
    
    private func findOrCreateScene(for marker: SceneMarker) -> StashScene? {
        // First check if scene exists in API
        if let existingScene = appModel.api.scenes.first(where: { $0.id == marker.scene.id }) {
            return existingScene
        }
        
        // Otherwise create from marker data
        guard let scenePaths = marker.scene.paths else { return nil }
        
        return StashScene(
            id: marker.scene.id,
            title: marker.scene.title,
            details: nil,
            paths: StashScene.ScenePaths(
                screenshot: scenePaths.screenshot ?? "",
                preview: scenePaths.preview,
                stream: scenePaths.stream ?? ""
            ),
            files: [],
            performers: marker.scene.performers ?? [],
            tags: [],
            rating100: nil,
            o_counter: nil
        )
    }
}