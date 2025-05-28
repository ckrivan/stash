import AVKit
import UIKit
import SwiftUI

class CustomVideoPlayer: AVPlayerViewController {
    // MARK: - Properties
    private var scenes: [StashScene] = []
    private var currentIndex: Int = 0
    private var currentSceneID: String = ""
    private var appModel: AppModel
    
    // Timer for continuously checking and hiding settings buttons
    private var settingsCheckTimer: Timer?
    
    // MARK: - Custom Buttons
    private var randomJumpButton: UIButton!
    private var performerJumpButton: UIButton!
    private var shuffleButton: UIButton!
    
    // MARK: - Initialization
    init(scenes: [StashScene], currentIndex: Int, sceneID: String, appModel: AppModel) {
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
        // Create custom buttons
        randomJumpButton = UIButton(type: .system)
        randomJumpButton.setImage(UIImage(systemName: "arrow.triangle.2.circlepath"), for: .normal)
        randomJumpButton.tintColor = .white
        randomJumpButton.addTarget(self, action: #selector(handleRandomJumpButtonTapped), for: .touchUpInside)
        
        performerJumpButton = UIButton(type: .system)
        performerJumpButton.setImage(UIImage(systemName: "person.crop.circle"), for: .normal)
        performerJumpButton.tintColor = .white
        performerJumpButton.addTarget(self, action: #selector(handlePerformerJumpButtonTapped), for: .touchUpInside)
        
        shuffleButton = UIButton(type: .system)
        shuffleButton.setImage(UIImage(systemName: "shuffle"), for: .normal)
        shuffleButton.tintColor = .white
        shuffleButton.addTarget(self, action: #selector(handleShuffleButtonTapped), for: .touchUpInside)
        
        // Buttons will be added in viewDidAppear
    }
    
    /// Update button icons based on current shuffle mode
    private func updateButtonsForShuffleMode() {
        if appModel.isMarkerShuffleMode {
            // In marker shuffle mode: Previous | Random Jump | Next
            performerJumpButton.setImage(UIImage(systemName: "backward.fill"), for: .normal)
            shuffleButton.setImage(UIImage(systemName: "forward.fill"), for: .normal)
            
            // Update button colors to indicate shuffle mode
            performerJumpButton.tintColor = .systemOrange
            shuffleButton.tintColor = .systemOrange
            randomJumpButton.tintColor = .white
        } else {
            // Normal mode: Performer Jump | Random Jump | Scene Shuffle
            performerJumpButton.setImage(UIImage(systemName: "person.crop.circle"), for: .normal)
            shuffleButton.setImage(UIImage(systemName: "shuffle"), for: .normal)
            
            // Reset to normal colors
            performerJumpButton.tintColor = .white
            shuffleButton.tintColor = .white
            randomJumpButton.tintColor = .white
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Make this view controller the first responder to receive keyboard events
        becomeFirstResponder()
        
        // Find the transport controls container view
        if let contentOverlayView = self.contentOverlayView {
            // Configure buttons
            configureButton(randomJumpButton, inView: contentOverlayView, position: .left)
            configureButton(performerJumpButton, inView: contentOverlayView, position: .center)
            configureButton(shuffleButton, inView: contentOverlayView, position: .right)
            
            // Update button icons based on shuffle mode
            print("🎲 VideoPlayer viewDidAppear - checking shuffle mode...")
            print("🎲 isMarkerShuffleMode: \(appModel.isMarkerShuffleMode)")
            print("🎲 markerShuffleQueue.count: \(appModel.markerShuffleQueue.count)")
            updateButtonsForShuffleMode()
            
            // Start with buttons visible
            randomJumpButton.alpha = 1.0
            performerJumpButton.alpha = 1.0
            shuffleButton.alpha = 1.0

            // Hide buttons on video start with a 5-second delay
            player?.addObserver(self, forKeyPath: "timeControlStatus", options: [.new], context: nil)
            
            // Also observe currentItem changes to catch when content changes
            player?.addObserver(self, forKeyPath: "currentItem", options: [.new, .old], context: nil)
            
            // Add tap gesture to show/hide buttons
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(toggleButtonVisibility))
            contentOverlayView.addGestureRecognizer(tapGesture)
            
            // Remove gear button and settings which appear in marker playback
            // First, immediate check to hide initial buttons
            hideSettingsButtons()
            
            // Then, multiple subsequent checks to catch buttons that appear later
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.hideSettingsButtons()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.hideSettingsButtons()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.hideSettingsButtons()
            }
            
            // Also watch for layer changes that might indicate the controls are reappearing
            startObservingLayerChanges()
        }
        
        // Hide status bar when video player appears
        setNeedsStatusBarAppearanceUpdate()
        
        // Set up periodic timer to check for and hide settings buttons
        // This ensures settings buttons stay hidden even if they reappear due to system events
        // Using a faster interval (0.5 seconds) to be more responsive
        settingsCheckTimer?.invalidate() // Ensure we don't have multiple timers
        settingsCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.hideSettingsButtons()
        }
        
        // Start playback automatically
        player?.play()
    }
    
    private func startObservingLayerChanges() {
        // Set up a CADisplayLink to watch for layer changes that might indicate controls being added
        let displayLink = CADisplayLink(target: self, selector: #selector(checkForNewControls))
        displayLink.add(to: .main, forMode: .common)
        
        // Store the display link so we can invalidate it later
        objc_setAssociatedObject(self, "displayLinkKey", displayLink, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    @objc private func checkForNewControls() {
        // Check for new controls whenever the display refreshes
        // This is especially important during transitions between scenes
        hideSettingsButtons()
    }
    
    /// Hide the settings and filter buttons that appear in AVPlayerViewController
    private func hideSettingsButtons() {
        // Walk the view hierarchy to find and hide buttons
        hideSettingsInView(self.view)
    }
    
    /// Recursively search the view hierarchy to find and hide settings buttons
    private func hideSettingsInView(_ view: UIView) {
        // Check all subviews
        for subview in view.subviews {
            // If this is a button or control that might be a settings button
            if let button = subview as? UIButton {
                // Skip our custom buttons
                if button === randomJumpButton || button === performerJumpButton || button === shuffleButton {
                    continue
                }
                // Check for settings buttons based on various attributes
                if let accessLabel = button.accessibilityLabel?.lowercased(),
                   (accessLabel.contains("sett") || 
                    accessLabel.contains("gear") || 
                    accessLabel.contains("config") || 
                    accessLabel.contains("option") || 
                    accessLabel.contains("filter") ||
                    accessLabel.contains("preferences") ||
                    accessLabel.contains("more")) {
                    // Hide known settings/gear buttons
                    button.isHidden = true
                    print("🔧 Found and hidden settings button: \(accessLabel)")
                }
                
                // Hide any small circular buttons in the corners which are likely settings
                if button.bounds.width < 50 && 
                   button.bounds.height < 50 && 
                   (button.layer.cornerRadius > 10 || 
                    button.layer.cornerRadius == button.bounds.width / 2) {
                    button.isHidden = true
                    print("🔧 Hidden small circular button that may be settings")
                }
                
                // Hide any button with an image (likely gear or filter icon)
                if let _ = button.image(for: .normal),
                   button.bounds.width < 60 {
                    button.isHidden = true
                    print("🔧 Hidden small button with image that may be settings")
                }
                
                // Check for likely corner position buttons (typical for settings)
                let safeFrame = view.frame.insetBy(dx: 60, dy: 60)
                let buttonCenter = button.center
                if !safeFrame.contains(buttonCenter) {
                    // Button appears to be in a corner or edge
                    button.isHidden = true
                    print("🔧 Hidden button positioned in corner/edge")
                }
            }
            
            // Hide any toolbar that might contain settings
            if let toolbar = subview as? UIToolbar {
                toolbar.isHidden = true
                print("🔧 Hidden toolbar that may contain settings")
            }
            
            // Hide any container views that might be used for settings menus
            if subview.subviews.count > 0 {
                if let accessID = subview.accessibilityIdentifier?.lowercased(),
                   (accessID.contains("menu") || 
                    accessID.contains("popup") || 
                    accessID.contains("settings") || 
                    accessID.contains("filter")) {
                    subview.isHidden = true
                    print("🔧 Hidden container with settings-related ID: \(accessID)")
                }
            }
            
            // Continue recursively checking subviews
            hideSettingsInView(subview)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        if player != nil {
            player?.removeObserver(self, forKeyPath: "timeControlStatus")
            player?.removeObserver(self, forKeyPath: "currentItem")
        }
        
        // Invalidate and clean up the settings check timer
        settingsCheckTimer?.invalidate()
        settingsCheckTimer = nil
        
        // Invalidate the display link
        if let displayLink = objc_getAssociatedObject(self, "displayLinkKey") as? CADisplayLink {
            displayLink.invalidate()
        }
    }

    // Monitor player status to auto-hide buttons when playback starts
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "timeControlStatus", let player = object as? AVPlayer {
            // Immediately check for and hide settings buttons on any player state change
            hideSettingsButtons()
            
            if player.timeControlStatus == .playing {
                // Hide buttons 5 seconds after playback starts
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                    guard let self = self else { return }
                    // Only hide if they're currently visible
                    if self.randomJumpButton.alpha > 0 {
                        UIView.animate(withDuration: 0.3) {
                            self.randomJumpButton.alpha = 0.0
                            self.performerJumpButton.alpha = 0.0
                            self.shuffleButton.alpha = 0.0
                        }
                    }
                    
                    // Also check for settings buttons that may have appeared since playback started
                    self.hideSettingsButtons()
                }
                
                // Add additional checks at key moments when buttons might appear
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.hideSettingsButtons()
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.hideSettingsButtons()
                }
            }
        } else if keyPath == "currentItem" {
            // Current item changed, make sure to hide settings buttons
            print("🔄 Player current item changed, checking for settings buttons")
            hideSettingsButtons()
            
            // Schedule additional checks for settings buttons after item change
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.hideSettingsButtons()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.hideSettingsButtons()
            }
        }
    }
    
    @objc private func toggleButtonVisibility() {
        let buttonsVisible = randomJumpButton.alpha > 0
        
        UIView.animate(withDuration: 0.3) {
            self.randomJumpButton.alpha = buttonsVisible ? 0.0 : 1.0
            self.performerJumpButton.alpha = buttonsVisible ? 0.0 : 1.0
            self.shuffleButton.alpha = buttonsVisible ? 0.0 : 1.0
        }
        
        // Always hide settings buttons when player controls are toggled
        hideSettingsButtons()
        
        // If we're showing buttons, hide them after a delay
        if !buttonsVisible {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self = self else { return }
                
                // Only hide if they're currently visible
                if self.randomJumpButton.alpha > 0 {
                    UIView.animate(withDuration: 0.3) {
                        self.randomJumpButton.alpha = 0.0
                        self.performerJumpButton.alpha = 0.0
                        self.shuffleButton.alpha = 0.0
                    }
                }
                
                // Also hide settings buttons again in case they reappeared
                self.hideSettingsButtons()
            }
        }
    }
    
