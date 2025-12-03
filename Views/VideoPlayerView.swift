import AVKit
import Combine
import SwiftUI
import UIKit

// Define a top-level custom view controller for AVPlayerViewController
class CustomPlayerViewController: UIViewController {
  let playerVC: AVPlayerViewController

  // Aspect ratio correction state
  private var originalVideoGravity: AVLayerVideoGravity = .resizeAspect
  private var isAspectRatioCorrected: Bool = false
  private var currentScene: StashScene?

  init(playerVC: AVPlayerViewController, scene: StashScene? = nil) {
    self.playerVC = playerVC
    self.currentScene = scene
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    // Add the player view controller as a child
    addChild(playerVC)
    view.addSubview(playerVC.view)
    playerVC.view.frame = view.bounds
    playerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    playerVC.didMove(toParent: self)

    // Add pan gesture for swipe seeking
    setupSwipeGestures()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    // Make this view controller the first responder to intercept keyboard events
    becomeFirstResponder()

    print("🎬 CustomPlayerViewController viewDidAppear - setting up additional gestures")

    // Add gestures with delay to ensure view hierarchy is ready
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      self.setupAdditionalGestures()
      self.hideGearButton(in: self.playerVC.view)
    }
  }

  override var canBecomeFirstResponder: Bool {
    return true
  }

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    guard let key = presses.first?.key else {
      super.pressesBegan(presses, with: event)
      return
    }

    // Override default AVPlayer arrow key behavior (15s -> 30s)
    switch key.keyCode {
    case .keyboardLeftArrow:
      print("🎹 Overriding AVPlayer default: ← - Seek backward 30 seconds (was 15)")
      seekVideo(by: -30)
      return  // Don't call super to prevent default behavior

    case .keyboardRightArrow:
      print("🎹 Overriding AVPlayer default: → - Seek forward 30 seconds (was 15)")
      seekVideo(by: 30)
      return  // Don't call super to prevent default behavior

    // Number keys for percentage seeking
    case .keyboard1:
      print("🎹 Number key 1 - Seek to 10%")
      seekToPercentage(10)
      return

    case .keyboard2:
      print("🎹 Number key 2 - Seek to 20%")
      seekToPercentage(20)
      return

    case .keyboard3:
      print("🎹 Number key 3 - Seek to 30%")
      seekToPercentage(30)
      return

    case .keyboard4:
      print("🎹 Number key 4 - Seek to 40%")
      seekToPercentage(40)
      return

    case .keyboard5:
      print("🎹 Number key 5 - Seek to 50%")
      seekToPercentage(50)
      return

    case .keyboard6:
      print("🎹 Number key 6 - Seek to 60%")
      seekToPercentage(60)
      return

    case .keyboard7:
      print("🎹 Number key 7 - Seek to 70%")
      seekToPercentage(70)
      return

    case .keyboard8:
      print("🎹 Number key 8 - Seek to 80%")
      seekToPercentage(80)
      return

    case .keyboard9:
      print("🎹 Number key 9 - Seek to 90%")
      seekToPercentage(90)
      return

    case .keyboard0:
      print("🎹 Number key 0 - Seek to 95%")
      seekToPercentage(95)
      return

    case .keyboardA:
      print("🎹 A key - Toggle aspect ratio correction")
      toggleAspectRatio()
      return

    default:
      super.pressesBegan(presses, with: event)
    }
  }

  private func seekVideo(by seconds: Double) {
    guard let player = playerVC.player,
      let currentItem = player.currentItem
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
        player.seek(to: zeroTime, toleranceBefore: .zero, toleranceAfter: .zero)
        print("⏱ Seeking to beginning of video")
        return
      } else if targetTime.seconds > duration.seconds {
        player.seek(to: duration, toleranceBefore: .zero, toleranceAfter: .zero)
        print("⏱ Seeking to end of video")
        return
      }
    }

    print("⏱ Seeking by \(seconds) seconds to \(targetTime.seconds)")
    player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { success in
      if success {
        print("✅ Successfully seeked by \(seconds) seconds")

        // Provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Ensure playback continues
        if player.timeControlStatus != .playing {
          player.play()
        }
      } else {
        print("❌ Seek operation failed")
      }
    }
  }

  private func seekToPercentage(_ percentage: Double) {
    guard let player = playerVC.player,
      let currentItem = player.currentItem
    else {
      print("⚠️ Cannot seek to percentage - player or item not available")
      return
    }

    let duration = currentItem.duration
    guard duration.isValid && !duration.seconds.isNaN && duration.seconds > 0 else {
      print("⚠️ Cannot seek to percentage - invalid duration")
      return
    }

    let targetSeconds = duration.seconds * (percentage / 100.0)
    let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 1000)

    print(
      "⏱ Seeking to \(percentage)% (\(targetSeconds) seconds) of video duration \(duration.seconds)"
    )

    player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { success in
      if success {
        print("✅ Successfully seeked to \(percentage)% of video")

        // Provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Ensure playback continues
        if player.timeControlStatus != .playing {
          player.play()
        }
      } else {
        print("❌ Seek to \(percentage)% operation failed")
      }
    }
  }

  func hideGearButton(in view: UIView) {
    // For debugging purposes, check if we have a button
    for subview in view.subviews {
      if let button = subview as? UIButton {
        // Check if this might be the gear button based on image or accessibility label
        if button.accessibilityLabel?.lowercased().contains("setting") == true {
          button.isHidden = true
          print("🔧 Found and hid a settings button")
        }
      }

      // Recursively search through subviews
      hideGearButton(in: subview)
    }
  }

  // MARK: - Swipe Gesture Setup

  private func setupSwipeGestures() {
    // Add pan gesture for swipe-like seeking
    let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture))
    panGesture.maximumNumberOfTouches = 1
    panGesture.cancelsTouchesInView = false
    view.addGestureRecognizer(panGesture)

    print("👆 Added pan gesture for swipe seeking: left = seek back 10s, right = seek forward 10s")
  }

  private func setupAdditionalGestures() {
    print("🎬 Setting up additional gestures with delay...")

    // Add pan gesture directly to player view
    let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture))
    panGesture.maximumNumberOfTouches = 1
    panGesture.cancelsTouchesInView = false
    playerVC.view.addGestureRecognizer(panGesture)

    // Also try adding to content overlay view if it exists
    if let contentOverlay = playerVC.contentOverlayView {
      let panGesture2 = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture))
      panGesture2.maximumNumberOfTouches = 1
      panGesture2.cancelsTouchesInView = false
      contentOverlay.addGestureRecognizer(panGesture2)
      print("👆 Added pan gesture to contentOverlayView")
    }

    print("👆 Added additional pan gestures to player views")
  }

  @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
    switch gesture.state {
    case .began:
      print("👆 🟢 Pan gesture BEGAN")
    case .changed:
      // Uncomment for detailed tracking:
      // let translation = gesture.translation(in: gesture.view)
      // print("👆 Pan changed: x=\(translation.x)")
      break
    case .ended:
      let velocity = gesture.velocity(in: gesture.view)
      let translation = gesture.translation(in: gesture.view)

      print(
        "👆 🔴 Pan gesture ENDED - translation: x=\(translation.x), y=\(translation.y), velocity: x=\(velocity.x), y=\(velocity.y)"
      )

      // Very lenient thresholds for detection
      let minDistance: CGFloat = 20  // Reduced from 30
      let minVelocity: CGFloat = 100  // Reduced from 200

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
        print("👆 ❌ Pan gesture didn't meet swipe criteria:")
        print("   isHorizontal: \(isHorizontalSwipe)")
        print("   distance: \(abs(translation.x)) (min: \(minDistance))")
        print("   velocity: \(abs(velocity.x)) (min: \(minVelocity))")
      }
    case .cancelled:
      print("👆 🟡 Pan gesture CANCELLED")
    case .failed:
      print("👆 🔴 Pan gesture FAILED")
    default:
      break
    }
  }

  // MARK: - Aspect Ratio Correction

  /// Toggles aspect ratio correction for anamorphic content
  func toggleAspectRatio() {
    print("🎥 CustomPlayerViewController: Toggle aspect ratio")
    print("🎥 DEBUG: Current videoGravity = \(playerVC.videoGravity)")

    // Cycle through different video gravity modes + Smart Fill
    switch playerVC.videoGravity {
    case .resizeAspect:
      playerVC.videoGravity = .resizeAspectFill
      print("🎥 Switched to Aspect Fill (crops to fill screen)")
    case .resizeAspectFill:
      playerVC.videoGravity = .resize
      print("🎥 Switched to Fill Screen (stretches to fit)")
    case .resize:
      // Smart Fill mode - intelligently choose best fit with minimal bars
      applySmartFill()
    default:
      playerVC.videoGravity = .resizeAspect
      print("🎥 Reset to Aspect Fit (maintains proportions)")
    }

    print("🎥 DEBUG: New videoGravity = \(playerVC.videoGravity)")

    // Provide haptic feedback
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.impactOccurred()
  }

  /// Smart Fill mode - intelligently chooses between aspect fit/fill for minimal black bars
  private func applySmartFill() {
    guard let player = playerVC.player,
      let currentItem = player.currentItem
    else {
      print("🎥 Smart Fill: No player or item available, using Aspect Fit")
      playerVC.videoGravity = .resizeAspect
      return
    }

    // Get video dimensions
    let videoSize = currentItem.presentationSize
    guard videoSize.width > 0 && videoSize.height > 0 else {
      print("🎥 Smart Fill: Invalid video dimensions, using Aspect Fit")
      playerVC.videoGravity = .resizeAspect
      return
    }

    // Get screen dimensions
    let screenSize = UIScreen.main.bounds.size
    let videoAspectRatio = videoSize.width / videoSize.height
    let screenAspectRatio = screenSize.width / screenSize.height

    // Detect common aspect ratios for better handling
    let videoRatioString = getAspectRatioString(videoAspectRatio)
    let screenRatioString = getAspectRatioString(screenAspectRatio)

    print("🎥 Smart Fill Analysis:")
    print("📱 Screen: \(screenSize.width) x \(screenSize.height) (\(screenRatioString))")
    print("🎬 Video: \(videoSize.width) x \(videoSize.height) (\(videoRatioString))")

    // Calculate how much black bar area each mode would create
    let aspectFitBars = abs(videoAspectRatio - screenAspectRatio) / screenAspectRatio
    let aspectFillCrop = abs(screenAspectRatio - videoAspectRatio) / videoAspectRatio

    // Special handling for common problematic aspect ratios
    if videoRatioString.contains("4:3") && !screenRatioString.contains("4:3") {
      // 4:3 video on modern screen - usually better with aspect fit
      playerVC.videoGravity = .resizeAspect
      print("🎥 Smart Fill: 4:3 video detected, using Aspect Fit for best viewing")
    } else if videoRatioString.contains("16:10") {
      // 16:10 videos often benefit from aspect fill on most modern screens
      playerVC.videoGravity = .resizeAspectFill
      print("🎥 Smart Fill: 16:10 video detected, using Aspect Fill for minimal bars")
    } else if aspectFitBars < 0.10 {  // Less than 10% black bar area
      playerVC.videoGravity = .resizeAspect
      print(
        "🎥 Smart Fill: Using Aspect Fit (minimal bars: \(String(format: "%.1f", aspectFitBars * 100))%)"
      )
    } else if aspectFillCrop < 0.20 {  // Less than 20% crop area
      playerVC.videoGravity = .resizeAspectFill
      print(
        "🎥 Smart Fill: Using Aspect Fill (crop: \(String(format: "%.1f", aspectFillCrop * 100))%)")
    } else {
      // For really mismatched ratios, use aspect fit
      playerVC.videoGravity = .resizeAspect
      print("🎥 Smart Fill: Extreme ratio mismatch, using Aspect Fit for best viewing")
    }
  }

  /// Helper function to get human-readable aspect ratio string
  private func getAspectRatioString(_ ratio: CGFloat) -> String {
    let tolerance: CGFloat = 0.02

    // Common aspect ratios
    if abs(ratio - 16.0 / 9.0) < tolerance { return "16:9" }
    if abs(ratio - 4.0 / 3.0) < tolerance { return "4:3" }
    if abs(ratio - 16.0 / 10.0) < tolerance { return "16:10" }
    if abs(ratio - 21.0 / 9.0) < tolerance { return "21:9" }
    if abs(ratio - 3.0 / 2.0) < tolerance { return "3:2" }
    if abs(ratio - 5.0 / 4.0) < tolerance { return "5:4" }
    if abs(ratio - 1.0) < tolerance { return "1:1" }

    // Return numeric ratio with 2 decimal places
    return String(format: "%.2f:1", ratio)
  }

  /// Detects if the current video is anamorphic and needs aspect ratio correction
  private func isAnamorphicVideo() -> Bool {
    // Get video dimensions from the current scene
    guard let currentScene = currentScene,
      let file = currentScene.files.first,
      let width = file.width,
      let height = file.height
    else {
      return false
    }

    print("🎥 Video dimensions: \(width)x\(height)")

    // Common anamorphic resolutions that should display as 16:9
    let anamorphicResolutions: [(width: Int, height: Int)] = [
      (1440, 1080),  // Most common anamorphic format
      (1920, 1440),  // 4:3 anamorphic that should be 16:9
      (960, 720),  // Smaller anamorphic format
      (720, 540)  // Even smaller anamorphic format
    ]

    // Check if current resolution matches any known anamorphic format
    let isAnamorphic = anamorphicResolutions.contains { res in
      width == res.width && height == res.height
    }

    if isAnamorphic {
      print("🎥 ✅ Detected anamorphic video: \(width)x\(height) - will correct to 16:9 aspect ratio")
    } else {
      print("🎥 ⚪ Standard video: \(width)x\(height) - no correction needed")
    }

    return isAnamorphic
  }

  /// Applies aspect ratio correction for anamorphic content
  private func applyAspectRatioCorrection() {
    guard
      let playerLayer = playerVC.view.layer.sublayers?.compactMap({ $0 as? AVPlayerLayer }).first
    else {
      print("🎥 ❌ Could not find AVPlayerLayer for aspect ratio correction")
      return
    }

    // Store original video gravity
    originalVideoGravity = playerLayer.videoGravity

    if isAnamorphicVideo() {
      // For anamorphic content, use aspect fill to stretch the video to fill the screen properly
      playerLayer.videoGravity = .resizeAspectFill
      print("🎥 ✅ Applied aspect ratio correction: changed videoGravity to resizeAspectFill")

      // Apply additional transform to correct the aspect ratio mathematically
      applyAnamorphicTransform(to: playerLayer)
    } else {
      // For standard content, ensure we use the default behavior
      playerLayer.videoGravity = .resizeAspect
      print("🎥 ⚪ Using standard aspect ratio for non-anamorphic content")
    }

    isAspectRatioCorrected = true
  }

  /// Applies a mathematical transform to correct anamorphic aspect ratio
  private func applyAnamorphicTransform(to playerLayer: AVPlayerLayer) {
    // Get video dimensions
    guard let currentScene = currentScene,
      let file = currentScene.files.first,
      let width = file.width,
      let height = file.height
    else {
      return
    }

    // Calculate the correction factor needed
    let currentAspectRatio = Double(width) / Double(height)
    let targetAspectRatio = 16.0 / 9.0  // Target 16:9 aspect ratio

    // For 1440x1080 (4:3), we need to stretch horizontally to achieve 16:9
    let correctionFactor = targetAspectRatio / currentAspectRatio

    print("🎥 Transform calculation:")
    print("  Current aspect ratio: \(currentAspectRatio) (\(width)x\(height))")
    print("  Target aspect ratio: \(targetAspectRatio) (16:9)")
    print("  Correction factor: \(correctionFactor)")

    // Apply transform to stretch the video horizontally
    let transform = CATransform3DMakeScale(correctionFactor, 1.0, 1.0)
    playerLayer.transform = transform

    print("🎥 ✅ Applied anamorphic transform with horizontal scale: \(correctionFactor)")
  }

  /// Resets aspect ratio correction
  private func resetAspectRatioCorrection() {
    guard
      let playerLayer = playerVC.view.layer.sublayers?.compactMap({ $0 as? AVPlayerLayer }).first
    else {
      return
    }

    playerLayer.videoGravity = originalVideoGravity
    playerLayer.transform = CATransform3DIdentity
    isAspectRatioCorrected = false
    print("🎥 🔄 Reset aspect ratio correction")
  }

  /// Updates the current scene for aspect ratio detection
  func updateScene(_ scene: StashScene) {
    currentScene = scene

    // Auto-apply aspect ratio correction if the video is anamorphic
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      if self.isAnamorphicVideo() && !self.isAspectRatioCorrected {
        print("🎥 Auto-applying aspect ratio correction for anamorphic video")
        self.applyAspectRatioCorrection()
      }
    }
  }
}

