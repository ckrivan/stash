import SwiftUI

struct MarkersSearchResultsView: View {
    let markers: [SceneMarker]
    let totalCount: Int?
    let onMarkerAppear: ((SceneMarker) -> Void)?
    let onOpenTagSelector: (([SceneMarker.Tag]) -> Void)?  // Callback to parent
    @EnvironmentObject private var appModel: AppModel
    
    // Simplified state - no complex tag management needed
    
    init(markers: [SceneMarker], totalCount: Int? = nil, onMarkerAppear: ((SceneMarker) -> Void)? = nil, onOpenTagSelector: (([SceneMarker.Tag]) -> Void)? = nil) {
        self.markers = markers
        self.totalCount = totalCount
        self.onMarkerAppear = onMarkerAppear
        self.onOpenTagSelector = onOpenTagSelector
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
            // Show helpful text for empty state or shuffle button for loaded markers
            if !markers.isEmpty {
                prominentShuffleButton
            } else {
                // Show helpful text about the new search syntax
                VStack(spacing: 16) {
                    Text("🏷️ Combine Tags with Search")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text("Search for multiple tags using + syntax:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("blowjob +anal +creampie")
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    
                    Text("This will find markers that contain ALL specified tags")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                .padding(.vertical, 24)
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
            // Just the shuffle button - tag combination handled via search
                // Big prominent shuffle button
                Button(action: {
                print("🎲 PROMINENT SHUFFLE BUTTON TAPPED - LOADING ALL MARKERS FROM API")
                print("🎲 Current displayed markers: \(markers.count)")
                
                if !markers.isEmpty {
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