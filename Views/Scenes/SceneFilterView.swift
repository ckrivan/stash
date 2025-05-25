import SwiftUI

struct SceneFilterView: View {
    let scene: StashScene
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var currentFilter: String = "default"
    
    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text("Sort Media Library")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Filter options
            VStack(spacing: 16) {
                filterButton("Default Sort", systemImage: "rectangle.grid.2x2", filter: "default") {
                    Task {
                        await appModel.api.fetchScenes(page: 1, sort: "file_mod_time", direction: "DESC")
                        dismiss()
                    }
                }
                
                filterButton("Newest Videos", systemImage: "clock", filter: "newest") {
                    Task {
                        await appModel.api.fetchScenes(page: 1, sort: "date", direction: "DESC")
                        dismiss()
                    }
                }
                
                filterButton("Most Played", systemImage: "number.circle", filter: "o_counter") {
                    Task {
                        await appModel.api.fetchScenes(page: 1, sort: "o_counter", direction: "DESC")
                        dismiss()
                    }
                }
                
                filterButton("Random Order", systemImage: "shuffle", filter: "random") {
                    Task {
                        await appModel.api.fetchScenes(page: 1, sort: "random", direction: "DESC")
                        dismiss()
                    }
                }
                
                if scene.tags.count > 0 {
                    Divider()
                    
                    Text("Filter by Tags")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(scene.tags) { tag in
                                Button {
                                    navigateToTag(tag)
                                } label: {
                                    Text(tag.name)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(12)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
                
                if scene.performers.count > 0 {
                    Divider()
                    
                    Text("Filter by Performers")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(scene.performers) { performer in
                                Button {
                                    navigateToPerformer(performer)
                                } label: {
                                    Text(performer.name)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.purple.opacity(0.1))
                                        .cornerRadius(12)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            
            Spacer()
            
            // Advanced filter button
            Button {
                // Cancel this sheet and show advanced filters
                dismiss()
                // The actual implementation would depend on how you handle advanced filters in your app
                NotificationCenter.default.post(name: Notification.Name("ShowAdvancedFilters"), object: nil)
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                    Text("Advanced Filters")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()
    }
    
    private func filterButton(_ title: String, systemImage: String, filter: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .frame(width: 24, height: 24)
                
                Text(title)
                    .font(.body)
                
                Spacer()
                
                if currentFilter == filter {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func navigateToTag(_ tag: StashScene.Tag) {
        dismiss()
        appModel.navigateToTag(tag)
    }
    
    private func navigateToPerformer(_ performer: StashScene.Performer) {
        dismiss()
        appModel.navigateToPerformer(performer)
    }
}

// Preview
struct SceneFilterView_Previews: PreviewProvider {
    static var previews: some View {
        let mockScene = StashScene(
            id: "1",
            title: "Test Scene",
            details: "Details",
            paths: StashScene.ScenePaths(
                screenshot: "",
                preview: "",
                stream: ""
            ),
            files: [
                StashScene.SceneFile(
                    size: 1000000,
                    duration: 300,
                    video_codec: "h264",
                    width: 1920,
                    height: 1080
                )
            ],
            performers: [
                StashScene.Performer(
                    id: "1",
                    name: "Performer 1",
                    gender: nil,
                    image_path: nil,
                    scene_count: 5,
                    favorite: true,
                    rating100: 80
                ),
                StashScene.Performer(
                    id: "2",
                    name: "Performer 2",
                    gender: nil,
                    image_path: nil,
                    scene_count: 10,
                    favorite: false,
                    rating100: 90
                )
            ],
            tags: [
                StashScene.Tag(id: "1", name: "Tag 1"),
                StashScene.Tag(id: "2", name: "Tag 2")
            ],
            rating100: 80,
            o_counter: 5
        )
        
        SceneFilterView(scene: mockScene)
            .environmentObject(AppModel())
    }
}