struct VideoPlayerView: View {
  let scene: StashScene
  var startTime: Double?
  var endTime: Double?
  @EnvironmentObject private var appModel: AppModel
  @Environment(\.dismiss) private var dismiss

  // Helper function to determine if a performer is likely female
  private func isLikelyFemalePerformer(_ performer: StashScene.Performer) -> Bool {
    // First check explicit gender
    if performer.gender == "FEMALE" {
      return true
    }

    // If gender is unknown or missing, use name-based heuristics for known male performers
    let knownMalePerformers = [
      "robby echo", "johnny sins", "danny d", "mike adriano", "ryan madison",
      "manuel ferrara", "charles dera", "van wylde", "chad white", "kyle mason",
      "scott nails", "jason luv", "richard mann", "lexington steele"
    ]

    let lowercaseName = performer.name.lowercased()

    // If it's a known male performer, return false
    if knownMalePerformers.contains(lowercaseName) {
      return false
    }

    // If gender is explicitly MALE, return false
    if performer.gender == "MALE" {
      return false
    }

    // For unknown gender, assume female (most performers in adult content are female)
    // This is a reasonable assumption since the user expects female performers by default
    return true
  }
  @State private var showVideoPlayer = false
  @State private var showControls = true  // Start with controls visible
  @State private var hideControlsTask: Task<Void, Never>?
  @State private var currentScene: StashScene
  @State private var effectiveStartTime: Double?
  @State private var effectiveEndTime: Double?
  // Store the original performer for the performer button
  @State private var originalPerformer: StashScene.Performer?
  // Store the current marker
  @State private var currentMarker: SceneMarker?
  // Track whether we're in random jump mode
  @State private var isRandomJumpMode: Bool = false
  // Track whether we're in marker shuffle mode
  @State private var isMarkerShuffleMode: Bool = false
  // Prevent rapid-fire performer shuffle calls
  @State private var isPerformerShuffleInProgress: Bool = false
  // Video loading timeout timer
  @State private var videoLoadingTimer: Timer?
  @State private var isVideoLoading: Bool = false
  @State private var isManualExit: Bool = false
  @FocusState private var isVideoPlayerFocused: Bool

  init(scene: StashScene, startTime: Double? = nil, endTime: Double? = nil) {
    self.scene = scene
    self.startTime = startTime
    self.endTime = endTime
    _currentScene = State(initialValue: scene)

    // Log important parameters for debugging
    print(
      "📱 VideoPlayerView init - scene: \(scene.id), startTime: \(String(describing: startTime)), endTime: \(String(describing: endTime))"
    )

    // Set effective start time directly in init if provided
    if let startTime = startTime {
      _effectiveStartTime = State(initialValue: startTime)
      print("⏱ Setting effectiveStartTime directly to \(startTime) in init")
    }

    // Set effective end time directly in init if provided
    if let endTime = endTime {
      _effectiveEndTime = State(initialValue: endTime)
      print("⏱ Setting effectiveEndTime directly to \(endTime) in init")
    }

    // Initialize the original performer with female preference
    let femalePerformer = scene.performers.first { isLikelyFemalePerformer($0) }
    let selectedPerformer = femalePerformer ?? scene.performers.first
    if let selectedPerformer = selectedPerformer {
      print(
        "📱 Initializing original performer to: \(selectedPerformer.name) (ID: \(selectedPerformer.id), gender: \(selectedPerformer.gender ?? "unknown"))"
      )
      _originalPerformer = State(initialValue: selectedPerformer)
    }
  }

