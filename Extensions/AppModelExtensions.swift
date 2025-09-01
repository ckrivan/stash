import AVKit
import Combine
import Foundation
import SwiftUI
import UIKit

// This file extends AppModel with references to the necessary model types
// to fix compiler errors related to missing type references

extension AppModel {
  // StashScene and SceneMarker references to help with compilation
  typealias Scene = StashScene
  typealias Marker = SceneMarker

  // Import required models for our navigations
  func importModels() {
    // This is a no-op function that's just here to ensure
    // the compiler can link these types properly
    _ = StashScene.self
    _ = SceneMarker.self
    _ = StashAPI.self
  }
}
