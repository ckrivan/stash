import SwiftUI
import AVKit
import Foundation

struct MarkerRow: View {
    // Model
    let marker: SceneMarker
    let serverAddress: String
    
    // Callbacks
    let onTitleTap: (SceneMarker) -> Void
    let onTagTap: (String) -> Void
    var onPerformerTap: ((StashScene.Performer) -> Void)? = nil
    var onShuffleTap: ((String) -> Void)? = nil // Shuffle callback for tag
    
    // State
    @State private var isVisible = false
    @State private var isMuted = true
    @State private var selectedPerformer: StashScene.Performer?
    @State private var associatedPerformer: StashScene.Performer?
    @State private var isPreviewPlaying = false

    // Environment
    @EnvironmentObject private var appModel: AppModel
    
    // Video player
    @StateObject private var previewPlayer = VideoPlayerViewModel()
    
    // Helper computed property to get female performers
    private var femalePerformers: [StashScene.Performer] {
        guard let performers = marker.scene.performers else {
            return []
        }
        
        // Filter for performers with "female" gender if available
        // If gender is nil, include them anyway for backward compatibility
        return performers.filter { performer in
            if let gender = performer.gender {
                return gender.lowercased() == "female"
            }
            return true // Include if gender is not specified
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            // Marker thumbnail and video preview
            GeometryReader { geometry in
                ZStack {
                    // Thumbnail image
                    AsyncImage(url: URL(string: marker.screenshot)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                    }
                    
                    // Video preview (only show when playing)
                    if isVisible && isPreviewPlaying {
                        VideoPlayer(player: previewPlayer.player)
                            .onDisappear {
                                // Ensure cleanup on disappear
                                cleanupPlayer()
                            }
                    }
                    
                    // Marker timestamp and controls overlay
                    VStack {
                        HStack {
                            // Timestamp badge
                            Text(formatTime(seconds: marker.seconds))
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial)
                                .cornerRadius(4)
                            
                            Spacer()
                            
                            // Play Button - ENHANCED STYLING like SceneRow's Random Jump button
                            Button {
                                // Set streaming preference first
                                setHLSPreference()
                                // Then navigate to marker in full screen
                                onTitleTap(marker)
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
                        .padding(.top, 4)
                        
                        Spacer()
                        
                        HStack {
                            // Spacer to push mute button to the right
                            Spacer()
                            
                            // Mute button (only when preview is playing)
                            if isPreviewPlaying {
                                Button(action: toggleMute) {
                                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                        .foregroundColor(.white)
                                        .padding(.all, 8)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .padding(.bottom, 8)
                        .padding(.trailing, 8)
                    }
                }
                .onTapGesture {
                    // Toggle preview on tap
                    isPreviewPlaying.toggle()
                    
                    if isPreviewPlaying {
                        startPreview()
                    } else {
                        stopPreview()
                    }
                }
                // Handle visibility changes
                .onChange(of: geometry.frame(in: .global).minY) { _, newValue in
                    let frame = geometry.frame(in: .global)
                    let isNowVisible = frame.minY > 0 && frame.maxY < UIScreen.main.bounds.height
                    onVisibilityChanged(isNowVisible: isNowVisible)
                }
                .onAppear {
                    // When the row appears, check if it's visible in the viewport
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        let frame = geometry.frame(in: .global)
                        let isNowVisible = frame.minY > 0 && frame.maxY < UIScreen.main.bounds.height
                        onVisibilityChanged(isNowVisible: isNowVisible)
                    }
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            .cornerRadius(8)
            .clipped()
            
            // Marker info section with styling from SceneRow
            VStack(alignment: .leading, spacing: 8) {
                // Title with tap action for full screen viewing - STYLED LIKE SCENEROW
                VStack(alignment: .leading) {
                    Button(action: {
                        // First set the HLS preference
                        setHLSPreference()
                        // Then navigate
                        onTitleTap(marker)
                    }) {
                        Text(marker.title.isEmpty ? "Untitled" : marker.title)
                            .font(.headline)
                            .fontWeight(.bold)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 4)
                            .foregroundColor(.purple)
                            .underline()
                            .layoutPriority(100)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Controls in separate row - like SceneRow
                    HStack {
                        // Marker ID and timestamp for reference
                        Text("ID: \(marker.id) (\(formatTime(seconds: marker.seconds)))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .opacity(0.7)
                        
                        Spacer()
                        
                        // Scene info as a link
                        Button(action: {
                            if let scene = appModel.api.scenes.first(where: { $0.id == marker.scene.id }) {
                                appModel.navigateToScene(scene)
                            }
                        }) {
                            Text("Scene: \(marker.scene.title ?? "Unknown")")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                
                // Female Performers - highlighted specifically
                if !femalePerformers.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Female Performers:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                        
                        HStack {
                            ForEach(femalePerformers) { performer in
                                NavigationLink(destination: PerformerDetailView(performer: performer)) {
                                    Text(performer.name)
                                        .font(.subheadline)
                                        .foregroundColor(.purple)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 8)
                                        .background(Color.purple.opacity(0.1))
                                        .cornerRadius(6)
                                        .contentShape(Rectangle())
                                }  // Use PlainButtonStyle to avoid visual effects
                                
                                if performer != femalePerformers.last {
                                    Text("·")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 2)
                                }
                            }
                        }
                        .lineLimit(1)
                    }
                }
                
                // All performers (if available)
                if let performers = marker.scene.performers, !performers.isEmpty, performers != femalePerformers, onPerformerTap != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        if !femalePerformers.isEmpty {
                            Text("Other Performers:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Performers:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(performers, id: \.id) { performer in
                                    // Skip female performers if they're already displayed above
                                    if !femalePerformers.contains(where: { $0.id == performer.id }) {
                                        NavigationLink(destination: PerformerDetailView(performer: performer)) {
                                            HStack(spacing: 4) {
                                                // Performer avatar if available
                                                if let imagePath = performer.image_path, !imagePath.isEmpty {
                                                    AsyncImage(url: URL(string: "\(serverAddress)\(imagePath)")) { image in
                                                        image
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                    } placeholder: {
                                                        Circle()
                                                            .fill(Color.gray.opacity(0.2))
                                                    }
                                                    .frame(width: 20, height: 20)
                                                    .clipShape(Circle())
                                                } else {
                                                    Image(systemName: "person.circle.fill")
                                                        .resizable()
                                                        .frame(width: 20, height: 20)
                                                        .foregroundColor(.gray)
                                                }
                                                
                                                Text(performer.name)
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 8)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(12)
                                            .contentShape(Rectangle())
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Tags section - STYLED LIKE SCENEROW
                HStack {
                    // Primary tag first - PURPLE LIKE SCENEROW
                    Button(action: {
                        onTagTap(marker.primary_tag.name)
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 10))
                            Text(marker.primary_tag.name)
                                .fontWeight(.medium)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.purple.opacity(0.2)) // PURPLE LIKE SCENEROW
                        .cornerRadius(12)
                    }
                    
                    // Shuffle button for this marker tag
                    Button(action: {
                        // Use local haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        
                        // Add debug print
                        print("📱 SHUFFLE BUTTON TAPPED - tag: \(marker.primary_tag.name)")
                        
                        // First filter by tag
                        onTagTap(marker.primary_tag.name)
                        
                        // Then call the shuffle callback if available
                        if let onShuffleTap = onShuffleTap {
                            print("📱 Calling onShuffleTap callback")
                            onShuffleTap(marker.primary_tag.id)
                        } else {
                            print("⚠️ No shuffle callback available")
                            // Fallback to just playing this marker
                            onTitleTap(marker)
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 10))
                            Text("Shuffle")
                                .fontWeight(.medium)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.pink.opacity(0.2))
                        .cornerRadius(12)
                    }
                    
                    // Additional tags
                    if !marker.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(marker.tags) { tag in
                                    Button(action: {
                                        onTagTap(tag.name)
                                    }) {
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
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1) // ADDED PURPLE BORDER
        )
        .onDisappear {
            // Ensure cleanup when row disappears
            if isPreviewPlaying {
                isPreviewPlaying = false
                cleanupPlayer()
            }
        }
    }
    
    // Format duration in mm:ss format
    private func formatDuration(_ seconds: Float) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
    
    private func formatTime(seconds: Float) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
    
    // Start video preview
    private func startPreview() {
        print("🎬 Starting preview for marker: \(marker.title) (ID: \(marker.id))")
        
        // Get API key for authentications
        let apiKey = appModel.apiKey
        let baseServerURL = serverAddress.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let sceneId = marker.scene.id
        let markerId = marker.id
        
        // EXACT FORMAT FROM VISION PRO APP: http://192.168.86.100:9999/scene/3969/scene_marker/2669/stream?apikey=KEY
        let visionProFormatURL = "\(baseServerURL)/scene/\(sceneId)/scene_marker/\(markerId)/stream?apikey=\(apiKey)"
        print("🎬 Using Vision Pro format URL: \(visionProFormatURL)")
        
        if let url = URL(string: visionProFormatURL) {
            previewPlayer.setupPlayerItem(with: url)
            previewPlayer.mute(isMuted)
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
            previewPlayer.mute(isMuted)
            previewPlayer.play()
            return
        }
        
        // If not available, try marker's stream URL
        if let url = URL(string: marker.stream) {
            print("🎬 Using direct marker.stream URL: \(marker.stream)")
            previewPlayer.setupPlayerItem(with: url)
            previewPlayer.mute(isMuted)
            previewPlayer.play()
            return
        }
        
        // Last resort: try with scene stream and timestamp
        let sceneStreamURL = "\(baseServerURL)/scene/\(sceneId)/stream?t=\(Int(marker.seconds))&apikey=\(apiKey)"
        print("🎬 Using scene stream with timestamp: \(sceneStreamURL)")
        
        if let url = URL(string: sceneStreamURL) {
            previewPlayer.setupPlayerItem(with: url)
            previewPlayer.mute(isMuted)
            previewPlayer.play()
        } else {
            print("❌ All URL formats failed, cannot play preview")
        }
    }
    
    // Stop video preview
    private func stopPreview() {
        print("🎬 Stopping preview for marker: \(marker.title)")
        // First mute to prevent audio leaks
        previewPlayer.player.isMuted = true
        previewPlayer.pause()
        // Replace item with nil to fully release resources
        previewPlayer.player.replaceCurrentItem(with: nil)
        previewPlayer.cleanup()
        
        // Also stop any other active players
        GlobalVideoManager.shared.stopAllPreviews()
    }
    
    // Helper method to set HLS streaming preference
    private func setHLSPreference() {
        // Set preference for HLS streaming
        UserDefaults.standard.set(true, forKey: "scene_\(marker.scene.id)_preferHLS")
        UserDefaults.standard.set(true, forKey: "scene_\(marker.scene.id)_isMarkerNavigation")
        
        // Save timestamp for player to use - make sure this is a Double
        let markerSeconds = Double(marker.seconds)
        UserDefaults.standard.set(markerSeconds, forKey: "scene_\(marker.scene.id)_startTime")
        
        // Add support for end_seconds if available
        if let markerEndSeconds = marker.end_seconds {
            let endSeconds = Double(markerEndSeconds)
            UserDefaults.standard.set(endSeconds, forKey: "scene_\(marker.scene.id)_endTime")
            print("⏱ MarkerRow: Setting end time for marker: \(endSeconds)")
        } else {
            // Clear any previous end time
            UserDefaults.standard.removeObject(forKey: "scene_\(marker.scene.id)_endTime")
        }
        
        // Get API key for authentication
        let apiKey = appModel.apiKey
        let baseServerURL = serverAddress.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let sceneId = marker.scene.id
        
        // Current timestamp (similar to _ts parameter in the URL)
        let currentTimestamp = Int(Date().timeIntervalSince1970)
        
        // Format exactly like the example URL:
        // http://192.168.86.100:9999/scene/3174/stream.m3u8?apikey=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1aWQiOiJjayIsInN1YiI6IkFQSUtleSIsImlhdCI6MTczMTgwOTM2Mn0.7AOyZqTzyDsSnuDx__RBhuIIkoPg2btebToAlpK1zXo&resolution=ORIGINAL&t=2132&_ts=1747330385
        let hlsStreamURL = "\(baseServerURL)/scene/\(sceneId)/stream.m3u8?apikey=\(apiKey)&resolution=ORIGINAL&t=\(Int(markerSeconds))&_ts=\(currentTimestamp)"
        
        print("🎬 MarkerRow: Setting exact HLS URL format: \(hlsStreamURL)")
        UserDefaults.standard.set(hlsStreamURL, forKey: "scene_\(marker.scene.id)_hlsURL")
        
        // Force immediate playback flag
        UserDefaults.standard.set(true, forKey: "scene_\(marker.scene.id)_forcePlay")
    }
    
    // Video visibility changes
    private func onVisibilityChanged(isNowVisible: Bool) {
        if isNowVisible != isVisible {
            print("📱 MarkerRow visibility changed: \(marker.id) -> \(isNowVisible)")
            isVisible = isNowVisible
            
            if isNowVisible {
                // Preload performer when visible
                if associatedPerformer == nil, let performers = marker.scene.performers, !performers.isEmpty {
                    associatedPerformer = performers.first
                }
                
                // DO NOT auto-start preview when just scrolled into view
                // Only preload the URL when visible
                getStreamURL()
            } else {
                // When scrolled out of view, ALWAYS stop playing
                if isPreviewPlaying {
                    isPreviewPlaying = false
                    cleanupPlayer()
                }
            }
        }
    }
    
    // Toggle mute
    private func toggleMute() {
        isMuted.toggle()
        previewPlayer.mute(isMuted)
    }
    
    // Cleanup player
    private func cleanupPlayer() {
        previewPlayer.player.replaceCurrentItem(with: nil)
        previewPlayer.cleanup()
    }
    
    // Get stream URL
    private func getStreamURL() {
        // Implementation of getStreamURL method
    }
}