  var body: some View {
    GeometryReader { _ in
      ZStack {
        // Background color
        Color.black.ignoresSafeArea()

        // Full screen video player
        FullScreenVideoPlayer(
          url: getStreamURL(),  // Use custom method to get stream URL
          startTime: effectiveStartTime,
          endTime: effectiveEndTime,
          scenes: appModel.api.scenes,
          currentIndex: appModel.api.scenes.firstIndex(of: currentScene) ?? 0,
          appModel: appModel
        )
        .ignoresSafeArea()
        .onAppear {
          print(
            "📱 FullScreenVideoPlayer appeared with startTime: \(String(describing: effectiveStartTime))"
          )

          // Verify that seeking will happen if startTime is provided
          if let startTime = effectiveStartTime, startTime > 0 {
            print("⏱ FullScreenVideoPlayer will seek to \(startTime) seconds")
          }
        }

        // Transparent overlay for capturing taps - only when controls are hidden
        if !showControls {
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
              print("👆 Tap detected - showing controls")
              withAnimation(.easeInOut(duration: 0.3)) {
                showControls = true
              }

              // Schedule auto-hide when controls are shown
              Task {
                await scheduleControlsHide()
              }
            }
            .gesture(
              DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onEnded { value in
                  let horizontalAmount = value.translation.width
                  let verticalAmount = value.translation.height

                  print(
                    "👆 DragGesture ended - horizontal: \(horizontalAmount), vertical: \(verticalAmount)"
                  )

                  // Check if this is primarily a horizontal swipe (more horizontal than vertical movement)
                  if abs(horizontalAmount) > abs(verticalAmount) && abs(horizontalAmount) > 30 {
                    if horizontalAmount > 0 {
                      // Swipe right - seek forward 10 seconds
                      print("👆 ✅ SWIPE RIGHT DETECTED - seeking forward 10 seconds")
                      VideoPlayerRegistry.shared.seek(by: 10)

                      // Haptic feedback
                      let generator = UIImpactFeedbackGenerator(style: .light)
                      generator.impactOccurred()
                    } else {
                      // Swipe left - seek backward 10 seconds
                      print("👆 ✅ SWIPE LEFT DETECTED - seeking back 10 seconds")
                      VideoPlayerRegistry.shared.seek(by: -10)

                      // Haptic feedback
                      let generator = UIImpactFeedbackGenerator(style: .light)
                      generator.impactOccurred()
                    }
                  } else {
                    print("👆 ❌ DragGesture didn't qualify as horizontal swipe:")
                    print("   horizontal: \(abs(horizontalAmount)) (min: 30)")
                    print("   vertical: \(abs(verticalAmount))")
                    print("   isHorizontal: \(abs(horizontalAmount) > abs(verticalAmount))")
                  }
                }
            )
        }

        // Control overlay - only show when showControls is true
        if showControls {
          // Background tap to hide controls
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
              print("👆 Tap on control area - hiding controls")
              withAnimation(.easeInOut(duration: 0.3)) {
                showControls = false
              }
            }

          VStack {
            // Top control buttons - only show close button
            HStack {
              Spacer()

              // Close button
              Button(action: {
                print("🔄 Close button tapped")
                // Mark as manual exit for cleanup
                isManualExit = true
                appModel.forceCloseVideo()
              }) {
                Image(systemName: "xmark.circle.fill")
                  .font(.title)
                  .foregroundColor(.white.opacity(0.8))
                  .padding()
                  .shadow(radius: 2)
              }
            }
            .padding(.top, 50)
            .padding(.horizontal)

            Spacer()

            // Playback control buttons at bottom
            HStack(spacing: 15) {
              Spacer()

              // Next Scene button - Skip to next scene in the queue
              Button {
                print("🎬 Next Scene button tapped")
                print("🎬 DEBUG - Button action triggered")
                print("🎬 DEBUG - showControls: \(showControls)")
                print("🎬 DEBUG - appModel.isMarkerShuffleMode: \(appModel.isMarkerShuffleMode)")
                navigateToNextScene()
              } label: {
                ZStack {
                  // Background circle
                  Circle()
                    .fill(Color.green.opacity(0.7))
                    .frame(width: 50, height: 50)
                    .shadow(color: .black, radius: 4)

                  // Icon
                  Image(systemName: "forward.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                  // Outer border
                  Circle()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: 50, height: 50)
                }
              }

              // Seek backward 30 seconds button
              Button {
                print("⏪ Seek backward 30 seconds")
                seekVideo(by: -30)
              } label: {
                ZStack {
                  // Background circle
                  Circle()
                    .fill(Color.gray.opacity(0.7))
                    .frame(width: 50, height: 50)
                    .shadow(color: .black, radius: 4)

                  // Icon
                  Image(systemName: "gobackward.30")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                  // Outer border
                  Circle()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: 50, height: 50)
                }
              }

              // Button 1: Library Random - Play a completely random scene from library
              Button {
                print("🔄 Library random button tapped")
                handlePureRandomVideo()
              } label: {
                ZStack {
                  // Background circle
                  Circle()
                    .fill(Color.blue.opacity(0.7))
                    .frame(width: 60, height: 60)
                    .shadow(color: .black, radius: 4)

                  // Icon
                  Image(systemName: "shuffle")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                  // Outer border
                  Circle()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: 60, height: 60)
                }
              }
              .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                  .onEnded { _ in
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    // Show info about what this button does
                    print("Showing button info: Random Scene")
                  }
              )

              // Button 2: Random Position - Jump to random position in current video
              Button {
                print("🎲 Random position button tapped")
                handleRandomVideo()  // Uses playNextScene() which jumps within current video
              } label: {
                ZStack {
                  // Background circle
                  Circle()
                    .fill(Color.purple.opacity(0.8))
                    .frame(width: 60, height: 60)
                    .shadow(color: .black, radius: 4)

                  // Icon
                  Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                  // Outer border
                  Circle()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: 60, height: 60)
                }
              }
              .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                  .onEnded { _ in
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    // Show info about what this button does
                    print("Showing button info: Jump to Random Position")
                  }
              )

              // Button 3: Performer Jump - Play a different scene with the same performer
              Button {
                print("👤 Performer random scene button tapped")
                handlePerformerRandomVideo()
              } label: {
                ZStack {
                  // Background circle
                  Circle()
                    .fill(Color.purple.opacity(0.8))
                    .frame(width: 60, height: 60)
                    .shadow(color: .black, radius: 4)

                  // Icon - using a simpler icon and making it larger and more visible
                  Image(systemName: "person.fill.and.arrow.left.and.arrow.right")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                  // Outer border
                  Circle()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: 60, height: 60)
                }
              }
              .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                  .onEnded { _ in
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    // Show info about what this button does
                    print("Showing button info: Play Different Scene with Same Performer")
                  }
              )

              // Seek forward 30 seconds button
              Button {
                print("⏩ Seek forward 30 seconds")
                seekVideo(by: 30)
              } label: {
                ZStack {
                  // Background circle
                  Circle()
                    .fill(Color.gray.opacity(0.7))
                    .frame(width: 50, height: 50)
                    .shadow(color: .black, radius: 4)

                  // Icon
                  Image(systemName: "goforward.30")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                  // Outer border
                  Circle()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: 50, height: 50)
                }
              }
            }
            .padding(.bottom, 30)
            .padding(.trailing, 20)
          }
          .transition(.opacity)
          .animation(.easeInOut(duration: 0.3), value: showControls)
        }
      }
      .navigationBarHidden(true)  // Hide the navigation bar completely
      .statusBarHidden(true)  // Hide the status bar for full immersion
      .ignoresSafeArea(.all)  // Ignore all safe areas for true full screen
      .id(scene.id)  // Force view recreation when scene changes
      .focused($isVideoPlayerFocused)  // Automatically focus for keyboard input
      .onKeyPress(phases: .down) { keyPress in
        return handleKeyPress(keyPress)
      }
      .onAppear {
        print("📱 VideoPlayerView appeared")
        print("📱 DEBUG - Scene: \(scene.title ?? "Untitled") ID: \(scene.id)")
        print(
          "📱 DEBUG - Is marker navigation: \(UserDefaults.standard.bool(forKey: "scene_\(scene.id)_isMarkerNavigation"))"
        )
        print("📱 DEBUG - showControls: \(showControls)")

        // Automatically focus the video player for immediate keyboard input
        isVideoPlayerFocused = true

        // IMPORTANT: Update currentScene to the correct scene being played
        currentScene = scene
        appModel.currentScene = scene

        // Reset performer context to prevent contamination from previous sessions
        // Always start fresh with performers from the current scene only
        print("📱 PERFORMER CONTEXT: Resetting performer state for new scene")
        print(
          "📱 PERFORMER CONTEXT: Previous originalPerformer: \(originalPerformer?.name ?? "none")")
        print(
          "📱 PERFORMER CONTEXT: PerformerDetailView performer: \(appModel.performerDetailViewPerformer?.name ?? "none")"
        )

        // Always reset to nil first, then set based on legitimate context only
        originalPerformer = nil

        // Only set originalPerformer if we have a specific performer context AND that performer is in current scene
        if let performerDetailPerformer = appModel.performerDetailViewPerformer,
          scene.performers.contains(where: { $0.id == performerDetailPerformer.id }) {
          print(
            "📱 PERFORMER CONTEXT: Setting originalPerformer to \(performerDetailPerformer.name) (found in current scene)"
          )
          originalPerformer = performerDetailPerformer
        } else {
          print("📱 PERFORMER CONTEXT: No valid performer context - originalPerformer remains nil")
          if let performerDetailPerformer = appModel.performerDetailViewPerformer {
            print(
              "📱 PERFORMER CONTEXT: Note: \(performerDetailPerformer.name) not found in current scene performers"
            )
          }
        }

        // Start video loading timeout
        startVideoLoadingTimeout()

        // Add scene to watch history when video player appears
        addToWatchHistory()

        // Check if this is a marker navigation
        let isMarkerNavigation = UserDefaults.standard.bool(
          forKey: "scene_\(scene.id)_isMarkerNavigation")

        // Get direct startTime parameter value as priority
        if let startTime = startTime {
          print("📱 Using provided startTime parameter: \(startTime)")
          effectiveStartTime = startTime
        } else if isMarkerNavigation {
          // For marker navigation, try to get the start time from UserDefaults
          let storedStartTime = UserDefaults.standard.double(forKey: "scene_\(scene.id)_startTime")
          if storedStartTime > 0 {
            print("📱 Using stored startTime from UserDefaults for marker: \(storedStartTime)")
            effectiveStartTime = storedStartTime
          }
        }

        // Get direct endTime parameter value if provided
        if let endTime = endTime {
          print("📱 Using provided endTime parameter: \(endTime)")
          effectiveEndTime = endTime
        } else {
          // Check if there's a stored end time for this scene in UserDefaults
          let storedEndTime = UserDefaults.standard.double(forKey: "scene_\(scene.id)_endTime")
          if storedEndTime > 0 {
            print("📱 Using stored endTime from UserDefaults: \(storedEndTime)")
            effectiveEndTime = storedEndTime
          }
        }

        // Enhanced performer context preservation
        // First check if there's a currentPerformer from PerformerDetailView context
        if let currentPerformer = appModel.currentPerformer,
          scene.performers.contains(where: { $0.id == currentPerformer.id }) {
          print(
            "📱 Initializing original performer from PerformerDetailView context: \(currentPerformer.name)"
          )
          originalPerformer = currentPerformer
        } else {
          // Default to female performer from current scene
          let femalePerformer = scene.performers.first { isLikelyFemalePerformer($0) }
          let selectedPerformer = femalePerformer ?? scene.performers.first
          if let selectedPerformer = selectedPerformer {
            print(
              "📱 Setting original performer to: \(selectedPerformer.name) (gender: \(selectedPerformer.gender ?? "unknown"))"
            )
            originalPerformer = selectedPerformer
          }
        }

        // Show controls initially, then hide after delay
        showControls = true
        Task {
          await scheduleControlsHide()
        }

        // Notify that main video player has started - this stops all preview videos
        NotificationCenter.default.post(
          name: Notification.Name("MainVideoPlayerStarted"), object: nil)

        // Listen for marker shuffle updates to avoid navigation flicker
        NotificationCenter.default.addObserver(
          forName: NSNotification.Name("UpdateVideoPlayerForMarkerShuffle"),
          object: nil,
          queue: .main
        ) { notification in
          print("🔄 Received marker shuffle update notification")
          if let userInfo = notification.userInfo,
            let newScene = userInfo["scene"] as? StashScene,
            let startSeconds = userInfo["startSeconds"] as? Double,
            let hlsURL = userInfo["hlsURL"] as? String {
            print("🔄 Updating VideoPlayerView to new scene: \(newScene.id) at \(startSeconds)s")

            // Update the current scene and times
            currentScene = newScene
            effectiveStartTime = startSeconds

            // Update originalPerformer to match the female performer from current scene
            let femalePerformer = newScene.performers.first { self.isLikelyFemalePerformer($0) }
            let newOriginalPerformer = femalePerformer ?? newScene.performers.first
            if let newOriginalPerformer = newOriginalPerformer {
              print("🔄 Updating originalPerformer to: \(newOriginalPerformer.name) from \(self.originalPerformer?.name ?? "nil")")
              self.originalPerformer = newOriginalPerformer
            }

            if let endSeconds = userInfo["endSeconds"] as? Double {
              effectiveEndTime = endSeconds
            }

            // Update the current player with new content
            if let player = getCurrentPlayer() {
              print("🔄 Updating player with new content")

              // Create new player item with the HLS URL
              if let url = URL(string: hlsURL) {
                let headers = ["User-Agent": "StashApp/iOS"]
                let asset = AVURLAsset(
                  url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                let playerItem = AVPlayerItem(asset: asset)

                // CRITICAL: Use stable buffering to prevent black screen with audio
                playerItem.preferredForwardBufferDuration = 5.0
                player.automaticallyWaitsToMinimizeStalling = true

                // Replace current item
                player.replaceCurrentItem(with: playerItem)

                // Wait for player to be READY before seeking/playing (prevents black screen)
                var statusObserver: NSKeyValueObservation?
                statusObserver = playerItem.observe(\.status, options: [.new]) { item, _ in
                  if item.status == .readyToPlay {
                    statusObserver?.invalidate()
                    let cmTime = CMTime(seconds: startSeconds, preferredTimescale: 1000)
                    player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                      player.play()
                      self.cancelVideoLoadingTimeout()
                      // Restore keyboard focus after scene transition
                      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.isVideoPlayerFocused = true
                      }
                    }
                  } else if item.status == .failed {
                    statusObserver?.invalidate()
                    print("❌ Player item failed: \(item.error?.localizedDescription ?? "unknown")")
                  }
                }
              }
            }
          }
        }

        // Listen for new marker shuffle updates (simplified approach)
        NotificationCenter.default.addObserver(
          forName: NSNotification.Name("UpdateVideoPlayerWithMarker"),
          object: nil,
          queue: .main
        ) { notification in
          print("🎲 Received UpdateVideoPlayerWithMarker notification")
          if let userInfo = notification.userInfo,
            let marker = userInfo["marker"] as? SceneMarker,
            let newScene = userInfo["scene"] as? StashScene {
            // Extract startTime - it might be Int, Float, or Double
            let startTime: Double
            if let intTime = userInfo["startTime"] as? Int {
              startTime = Double(intTime)
            } else if let floatTime = userInfo["startTime"] as? Float {
              startTime = Double(floatTime)
            } else if let doubleTime = userInfo["startTime"] as? Double {
              startTime = doubleTime
            } else {
              print("❌ Invalid startTime type in notification")
              return
            }

            print("🎲 Updating VideoPlayerView with marker: \(marker.title) at \(startTime)s")

            // Update the current scene and marker
            currentScene = newScene
            currentMarker = marker
            effectiveStartTime = startTime
            effectiveEndTime = nil  // Reset end time for markers

            // Update originalPerformer to match the female performer from current scene
            let femalePerformer = newScene.performers.first { self.isLikelyFemalePerformer($0) }
            let newOriginalPerformer = femalePerformer ?? newScene.performers.first
            if let newOriginalPerformer = newOriginalPerformer {
              print("🎲 Updating originalPerformer to: \(newOriginalPerformer.name) from \(self.originalPerformer?.name ?? "nil")")
              self.originalPerformer = newOriginalPerformer
            }

            // Update the current player with new content
            if let player = getCurrentPlayer() {
              print("🎲 Updating player with marker content")

              // Pause current playback to prevent audio stacking
              player.pause()

              // Get codec-aware stream URL (direct play for h264/hevc, HLS otherwise)
              guard let streamURL = VideoPlayerUtility.getStreamURL(for: newScene, startTime: startTime) else {
                print("❌ Failed to construct stream URL for marker scene")
                return
              }
              print("🎲 Using stream URL for marker: \(streamURL.absoluteString)")

              // Create headers for authentication (simplified, following existing pattern)
              let headers = ["User-Agent": "StashApp/iOS"]

              let asset = AVURLAsset(
                url: streamURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
              let playerItem = AVPlayerItem(asset: asset)

              // CRITICAL: Use stable buffering to prevent black screen with audio
              playerItem.preferredForwardBufferDuration = 5.0
              player.automaticallyWaitsToMinimizeStalling = true

              // Replace current item
              player.replaceCurrentItem(with: playerItem)

              // Wait for player to be READY before seeking/playing (prevents black screen)
              var statusObserver: NSKeyValueObservation?
              statusObserver = playerItem.observe(\.status, options: [.new]) { item, _ in
                if item.status == .readyToPlay {
                  statusObserver?.invalidate()
                  print("🎲 Player ready - seeking to marker time: \(startTime)s")

                  let cmTime = CMTime(seconds: startTime, preferredTimescale: 1000)
                  player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) {
                    completed in
                    if completed {
                      print("🎲 ✅ Successfully seeked to marker time \(startTime)s, starting playback")
                    } else {
                      print("⚠️ Seek incomplete, starting playback anyway")
                    }
                    player.play()
                    // Restore keyboard focus after scene transition
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                      self.isVideoPlayerFocused = true
                    }
                  }
                } else if item.status == .failed {
                  statusObserver?.invalidate()
                  print("❌ Player item failed: \(item.error?.localizedDescription ?? "unknown")")
                }
              }
            } else {
              print("❌ No current player found for marker update")
            }
          }
        }

        // Listen for keyboard shortcuts from menu commands (Mac Catalyst)
        NotificationCenter.default.addObserver(
          forName: NSNotification.Name("VideoPlayerKeyboardShortcut"),
          object: nil,
          queue: .main
        ) { notification in
          if let keyCodeRaw = notification.userInfo?["keyCode"] as? CFIndex,
            let keyCode = UIKeyboardHIDUsage(rawValue: keyCodeRaw) {
            self.handleMenuKeyboardShortcut(keyCode)
          }
        }

        // Listen for video loading timeout
        NotificationCenter.default.addObserver(
          forName: NSNotification.Name("VideoLoadingTimeout"),
          object: nil,
          queue: .main
        ) { _ in
          print("🎲 Video loading timeout notification received - cleaning up audio first")

          // CRITICAL: Stop and clean up current player audio before advancing
          if let currentPlayer = VideoPlayerRegistry.shared.currentPlayer {
            print("🔇 Stopping current player audio due to timeout")
            currentPlayer.pause()
            currentPlayer.seek(to: .zero)
            // Add small delay to ensure audio stops
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
              appModel.shuffleToNextMarker()
            }
          } else {
            appModel.shuffleToNextMarker()
          }
        }

        // Listen for video loading success (to cancel timeout)
        NotificationCenter.default.addObserver(
          forName: NSNotification.Name("VideoLoadingSuccess"),
          object: nil,
          queue: .main
        ) { _ in
          print("✅ Video loading success notification received")
          self.cancelVideoLoadingTimeout()
        }

        // Listen for tag shuffle updates
        NotificationCenter.default.addObserver(
          forName: NSNotification.Name("UpdateVideoPlayerForTagShuffle"),
          object: nil,
          queue: .main
        ) { notification in
          print("🔄 Received tag shuffle update notification")
          if let userInfo = notification.userInfo,
            let newScene = userInfo["scene"] as? StashScene,
            let hlsURL = userInfo["hlsURL"] as? String {
            print("🔄 Updating VideoPlayerView to new tag scene: \(newScene.id)")

            // Update the current scene - tag shuffle doesn't use start/end times
            currentScene = newScene
            effectiveStartTime = nil
            effectiveEndTime = nil

            // Update the current player with new content
            if let player = getCurrentPlayer() {
              print("🔄 Updating player with new tag scene content")

              // Create new player item with the HLS URL
              if let url = URL(string: hlsURL) {
                let headers = ["User-Agent": "StashApp/iOS"]
                let asset = AVURLAsset(
                  url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                let playerItem = AVPlayerItem(asset: asset)

                // Replace current item
                player.replaceCurrentItem(with: playerItem)

                // Start playing from the beginning
                player.seek(to: .zero) { _ in
                  player.play()
                }
              }
            }
          }
        }

        // Listen for most played shuffle updates
        NotificationCenter.default.addObserver(
          forName: NSNotification.Name("UpdateVideoPlayerForMostPlayedShuffle"),
          object: nil,
          queue: .main
        ) { notification in
          print("🎯 Received most played shuffle update notification")
          if let userInfo = notification.userInfo,
            let newScene = userInfo["scene"] as? StashScene,
            let hlsURL = userInfo["hlsURL"] as? String {
            print("🎯 Updating VideoPlayerView to new most played scene: \(newScene.id)")

            // Update the current scene - most played shuffle doesn't use start/end times
            currentScene = newScene
            effectiveStartTime = nil
            effectiveEndTime = nil

            // Update the current player with new content
            if let player = getCurrentPlayer() {
              print("🎯 Updating player with new most played scene content")

              // Create new player item with the HLS URL
              if let url = URL(string: hlsURL) {
                let headers = ["User-Agent": "StashApp/iOS"]
                let asset = AVURLAsset(
                  url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                let playerItem = AVPlayerItem(asset: asset)

                // Replace current item
                player.replaceCurrentItem(with: playerItem)

                // Start playing from the beginning
                player.seek(to: .zero) { _ in
                  player.play()
                }
              }
            }
          }
        }
      }
      .onDisappear {
        print("📱 VideoPlayerView disappeared - cleaning up video player")
        appModel.currentScene = nil
        // Cancel any pending hide task when view disappears
        hideControlsTask?.cancel()

        // Cancel video loading timeout timer
        videoLoadingTimer?.invalidate()
        videoLoadingTimer = nil
        isVideoLoading = false

        // Check if we're in shuffle mode and if this is a manual exit
        let isMarkerShuffle = UserDefaults.standard.bool(forKey: "isMarkerShuffleContext")
        let isTagShuffle = UserDefaults.standard.bool(forKey: "isTagSceneShuffleContext")
        let isMostPlayedShuffle = UserDefaults.standard.bool(forKey: "isMostPlayedShuffleMode")

        // Clean up video player if:
        // 1. Not in shuffle mode, OR
        // 2. Manual exit (user pressed close/exit button)
        if (!isMarkerShuffle && !isTagShuffle && !isMostPlayedShuffle) || isManualExit {
          // CRITICAL: Clean up time observers BEFORE disposing the player
          // This prevents the "black screen + audio continuing" bug
          VideoPlayerRegistry.shared.cleanupObservers()

          if let player = VideoPlayerRegistry.shared.currentPlayer {
            print("🔇 Disposing of video player on view disappear (non-shuffle or manual exit)")
            player.pause()
            player.replaceCurrentItem(with: nil)
          }
          VideoPlayerRegistry.shared.currentPlayer = nil
          VideoPlayerRegistry.shared.playerViewController = nil

          if isManualExit {
            print("🔇 Manual exit detected - forcing audio cleanup in shuffle mode")
            appModel.killAllAudio()
          }
        } else {
          print("🎲 Skipping video player cleanup - in shuffle mode (automatic navigation)")
        }
      }
      // Add emergency exit gesture at bottom of screen
      .gesture(
        TapGesture(count: 2)
          .onEnded { _ in
            print("👋 Emergency exit gesture detected")
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Mark as manual exit for cleanup
            isManualExit = true

            // Force close video and navigation cleanup
            appModel.forceCloseVideo()

            // Clear the video player
            VideoPlayerRegistry.shared.currentPlayer?.pause()
            VideoPlayerRegistry.shared.currentPlayer = nil
            VideoPlayerRegistry.shared.playerViewController = nil
          }
      )
    }
  }

  // Function to hide controls after a delay
  private func scheduleControlsHide() async {
    // Cancel any existing hide task
    hideControlsTask?.cancel()

    // Create a new task to hide controls after delay
    hideControlsTask = Task {
      do {
        // Wait 5 seconds before hiding controls
        try await Task.sleep(nanoseconds: 5_000_000_000)

        // Check if task was cancelled
        if !Task.isCancelled {
          // Add a small delay for animation
          try await Task.sleep(nanoseconds: UInt64(0.3 * 1_000_000_000))

          // Check again if task was cancelled
          if !Task.isCancelled {
            // Update UI on main thread
            await MainActor.run {
              withAnimation(.easeInOut(duration: 0.3)) {
                showControls = false
              }
            }
          }
        }
      } catch {
        // Task was cancelled, do nothing
      }
    }
  }

  private func handlePureRandomVideo() {
    withAnimation(.easeOut(duration: 0.2)) {
      showControls = false
    }

    playPureRandomVideo()
  }

  private func handlePerformerRandomVideo() {
    withAnimation(.easeOut(duration: 0.2)) {
      showControls = false
    }

    // M key ALWAYS plays performer random video - no restore logic here
    // Restore logic is on V key (navigateToNextScene) to return to marker shuffle
    playPerformerRandomVideo()
  }

  private func handleRandomVideo() {
    withAnimation(.easeOut(duration: 0.2)) {
      showControls = false
    }

    playNextScene()
  }

  // Helper to get the correct stream URL - uses direct play for compatible codecs, HLS for others
  private func getStreamURL() -> URL {
    let sceneId = currentScene.id

    // Check if we're in marker shuffle mode and need to clear cached URLs for OTHER scenes
    let isMarkerShuffle = UserDefaults.standard.bool(forKey: "isMarkerShuffleContext")
    if isMarkerShuffle {
      print("🧹 VideoPlayerView: Clearing cached stream URLs for other scenes (keeping current scene \(sceneId))")
      let defaults = UserDefaults.standard
      let keys = defaults.dictionaryRepresentation().keys
      for key in keys {
        // Only clear URLs for OTHER scenes, not the current one we're about to play
        if (key.contains("_hlsURL") || key.contains("_streamURL")) && !key.contains("scene_\(sceneId)_") {
          defaults.removeObject(forKey: key)
          print("🧹 Removed cached URL key: \(key)")
        }
      }
    }

    // Check if this video can be direct played (h264, hevc, etc.)
    let videoCodec = currentScene.files.first?.video_codec
    let canDirectPlay = VideoPlayerUtility.canDirectPlay(codec: videoCodec)

    // Check if marker navigation prefers HLS (for reliable seeking via manifest)
    let preferHLS = UserDefaults.standard.bool(forKey: "scene_\(sceneId)_preferHLS")

    let apiKey = appModel.apiKey
    let baseServerURL = appModel.serverAddress.trimmingCharacters(
      in: CharacterSet(charactersIn: "/"))
    let currentTimestamp = Int(Date().timeIntervalSince1970)

    // Use HLS if preferred (marker navigation) OR if codec needs transcoding
    if canDirectPlay && !preferHLS {
      // Use direct stream URL for compatible codecs (no transcoding needed)
      print("✅ Using direct play for scene \(sceneId) with codec: \(videoCodec ?? "unknown")")

      var streamURL = "\(baseServerURL)/scene/\(sceneId)/stream?apikey=\(apiKey)&_ts=\(currentTimestamp)"

      // Add start time if we have one (for seeking after load)
      if let startTime = effectiveStartTime {
        streamURL += "&t=\(Int(startTime))"
        print("🎬 Direct stream URL with start time: \(streamURL)")
      } else {
        print("🎬 Direct stream URL: \(streamURL)")
      }

      if let url = URL(string: streamURL) {
        return url
      }
    } else {
      // Use HLS for incompatible codecs OR when marker navigation prefers HLS
      if preferHLS {
        print("🔄 Using HLS for marker navigation (preferHLS=true) for scene \(sceneId)")
      } else {
        print("🔄 Using HLS transcoding for scene \(sceneId) with codec: \(videoCodec ?? "unknown")")
      }

      // First check if we have a saved HLS URL format FOR THIS SPECIFIC SCENE
      if let savedHlsUrlString = UserDefaults.standard.string(forKey: "scene_\(sceneId)_hlsURL"),
        let savedHlsUrl = URL(string: savedHlsUrlString) {
        // Verify the saved URL is actually for this scene
        if savedHlsUrlString.contains("/scene/\(sceneId)/") {
          print("📱 Using saved HLS URL format for scene \(sceneId): \(savedHlsUrlString)")
          // Force update effectiveStartTime if it's included in the URL
          if savedHlsUrlString.contains("t=") {
            if let tRange = savedHlsUrlString.range(of: "t=\\d+", options: .regularExpression),
              let tValue = Int(savedHlsUrlString[tRange].replacingOccurrences(of: "t=", with: "")) {
              print("📱 Extracted timestamp from URL: \(tValue)")
              // Only update if not already set
              if effectiveStartTime == nil {
                effectiveStartTime = Double(tValue)
                print("📱 Updated effectiveStartTime to \(tValue) from URL")
              }
            }
          }
          return savedHlsUrl
        } else {
          print(
            "⚠️ Saved HLS URL is for wrong scene (found scene ID in URL doesn't match \(sceneId)), clearing it"
          )
          UserDefaults.standard.removeObject(forKey: "scene_\(sceneId)_hlsURL")
        }
      }

      // If no saved URL and we have a start time, construct a proper HLS URL
      if let startTime = effectiveStartTime {
        let markerSeconds = Int(startTime)

        // Format exactly like the example
        let hlsStreamURL =
          "\(baseServerURL)/scene/\(sceneId)/stream.m3u8?apikey=\(apiKey)&resolution=ORIGINAL&t=\(markerSeconds)&_ts=\(currentTimestamp)"
        print("🎬 Constructing HLS URL on-demand: \(hlsStreamURL)")

        // Save for future use
        UserDefaults.standard.set(hlsStreamURL, forKey: "scene_\(sceneId)_hlsURL")

        if let url = URL(string: hlsStreamURL) {
          return url
        }
      }

      // Construct HLS URL without timestamp (will seek manually if needed)
      let hlsStreamURL =
        "\(baseServerURL)/scene/\(sceneId)/stream.m3u8?apikey=\(apiKey)&resolution=ORIGINAL&_ts=\(currentTimestamp)"
      print("🎬 Constructing HLS URL without start time: \(hlsStreamURL)")

      // Save for future use
      UserDefaults.standard.set(hlsStreamURL, forKey: "scene_\(sceneId)_hlsURL")

      if let url = URL(string: hlsStreamURL) {
        return url
      }
    }

    // Absolute fallback to default URL (should rarely happen)
    guard let stream = currentScene.paths.stream,
          let url = URL(string: stream) else {
      print("❌ Critical error: No stream URL for current scene \(currentScene.id)")
      // Return a placeholder URL to avoid crash
      return URL(string: "about:blank")!
    }
    return url
  }

  // Video loading timeout functions
  private func startVideoLoadingTimeout() {
    isVideoLoading = true
    videoLoadingTimer?.invalidate()

    videoLoadingTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { _ in
      print("⚠️ VIDEO LOADING TIMEOUT: Video failed to load within 15 seconds")

      // Check if we're in shuffle mode and can advance to next
      let isMarkerShuffle = UserDefaults.standard.bool(forKey: "isMarkerShuffleContext")

      if isMarkerShuffle {
        print("🎲 Auto-advancing to next marker due to loading timeout")
        DispatchQueue.main.async {
          // Access appModel through @EnvironmentObject - this will work in timer context
          NotificationCenter.default.post(
            name: NSNotification.Name("VideoLoadingTimeout"), object: nil)
        }
      } else {
        print("⚠️ Video timeout in non-shuffle mode - staying on current video")
      }
    }
  }

  private func cancelVideoLoadingTimeout() {
    videoLoadingTimer?.invalidate()
    videoLoadingTimer = nil
    isVideoLoading = false
  }
}

