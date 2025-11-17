import AVKit
import SwiftUI
import UIKit

class CustomVideoPlayer: AVPlayerViewController, UIGestureRecognizerDelegate {
  // MARK: - Properties
  private var scenes: [StashScene] = []
  private var currentIndex: Int = 0
  private var currentSceneID: String = ""
  private var appModel: AppModel

  // Timer for continuously checking and hiding settings buttons
  private var settingsCheckTimer: Timer?

  // MARK: - Aspect Ratio Correction
  private var originalVideoGravity: AVLayerVideoGravity = .resizeAspect

  // MARK: - Aspect Mode
  private enum AspectMode: Int, CaseIterable {
    case original  // Whatever the system/player started with
    case fit  // Letterbox, preserve aspect
    case fill  // Fill, may crop
    case stretch  // Stretch to fill (not recommended, but available)
  }
  private var currentAspectMode: AspectMode = .original

  // MARK: - Custom Buttons
  private var randomJumpButton: UIButton!
  private var performerJumpButton: UIButton!
  private var shuffleButton: UIButton!
  private var reshuffleButton: UIButton!

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
    randomJumpButton.accessibilityLabel = "Random jump to position in video"
    randomJumpButton.accessibilityHint = "Jumps to a random position in the current video"
    randomJumpButton.addTarget(
      self, action: #selector(handleRandomJumpButtonTapped), for: .touchUpInside)

    performerJumpButton = UIButton(type: .system)
    performerJumpButton.setImage(UIImage(systemName: "person.crop.circle"), for: .normal)
    performerJumpButton.tintColor = .white
    performerJumpButton.accessibilityLabel = "Jump to performer scene"
    performerJumpButton.accessibilityHint = "Plays a random scene with the same performer"
    performerJumpButton.addTarget(
      self, action: #selector(handlePerformerJumpButtonTapped), for: .touchUpInside)

    shuffleButton = UIButton(type: .system)
    shuffleButton.setImage(UIImage(systemName: "shuffle"), for: .normal)
    shuffleButton.tintColor = .white
    shuffleButton.accessibilityLabel = "Shuffle to next scene"
    shuffleButton.accessibilityHint = "Plays a random scene from the library"
    shuffleButton.addTarget(self, action: #selector(handleShuffleButtonTapped), for: .touchUpInside)

    reshuffleButton = UIButton(type: .system)
    reshuffleButton.setImage(UIImage(systemName: "shuffle.circle.fill"), for: .normal)
    reshuffleButton.tintColor = .systemBlue
    reshuffleButton.accessibilityLabel = "Re-shuffle marker queue"
    reshuffleButton.accessibilityHint = "Randomizes the order of markers in the shuffle queue"
    reshuffleButton.addTarget(
      self, action: #selector(handleReshuffleButtonTapped), for: .touchUpInside)
    reshuffleButton.isHidden = true  // Hidden by default, only shown in marker shuffle mode

    // Buttons will be added in viewDidAppear
  }

  /// Update button icons based on current shuffle mode
  private func updateButtonsForShuffleMode() {
    if appModel.isMarkerShuffleMode && appModel.markerShuffleQueue.count > 1 {
      // In marker shuffle mode: Previous | Random Jump | Next | Reshuffle
      performerJumpButton.setImage(UIImage(systemName: "backward.fill"), for: .normal)
      shuffleButton.setImage(UIImage(systemName: "forward.fill"), for: .normal)

      // Update accessibility labels for shuffle mode
      performerJumpButton.accessibilityLabel = "Previous marker in shuffle queue"
      performerJumpButton.accessibilityHint = "Go to the previous marker in the shuffle"
      shuffleButton.accessibilityLabel = "Next marker in shuffle queue"
      shuffleButton.accessibilityHint = "Go to the next marker in the shuffle"

      // Update button colors to indicate shuffle mode
      performerJumpButton.tintColor = .systemOrange
      shuffleButton.tintColor = .systemOrange
      randomJumpButton.tintColor = .white

      // Show reshuffle button only in marker shuffle mode with multiple markers
      reshuffleButton.isHidden = false
      print(
        "🔀 Reshuffle button now visible - marker shuffle mode with \(appModel.markerShuffleQueue.count) markers"
      )
    } else {
      // Normal mode: Performer Jump | Random Jump | Scene Shuffle
      performerJumpButton.setImage(UIImage(systemName: "person.crop.circle"), for: .normal)
      shuffleButton.setImage(UIImage(systemName: "shuffle"), for: .normal)

      // Reset accessibility labels to normal mode
      performerJumpButton.accessibilityLabel = "Jump to performer scene"
      performerJumpButton.accessibilityHint = "Plays a random scene with the same performer"
      shuffleButton.accessibilityLabel = "Shuffle to next scene"
      shuffleButton.accessibilityHint = "Plays a random scene from the library"

      // Reset to normal colors
      performerJumpButton.tintColor = .white
      shuffleButton.tintColor = .white
      randomJumpButton.tintColor = .white

      // Hide reshuffle button in normal mode
      reshuffleButton.isHidden = true
      print("🔀 Reshuffle button now hidden - not in marker shuffle mode")
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    // Ensure we can become first responder immediately when the view appears
    becomeFirstResponder()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)

    // Invalidate timer to prevent leaks
    settingsCheckTimer?.invalidate()
    settingsCheckTimer = nil

    // Invalidate display link to prevent CPU/battery drain
    if let displayLink = objc_getAssociatedObject(self, "displayLinkKey") as? CADisplayLink {
      displayLink.invalidate()
      objc_setAssociatedObject(self, "displayLinkKey", nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    // Make this view controller the first responder to receive keyboard events
    becomeFirstResponder()

    // Use a delayed call to ensure first responder status is maintained
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      if !self.isFirstResponder {
        print("🎹 Video player was not first responder, forcing focus")
        self.becomeFirstResponder()
      }
    }

    // Find the transport controls container view
    if let contentOverlayView = self.contentOverlayView {
      // Configure buttons
      configureButton(randomJumpButton, inView: contentOverlayView, position: .left)
      configureButton(performerJumpButton, inView: contentOverlayView, position: .center)
      configureButton(shuffleButton, inView: contentOverlayView, position: .right)

      // Configure reshuffle button above center button
      configureReshuffleButton(reshuffleButton, inView: contentOverlayView)

      // Update button icons based on shuffle mode
      print("🎲 VideoPlayer viewDidAppear - checking shuffle mode...")
      print("🎲 isMarkerShuffleMode: \(appModel.isMarkerShuffleMode)")
      print("🎲 markerShuffleQueue.count: \(appModel.markerShuffleQueue.count)")
      updateButtonsForShuffleMode()

      // Start with buttons visible
      randomJumpButton.alpha = 1.0
      performerJumpButton.alpha = 1.0
      shuffleButton.alpha = 1.0
      reshuffleButton.alpha = 1.0

      // Hide buttons on video start with a 5-second delay
      player?.addObserver(self, forKeyPath: "timeControlStatus", options: [.new], context: nil)

      // Also observe currentItem changes to catch when content changes
      player?.addObserver(self, forKeyPath: "currentItem", options: [.new, .old], context: nil)

      // Add tap gesture to show/hide buttons
      let tapGesture = UITapGestureRecognizer(
        target: self, action: #selector(toggleButtonVisibility))
      contentOverlayView.addGestureRecognizer(tapGesture)

      // Add pan gesture for swipe-like seeking to multiple views
      let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture))
      panGesture.delegate = self
      panGesture.maximumNumberOfTouches = 1
      panGesture.cancelsTouchesInView = false
      contentOverlayView.addGestureRecognizer(panGesture)

      // Also add to main view
      let panGestureMain = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture))
      panGestureMain.delegate = self
      panGestureMain.maximumNumberOfTouches = 1
      panGestureMain.cancelsTouchesInView = false
      view.addGestureRecognizer(panGestureMain)

      print(
        "👆 Added pan gestures for swipe seeking: left = seek back 10s, right = seek forward 10s")

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
    settingsCheckTimer?.invalidate()  // Ensure we don't have multiple timers
    settingsCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
      [weak self] _ in
      self?.hideSettingsButtons()
    }

    // Check and apply aspect ratio correction
    applyAspectRatioCorrection()

    // Start playback automatically
    player?.play()
  }

  private func startObservingLayerChanges() {
    // Set up a CADisplayLink to watch for layer changes that might indicate controls being added
    let displayLink = CADisplayLink(target: self, selector: #selector(checkForNewControls))
    displayLink.add(to: .main, forMode: .common)

    // Store the display link so we can invalidate it later
    objc_setAssociatedObject(
      self, "displayLinkKey", displayLink, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
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
        if button === randomJumpButton || button === performerJumpButton || button === shuffleButton
          || button === reshuffleButton
        {
          continue
        }
        // Check for settings buttons based on various attributes
        if let accessLabel = button.accessibilityLabel?.lowercased(),
          accessLabel.contains("sett") || accessLabel.contains("gear")
            || accessLabel.contains("config") || accessLabel.contains("option")
            || accessLabel.contains("filter") || accessLabel.contains("preferences")
            || accessLabel.contains("more")
        {
          // Hide known settings/gear buttons
          button.isHidden = true
          print("🔧 Found and hidden settings button: \(accessLabel)")
        }

        // Hide any small circular buttons in the corners which are likely settings
        if button.bounds.width < 50 && button.bounds.height < 50
          && (button.layer.cornerRadius > 10
            || button.layer.cornerRadius == button.bounds.width / 2)
        {
          button.isHidden = true
          print("🔧 Hidden small circular button that may be settings")
        }

        // Hide any button with an image (likely gear or filter icon)
        if button.image(for: .normal) != nil,
          button.bounds.width < 60
        {
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
      if !subview.subviews.isEmpty {
        if let accessID = subview.accessibilityIdentifier?.lowercased(),
          accessID.contains("menu") || accessID.contains("popup") || accessID.contains("settings")
            || accessID.contains("filter")
        {
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

    // Safely remove observers even if player is nil
    if let player = player {
      // Use try-catch to prevent crashes if observer wasn't added
      player.removeObserver(self, forKeyPath: "timeControlStatus", context: nil)
      player.removeObserver(self, forKeyPath: "currentItem", context: nil)
    }

    // Invalidate and clean up the settings check timer
    settingsCheckTimer?.invalidate()
    settingsCheckTimer = nil

    // Invalidate the display link
    if let displayLink = objc_getAssociatedObject(self, "displayLinkKey") as? CADisplayLink {
      displayLink.invalidate()
      objc_setAssociatedObject(self, "displayLinkKey", nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  // Monitor player status to auto-hide buttons when playback starts
  override func observeValue(
    forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
    context: UnsafeMutableRawPointer?
  ) {
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

  // MARK: - Pan Gesture Handler (for swipe-like seeking)

  @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
    switch gesture.state {
    case .began:
      print("👆 Pan gesture began")
    case .changed:
      let translation = gesture.translation(in: gesture.view)
    // Uncomment for detailed tracking: print("👆 Pan changed: x=\(translation.x), y=\(translation.y)")
    case .ended:
      let velocity = gesture.velocity(in: gesture.view)
      let translation = gesture.translation(in: gesture.view)

      print(
        "👆 Pan gesture ended - translation: x=\(translation.x), y=\(translation.y), velocity: x=\(velocity.x), y=\(velocity.y)"
      )

      // More lenient thresholds for detection
      let minDistance: CGFloat = 30  // Reduced from 50
      let minVelocity: CGFloat = 200  // Reduced from 500

      // Ensure horizontal movement is dominant
      let isHorizontalSwipe = abs(translation.x) > abs(translation.y)

      if isHorizontalSwipe && abs(translation.x) > minDistance && abs(velocity.x) > minVelocity {
        if translation.x > 0 {
          // Swipe right - seek forward
          print("👆 ✅ SWIPE RIGHT DETECTED (via pan) - seeking forward 10 seconds")
          seekVideo(by: 10)

          // Provide haptic feedback
          let generator = UIImpactFeedbackGenerator(style: .light)
          generator.impactOccurred()
        } else {
          // Swipe left - seek backward
          print("👆 ✅ SWIPE LEFT DETECTED (via pan) - seeking back 10 seconds")
          seekVideo(by: -10)

          // Provide haptic feedback
          let generator = UIImpactFeedbackGenerator(style: .light)
          generator.impactOccurred()
        }
      } else {
        print(
          "👆 Pan gesture didn't meet swipe criteria: isHorizontal=\(isHorizontalSwipe), distance=\(abs(translation.x)), velocity=\(abs(velocity.x))"
        )
      }
    case .cancelled, .failed:
      print("👆 Pan gesture cancelled/failed")
    default:
      break
    }
  }

  // MARK: - UIGestureRecognizerDelegate

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    // Allow pan gestures to work alongside other gestures
    print(
      "👆 Gesture recognizer simultaneous check: \(gestureRecognizer) with \(otherGestureRecognizer)"
    )
    return true
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch)
    -> Bool
  {
    // Make sure pan gestures can receive touches
    print(
      "👆 Gesture recognizer should receive touch: \(gestureRecognizer) at location: \(touch.location(in: gestureRecognizer.view))"
    )
    return true
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer, shouldBegin gesture: UIGestureRecognizer
  ) -> Bool {
    print("👆 Gesture recognizer should begin: \(gestureRecognizer)")
    return true
  }

  private enum ButtonPosition {
    case left, center, right
  }

  private func configureReshuffleButton(_ button: UIButton, inView contentView: UIView) {
    // Configure button appearance
    button.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(button)

    // Position button - adjust size for iPads
    let isIpad = UIDevice.current.userInterfaceIdiom == .pad
    let size: CGFloat = isIpad ? 50 : 38  // Slightly smaller than main buttons
    // Position above the random jump button (center)
    let yOffset: CGFloat = isIpad ? 280 : 200  // Higher up than main buttons

    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: size),
      button.heightAnchor.constraint(equalToConstant: size),
      button.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -yOffset),
    ])
  }

  private func configureButton(
    _ button: UIButton, inView contentView: UIView, position: ButtonPosition
  ) {
    // Configure button appearance
    button.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(button)

    // Position button - adjust size for iPads
    let isIpad = UIDevice.current.userInterfaceIdiom == .pad
    let padding: CGFloat = isIpad ? 60 : 30  // Increased padding to avoid conflict with controls
    let size: CGFloat = isIpad ? 60 : 44
    // Move buttons higher up to avoid conflict with native controls
    let yOffset: CGFloat = isIpad ? 200 : 140  // Increased distance from bottom

    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: size),
      button.heightAnchor.constraint(equalToConstant: size),
      button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -yOffset),
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
    let minPosition = max(5, duration * 0.1)  // Ensure at least 5 seconds from start
    let maxPosition = min(duration - 10, duration * 0.9)  // Ensure at least 10 seconds from end

    // Generate and log random position with more precision
    let randomPosition = Double.random(in: minPosition...maxPosition)
    let minutes = Int(randomPosition / 60)
    let seconds = Int(randomPosition) % 60

    print(
      "🎲 RANDOM JUMP: Generated position - \(randomPosition) seconds (\(minutes):\(String(format: "%02d", seconds)))"
    )
    print("🎲 RANDOM JUMP: Acceptable range was \(minPosition) to \(maxPosition) seconds")

    // Create time with higher precision timescale (was 600, now 1000)
    let time = CMTime(seconds: randomPosition, preferredTimescale: 1000)

    // Set tolerances to ensure more precise seeking
    let toleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 1000)
    let toleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 1000)

    print("🎲 RANDOM JUMP: Attempting to seek to position...")

    // Use the more precise seek method with tolerances
    currentPlayer.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter) {
      success in
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
      !currentScene.performers.isEmpty
    else {
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

    guard let stream = randomScene.paths.stream,
          let nextUrl = URL(string: stream) else {
      print("❌ Performer shuffle: No stream URL for scene \(randomScene.id)")
      return
    }

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
          if let existingIndex = self.appModel.api.scenes.firstIndex(where: {
            $0.id == randomScene.id
          }) {
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

          // Apply aspect ratio correction for the new content
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.applyAspectRatioCorrection()
          }

          // Hide any settings buttons that might have appeared after content change
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.hideSettingsButtons()
          }
        }

