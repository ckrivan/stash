import Foundation
import SwiftUI
import Combine
import AVKit
import UIKit

// This file serves as a central location for importing models
// and defining type aliases to avoid compilation errors.

// Re-export all model types for use throughout the app
@_exported import struct Foundation.URL

// Type aliases for commonly used types
typealias Scene = StashScene
typealias Performer = StashScene.Performer
typealias Marker = SceneMarker