// MARK: - Video Controls
extension VideoPlayerView {
  /// Seeks the video forward or backward by the specified number of seconds
  private func seekVideo(by seconds: Double) {
    // Get the current player
    guard let player = getCurrentPlayer() else {
      print("⚠️ Cannot seek - player not found")
      return
    }

    print("⏱ Seeking video by \(seconds) seconds")

    // Get current time
    guard let currentItem = player.currentItem else {
      print("⚠️ Cannot seek - no current item")
      return
    }

    let currentTime = currentItem.currentTime()
    let targetTime = CMTimeAdd(currentTime, CMTime(seconds: seconds, preferredTimescale: 1000))

    // Make sure we don't seek past beginning or end
    let duration = currentItem.duration
    let zeroTime = CMTime.zero

    // Only apply limits if we have valid duration
    if duration.isValid && !duration.seconds.isNaN {
      if targetTime.seconds < 0 {
        // Don't seek before beginning
        player.seek(to: zeroTime, toleranceBefore: .zero, toleranceAfter: .zero)
        print("⏱ Seeking to beginning of video")
        return
      } else if targetTime.seconds > duration.seconds {
        // Don't seek past end
        player.seek(to: duration, toleranceBefore: .zero, toleranceAfter: .zero)
        print("⏱ Seeking to end of video")
        return
      }
    }

    // Perform the normal seek
    print("⏱ Seeking to \(targetTime.seconds) seconds")
    player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { success in
      if success {
        print("✅ Successfully seeked by \(seconds) seconds")

        // Provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Make sure playback continues
        if player.timeControlStatus != .playing {
          player.play()
        }
      } else {
        print("❌ Seek operation failed")
      }
    }
  }

