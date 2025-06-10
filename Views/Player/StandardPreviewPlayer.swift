import SwiftUI
import AVKit

// MARK: - Standard Preview Player
/// A unified preview player for inline video playback in lists
struct StandardPreviewPlayer: View {
    let url: URL
    let sceneID: String?
    let markerID: String?
    let isMuted: Bool
    let autoPlay: Bool
    let showControls: Bool
    let onTap: () -> Void
    
    @StateObject private var viewModel = VideoPlayerViewModel()
    @State private var isPlaying = false
    @State private var showError = false
    
    init(
        url: URL,
        sceneID: String? = nil,
        markerID: String? = nil,
        isMuted: Bool = true,
        autoPlay: Bool = true,
        showControls: Bool = true,
        onTap: @escaping () -> Void = {}
    ) {
        self.url = url
        self.sceneID = sceneID
        self.markerID = markerID
        self.isMuted = isMuted
        self.autoPlay = autoPlay
        self.showControls = showControls
        self.onTap = onTap
    }
    
    var body: some View {
        VideoPlayer(player: viewModel.player) {
            if showControls {
                VStack {
                    Spacer()
                    HStack {
                        controlButtons
                        Spacer()
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .onTapGesture {
            onTap()
        }
        .overlay(
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
                
                if showError, let error = viewModel.error {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
        )
    }
    
    @ViewBuilder
    private var controlButtons: some View {
        HStack(spacing: 12) {
            // Play/Pause button
            Button(action: {
                if isPlaying {
                    viewModel.pause()
                } else {
                    viewModel.play()
                }
                isPlaying.toggle()
            }) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            
            // Mute button
            Button(action: {
                viewModel.mute(!viewModel.player.isMuted)
            }) {
                Image(systemName: viewModel.player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            
            // Random jump button (for scenes)
            if sceneID != nil {
                Button(action: {
                    VideoPlayerUtility.jumpToRandomPosition(in: viewModel.player)
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.white)
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                        .background(Color.purple.opacity(0.8))
                        .clipShape(Circle())
                }
            }
        }
    }
    
    private func setupPlayer() {
        // Convert to HLS if needed
        let finalURL: URL
        if let hlsURL = VideoPlayerUtility.getHLSStreamURL(from: url, isMarkerURL: markerID != nil) {
            finalURL = hlsURL
        } else {
            finalURL = url
        }
        
        // Setup player
        viewModel.setupPlayerItem(with: finalURL)
        viewModel.mute(isMuted)
        
        // Setup marker end time if needed
        if let markerID = markerID {
            // Extract end time from URL parameters if available
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let endParam = components.queryItems?.first(where: { $0.name == "end" })?.value,
               let endSeconds = Double(endParam) {
                viewModel.endSeconds = endSeconds
            }
        }
        
        // Auto-play if enabled
        if autoPlay {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                viewModel.play()
                isPlaying = true
            }
        }
        
        // Monitor errors
        viewModel.$error
            .sink { error in
                showError = error != nil
            }
            .store(in: &cancellables)
    }
    
    @State private var cancellables = Set<AnyCancellable>()
}

// MARK: - Scene Preview Extension
extension StandardPreviewPlayer {
    static func forScene(_ scene: StashScene, appModel: AppModel, onTap: @escaping () -> Void) -> StandardPreviewPlayer {
        let url = URL(string: scene.paths.stream)!
        return StandardPreviewPlayer(
            url: url,
            sceneID: scene.id,
            onTap: onTap
        )
    }
}

// MARK: - Marker Preview Extension
extension StandardPreviewPlayer {
    static func forMarker(_ marker: StashMarker, appModel: AppModel, onTap: @escaping () -> Void) -> StandardPreviewPlayer {
        // Build marker URL with proper parameters
        guard let serverAddress = appModel.api.serverAddress,
              let apiKey = appModel.api.apiKeyForURLs else {
            return StandardPreviewPlayer(url: URL(string: "https://invalid")!, markerID: marker.id, onTap: onTap)
        }
        
        var components = URLComponents(string: "\(serverAddress)/scene/\(marker.scene.id)/stream")!
        
        var queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "start", value: String(format: "%.2f", marker.seconds)),
            URLQueryItem(name: "resolution", value: "ORIGINAL")
        ]
        
        // Add end time if primary tag has marker preview type
        if let primaryTag = marker.primaryTag,
           primaryTag.id == appModel.markerPreviewsTagId {
            let endSeconds = marker.seconds + 30
            queryItems.append(URLQueryItem(name: "end", value: String(format: "%.2f", endSeconds)))
        }
        
        components.queryItems = queryItems
        
        return StandardPreviewPlayer(
            url: components.url!,
            markerID: marker.id,
            onTap: onTap
        )
    }
}