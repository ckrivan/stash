# Stash iOS App

A native iOS/iPadOS client for [Stash](https://stashapp.cc/), the open-source adult content organizer and player.

## Overview

This app provides a mobile-friendly interface to browse and play content from your Stash server, optimized for iOS and iPadOS devices.

## Features

- **Server Connection**: Connect to your Stash server using IP address and API key
- **Content Browsing**: 
  - Browse scenes with grid layout
  - View performers with detailed profiles
  - Explore content by tags
  - Search markers with exact tag matching (#tag syntax)
- **Video Playback**:
  - Native iOS video player with custom controls
  - Marker-based navigation and playback
  - Shuffle mode for continuous playback
  - Random jump functionality
  - Scene-to-scene navigation
- **Filtering & Search**:
  - Filter scenes by performers, tags, and other criteria
  - Universal search across all content types
  - Save and manage filter presets
- **Responsive Design**: Optimized for both iPad and iPhone screens

## Requirements

- iOS 18.1 or later
- iPadOS 18.1 or later
- A running Stash server instance
- Network access to your Stash server

## Installation

1. Clone this repository
2. Open `stash.xcodeproj` in Xcode
3. Build and run on your iOS device or simulator

## Configuration

On first launch, you'll need to configure:
1. Your Stash server address (e.g., `http://192.168.1.100:9999`)
2. Your Stash API key (found in Settings > Security in your Stash web interface)

## Architecture

The app is built using:
- SwiftUI for the user interface
- AVKit for video playback
- GraphQL for API communication with Stash server
- Native iOS navigation and gesture support

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

This project is licensed under the same terms as the main Stash project.

## Acknowledgments

Built for the [Stash](https://stashapp.cc/) community.