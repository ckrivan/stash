import SwiftUI
import AVKit

struct MarkerView: View {
    @EnvironmentObject var appModel: AppModel
    @StateObject private var viewModel = MarkerViewModel()
    
    // Optional parameters for filtered views
    var scene: StashScene?
    var performer: StashScene.Performer?
    
    // UI Configuration
    @State private var columnCount = 2
    @State private var filterMenuPresented = false
    @State private var sortOption: MarkerSortOption = .createdAtDesc
    @State private var selectedTagId: String? = nil
    
    // Dynamic grid column calculation
    private func gridItems(for width: CGFloat) -> [GridItem] {
        // Base on available width
        let baseWidth: CGFloat = 300
        let calculatedCount = max(1, Int(width / baseWidth))
        let columns = Array(repeating: GridItem(.flexible()), count: calculatedCount)
        return columns
    }
    
    private func getNavigationTitle() -> String {
        if let scene = scene {
            return "Markers: \(scene.title)"
        } else if let performer = performer {
            return "\(performer.name)'s Markers"
        } else {
            return "All Markers"
        }
    }
    
    // Loading view for initial load
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.5)
            
            Text("Loading markers...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .slideIn(from: .bottom)
    }
    
    // Empty state view
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "film")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
                .padding()
            
            if let scene = scene {
                Text("No markers for \(scene.title)")
                    .font(.headline)
            } else if let performer = performer {
                Text("No markers for \(performer.name)")
                    .font(.headline)
            } else {
                Text("No markers found")
                    .font(.headline)
            }
            
            Text("Try changing your filters or adding new markers")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if let error = viewModel.error {
                Text("Error: \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .slideIn(from: .bottom)
    }
    
    // Main content view with markers
    private var markersContentView: some View {
        GeometryReader { geo in
            let columns = gridItems(for: geo.size.width)
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(viewModel.filteredMarkers) { marker in
                        MarkerRow(
                            marker: marker, 
                            serverAddress: appModel.serverAddress,
                            onTitleTap: { marker in
                                print("🎬 MarkerView: Handling marker title tap via onTitleTap")
                                // Directly navigate from parent component
                                appModel.navigateToMarker(marker)
                            },
                            onTagTap: { tagName in
                                // Find the tag by name
                                if let tag = viewModel.availableTags.first(where: { $0.name == tagName }) {
                                    selectedTagId = tag.id
                                    viewModel.filterMarkersByTag(tagId: tag.id)
                                }
                            },
                            onPerformerTap: { performer in
                                // Navigate to performer when tapped
                                print("👤 MarkerView: Navigating to performer: \(performer.name)")
                                appModel.navigateToPerformer(performer)
                            },
                            onShuffleTap: { tagId in
                                // Shuffle markers with this tag
                                print("🎲 DIRECT SHUFFLE: With tag ID: \(tagId)")
                                
                                // First ensure we have markers
                                if viewModel.filteredMarkers.isEmpty {
                                    print("⚠️ No filtered markers to shuffle")
                                    return
                                }
                                
                                // Get a random marker from filtered set
                                guard let randomMarker = viewModel.filteredMarkers.randomElement() else {
                                    print("⚠️ Could not get random marker")
                                    return
                                }
                                
                                // Perform direct navigation to the random marker
                                print("🎲 Shuffling directly to: \(randomMarker.title) (ID: \(randomMarker.id))")
                                appModel.navigateToMarker(randomMarker)
                            }
                        )
                        .slideIn(from: .bottom, delay: 0.05 * Double(viewModel.filteredMarkers.firstIndex(of: marker) ?? 0), duration: 0.25)
                        .onAppear {
                            // Load more if needed
                            if marker.id == viewModel.filteredMarkers.last?.id && !viewModel.isLoadingMore && viewModel.hasMorePages {
                                Task {
                                    await viewModel.loadMoreMarkers()
                                }
                            }
                        }
                    }
                    
                    if viewModel.isLoadingMore {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding()
                            .gridCellColumns(columns.count)
                    }
                }
                .padding()
            }
        }
    }
    
    // Sorting and filtering menu
    private var sortFilterMenu: some View {
        Menu {
            Section("Sort by") {
                ForEach(MarkerSortOption.allCases) { option in
                    Button(option.label) {
                        viewModel.sortMarkers(by: option)
                        sortOption = option
                    }
                    .foregroundColor(sortOption == option ? .accentColor : .primary)
                }
            }
            
            if !viewModel.availableTags.isEmpty {
                Section("Filter by tag") {
                    Button("All Tags") {
                        selectedTagId = nil
                        viewModel.resetTagFilter()
                    }
                    .foregroundColor(selectedTagId == nil ? .accentColor : .primary)
                    
                    ForEach(viewModel.availableTags) { tag in
                        Button(tag.name) {
                            selectedTagId = tag.id
                            viewModel.filterMarkersByTag(tagId: tag.id)
                        }
                        .foregroundColor(selectedTagId == tag.id ? .accentColor : .primary)
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 16, weight: .semibold))
                Text("Sort & Filter")
            }
        }
    }
    
    var body: some View {
        ZStack {
            if viewModel.isLoading && viewModel.markers.isEmpty {
                loadingView
            } else if viewModel.markers.isEmpty {
                emptyStateView
            } else {
                markersContentView
            }
        }
        .navigationTitle(getNavigationTitle())
        .overlay {
            // Overlay loading indicator for subsequent loads
            if viewModel.isLoading && !viewModel.markers.isEmpty {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                    .frame(width: 60, height: 60)
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                sortFilterMenu
            }
        }
        .task {
            // Load markers when the view appears
            if let scene = scene {
                await viewModel.loadMarkers(for: scene, api: appModel.api)
            } else if let performer = performer {
                await viewModel.loadMarkers(for: performer, api: appModel.api)
            } else {
                await viewModel.loadAllMarkers(api: appModel.api)
            }
        }
    }
}

