import SwiftUI
import AVKit
import Foundation

struct SceneRow: View {
    let scene: StashScene
    let onTagSelected: (StashScene.Tag) -> Void
    let onPerformerSelected: (StashScene.Performer) -> Void
    @State private var isVisible = false
    @State private var isMuted = true
    @State private var showingTagEditor = false
    @StateObject private var previewPlayer = VideoPlayerViewModel()
    var onSceneUpdated: (StashScene) -> Void
    var onSceneSelected: (StashScene) -> Void
    
    var body: some View {
        // Log scene info for debugging
        let _ = print("📱 SCENE ROW: Rendering scene: \(scene.id), title: \(scene.title ?? "missing title")")
        let titleValue = scene.title ?? "Untitled" // Cache title for consistent use

        return VStack(alignment: .leading) {
            // Thumbnail with preview
            GeometryReader { geometry in
                ZStack {
                    // Thumbnail
                    AsyncImage(url: URL(string: scene.paths.screenshot)) { image in
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                    }

                    // Video preview - check both paths.preview and paths.stream
                    if isVisible {
                        VideoPlayer(player: previewPlayer.player)
                            .onAppear {
                                previewPlayer.player.isMuted = isMuted
                            }
                    }

                    // Duration and mute overlay
                    HStack {
                        if let firstFile = scene.files.first {
                            Text(formatDuration(firstFile.duration))
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial)
                                .cornerRadius(4)
                        }

                        Spacer()

                        if isVisible {
                            Button(action: {
                                isMuted.toggle()
                                previewPlayer.player.isMuted = isMuted
                            }) {
                                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(8)

                    // Random jump button positioned at the top-right (now matching MarkerRow styling)
                    VStack {
                        HStack {
                            Spacer()

                            // Random Jump button at top-right - ENHANCED STYLING like MarkerRow
                            Button {
                                print("📱 SCENEROW: Random Jump button tapped for scene: \(scene.id), title: \(scene.title ?? "unknown")")
                                playRandomPositionInScene(scene)
                            } label: {
                                ZStack {
                                    // Background circle - BRIGHT PURPLE
                                    Circle()
                                        .fill(Color.purple)
                                        .frame(width: 60, height: 60)
                                        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)

                                    // Icon - LARGER
                                    Image(systemName: "shuffle")
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
                        Spacer()
                    }
                }
                .task {
                    // Check visibility on task creation
                    let frame = geometry.frame(in: .global)
                    let isNowVisible = frame.minY > 0 && frame.maxY < UIScreen.main.bounds.height

                    if isNowVisible && !isVisible {
                        print("📱 SCENEROW: Task - Scene \(scene.id) is visible, starting preview")
                        await MainActor.run {
                            isVisible = true
                            startPreview()
                        }
                    }
                }
                .onChange(of: geometry.frame(in: .global).minY) { _, newValue in
                    let frame = geometry.frame(in: .global)
                    let isNowVisible = frame.minY > 0 && frame.maxY < UIScreen.main.bounds.height

                    if isNowVisible != isVisible {
                        print("📱 SCENEROW: Visibility changed for scene \(scene.id) to \(isNowVisible)")
                        isVisible = isNowVisible
                        if isNowVisible {
                            startPreview()
                        } else {
                            stopPreview()
                        }
                    }
                }
                .onAppear {
                    // When the row appears, check if it's visible in the viewport
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        let frame = geometry.frame(in: .global)
                        let isNowVisible = frame.minY > 0 && frame.maxY < UIScreen.main.bounds.height

                        if isNowVisible && !isVisible {
                            isVisible = true
                            startPreview()
                        }
                    }
                }
                .onTapGesture(count: 2) {
                    // Double-tap to select scene
                    onSceneSelected(scene)
                }
                .onTapGesture {
                    // Single tap toggles preview
                    isVisible.toggle()
                    if isVisible {
                        startPreview()
                    } else {
                        stopPreview()
                    }
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Info section with higher priority for title - STYLING MATCHED TO MARKERROW
            VStack(alignment: .leading, spacing: 8) {
                // Title section gets higher layout priority to ensure it's always visible
                VStack(alignment: .leading) {
                    // Title in separate stack with PURPLE COLOR and UNDERLINE like MarkerRow
                    HStack {
                        Button(action: {
                            onSceneSelected(scene)
                        }) {
                            Text(titleValue)
                                .font(.headline)
                                .fontWeight(.bold)
                                .lineLimit(2) // Allow up to 2 lines for longer titles
                                .fixedSize(horizontal: false, vertical: true) // Ensure text doesn't get cut off
                                .padding(.vertical, 4) // Add padding above and below title
                                .foregroundColor(.purple) // CHANGED TO PURPLE
                                .underline() // ADDED UNDERLINE
                                .layoutPriority(100) // Give title highest layout priority
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Controls in separate row
                    HStack {
                        // Scene ID for debugging
                        Text("ID: \(scene.id)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .opacity(0.7)

                        Spacer()

                        Button(action: { showingTagEditor = true }) {
                            Image(systemName: "tag")
                                .foregroundColor(.green) // CHANGED FROM BLUE TO GREEN
                        }

                        // Show ratings and o_counter information
                        HStack(spacing: 12) {
                            if let rating = scene.rating100 {
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                    Text("\(rating/20)")
                                        .foregroundColor(.secondary)
                                }
                                .font(.subheadline)
                            }

                            // Display o_counter when available
                            if let oCounter = scene.o_counter, oCounter > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "number.circle.fill")
                                        .foregroundColor(.orange) // CHANGED TO ORANGE
                                    Text("\(oCounter)")
                                        .foregroundColor(.secondary)
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }
                
                // Performers
                if !scene.performers.isEmpty {
                    HStack {
                        ForEach(scene.performers) { performer in
                            NavigationLink(destination: PerformerDetailView(performer: performer)) {
                                Text(performer.name)
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 8)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(6)
                                    .contentShape(Rectangle())
                            }
                            
                            if performer != scene.performers.last {
                                Text("·")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 2)
                            }
                        }
                    }
                    .lineLimit(1)
                }
                
                // Tags - UPDATED TO MATCH MARKERROW STYLING
                if !scene.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            // First tag styled as primary tag (purple background)
                            if let firstTag = scene.tags.first {
                                Button(action: { onTagSelected(firstTag) }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "tag.fill")
                                            .font(.system(size: 10))
                                        Text(firstTag.name)
                                            .fontWeight(.medium)
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.purple.opacity(0.2)) // CHANGED FROM BLUE TO PURPLE
                                    .cornerRadius(12)
                                }
                            }
                            
                            // Rest of the tags
                            ForEach(scene.tags.dropFirst()) { tag in
                                Button(action: { onTagSelected(tag) }) {
                                    Text(tag.name)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.secondary.opacity(0.15))
                                        .cornerRadius(12)
                                }
                            }
                        }
                    }
                }
                
                // File info
                if let firstFile = scene.files.first {
                    HStack(spacing: 12) {
                        Label(firstFile.formattedSize, systemImage: "folder")
                        if let height = firstFile.height {
                            Label("\(height)p", systemImage: "rectangle.on.rectangle")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .padding(8)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1) // ADDED PURPLE BORDER
        )
        .sheet(isPresented: $showingTagEditor) {
            TagEditorView(scene: scene) { updatedScene in
                onSceneUpdated(updatedScene)
                showingTagEditor = false
            }
        }
    }
    
    private func formatDuration(_ duration: Float?) -> String {
        guard let duration = duration else { return "Unknown" }
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%.2d:%.2d:%.2d", hours, minutes, seconds)
        } else {
            return String(format: "%.2d:%.2d", minutes, seconds)
        }
    }
    
    private func startPreview() {
        // Try to get either preview URL or stream URL
        var previewURLString = scene.paths.preview
        if previewURLString == nil || previewURLString?.isEmpty == true {
            // Fall back to stream URL if no preview URL
            print("⚠️ No preview URL found for scene ID \(scene.id), falling back to stream URL")
            previewURLString = scene.paths.stream
        }
        
        if let urlString = previewURLString, let url = URL(string: urlString) {
            print("🔥 Starting preview for scene: \(scene.title ?? "") with URL: \(urlString)")
            
            var request = URLRequest(url: url)
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.setValue("bytes=0-1146540", forHTTPHeaderField: "Range")
            
            // If using a stream URL instead of preview, we need authentication
            if urlString == scene.paths.stream, let api = StashAPI.shared {
                request.setValue(api.apiKeyForURLs, forHTTPHeaderField: "ApiKey")
                request.setValue("Bearer \(api.apiKeyForURLs)", forHTTPHeaderField: "Authorization")
            }
            
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": request.allHTTPHeaderFields ?? [:]])
            let playerItem = AVPlayerItem(asset: asset)
            previewPlayer.player.replaceCurrentItem(with: playerItem)
            previewPlayer.player.isMuted = isMuted
            previewPlayer.player.play()
        } else {
            print("❌ No valid preview or stream URL found for scene ID \(scene.id)")
        }
    }
    
    private func stopPreview() {
        print("🔥 Stopping preview for scene: \(scene.title ?? "")")
        previewPlayer.cleanup()
        isVisible = false
    }

    /// Plays the scene from a random position
    private func playRandomPositionInScene(_ scene: StashScene) {
        print("🎲 SCENEROW: Playing scene from random position")

        // Set random jump mode flag so that subsequent "next" button presses will also perform random jumps
        UserDefaults.standard.set(true, forKey: "isRandomJumpMode")
        print("🎲 SCENEROW: Enabled random jump mode for future navigation")

        // First pass the scene to the parent to handle navigation and display
        onSceneSelected(scene)

        // Give more time for the player to initialize and load the video
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            // Look for the player from the registry in VideoPlayerView
            if let player = VideoPlayerRegistry.shared.currentPlayer {
                print("🎲 SCENEROW: Got player from registry, attempting to jump to random position")

                // Check if the player is ready
                if let currentItem = player.currentItem, currentItem.status == .readyToPlay {
                    print("🎲 SCENEROW: Player is ready, jumping to random position")
                    VideoPlayerUtility.jumpToRandomPosition(in: player)
                } else {
                    print("🎲 SCENEROW: Player not ready yet, will retry in 1.5 seconds")

                    // Retry after another delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if let player = VideoPlayerRegistry.shared.currentPlayer,
                           let currentItem = player.currentItem,
                           currentItem.status == .readyToPlay {
                            print("🎲 SCENEROW: Player is now ready (retry), jumping to random position")
                            VideoPlayerUtility.jumpToRandomPosition(in: player)
                        } else {
                            print("🎲 SCENEROW: Player still not ready after retry")

                            // One final attempt with a longer delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                if let player = VideoPlayerRegistry.shared.currentPlayer {
                                    print("🎲 SCENEROW: Final attempt to jump to random position")
                                    // Force the jump even if not fully ready
                                    VideoPlayerUtility.jumpToRandomPosition(in: player)
                                }
                            }
                        }
                    }
                }
            } else {
                print("⚠️ SCENEROW: Failed to get player from registry")
            }
        }
    }
}

struct TagView: View {
    let tag: StashScene.Tag
    let onTagSelected: (StashScene.Tag) -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: { onTagSelected(tag) }) {
            Text(tag.name)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isHovering ? 
                        Color.purple.opacity(0.3) : 
                        Color.secondary.opacity(0.15)
                )
                .cornerRadius(12)
                .scaleEffect(isHovering ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovering)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}