  /// Plays a random scene from the media library directly in the current player
  private func playPureRandomVideo() {
    Task {
      print("🔄 Starting random video selection with female performer preference")

      // CRITICAL: Clear performer context when switching to library random shuffle
      // This ensures subsequent M presses use the female performer from the NEW scene
      // rather than a stale performer from a previous shuffle session
      await MainActor.run {
        if appModel.currentPerformer != nil {
          print("🧹 LIBRARY SHUFFLE: Clearing appModel.currentPerformer (was: \(appModel.currentPerformer?.name ?? "nil"))")
          appModel.currentPerformer = nil
        }
        // Also clear local originalPerformer so we pick from the new scene
        originalPerformer = nil
      }

      // Fetch a random scene with female performers using direct GraphQL query
      let query = """
        {
            "operationName": "FindScenes",
            "variables": {
                "filter": {
                    "page": 1,
                    "per_page": 100,
                    "sort": "random",
                    "direction": "ASC"
                },
                "scene_filter": {
                    "performer_gender": {
                        "value": ["FEMALE"],
                        "modifier": "INCLUDES"
                    }
                }
            },
            "query": "query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) { findScenes(filter: $filter, scene_filter: $scene_filter) { count scenes { id title details paths { screenshot preview stream } files { size duration video_codec width height } performers { id name gender scene_count } tags { id name } rating100 } } }"
        }
        """

      do {
        print("🔄 Executing GraphQL query for female performer scenes")
        let data = try await appModel.api.executeGraphQLQuery(query)

        struct FindScenesResponse: Decodable {
          struct Data: Decodable {
            struct FindScenes: Decodable {
              let count: Int
              let scenes: [StashScene]
            }
            let findScenes: FindScenes
          }
          let data: Data
        }

        let response = try JSONDecoder().decode(FindScenesResponse.self, from: data)
        let femaleScenes = response.data.findScenes.scenes

        print("🔄 Found \(femaleScenes.count) scenes with female performers")

        // The API should filter out VR tags automatically, but let's double-check
        let filteredScenes = femaleScenes.filter { scene in
          // Filter out VR scenes
          !scene.tags.contains { tag in
            tag.name.lowercased() == "vr"
          }
        }

        print(
          "🔄 Additional VR scene check: \(femaleScenes.count - filteredScenes.count) VR scenes would be removed"
        )

        if let randomScene = filteredScenes.randomElement() {
          print("✅ Selected random scene with female performer: \(randomScene.title ?? "Untitled")")

          // Update the current scene reference AND add to watch history
          await MainActor.run {
            print("🔄 Updating current scene reference and adding to watch history")
            currentScene = randomScene
            appModel.currentScene = randomScene

            // IMPORTANT: Add to watch history (avoid duplicates of consecutive same scene)
            if appModel.watchHistory.last?.id != randomScene.id {
              appModel.watchHistory.append(randomScene)
              // Keep history to reasonable size (last 20 scenes)
              if appModel.watchHistory.count > 20 {
                appModel.watchHistory = Array(appModel.watchHistory.suffix(20))
              }
              print(
                "🔄 SHUFFLE: Added to watch history: \(randomScene.title ?? "Untitled") (history count: \(appModel.watchHistory.count))"
              )
            }

            // When shuffling to a new scene, update the original performer to first female performer
            // But ONLY if we don't already have an original performer set
            if originalPerformer == nil {
              if let femalePerformer = randomScene.performers.first(where: {
                isLikelyFemalePerformer($0)
              }
              ) {
                print(
                  "🔄 Setting original performer to female: \(femalePerformer.name) (ID: \(femalePerformer.id))"
                )
                originalPerformer = femalePerformer
              } else if let anyPerformer = randomScene.performers.first {
                print("🔄 No female performer found, using first performer: \(anyPerformer.name)")
                originalPerformer = anyPerformer
              } else {
                print("⚠️ No performers in new scene, clearing original performer")
                originalPerformer = nil
              }
            } else {
              print("🔄 Keeping original performer set: \(originalPerformer!.name)")
            }
          }

          // Get the player from the current view controller
          if let player = getCurrentPlayer() {
            print("✅ Got player reference, preparing to play new content")

            // Create a new player item using codec-aware URL (direct play for h264/hevc, HLS otherwise)
            guard let streamURL = VideoPlayerUtility.getStreamURL(for: randomScene) else {
              print("❌ Shuffle: No stream URL for scene \(randomScene.id)")
              return
            }
            print("🔄 Created stream URL for random scene: \(streamURL.absoluteString)")
            let playerItem = AVPlayerItem(url: streamURL)

            print("🔄 Creating new player item with URL: \(streamURL.absoluteString)")

            // Replace the current item in the player
            player.replaceCurrentItem(with: playerItem)
            player.play()

            print("▶️ Started playing random scene: \(randomScene.title ?? "Untitled")")

            // Enhanced shuffle: Jump to a random position in the new scene after minimal delay
            // Wait for the player to be ready before jumping to random position
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
              print("🎲 Shuffle: Jumping to random position in new scene")
              VideoPlayerUtility.jumpToRandomPosition(in: player)
            }

            // Add observer for playback progress
            let interval = CMTime(seconds: 5, preferredTimescale: 1)
            player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
              let seconds = CMTimeGetSeconds(time)
              if seconds > 0 {
                UserDefaults.standard.setVideoProgress(seconds, for: randomScene.id)
              }
            }

            // Reset the controls visibility
            await MainActor.run {
              showControls = true
              Task {
                await scheduleControlsHide()
              }
            }
          } else {
            print("⚠️ Failed to get player reference")
          }
        } else {
          print("⚠️ No female performer scenes available, falling back to any scene")

          // Fallback to any scene if no female performer scenes were found
          await fallbackToAnyScene()
        }
      } catch {
        print("⚠️ Error fetching female performer scenes: \(error.localizedDescription)")

        // Fallback to any scene if query failed
        await fallbackToAnyScene()
      }
    }
  }
  private func navigateToNextScene() {
    // FIRST CHECK: If in performer shuffle mode with saved marker state, restore markers on V press
    // This allows V key to return from performer shuffle back to marker shuffle
    if appModel.isPerformerShuffleMode && appModel.hasSavedMarkerShuffleState {
      print("🔙 V KEY: Returning from performer shuffle to marker shuffle")
      appModel.isPerformerShuffleMode = false
      appModel.performerShufflePerformer = nil
      if appModel.restoreMarkerShuffleState() {
        isMarkerShuffleMode = true
        if let nextMarker = appModel.nextMarkerInShuffle() {
          print("🎲 V KEY: Navigating to restored marker: \(nextMarker.title)")
          appModel.navigateToMarker(nextMarker)
        }
        return
      }
    }

    // Load state flags from UserDefaults (to handle view recreations)
    if !isRandomJumpMode {
      isRandomJumpMode = UserDefaults.standard.bool(forKey: "isRandomJumpMode")
    }
    if !isMarkerShuffleMode {
      isMarkerShuffleMode = UserDefaults.standard.bool(forKey: "isMarkerShuffleMode")
    }

    print(
      "▶️ Starting next scene navigation - Modes: \(isRandomJumpMode ? "RANDOM JUMP" : "") \(isMarkerShuffleMode ? "MARKER SHUFFLE" : "") \(!isRandomJumpMode && !isMarkerShuffleMode ? "SEQUENTIAL" : "")"
    )

    // Check if we're currently viewing a marker
    let isMarkerContext = currentMarker != nil || effectiveStartTime != nil
    print("📊 Current context: \(isMarkerContext ? "MARKER" : "REGULAR SCENE")")

    // If we're in tag scene shuffle mode, use the tag shuffle system
    if appModel.isTagSceneShuffleMode {
      print("🏷️ In tag scene shuffle mode")
      print("🏷️ Queue size: \(appModel.tagSceneShuffleQueue.count)")
      print("🏷️ Current index: \(appModel.currentTagShuffleIndex)")

      if !appModel.tagSceneShuffleQueue.isEmpty {
        print("🏷️ ✅ Using tag scene shuffle queue - going to next scene")
        appModel.shuffleToNextTagScene()
        return
      } else {
        print("🏷️ ❌ Tag scene shuffle queue empty")
      }
    }

    // If we're in most played shuffle mode, use the most played shuffle system
    if appModel.isMostPlayedShuffleMode {
      print("🎯 In most played shuffle mode")
      print("🎯 Queue size: \(appModel.mostPlayedShuffleQueue.count)")
      print("🎯 Current index: \(appModel.currentMostPlayedShuffleIndex)")

      if !appModel.mostPlayedShuffleQueue.isEmpty {
        print("🎯 ✅ Using most played shuffle queue - going to next scene")
        appModel.shuffleToNextMostPlayedScene()
        return
      } else {
        print("🎯 ❌ Most played shuffle queue empty")
      }
    }

    // If we're in marker shuffle mode, use the NEW shuffle queue system
    if isMarkerShuffleMode || appModel.isMarkerShuffleMode {
      print("🎲 In marker shuffle mode - using NEW queue system")
      print("🎲 Queue size: \(appModel.markerShuffleQueue.count)")
      print("🎲 Current index: \(appModel.currentShuffleIndex)")
      print("🎲 appModel.isMarkerShuffleMode: \(appModel.isMarkerShuffleMode)")

      // If we have a shuffle queue, use it
      if !appModel.markerShuffleQueue.isEmpty {
        print("🎲 ✅ Using AppModel shuffle queue - going to next marker")
        // Just use the normal shuffle for both cases
        appModel.shuffleToNextMarker()
        return
      } else {
        print("🎲 ❌ AppModel shuffle queue empty - falling back to old system")
        // Fallback to old system if queue is empty
        if let currentMarker = currentMarker {
          handleMarkerShuffle()
          return
        }
        // If we don't have a current marker but we're in a search context, try to find markers
        else if let savedQuery = UserDefaults.standard.string(forKey: "lastMarkerSearchQuery"),
          !savedQuery.isEmpty {
          print("🔍 Using saved search query for marker shuffle: '\(savedQuery)'")
          Task {
            await shuffleToRandomMarkerFromSearch(query: savedQuery)
          }
          return
        }
      }
    }

    // Add more aggressive logging to debug
    print("📊 navigateToNextScene - current marker: \(String(describing: currentMarker))")
    print(
      "📊 navigateToNextScene - appModel.currentMarker: \(String(describing: appModel.currentMarker))"
    )
    print("📊 navigateToNextScene - effectiveStartTime: \(String(describing: effectiveStartTime))")
    print("📊 navigateToNextScene - isRandomJumpMode: \(isRandomJumpMode)")
    print("📊 navigateToNextScene - isMarkerShuffleMode: \(isMarkerShuffleMode)")

    withAnimation(.easeOut(duration: 0.2)) {
      showControls = false
    }

    // Set a failsafe timer to restore controls and keyboard responder if navigation fails
    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
      if !self.showControls {
        print("⚠️ FAILSAFE: Restoring controls after navigation timeout")
        withAnimation(.easeInOut(duration: 0.3)) {
          self.showControls = true
        }
      }
    }

    // Also set a timer to ensure keyboard shortcuts remain functional
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
      // Force keyboard responder status restoration
      if let window = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows })
        .first(where: { $0.isKeyWindow }),
        let rootVC = window.rootViewController {
        self.ensureKeyboardResponder(rootVC)
      }
    }

    // Get scenes from the app model - these represent the current context
    // (could be from a search, performer, tag, etc.)
    let contextScenes = appModel.api.scenes

    // Debug context information
    print("📊 CONTEXT DEBUG - navigateToNextScene:")
    print("📊   Current performer: \(appModel.currentPerformer?.name ?? "none")")
    print("📊   Context scenes count: \(contextScenes.count)")
    print("📊   Current scene: \(currentScene.title ?? "Untitled") (ID: \(currentScene.id))")

    // Get current index in the context's scene array
    let currentIndex = contextScenes.firstIndex(of: currentScene) ?? -1
    print("📊 Current scene index: \(currentIndex) out of \(contextScenes.count)")

    // If current scene is in the list and there's a next one, go to it
    if currentIndex >= 0 && currentIndex < contextScenes.count - 1 {
      // Get the next scene
      let nextScene = contextScenes[currentIndex + 1]
      print("🎬 Navigating to next scene: \(nextScene.title ?? "Untitled")")

      // Update current scene reference
      currentScene = nextScene
      appModel.currentScene = nextScene

      if isRandomJumpMode {
        print("🎲 Continuing in RANDOM JUMP mode - will perform random jump in the next scene")

        // Play the scene first
        playScene(nextScene)

        // Then perform a random jump within that scene
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
          if let player = self.getCurrentPlayer() {
            // Get current duration to calculate a random position
            guard let currentItem = player.currentItem else { return }

            // Define the check duration function as a recursive function
            func checkDuration() {
              let duration = currentItem.duration.seconds
              if duration.isFinite && duration > 10 {
                // Generate a random position (10% to 90% of the video)
                let minPosition = max(5, duration * 0.1)
                let maxPosition = min(duration - 10, duration * 0.9)
                let randomPosition = Double.random(in: minPosition...maxPosition)

                print("🎲 Random jumping to \(Int(randomPosition)) seconds in next scene")

                // Set position and play
                let time = CMTime(seconds: randomPosition, preferredTimescale: 1000)
                player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                player.play()
              } else {
                // Try again after a delay if duration isn't ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                  checkDuration()
                }
              }
            }

            // Start the duration check
            checkDuration()
          }
        }
      } else {
        // Normal sequential playback
        playScene(nextScene)
      }
    } else {
      // We're at the end of the current context's list
      print("📊 Reached the end of the current context list")

      // Check if we're in a marker context
      if isMarkerContext {
        print("🏷️ In marker context, attempting to find next marker")

        // Make sure currentMarker is set in appModel if it's only set locally
        if appModel.currentMarker == nil && currentMarker != nil {
          print("🔄 Syncing current marker to appModel")
          appModel.currentMarker = currentMarker
        }

        // If we have effectiveStartTime but no marker, try to create one
        if appModel.currentMarker == nil && effectiveStartTime != nil {
          print("🔄 Creating temporary marker from effectiveStartTime")

          // Try to get the primary tag from UserDefaults
          let sceneId = currentScene.id
          let isMarkerNavigation = UserDefaults.standard.bool(
            forKey: "scene_\(sceneId)_isMarkerNavigation")

          // Use TagAPI to get a default tag
          Task {
            do {
              // Get default tag for fallback (first tag in system)
              let tagsQuery = """
                {
                    "operationName": "FindTags",
                    "variables": {
                        "filter": {
                            "page": 1,
                            "per_page": 1
                        }
                    },
                    "query": "query FindTags($filter: FindFilterType) { findTags(filter: $filter) { count tags { id name } } }"
                }
                """

              let tagData = try await appModel.api.executeGraphQLQuery(tagsQuery)

              struct TagsResponseData: Decodable {
                let data: TagData

                struct TagData: Decodable {
                  let findTags: TagsPayload

                  struct TagsPayload: Decodable {
                    let count: Int
                    let tags: [SceneMarker.Tag]
                  }
                }
              }

              let tagResponse = try JSONDecoder().decode(TagsResponseData.self, from: tagData)

              if let firstTag = tagResponse.data.findTags.tags.first {
                print("✅ Found default tag: \(firstTag.name)")

                // Create temporary marker
                let tempMarker = SceneMarker(
                  id: UUID().uuidString,
                  title: "Temporary marker at \(Int(effectiveStartTime!))",
                  seconds: Float(effectiveStartTime!),
                  end_seconds: effectiveEndTime != nil ? Float(effectiveEndTime!) : nil,
                  stream: "",
                  preview: "",
                  screenshot: "",
                  scene: SceneMarker.MarkerScene(id: currentScene.id),
                  primary_tag: firstTag,
                  tags: []
                )

                // Set as current marker
                currentMarker = tempMarker
                appModel.currentMarker = tempMarker

                // Now find next marker
                let foundNextMarker = await findNextMarkerInSameTag()
                if !foundNextMarker {
                  print("⚠️ No next marker available with temp marker, staying on current scene")
                  await MainActor.run {
                    showControls = true
                    Task {
                      await scheduleControlsHide()
                    }
                  }
                }
              }
            } catch {
              print("❌ Error fetching tags: \(error)")
            }
          }
        } else {
          // Use the regular find next marker approach
          Task {
            let foundNextMarker = await findNextMarkerInSameTag()
            if !foundNextMarker {
              print("⚠️ No next marker available, staying on current scene")
              // Return to UI controls, don't switch scenes
              await MainActor.run {
                showControls = true
                Task {
                  await scheduleControlsHide()
                }
              }
            }
          }
        }
      } else {
        print("⚠️ At end of context list, looping back to beginning")
        // Loop back to the first item in the list if we have scenes
        if !contextScenes.isEmpty {
          let firstScene = contextScenes[0]
          print("🔄 Looping back to first scene: \(firstScene.title ?? "Untitled")")
          currentScene = firstScene
          appModel.currentScene = firstScene

          if isRandomJumpMode {
            print("🎲 Continuing in RANDOM JUMP mode - will perform random jump in the looped scene")

            // Play the scene first
            playScene(firstScene)

            // Then perform a random jump within that scene
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
              if let player = self.getCurrentPlayer() {
                // Get current duration to calculate a random position
                guard let currentItem = player.currentItem else { return }

                // Define the check duration function as a recursive function
                func checkDuration() {
                  let duration = currentItem.duration.seconds
                  if duration.isFinite && duration > 10 {
                    // Generate a random position (10% to 90% of the video)
                    let minPosition = max(5, duration * 0.1)
                    let maxPosition = min(duration - 10, duration * 0.9)
                    let randomPosition = Double.random(in: minPosition...maxPosition)

                    print("🎲 Random jumping to \(Int(randomPosition)) seconds in looped scene")

                    // Set position and play
                    let time = CMTime(seconds: randomPosition, preferredTimescale: 1000)
                    player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                    player.play()
                  } else {
                    // Try again after a delay if duration isn't ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                      checkDuration()
                    }
                  }
                }

                // Start the duration check
                checkDuration()
              }
            }
          } else {
            // Normal sequential playback
            playScene(firstScene)
          }
        }
      }
    }
  }

  /// Fallback method to fetch any scene when female performer filtering fails
  private func fallbackToAnyScene() async {
    print("🔄 Falling back to fetch any scene")

    // CRITICAL: Clear performer context when switching to library random shuffle (fallback path)
    // This ensures subsequent M presses use the female performer from the NEW scene
    await MainActor.run {
      if appModel.currentPerformer != nil {
        print("🧹 FALLBACK SHUFFLE: Clearing appModel.currentPerformer (was: \(appModel.currentPerformer?.name ?? "nil"))")
        appModel.currentPerformer = nil
      }
      originalPerformer = nil
    }

    // Fetch any scene using the API's random sort
    await appModel.api.fetchScenes(page: 1, sort: "random", direction: "DESC")

    // Filter out VR scenes
    let filteredScenes = appModel.api.scenes.filter { scene in
      !scene.tags.contains { tag in
        tag.name.lowercased() == "vr"
      }
    }

    if let randomScene = filteredScenes.randomElement() {
      print("✅ Selected fallback random scene: \(randomScene.title ?? "Untitled")")

      // Update the current scene reference AND add to watch history
      await MainActor.run {
        currentScene = randomScene
        appModel.currentScene = randomScene

        // IMPORTANT: Add to watch history (avoid duplicates of consecutive same scene)
        if appModel.watchHistory.last?.id != randomScene.id {
          appModel.watchHistory.append(randomScene)
          // Keep history to reasonable size (last 20 scenes)
          if appModel.watchHistory.count > 20 {
            appModel.watchHistory = Array(appModel.watchHistory.suffix(20))
          }
          print(
            "🔄 FALLBACK SHUFFLE: Added to watch history: \(randomScene.title ?? "Untitled") (history count: \(appModel.watchHistory.count))"
          )
        }

        // When shuffling to a new scene, update the original performer with female preference
        let femalePerformer = randomScene.performers.first { isLikelyFemalePerformer($0) }
        let newPerformer = femalePerformer ?? randomScene.performers.first
        if let newPerformer = newPerformer {
          print(
            "🔄 Updating original performer to: \(newPerformer.name) (gender: \(newPerformer.gender ?? "unknown"))"
          )
          originalPerformer = newPerformer
        }
      }

      // Get the player and play the scene
      if let player = getCurrentPlayer() {
        guard let streamURL = VideoPlayerUtility.getStreamURL(for: randomScene) else {
          print("❌ Fallback shuffle: No stream URL for scene \(randomScene.id)")
          return
        }
        let playerItem = AVPlayerItem(url: streamURL)

        player.replaceCurrentItem(with: playerItem)
        player.play()

        // Enhanced shuffle: Jump to a random position in the fallback scene after minimal delay
        // Wait for the player to be ready before jumping to random position
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
          print("🎲 Fallback shuffle: Jumping to random position in new scene")
          VideoPlayerUtility.jumpToRandomPosition(in: player)
        }

        // Add observer for playback progress
        let interval = CMTime(seconds: 5, preferredTimescale: 1)
        player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
          let seconds = CMTimeGetSeconds(time)
          if seconds > 0 {
            UserDefaults.standard.setVideoProgress(seconds, for: randomScene.id)
          }
        }

        // Reset controls visibility
        await MainActor.run {
          showControls = true
          Task {
            await scheduleControlsHide()
          }
        }
      }
    } else {
      print("⚠️ No scenes available at all")
    }
  }

  /// Plays a different scene featuring the same performer from current scene
  private func playPerformerRandomVideo() {
    print("🎯 PERFORMER BUTTON: Starting performer random video function")

    // Prevent rapid-fire calls
    guard !isPerformerShuffleInProgress else {
      print("🎯 PERFORMER BUTTON: Already in progress, ignoring duplicate call")
      return
    }

    isPerformerShuffleInProgress = true

    // Add timeout to prevent getting stuck in shuffle state
    DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
      if self.isPerformerShuffleInProgress {
        print("⚠️ PERFORMER BUTTON: Timeout reached, resetting shuffle flag")
        self.isPerformerShuffleInProgress = false
      }
    }

    // Clear shuffle context when doing performer random jumps to prevent empty queue issues
    // CRITICAL: Check BOTH local and appModel flags - local may be true when appModel is false
    let wasInMarkerShuffle = appModel.isMarkerShuffleMode || isMarkerShuffleMode
    if wasInMarkerShuffle {
      print("🎯 PERFORMER BUTTON: Switching FROM marker shuffle TO performer shuffle")
      print("🎯 PERFORMER BUTTON: Flags - appModel.isMarkerShuffleMode: \(appModel.isMarkerShuffleMode), local isMarkerShuffleMode: \(isMarkerShuffleMode)")

      // CRITICAL: Save marker shuffle state BEFORE clearing so we can restore when returning
      appModel.saveMarkerShuffleState()

      print("🎯 PERFORMER BUTTON: Clearing shuffle context to prevent empty queue issues")
      appModel.isMarkerShuffleMode = false
      appModel.markerShuffleQueue = []
      appModel.currentShuffleIndex = 0
      appModel.shuffleTagFilter = nil
      appModel.shuffleSearchQuery = nil
      UserDefaults.standard.set(false, forKey: "isMarkerShuffleContext")

      // IMPORTANT: Do NOT clear appModel.currentPerformer when coming from marker shuffle!
      // navigateToMarker() sets currentPerformer to the female performer from the destination scene,
      // and we want to KEEP that performer context so M press shuffles the correct performer.
      print("🎯 PERFORMER BUTTON: Preserving appModel.currentPerformer from marker navigation: \(appModel.currentPerformer?.name ?? "nil")")

      // CRITICAL FIX: Clear performerDetailViewPerformer when coming from marker shuffle
      // This stale value from previous PerformerDetailView browsing takes Priority 1 in performer selection
      // and would override the correct currentPerformer set by marker navigation
      if appModel.performerDetailViewPerformer != nil {
        print("🎯 PERFORMER BUTTON: Clearing stale performerDetailViewPerformer: \(appModel.performerDetailViewPerformer?.name ?? "nil")")
        appModel.performerDetailViewPerformer = nil
      }

      // Set performer shuffle mode so V key knows to restore markers
      appModel.isPerformerShuffleMode = true
      print("🎯 PERFORMER BUTTON: Set isPerformerShuffleMode = true")
    }

    // CRITICAL: Clear local VideoPlayerView marker state to prevent state leakage
    // This ensures we don't have stale marker context when switching to performer shuffle
    isMarkerShuffleMode = false
    currentMarker = nil
    print("🎯 PERFORMER BUTTON: Cleared local marker state (isMarkerShuffleMode=false, currentMarker=nil)")

    // CRITICAL: Sync originalPerformer with current performer context
    // When user taps a different performer, performerDetailViewPerformer is updated
    // We must sync originalPerformer to use the NEW performer, not the old one
    if let detailPerformer = appModel.performerDetailViewPerformer {
      if originalPerformer?.id != detailPerformer.id {
        print("🎯 PERFORMER BUTTON: Updating originalPerformer from \(originalPerformer?.name ?? "nil") to \(detailPerformer.name)")
        originalPerformer = detailPerformer
      }
    }

    // Debug context information
    print("📊 CONTEXT DEBUG - playPerformerRandomVideo:")
    print("📊   Current performer: \(appModel.currentPerformer?.name ?? "none")")
    print("📊   Original performer: \(originalPerformer?.name ?? "none")")
    print(
      "📊   PerformerDetailView performer: \(appModel.performerDetailViewPerformer?.name ?? "none")")
    print("📊   Context scenes count: \(appModel.api.scenes.count)")

    print(
      "🎯 PERFORMER BUTTON: Current scene: \(currentScene.title ?? "Untitled") (ID: \(currentScene.id))"
    )

    // Enhanced performer selection with persistent context
    var selectedPerformer: StashScene.Performer?

    // Debug logging to track state across view recreations
    print("📊 PERFORMER STATE DEBUG:")
    print("📊   appModel.currentPerformer: \(appModel.currentPerformer?.name ?? "nil")")
    print("📊   appModel.performerDetailViewPerformer: \(appModel.performerDetailViewPerformer?.name ?? "nil")")
    print("📊   originalPerformer (@State): \(originalPerformer?.name ?? "nil")")
    print("📊   currentScene performers: \(currentScene.performers.map { $0.name }.joined(separator: ", "))")

    print("🎯 PERFORMER BUTTON: Current scene performers:")
    for performer in currentScene.performers {
      print(
        "📊   - \(performer.name) (ID: \(performer.id), gender: \(performer.gender ?? "unknown"))")
    }

    // Priority 1: Use performerDetailViewPerformer if set (from PerformerDetailView context)
    if let detailViewPerformer = appModel.performerDetailViewPerformer {
      print("🎯 PERFORMER BUTTON: DetailView performer available: \(detailViewPerformer.name) (ID: \(detailViewPerformer.id))")
      // Check if this performer is in the current scene
      if currentScene.performers.contains(where: { $0.id == detailViewPerformer.id }) {
        selectedPerformer = detailViewPerformer
        print("🎯 PERFORMER BUTTON: Using performer from DetailView context: \(detailViewPerformer.name)")
      } else {
        // Keep the DetailView performer context but look for same gender in current scene
        let sameGenderPerformer = currentScene.performers.first { $0.gender == detailViewPerformer.gender }
        selectedPerformer = sameGenderPerformer ?? currentScene.performers.first
        print("🎯 PERFORMER BUTTON: DetailView performer \(detailViewPerformer.name) not in scene, using same gender: \(selectedPerformer?.name ?? "none")")
      }
    }
    // Priority 2: Use appModel.currentPerformer (survives view recreation - MOST RELIABLE)
    // ALWAYS use this performer when set - we want to find MORE of their scenes
    else if let currentPerf = appModel.currentPerformer {
      selectedPerformer = currentPerf
      if currentScene.performers.contains(where: { $0.id == currentPerf.id }) {
        print("🎯 PERFORMER BUTTON: Using performer from appModel.currentPerformer (in scene): \(currentPerf.name)")
      } else {
        print("🎯 PERFORMER BUTTON: Using performer from appModel.currentPerformer (searching for more scenes): \(currentPerf.name)")
      }
    }
    // Priority 3: Use originalPerformer if it's in the current scene (fallback - may be stale due to view recreation)
    else if let originalPerf = originalPerformer,
      currentScene.performers.contains(where: { $0.id == originalPerf.id }) {
      selectedPerformer = originalPerf
      print("🎯 PERFORMER BUTTON: Using original performer from current scene: \(originalPerf.name)")
    }
    // Priority 4: Default to female performer from current scene
    else {
      let femalePerformer = currentScene.performers.first { isLikelyFemalePerformer($0) }
      selectedPerformer = femalePerformer ?? currentScene.performers.first
      print(
        "🎯 PERFORMER BUTTON: Using female performer from current scene: \(selectedPerformer?.name ?? "none")"
      )

      // Update the originalPerformer to match this performer from current scene
      originalPerformer = selectedPerformer
    }
    
    // Always update appModel.currentPerformer to maintain context
    if let selectedPerformer = selectedPerformer {
      appModel.currentPerformer = selectedPerformer
    }

    // Make sure we have a performer to work with
    guard let selectedPerformer = selectedPerformer else {
      print("⚠️ PERFORMER BUTTON: No performers in the current scene, cannot shuffle")

      // Reset performer shuffle flag
      isPerformerShuffleInProgress = false

      // Just play a random position in current scene instead
      playNextScene()
      return
    }

    print(
      "🎯 PERFORMER BUTTON: Selected performer: \(selectedPerformer.name) (ID: \(selectedPerformer.id), gender: \(selectedPerformer.gender ?? "unknown"))"
    )
    print(
      "🎯 PERFORMER BUTTON: Current scene ID: \(currentScene.id), title: \(currentScene.title ?? "Untitled")"
    )

    // Track the performer being shuffled for performer shuffle mode
    appModel.performerShufflePerformer = selectedPerformer

    // Start a task to find and play another scene with this performer
    Task {
      print("🎯 PERFORMER BUTTON: Fetching scenes with performer ID: \(selectedPerformer.id)")

      // Use direct API method to find scenes with this performer
      // Modified to include gender filter for female performers
      let query = """
        {
            "operationName": "FindScenes",
            "variables": {
                "filter": {
                    "page": 1,
                    "per_page": 100,
                    "sort": "date",
                    "direction": "DESC"
                },
                "scene_filter": {
                    "performers": {
                        "value": ["\(selectedPerformer.id)"],
                        "modifier": "INCLUDES"
                    }
                }
            },
            "query": "query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) { findScenes(filter: $filter, scene_filter: $scene_filter) { count scenes { id title details paths { screenshot preview stream } files { size duration video_codec width height } performers { id name gender scene_count } tags { id name } rating100 } } }"
        }
        """

      do {
        print("🎯 PERFORMER BUTTON: Executing GraphQL query for performer scenes")
        let data = try await appModel.api.executeGraphQLQuery(query)

        struct FindScenesResponse: Decodable {
          struct Data: Decodable {
            struct FindScenes: Decodable {
              let count: Int
              let scenes: [StashScene]
            }
            let findScenes: FindScenes
          }
          let data: Data
        }

        let response = try JSONDecoder().decode(FindScenesResponse.self, from: data)
        let performerScenes = response.data.findScenes.scenes

        print(
          "🎯 PERFORMER BUTTON: Found \(performerScenes.count) scenes with performer \(selectedPerformer.name)"
        )

        // Filter out the current scene and VR scenes (API should already filter VR, but double-check)
        let otherScenes = performerScenes.filter { scene in
          // Filter out the current scene
          if scene.id == currentScene.id {
            return false
          }

          // Double-check for VR tag filtering
          if scene.tags.contains(where: { $0.name.lowercased() == "vr" }) {
            print("⚠️ PERFORMER BUTTON: Found VR scene despite filtering: \(scene.id)")
            return false
          }

          return true
        }

        print(
          "🎯 PERFORMER BUTTON: Current scene and VR filtering: \(performerScenes.count - otherScenes.count) scenes excluded"
        )
        print(
          "🎯 PERFORMER BUTTON: After filtering current scene, found \(otherScenes.count) other scenes"
        )

        // Get a random scene from this performer's scenes
        if let randomScene = otherScenes.randomElement()
          ?? (!performerScenes.isEmpty ? performerScenes[0] : nil) {
          print(
            "🎯 PERFORMER BUTTON: Selected scene: \(randomScene.title ?? "Untitled") (ID: \(randomScene.id))"
          )

          // Update the current scene reference AND add to watch history
          await MainActor.run {
            print(
              "🎯 PERFORMER BUTTON: Updating current scene reference and adding to watch history")
            
            // Preserve the performer context before navigation
            let preservedPerformer = selectedPerformer
            
            currentScene = randomScene
            appModel.currentScene = randomScene
            
            // Restore performer context after navigation
            appModel.currentPerformer = preservedPerformer
            // If we're in DetailView context, keep that too
            if appModel.performerDetailViewPerformer?.id == preservedPerformer.id {
              // Keep the DetailView context intact
              print("🎯 PERFORMER BUTTON: Preserving DetailView performer context")
            }

            // IMPORTANT: Add to watch history (avoid duplicates of consecutive same scene)
            if appModel.watchHistory.last?.id != randomScene.id {
              appModel.watchHistory.append(randomScene)
              // Keep history to reasonable size (last 20 scenes)
              if appModel.watchHistory.count > 20 {
                appModel.watchHistory = Array(appModel.watchHistory.suffix(20))
              }
              print(
                "🎯 PERFORMER BUTTON: Added to watch history: \(randomScene.title ?? "Untitled") (history count: \(appModel.watchHistory.count))"
              )
            }
          }

          // Get the player from the current view controller
          if let player = getCurrentPlayer() {
            print("🎯 PERFORMER BUTTON: Got player reference, preparing to play new content")

            // Create a new player item using codec-aware URL (direct play for h264/hevc, HLS otherwise)
            guard let streamURL = VideoPlayerUtility.getStreamURL(for: randomScene) else {
              print("❌ Performer button shuffle: No stream URL for scene \(randomScene.id)")
              return
            }
            print("🎯 PERFORMER BUTTON: Created stream URL: \(streamURL.absoluteString)")
            let playerItem = AVPlayerItem(url: streamURL)

            print("🎯 PERFORMER BUTTON: Creating new player item with URL: \(streamURL.absoluteString)")

            // Replace the current item in the player
            player.replaceCurrentItem(with: playerItem)
            player.play()

            print(
              "🎯 PERFORMER BUTTON: Started playing random scene with performer: \(selectedPerformer.name)"
            )

            // Generate a random position to seek to (between 20% and 80% of video)
            // Use minimal delay for faster video switching
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
              print("🎯 PERFORMER BUTTON: First delayed seek timer fired")

              guard let player = getCurrentPlayer(),
                let currentItem = player.currentItem
              else {
                print("⚠️ PERFORMER BUTTON: Player or item is nil in delayed seek")
                return
              }

              print("🎯 PERFORMER BUTTON: Current item status: \(currentItem.status.rawValue)")

              // Helper function to handle the actual seek
              func attemptSeek(with player: AVPlayer, item: AVPlayerItem, isRetry: Bool = false) {
                // Use VideoPlayerUtility to handle the seek with full fallback logic
                // This will work even if the player isn't fully loaded
                let success = VideoPlayerUtility.jumpToRandomPosition(in: player)
                if success {
                  print("✅ PERFORMER BUTTON: Successfully jumped to random position using utility")
                } else if !isRetry {
                  print("⚠️ PERFORMER BUTTON: Failed to jump, will retry shortly")

                  // Last resort retry
                  DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard let player = getCurrentPlayer(),
                      let currentItem = player.currentItem
                    else { return }

                    print("🎯 PERFORMER BUTTON: Final retry for seeking")
                    attemptSeek(with: player, item: currentItem, isRetry: true)
                  }
                }
              }

              // If the player is ready, use its duration
              if currentItem.status == .readyToPlay {
                let duration = currentItem.duration.seconds
                if !duration.isNaN && duration.isFinite && duration > 0 {
                  print("🎯 PERFORMER BUTTON: Player ready with duration: \(duration) seconds")
                  attemptSeek(with: player, item: currentItem)
                } else {
                  print(
                    "⚠️ PERFORMER BUTTON: Player ready but duration not valid: \(duration), will still attempt seek"
                  )
                  attemptSeek(with: player, item: currentItem)
                }
              } else {
                print(
                  "⚠️ PERFORMER BUTTON: Player not ready for seeking, status: \(currentItem.status.rawValue)"
                )
                print("🎯 PERFORMER BUTTON: Will retry after short delay")

                // Try again after minimal delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                  print("🎯 PERFORMER BUTTON: Retry delayed seek timer fired")
                  guard let player = getCurrentPlayer(),
                    let currentItem = player.currentItem
                  else { return }

                  print(
                    "🎯 PERFORMER BUTTON: Retry - current item status: \(currentItem.status.rawValue)"
                  )
                  attemptSeek(with: player, item: currentItem)
                }
              }
            }

            // Add observer for playback progress
            let interval = CMTime(seconds: 5, preferredTimescale: 1)
            player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
              let seconds = CMTimeGetSeconds(time)
              if seconds > 0 {
                UserDefaults.standard.setVideoProgress(seconds, for: randomScene.id)
              }
            }

            // Provide haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            // Reset the controls visibility
            await MainActor.run {
              showControls = true
              Task {
                await scheduleControlsHide()
              }
              // Reset performer shuffle flag
              isPerformerShuffleInProgress = false
            }
          } else {
            print("⚠️ PERFORMER BUTTON: Failed to get player reference")
            // Reset performer shuffle flag on error
            await MainActor.run {
              isPerformerShuffleInProgress = false
            }
          }
        } else {
          print(
            "⚠️ PERFORMER BUTTON: No other scenes found with performer \(selectedPerformer.name), trying broader search for the same performer"
          )

          // First try a broader search for the same performer (different query parameters)
          let fallbackQuery = """
            {
                "operationName": "FindScenes",
                "variables": {
                    "filter": {
                        "page": 1,
                        "per_page": 100,
                        "sort": "random",
                        "direction": "ASC"
                    },
                    "scene_filter": {
                        "performers": {
                            "value": ["\(selectedPerformer.id)"],
                            "modifier": "INCLUDES"
                        }
                    }
                },
                "query": "query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) { findScenes(filter: $filter, scene_filter: $scene_filter) { count scenes { id title details paths { screenshot preview stream } files { size duration video_codec width height } performers { id name gender scene_count } tags { id name } rating100 } } }"
            }
            """

          do {
            print("🎯 PERFORMER BUTTON: Executing broader fallback query for same performer")
            let fallbackData = try await appModel.api.executeGraphQLQuery(fallbackQuery)

            let fallbackResponse = try JSONDecoder().decode(
              FindScenesResponse.self, from: fallbackData)
            let performerScenes = fallbackResponse.data.findScenes.scenes

            print(
              "🎯 PERFORMER BUTTON: Found \(performerScenes.count) scenes with performer using broader query"
            )

            // Filter out the current scene and VR scenes
            let otherPerformerScenes = performerScenes.filter { scene in
              // Filter out the current scene
              if scene.id == currentScene.id {
                return false
              }

              // Double-check for VR tag filtering
              if scene.tags.contains(where: { $0.name.lowercased() == "vr" }) {
                return false
              }

              return true
            }

            if let randomScene = otherPerformerScenes.randomElement() {
              print(
                "🎯 PERFORMER BUTTON: Selected scene with same performer: \(randomScene.title ?? "Untitled") (ID: \(randomScene.id))"
              )

              // Update the current scene reference AND add to watch history
              await MainActor.run {
                print(
                  "🎯 PERFORMER BUTTON: Updating current scene reference and adding to watch history"
                )
                
                // Preserve the performer context before navigation
                let preservedPerformer = selectedPerformer
                
                currentScene = randomScene
                appModel.currentScene = randomScene
                
                // Restore performer context after navigation
                appModel.currentPerformer = preservedPerformer
                // If we're in DetailView context, keep that too
                if appModel.performerDetailViewPerformer?.id == preservedPerformer.id {
                  // Keep the DetailView context intact
                  print("🎯 PERFORMER BUTTON (FALLBACK): Preserving DetailView performer context")
                }

                // IMPORTANT: Add to watch history (avoid duplicates of consecutive same scene)
                if appModel.watchHistory.last?.id != randomScene.id {
                  appModel.watchHistory.append(randomScene)
                  // Keep history to reasonable size (last 20 scenes)
                  if appModel.watchHistory.count > 20 {
                    appModel.watchHistory = Array(appModel.watchHistory.suffix(20))
                  }
                  print(
                    "🎯 PERFORMER BUTTON (FALLBACK): Added to watch history: \(randomScene.title ?? "Untitled") (history count: \(appModel.watchHistory.count))"
                  )
                }

                // IMPORTANT: Keep the original performer reference unchanged
                print(
                  "🎯 PERFORMER BUTTON (FALLBACK): Keeping original performer: \(selectedPerformer.name)"
                )
              }

              // Play the scene using same method as above
              if let player = getCurrentPlayer() {
                guard let streamURL = VideoPlayerUtility.getStreamURL(for: randomScene) else {
                  print("❌ Performer button fallback: No stream URL for scene \(randomScene.id)")
                  return
                }
                let playerItem = AVPlayerItem(url: streamURL)

                player.replaceCurrentItem(with: playerItem)
                player.play()

                // Add same delayed seeking as the main function
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                  VideoPlayerUtility.jumpToRandomPosition(in: player)
                }

                // Provide haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()

                // Reset the controls visibility
                await MainActor.run {
                  showControls = true
                  Task {
                    await scheduleControlsHide()
                  }
                  // Reset performer shuffle flag
                  isPerformerShuffleInProgress = false
                }
              }
            } else {
              // If no other scenes with this performer exist at all, just keep playing current scene
              print(
                "⚠️ PERFORMER BUTTON: No scenes at all found with performer \(selectedPerformer.name), staying with current scene"
              )

              // Reset performer shuffle flag
              await MainActor.run {
                isPerformerShuffleInProgress = false
              }

              // Jump to a random position in the current scene instead
              playNextScene()

              // Show a hint to the user that no other scenes found
              let generator = UINotificationFeedbackGenerator()
              generator.notificationOccurred(.warning)
            }
          } catch {
            print("⚠️ PERFORMER BUTTON: Error fetching scenes: \(error.localizedDescription)")

            // Reset performer shuffle flag on error
            await MainActor.run {
              isPerformerShuffleInProgress = false
            }

            // Jump to a random position in the current scene instead
            playNextScene()
          }
        }
      } catch {
        print("⚠️ PERFORMER BUTTON: Error fetching performer scenes: \(error)")
        print("⚠️ PERFORMER BUTTON: Falling back to regular API method")

        // Fall back to regular API method
        await appModel.api.fetchPerformerScenes(performerId: selectedPerformer.id)

        // Continue with the same flow as before - filter out current scene and VR scenes
        let otherScenes = appModel.api.scenes.filter { scene in
          // Filter out the current scene
          if scene.id == currentScene.id {
            return false
          }

          // Double-check for VR tag filtering (API should already filter it)
          if scene.tags.contains(where: { $0.name.lowercased() == "vr" }) {
            print("⚠️ PERFORMER BUTTON: Found VR scene despite API filtering: \(scene.id)")
            return false
          }

          return true
        }
        print(
          "🎯 PERFORMER BUTTON: Found \(otherScenes.count) scenes with performer using fallback method"
        )

        if let randomScene = otherScenes.randomElement() ?? appModel.api.scenes.first {
          // Update scene and play it (same implementation as above) AND add to watch history
          await MainActor.run {
            currentScene = randomScene
            appModel.currentScene = randomScene

            // IMPORTANT: Add to watch history (avoid duplicates of consecutive same scene)
            if appModel.watchHistory.last?.id != randomScene.id {
              appModel.watchHistory.append(randomScene)
              // Keep history to reasonable size (last 20 scenes)
              if appModel.watchHistory.count > 20 {
                appModel.watchHistory = Array(appModel.watchHistory.suffix(20))
              }
              print(
                "🎯 PERFORMER BUTTON (API FALLBACK): Added to watch history: \(randomScene.title ?? "Untitled") (history count: \(appModel.watchHistory.count))"
              )
            }
          }

          if let player = getCurrentPlayer() {
            guard let streamURL = VideoPlayerUtility.getStreamURL(for: randomScene) else {
              print("❌ Performer button API fallback: No stream URL for scene \(randomScene.id)")
              return
            }
            print("🎯 PERFORMER BUTTON (FALLBACK): Created stream URL: \(streamURL.absoluteString)")
            let playerItem = AVPlayerItem(url: streamURL)
            player.replaceCurrentItem(with: playerItem)
            player.play()

            // Add minimal delay seek to random position
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
              print("🎯 PERFORMER BUTTON (FALLBACK): Attempting to seek to random position")
              if let player = getCurrentPlayer() {
                // Use the improved utility method which handles all edge cases
                let success = VideoPlayerUtility.jumpToRandomPosition(in: player)
                if success {
                  print("✅ PERFORMER BUTTON (FALLBACK): Jumped to random position using utility")
                } else {
                  print("⚠️ PERFORMER BUTTON (FALLBACK): Failed initial jump, will retry")

                  // One more try after minimal delay
                  DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let player = getCurrentPlayer() {
                      VideoPlayerUtility.jumpToRandomPosition(in: player)
                    }
                  }
                }
              }
            }

            // Provide haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            // Reset controls visibility
            Task {
              await MainActor.run {
                showControls = true
                Task {
                  await scheduleControlsHide()
                }
              }
            }
          }
        } else {
          // If no other scenes with this performer exist, just go to a random spot in current scene
          print(
            "⚠️ PERFORMER BUTTON: No scenes at all found with performer \(selectedPerformer.name), staying with current scene"
          )

          // Jump to a random position in the current scene instead
          playNextScene()

          // Show a hint to the user that no other scenes found
          let generator = UINotificationFeedbackGenerator()
          generator.notificationOccurred(.warning)
        }
      }
    }
  }

  /// Jumps to a random position in the current video
  private func playNextScene() {
    // Get the current player
    guard let player = getCurrentPlayer() else {
      print("⚠️ Cannot jump to random position - player not found")
      return
    }

    // Check if we have a valid duration to work with
    guard let currentItem = player.currentItem,
      currentItem.status == .readyToPlay,
      currentItem.duration.isValid,
      !currentItem.duration.seconds.isNaN,
      currentItem.duration.seconds > 0
    else {
      print("⚠️ Cannot jump to random position - invalid duration")
      return
    }

    let duration = currentItem.duration.seconds
    print("🎲 Current video duration: \(duration) seconds")

    // Current time for logging
    let currentSeconds = currentItem.currentTime().seconds
    print("🎲 Current position: \(currentSeconds) seconds")

    // Calculate a random position between 5 minutes and 90% of the duration
    // Ensure we don't go too close to the beginning or end
    let minPosition = max(300, duration * 0.1)  // At least 5 minutes (300 seconds) or 10% in
    let maxPosition = min(duration - 10, duration * 0.9)  // At most 90% through the video

    if minPosition >= maxPosition {
      print("⚠️ Video too short for meaningful random jump")
      return
    }

    // Generate random position
    let randomPosition = Double.random(in: minPosition...maxPosition)
    let minutes = Int(randomPosition / 60)
    let seconds = Int(randomPosition) % 60

    print(
      "🎲 Jumping to random position: \(randomPosition) seconds (\(minutes):\(String(format: "%02d", seconds)))"
    )

    // Create time with higher precision timescale
    let time = CMTime(seconds: randomPosition, preferredTimescale: 1000)

    // Set tolerances for more precise seeking
    let toleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 1000)
    let toleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 1000)

    // Perform the seek operation
    print("🎲 Seeking to new position...")
    player.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter) {
      success in
      if success {
        print("✅ Successfully jumped to \(minutes):\(String(format: "%02d", seconds))")

        // Provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Make sure playback continues
        if player.timeControlStatus != .playing {
          player.play()
        }
      } else {
        print("❌ Seek operation failed")
      }
    }
  }

  /// Helper method to get the current player
  private func getCurrentPlayer() -> AVPlayer? {
    // First try to get the player from our registry
    if let player = VideoPlayerRegistry.shared.currentPlayer {
      print("▶️ Retrieved player from registry")
      return player
    }

    // Fallback to searching for player in view hierarchy
    if let playerVC = UIApplication.shared.windows.first?.rootViewController?
      .presentedViewController as? AVPlayerViewController {
      // Register this player for future use
      VideoPlayerRegistry.shared.currentPlayer = playerVC.player
      VideoPlayerRegistry.shared.playerViewController = playerVC
      print("▶️ Retrieved player from presented view controller")
      return playerVC.player
    }

    // Alternative approach if the above doesn't work
    if let playerVC = findPlayerViewController() {
      // Register this player for future use
      VideoPlayerRegistry.shared.currentPlayer = playerVC.player
      VideoPlayerRegistry.shared.playerViewController = playerVC
      print("▶️ Retrieved player using findPlayerViewController")
      return playerVC.player
    }

    print("⚠️ Failed to find player")
    return nil
  }

  /// Helper method to find the AVPlayerViewController in the view hierarchy
  private func findPlayerViewController() -> AVPlayerViewController? {
    // Try to find the player view controller in the parent hierarchy
    var parentController = UIApplication.shared.windows.first?.rootViewController
    while parentController != nil {
      if let playerVC = parentController as? AVPlayerViewController {
        return playerVC
      }
      if let presentedVC = parentController?.presentedViewController as? AVPlayerViewController {
        return presentedVC
      }
      parentController = parentController?.presentedViewController
    }
    return nil
  }

  /// Helper method to ensure keyboard responder status is maintained
  private func ensureKeyboardResponder(_ rootVC: UIViewController) {
    // Recursively find CustomPlayerViewController and ensure it's first responder
    func findAndActivatePlayer(_ vc: UIViewController) {
      if let customPlayer = vc as? CustomPlayerViewController {
        if !customPlayer.isFirstResponder {
          print("🎹 FAILSAFE: Restoring keyboard responder for CustomPlayerViewController")
          customPlayer.becomeFirstResponder()
        }
        return
      }

      // Check children
      for child in vc.children {
        findAndActivatePlayer(child)
      }

      // Check presented view controllers
      if let presented = vc.presentedViewController {
        findAndActivatePlayer(presented)
      }
    }

    findAndActivatePlayer(rootVC)
  }

  /// Helper method to play a random scene
  private func playRandomScene(_ scene: StashScene) {
    print("🎯 Playing random scene: \(scene.title ?? "Untitled") (ID: \(scene.id))")

    // Update the current scene reference
    Task {
      await MainActor.run {
        print("🎯 Updating current scene reference")
        currentScene = scene
        appModel.currentScene = scene

        // Do NOT update the original performer - keep it intact for performer button
        // This ensures that even after shuffling scenes, the performer button stays with the original performer
      }

      // Get the player from the current view controller
      if let player = getCurrentPlayer() {
        guard let streamURL = VideoPlayerUtility.getStreamURL(for: scene) else {
          print("❌ Tag shuffle update: No stream URL for scene \(scene.id)")
          return
        }
        let playerItem = AVPlayerItem(url: streamURL)

        player.replaceCurrentItem(with: playerItem)
        player.play()

        // Add minimal delay seeking to random position
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          VideoPlayerUtility.jumpToRandomPosition(in: player)
        }

        // Provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Reset the controls visibility
        await MainActor.run {
          showControls = true
          Task {
            await scheduleControlsHide()
          }
        }
      }
    }
  }

  // MARK: - Helper Functions for Next Scene Navigation

  /// Load next marker directly in the player without navigation
  private func loadNextMarkerDirectly() async {
    print("🎲 Loading next marker directly in player")

    // Get the next marker from server
    await appModel.playNextServerSideMarker()

    // The notification from playNextServerSideMarker will update the player
    // We don't need to do anything else here
    print("🎲 Waiting for player update via notification")
  }

  private func findNextMarkerInSameTag() async -> Bool {
    print("🔍 Finding next marker with same tag")
    guard let currentMarker = appModel.currentMarker else {
      print("⚠️ No current marker found in appModel")
      return false
    }

    // Get the current primary tag
    let primaryTagId = currentMarker.primary_tag.id
    print("🏷️ Looking for next marker with tag ID: \(primaryTagId)")

    do {
      // Use the existing fetchMarkersByTagAllPages method
      let sameTagMarkers = try await appModel.api.fetchMarkersByTagAllPages(tagId: primaryTagId)
      print("✅ Found \(sameTagMarkers.count) markers with the same primary tag")

      // Find the current marker's index in this array
      if let currentIndex = sameTagMarkers.firstIndex(where: { $0.id == currentMarker.id }) {
        print("📊 Current marker index: \(currentIndex) out of \(sameTagMarkers.count)")

        // If we're not at the end, go to the next marker
        if currentIndex < sameTagMarkers.count - 1 {
          let nextMarker = sameTagMarkers[currentIndex + 1]
          print("🎬 Navigating to next marker: \(nextMarker.title)")

          await MainActor.run {
            appModel.navigateToMarker(nextMarker)
          }
          return true
        } else {
          // We're at the end, loop back to the first marker
          print("🔄 At end of markers list, looping back to first")
          let firstMarker = sameTagMarkers[0]
          await MainActor.run {
            appModel.navigateToMarker(firstMarker)
          }
          return true
        }
      }
    } catch {
      print("❌ Error finding markers with same tag: \(error)")
    }

    return false
  }

  private func handleMarkerShuffle() {
    print("🔄 Starting marker shuffle functionality")

    // Set marker shuffle mode
    isMarkerShuffleMode = true
    UserDefaults.standard.set(true, forKey: "isMarkerShuffleMode")

    // If we have a current marker, shuffle to another marker with same tag
    if let currentMarker = currentMarker {
      Task {
        await findNextMarkerInSameTag()
      }
    } else {
      // No current marker, try to use search query
      if let savedQuery = UserDefaults.standard.string(forKey: "lastMarkerSearchQuery"),
        !savedQuery.isEmpty {
        print("🔍 Using saved search query for marker shuffle: '\(savedQuery)'")
        Task {
          await shuffleToRandomMarkerFromSearch(query: savedQuery)
        }
      }
    }
  }

  private func shuffleToRandomMarkerFromSearch(query: String) async {
    print("🔄 Starting marker shuffle from search query: '\(query)'")

    do {
      // Search for markers
      let markers = try await appModel.api.searchMarkers(query: query)

      if !markers.isEmpty {
        // Pick a random marker
        let randomMarker = markers.randomElement()!
        print("🎯 Selected random marker: \(randomMarker.title)")

        await MainActor.run {
          appModel.navigateToMarker(randomMarker)
        }
      } else {
        print("⚠️ No markers found for query: '\(query)'")
      }
    } catch {
      print("❌ Error searching markers: \(error)")
    }
  }

  private func playScene(_ scene: StashScene) {
    // Get the player from the current view controller
    guard let player = getCurrentPlayer() else {
      print("⚠️ Cannot play scene - player not found")
      return
    }

    // Create URL for the scene using codec-aware method
    guard let streamURL = VideoPlayerUtility.getStreamURL(for: scene) else {
      print("❌ Play scene: No stream URL for scene \(scene.id)")
      return
    }

    // Create asset with HTTP headers to ensure proper authorization
    let headers = ["User-Agent": "StashApp/iOS"]
    let asset = AVURLAsset(url: streamURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    let playerItem = AVPlayerItem(asset: asset)

    // Replace current item and play
    player.replaceCurrentItem(with: playerItem)
    player.play()

    // Reset controls
    Task {
      await MainActor.run {
        showControls = true
        Task {
          await scheduleControlsHide()
        }
      }
    }
  }

  /// Handle keyboard shortcuts for video player controls
  private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
    let key = keyPress.key

    // Handle character keys
    let character = key.character
    switch character.lowercased() {
    case "v":
      // Previous scene / Next Scene button
      print("🎹 Keyboard shortcut: V - Next Scene")
      navigateToNextScene()
      return .handled

    case "b":
      // Seek backward 30 seconds
      print("🎹 Keyboard shortcut: B - Seek backward 30 seconds")
      seekVideo(by: -30)
      return .handled

    case "n":
      // Random position jump
      print("🎹 Keyboard shortcut: N - Random position jump")
      handleRandomVideo()
      return .handled

    case "m":
      // Performer random scene
      print("🎹 Keyboard shortcut: M - Performer random scene")
      handlePerformerRandomVideo()
      return .handled

    case "<", ",":
      // Library random shuffle
      print("🎹 Keyboard shortcut: < - Library random shuffle")
      handlePureRandomVideo()
      return .handled

    case "r":
      // Restart scene from beginning
      print("🎹 Keyboard shortcut: R - Restart from beginning")
      restartFromBeginning()
      return .handled

    case "a":
      // Toggle aspect ratio correction
      print("🎹 Keyboard shortcut: A - Toggle aspect ratio correction")
      toggleAspectRatioFromVideoPlayer()
      return .handled

    default:
      break
    }

    // Handle special keys (arrows)
    if key == .leftArrow {
      print("🎹 Keyboard shortcut: ← - Seek backward 30 seconds")
      seekVideo(by: -30)
      return .handled
    }

    if key == .rightArrow {
      print("🎹 Keyboard shortcut: → - Seek forward 30 seconds")
      seekVideo(by: 30)
      return .handled
    }

    // Handle space bar for play/pause
    if key == .space {
      print("🎹 Keyboard shortcut: Space - Toggle play/pause")
      togglePlayPause()
      return .handled
    }

    return .ignored
  }

  /// Handle keyboard shortcuts from menu commands (Mac Catalyst fallback)
  private func handleMenuKeyboardShortcut(_ keyCode: UIKeyboardHIDUsage) {
    print("🎹 Menu keyboard shortcut received: \(keyCode.rawValue)")

    switch keyCode {
    case .keyboardV:
      print("🎹 Menu shortcut: V - Next Scene")
      navigateToNextScene()

    case .keyboardB:
      print("🎹 Menu shortcut: B - Seek backward 30 seconds")
      seekVideo(by: -30)

    case .keyboardN:
      print("🎹 Menu shortcut: N - Random position jump")
      handleRandomVideo()

    case .keyboardM:
      print("🎹 Menu shortcut: M - Performer random scene")
      handlePerformerRandomVideo()

    case .keyboardComma:
      print("🎹 Menu shortcut: , - Library random shuffle")
      handlePureRandomVideo()

    case .keyboardR:
      print("🎹 Menu shortcut: R - Restart from beginning")
      restartFromBeginning()

    case .keyboardA:
      print("🎹 Menu shortcut: A - Toggle aspect ratio correction")
      toggleAspectRatioFromVideoPlayer()

    case .keyboardLeftArrow:
      print("🎹 Menu shortcut: ← - Seek backward 30 seconds")
      seekVideo(by: -30)

    case .keyboardRightArrow:
      print("🎹 Menu shortcut: → - Seek forward 30 seconds")
      seekVideo(by: 30)

    case .keyboardSpacebar:
      print("🎹 Menu shortcut: Space - Toggle play/pause")
      togglePlayPause()

    default:
      print("🎹 Menu shortcut: Unhandled key code \(keyCode.rawValue)")
    }
  }

  /// Toggle play/pause state
  private func togglePlayPause() {
    guard let player = getCurrentPlayer() else {
      print("⚠️ Cannot toggle play/pause - player not found")
      return
    }

    if player.timeControlStatus == .playing {
      player.pause()
      print("⏸️ Paused playback")
    } else {
      player.play()
      print("▶️ Resumed playback")
    }

    // Provide haptic feedback
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()
  }

  /// Restart video from the beginning
  private func restartFromBeginning() {
    guard let player = getCurrentPlayer() else {
      print("⚠️ Cannot restart - player not found")
      return
    }

    print("🔄 Restarting video from beginning")

    // Seek to beginning
    player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { success in
      if success {
        print("✅ Successfully restarted from beginning")
        player.play()
      } else {
        print("❌ Failed to restart from beginning")
      }
    }

    // Provide haptic feedback
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.impactOccurred()
  }

  /// Toggle aspect ratio correction from VideoPlayerView
  private func toggleAspectRatioFromVideoPlayer() {
    // Get the current CustomPlayerViewController from the registry
    if let customVC = VideoPlayerRegistry.shared.playerViewController?.parent
      as? CustomPlayerViewController {
      print("🎥 Found CustomPlayerViewController, toggling aspect ratio")
      customVC.toggleAspectRatio()
    } else {
      print("⚠️ Could not find CustomPlayerViewController for aspect ratio toggle")
    }
  }

  /// Add scene to watch history when video starts playing
  private func addToWatchHistory() {
    // Add current scene to watch history (avoid duplicates)
    if appModel.watchHistory.last?.id != currentScene.id {
      appModel.watchHistory.append(currentScene)
      // Keep history to reasonable size (last 20 scenes)
      if appModel.watchHistory.count > 20 {
        appModel.watchHistory = Array(appModel.watchHistory.suffix(20))
      }
      print(
        "🎯 HISTORY - Added to watch history from VideoPlayerView: \(currentScene.title ?? "Untitled") (history count: \(appModel.watchHistory.count))"
      )
    } else {
      print(
        "🎯 HISTORY - Skipping duplicate scene in VideoPlayerView: \(currentScene.title ?? "Untitled")"
      )
    }
  }
}

