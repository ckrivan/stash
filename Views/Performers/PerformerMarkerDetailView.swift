import SwiftUI

struct PerformerMarkerDetailView: View {
    let performer: StashScene.Performer
    @EnvironmentObject private var appModel: AppModel
    @State private var currentPage = 1
    @State private var isLoadingMore = false
    @State private var hasMorePages = true
    @State private var selectedTag: StashScene.Tag?
    @State private var markerCount: Int = 0
    
    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)
    ]
    
    // We no longer track visibility externally, handled by MarkerRow itself
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Performer header
                PerformerHeaderView(performer: performer)
                
                // Show marker count and test button
                HStack {
                    Text("\(markerCount) markers")
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Add test marker player button
                    NavigationLink(destination: TestMarkerPlayerView()) {
                        Text("Test Marker Player")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
                
                // Get filtered markers first
                let markersList = appModel.api.markers
                
                // Markers grid
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(markersList) { marker in
                        MarkerRow(
                            marker: marker,
                            serverAddress: appModel.serverAddress,
                            onTitleTap: { marker in
                                // Navigate to marker when title tapped
                                appModel.navigateToMarker(marker)
                            },
                            onTagTap: { tagName in
                                print("🔍 Setting tag filter: \(tagName)")
                                // Handle tag selection if needed
                            }
                        )
                        // Set max width to improve appearance
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            // Check if we need to load more markers
                            if marker == appModel.api.markers.last && !isLoadingMore && hasMorePages {
                                Task {
                                    await loadMoreMarkers()
                                }
                            }
                        }
                    }
                    
                    if isLoadingMore {
                        ProgressView()
                            .gridCellColumns(columns.count)
                            .padding()
                    }
                }
                .padding()
            }
        }
        .navigationTitle(performer.name)
        .task {
            // Load marker count
            markerCount = await getMarkerCount()
            // Load initial markers
            await loadInitialMarkers()
        }
        .sheet(item: $selectedTag) { tag in
            NavigationStack {
                TaggedScenesView(tag: tag)
            }
        }
    }
    
    private func getMarkerCount() async -> Int {
        let query = """
        {"operationName":"FindSceneMarkers","variables":{"filter":{"q":"","page":1,"per_page":1,"sort":"title","direction":"ASC"},"scene_marker_filter":{"performers":{"value":["\(performer.id)"],"modifier":"INCLUDES"}}},"query":"query FindSceneMarkers($filter: FindFilterType, $scene_marker_filter: SceneMarkerFilterType) {\\n  findSceneMarkers(filter: $filter, scene_marker_filter: $scene_marker_filter) {\\n    count\\n    __typename\\n  }\\n}"}
        """
        
        guard let url = URL(string: "\(appModel.serverAddress)/graphql") else { return 0 }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(appModel.serverAddress, forHTTPHeaderField: "Origin")
        request.setValue("nc_sameSiteCookielax=true; nc_sameSiteCookiestrict=true", forHTTPHeaderField: "Cookie")
        request.httpBody = query.data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
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
            return response.data.findSceneMarkers.count
        } catch {
            print("❌ Error fetching marker count: \(error)")
            return 0
        }
    }
    
    private func loadInitialMarkers() async {
        currentPage = 1
        hasMorePages = true
        isLoadingMore = false
        await appModel.api.fetchPerformerMarkers(performerId: performer.id, page: currentPage, appendResults: false)
    }
    
    private func loadMoreMarkers() async {
        guard !isLoadingMore else { return }

        isLoadingMore = true
        currentPage += 1

        let previousCount = appModel.api.markers.count
        await appModel.api.fetchPerformerMarkers(performerId: performer.id, page: currentPage, appendResults: true)

        hasMorePages = appModel.api.markers.count > previousCount
        isLoadingMore = false
    }
} 