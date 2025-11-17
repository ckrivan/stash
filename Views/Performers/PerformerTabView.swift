import AVKit
import SwiftUI

struct PerformerTabView: View {
  let performer: StashScene.Performer
  @EnvironmentObject private var appModel: AppModel
  @State private var selectedTab = 0  // 0 for scenes, 1 for markers
  @State private var markerCount: Int = 0
  @State private var isLoadingMore = false
  @State private var hasMorePages = true
  @State private var currentPage = 1
  @State private var selectedTag: StashScene.Tag?
  @State private var viewRefreshTrigger = UUID()  // Add refresh trigger
  @State private var markerPreviewPlayers: [String: VideoPlayerViewModel] = [:]
  @State private var markerPreviewStates: [String: Bool] = [:]
  @State private var markerMuteStates: [String: Bool] = [:]

  // MARK: - Shuffle Function

  private func shuffleAndPlayScene() {
    print(
      "🎲 Gender-aware shuffle for performer: \(performer.name) (gender: \(performer.gender ?? "unknown"))"
    )

    // Ensure we have scenes loaded
    guard !appModel.api.scenes.isEmpty else {
      print("⚠️ No scenes available to shuffle")
      return
    }

    // Set performer context for gender-aware filtering
    appModel.currentPerformer = performer
    appModel.performerDetailViewPerformer = performer
    print("🎯 Set performer context: \(performer.name) (gender: \(performer.gender ?? "unknown"))")

    // Use the new gender-aware shuffle method
    appModel.shufflePerformerScenes(fromScenes: appModel.api.scenes, currentPerformer: performer)
  }

  // MARK: - Response Types
  struct DirectFindScenesResponse: Decodable {
    struct Data: Decodable {
      struct FindScenes: Decodable {
        let count: Int
        let scenes: [StashScene]
      }
      let findScenes: FindScenes
    }
    let data: Data
    let errors: [GraphQLError]?
  }

