import SwiftUI

struct MarkersSearchResultsView: View {
    let markers: [SceneMarker]
    let totalCount: Int?
    let onMarkerAppear: ((SceneMarker) -> Void)?
    @EnvironmentObject private var appModel: AppModel
    
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
            // ALWAYS show shuffle button when there are markers (regardless of search query state)
            if !markers.isEmpty {
                prominentShuffleButton
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
    
    private var prominentShuffleButton: some View {
        VStack(spacing: 8) {
            // Big prominent shuffle button
            Button(action: {
                print("🎲 PROMINENT SHUFFLE BUTTON TAPPED - LOADING ALL MARKERS FROM API")
                print("🎲 Current displayed markers: \(markers.count)")
                
                // Always treat marker search results as text-based searches to get ALL matching markers
                // This ensures we fetch all markers from the server, not just the displayed ones
                if !markers.isEmpty {
                    // Check if we can extract the search query from the markers
                    // For text searches like "cumshot", we want ALL markers containing that term
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