import SwiftUI

struct MarkersSearchResultsView: View {
    let markers: [SceneMarker]
    @EnvironmentObject private var appModel: AppModel
    
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
                
                // Determine if this is a tag-based search or text search
                if !markers.isEmpty {
                    // Check if all markers have the same primary tag (tag search)
                    let firstTag = markers[0].primary_tag
                    let allSameTag = markers.allSatisfy { $0.primary_tag.id == firstTag.id }
                    
                    if allSameTag {
                        // This is a tag-based search - fetch ALL markers with this tag
                        print("🎲 Tag-based search detected: '\(firstTag.name)'")
                        print("🎲 Fetching ALL '\(firstTag.name)' markers from server...")
                        appModel.startMarkerShuffle(forTag: firstTag.id, tagName: firstTag.name, displayedMarkers: markers)
                    } else {
                        // This is a text search - fetch ALL markers matching the search query
                        print("🎲 Text search detected, using search query: '\(appModel.searchQuery)'")
                        if !appModel.searchQuery.isEmpty {
                            appModel.startMarkerShuffle(forSearchQuery: appModel.searchQuery, displayedMarkers: markers)
                        } else {
                            // Fallback to just shuffling displayed markers
                            print("🎲 No search query available, shuffling displayed markers only")
                            appModel.startMarkerShuffle(withMarkers: markers)
                        }
                    }
                } else {
                    // Fallback to simple shuffle if no markers
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
                        Text("Load ALL matching markers from server")
                            .font(.caption)
                            .opacity(0.9)
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
                print("🎲 Individual marker shuffle in search results for tag ID: \(tagId)")
                let tagName = marker.primary_tag.name
                // Get all markers from the parent view (search results)
                if let parent = appModel.api.markers.first?.primary_tag.name {
                    appModel.startMarkerShuffle(forSearchQuery: appModel.searchQuery, displayedMarkers: appModel.api.markers)
                }
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
        // Tag navigation is handled elsewhere
        if let tag = marker.tags.first(where: { $0.name == tagName }) {
            // This would need to be handled via a different mechanism
            // Since appModel doesn't have a selectedTag property
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