  private let columns = [
    GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)
  ]

  init(performer: StashScene.Performer) {
    self.performer = performer
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        // Performer header
        PerformerHeaderView(performer: performer)

        // Tab picker - use stronger typing and perform change immediately
        Picker(
          "View",
          selection: Binding(
            get: { self.selectedTab },
            set: { newValue in
              // Only process if actually changing tabs
              if self.selectedTab != newValue {
                self.selectedTab = newValue
                print("💫 Tab changed to: \(newValue)")

                // Perform content loading immediately when tab changes
                Task {
                  // Reset pagination when switching tabs
                  currentPage = 1
                  hasMorePages = true
                  isLoadingMore = false

                  // Set loading state
                  await MainActor.run {
                    appModel.api.isLoading = true

                    // Clear existing content for both tabs to avoid memory issues
                    if newValue == 0 {
                      appModel.api.scenes = []
                    } else {
                      appModel.api.markers = []
                    }

                    // Force trigger UI refresh
                    viewRefreshTrigger = UUID()
                    print("♻️ UI refresh triggered for tab change to \(newValue)")
                  }

                  // Load the appropriate content
                  if newValue == 0 {
                    print("💫 Loading scenes for tab change")
                    await loadScenes()
                  } else {
                    print("💫 Loading markers for tab change")
                    await loadMarkers()
                  }
                }
              }
            }
          )
        ) {
          Text("Scenes").tag(0)
          Text("Markers").tag(1)
        }
        .pickerStyle(.segmented)
        .padding()

        // Content based on selected tab
        if selectedTab == 0 {
          scenesContent
        } else {
          markersContent
        }
      }
    }
    .navigationTitle("")
    .id(viewRefreshTrigger)  // Force entire view to refresh
    .task {
      // Only run once when the view appears
      print(
        "🚀 TASK: PerformerTabView appeared, selectedTab: \(selectedTab), performer: \(performer.name) (ID: \(performer.id))"
      )

      // Avoid any existing tasks with a unique ID
      let taskID = UUID()
      let currentTaskID = taskID

      // Clear any previous content immediately to avoid stale data
      await MainActor.run {
        print("🚀 Clearing existing data and showing loading state")
        appModel.api.isLoading = true

        // Only clear content for the current tab
        if selectedTab == 0 {
          appModel.api.scenes = []
        } else {
          appModel.api.markers = []
        }

        // Reset pagination state
        currentPage = 1
        hasMorePages = true
        isLoadingMore = false
      }

      // Small delay to ensure UI update
      try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds

      // Make sure we haven't been cancelled or replaced
      if Task.isCancelled {
        print("⚠️ Task was cancelled before loading content")
        return
      }

      // Load content for the selected tab
      if selectedTab == 0 {
        print("🚀 TASK: Loading scenes for \(performer.name)")

        // Force delay to ensure loading state is shown
        await loadScenes()

        // Verify scenes were loaded
        print("🚀 POST-LOAD: Final scenes count is \(appModel.api.scenes.count)")
        if appModel.api.scenes.isEmpty {
          print("⚠️ WARNING: No scenes were loaded for performer \(performer.name)")
        } else {
          print("✅ Successfully loaded scenes for \(performer.name)")
          if let firstScene = appModel.api.scenes.first {
            print("🚀 First scene: \(firstScene.title ?? "No title") (ID: \(firstScene.id))")
          }
        }
      } else {
        print("🚀 TASK: Loading markers for \(performer.name)")
        await loadMarkers()
      }

      // Get marker count regardless of tab
      markerCount = await getMarkerCount()
    }
    // Removed onChange handler since we're handling tab changes directly in the Picker's binding
    .sheet(item: $selectedTag) { tag in
      NavigationStack {
        TaggedScenesView(tag: tag)
      }
    }
  }

  @ViewBuilder
  private var scenesContent: some View {
    Color.clear.frame(height: 0)
      .onAppear {
        print("📱 SCENES CONTENT APPEARING")
        print("📱 Current scenes count: \(appModel.api.scenes.count)")
        print("📱 isLoading: \(appModel.api.isLoading)")

        // Only log data, don't trigger reloads
        if !appModel.api.scenes.isEmpty {
          print("📱 First scene ID: \(appModel.api.scenes[0].id)")
          print("📱 First scene title: \(appModel.api.scenes[0].title ?? "No title")")
        }
      }

    if appModel.api.isLoading {
      loadingStateView
    } else if appModel.api.scenes.isEmpty {
      emptyStateView
    } else {
      scenesGridView
    }
  }

  private var loadingStateView: some View {
    VStack(spacing: 16) {
      ProgressView()
        .scaleEffect(1.5)
        .padding()

      Text("Loading scenes for \(performer.name)...")
        .foregroundColor(.secondary)
    }
    .padding(.vertical, 60)
    .frame(maxWidth: .infinity)
  }

  private var emptyStateView: some View {
    VStack(spacing: 16) {
      Image(systemName: "film.stack")
        .font(.system(size: 50))
        .foregroundColor(.secondary)
        .padding()

      Text("No scenes found for \(performer.name)")
        .font(.headline)
        .foregroundColor(.secondary)

      Button("Reload") {
        Task {
          currentPage = 1
          await loadScenes()
          // Trigger refresh after manual reload
          await MainActor.run {
            viewRefreshTrigger = UUID()
          }
        }
      }
      .buttonStyle(.borderedProminent)
      .padding(.top, 8)
    }
    .padding(.vertical, 60)
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private var scenesGridView: some View {
    // Content found - display scene count with shuffle button
    HStack {
          Text("Found \(appModel.api.scenes.count) scenes")
            .font(.headline)
            .foregroundColor(.primary)

          Spacer()

          Button(action: shuffleAndPlayScene) {
            HStack(spacing: 4) {
              Image(systemName: "shuffle")
              Text("Shuffle")
            }
            .font(.system(size: 14, weight: .medium))
          }
          .buttonStyle(.bordered)
          .tint(.accentColor)
        }
        .padding(.horizontal)
        .padding(.top, 8)

        // Scene grid
        LazyVGrid(columns: columns, spacing: 16) {
          ForEach(appModel.api.scenes) { scene in
            // Wrap SceneRow in a container with consistent styling
            SceneRow(
              scene: scene,
              onTagSelected: { selectedTag = $0 },
              onPerformerSelected: { _ in },  // Ignore performer selection in performer view
              onSceneUpdated: { _ in },
              onSceneSelected: { selectedScene in
                if let stream = selectedScene.paths.stream,
                   let url = URL(string: stream) {
                  if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                    let window = windowScene.windows.first,
                    let rootViewController = window.rootViewController {
                    let controller = VideoPlayerUtility.createPlayerViewController(
                      url: url,
                      startTime: UserDefaults.standard.getVideoProgress(for: selectedScene.id),
                      scenes: appModel.api.scenes,
                      currentIndex: appModel.api.scenes.firstIndex(of: selectedScene) ?? 0,
                      appModel: appModel
                    )
                    rootViewController.present(controller, animated: true)
                  }
                }
              },
              preservePerformerContext: true
            )
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .shadow(radius: 2)
            .overlay(
              RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
            )
            .onTapGesture {
              if let stream = scene.paths.stream,
                 let url = URL(string: stream) {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let rootViewController = window.rootViewController {
                  let controller = VideoPlayerUtility.createPlayerViewController(
                    url: url,
                    startTime: UserDefaults.standard.getVideoProgress(for: scene.id),
                    scenes: appModel.api.scenes,
                    currentIndex: appModel.api.scenes.firstIndex(of: scene) ?? 0,
                    appModel: appModel
                  )
                  rootViewController.present(controller, animated: true)
                }
              }
            }
            .onAppear {
              if scene == appModel.api.scenes.last && !isLoadingMore && hasMorePages {
                Task {
                  await loadMoreScenes()
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
        .id(viewRefreshTrigger)  // Force LazyVGrid to refresh when scenes change
  }

  private var markersContent: some View {
    VStack(spacing: 0) {
      // Debug trigger that doesn't reload data
      Color.clear
        .frame(width: 0, height: 0)
        .onAppear {
          print("💡 MARKERS TAB - Tab content appeared")

          // Do NOT reload markers here - this is causing an infinite loop!
          // The markers are already loaded when the tab is selected
        }

      // Status view for loading/empty state
      if appModel.api.markers.isEmpty {
        if appModel.api.isLoading {
          VStack(spacing: 16) {
            ProgressView()
              .scaleEffect(1.5)
              .padding()

            Text("Loading markers for \(performer.name)...")
              .foregroundColor(.secondary)
          }
          .padding(.vertical, 60)
          .frame(maxWidth: .infinity)
        } else {
          VStack(spacing: 16) {
            Image(systemName: "bookmark.slash")
              .font(.system(size: 50))
              .foregroundColor(.secondary)
              .padding()

            Text("No markers found for \(performer.name)")
              .font(.headline)
              .foregroundColor(.secondary)

            Button("Reload") {
              Task {
                currentPage = 1
                await loadMarkers()
              }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
          }
          .padding(.vertical, 60)
          .frame(maxWidth: .infinity)
        }
      } else {
        // VStack containing grid to allow onAppear modifier
        VStack {
          // Color.clear for debug info only - DO NOT trigger reloads
          Color.clear
            .frame(height: 0)
            .onAppear {
              // Debug info only - no loading!
              let allMarkers = appModel.api.markers
              print("🌟 MARKERS GRID - Showing \(allMarkers.count) markers")
            }

          // Grid with same styling as scenes tab
          LazyVGrid(columns: columns, spacing: 16) {
            ForEach(appModel.api.markers) { marker in
              // Custom marker row with video preview
              VStack(alignment: .leading) {
                // Thumbnail with preview video functionality
                GeometryReader { geometry in
                  ZStack {
                    // Base thumbnail image with caching
                    CachedAsyncImage(url: URL(string: marker.screenshot), width: 500) { image in
                      image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    } placeholder: {
                      Rectangle()
                        .fill(Color.gray.opacity(0.2))
                    }

                    // Video preview layer
                    if let previewPlayer = markerPreviewPlayers[marker.id], markerPreviewStates[marker.id, default: false] {
                      VideoPlayer(player: previewPlayer.player)
                        .onAppear {
                          previewPlayer.player.isMuted = markerMuteStates[marker.id, default: true]
                        }
                    }

                    // Timestamp and mute overlay
                    HStack {
                      Text(formatDuration(marker.seconds))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .cornerRadius(4)

                      Spacer()

                      // Mute button - only show when preview is playing
                      if markerPreviewStates[marker.id, default: false] {
                        Button(action: {
                          toggleMute(for: marker)
                        }) {
                          Image(
                            systemName: markerMuteStates[marker.id, default: true]
                              ? "speaker.slash.fill" : "speaker.wave.2.fill"
                          )
                          .foregroundColor(.white)
                          .padding(8)
                          .background(.ultraThinMaterial)
                          .clipShape(Circle())
                        }
                      }

                      // Play button
                      Button {
                        // Set the HLS preference before navigating
                        setHLSPreference(for: marker)
                        appModel.navigateToMarker(marker)
                      } label: {
                        ZStack {
                          // Background circle - BRIGHT PURPLE
                          Circle()
                            .fill(Color.purple)
                            .frame(width: 60, height: 60)
                            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)

                          // Icon - LARGER
                          Image(systemName: "play.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)

                          // Animated outer border
                          Circle()
                            .strokeBorder(Color.white, lineWidth: 3)
                            .frame(width: 60, height: 60)
                        }
                        .scaleEffect(1.1)
                      }
                      .padding(12)
                    }
                    .padding(8)
                  }
                  .onTapGesture(count: 2) {
                    // Double-tap to navigate directly
                    setHLSPreference(for: marker)
                    appModel.navigateToMarker(marker)
                  }
                  .onTapGesture {
                    // Single tap toggles preview - explicitly control preview state
                    togglePreview(for: marker, in: geometry)
                  }
                  .onChange(of: geometry.frame(in: .global).minY) { _, _ in
                    let frame = geometry.frame(in: .global)
                    let isNowVisible = frame.minY > 0 && frame.maxY < UIScreen.main.bounds.height
                    if isNowVisible && markerPreviewStates[marker.id, default: false] == false {
                      markerPreviewStates[marker.id] = true
                      startPreview(for: marker)
                    } else if !isNowVisible && markerPreviewStates[marker.id, default: false] == true {
                      stopPreview(for: marker)
                    }
                  }
                  .onAppear {
                    let frame = geometry.frame(in: .global)
                    let isNowVisible = frame.minY > 0 && frame.maxY < UIScreen.main.bounds.height
                    if isNowVisible && markerPreviewStates[marker.id, default: false] == false {
                      // initialize player if needed and start muted preview automatically
                      markerPreviewStates[marker.id] = true
                      startPreview(for: marker)
                    }
                  }
                  .onDisappear {
                    if markerPreviewStates[marker.id, default: false] {
                      stopPreview(for: marker)
                    }
                  }
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Info section
                VStack(alignment: .leading, spacing: 8) {
                  // Title
                  Text(marker.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(.purple)
                    .underline()

                  // Tags
                  ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                      Text(marker.primary_tag.name)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.2))
                        .cornerRadius(12)

                      ForEach(marker.tags) { tag in
                        Text(tag.name)
                          .font(.caption)
                          .padding(.horizontal, 8)
                          .padding(.vertical, 4)
                          .background(Color.secondary.opacity(0.15))
                          .cornerRadius(12)
                      }
                    }
                  }

                  // Scene info
                  Text("From: \(marker.scene.title ?? "Unknown Scene")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(12)
              }
              .background(Color(UIColor.secondarySystemBackground))
              .cornerRadius(12)
              .shadow(radius: 2)
              .overlay(
                RoundedRectangle(cornerRadius: 12)
                  .stroke(Color.purple, lineWidth: 1)
              )
              .scaleEffect(markerPreviewStates[marker.id, default: false] ? 1.0 : 0.98)
              .animation(
                .spring(response: 0.3, dampingFraction: 0.7),
                value: markerPreviewStates[marker.id, default: false]
              )
              .onTapGesture {
                // Set the HLS preference before navigating
                setHLSPreference(for: marker)
                appModel.navigateToMarker(marker)
              }
              .contextMenu {
                Button(action: {
                  // Set the HLS preference before navigating
                  setHLSPreference(for: marker)
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
              .onAppear {
                // Trigger pagination when nearing the end of the list
                if marker.id == appModel.api.markers.last?.id,
                  !isLoadingMore && hasMorePages {
                  print("🔄 Last marker appeared - loading more markers")
                  Task {
                    await loadMoreMarkers()
                  }
                }
              }
            }

            // Loading indicator for pagination
            if isLoadingMore {
              ProgressView()
                .scaleEffect(1.2)
                .gridCellColumns(columns.count)
                .padding(.vertical, 30)
            }
          }
          .padding(.horizontal, 16)
          .padding(.top, 16)

          // Footer with stats
          if !appModel.api.markers.isEmpty {
            HStack {
              Spacer()
              Text("\(appModel.api.markers.count) markers loaded")
                .font(.caption)
                .foregroundColor(.secondary)
              Spacer()
            }
            .padding(.vertical, 8)
          }
        }  // End of VStack
      }
    }
    .animation(.easeInOut(duration: 0.3), value: appModel.api.markers.count)
    .animation(.easeInOut(duration: 0.3), value: isLoadingMore)
    .animation(.easeInOut(duration: 0.3), value: appModel.api.isLoading)
  }

  private func loadScenes() async {
    print("🎭 Loading scenes for performer: \(performer.name) with ID: \(performer.id)")

    // Verify we have a valid performer ID before fetching
    guard !performer.id.isEmpty else {
      print("⚠️ ERROR: Empty performer ID, cannot fetch scenes!")
      return
    }

    // Set loading state
    await MainActor.run {
      appModel.api.isLoading = true
      appModel.api.scenes = []  // Force clear scenes first
    }

    do {
      // Force reconnection to ensure auth is current
      print("🔐 PERFORMER: Forcing server connection check")
      try? await appModel.api.checkServerConnection()

      print("📝 PERFORMER: Using direct query approach with performer filter")

      // Create a query using proper format with correct performer filtering
      let query = """
        {
            "operationName": "FindScenes",
            "variables": {
                "filter": {
                    "page": \(currentPage),
                    "per_page": 40,
                    "sort": "date",
                    "direction": "DESC"
                },
                "scene_filter": {
                    "performers": {
                        "value": ["\(performer.id)"],
                        "modifier": "INCLUDES"
                    }
                }
            },
            "query": "query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) { findScenes(filter: $filter, scene_filter: $scene_filter) { count scenes { id title details paths { screenshot preview stream } files { size duration video_codec width height } performers { id name gender scene_count } tags { id name } rating100 o_counter} } }"
        }
        """

      print("🎭 Executing GraphQL query for performer scenes")
      let data = try await appModel.api.executeGraphQLQuery(query)

      let directResponse = try JSONDecoder().decode(DirectFindScenesResponse.self, from: data)

      if let errors = directResponse.errors, !errors.isEmpty {
        let errorMessages = errors.map { $0.message }.joined(separator: ", ")
        print("🎭 GraphQL errors in query: \(errorMessages)")
        throw StashAPIError.graphQLError(errorMessages)
      } else {
        print("🎭 Query successful!")
        let sceneCount = directResponse.data.findScenes.scenes.count
        let totalCount = directResponse.data.findScenes.count
        print("🎭 Found \(sceneCount) scenes")
        print("🎭 Total count: \(totalCount)")

        // Debug first few scenes to verify content
        if !directResponse.data.findScenes.scenes.isEmpty {
          for (index, scene) in directResponse.data.findScenes.scenes.prefix(3).enumerated() {
            print("🎭 Scene \(index): \(scene.title ?? "No title") (ID: \(scene.id))")
            print("🎭 Has \(scene.performers.count) performers")

            // Verify this scene actually contains our performer
            let containsPerformer = scene.performers.contains { $0.id == performer.id }
            print("🎭 Contains target performer: \(containsPerformer)")
          }
        }

        // CRITICAL: Force UI update on main thread
        await MainActor.run {
          print("🔄 Main thread update: Setting \(sceneCount) scenes directly")
          appModel.api.scenes = directResponse.data.findScenes.scenes
          appModel.api.totalSceneCount = totalCount
          appModel.api.isLoading = false

          // Force view refresh
          viewRefreshTrigger = UUID()
          print("♻️ UI refresh triggered with new UUID")

          // Verify data was set
          print("✅ Updated scenes array, now count: \(appModel.api.scenes.count)")
        }
      }
    } catch {
      print("❌ Scene query failed: \(error.localizedDescription)")

      // Use a simpler direct fetching approach as fallback
      print("🔄 FALLBACK: Using direct API fetch for performer \(performer.id)")

      do {
        let backupQuery = """
          {
              "operationName": "FindScenes",
              "variables": {
                  "filter": {
                      "page": 1,
                      "per_page": 100
                  },
                  "scene_filter": {
                      "performers": {
                          "value": ["\(performer.id)"],
                          "modifier": "INCLUDES"
                      }
                  }
              },
              "query": "query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) { findScenes(filter: $filter, scene_filter: $scene_filter) { count scenes { id title details paths { screenshot preview stream } files { size duration video_codec width height } performers { id name } tags { id name } rating100 o_counter } } }"
          }
          """

        print("🔄 Executing backup query")
        let backupData = try await appModel.api.executeGraphQLQuery(backupQuery)
        let backupResponse = try JSONDecoder().decode(
          DirectFindScenesResponse.self, from: backupData)

        await MainActor.run {
          print(
            "🔄 FALLBACK: Setting \(backupResponse.data.findScenes.scenes.count) scenes from backup")
          appModel.api.scenes = backupResponse.data.findScenes.scenes
          appModel.api.totalSceneCount = backupResponse.data.findScenes.count
          appModel.api.isLoading = false

          // Force view refresh
          viewRefreshTrigger = UUID()
          print("♻️ UI refresh triggered with new UUID (fallback path)")
        }
      } catch {
        print("❌ CRITICAL: Both query approaches failed: \(error.localizedDescription)")
        await MainActor.run {
          appModel.api.isLoading = false
        }
      }
    }
  }

  private func loadMoreScenes() async {
    guard !isLoadingMore else { return }

    isLoadingMore = true
    currentPage += 1

    let previousCount = appModel.api.scenes.count
    await loadScenes()

    hasMorePages = appModel.api.scenes.count > previousCount
    isLoadingMore = false
  }

  private func loadMarkers() async {
    print("🔍🔍🔍 PERFORMER: Loading markers for \(performer.name) (ID: \(performer.id))")

    // Set loading state
    await MainActor.run {
      appModel.api.isLoading = true
      appModel.api.markers = []  // Clear markers immediately
    }

    do {
      // Force reconnection to ensure auth is current - seems to be causing 401 errors
      print("🔐 PERFORMER: Forcing server connection check")
      try? await appModel.api.checkServerConnection()

      // Using the same approach as in the VisionPro version
      print("📝 PERFORMER: Using direct query approach with performer filter")

      // Generate a random seed for consistent random sorting
      let randomSeed = Int.random(in: 0...999999)

      let query = """
        {
            "operationName": "FindSceneMarkers",
            "variables": {
                "filter": {
                    "page": 1,
                    "per_page": 200,
                    "sort": "random_\(randomSeed)",
                    "direction": "ASC"
                },
                "scene_marker_filter": {
                    "performers": {
                        "value": ["\(performer.id)"],
                        "modifier": "INCLUDES_ALL"
                    }
                }
            },
            "query": "query FindSceneMarkers($filter: FindFilterType, $scene_marker_filter: SceneMarkerFilterType) { findSceneMarkers(filter: $filter, scene_marker_filter: $scene_marker_filter) { count scene_markers { id title seconds stream preview screenshot scene { id title performers { id name image_path } } primary_tag { id name } tags { id name } } } }"
        }
        """

      print("📝 PERFORMER: Executing GraphQL query")
      let data = try await appModel.api.executeGraphQLQuery(query)

      print("📝 PERFORMER: Got response data, parsing...")

      // Parse the response
      struct MarkersResponseData: Decodable {
        let data: MarkerData

        struct MarkerData: Decodable {
          let findSceneMarkers: MarkersPayload

          struct MarkersPayload: Decodable {
            let count: Int
            let scene_markers: [SceneMarker]
          }
        }
      }

      let response = try JSONDecoder().decode(MarkersResponseData.self, from: data)
      let markers = response.data.findSceneMarkers.scene_markers

      print(
        "✅ PERFORMER: Successfully loaded \(markers.count) markers for performer \(performer.name)")

      await MainActor.run {
        // Set the markers directly since we're already filtering by performer in the query
        appModel.api.markers = markers

        // Force view refresh
        viewRefreshTrigger = UUID()
        print("♻️ UI refresh triggered with new UUID (markers)")

        // Verify a few markers to ensure the filter worked correctly
        if !appModel.api.markers.isEmpty {
          print("🔎 PERFORMER: Validating first few markers...")

          for (index, marker) in appModel.api.markers.prefix(5).enumerated() {
            print("  [\(index)] Marker: \(marker.title)")

            if let performers = marker.scene.performers {
              var performerNames = performers.map { $0.name }
              print("    Has performers: \(performerNames.joined(separator: ", "))")
            }
          }
        }

        print("✅ PERFORMER: Marker loading complete, displaying \(markers.count) markers")

        hasMorePages = false  // Disable pagination with this direct filtering approach
        appModel.api.isLoading = false
        isLoadingMore = false
      }
    } catch {
      print("❌ PERFORMER ERROR: Failed to load markers: \(error.localizedDescription)")
      await MainActor.run {
        hasMorePages = false
        appModel.api.isLoading = false
        isLoadingMore = false
        appModel.api.error = error
      }
    }
  }

  private func loadMoreMarkers() async {
    guard !isLoadingMore, hasMorePages else {
      print(
        "⚠️ Skipping loadMoreMarkers - isLoadingMore: \(isLoadingMore), hasMorePages: \(hasMorePages)"
      )
      return
    }

    print("🔄 Loading more markers is disabled with the local filtering approach")
    // With our local filtering approach, we don't need pagination since we load and filter
    // all markers at once. This function is kept for API compatibility but doesn't do anything.
  }

  private func getMarkerCount() async -> Int {
    print("📊 Getting marker count for performer: \(performer.name) (ID: \(performer.id))")

    // Use direct query with performer filter like in VisionPro version
    do {
      // First make sure authentication is working
      try? await appModel.api.checkServerConnection()

      // Query for just the count, but with performer filter
      let query = """
        {
            "operationName": "FindSceneMarkers",
            "variables": {
                "filter": {
                    "page": 1,
                    "per_page": 1
                },
                "scene_marker_filter": {
                    "performers": {
                        "value": ["\(performer.id)"],
                        "modifier": "INCLUDES_ALL"
                    }
                }
            },
            "query": "query FindSceneMarkers($filter: FindFilterType, $scene_marker_filter: SceneMarkerFilterType) { findSceneMarkers(filter: $filter, scene_marker_filter: $scene_marker_filter) { count } }"
        }
        """

      let data = try await appModel.api.executeGraphQLQuery(query)

      struct CountResponse: Decodable {
        let data: DataField

        struct DataField: Decodable {
          let findSceneMarkers: CountField

          struct CountField: Decodable {
            let count: Int
          }
        }
      }

      let response = try JSONDecoder().decode(CountResponse.self, from: data)
      let totalCount = response.data.findSceneMarkers.count

      print("📊 Marker count for performer \(performer.name): \(totalCount)")
      return totalCount
    } catch {
      print("❌ Error getting marker count: \(error)")
      return 0
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

  private func getResumeTime(for sceneId: String) async -> Double? {
    let query = """
      {
          "operationName": "FindScene",
          "variables": {
              "id": "\(sceneId)"
          },
          "query": "query FindScene($id: ID!) { findScene(id: $id) { resume_time } }"
      }
      """

    print("⏱️ Fetching resume time for scene: \(sceneId)")
    do {
      // Use the app model's enhanced executeGraphQLQuery method for consistent auth
      let data = try await appModel.api.executeGraphQLQuery(query)

      struct ResumeResponse: Decodable {
        let data: DataResponse
        struct DataResponse: Decodable {
          let findScene: SceneData
          struct SceneData: Decodable {
            let resume_time: Double?
          }
        }
      }

      let response = try JSONDecoder().decode(ResumeResponse.self, from: data)
      if let resumeTime = response.data.findScene.resume_time {
        print("⏱️ Found resume time: \(resumeTime) seconds for scene \(sceneId)")
      } else {
        print("⏱️ No resume time found for scene \(sceneId)")
      }
      return response.data.findScene.resume_time
    } catch {
      print("❌ Error fetching resume time: \(error)")
      return nil
    }
  }

  // Helper function to set HLS preference for markers
  private func setHLSPreference(for marker: SceneMarker) {
    // Set preference for HLS streaming
    UserDefaults.standard.set(true, forKey: "scene_\(marker.scene.id)_preferHLS")

    // Save timestamp for player to use
    let markerSeconds = Int(marker.seconds)
    UserDefaults.standard.set(Double(marker.seconds), forKey: "scene_\(marker.scene.id)_startTime")

    // Get API key for authentication
    let apiKey = appModel.apiKey
    let baseServerURL = appModel.serverAddress.trimmingCharacters(
      in: CharacterSet(charactersIn: "/"))
    let sceneId = marker.scene.id

    // Current timestamp (similar to _ts parameter in the URL)
    let currentTimestamp = Int(Date().timeIntervalSince1970)

    // EXACT FORMAT: http://192.168.86.100:9999/scene/3174/stream.m3u8?apikey=KEY&resolution=ORIGINAL&t=2132&_ts=1747330385
    let hlsStreamURL =
      "\(baseServerURL)/scene/\(sceneId)/stream.m3u8?apikey=\(apiKey)&resolution=ORIGINAL&t=\(markerSeconds)&_ts=\(currentTimestamp)"

    print("🎬 Using exact HLS format: \(hlsStreamURL)")

    // Save HLS format URL to UserDefaults
    UserDefaults.standard.set(hlsStreamURL, forKey: "scene_\(marker.scene.id)_hlsURL")
  }

  // Helper function to toggle preview for marker
  private func togglePreview(for marker: SceneMarker, in geometry: GeometryProxy) {
    print("🎬 Toggle preview for marker: \(marker.title)")

    // Toggle preview state
    let isCurrentlyPlaying = markerPreviewStates[marker.id, default: false]
    markerPreviewStates[marker.id] = !isCurrentlyPlaying

    if !isCurrentlyPlaying {
      // Start preview
      startPreview(for: marker)
    } else {
      // Stop preview
      stopPreview(for: marker)
    }
  }

  private func checkVisibility(for marker: SceneMarker, in geometry: GeometryProxy) {
    let frame = geometry.frame(in: .global)
    let isNowVisible = frame.minY > 0 && frame.maxY < UIScreen.main.bounds.height

    // If not visible, ensure preview is stopped
    if !isNowVisible && markerPreviewStates[marker.id, default: false] {
      print("🎬 Marker scrolled out of view, stopping preview: \(marker.id)")
      stopPreview(for: marker)
    }
  }

  private func startPreview(for marker: SceneMarker) {
    print("🎬 Starting preview for marker: \(marker.title) (ID: \(marker.id))")

    // Create a new player if needed
    if markerPreviewPlayers[marker.id] == nil {
      markerPreviewPlayers[marker.id] = VideoPlayerViewModel()
    }

    guard let previewPlayer = markerPreviewPlayers[marker.id] else { return }

    // Get API key for authentication
    let apiKey = appModel.apiKey
    let baseServerURL = appModel.serverAddress.trimmingCharacters(
      in: CharacterSet(charactersIn: "/"))
    let sceneId = marker.scene.id
    let markerId = marker.id

    // EXACT FORMAT FROM VISION PRO APP: http://192.168.86.100:9999/scene/3969/scene_marker/2669/stream?apikey=KEY
    let visionProFormatURL =
      "\(baseServerURL)/scene/\(sceneId)/scene_marker/\(markerId)/stream?apikey=\(apiKey)"
    print("🎬 Using Vision Pro format URL: \(visionProFormatURL)")

    if let url = URL(string: visionProFormatURL) {
      previewPlayer.setupPlayerItem(with: url)
      previewPlayer.mute(markerMuteStates[marker.id, default: true])
      previewPlayer.play()
      return
    }

    // If Vision Pro format fails, try the marker's direct URLs
    print("⚠️ Vision Pro format failed, trying direct API URLs")
    print("🎬 Marker preview URL: \(marker.preview)")
    print("🎬 Marker stream URL: \(marker.stream)")

    // Try using the marker's preview URL directly
    if let url = URL(string: marker.preview) {
      print("🎬 Using direct marker.preview URL: \(marker.preview)")
      previewPlayer.setupPlayerItem(with: url)
      previewPlayer.mute(markerMuteStates[marker.id, default: true])
      previewPlayer.play()
      return
    }

    // If not available, try marker's stream URL
    if let url = URL(string: marker.stream) {
      print("🎬 Using direct marker.stream URL: \(marker.stream)")
      previewPlayer.setupPlayerItem(with: url)
      previewPlayer.mute(markerMuteStates[marker.id, default: true])
      previewPlayer.play()
      return
    }

    // Last resort: try with scene stream and timestamp
    let sceneStreamURL =
      "\(baseServerURL)/scene/\(sceneId)/stream?t=\(Int(marker.seconds))&apikey=\(apiKey)"
    print("🎬 Using scene stream with timestamp: \(sceneStreamURL)")

    if let url = URL(string: sceneStreamURL) {
      previewPlayer.setupPlayerItem(with: url)
      previewPlayer.mute(markerMuteStates[marker.id, default: true])
      previewPlayer.play()
    } else {
      print("❌ All URL formats failed, cannot play preview")
    }
  }

  private func stopPreview(for marker: SceneMarker) {
    print("🎬 Stopping preview for marker: \(marker.title)")

    guard let previewPlayer = markerPreviewPlayers[marker.id] else { return }

    // First mute to prevent audio leaks
    previewPlayer.player.isMuted = true
    previewPlayer.pause()

    // Cleanup player
    previewPlayer.cleanup()

    // Remove player from dictionary
    markerPreviewPlayers.removeValue(forKey: marker.id)
    markerPreviewStates[marker.id] = false
  }

  private func toggleMute(for marker: SceneMarker) {
    guard let previewPlayer = markerPreviewPlayers[marker.id] else { return }

    // Toggle mute state
    let newMuteState = !markerMuteStates[marker.id, default: true]
    markerMuteStates[marker.id] = newMuteState

    // Apply to player
    previewPlayer.mute(newMuteState)
  }
}