// MARK: - FullScreenVideoPlayer
struct FullScreenVideoPlayer: UIViewControllerRepresentable {
  typealias UIViewControllerType = UIViewController  // Changed from AVPlayerViewController to UIViewController

  let url: URL
  let startTime: Double?
  let endTime: Double?
  let scenes: [StashScene]
  let currentIndex: Int
  let appModel: AppModel

  // Add coordinator to store persistent reference to player
  class Coordinator: NSObject {
    var player: AVPlayer?
    var observationToken: NSKeyValueObservation?
    var timeObserver: Any?
    var endTimeReached = false
    var timeStatusObserver: NSKeyValueObservation?
    var progressObserver: Any?

    deinit {
      // Clean up resources
      // NOTE: Time observers are now managed by VideoPlayerRegistry.cleanupObservers()
      // which is called from onDisappear and killAllAudio(). We should NOT try to
      // remove them here as they may have already been removed, or the player
      // reference here may not match the one that created the observers.
      // Attempting to remove an observer from a different player crashes with:
      // "An instance of AVPlayer cannot remove a time observer that was added by a different instance of AVPlayer."

      // Only invalidate observation tokens that are specific to this coordinator
      timeStatusObserver?.invalidate()

      // Note: observationToken is now managed by VideoPlayerRegistry
      // Don't pause here as the player may have been replaced
      player = nil
      timeObserver = nil
      progressObserver = nil
    }
  }

