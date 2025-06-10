import UIKit
import AVKit

// MARK: - Keyboard Shortcut Handler
/// Centralized keyboard shortcut handling for video players
class KeyboardShortcutHandler {
    
    // MARK: - Shortcut Definitions
    enum VideoShortcut {
        case seekBackward30     // B, ←
        case seekForward30      // →
        case nextScene          // V
        case randomJump         // N
        case performerScene     // M
        case libraryRandom      // ,
        case restart            // R
        case playPause          // Space
        
        var description: String {
            switch self {
            case .seekBackward30: return "Seek backward 30 seconds"
            case .seekForward30: return "Seek forward 30 seconds"
            case .nextScene: return "Next scene"
            case .randomJump: return "Random position jump"
            case .performerScene: return "Performer random scene"
            case .libraryRandom: return "Library random shuffle"
            case .restart: return "Restart from beginning"
            case .playPause: return "Toggle play/pause"
            }
        }
    }
    
    // MARK: - Handle Key Press
    static func handleKeyPress(_ key: UIKeyboardHIDUsage, in player: AVPlayer?, appModel: AppModel?) -> Bool {
        guard let player = player else { return false }
        
        switch key {
        case .keyboardLeftArrow, .keyboardB:
            seekVideo(player: player, by: -30)
            return true
            
        case .keyboardRightArrow:
            seekVideo(player: player, by: 30)
            return true
            
        case .keyboardV:
            handleNextScene(player: player, appModel: appModel)
            return true
            
        case .keyboardN:
            VideoPlayerUtility.jumpToRandomPosition(in: player)
            return true
            
        case .keyboardM:
            handlePerformerScene(player: player, appModel: appModel)
            return true
            
        case .keyboardComma:
            handleLibraryRandom(player: player, appModel: appModel)
            return true
            
        case .keyboardR:
            restartFromBeginning(player: player)
            return true
            
        case .keyboardSpacebar:
            togglePlayPause(player: player)
            return true
            
        default:
            return false
        }
    }
    