    private enum ButtonPosition {
        case left, center, right
    }
    
    private func configureButton(_ button: UIButton, inView contentView: UIView, position: ButtonPosition) {
        // Configure button appearance
        button.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(button)
        
        // Position button - adjust size for iPads
        let isIpad = UIDevice.current.userInterfaceIdiom == .pad
        let padding: CGFloat = isIpad ? 60 : 30 // Increased padding to avoid conflict with controls
        let size: CGFloat = isIpad ? 60 : 44
        // Move buttons higher up to avoid conflict with native controls
        let yOffset: CGFloat = isIpad ? 200 : 140 // Increased distance from bottom
        
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: size),
            button.heightAnchor.constraint(equalToConstant: size),
            button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -yOffset)
        ])
        
        // Set horizontal position based on position enum
        switch position {
        case .left:
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding)
            ])
        case .center:
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: contentView.centerXAnchor)
            ])
        case .right:
            NSLayoutConstraint.activate([
                button.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding)
            ])
        }
        
        // Add background for better visibility
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = size / 2
        
        // Configure tap animation
        button.showsTouchWhenHighlighted = true
        
        // Make the button larger for image
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        
        // Configure button font size
        let imageConfig = UIImage.SymbolConfiguration(pointSize: isIpad ? 24 : 18, weight: .semibold)
        button.setPreferredSymbolConfiguration(imageConfig, forImageIn: .normal)
    }
    
    // MARK: - Button Handlers
    
    @objc private func handleRandomJumpButtonTapped() {
        // Detailed logging for debugging
        print("🎲 RANDOM JUMP: Button tapped")

        guard let currentPlayer = player else {
            print("❌ RANDOM JUMP: Player is nil!")
            return
        }

        guard let currentItem = currentPlayer.currentItem else {
            print("❌ RANDOM JUMP: Current item is nil!")
            return
        }

        let duration = currentItem.duration.seconds
        print("🎲 RANDOM JUMP: Current duration = \(duration) seconds")

        guard duration.isFinite && duration > 10 else {
            print("❌ RANDOM JUMP: Invalid duration: \(duration)")
            return
        }

        // Current time for logging
        let currentSeconds = currentItem.currentTime().seconds
        print("🎲 RANDOM JUMP: Current position = \(currentSeconds) seconds")

        // Generate a random position between 10% and 90% of the video duration
        // Using a wider range than before (10-90% instead of 5-95%)
        let minPosition = max(5, duration * 0.1) // Ensure at least 5 seconds from start
        let maxPosition = min(duration - 10, duration * 0.9) // Ensure at least 10 seconds from end

        // Generate and log random position with more precision
        let randomPosition = Double.random(in: minPosition...maxPosition)
        let minutes = Int(randomPosition / 60)
        let seconds = Int(randomPosition) % 60

        print("🎲 RANDOM JUMP: Generated position - \(randomPosition) seconds (\(minutes):\(String(format: "%02d", seconds)))")
        print("🎲 RANDOM JUMP: Acceptable range was \(minPosition) to \(maxPosition) seconds")

        // Create time with higher precision timescale (was 600, now 1000)
        let time = CMTime(seconds: randomPosition, preferredTimescale: 1000)

        // Set tolerances to ensure more precise seeking
        let toleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 1000)
        let toleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 1000)

        print("🎲 RANDOM JUMP: Attempting to seek to position...")

        // Use the more precise seek method with tolerances
        currentPlayer.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter) { success in
            if success {
                print("✅ RANDOM JUMP: Successfully jumped to \(minutes):\(String(format: "%02d", seconds))")

                // Provide haptic feedback when jump succeeds
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()

                // Force the player to resume playback after seeking
                if currentPlayer.timeControlStatus != .playing {
                    print("▶️ RANDOM JUMP: Resuming playback after jump")
                    currentPlayer.play()
                    
                    // Hide any settings buttons that might have appeared after seeking
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.hideSettingsButtons()
                    }
                }
            } else {
                print("❌ RANDOM JUMP: Seek operation failed")
            }
        }
    }
    
    @objc private func handlePerformerJumpButtonTapped() {
        // Check if we're in marker shuffle mode - use as "previous" button
        if appModel.isMarkerShuffleMode && !appModel.markerShuffleQueue.isEmpty {
            print("🎲 Marker shuffle mode: Moving to previous marker in queue")
            appModel.shuffleToPreviousMarker()
            
            // Update button icons to reflect current mode
            updateButtonsForShuffleMode()
            
            // Provide haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            return
        }
        
        // Fallback to performer jump mode
        print("🎭 Performer jump mode: Finding scene with same performer")
        
        // Find current scene and get its performers
        guard let currentScene = scenes.first(where: { $0.id == currentSceneID }),
              !currentScene.performers.isEmpty else {
            print("⚠️ No performers found for current scene")
            return
        }
        
        // Get the first performer from the scene
        if let performer = currentScene.performers.first {
            // Directly jump to a random scene with the same performer
            jumpToPerformerScenes(performer: performer)
            
            // Provide haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }
    
    private func jumpToPerformerScenes(performer: StashScene.Performer) {
        // Navigate to a different scene with the selected performer
        // Filter scenes that contain this performer
        let performerScenes = scenes.filter { scene in
            scene.performers.contains { $0.id == performer.id }
        }
        
        if performerScenes.isEmpty {
            print("⚠️ No other scenes found with performer \(performer.name)")
            return
        }
        
        // Get a random scene with this performer (excluding current scene)
        let otherScenes = performerScenes.filter { $0.id != currentSceneID }
        guard let randomScene = otherScenes.randomElement() ?? performerScenes.first else { return }
        
        if let nextUrl = URL(string: randomScene.paths.stream) {
            // Create a new player item for the next scene
            let playerItem = AVPlayerItem(url: nextUrl)
            
            // Replace the current item with the new one
            if let currentPlayer = player {
                // Save progress for current scene before switching
                if let currentTime = currentPlayer.currentItem?.currentTime().seconds {
                    UserDefaults.standard.setVideoProgress(currentTime, for: currentSceneID)
                }
                
                // Ensure current audio is stopped to prevent stacking
                if currentPlayer.timeControlStatus == .playing {
                    print("⏸️ Pausing current player to prevent audio stacking")
                    currentPlayer.pause()
                    
                    // Post notification to ensure proper cleanup
                    if let currentItem = currentPlayer.currentItem {
                        NotificationCenter.default.post(
                            name: AVPlayerItem.didPlayToEndTimeNotification,
                            object: currentItem
                        )
                    }
                }
                
                // Update current scene ID
                currentSceneID = randomScene.id
                
                // IMPORTANT: Update the app model's scene list to include this scene at the beginning
                // This ensures that when the user hits the "next" button, it will work properly
                if !self.appModel.api.scenes.isEmpty {
                    print("📋 SHUFFLE BUTTON: Updating app model scene list for sequential navigation")
                    
                    // If the scene is already in the list somewhere, move it to the front
                    if let existingIndex = self.appModel.api.scenes.firstIndex(where: { $0.id == randomScene.id }) {
                        self.appModel.api.scenes.remove(at: existingIndex)
                        self.appModel.api.scenes.insert(randomScene, at: 0)
                        print("📋 SHUFFLE BUTTON: Moved scene to front of list for sequential navigation")
                    } else {
                        // If not in list, add it to the front
                        self.appModel.api.scenes.insert(randomScene, at: 0)
                        print("📋 SHUFFLE BUTTON: Added scene to front of list for sequential navigation")
                    }
                }
                
                // Update player with new content
                currentPlayer.replaceCurrentItem(with: playerItem)
                
                // Wait a short moment before starting playback to ensure clean audio transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    currentPlayer.play()
                    
                    // Hide any settings buttons that might have appeared after content change
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.hideSettingsButtons()
                    }
                }
                
                print("🔄 Switched to scene: \(randomScene.title ?? "Untitled") with performer: \(performer.name)")
            } else {
                // Fallback if player is nil - create and present a new player
                dismiss(animated: true) {
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootViewController = window.rootViewController {
                        
                        let nextIndex = self.scenes.firstIndex(where: { $0.id == randomScene.id }) ?? 0
                        let nextPlayer = CustomVideoPlayer(
                            scenes: self.scenes,
                            currentIndex: nextIndex,
                            sceneID: randomScene.id,
                            appModel: self.appModel
                        )
                        nextPlayer.player = AVPlayer(url: nextUrl)
                        rootViewController.present(nextPlayer, animated: true)
                    }
                }
            }
        }
    }
    
    @objc private func handleShuffleButtonTapped() {
        // Debug current shuffle state
        print("🎲 SHUFFLE BUTTON TAPPED - Debug info:")
        print("🎲 isMarkerShuffleMode: \(appModel.isMarkerShuffleMode)")
        print("🎲 markerShuffleQueue.count: \(appModel.markerShuffleQueue.count)")
        print("🎲 currentShuffleIndex: \(appModel.currentShuffleIndex)")
        
        // Check if we're in marker shuffle mode
        if appModel.isMarkerShuffleMode && !appModel.markerShuffleQueue.isEmpty {
            print("🎲 ✅ Marker shuffle mode: Moving to next marker in queue")
            appModel.shuffleToNextMarker()
            
            // Update button icons to reflect current mode
            updateButtonsForShuffleMode()
            
            // Provide haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            return
        }
        
        // Fallback to scene shuffle mode
        print("🎲 ❌ NOT in marker shuffle mode - using scene shuffle mode")
        
        // Play a random scene from the entire collection
        guard !scenes.isEmpty else { return }
        
        // Get a random scene (excluding current scene)
        let otherScenes = scenes.filter { $0.id != currentSceneID }
        guard let randomScene = otherScenes.randomElement() ?? scenes.first else { return }
        
        if let nextUrl = URL(string: randomScene.paths.stream) {
            // Create a new player item for the next scene
            let playerItem = AVPlayerItem(url: nextUrl)
            
            // Replace the current item with the new one
            if let currentPlayer = player {
                // Save progress for current scene before switching
                if let currentTime = currentPlayer.currentItem?.currentTime().seconds {
                    UserDefaults.standard.setVideoProgress(currentTime, for: currentSceneID)
                }
                
                // Ensure current audio is stopped to prevent stacking
                if currentPlayer.timeControlStatus == .playing {
                    print("⏸️ Pausing current player to prevent audio stacking")
                    currentPlayer.pause()
                    
                    // Post notification to ensure proper cleanup
                    if let currentItem = currentPlayer.currentItem {
                        NotificationCenter.default.post(
                            name: AVPlayerItem.didPlayToEndTimeNotification,
                            object: currentItem
                        )
                    }
                }
                
                // Update current scene ID
                currentSceneID = randomScene.id
                
                // IMPORTANT: Update the app model's scene list to include this scene at the beginning
                // This ensures that when the user hits the "next" button, it will work properly
                if !self.appModel.api.scenes.isEmpty {
                    print("📋 SHUFFLE BUTTON: Updating app model scene list for sequential navigation")
                    
                    // If the scene is already in the list somewhere, move it to the front
                    if let existingIndex = self.appModel.api.scenes.firstIndex(where: { $0.id == randomScene.id }) {
                        self.appModel.api.scenes.remove(at: existingIndex)
                        self.appModel.api.scenes.insert(randomScene, at: 0)
                        print("📋 SHUFFLE BUTTON: Moved scene to front of list for sequential navigation")
                    } else {
                        // If not in list, add it to the front
                        self.appModel.api.scenes.insert(randomScene, at: 0)
                        print("📋 SHUFFLE BUTTON: Added scene to front of list for sequential navigation")
                    }
                }
                
                // Update player with new content
                currentPlayer.replaceCurrentItem(with: playerItem)
                
                // Wait a short moment before starting playback to ensure clean audio transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    currentPlayer.play()
                    
                    // Hide any settings buttons that might have appeared after content change
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.hideSettingsButtons()
                    }
                }
                
                // Provide haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                
                print("🔄 Shuffled to scene: \(randomScene.title ?? "Untitled")")
            } else {
                // Fallback if player is nil - create and present a new player
                dismiss(animated: true) {
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootViewController = window.rootViewController {
                        
                        let nextIndex = self.scenes.firstIndex(where: { $0.id == randomScene.id }) ?? 0
                        let nextPlayer = CustomVideoPlayer(
                            scenes: self.scenes,
                            currentIndex: nextIndex,
                            sceneID: randomScene.id,
                            appModel: self.appModel
                        )
                        nextPlayer.player = AVPlayer(url: nextUrl)
                        rootViewController.present(nextPlayer, animated: true)
                    }
                }
            }
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
        
        // Intercept and override the default AVPlayer arrow key behavior
        switch key.keyCode {
        case .keyboardLeftArrow:
            print("🎹 Overriding AVPlayer: ← - Seek backward 30 seconds (was 15)")
            seekVideo(by: -30)
            return // Don't call super to prevent default 15-second behavior
            
        case .keyboardRightArrow:
            print("🎹 Overriding AVPlayer: → - Seek forward 30 seconds (was 15)")
            seekVideo(by: 30)
            return // Don't call super to prevent default 15-second behavior
            
        case .keyboardV:
            print("🎹 Keyboard shortcut: V - Next Scene")
            handleShuffleButtonTapped()
            
        case .keyboardB:
            print("🎹 Keyboard shortcut: B - Seek backward 30 seconds")
            seekVideo(by: -30)
            
        case .keyboardN:
            print("🎹 Keyboard shortcut: N - Random position jump")
            handleRandomJumpButtonTapped()
            
        case .keyboardM:
            print("🎹 Keyboard shortcut: M - Performer random scene")
            handlePerformerJumpButtonTapped()
            
        case .keyboardComma:
            print("🎹 Keyboard shortcut: < - Library random shuffle (using performer jump)")
            handlePerformerJumpButtonTapped()
            
        case .keyboardSpacebar:
            print("🎹 Keyboard shortcut: Space - Toggle play/pause")
            togglePlayPause()
            
        default:
            super.pressesBegan(presses, with: event)
        }
    }
    
    /// Seek video forward or backward by specified seconds
    private func seekVideo(by seconds: Double) {
        guard let currentPlayer = player,
              let currentItem = currentPlayer.currentItem else {
            print("⚠️ Cannot seek - player or item not available")
            return
        }
        
        let currentTime = currentItem.currentTime()
        let targetTime = CMTimeAdd(currentTime, CMTime(seconds: seconds, preferredTimescale: 1000))
        
        // Ensure we don't seek before the beginning or past the end
        let duration = currentItem.duration
        let zeroTime = CMTime.zero
        
        if duration.isValid && !duration.seconds.isNaN {
            if targetTime.seconds < 0 {
                currentPlayer.seek(to: zeroTime, toleranceBefore: .zero, toleranceAfter: .zero)
                print("⏱ Seeking to beginning of video")
                return
            } else if targetTime.seconds > duration.seconds {
                currentPlayer.seek(to: duration, toleranceBefore: .zero, toleranceAfter: .zero)
                print("⏱ Seeking to end of video")
                return
            }
        }
        
        print("⏱ Seeking by \(seconds) seconds to \(targetTime.seconds)")
        currentPlayer.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { success in
            if success {
                print("✅ Successfully seeked by \(seconds) seconds")
                
                // Provide haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                
                // Ensure playback continues
                if currentPlayer.timeControlStatus != .playing {
                    currentPlayer.play()
                }
            } else {
                print("❌ Seek operation failed")
            }
        }
    }
    
    /// Toggle play/pause state
    private func togglePlayPause() {
        guard let currentPlayer = player else {
            print("⚠️ Cannot toggle play/pause - player not found")
            return
        }
        
        if currentPlayer.timeControlStatus == .playing {
            currentPlayer.pause()
            print("⏸️ Paused playback")
        } else {
            currentPlayer.play()
            print("▶️ Resumed playback")
        }
        
        // Provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}