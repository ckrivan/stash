import AVKit
import SwiftUI
import UIKit
import Combine

// MARK: - Standard Video Player
/// A unified video player that consolidates all video player functionality
class StandardVideoPlayer: AVPlayerViewController {
    // MARK: - Properties
    private var scenes: [StashScene] = []
    private var currentIndex: Int = 0
    private var currentSceneID: String = ""
    private weak var appModel: AppModel?
    
    // Custom controls
    private var randomJumpButton: UIButton!
    private var performerJumpButton: UIButton!
    private var shuffleButton: UIButton!
    
    // Observers and timers
    private var settingsCheckTimer: Timer?
    private var timeObserver: Any?
    private var playbackObserver: Any?
    
    // Aspect ratio properties
    private var originalVideoGravity: AVLayerVideoGravity = .resizeAspect
    
    // MARK: - Initialization
    init(scenes: [StashScene] = [], currentIndex: Int = 0, sceneID: String = "", appModel: AppModel) {
        self.scenes = scenes
        self.currentIndex = currentIndex
        self.currentSceneID = sceneID
        self.appModel = appModel
        super.init(nibName: nil, bundle: nil)
        setupCustomControls()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupCustomControls() {
        // Create unified custom buttons
        randomJumpButton = createButton(systemName: "arrow.triangle.2.circlepath", action: #selector(handleRandomJump))
        performerJumpButton = createButton(systemName: "person.crop.circle", action: #selector(handlePerformerJump))
        shuffleButton = createButton(systemName: "shuffle", action: #selector(handleShuffle))
    }
    
    private func createButton(systemName: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = .white
        button.addTarget(self, action: action, for: .touchUpInside)
        button.showsTouchWhenHighlighted = true
        return button
    }
    
    // MARK: - View Lifecycle
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Make first responder for keyboard events
        becomeFirstResponder()
        
        // Setup controls and gestures
        setupUI()
        setupGestures()
        startSettingsButtonHiding()
        
        // Apply aspect ratio correction if needed
        applyAspectRatioCorrection()
        
        // Register with managers
        registerWithManagers()
        
        // Start playback
        player?.play()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Save progress before leaving
        saveCurrentProgress()
        
        // Cleanup
        cleanupObservers()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        guard let contentOverlayView = self.contentOverlayView else { return }
        
        // Configure buttons with unified positioning
        let isIpad = UIDevice.current.userInterfaceIdiom == .pad
        let padding: CGFloat = isIpad ? 60 : 30
        let size: CGFloat = isIpad ? 60 : 44
        let yOffset: CGFloat = isIpad ? 200 : 140
        
        // Add and position buttons
        [randomJumpButton, performerJumpButton, shuffleButton].forEach { button in
            button.translatesAutoresizingMaskIntoConstraints = false
            contentOverlayView.addSubview(button)
            
            // Common constraints
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: size),
                button.heightAnchor.constraint(equalToConstant: size),
                button.bottomAnchor.constraint(equalTo: contentOverlayView.bottomAnchor, constant: -yOffset)
            ])
            
            // Style button
            button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            button.layer.cornerRadius = size / 2
            button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
            
            let imageConfig = UIImage.SymbolConfiguration(pointSize: isIpad ? 24 : 18, weight: .semibold)
            button.setPreferredSymbolConfiguration(imageConfig, forImageIn: .normal)
        }
        
        // Position buttons horizontally
        NSLayoutConstraint.activate([
            randomJumpButton.leadingAnchor.constraint(equalTo: contentOverlayView.leadingAnchor, constant: padding),
            performerJumpButton.centerXAnchor.constraint(equalTo: contentOverlayView.centerXAnchor),
            shuffleButton.trailingAnchor.constraint(equalTo: contentOverlayView.trailingAnchor, constant: -padding)
        ])
        
        // Update button appearance based on shuffle mode
        updateButtonsForShuffleMode()
        
        // Setup visibility management
        setupButtonVisibility()
    }
    
