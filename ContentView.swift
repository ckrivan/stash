import SwiftUI
import os.log
import Combine

struct ContentView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var isLoadingContent = false
    @State private var showingConnectionRetry = false
    @State private var showingSettings = false
    
    var body: some View {
        if appModel.isConnected {
            ZStack {
                NavigationStack(path: $appModel.navigationPath) {
                    TabView(selection: $appModel.activeTab) {
                        // Group the views without extra hierarchical layer
                        MediaLibraryView()
                            .tabItem {
                                Label(AppModel.Tab.scenes.rawValue,
                                      systemImage: AppModel.Tab.scenes.icon)
                            }
                            .tag(AppModel.Tab.scenes)

                        
                        
                        PerformersView()
                            .tabItem {
                                Label(AppModel.Tab.performers.rawValue,
                                      systemImage: AppModel.Tab.performers.icon)
                            }
                            .tag(AppModel.Tab.performers)
                        
                        HistoryView()
                            .tabItem {
                                Label(AppModel.Tab.history.rawValue,
                                      systemImage: AppModel.Tab.history.icon)
                            }
                            .tag(AppModel.Tab.history)

                    }
                    // Removed title as requested
                    .sheet(isPresented: $appModel.showingFilterOptions) {
                        NavigationStack {
                            FilterMenuSheet()
                                .environmentObject(appModel)
                                .navigationTitle("Filter Options")
                                .navigationBarTitleDisplayMode(.inline)
                        }
                        .presentationDetents([.medium, .large])
                    }
                    .navigationDestination(for: StashScene.self) { scene in
                        VideoPlayerView(scene: scene)
                            .environmentObject(appModel)
                            .id("scene_\(scene.id)")
                            .onAppear {
                                print("🎬 ContentView: StashScene navigation destination appeared for scene \(scene.id)")
                                
                                // FIXED: Add to watch history when navigating directly to scene
                                if appModel.watchHistory.last?.id != scene.id {
                                    appModel.watchHistory.append(scene)
                                    // Keep history to reasonable size (last 20 scenes)
                                    if appModel.watchHistory.count > 20 {
                                        appModel.watchHistory = Array(appModel.watchHistory.suffix(20))
                                    }
                                    print("🎯 HISTORY - Added to watch history via navigation: \(scene.title ?? "Untitled") (history count: \(appModel.watchHistory.count))")
                                }
                            }
                    }
                    .navigationDestination(for: StashScene.Performer.self) { performer in
                        PerformerDetailView(performer: performer)
                            .environmentObject(appModel)
                    }
                    .navigationDestination(for: StashScene.Tag.self) { tag in
                        TaggedScenesView(tag: tag)
                            .environmentObject(appModel)
                    }
                    .navigationDestination(for: SceneMarker.self) { marker in
                        VideoPlayerView(scene: StashScene(
                            id: marker.scene.id,
                            title: nil,
                            details: nil,
                            paths: StashScene.ScenePaths(
                                screenshot: marker.screenshot,
                                preview: marker.preview,
                                stream: marker.stream
                            ),
                            files: [],
                            performers: [],
                            tags: [],
                            rating100: nil,
                            o_counter: nil
                        ), startTime: Double(marker.seconds))
                        .environmentObject(appModel)
                        .id("marker_\(marker.scene.id)")
                        .onAppear {
                            print("🎬 ContentView: SceneMarker navigation destination appeared for marker \(marker.id) -> scene \(marker.scene.id)")
                            
                            // FIXED: Add marker's scene to watch history when navigating to marker
                            let markerScene = StashScene(
                                id: marker.scene.id,
                                title: marker.title,
                                details: nil,
                                paths: StashScene.ScenePaths(
                                    screenshot: marker.screenshot,
                                    preview: marker.preview,
                                    stream: marker.stream
                                ),
                                files: [],
                                performers: [],
                                tags: [],
                                rating100: nil,
                                o_counter: nil
                            )
                            
                            if appModel.watchHistory.last?.id != markerScene.id {
                                appModel.watchHistory.append(markerScene)
                                // Keep history to reasonable size (last 20 scenes)
                                if appModel.watchHistory.count > 20 {
                                    appModel.watchHistory = Array(appModel.watchHistory.suffix(20))
                                }
                                print("🎯 HISTORY - Added marker scene to watch history: \(marker.title) (history count: \(appModel.watchHistory.count))")
                            }
                        }
                    }
                }
                
                // Settings button overlay - show for iPad only when not in video player
                if UIDevice.current.userInterfaceIdiom == .pad && appModel.navigationPath.isEmpty {
                    VStack {
                        HStack {
                            Spacer()

                            // Filter button (only show for Scenes tab)
                            if appModel.activeTab == .scenes {
                                Button(action: {
                                    appModel.showingFilterOptions = true
                                }) {
                                    Image(systemName: "line.3.horizontal.decrease.circle")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .padding(12)
                                        .background(Circle().fill(Color.purple.opacity(0.8)))
                                        .shadow(radius: 3)
                                }
                                .padding(.horizontal, 4)
                            }

                            // Emergency reset button (only show if app is stuck)
                            if appModel.navigationPath.count > 2 {
                                Button(action: {
                                    appModel.emergencyReset()
                                }) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .padding(12)
                                        .background(Circle().fill(Color.red.opacity(0.8)))
                                        .shadow(radius: 3)
                                }
                                .padding(.horizontal, 4)
                            }
                            
                            // Settings button
                            NavigationLink(destination: SettingsView().environmentObject(appModel)) {
                                Image(systemName: "gear")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Circle().fill(Color.blue.opacity(0.8)))
                                    .shadow(radius: 3)
                            }
                            .padding(.horizontal)
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
            .onAppear {
                print("📱 ContentView appeared")
                ensureContentLoaded()
            }
            .onChange(of: appModel.activeTab) { _, newTab in
                print("📱 Tab changed to: \(newTab)")
                ensureContentLoaded()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowSettings"))) { _ in
                // Show settings as sheet for iOS users
                showingSettings = true
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                        .environmentObject(appModel)
                        .navigationTitle("Settings")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showingSettings = false
                                }
                            }
                        }
                }
            }
        } else {
            VStack(spacing: 20) {
                EnhancedConnectionView()
                    .environmentObject(appModel)
                
                // Only show the retry button if we attempted connection but failed
                if false {
                    VStack(spacing: 15) {
                        Text("Connection to server failed")
                            .font(.headline)
                        
                        if case .failed = appModel.api.connectionStatus {
                            Text("Server error")
                                .foregroundColor(.secondary)
                        } else {
                            Text("Check your server and try again")
                                .foregroundColor(.secondary)
                        }
                        
                        Button("Retry Connection") {
                            Task {
                                do {
                                    try await appModel.api.checkServerConnection()
                                } catch {
                                    print("Connection error: \(error)")
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 10)
                    }
                    .padding(.horizontal)
                    .padding(.top, 30)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}

#Preview("Disconnected") {
    ContentView()
        .environmentObject(AppModel(isConnected: false))
}

// MARK: - Content Loading Logic
extension ContentView {
    func ensureContentLoaded() {
        guard !isLoadingContent, appModel.isConnected else { return }
        
        isLoadingContent = true
        
        Task {
            do {
                switch appModel.activeTab {
                case .scenes:
                    print("📱 Loading scenes for tab")
                    // FIXED: Load "Recently Added" (VR-excluded) as default view
                    // This prevents randomizing when returning from video player
                    if appModel.api.scenes.isEmpty {
                        print("📱 No scenes loaded, loading recently added scenes (excluding VR)")
                        await appModel.api.fetchScenesExcludingVR(page: 1, sort: "created_at", direction: "DESC", appendResults: false)
                    } else {
                        print("📱 Scenes already loaded (\(appModel.api.scenes.count)), preserving order")
                    }
                    
                case .performers:
                    print("📱 Loading performers for tab")
                    appModel.api.fetchPerformers(filter: .twoOrMore, page: 1, appendResults: false, search: "") { result in
                        switch result {
                        case .success(let performers):
                            print("✅ Loaded \(performers.count) performers")
                        case .failure(let error):
                            print("❌ Error loading performers: \(error)")
                        }
                    }
                
                case .history:
                    print("📱 History tab selected - no loading needed")
                    // History is already in appModel.watchHistory, no need to load anything
                }
            } catch {
                print("❌ Error loading content for tab \(appModel.activeTab): \(error)")
            }
            
            await MainActor.run {
                isLoadingContent = false
            }
        }
    }
}
