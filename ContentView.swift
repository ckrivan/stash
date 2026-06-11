import Combine
import SwiftUI
import os.log

struct ContentView: View {
  @EnvironmentObject var appModel: AppModel
  @State private var isLoadingContent = false
  @State private var showingConnectionRetry = false
  @State private var showingSettings = false

  /// Each tab's NavigationStack binds to its own per-tab path.
  private func pathBinding(_ tab: AppModel.Tab) -> Binding<NavigationPath> {
    Binding(
      get: { appModel.navigationPaths[tab] ?? NavigationPath() },
      set: { appModel.navigationPaths[tab] = $0 }
    )
  }

  var body: some View {
    if appModel.isConnected {
      // Native structure: TabView at the root, each tab owns its own
      // NavigationStack (the previous stack-around-tabs inversion stopped the
      // iOS 26 SDK from rendering any nav bar, toolbar, or search field).
      TabView(selection: $appModel.activeTab) {
        Tab(
          AppModel.Tab.scenes.rawValue,
          systemImage: AppModel.Tab.scenes.icon,
          value: AppModel.Tab.scenes
        ) {
          NavigationStack(path: pathBinding(.scenes)) {
            MediaLibraryView()
              .modifier(AppNavigationDestinations())
          }
        }

        Tab(
          AppModel.Tab.performers.rawValue,
          systemImage: AppModel.Tab.performers.icon,
          value: AppModel.Tab.performers
        ) {
          NavigationStack(path: pathBinding(.performers)) {
            PerformersView()
              .modifier(AppNavigationDestinations())
          }
        }

        Tab(
          AppModel.Tab.history.rawValue,
          systemImage: AppModel.Tab.history.icon,
          value: AppModel.Tab.history
        ) {
          NavigationStack(path: pathBinding(.history)) {
            HistoryView()
              .modifier(AppNavigationDestinations())
          }
        }
      }
      // Tab bar recedes on scroll so content takes the stage (iOS 26 idiom).
      .tabBarMinimizeBehavior(.onScrollDown)
      .sheet(isPresented: $appModel.showingFilterOptions) {
        NavigationStack {
          FilterMenuSheet()
            .environmentObject(appModel)
            .navigationTitle("Filter Options")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
      }
      .onAppear {
        print("📱 ContentView appeared")
        ensureContentLoaded()
      }
      // Sim harness (mirrors the visionOS AUTO_* env vars): AUTO_OPEN_SCENE=<id>
      // navigates straight into the player — tap automation on the iPad sim is
      // too flaky for UI verification.
      .task {
        if let sceneID = ProcessInfo.processInfo.environment["AUTO_OPEN_SCENE"],
          !sceneID.isEmpty {
          try? await Task.sleep(for: .seconds(3))
          if let scene = try? await appModel.api.fetchScene(byID: sceneID) {
            print("🤖 auto-pilot: opening scene \(sceneID)")
            appModel.navigateToScene(scene)
          }
        }
      }
      .onChange(of: appModel.activeTab) { oldTab, newTab in
        print("📱 Tab changed from \(oldTab) to: \(newTab)")

        // Clear ALL tab paths on switch: popping every stack to root matches
        // the old single-stack behavior, and a backgrounded tab must never
        // keep a pushed video player alive off-screen.
        if !appModel.navigationPaths.isEmpty {
          print("📱 Clearing navigation paths")
          appModel.navigationPaths = [:]
        }

        ensureContentLoaded()
      }
      .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowSettings"))) {
        _ in
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

/// The app's navigation destinations, shared by every tab's NavigationStack.
struct AppNavigationDestinations: ViewModifier {
  @EnvironmentObject var appModel: AppModel

  func body(content: Content) -> some View {
    content
      .navigationDestination(for: StashScene.self) { scene in
        NativeVideoPlayerView(
          scene: scene,
          startTime: UserDefaults.standard.object(forKey: "scene_\(scene.id)_startTime")
            as? Double,
          endTime: UserDefaults.standard.object(forKey: "scene_\(scene.id)_endTime") as? Double
        )
        .environmentObject(appModel)
        .id("scene_\(scene.id)")
        // The floating tab bar has no place over a playing video.
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
          print(
            "🎬 ContentView: StashScene navigation destination appeared for scene \(scene.id)")
          if !appModel.skipNextHistoryAdd {
            SessionHistoryManager.shared.addEntry(scene: scene)
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
        NativeVideoPlayerView(
          scene: StashScene(
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
          ), startTime: Double(marker.seconds)
        )
        .environmentObject(appModel)
        .id("marker_\(marker.scene.id)")
        // The floating tab bar has no place over a playing video.
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
          print(
            "🎬 ContentView: SceneMarker navigation destination appeared for marker \(marker.id) -> scene \(marker.scene.id)"
          )

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

          SessionHistoryManager.shared.addEntry(
            scene: markerScene,
            startSeconds: Double(marker.seconds),
            markerTitle: marker.title
          )
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
      switch appModel.activeTab {
      case .scenes:
        print("📱 Loading scenes for tab")
        // FIXED: Load "Recently Added" (VR-excluded) as default view
        // This prevents randomizing when returning from video player
        if appModel.api.scenes.isEmpty {
          print("📱 No scenes loaded, loading recently added scenes (excluding VR)")
          await appModel.api.fetchScenesExcludingVR(
            page: 1, sort: "created_at", direction: "DESC", appendResults: false)
        } else {
          print("📱 Scenes already loaded (\(appModel.api.scenes.count)), preserving order")
        }

      case .performers:
        print("📱 Loading performers for tab")
        appModel.api.fetchPerformers(
          filter: .twoOrMore, page: 1, appendResults: false, search: ""
        ) { result in
          switch result {
          case .success(let performers):
            print("✅ Loaded \(performers.count) performers")
          case .failure(let error):
            print("❌ Error loading performers: \(error)")
          }
        }

      case .history:
        print("📱 History tab selected - no loading needed")
      // History is managed by SessionHistoryManager.shared
      }

      await MainActor.run {
        isLoadingContent = false
      }
    }
  }
}