    private func setupButtonVisibility() {
        // Add tap gesture to toggle button visibility
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(toggleButtonVisibility))
        contentOverlayView?.addGestureRecognizer(tapGesture)
        
        // Observe player state to auto-hide buttons
        player?.addObserver(self, forKeyPath: "timeControlStatus", options: [.new], context: nil)
    }
    
    // MARK: - Gesture Setup
    private func setupGestures() {
        guard let contentOverlayView = self.contentOverlayView else { return }
        
        // Pan gesture for swipe seeking
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture))
        panGesture.delegate = self
        panGesture.maximumNumberOfTouches = 1
        panGesture.cancelsTouchesInView = false
        contentOverlayView.addGestureRecognizer(panGesture)
        
        // Double tap for seek
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTapGesture.numberOfTapsRequired = 2
        contentOverlayView.addGestureRecognizer(doubleTapGesture)
    }
    
    // MARK: - Settings Button Management
    private func startSettingsButtonHiding() {
        // Initial hide
        hideSettingsButtons()
        
        // Delayed checks
        [0.2, 0.5, 1.0].forEach { delay in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.hideSettingsButtons()
            }
        }
        
        // Periodic timer
        settingsCheckTimer?.invalidate()
        settingsCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.hideSettingsButtons()
        }
    }
    
    private func hideSettingsButtons() {
        hideSettingsInView(self.view)
    }
    
    private func hideSettingsInView(_ view: UIView) {
        for subview in view.subviews {
            if let button = subview as? UIButton {
                // Skip our custom buttons
                if button === randomJumpButton || button === performerJumpButton || button === shuffleButton {
                    continue
                }
                
                // Hide potential settings buttons
                if let accessLabel = button.accessibilityLabel?.lowercased(),
                   accessLabel.contains("sett") || accessLabel.contains("gear") || 
                   accessLabel.contains("config") || accessLabel.contains("option") ||
                   accessLabel.contains("filter") || accessLabel.contains("preferences") {
                    button.isHidden = true
                }
                
                // Hide small circular buttons that might be settings
                if button.bounds.width < 60 && button.bounds.height < 60 {
                    button.isHidden = true
                }
            }
            
            // Recursively check subviews
            hideSettingsInView(subview)
        }
    }
    
    // MARK: - Button Actions
    @objc private func handleRandomJump() {
        VideoPlayerUtility.jumpToRandomPosition(in: player ?? AVPlayer())
    }
    
    @objc private func handlePerformerJump() {
        if appModel?.isMarkerShuffleMode == true && !(appModel?.markerShuffleQueue.isEmpty ?? true) {
            appModel?.shuffleToPreviousMarker()
            updateButtonsForShuffleMode()
        } else {
            jumpToPerformerScene()
        }
    }
    
    @objc private func handleShuffle() {
        if appModel?.isMarkerShuffleMode == true && !(appModel?.markerShuffleQueue.isEmpty ?? true) {
            appModel?.shuffleToNextMarker()
            updateButtonsForShuffleMode()
        } else {
            shuffleToRandomScene()
        }
    }
    
    @objc private func toggleButtonVisibility() {
        let buttonsVisible = randomJumpButton.alpha > 0
        
        UIView.animate(withDuration: 0.3) {
            let alpha: CGFloat = buttonsVisible ? 0.0 : 1.0
            self.randomJumpButton.alpha = alpha
            self.performerJumpButton.alpha = alpha
            self.shuffleButton.alpha = alpha
        }
        
        // Auto-hide after delay if showing
        if !buttonsVisible {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.hideButtons()
            }
        }
    }
    
    private func hideButtons() {
        UIView.animate(withDuration: 0.3) {
            self.randomJumpButton.alpha = 0.0
            self.performerJumpButton.alpha = 0.0
            self.shuffleButton.alpha = 0.0
        }
    }
    
    // MARK: - Gesture Handlers
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        
        let velocity = gesture.velocity(in: gesture.view)
        let translation = gesture.translation(in: gesture.view)
        
        let minDistance: CGFloat = 30
        let minVelocity: CGFloat = 200
        let isHorizontalSwipe = abs(translation.x) > abs(translation.y)
        
        if isHorizontalSwipe && abs(translation.x) > minDistance && abs(velocity.x) > minVelocity {
            if translation.x > 0 {
                seekVideo(by: 10) // Swipe right - forward
            } else {
                seekVideo(by: -10) // Swipe left - backward
            }
            
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }
    
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: gesture.view)
        let viewWidth = gesture.view?.bounds.width ?? 0
        
        if location.x < viewWidth / 3 {
            seekVideo(by: -10) // Left side - backward
        } else if location.x > viewWidth * 2 / 3 {
            seekVideo(by: 10) // Right side - forward
        }
    }
    
    // MARK: - Keyboard Handling
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let key = presses.first?.key else {
            super.pressesBegan(presses, with: event)
            return
        }
        
        switch key.keyCode {
        case .keyboardLeftArrow:
            seekVideo(by: -30)
            return
            
        case .keyboardRightArrow:
            seekVideo(by: 30)
            return
            
        case .keyboardV:
            handleShuffle()
            
        case .keyboardB:
            seekVideo(by: -30)
            
        case .keyboardN:
            handleRandomJump()
            
        case .keyboardM:
            handlePerformerJump()
            
        case .keyboardComma:
            handlePerformerJump()
            
        case .keyboardR:
            restartFromBeginning()
            
        case .keyboardSpacebar:
            togglePlayPause()
            
        default:
            super.pressesBegan(presses, with: event)
        }
    }
    
    // MARK: - Video Control Methods
    private func seekVideo(by seconds: Double) {
        guard let currentPlayer = player,
              let currentItem = currentPlayer.currentItem else { return }
        
        let currentTime = currentItem.currentTime()
        let targetTime = CMTimeAdd(currentTime, CMTime(seconds: seconds, preferredTimescale: 1000))
        
        // Clamp to valid range
        let duration = currentItem.duration
        let zeroTime = CMTime.zero
        
        if targetTime.seconds < 0 {
            currentPlayer.seek(to: zeroTime, toleranceBefore: .zero, toleranceAfter: .zero)
        } else if duration.isValid && targetTime.seconds > duration.seconds {
            currentPlayer.seek(to: duration, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            currentPlayer.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    private func togglePlayPause() {
        guard let currentPlayer = player else { return }
        
        if currentPlayer.timeControlStatus == .playing {
            currentPlayer.pause()
        } else {
            currentPlayer.play()
        }
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    private func restartFromBeginning() {
        player?.seek(to: .zero)
        player?.play()
    }
    
    // MARK: - Scene Navigation
    private func jumpToPerformerScene() {
        guard let currentScene = scenes.first(where: { $0.id == currentSceneID }),
              let performer = currentScene.performers.first else { return }
        
        let performerScenes = scenes.filter { scene in
            scene.performers.contains { $0.id == performer.id }
        }
        
        let otherScenes = performerScenes.filter { $0.id != currentSceneID }
        guard let randomScene = otherScenes.randomElement() ?? performerScenes.first else { return }
        
        loadScene(randomScene)
    }
    
    private func shuffleToRandomScene() {
        guard !scenes.isEmpty else { return }
        
        let otherScenes = scenes.filter { $0.id != currentSceneID }
        guard let randomScene = otherScenes.randomElement() ?? scenes.first else { return }
        
        loadScene(randomScene)
    }
    
    private func loadScene(_ scene: StashScene) {
        guard let url = URL(string: scene.paths.stream) else { return }
        
        // Save current progress
        saveCurrentProgress()
        
        // Pause current playback
        player?.pause()
        
        // Update scene ID
        currentSceneID = scene.id
        
        // Create new player item
        let playerItem = AVPlayerItem(url: url)
        player?.replaceCurrentItem(with: playerItem)
        
        // Update app model scene list
        if var scenes = appModel?.api.scenes {
            if let index = scenes.firstIndex(where: { $0.id == scene.id }) {
                scenes.remove(at: index)
            }
            scenes.insert(scene, at: 0)
            appModel?.api.scenes = scenes
        }
        
        // Start playback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.player?.play()
            self.applyAspectRatioCorrection()
        }
    }
    
    // MARK: - Aspect Ratio Correction
    private func applyAspectRatioCorrection() {
        guard let playerLayer = view.layer.sublayers?.first(where: { $0 is AVPlayerLayer }) as? AVPlayerLayer else { return }
        
        originalVideoGravity = playerLayer.videoGravity
        
        if isAnamorphicVideo() {
            playerLayer.videoGravity = .resizeAspectFill
            applyAnamorphicTransform(to: playerLayer)
        } else {
            playerLayer.videoGravity = .resizeAspect
        }
    }
    
    private func isAnamorphicVideo() -> Bool {
        guard let currentScene = scenes.first(where: { $0.id == currentSceneID }),
              let file = currentScene.files.first,
              let width = file.width,
              let height = file.height else { return false }
        
        let anamorphicResolutions = [(1440, 1080), (1920, 1440), (960, 720), (720, 540)]
        return anamorphicResolutions.contains { $0.0 == width && $0.1 == height }
    }
    
    private func applyAnamorphicTransform(to playerLayer: AVPlayerLayer) {
        guard let currentScene = scenes.first(where: { $0.id == currentSceneID }),
              let file = currentScene.files.first,
              let width = file.width,
              let height = file.height else { return }
        
        let currentAspectRatio = Double(width) / Double(height)
        let targetAspectRatio = 16.0 / 9.0
        let correctionFactor = targetAspectRatio / currentAspectRatio
        
        let transform = CATransform3DMakeScale(correctionFactor, 1.0, 1.0)
        playerLayer.transform = transform
    }
    
    // MARK: - Shuffle Mode Support
    private func updateButtonsForShuffleMode() {
        if appModel?.isMarkerShuffleMode == true {
            performerJumpButton.setImage(UIImage(systemName: "backward.fill"), for: .normal)
            shuffleButton.setImage(UIImage(systemName: "forward.fill"), for: .normal)
            performerJumpButton.tintColor = .systemOrange
            shuffleButton.tintColor = .systemOrange
            randomJumpButton.tintColor = .white
        } else {
            performerJumpButton.setImage(UIImage(systemName: "person.crop.circle"), for: .normal)
            shuffleButton.setImage(UIImage(systemName: "shuffle"), for: .normal)
            performerJumpButton.tintColor = .white
            shuffleButton.tintColor = .white
            randomJumpButton.tintColor = .white
        }
    }
    
    // MARK: - Progress Management
    private func saveCurrentProgress() {
        guard let currentPlayer = player,
              let currentTime = currentPlayer.currentItem?.currentTime().seconds,
              currentTime > 0 else { return }
        
        UserDefaults.standard.setVideoProgress(currentTime, for: currentSceneID)
    }
    
    private func registerWithManagers() {
        if let player = player {
            VideoPlayerRegistry.shared.currentPlayer = player
            VideoPlayerRegistry.shared.playerViewController = self
            GlobalVideoManager.shared.registerPlayer(player)
        }
    }
    
    // MARK: - Cleanup
    private func cleanupObservers() {
        settingsCheckTimer?.invalidate()
        settingsCheckTimer = nil
        
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        if player != nil {
            player?.removeObserver(self, forKeyPath: "timeControlStatus")
        }
        
        if let player = player {
            GlobalVideoManager.shared.unregisterPlayer(player)
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "timeControlStatus", let player = object as? AVPlayer {
            hideSettingsButtons()
            
            if player.timeControlStatus == .playing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                    self?.hideButtons()
                }
            }
        }
    }
    
    deinit {
        cleanupObservers()
    }
}

// MARK: - UIGestureRecognizerDelegate
extension StandardVideoPlayer: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}