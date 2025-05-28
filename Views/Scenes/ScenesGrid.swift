import SwiftUI
import AVKit
import Foundation

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
                .cornerRadius(12)
                .shadow(radius: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                )
                .onTapGesture {
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