  func makeCoordinator() -> Coordinator {
    return Coordinator()
  }

  func makeUIViewController(context: Context) -> UIViewController {
    print("🎬 Creating video player for URL: \(url.absoluteString)")

    // Create player with the correct URL
    let finalUrl: URL
    var explicitStartTime: Double? = startTime

    // Always check if we can extract the scene ID from the URL to use the saved HLS format
    if let sceneId = extractSceneId(from: url.absoluteString),
      let savedHlsUrlString = UserDefaults.standard.string(forKey: "scene_\(sceneId)_hlsURL"),
      let savedHlsUrl = URL(string: savedHlsUrlString) {
      print("📱 Using saved exact HLS URL format: \(savedHlsUrlString)")
      finalUrl = savedHlsUrl

      // Extract timestamp from URL if present
      if let tRange = savedHlsUrlString.range(of: "t=\\d+", options: .regularExpression),
        let tValue = Int(savedHlsUrlString[tRange].replacingOccurrences(of: "t=", with: "")) {
        print("📱 Extracted timestamp from URL: \(tValue)")

        // Create player with forced seek
        explicitStartTime = Double(tValue)
      }
    } else {
      // If no saved URL, use the provided URL but make sure it's in HLS format with t parameter
      let urlString = url.absoluteString

      // Check if this is already an HLS URL
      if urlString.contains("stream.m3u8") {
        // If URL doesn't have the t parameter but has startTime, add it
        if !urlString.contains("&t=") && !urlString.contains("?t=") && startTime != nil {
          // Add t parameter to the URL
          var modifiedUrlString = urlString
          let timeParam = "t=\(Int(startTime!))"
          if modifiedUrlString.contains("?") {
            modifiedUrlString += "&\(timeParam)"
          } else {
            modifiedUrlString += "?\(timeParam)"
          }

          // Add timestamp parameter if missing
          if !modifiedUrlString.contains("_ts=") {
            let currentTimestamp = Int(Date().timeIntervalSince1970)
            modifiedUrlString += "&_ts=\(currentTimestamp)"
          }

          print("🔄 Modified URL to include t parameter: \(modifiedUrlString)")

          if let modifiedUrl = URL(string: modifiedUrlString) {
            finalUrl = modifiedUrl
          } else {
            finalUrl = url
          }
        } else {
          finalUrl = url

          // Extract t parameter if it exists in the URL
          if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let queryItems = urlComponents.queryItems,
            let tItem = queryItems.first(where: { $0.name == "t" }),
            let tValue = tItem.value,
            let tSeconds = Double(tValue) {
            print("📱 Extracted t parameter from URL: \(tSeconds)")
            explicitStartTime = tSeconds
          }
        }
      } else {
        // Not an HLS URL - could be a direct stream URL (for h264/hevc codecs)
        // Keep it as-is since getStreamURL() already made the codec-aware decision
        print("🎬 Using direct stream URL (codec-compatible): \(url.absoluteString)")
        finalUrl = url
      }
    }

    print("🎬 Final URL being used: \(finalUrl.absoluteString)")
    print("⏱ Explicit start time to use: \(String(describing: explicitStartTime))")

    // Create asset with HTTP headers if needed (helps with authorization issues)
    let headers = ["User-Agent": "StashApp/iOS"]
    let asset = AVURLAsset(url: finalUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])

