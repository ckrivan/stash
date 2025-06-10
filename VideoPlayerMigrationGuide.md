# Video Player Migration Guide

This guide helps migrate from the old fragmented video player implementations to the new unified system.

## New Components

### 1. StandardVideoPlayer
- **Location**: `/Views/Player/StandardVideoPlayer.swift`
- **Purpose**: Unified full-screen video player replacing both `VideoPlayerView` and `CustomVideoPlayer`
- **Features**:
  - Consistent keyboard shortcuts
  - Unified gesture support (swipe, double-tap, pan)
  - Standardized button controls
  - Aspect ratio correction
  - Settings button hiding

### 2. StandardPreviewPlayer
- **Location**: `/Views/Player/StandardPreviewPlayer.swift`
- **Purpose**: Unified inline preview player for lists
- **Usage**: Replace inline players in `SceneRow` and `MarkerRow`
- **Features**:
  - Consistent UI styling
  - Proper URL handling
  - Unified control buttons
  - Error handling

### 3. KeyboardShortcutHandler
- **Location**: `/Utilities/KeyboardShortcutHandler.swift`
- **Purpose**: Centralized keyboard shortcut handling
- **Features**:
  - Single source of truth for shortcuts
  - Menu command creation
  - Notification-based communication

## Migration Steps

### Step 1: Replace Full-Screen Players

#### Old VideoPlayerView Usage:
```swift
VideoPlayerView(
    scene: scene,
    useHLS: true,
    appModel: appModel,
    onDismiss: { }
)
```

#### New StandardVideoPlayer Usage:
```swift
let player = StandardVideoPlayer(
    scenes: [scene],
    currentIndex: 0,
    sceneID: scene.id,
    appModel: appModel
)
// Present the player
present(player, animated: true)
```

### Step 2: Replace Inline Preview Players

#### Old SceneRow Preview:
```swift
VideoPlayer(player: viewModel.player) {
    // Custom overlay
}
```

#### New StandardPreviewPlayer:
```swift
StandardPreviewPlayer.forScene(
    scene,
    appModel: appModel,
    onTap: {
        // Handle tap
    }
)
```

### Step 3: Update Keyboard Handling

Remove all duplicate `pressesBegan` implementations and use the centralized handler:

```swift
override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    guard let key = presses.first?.key else {
        super.pressesBegan(presses, with: event)
        return
    }
    
    if !KeyboardShortcutHandler.handleKeyPress(key, in: player, appModel: appModel) {
        super.pressesBegan(presses, with: event)
    }
}
```

### Step 4: Update URL Construction

Use `VideoPlayerUtility` for all URL construction:

```swift
// For HLS streams
let hlsURL = VideoPlayerUtility.getHLSStreamURL(from: directURL, isMarkerURL: false)

// For thumbnails
let thumbnailURL = VideoPlayerUtility.getThumbnailURL(forSceneID: sceneID, seconds: time)
```

## Benefits of Migration

1. **Consistency**: Same UI/UX across all video players
2. **Maintainability**: Single implementation to update
3. **Bug Fixes**: Keyboard shortcuts work consistently
4. **Performance**: Reduced memory usage from duplicate implementations
5. **Features**: All players get new features automatically

## Deprecation Notes

The following files should be deprecated after migration:
- `VideoPlayerView.swift` (keep temporarily for reference)
- `CustomVideoPlayer.swift`
- `TestMarkerPlayerView.swift` (debug only)
- Inline player code in `SceneRow.swift` and `MarkerRow.swift`

## Testing Checklist

After migration, test:
- [ ] Full-screen video playback from scenes
- [ ] Full-screen video playback from markers
- [ ] Inline preview playback in lists
- [ ] All keyboard shortcuts (B, N, M, V, R, Space, arrows)
- [ ] Gesture controls (swipe, double-tap)
- [ ] Aspect ratio correction for anamorphic content
- [ ] Settings button hiding
- [ ] Progress tracking
- [ ] Memory usage and cleanup