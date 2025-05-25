import Foundation
import SwiftUI
import Combine
import AVKit
import UIKit

/// This file provides an easy way to import all common models and types
/// used throughout the app to avoid missing imports in individual files.

// Re-export key types for easy import
@_exported import struct Foundation.URL
@_exported import class AVKit.AVPlayerViewController
@_exported import class AVKit.AVPlayer