    print("🎬 Creating player item with AVURLAsset")

    // CRITICAL FIX: Clean up existing player BEFORE creating new one
    // This prevents audio overlap when switching scenes
    if let existingPlayer = VideoPlayerRegistry.shared.currentPlayer {
      print("🧹 Cleaning up existing player BEFORE creating new one")
      existingPlayer.pause()
      existingPlayer.replaceCurrentItem(with: nil)
      VideoPlayerRegistry.shared.currentPlayer = nil
    }

    let playerItem = AVPlayerItem(asset: asset)
    let player = AVPlayer(playerItem: playerItem)
    let playerVC = AVPlayerViewController()
    playerVC.player = player

    // Configure player options
    playerVC.allowsPictureInPicturePlayback = true
    playerVC.showsPlaybackControls = true

    // CRITICAL: Configure video layer BEFORE playback
    playerVC.videoGravity = .resizeAspect
    print("🎬 Video gravity configured to resizeAspect")

    // Create our custom wrapper with scene information for aspect ratio correction
    let currentScene = scenes.indices.contains(currentIndex) ? scenes[currentIndex] : nil
    let customVC = CustomPlayerViewController(playerVC: playerVC, scene: currentScene)

    // DO NOT call play() here - wait for readyToPlay status
    print("🎬 Player created, waiting for ready state before playback")

    // Add timeControlStatus observer for debugging
    let timeObserver = player.observe(\.timeControlStatus, options: [.new]) { player, _ in
      switch player.timeControlStatus {
      case .playing:
        print("✅ Player status: PLAYING")
      case .paused:
        print("⚠️ Player status: PAUSED")
      case .waitingToPlayAtSpecifiedRate:
        print(
          "⏳ Player status: WAITING TO PLAY - \(player.reasonForWaitingToPlay?.rawValue ?? "Unknown reason")"
        )
      @unknown default:
        print("❓ Player status: UNKNOWN")
      }
    }
    context.coordinator.timeStatusObserver = timeObserver

    // If an end time is specified, set it on the player view model
    if let endTime = endTime,
      let playerViewModel = appModel.playerViewModel as? VideoPlayerViewModel {
      print("⏱ Setting end time on player view model: \(endTime) seconds")
      playerViewModel.endSeconds = endTime
    }

    // Store start time for use in readyToPlay observer
    // DO NOT seek or play here - wait for video to be ready

    // Add observer for readyToPlay status
    let token = playerItem.observe(\.status, options: [.new, .old]) { item, _ in
      print("🎬 Player item status changed to: \(item.status.rawValue)")

      if item.status == .readyToPlay {
        print("🎬 Player item is ready to play")

        // CRITICAL: Verify video tracks are available and ready
        let videoTracks = item.asset.tracks(withMediaType: .video)
        print("🎬 Video tracks found: \(videoTracks.count)")

        if let videoTrack = videoTracks.first {
          print("🎬 Video track details:")
          print("   - Enabled: \(videoTrack.isEnabled)")
          print("   - Playable: \(videoTrack.isPlayable)")
          print("   - Natural size: \(videoTrack.naturalSize)")
        } else {
          print("❌ WARNING: No video track found - audio only?")
        }

        // Configure audio session NOW that video is ready
        DispatchQueue.main.async {
          do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [])
            try audioSession.setActive(true)
            print("🔊 Audio session configured after video ready")
          } catch {
            print("⚠️ Failed to configure audio session: \(error)")
          }

          // Minimal delay for faster video switching
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // NOW it's safe to start playback
            player.play()
            print("▶️ Starting playback after video track verified")

            // Cancel loading timeout since video is ready and playing
            NotificationCenter.default.post(
              name: NSNotification.Name("VideoLoadingSuccess"), object: nil)

            // Handle seeking if needed
            if let t = explicitStartTime, t > 0 {
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let cmTime = CMTime(seconds: t, preferredTimescale: 1000)
                print("⏱ Seeking to \(t) seconds after playback started")

                player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { success in
                  print("⏱ Seek completed: \(success)")
                  player.play()  // Resume after seek
                  print("▶️ Playback resumed after seeking")
                }
              }
            }
          }
        }

        // Set up coordinator
        context.coordinator.player = player

        // CRITICAL FIX: Clean up existing player before setting new one
        if let existingPlayer = VideoPlayerRegistry.shared.currentPlayer, existingPlayer !== player {
          print("🧹 Cleaning up existing player before setting new one")
          existingPlayer.pause()
          existingPlayer.replaceCurrentItem(with: nil)
        }

        VideoPlayerRegistry.shared.currentPlayer = player
        VideoPlayerRegistry.shared.playerViewController = playerVC

        // Set up end time observer if needed
        if let endTime = endTime {
          print("⏱ Setting up marker end time observer at \(endTime) seconds")

          // Create a video player view model if not already set
          if appModel.playerViewModel == nil {
            let viewModel = VideoPlayerViewModel()
            viewModel.endSeconds = endTime
            appModel.playerViewModel = viewModel
          }

          // Create a precise time observer for the end time
          let endTimeObs = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
          ) { [weak player] time in
            guard !context.coordinator.endTimeReached else { return }

            if time.seconds >= endTime {
              print("🎬 Reached marker end time \(endTime), pausing playback")
              player?.pause()
              context.coordinator.endTimeReached = true

              // Provide feedback
              let generator = UINotificationFeedbackGenerator()
              generator.notificationOccurred(.success)

              // Post notification for UI to respond
              NotificationCenter.default.post(
                name: Notification.Name("MarkerEndReached"),
                object: nil
              )
            }
          }
          context.coordinator.timeObserver = endTimeObs
          // Register for cleanup on view disappear - pass player to avoid cross-player crashes
          VideoPlayerRegistry.shared.registerTimeObserver(endTimeObs, for: player)
        }

        // Add periodic time observer to monitor actual playback progress
        let progressObs = player.addPeriodicTimeObserver(
          forInterval: CMTime(seconds: 1.0, preferredTimescale: 10),
          queue: .main
        ) { time in
          print("⏱ Current playback position: \(time.seconds) seconds")
        }
        context.coordinator.progressObserver = progressObs
        // Register for cleanup on view disappear - pass player to avoid cross-player crashes
        VideoPlayerRegistry.shared.registerTimeObserver(progressObs, for: player)
      } else if item.status == .failed {
        print("❌ Player item failed: \(item.error?.localizedDescription ?? "Unknown error")")

        // Try to recover by creating a new player with direct URL
        if let directURL = URL(
          string: url.absoluteString.replacingOccurrences(of: "stream.m3u8", with: "stream")) {
          print("🔄 Attempting recovery with direct URL: \(directURL)")
          player.replaceCurrentItem(with: AVPlayerItem(url: directURL))
          player.play()

          // Cancel loading timeout since video started playing
          NotificationCenter.default.post(
            name: NSNotification.Name("VideoLoadingSuccess"), object: nil)

          // If we have an explicit start time, seek to it
          if let timeToSeek = explicitStartTime, timeToSeek > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
              print("⏱ CRITICAL: Performing recovery seek to \(timeToSeek) seconds")
              let cmTime = CMTime(seconds: timeToSeek, preferredTimescale: 1000)
              player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                player.play()
              }
            }
          }
        }
      }
    }

    // Store token in context for memory management
    context.coordinator.observationToken = token
    // Register for cleanup on view disappear
    VideoPlayerRegistry.shared.registerObservationToken(token)

    // Register with VideoPlayerRegistry for consistent access
    // CRITICAL FIX: Clean up existing player before setting new one
    if let existingPlayer = VideoPlayerRegistry.shared.currentPlayer, existingPlayer !== player {
      print("🧹 [makeCoordinator] Cleaning up existing player before setting new one")
      // Also clean up observers from the old player
      VideoPlayerRegistry.shared.cleanupObservers()
      existingPlayer.pause()
      existingPlayer.replaceCurrentItem(with: nil)
    }

    VideoPlayerRegistry.shared.currentPlayer = player
    VideoPlayerRegistry.shared.playerViewController = playerVC

    // Store reference to the player
    context.coordinator.player = player

    return customVC
  }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    // Check if we have our custom view controller
    if let customVC = uiViewController as? CustomPlayerViewController {
      let playerVC = customVC.playerVC

      // Check if we need to update player reference
      if VideoPlayerRegistry.shared.playerViewController !== playerVC {
        print("🔄 Updating registry with current player reference")
        VideoPlayerRegistry.shared.playerViewController = playerVC
        VideoPlayerRegistry.shared.currentPlayer = playerVC.player
      }

      // Try to hide the gear button again
      DispatchQueue.main.async {
        customVC.hideGearButton(in: customVC.view)
      }
    }
  }

  // Helper method to extract scene ID from URL
  private func extractSceneId(from urlString: String) -> String? {
    // Extract scene ID from URLs like http://server/scene/{id}/stream...
    if let range = urlString.range(of: "/scene/([^/]+)/", options: .regularExpression) {
      let sceneIdWithSlashes = String(urlString[range])
      // Remove "/scene/" and trailing slash
      let sceneId = sceneIdWithSlashes.replacingOccurrences(of: "/scene/", with: "")
        .replacingOccurrences(of: "/", with: "")
      print("📱 Extracted scene ID: \(sceneId)")
      return sceneId
    }
    return nil
  }
}

// Add a global singleton to store the current player
class VideoPlayerRegistry {
  static let shared = VideoPlayerRegistry()

  var currentPlayer: AVPlayer?
  var playerViewController: AVPlayerViewController?

  // Store time observers WITH their associated player for safe cleanup
  // This prevents "cannot remove observer added by different player" crashes
  private var timeObserverEntries: [(player: AVPlayer, observer: Any)] = []
  var observationTokens: [NSKeyValueObservation] = []

  private init() {}

  /// Clean up all time observers - MUST be called before disposing player
  func cleanupObservers() {
    print("🔇 Cleaning up \(timeObserverEntries.count) time observers and \(observationTokens.count) tokens")

    // Remove each observer from its ORIGINAL player (not currentPlayer)
    // This prevents crashes when the player instance has changed
    for entry in timeObserverEntries {
      entry.player.removeTimeObserver(entry.observer)
    }
    timeObserverEntries.removeAll()

    // Invalidate all observation tokens
    for token in observationTokens {
      token.invalidate()
    }
    observationTokens.removeAll()

    print("🔇 Observer cleanup complete")
  }

  /// Register a time observer for later cleanup - stores the player reference
  func registerTimeObserver(_ observer: Any, for player: AVPlayer) {
    timeObserverEntries.append((player: player, observer: observer))
  }

  /// Register an observation token for later cleanup
  func registerObservationToken(_ token: NSKeyValueObservation) {
    observationTokens.append(token)
  }

  func seek(by seconds: Double) {
    guard let player = currentPlayer,
      let currentItem = player.currentItem
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
        player.seek(to: zeroTime, toleranceBefore: .zero, toleranceAfter: .zero)
        print("⏱ Seeking to beginning of video")
        return
      } else if targetTime.seconds > duration.seconds {
        player.seek(to: duration, toleranceBefore: .zero, toleranceAfter: .zero)
        print("⏱ Seeking to end of video")
        return
      }
    }

    print("⏱ Seeking by \(seconds) seconds to \(targetTime.seconds)")
    player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { success in
      if success {
        print("✅ Successfully seeked by \(seconds) seconds")

        // Provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Ensure playback continues
        if player.timeControlStatus != .playing {
          player.play()
        }
      } else {
        print("❌ Seek operation failed")
      }
    }
  }
}