        print(
          "🔄 Switched to scene: \(randomScene.title ?? "Untitled") with performer: \(performer.name)"
        )
      } else {
        // Fallback if player is nil - create and present a new player
        dismiss(animated: true) {
          if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first,
            let rootViewController = window.rootViewController
          {
            let nextIndex = self.scenes.firstIndex { $0.id == randomScene.id } ?? 0
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

    guard let stream = randomScene.paths.stream,
          let nextUrl = URL(string: stream) else {
      print("❌ Scene shuffle: No stream URL for scene \(randomScene.id)")
      return
    }

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
          if let existingIndex = self.appModel.api.scenes.firstIndex(where: {
            $0.id == randomScene.id
          }) {
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

          // Apply aspect ratio correction for the new content
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.applyAspectRatioCorrection()
          }

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
            let rootViewController = window.rootViewController
          {
            let nextIndex = self.scenes.firstIndex { $0.id == randomScene.id } ?? 0
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

  @objc private func handleReshuffleButtonTapped() {
    print("🔀 RESHUFFLE BUTTON TAPPED")

    // Only work in marker shuffle mode
    guard appModel.isMarkerShuffleMode && !appModel.markerShuffleQueue.isEmpty else {
      print("⚠️ Not in marker shuffle mode or queue is empty")
      return
    }

    print("🔀 Re-shuffling marker queue with \(appModel.markerShuffleQueue.count) markers")

    // Call the reshuffle function in AppModel
    appModel.reshuffleMarkerQueue()

    // Provide haptic feedback
    let generator = UIImpactFeedbackGenerator(style: .heavy)
    generator.impactOccurred()

    print("🔀 Queue re-shuffled successfully")
  }

  // MARK: - Aspect Ratio Correction

  /// Detects if the current video is anamorphic and needs aspect ratio correction
  private func isAnamorphicVideo() -> Bool {
    // Deprecated heuristic; relying on player-provided presentation size and aspect.
    return false
  }

  /// Applies aspect ratio correction for anamorphic content
  private func applyAspectRatioCorrection() {
    guard let playerLayer = findPlayerLayer(in: self.view.layer) else {
      print("🎥 ❌ Could not find AVPlayerLayer for aspect ratio correction (recursive)")
      return
    }

    // Always clear any previous transform to avoid accumulated distortion
    playerLayer.transform = CATransform3DIdentity

    // Store original gravity if not already captured
    originalVideoGravity = playerLayer.videoGravity

    switch currentAspectMode {
    case .original:
      playerLayer.videoGravity = originalVideoGravity
      print("🎥 Aspect mode: ORIGINAL (\(originalVideoGravity.rawValue))")
    case .fit:
      playerLayer.videoGravity = .resizeAspect
      print("🎥 Aspect mode: FIT (resizeAspect)")
    case .fill:
      playerLayer.videoGravity = .resizeAspectFill
      print("🎥 Aspect mode: FILL (resizeAspectFill)")
    case .stretch:
      playerLayer.videoGravity = .resize
      print("🎥 Aspect mode: STRETCH (resize)")
    }
  }

  /// Helper to recursively find AVPlayerLayer inside a CALayer hierarchy
  private func findPlayerLayer(in layer: CALayer) -> AVPlayerLayer? {
    if let playerLayer = layer as? AVPlayerLayer { return playerLayer }
    for sub in layer.sublayers ?? [] {
      if let found = findPlayerLayer(in: sub) { return found }
    }
    return nil
  }

  /// Applies a mathematical transform to correct anamorphic aspect ratio
  private func applyAnamorphicTransform(to playerLayer: AVPlayerLayer) {
    // Deprecated: We no longer apply custom transforms that can distort the image.
    // Aspect handling is controlled via `currentAspectMode` and `videoGravity` only.
    print("🎥 Deprecated anamorphic transform skipped")
  }

  /// Resets aspect ratio correction
  private func resetAspectRatioCorrection() {
    guard let playerLayer = findPlayerLayer(in: self.view.layer) else { return }

    currentAspectMode = .original
    playerLayer.videoGravity = originalVideoGravity
    playerLayer.transform = CATransform3DIdentity
    print("🎥 🔄 Reset aspect ratio to ORIGINAL (\(originalVideoGravity.rawValue))")
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
      return  // Don't call super to prevent default 15-second behavior

    case .keyboardRightArrow:
      print("🎹 Overriding AVPlayer: → - Seek forward 30 seconds (was 15)")
      seekVideo(by: 30)
      return  // Don't call super to prevent default 15-second behavior

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

    case .keyboardA:
      // Cycle aspect modes: Original -> Fit -> Fill -> Stretch -> Original
      if let next = AspectMode(
        rawValue: (currentAspectMode.rawValue + 1) % AspectMode.allCases.count)
      {
        currentAspectMode = next
        applyAspectRatioCorrection()
        // Provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
      }
      return

    default:
      super.pressesBegan(presses, with: event)
    }
  }

  /// Seek video forward or backward by specified seconds
  private func seekVideo(by seconds: Double) {
    guard let currentPlayer = player,
      let currentItem = currentPlayer.currentItem
    else {
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
