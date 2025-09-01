import SwiftUI

struct PerformerMarkerRow: View {
  let performer: StashScene.Performer
  @EnvironmentObject private var appModel: AppModel
  @State private var markerCount: Int = 0

  init(performer: StashScene.Performer) {
    self.performer = performer
  }

  var body: some View {
    VStack(alignment: .center, spacing: 12) {
      // Image
      if let imagePath = performer.image_path {
        AsyncImage(url: URL(string: imagePath)) { image in
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } placeholder: {
          Color.gray
        }
        .frame(width: 120, height: 120)
        .clipShape(Circle())
      }

      // Info
      VStack(alignment: .center, spacing: 4) {
        Text(performer.name)
          .font(.headline)
          .lineLimit(1)

        Text("\(markerCount) markers")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(Color(UIColor.secondarySystemBackground))
    .cornerRadius(12)
    .task {
      await fetchMarkerCount()
    }
  }

  private func fetchMarkerCount() async {
    let query = """
      {"operationName":"FindSceneMarkers","variables":{"filter":{"q":"","page":1,"per_page":1,"sort":"title","direction":"ASC"},"scene_marker_filter":{"performers":{"value":["\(performer.id)"],"modifier":"INCLUDES"}}},"query":"query FindSceneMarkers($filter: FindFilterType, $scene_marker_filter: SceneMarkerFilterType) {\\n  findSceneMarkers(filter: $filter, scene_marker_filter: $scene_marker_filter) {\\n    count\\n    __typename\\n  }\\n}"}
      """

    guard let url = URL(string: "\(appModel.serverAddress)/graphql") else { return }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("*/*", forHTTPHeaderField: "Accept")
    request.setValue(appModel.serverAddress, forHTTPHeaderField: "Origin")
    request.setValue(
      "nc_sameSiteCookielax=true; nc_sameSiteCookiestrict=true", forHTTPHeaderField: "Cookie")
    request.httpBody = query.data(using: .utf8)

    do {
      let (data, _) = try await URLSession.shared.data(for: request)

      struct MarkerCountResponse: Decodable {
        let data: DataResponse

        struct DataResponse: Decodable {
          let findSceneMarkers: MarkersResponse

          struct MarkersResponse: Decodable {
            let count: Int
          }
        }
      }

      let response = try JSONDecoder().decode(MarkerCountResponse.self, from: data)
      await MainActor.run {
        self.markerCount = response.data.findSceneMarkers.count
      }
    } catch {
      print("❌ Error fetching marker count: \(error)")
    }
  }
}
