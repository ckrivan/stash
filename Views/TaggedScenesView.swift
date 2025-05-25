import SwiftUI

struct TaggedScenesView: View {
    let tag: StashScene.Tag
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedTag: StashScene.Tag?
    @Environment(\.dismiss) private var dismiss
    
    init(tag: StashScene.Tag) {
        self.tag = tag
    }
    
    private func fetchTaggedScenes() async {
        let query = """
        {
            "operationName": "FindScenes",
            "variables": {
                "filter": {
                    "page": 1,
                    "per_page": 40,
                    "sort": "date",
                    "direction": "DESC"
                },
                "scene_filter": {
                    "tags": {
                        "value": ["\(tag.id)"],
                        "modifier": "INCLUDES"
                    }
                }
            },
            "query": "query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) { findScenes(filter: $filter, scene_filter: $scene_filter) { count scenes { id title details paths { screenshot preview stream } files { size duration video_codec width height } performers { id name } tags { id name } rating100 } } }"
        }
        """

        guard let url = URL(string: "\(appModel.serverAddress)/graphql") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(appModel.serverAddress, forHTTPHeaderField: "Origin")
        request.setValue("nc_sameSiteCookielax=true; nc_sameSiteCookiestrict=true", forHTTPHeaderField: "Cookie")
        request.setValue("\(appModel.serverAddress)/scenes?c=(\"type\":\"tags\",\"value\":[\"\(tag.id)\"],\"modifier\":\"INCLUDES\")&sortby=date", forHTTPHeaderField: "Referer")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.httpBody = query.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(GraphQLResponse<ScenesResponseData>.self, from: data)

            await MainActor.run {
                self.appModel.api.scenes = response.data.findScenes.scenes
            }
        } catch {
            print("🔥 Error loading tagged scenes: \(error)")
        }
    }
    
    private func handleNavigateToScene(_ scene: StashScene) {
        if presentedAsSheet() {
            print("📱 TaggedScenesView: Dismissing sheet before navigating to scene")
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                appModel.previousView = "tag:\(tag.id)"
                appModel.navigateToScene(scene)
            }
        } else {
            print("📱 TaggedScenesView: Regular navigation to scene")
            appModel.previousView = "tag:\(tag.id)"
            appModel.navigateToScene(scene)
        }
    }
    
    private func presentedAsSheet() -> Bool {
        return true
    }
    
    private var shuffleButton: some View {
        Button(action: {
            print("🎲 Starting tag shuffle for: \(tag.name)")
            appModel.startTagSceneShuffle(forTag: tag.id, tagName: tag.name, displayedScenes: appModel.api.scenes)
        }) {
            HStack(spacing: 4) {
                Image(systemName: "shuffle")
                    .font(.system(size: 16, weight: .medium))
                Text("Shuffle")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue)
            .cornerRadius(8)
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: 16) {
                ForEach(appModel.api.scenes) { scene in
                    SceneRow(
                        scene: scene,
                        onTagSelected: { tag in
                            appModel.navigateToTag(tag)
                        },
                        onPerformerSelected: { performer in
                            appModel.navigateToPerformer(performer)
                        },
                        onSceneUpdated: { updatedScene in
                            Task {
                                await fetchTaggedScenes()
                            }
                        },
                        onSceneSelected: { scene in
                            handleNavigateToScene(scene)
                        }
                    )
                    .onTapGesture {
                        handleNavigateToScene(scene)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Tag: \(tag.name)")
        .navigationBarItems(trailing: shuffleButton)
        .task {
            await fetchTaggedScenes()
        }
        .sheet(item: $selectedTag) { tag in
            NavigationStack {
                TaggedScenesView(tag: tag)
                    .environmentObject(appModel)
            }
        }
    }
} 