// MARK: - Using shared animation modifiers
// These are now defined in AnimationModifiers.swift

// MARK: - Marker Shuffle Functionality
extension MarkerView {
    /// Shuffles to a random marker within the current filtered set or all markers
    func shuffleRandomMarker() {
        // Show haptic feedback to indicate action
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // If we have filtered markers, shuffle within those
        if !viewModel.filteredMarkers.isEmpty {
            shuffleWithinFilteredMarkers()
        } else {
            // Otherwise, fetch a completely random marker
            fetchRandomMarker()
        }
    }
    
    /// Shuffle within the currently filtered set of markers
    private func shuffleWithinFilteredMarkers() {
        guard let randomMarker = viewModel.filteredMarkers.randomElement() else {
            print("⚠️ No markers available to shuffle to")
            return
        }
        
        print("🎲 Shuffling to random marker: \(randomMarker.title) (ID: \(randomMarker.id))")
        appModel.navigateToMarker(randomMarker)
    }
    
    /// Fetch a completely random marker using the API
    private func fetchRandomMarker() {
        // Show a loading indicator
        viewModel.isLoading = true
        
        Task {
            do {
                // Build a GraphQL query to find random markers
                let query = """
                {
                    "operationName": "FindSceneMarkers",
                    "variables": {
                        "filter": {
                            "page": 1,
                            "per_page": 40,
                            "sort": "random",
                            "direction": "ASC"
                        }
                    },
                    "query": "query FindSceneMarkers($filter: FindFilterType) { findSceneMarkers(filter: $filter) { count markers { id title seconds stream scene { id name date created_at title studio { id name } performers { id name } files { height width duration } galleries { id } } preview tags { id name } primary_tag { id name } screenshot } } }"
                }
                """
                
                let data = try await appModel.api.executeGraphQLQuery(query)
                
                // Define struct for parsing the response
                struct MarkersResponseData: Decodable {
                    let data: MarkerData
                    
                    struct MarkerData: Decodable {
                        let findSceneMarkers: MarkersPayload
                        
                        struct MarkersPayload: Decodable {
                            let count: Int
                            let markers: [SceneMarker]
                        }
                    }
                }
                
                // Parse the response
                let response = try JSONDecoder().decode(MarkersResponseData.self, from: data)
                let randomMarkers = response.data.findSceneMarkers.markers
                
                await MainActor.run {
                    // Hide loading indicator
                    viewModel.isLoading = false
                    
                    // Navigate to the first random marker if available
                    if let randomMarker = randomMarkers.first {
                        print("🎲 Navigating to random marker: \(randomMarker.title)")
                        appModel.navigateToMarker(randomMarker)
                    } else {
                        print("⚠️ No random markers found")
                    }
                }
            } catch {
                await MainActor.run {
                    // Hide loading indicator and show error
                    viewModel.isLoading = false
                    viewModel.error = "Failed to load random marker: \(error.localizedDescription)"
                    print("❌ Error fetching random marker: \(error)")
                }
            }
        }
    }
}

// MARK: - Preview
struct MarkerView_Previews: PreviewProvider {
    static var previews: some View {
        MarkerView()
            .environmentObject(AppModel())
    }
}