    // MARK: - Video Control Methods
    private static func seekVideo(player: AVPlayer, by seconds: Double) {
        guard let currentItem = player.currentItem else { return }
        
        let currentTime = currentItem.currentTime()
        let targetTime = CMTimeAdd(currentTime, CMTime(seconds: seconds, preferredTimescale: 1000))
        
        // Clamp to valid range
        let duration = currentItem.duration
        let zeroTime = CMTime.zero
        
        if targetTime.seconds < 0 {
            player.seek(to: zeroTime, toleranceBefore: .zero, toleranceAfter: .zero)
            print("⏱ Seeking to beginning of video")
        } else if duration.isValid && !duration.seconds.isNaN && targetTime.seconds > duration.seconds {
            player.seek(to: duration, toleranceBefore: .zero, toleranceAfter: .zero)
            print("⏱ Seeking to end of video")
        } else {
            player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { success in
                if success {
                    print("✅ Successfully seeked by \(seconds) seconds")
                    
                    // Ensure playback continues
                    if player.timeControlStatus != .playing {
                        player.play()
                    }
                }
            }
        }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    private static func togglePlayPause(player: AVPlayer) {
        if player.timeControlStatus == .playing {
            player.pause()
            print("⏸️ Paused playback")
        } else {
            player.play()
            print("▶️ Resumed playback")
        }
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    private static func restartFromBeginning(player: AVPlayer) {
        player.seek(to: .zero) { success in
            if success {
                player.play()
                print("🔄 Restarted from beginning")
            }
        }
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    // MARK: - Scene Navigation Methods
    private static func handleNextScene(player: AVPlayer, appModel: AppModel?) {
        // Check if in marker shuffle mode
        if appModel?.isMarkerShuffleMode == true && !(appModel?.markerShuffleQueue.isEmpty ?? true) {
            appModel?.shuffleToNextMarker()
        } else {
            // Regular next scene behavior
            NotificationCenter.default.post(name: Notification.Name("NextSceneRequested"), object: nil)
        }
    }
    
    private static func handlePerformerScene(player: AVPlayer, appModel: AppModel?) {
        // Check if in marker shuffle mode
        if appModel?.isMarkerShuffleMode == true && !(appModel?.markerShuffleQueue.isEmpty ?? true) {
            appModel?.shuffleToPreviousMarker()
        } else {
            // Regular performer scene behavior
            NotificationCenter.default.post(name: Notification.Name("PerformerSceneRequested"), object: nil)
        }
    }
    
    private static func handleLibraryRandom(player: AVPlayer, appModel: AppModel?) {
        // Use performer scene logic for library random
        handlePerformerScene(player: player, appModel: appModel)
    }
    
    // MARK: - Menu Command Creation
    static func createMenuCommands() -> [UIKeyCommand] {
        return [
            UIKeyCommand(
                title: "Next Scene",
                action: #selector(VideoPlayerMenuHandler.handleNextScene),
                input: "V",
                modifierFlags: []
            ),
            UIKeyCommand(
                title: "Seek Backward 30s",
                action: #selector(VideoPlayerMenuHandler.handleSeekBackward),
                input: "B",
                modifierFlags: []
            ),
            UIKeyCommand(
                title: "Random Position Jump",
                action: #selector(VideoPlayerMenuHandler.handleRandomJump),
                input: "N",
                modifierFlags: []
            ),
            UIKeyCommand(
                title: "Performer Random Scene",
                action: #selector(VideoPlayerMenuHandler.handlePerformerScene),
                input: "M",
                modifierFlags: []
            ),
            UIKeyCommand(
                title: "Library Random Shuffle",
                action: #selector(VideoPlayerMenuHandler.handleLibraryRandom),
                input: ",",
                modifierFlags: []
            ),
            UIKeyCommand(
                title: "Restart from Beginning",
                action: #selector(VideoPlayerMenuHandler.handleRestart),
                input: "R",
                modifierFlags: []
            ),
            UIKeyCommand(
                title: "Seek Backward 30s",
                action: #selector(VideoPlayerMenuHandler.handleSeekBackward),
                input: UIKeyCommand.inputLeftArrow,
                modifierFlags: []
            ),
            UIKeyCommand(
                title: "Seek Forward 30s",
                action: #selector(VideoPlayerMenuHandler.handleSeekForward),
                input: UIKeyCommand.inputRightArrow,
                modifierFlags: []
            ),
            UIKeyCommand(
                title: "Play/Pause",
                action: #selector(VideoPlayerMenuHandler.handlePlayPause),
                input: " ",
                modifierFlags: []
            )
        ]
    }
}

// MARK: - Menu Handler
@objc class VideoPlayerMenuHandler: NSObject {
    @objc static func handleNextScene() {
        NotificationCenter.default.post(name: Notification.Name("MenuCommand_NextScene"), object: nil)
    }
    
    @objc static func handleSeekBackward() {
        NotificationCenter.default.post(name: Notification.Name("MenuCommand_SeekBackward"), object: nil)
    }
    
    @objc static func handleSeekForward() {
        NotificationCenter.default.post(name: Notification.Name("MenuCommand_SeekForward"), object: nil)
    }
    
    @objc static func handleRandomJump() {
        NotificationCenter.default.post(name: Notification.Name("MenuCommand_RandomJump"), object: nil)
    }
    
    @objc static func handlePerformerScene() {
        NotificationCenter.default.post(name: Notification.Name("MenuCommand_PerformerScene"), object: nil)
    }
    
    @objc static func handleLibraryRandom() {
        NotificationCenter.default.post(name: Notification.Name("MenuCommand_LibraryRandom"), object: nil)
    }
    
    @objc static func handleRestart() {
        NotificationCenter.default.post(name: Notification.Name("MenuCommand_Restart"), object: nil)
    }
    
    @objc static func handlePlayPause() {
        NotificationCenter.default.post(name: Notification.Name("MenuCommand_PlayPause"), object: nil)
    }
}