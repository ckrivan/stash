import AVKit
import Foundation
import SwiftUI

struct ScenesGrid: View {
  let scenes: [StashScene]
  let columns: [GridItem]
  let onSceneSelected: (StashScene) -> Void
  let onTagSelected: (StashScene.Tag) -> Void
  let onPerformerSelected: (StashScene.Performer) -> Void
  let onSceneAppear: (StashScene) -> Void
  let onSceneUpdated: (StashScene) -> Void
  let isLoadingMore: Bool
  @State private var currentIndex = 0

  var body: some View {
    LazyVGrid(columns: columns, spacing: UIDevice.current.userInterfaceIdiom == .pad ? 16 : 10) {
      ForEach(Array(scenes.enumerated()), id: \.element.id) { index, scene in
        SceneRow(
          scene: scene,
          onTagSelected: onTagSelected,
          onPerformerSelected: onPerformerSelected,
          onSceneUpdated: onSceneUpdated,
          onSceneSelected: onSceneSelected
        )
        .slideIn(from: .bottom, delay: Double(index) * 0.05, duration: 0.4)
        .applyHoverEffect()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
        .onTapGesture {
          // Tapping a scene directly = watch in order (NOT shuffle mode).
          UserDefaults.standard.set(false, forKey: "isRandomJumpMode")
          onSceneSelected(scene)
        }
        .onAppear {
          onSceneAppear(scene)
        }
      }

      if isLoadingMore {
        ProgressView()
          .gridCellColumns(columns.count)
          .padding()
      }
    }
    .padding(UIDevice.current.userInterfaceIdiom == .pad ? 16 : 8)
  }
}

extension UIView {
  func centerYConstraint(to other: UIView) -> NSLayoutConstraint {
    return centerYAnchor.constraint(equalTo: other.centerYAnchor)
  }
}
