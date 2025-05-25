I’m providing a detailed specification for implementing the MarkerView and the Markers section within PerformerView for our Stash VisionPro app, targeting iOS/iPadOS 18, with a requirement to enforce strict HLS playback for all video content. These components are essential for navigating marked moments in scenes and enhancing performer-related interactions. Below are the requirements and guidelines, aligned with our SwiftUI-based architecture and Stash API, without including code.

1. MarkerView Implementation
Purpose: A reusable view to display a list of markers (specific timestamps in a scene) for a given scene, allowing users to navigate to these points in the video player.

Requirements:

Data Source: Retrieve marker data from the StashScene model, including marker ID, title, timestamp (in seconds), and primary tag.
UI Components:
Present markers in a user-configurable scrollable list or grid.
Each marker item should display a thumbnail (from scene’s VTT/sprite endpoints), title, primary tag, and timestamp (MM:SS format).
Include a filter bar to sort by tag or timestamp.
Provide a context menu per marker for editing (title, tag) or deleting (with confirmation).
Interaction:
Tapping a marker seeks the video player to the marker’s timestamp using HLS playback.
Support drag-and-drop to reorder markers if editable.
Accessibility:
Ensure VoiceOver compatibility with descriptive labels (e.g., “Marker: Action Scene at 1:30”).
Support Dynamic Type and high contrast ratios.
Performance:
Lazy-load thumbnails and cache marker data/thumbnails using existing mechanisms.
Integration:
Embed in SceneFileInfoView and PerformerScenesView.
Coordinate with the video player for seamless seek actions.
Technical Guidelines:

File Location: Store in Stash/Features/Markers/MarkerView.swift.
Architecture: Use MVVM with a view model to manage data fetching, filtering/sorting, and player coordination.
Dependencies: Rely on AVKit for HLS playback, Combine for reactive updates, and StashAPI for GraphQL queries.
API Integration: Extend FindScene GraphQL query to include markers (ID, title, seconds, primary_tag). Fetch VTT/sprite thumbnails via URLSession.
Error Handling: Show user-friendly errors for failed API calls and log issues using the existing logger utility.
Styling: Use a minimal, visionOS-inspired design with semi-transparent backgrounds, rounded corners, and system icons for actions.
2. PerformerView > Markers Implementation
Purpose: A section within PerformerView to display all markers associated with a performer’s scenes, enabling quick access to key moments.

Requirements:

Data Source: Aggregate markers from all scenes linked to a performer via the FindPerformers GraphQL query, cross-referencing with FindScene for marker data.
UI Components:
Display markers in a scrollable list or grid, similar to MarkerView, with thumbnails, titles, tags, timestamps, and scene titles for context.
Include a filter bar to sort by tag, timestamp, or scene.
Provide a context menu for editing/deleting markers (if permitted).
Interaction:
Tapping a marker loads the corresponding scene in the video player (using HLS) and seeks to the timestamp.
Allow navigation to the full scene details view.
Accessibility: Same as MarkerView (VoiceOver, Dynamic Type, high contrast).
Performance: Use lazy loading and caching for thumbnails and data.
Integration: Embed within PerformerDetailView or PerformerScenesView, ensuring seamless navigation to the video player.
Technical Guidelines:

File Location: Extend PerformerScenesView.swift or create a new PerformerMarkersView.swift in Stash/Features/Performers/.
Architecture: Use MVVM, with a view model to handle performer-specific marker aggregation and filtering.
Dependencies: Same as MarkerView, with additional logic to query performer-related scenes.
API Integration: Use FindPerformers to get scene IDs, then FindScene for marker data. Fetch thumbnails via VTT/sprite endpoints.
Error Handling: Display errors for failed queries and log them.
Styling: Match MarkerView styling for consistency, with added context (e.g., scene title) for performer-specific markers.
3. Strict HLS Playback Requirement
Purpose: Enforce HLS streaming for all video playback in the iOS/iPadOS 18 app to ensure smooth performance, especially for HEVC/H.265 and VR content.

Requirements:

Playback Mode: Disable direct streaming; use only HLS streaming ({serverURL}/scene/{id}/stream.m3u8?apikey={key}&resolution={res}).
UI Adjustment: Remove the HLS/Direct toggle button from VideoPlayerView and related views, as only HLS will be supported.
Resolution Handling: Support HLS resolutions (240p, 480p, 720p, 1080p, 4k, original), with user-selectable options in player settings.
Fallback: Implement automatic fallback to lower resolutions if buffering occurs, prioritizing smooth playback.
Player Integration:
Configure AVPlayer in VideoPlayerView to use HLS playlists exclusively.
Ensure marker seek actions use HLS segment alignment for accurate navigation.
Performance:
Optimize HLS streaming with efficient buffering and caching.
Handle VR content (detected via tags like “vr”, “180”, “360”) with HLS to ensure compatibility.
Error Handling: Display user-friendly errors for HLS stream failures (e.g., “Unable to load video”) and log details.
Technical Guidelines:

File Modifications:
Update VideoPlayerView.swift to enforce HLS URLs and remove direct streaming logic.
Modify PreviewPlayerManager.swift to initialize AVPlayer with HLS playlists only.
Update VideoPlayerUtility.swift to handle HLS-specific seek and playback logic.
API Integration: Use HLS stream endpoints exclusively; ensure API key authentication is included in URL parameters.
Dependencies: Rely on AVKit for HLS playback and URLSession for stream fetching.
Settings: Store user-selected resolution preferences in UserDefaults, defaulting to “original” for optimal quality.
Logging: Log HLS-specific errors (e.g., stream timeouts, resolution fallback) using the existing logger.
