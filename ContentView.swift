//
//  ContentView.swift
//  stash
//
//  Created by Charles Krivan on 11/14/24.
//

import SwiftUI
import AVKit
import os.log

// Add this extension at the top of the file after the imports
extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!
    
    static let networking = Logger(subsystem: subsystem, category: "networking")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let player = Logger(subsystem: subsystem, category: "player")
    static let connection = Logger(subsystem: subsystem, category: "connection")
    
    // Add convenience methods
    func logRequest(_ request: URLRequest) {
        let method = request.httpMethod ?? "Unknown"
        let url = request.url?.absoluteString ?? "Unknown"
        let headers = request.allHTTPHeaders?.description ?? "None"
        let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "None"
        
        self.debug("""
        🌐 HTTP Request:
        Method: \(method)
        URL: \(url)
        Headers: \(headers)
        Body: \(body)
        """)
    }
    
    func logResponse(_ response: HTTPURLResponse, data: Data?) {
        let status = response.statusCode
        let headers = response.allHeaderFields.description
        let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "None"
        
        self.debug("""
        📥 HTTP Response:
        Status: \(status)
        Headers: \(headers)
        Body: \(body)
        """)
    }
}

// Add this extension near the top of the file after the imports
extension URLRequest {
    var allHTTPHeaders: [String: String]? {
        return self.allHTTPHeaderFields
    }
}

// Add this extension near the top of the file
extension URL {
    func appendingQueryParameters(_ parameters: [String: String]) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: true)!
        var queryItems = components.queryItems ?? []
        
        for (key, value) in parameters {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        
        components.queryItems = queryItems
        return components.url!
    }
}

// MARK: - Models
struct StashScene: Identifiable, Decodable, Equatable {
    let id: String
    let title: String?
    let details: String?
    let paths: ScenePaths
    let files: [SceneFile]
    let performers: [Performer]
    let tags: [Tag]
    let rating100: Int?
    
    // Add Equatable conformance
    static func == (lhs: StashScene, rhs: StashScene) -> Bool {
        return lhs.id == rhs.id
    }
    
    struct ScenePaths: Decodable, Equatable {
        let screenshot: String
        let preview: String?
        let stream: String
    }
    
    struct SceneFile: Decodable, Equatable {
        let size: Int
        let duration: Float
        let video_codec: String?
        let width: Int?
        let height: Int?
        
        var formattedSize: String {
            let bytes = Double(size)
            let units = ["B", "KB", "MB", "GB"]
            var level = 0
            var value = bytes
            
            while value > 1024 && level < units.count - 1 {
                value /= 1024
                level += 1
            }
            
            return String(format: "%.1f %@", value, units[level])
        }
    }
    
    struct Performer: Identifiable, Decodable, Equatable {
        let id: String
        let name: String
        let gender: String?
        let image_path: String?
        let scene_count: Int?
        let favorite: Bool?
        let rating100: Int?
        
        // Add Equatable conformance
        static func == (lhs: Performer, rhs: Performer) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    struct Tag: Identifiable, Decodable, Equatable {
        let id: String
        let name: String
    }
}

// MARK: - API Response Types
struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T
}

struct ScenesResponse: Decodable {
    let findScenes: FindScenesResult
    
    struct FindScenesResult: Decodable {
        let scenes: [StashScene]
    }
}

// MARK: - API Class
class StashAPI: ObservableObject {
    @Published var scenes: [StashScene] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var performers: [StashScene.Performer] = []
    @Published var markers: [SceneMarker] = []
    @Published var markerTags: [String] = []
    @Published var allMarkerTags: [String] = []
    
    let serverAddress: String
    private var currentTask: Task<Void, Error>?
    
    init(serverAddress: String) {
        self.serverAddress = serverAddress
        print("🔥 StashAPI initialized with server: \(serverAddress)")
    }
    
    func fetchScenes(page: Int = 1, appendResults: Bool = false) async {
        // Cancel any existing task
        currentTask?.cancel()
        
        // Create new task
        currentTask = Task {
            await MainActor.run { isLoading = true }
            
            let query = """
            {
                "operationName": "FindScenes",
                "variables": {
                    "filter": {
                        "page": \(page),
                        "per_page": 20,
                        "sort": "date",
                        "direction": "DESC"
                    }
                },
                "query": "query FindScenes($filter: FindFilterType) { findScenes(filter: $filter) { scenes { id title details paths { screenshot preview stream } files { size duration video_codec width height } performers { id name } tags { id name } rating100 } } }"
            }
            """
            
            guard let url = URL(string: "\(serverAddress)/graphql") else {
                print("🔥 Invalid URL for scenes")
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = query.data(using: .utf8)
            
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let response = try JSONDecoder().decode(GraphQLResponse<ScenesResponse>.self, from: data)
                
                await MainActor.run {
                    if appendResults {
                        self.scenes.append(contentsOf: response.data.findScenes.scenes)
                        print("🔥 Added \(response.data.findScenes.scenes.count) scenes (total: \(self.scenes.count))")
                    } else {
                        self.scenes = response.data.findScenes.scenes
                        print("🔥 Loaded \(self.scenes.count) scenes")
                    }
                    self.isLoading = false
                }
            } catch {
                print("🔥 Error loading scenes: \(error)")
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
        
        // Wait for task completion
        do {
            try await currentTask?.value
        } catch {
            if error is CancellationError {
                print("🔥 Task was cancelled")
            } else {
                print("🔥 Error: \(error)")
            }
        }
    }
    
    func searchScenes(query: String) async {
        print("🔥 Searching for: \(query)")
        Logger.networking.info("🔍 Starting scene search with query: '\(query)'")
        await MainActor.run { isLoading = true }
        
        let searchQuery = """
        {
            "query": "query($filter: FindFilterType!) { findScenes(filter: $filter) { scenes { id title details paths { screenshot preview stream } files { size duration video_codec width height } performers { id name } tags { id name } rating100 } } }",
            "variables": {
                "filter": {
                    "q": "\(query)",
                    "per_page": 40
                }
            }
        }
        """
        
        guard let url = URL(string: "\(serverAddress)/graphql") else {
            Logger.networking.error("❌ Invalid URL for search")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = searchQuery.data(using: .utf8)
        
        Logger.networking.info("""
        🔍 Sending Search Request:
        Query: '\(query)'
        URL: \(url.absoluteString)
        """)
        
        do {
            let (data, httpResponse) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = httpResponse as? HTTPURLResponse {
                Logger.networking.info("📥 Search response status: \(httpResponse.statusCode)")
            }
            
            if let responseString = String(data: data, encoding: .utf8) {
                Logger.networking.debug("📦 Search response data: \(responseString)")
            }
            
            let decodedResponse = try JSONDecoder().decode(GraphQLResponse<ScenesResponse>.self, from: data)
            
            await MainActor.run {
                self.scenes = decodedResponse.data.findScenes.scenes
                Logger.networking.info("✅ Search complete: Found \(self.scenes.count) scenes")
                self.isLoading = false
            }
        } catch {
            Logger.networking.error("""
            ❌ Search failed:
            Query: '\(query)'
            Error: \(error.localizedDescription)
            """)
            
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func fetchPerformers(
        gender: String,
        minimumScenes: Int,
        page: Int = 1,
        appendResults: Bool = false
    ) async {
        print("🔥 Fetching performers page \(page)")
        
        // Build the scene count filter based on the value
        let sceneCountFilter = if minimumScenes != 0 {
            switch minimumScenes {
            case 1:
                """
                ,"scene_count": {
                    "value": "1",
                    "modifier": "EQUALS"
                }
                """
            case -5:
                """
                ,"scene_count": {
                    "value": "5",
                    "modifier": "LESS_THAN"
                }
                """
            case -10:
                """
                ,"scene_count": {
                    "value": "10",
                    "modifier": "LESS_THAN"
                }
                """
            case 3:
                """
                ,"scene_count": {
                    "value": "2",
                    "modifier": "GREATER_THAN"
                }
                """
            case 15:
                """
                ,"scene_count": {
                    "value": "15",
                    "modifier": "GREATER_THAN"
                }
                """
            default:
                ""
            }
        } else {
            ""
        }
        
        let query = """
        {
            "operationName": "FindPerformers",
            "variables": {
                "filter": {
                    "q": "",
                    "page": \(page),
                    "per_page": 25,
                    "sort": "name",
                    "direction": "ASC"
                },
                "performer_filter": {
                    "gender": {
                        "value_list": ["FEMALE"],
                        "modifier": "INCLUDES"
                    }\(sceneCountFilter)
                }
            },
            "query": "query FindPerformers($filter: FindFilterType, $performer_filter: PerformerFilterType, $performer_ids: [Int!]) { findPerformers(filter: $filter, performer_filter: $performer_filter, performer_ids: $performer_ids) { count performers { ...PerformerData __typename } __typename } } fragment PerformerData on Performer { id name disambiguation urls gender birthdate ethnicity country eye_color height_cm measurements fake_tits penis_length circumcised career_length tattoos piercings alias_list favorite ignore_auto_tag image_path scene_count image_count gallery_count group_count performer_count o_counter tags { ...SlimTagData __typename } stash_ids { stash_id endpoint __typename } rating100 details death_date hair_color weight __typename } fragment SlimTagData on Tag { id name aliases image_path parent_count child_count __typename }"
        }
        """
        
        print("🔥 Query: \(query)") // Debug print
        
        guard let url = URL(string: "\(serverAddress)/graphql") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("u=3, i", forHTTPHeaderField: "Priority")
        request.setValue("include", forHTTPHeaderField: "credentials")
        request.httpBody = query.data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            // Log raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("🔥 Performers response: \(responseString)")
            }
            
            let response = try JSONDecoder().decode(GraphQLResponse<PerformersResponse>.self, from: data)
            
            await MainActor.run {
                if appendResults {
                    self.performers.append(contentsOf: response.data.findPerformers.performers)
                    print("🔥 Added \(response.data.findPerformers.performers.count) performers (total: \(self.performers.count))")
                } else {
                    self.performers = response.data.findPerformers.performers
                    print("🔥 Loaded \(self.performers.count) performers")
                }
            }
        } catch {
            print("🔥 Error loading performers: \(error)")
            if let decodingError = error as? DecodingError {
                print("🔥 Decoding error details: \(decodingError)")
            }
        }
    }
    
    func fetchMarkers(page: Int = 1, appendResults: Bool = false) async {
        print("🔥 Fetching markers page \(page)")
        
        let query = """
        {
            "operationName": "FindSceneMarkers",
            "variables": {
                "filter": {
                    "q": "",
                    "page": \(page),
                    "per_page": 20,
                    "sort": "random_\(Int.random(in: 0...999999))",
                    "direction": "ASC"
                },
                "scene_marker_filter": {}
            },
            "query": "query FindSceneMarkers($filter: FindFilterType, $scene_marker_filter: SceneMarkerFilterType) { findSceneMarkers(filter: $filter, scene_marker_filter: $scene_marker_filter) { count scene_markers { ...SceneMarkerData __typename } __typename } } fragment SceneMarkerData on SceneMarker { id title seconds stream preview screenshot scene { id __typename } primary_tag { id name __typename } tags { id name __typename } __typename }"
        }
        """
        
        guard let url = URL(string: "\(serverAddress)/graphql") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("u=3, i", forHTTPHeaderField: "Priority")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("http://192.168.86.100:9999", forHTTPHeaderField: "Origin")
        request.setValue("nc_sameSiteCookielax=true; nc_sameSiteCookiestrict=true", forHTTPHeaderField: "Cookie")
        request.setValue("http://192.168.86.100:9999/scenes/markers", forHTTPHeaderField: "Referer")
        request.httpBody = query.data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(GraphQLResponse<SceneMarkersResponse>.self, from: data)
            
            await MainActor.run {
                if appendResults {
                    self.markers.append(contentsOf: response.data.findSceneMarkers.scene_markers)
                    print("🔥 Added \(response.data.findSceneMarkers.scene_markers.count) markers (total: \(self.markers.count))")
                } else {
                    self.markers = response.data.findSceneMarkers.scene_markers
                    print("🔥 Loaded \(self.markers.count) markers")
                }
            }
        } catch {
            print("🔥 Error loading markers: \(error)")
            if let error = error as? DecodingError {
                print("🔥 Decoding error details: \(error)")
            }
        }
    }
    
    func fetchScenesByTag(tagId: String, page: Int = 1) async {
        print("🔥 Fetching scenes for tag: \(tagId), page: \(page)")
        
        let query = """
        {
            "operationName": "FindScenes",
            "variables": {
                "filter": {
                    "page": \(page),
                    "per_page": 20,
                    "sort": "date",
                    "direction": "DESC"
                },
                "scene_filter": {
                    "tags": {
                        "value": ["\(tagId)"],
                        "modifier": "INCLUDES"
                    }
                }
            },
            "query": "query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) { findScenes(filter: $filter, scene_filter: $scene_filter) { count scenes { id title details paths { screenshot preview stream } files { size duration video_codec width height } performers { id name } tags { id name } rating100 } } }"
        }
        """
        
        guard let url = URL(string: "\(serverAddress)/graphql") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = query.data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(GraphQLResponse<ScenesResponse>.self, from: data)
            
            await MainActor.run {
                self.scenes = response.data.findScenes.scenes
                print("🔥 Loaded \(self.scenes.count) scenes for tag")
            }
        } catch {
            print(" Error loading scenes by tag: \(error)")
        }
    }
    
    func fetchAllTags() async {
        print("🔥 Fetching all tags")
        
        let query = """
        {
            "operationName": "FindTags",
            "variables": {},
            "query": "query FindTags { findTags { tags { id name scene_count } } } }"
        }
        """
        
        guard let url = URL(string: "\(serverAddress)/graphql") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = query.data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            print("🔥 Got tags response: \(String(data: data, encoding: .utf8) ?? "")")
            
            // Add decoding here once we confirm the response format
        } catch {
            print("🔥 Error fetching tags: \(error)")
        }
    }
    
    func updateSceneTags(sceneId: String, tagIds: [String]) async {
        print("🔥 Updating tags for scene \(sceneId)")
        
        let query = """
        {
            "operationName": "SceneUpdate",
            "variables": {
                "input": {
                    "id": "\(sceneId)",
                    "tag_ids": \(tagIds)
                }
            },
            "query": "mutation SceneUpdate($input: SceneUpdateInput!) { sceneUpdate(input: $input) { id tags { id name } } }"
        }
        """
        
        guard let url = URL(string: "\(serverAddress)/graphql") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = query.data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            print("🔥 Tag update response: \(String(data: data, encoding: .utf8) ?? "")")
        } catch {
            print("🔥 Error updating tags: \(error)")
        }
    }
    
    func searchMarkers(query: String, tagId: String? = nil) async {
        print("🔥 Searching markers with query: \(query)")
        
        let searchQuery = """
        {
            "operationName": "FindSceneMarkers",
            "variables": {
                "filter": {
                    "q": "\(query)",
                    "page": 1,
                    "per_page": 20,
                    "sort": "random_\(Int.random(in: 0...999999))",
                    "direction": "ASC"
                },
                "scene_marker_filter": {}
            },
            "query": "query FindSceneMarkers($filter: FindFilterType, $scene_marker_filter: SceneMarkerFilterType) {\\n  findSceneMarkers(filter: $filter, scene_marker_filter: $scene_marker_filter) {\\n    count\\n    scene_markers {\\n      ...SceneMarkerData\\n      __typename\\n    }\\n    __typename\\n  }\\n}\\n\\nfragment SceneMarkerData on SceneMarker {\\n  id\\n  title\\n  seconds\\n  stream\\n  preview\\n  screenshot\\n  scene {\\n    id\\n    __typename\\n  }\\n  primary_tag {\\n    id\\n    name\\n    __typename\\n  }\\n  tags {\\n    id\\n    name\\n    __typename\\n  }\\n  __typename\\n}"
        }
        """
        
        guard let url = URL(string: "\(serverAddress)/graphql") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(serverAddress, forHTTPHeaderField: "Origin")
        request.setValue("nc_sameSiteCookielax=true; nc_sameSiteCookiestrict=true", forHTTPHeaderField: "Cookie")
        request.httpBody = searchQuery.data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(GraphQLResponse<SceneMarkersResponse>.self, from: data)
            
            await MainActor.run {
                self.markers = response.data.findSceneMarkers.scene_markers
                print("🔥 Found \(self.markers.count) markers matching '\(query)'")
            }
        } catch {
            print("🔥 Error searching markers: \(error)")
            if let error = error as? DecodingError {
                print("🔥 Decoding error details: \(error)")
            }
        }
    }
    
    func search(query: String, type: SearchType) async {
        print("🔥 Searching \(type.rawValue) with query: \(query)")
        
        let searchQuery: String
        
        switch type {
        case .markers:
            searchQuery = """
            {
                "variables": {
                    "filter": {
                        "q": "\(query)",
                        "page": 1,
                        "per_page": 20,
                        "sort": "random_\(Int.random(in: 0...999999))",
                        "direction": "ASC"
                    },
                    "scene_marker_filter": {}
                },
                "query": "query FindSceneMarkers($filter: FindFilterType, $scene_marker_filter: SceneMarkerFilterType) { findSceneMarkers(filter: $filter, scene_marker_filter: $scene_marker_filter) { count scene_markers { id seconds stream preview screenshot scene { id } primary_tag { name } title tags { name } } } } } } } } } } } } } } } } } } } } } } }"
            }
            """
        case .scenes:
            // ... existing scenes query ...
            searchQuery = """
            {
                "operationName": "FindScenes",
                "variables": {
                    "filter": {
                        "q": "\(query)",
                        "page": 1,
                        "per_page": 40,
                        "sort": "date",
                        "direction": "DESC"
                    }
                },
                "query": "\(type.queryString)"
            }
            """
        case .performers:
            // ... existing performers query ...
            searchQuery = """
            {
                "operationName": "FindPerformers",
                "variables": {
                    "filter": {
                        "q": "\(query)",
                        "page": 1,
                        "per_page": 40,
                        "sort": "date",
                        "direction": "DESC"
                    }
                },
                "query": "\(type.queryString)"
            }
            """
        }
        
        guard let url = URL(string: "\(serverAddress)/graphql") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(serverAddress, forHTTPHeaderField: "Origin")
        request.setValue("nc_sameSiteCookielax=true; nc_sameSiteCookiestrict=true", forHTTPHeaderField: "Cookie")
        request.httpBody = searchQuery.data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("🔥 Search response: \(responseString)")
            }
            
            switch type {
            case .scenes:
                let response = try JSONDecoder().decode(GraphQLResponse<ScenesResponse>.self, from: data)
                await MainActor.run { self.scenes = response.data.findScenes.scenes }
            case .performers:
                let response = try JSONDecoder().decode(GraphQLResponse<PerformersResponse>.self, from: data)
                await MainActor.run { self.performers = response.data.findPerformers.performers }
            case .markers:
                let response = try JSONDecoder().decode(GraphQLResponse<SceneMarkersResponse>.self, from: data)
                await MainActor.run { self.markers = response.data.findSceneMarkers.scene_markers }
            }
        } catch {
            print("🔥 Search error: \(error)")
            if let error = error as? DecodingError {
                print("🔥 Decoding error details: \(error)")
            }
        }
    }
    
    enum SearchType: String {
        case scenes = "Scenes"
        case performers = "Performers"
        case markers = "SceneMarkers"
        
        var queryString: String {
            switch self {
            case .scenes:
                return "query FindScenes($filter: FindFilterType) { findScenes(filter: $filter) { scenes { id title details paths { screenshot preview stream } files { size duration video_codec width height } performers { id name } tags { id name } rating100 } } }"
            case .performers:
                return "query FindPerformers($filter: FindFilterType) { findPerformers(filter: $filter) { performers { id name gender image_path scene_count favorite rating100 } } }"
            case .markers:
                return "query FindSceneMarkers($filter: FindFilterType) { findSceneMarkers(filter: $filter) { scene_markers { id title seconds stream preview screenshot scene { id } primary_tag { id name } tags { id name } } } } }"
            }
        }
    }
}

// MARK: - Scene Row View
struct SceneRow: View {
    let scene: StashScene
    let onTagSelected: (StashScene.Tag) -> Void
    @State private var isVisible = false
    @State private var isMuted = true
    @StateObject private var previewPlayer = VideoPlayerViewModel()
    
    var body: some View {
        VStack(alignment: .leading) {
            // Thumbnail with preview
            GeometryReader { geometry in
                ZStack {
                    // Thumbnail
                    AsyncImage(url: URL(string: scene.paths.screenshot)) { image in
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                    }
                    
                    // Video preview
                    if isVisible, let previewURL = scene.paths.preview {
                        VideoPlayer(player: previewPlayer.player)
                            .onAppear {
                                previewPlayer.player.isMuted = isMuted
                            }
                    }
                    
                    // Duration and mute overlay
                    HStack {
                        if let firstFile = scene.files.first {
                            Text(formatDuration(firstFile.duration))
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial)
                                .cornerRadius(4)
                        }
                        
                        Spacer()
                        
                        if isVisible {
                            Button(action: {
                                isMuted.toggle()
                                previewPlayer.player.isMuted = isMuted
                            }) {
                                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: geometry.frame(in: .global).minY) { _, newValue in
                    let frame = geometry.frame(in: .global)
                    let isNowVisible = frame.minY > 0 && frame.maxY < UIScreen.main.bounds.height
                    
                    if isNowVisible != isVisible {
                        isVisible = isNowVisible
                        if isNowVisible {
                            startPreview()
                        } else {
                            stopPreview()
                        }
                    }
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Info section
            VStack(alignment: .leading, spacing: 8) {
                // Title and rating
                HStack {
                    Text(scene.title ?? "Untitled")
                        .font(.headline)
                        .lineLimit(1)
                    
                    if let rating = scene.rating100 {
                        Spacer()
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            Text("\(rating/20)")
                                .foregroundColor(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
                
                // Performers
                if !scene.performers.isEmpty {
                    Text(scene.performers.map { $0.name }.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // Tags
                if !scene.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(scene.tags) { tag in
                                TagView(tag: tag, onTagSelected: onTagSelected)
                            }
                        }
                    }
                }
                
                // File info
                if let firstFile = scene.files.first {
                    HStack(spacing: 12) {
                        Label(firstFile.formattedSize, systemImage: "folder")
                        if let height = firstFile.height {
                            Label("\(height)p", systemImage: "rectangle.on.rectangle")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .padding(12)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .onDisappear {
            stopPreview()
        }
    }
    
    private func formatDuration(_ duration: Float) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%.2d:%.2d:%.2d", hours, minutes, seconds)
        } else {
            return String(format: "%.2d:%.2d", minutes, seconds)
        }
    }
    
    private func startPreview() {
        if let previewURL = scene.paths.preview,
           let url = URL(string: previewURL) {
            print("🔥 Starting preview for scene: \(scene.title ?? "")")
            
            var request = URLRequest(url: url)
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("bytes=0-1146540", forHTTPHeaderField: "Range")
            
            let asset = AVURLAsset(url: url)
            let playerItem = AVPlayerItem(asset: asset)
            previewPlayer.player.replaceCurrentItem(with: playerItem)
            previewPlayer.player.isMuted = isMuted
            previewPlayer.player.play()
        }
    }
    
    private func stopPreview() {
        print("🔥 Stopping preview for scene: \(scene.title ?? "")")
        previewPlayer.cleanup()
        isVisible = false
    }
}

// Simplify VideoPlayerViewModel
class VideoPlayerViewModel: NSObject, ObservableObject {
    let player = AVPlayer()
    @Published var isLoading = true
    @Published var error: String?
    private var timeObserver: Any?
    private var playerItem: AVPlayerItem?  // Keep strong reference
    
    override init() {
        super.init()
        setupPlayer()
    }
    
    private func setupPlayer() {
        // Configure audio session
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        
        // Configure player
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        
        // Add state observer
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            self?.isLoading = false
            print("🔥 Player time update: \(self?.player.currentTime().seconds ?? 0)")
        }
    }
    
    func play(url: URL) {
        print("🔥 Playing URL: \(url)")
        
        // Create HLS URL
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        let streamPath = components.path + ".m3u8"
        components.path = streamPath
        
        guard let hlsURL = components.url else {
            print("🔥 Error creating HLS URL")
            return
        }
        
        // Create asset with options
        let assetOptions = [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "Accept": "*/*",
                "Accept-Language": "en-US,en;q=0.9",
                "Accept-Encoding": "identity",
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15",
                "Connection": "keep-alive"
            ]
        ]
        
        let asset = AVURLAsset(url: hlsURL, options: assetOptions)
        playerItem = AVPlayerItem(asset: asset)
        
        // Add item status observer
        playerItem?.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.new], context: nil)
        
        player.replaceCurrentItem(with: playerItem)
        player.play()
        
        print("🔥 Started playback")
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(AVPlayerItem.status),
           let item = object as? AVPlayerItem {
            switch item.status {
            case .readyToPlay:
                print("🔥 Player ready to play")
                isLoading = false
            case .failed:
                print("🔥 Player failed: \(String(describing: item.error))")
                error = item.error?.localizedDescription
            default:
                break
            }
        }
    }
    
    func cleanup() {
        print("🔥 Cleaning up player")
        player.pause()
        
        // Remove observers
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        if let item = playerItem {
            item.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
        }
        
        playerItem = nil
        player.replaceCurrentItem(with: nil)
    }
    
    deinit {
        cleanup()
    }
}

// Simplify VideoPlayerView to go straight to full screen
struct VideoPlayerView: View {
    let scene: StashScene
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        FullScreenVideoPlayer(url: URL(string: scene.paths.stream)!)
    }
}

// Add new FullScreenVideoPlayer
struct FullScreenVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer()
        let controller = AVPlayerViewController()
        controller.player = player
        
        // Configure for immediate full-screen playback
        controller.modalPresentationStyle = .fullScreen
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        
        // Create HLS URL
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        let streamPath = components.path + ".m3u8"
        components.path = streamPath
        
        guard let hlsURL = components.url else { return controller }
        
        // Set up asset with headers
        let assetOptions = [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "Accept": "*/*",
                "Accept-Language": "en-US,en;q=0.9",
                "Accept-Encoding": "identity",
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15",
                "Connection": "keep-alive"
            ]
        ]
        
        let asset = AVURLAsset(url: hlsURL, options: assetOptions)
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)
        
        // Start playback immediately
        player.play()
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}

struct ContentView: View {
    @State private var serverAddress: String = UserDefaults.standard.string(forKey: "serverAddress") ?? ""
    @State private var isConnected: Bool = false
    
    var body: some View {
        if isConnected {
            NavigationStack {
                TabView {
                    MediaLibraryView()
                        .tabItem {
                            Label("Scenes", systemImage: "film")
                        }
                    
                    PerformersView()
                        .tabItem {
                            Label("Performers", systemImage: "person.2")
                        }
                    
                    MarkersView(api: StashAPI(serverAddress: UserDefaults.standard.string(forKey: "serverAddress") ?? ""))
                        .tabItem {
                            Label("Markers", systemImage: "bookmark.fill")
                        }
                }
            }
        } else {
            ConnectionView(
                serverAddress: $serverAddress,
                isConnected: $isConnected
            )
        }
    }
}

// First, create a separate view for the toolbar menu
struct MediaLibraryToolbar: View {
    let onShowFilters: () -> Void
    let onRefresh: () -> Void
    
    var body: some View {
        Menu {
            Button(action: onShowFilters) {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
            }
            
            Button(action: onRefresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}

// Create a separate view for the scenes grid
struct ScenesGrid: View {
    let scenes: [StashScene]
    let columns: [GridItem]
    let onSceneSelected: (StashScene) -> Void
    let onTagSelected: (StashScene.Tag) -> Void
    let onSceneAppear: (StashScene) -> Void
    let isLoadingMore: Bool
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(scenes) { scene in
                SceneRow(scene: scene, onTagSelected: onTagSelected)
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
        .padding()
    }
}

// Simplify MediaLibraryView
struct MediaLibraryView: View {
    @StateObject private var api: StashAPI
    @State private var selectedScene: StashScene?
    @State private var showingFilters = false
    @State private var currentPage = 1
    @State private var isLoadingMore = false
    @State private var hasMorePages = true
    @State private var searchText = ""
    @State private var selectedTag: StashScene.Tag?
    
    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)
    ]
    
    init() {
        let serverAddress = UserDefaults.standard.string(forKey: "serverAddress") ?? ""
        _api = StateObject(wrappedValue: StashAPI(serverAddress: serverAddress))
    }
    
    var body: some View {
        Group {
            if api.isLoading && currentPage == 1 {
                ProgressView("Loading media...")
            } else {
                scenesContent
            }
        }
        .sheet(item: $selectedTag) { tag in
            NavigationStack {
                TaggedScenesView(tag: tag)
            }
        }
    }
    
    private var scenesContent: some View {
        ScrollView {
            ScenesGrid(
                scenes: api.scenes,
                columns: columns,
                onSceneSelected: { scene in
                    // Present video full screen
                    if let url = URL(string: scene.paths.stream) {
                        let player = AVPlayer(url: url)
                        let controller = AVPlayerViewController()
                        controller.player = player
                        controller.modalPresentationStyle = .fullScreen
                        
                        // Get the current window scene
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = windowScene.windows.first,
                           let rootViewController = window.rootViewController {
                            rootViewController.present(controller, animated: true) {
                                player.play()
                            }
                        }
                    }
                },
                onTagSelected: { selectedTag = $0 },
                onSceneAppear: { scene in
                    if scene == api.scenes.last && !isLoadingMore && hasMorePages {
                        Task {
                            await loadMoreScenes()
                        }
                    }
                },
                isLoadingMore: isLoadingMore
            )
        }
        .searchable(text: $searchText)
        .onChange(of: searchText) { _, newValue in
            Task {
                // Add debounce
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !newValue.isEmpty {
                    await api.searchScenes(query: newValue)
                } else {
                    await resetAndReload()
                }
            }
        }
        .refreshable {
            await resetAndReload()
        }
        .navigationTitle("Media Library")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                MediaLibraryToolbar(
                    onShowFilters: { showingFilters = true },
                    onRefresh: {
                        Task {
                            await resetAndReload()
                        }
                    }
                )
            }
        }
        .onAppear {
            // Only load if we haven't loaded anything yet
            if api.scenes.isEmpty {
                Task {
                    await initialLoad()
                }
            }
        }
        .sheet(item: $selectedScene) { scene in
            VideoPlayerView(scene: scene)
        }
    }
    
    private func initialLoad() async {
        currentPage = 1
        hasMorePages = true
        api.scenes = []
        await loadScenes()
    }
    
    private func resetAndReload() async {
        await initialLoad()
    }
    
    private func loadScenes() async {
        await api.fetchScenes(page: currentPage, appendResults: false)
    }
    
    private func loadMoreScenes() async {
        guard hasMorePages && !isLoadingMore else { return }
        
        isLoadingMore = true
        currentPage += 1
        
        print("🔥 Loading more scenes (page \(currentPage))")
        let previousCount = api.scenes.count
        await api.fetchScenes(page: currentPage, appendResults: true)
        
        hasMorePages = api.scenes.count > previousCount
        isLoadingMore = false
    }
}

struct ConnectionView: View {
    @Binding var serverAddress: String
    @Binding var isConnected: Bool
    @State private var isAttemptingConnection = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            Text("Connect to Stash Server")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Server Address")
                        .foregroundColor(.secondary)
                    TextField("192.168.86.100:9999", text: $serverAddress)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                    Text("Example: 192.168.86.100:9999 or localhost:9999")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: 300)
            .padding(.horizontal)
            
            Button(action: attemptConnection) {
                if isAttemptingConnection {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Text("Connect")
                        .frame(minWidth: 200)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(serverAddress.isEmpty || isAttemptingConnection)
            .controlSize(.large)
        }
        .padding()
        .alert("Connection Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func attemptConnection() {
        print("🔥 Starting connection attempt")
        print(" Server address: \(serverAddress)")
        
        guard !serverAddress.isEmpty else { return }
        
        var address = serverAddress
        if !address.hasPrefix("http://") && !address.hasPrefix("https://") {
            address = "http://" + address
        }
        if !address.contains(":9999") && !address.contains(":443") {
            if address.hasSuffix("/") {
                address.removeLast()
            }
            address += ":9999"
        }
        
        Logger.connection.info("🔄 Attempting connection to: \(address)")
        
        guard let url = URL(string: address) else {
            Logger.connection.error("❌ Invalid server address: \(address)")
            errorMessage = "Invalid server address"
            showError = true
            return
        }
        
        isAttemptingConnection = true
        
        var request = URLRequest(url: url.appendingPathComponent("graphql"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let query = """
        {
            "query": "{ stats { scene_count } }"
        }
        """
        
        request.httpBody = query.data(using: .utf8)
        Logger.connection.logRequest(request)
        
        Task {
            do {
                print("🔥 Sending connection test...")
                let (data, response) = try await URLSession.shared.data(for: request)
                print("🔥 Got response: \(response)")
                
                if let responseString = String(data: data, encoding: .utf8) {
                    print("🔥 Response data: \(responseString)")
                }
                
                await MainActor.run {
                    guard let httpResponse = response as? HTTPURLResponse else {
                        Logger.connection.error("❌ Invalid response type")
                        errorMessage = "Invalid response type"
                        showError = true
                        isAttemptingConnection = false
                        return
                    }
                    
                    Logger.connection.logResponse(httpResponse, data: data)
                    
                    switch httpResponse.statusCode {
                    case 200:
                        Logger.connection.info("✅ Successfully connected to server")
                        UserDefaults.standard.set(address, forKey: "serverAddress")
                        isConnected = true
                    case 401:
                        Logger.connection.error("🔒 Authentication required")
                        errorMessage = "Authentication required"
                        showError = true
                    case 422:
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let errors = json["errors"] as? [[String: Any]],
                           let firstError = errors.first?["message"] as? String {
                            Logger.connection.error("❌ GraphQL Error: \(firstError)")
                            errorMessage = "GraphQL Error: \(firstError)"
                        } else {
                            Logger.connection.error("❌ Invalid query format")
                            errorMessage = "Invalid query format"
                        }
                        showError = true
                    default:
                        Logger.connection.error(" Server returned error: \(httpResponse.statusCode)")
                        errorMessage = "Server returned error: \(httpResponse.statusCode)"
                        showError = true
                    }
                    
                    isAttemptingConnection = false
                }
            } catch {
                print("🔥 Connection error: \(error)")
                await MainActor.run {
                    Logger.connection.error("❌ Connection failed: \(error.localizedDescription)")
                    errorMessage = "Connection failed: \(error.localizedDescription)"
                    showError = true
                    isAttemptingConnection = false
                }
            }
        }
    }
}

// First, add these models
struct PerformersResponse: Decodable {
    let findPerformers: FindPerformersResult
    
    struct FindPerformersResult: Decodable {
        let performers: [StashScene.Performer]
        let count: Int
    }
}

// Update PerformerFilterButton
struct PerformerFilterButton: View {
    @Binding var selectedGender: String
    @Binding var minimumScenes: Int
    let onRefresh: () -> Void
    
    var body: some View {
        Menu {
            // Remove Gender menu since we're always using Female
            
            Menu("Scene Count") {
                Button("Any") { minimumScenes = 0 }
                Button("One scene only") { minimumScenes = 1 }
                Button("5 scenes or less") { minimumScenes = -5 }
                Button("10 scenes or less") { minimumScenes = -10 }
                Button("15 or more") { minimumScenes = 15 }
            }
            
            Divider()
            
            Button(action: onRefresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            
            // Show current filters
            Section {
                Text("Current Filters:")
                Text("Gender: Female")
                Text("Scenes: \(sceneCountText)")
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }
    
    private var sceneCountText: String {
        switch minimumScenes {
        case 0:
            return "Any"
        case 1:
            return "One scene only"
        case -5:
            return "5 scenes or less"
        case -10:
            return "10 scenes or less"
        case 15:
            return "15 or more"
        default:
            return "\(abs(minimumScenes))+"
        }
    }
}

// Loading indicator
struct LoadingRow: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .listRowSeparator(.hidden)
    }
}

// Update PerformersView with simpler grid layout
struct PerformersView: View {
    @StateObject private var api: StashAPI
    @State private var selectedGender = "FEMALE"
    @State private var minimumScenes = 3  // Default to 3 scenes
    @State private var currentPage = 1
    @State private var isLoadingMore = false
    @State private var hasMorePages = true
    
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]
    
    init() {
        let serverAddress = UserDefaults.standard.string(forKey: "serverAddress") ?? ""
        _api = StateObject(wrappedValue: StashAPI(serverAddress: serverAddress))
    }
    
    var body: some View {
        ScrollView {
            if api.performers.isEmpty {
                Text("No performers found")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(api.performers) { performer in
                        NavigationLink(destination: PerformerDetailView(performer: performer)) {
                            PerformerRow(performer: performer)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onAppear {
                            if performer == api.performers.last && !isLoadingMore && hasMorePages {
                                Task {
                                    await loadMorePerformers()
                                }
                            }
                        }
                    }
                    
                    if isLoadingMore {
                        LoadingRow()
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Performers")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                PerformerFilterButton(
                    selectedGender: $selectedGender,
                    minimumScenes: $minimumScenes,
                    onRefresh: {
                        Task {
                            await resetAndReload()
                        }
                    }
                )
            }
        }
        .task {
            await initialLoad()
        }
    }
    
    private func loadMorePerformers() async {
        guard !isLoadingMore else { return }
        
        isLoadingMore = true
        currentPage += 1
        await api.fetchPerformers(
            gender: selectedGender,
            minimumScenes: minimumScenes,
            page: currentPage,
            appendResults: true
        )
        isLoadingMore = false
    }
    
    private func initialLoad() async {
        currentPage = 1
        hasMorePages = true
        api.performers = []
        await loadPerformers()
    }
    
    private func resetAndReload() async {
        await initialLoad()
    }
    
    private func loadPerformers() async {
        await api.fetchPerformers(
            gender: selectedGender,
            minimumScenes: minimumScenes,
            page: currentPage,
            appendResults: false
        )
    }
}

// Update PerformerRow for better layout
struct PerformerRow: View {
    let performer: StashScene.Performer
    
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
                
                if let count = performer.scene_count {
                    Text("\(count) scenes")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// First, create a separate view for the performer header
struct PerformerHeaderView: View {
    let performer: StashScene.Performer
    
    var body: some View {
        VStack(spacing: 16) {
            // Performer Image
            if let imagePath = performer.image_path {
                AsyncImage(url: URL(string: imagePath)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                .frame(width: 200, height: 200)
                .clipShape(Circle())
            }
            
            // Performer Info
            VStack(spacing: 8) {
                Text(performer.name)
                    .font(.title)
                
                if let sceneCount = performer.scene_count {
                    Text("\(sceneCount) scenes")
                        .foregroundColor(.secondary)
                }
                
                if let rating = performer.rating100 {
                    HStack {
                        ForEach(0..<5) { index in
                            Image(systemName: index < rating/20 ? "star.fill" : "star")
                                .foregroundColor(.yellow)
                        }
                    }
                }
            }
        }
    }
}

// Create a separate view for the scenes grid
struct PerformerScenesGridView: View {
    let scenes: [StashScene]
    let onSceneSelected: (StashScene) -> Void
    let onTagSelected: (StashScene.Tag) -> Void
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: 16) {
            ForEach(scenes) { scene in
                SceneRow(scene: scene, onTagSelected: onTagSelected)
                    .onTapGesture {
                        onSceneSelected(scene)
                    }
            }
        }
        .padding()
    }
}

// Now simplify the PerformerDetailView
struct PerformerDetailView: View {
    let performer: StashScene.Performer
    @StateObject private var api: StashAPI
    @State private var selectedScene: StashScene?
    @State private var selectedTag: StashScene.Tag?
    
    init(performer: StashScene.Performer) {
        self.performer = performer
        let serverAddress = UserDefaults.standard.string(forKey: "serverAddress") ?? ""
        _api = StateObject(wrappedValue: StashAPI(serverAddress: serverAddress))
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PerformerHeaderView(performer: performer)
                
                PerformerScenesGridView(
                    scenes: api.scenes,
                    onSceneSelected: { selectedScene = $0 },
                    onTagSelected: { selectedTag = $0 }
                )
            }
        }
        .navigationTitle(performer.name)
        .task {
            await fetchPerformerScenes()
        }
        .sheet(item: $selectedScene) { scene in
            VideoPlayerView(scene: scene)
        }
        .sheet(item: $selectedTag) { tag in
            NavigationView {
                TaggedScenesView(tag: tag)
            }
        }
    }
    
    private func fetchPerformerScenes() async {
        let query = """
        {
            "operationName": "FindScenes",
            "variables": {
                "filter": {
                    "q": "",
                    "page": 1,
                    "per_page": 40,
                    "sort": "date",
                    "direction": "DESC"
                },
                "scene_filter": {
                    "performers": {
                        "value": ["\(performer.id)"],
                        "excludes": [],
                        "modifier": "INCLUDES_ALL"
                    }
                }
            },
            "query": "query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType, $scene_ids: [Int!]) { findScenes(filter: $filter, scene_filter: $scene_filter, scene_ids: $scene_ids) { count filesize duration scenes { ...SlimSceneData __typename } __typename } } fragment SlimSceneData on Scene { id title code details director urls date rating100 o_counter organized interactive interactive_speed resume_time play_duration play_count files { ...VideoFileData __typename } paths { screenshot preview stream webp vtt sprite funscript interactive_heatmap caption __typename } scene_markers { id title seconds primary_tag { id name __typename } __typename } tags { id name __typename } performers { id name disambiguation gender favorite image_path __typename } stash_ids { endpoint stash_id __typename } __typename } fragment VideoFileData on VideoFile { id path size mod_time duration video_codec audio_codec width height frame_rate bit_rate fingerprints { type value __typename } __typename }"
        }
        """
        
        guard let url = URL(string: "\(api.serverAddress)/graphql") else { 
            print("🔥 Invalid URL for performer scenes")
            return 
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("u=3, i", forHTTPHeaderField: "Priority")
        request.setValue("include", forHTTPHeaderField: "credentials")
        request.httpBody = query.data(using: .utf8)
        
        do {
            print("🔥 Fetching scenes for performer: \(performer.name)")
            let (data, _) = try await URLSession.shared.data(for: request)
            let decodedResponse = try JSONDecoder().decode(GraphQLResponse<ScenesResponse>.self, from: data)
            
            await MainActor.run {
                api.scenes = decodedResponse.data.findScenes.scenes
                print("🔥 Successfully loaded \(api.scenes.count) scenes for performer")
            }
        } catch {
            print("🔥 Error fetching performer scenes: \(error.localizedDescription)")
            if let decodingError = error as? DecodingError {
                print("🔥 Decoding error details: \(decodingError)")
            }
        }
    }
}

// Add these models
struct SceneMarker: Identifiable, Decodable, Equatable {
    let id: String
    let title: String
    let seconds: Float
    let stream: String
    let preview: String
    let screenshot: String
    let scene: MarkerScene
    let primary_tag: Tag
    let tags: [Tag]
    
    struct MarkerScene: Identifiable, Decodable, Equatable {
        let id: String
    }
    
    struct Tag: Identifiable, Decodable, Equatable {
        let id: String
        let name: String
    }
    
    static func == (lhs: SceneMarker, rhs: SceneMarker) -> Bool {
        return lhs.id == rhs.id
    }
}

struct SceneMarkersResponse: Decodable {
    let findSceneMarkers: FindSceneMarkersResult
    
    struct FindSceneMarkersResult: Decodable {
        let count: Int
        let scene_markers: [SceneMarker]
    }
}

// Create a separate view for the marker preview
struct MarkerPreviewSection: View {
    let marker: SceneMarker
    let isVisible: Bool
    let isMuted: Bool
    let previewPlayer: VideoPlayerViewModel
    let onMuteToggle: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Thumbnail
                AsyncImage(url: URL(string: marker.screenshot)) { image in
                    image.resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                }
                
                // Video preview
                if isVisible {
                    VideoPlayer(player: previewPlayer.player)
                        .onAppear {
                            previewPlayer.player.isMuted = isMuted
                        }
                }
                
                // Sound toggle button
                if isVisible {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: onMuteToggle) {
                                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .padding(8)
                        }
                    }
                }
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// Create a separate view for the marker tags section
struct MarkerTagsSection: View {
    let marker: SceneMarker
    let onTagTap: (String) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Button(action: { onTagTap(marker.primary_tag.name) }) {
                    Text(marker.primary_tag.name)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(12)
                }
                
                ForEach(marker.tags) { tag in
                    Button(action: { onTagTap(tag.name) }) {
                        Text(tag.name)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(12)
                    }
                }
            }
        }
    }
}

// Simplified MarkerRow
struct MarkerRow: View {
    let marker: SceneMarker
    let serverAddress: String
    @State private var isVisible = false
    @State private var isMuted = true
    @StateObject private var previewPlayer = VideoPlayerViewModel()
    let onTitleTap: (String) -> Void
    let onTagTap: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading) {
            // Make the entire video area tappable
            Button(action: {
                playSceneAtMarker()
            }) {
                GeometryReader { geometry in
                    ZStack {
                        // Thumbnail
                        AsyncImage(url: URL(string: marker.screenshot)) { image in
                            image.resizable()
                                .aspectRatio(16/9, contentMode: .fill)
                        } placeholder: {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                        }
                        
                        // Video preview
                        if isVisible {
                            VideoPlayer(player: previewPlayer.player)
                                .onAppear {
                                    previewPlayer.player.isMuted = isMuted
                                }
                        }
                        
                        // Sound toggle button
                        if isVisible {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        isMuted.toggle()
                                        previewPlayer.player.isMuted = isMuted
                                    }) {
                                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                            .foregroundColor(.white)
                                            .padding(8)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Circle())
                                    }
                                    .padding(8)
                                }
                            }
                        }
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onChange(of: geometry.frame(in: .global).minY) { _, newValue in
                        let frame = geometry.frame(in: .global)
                        let isNowVisible = frame.minY > 0 && frame.maxY < UIScreen.main.bounds.height
                        
                        if isNowVisible != isVisible {
                            isVisible = isNowVisible
                            if isNowVisible {
                                startPreview()
                            } else {
                                stopPreview()
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
            .buttonStyle(PlainButtonStyle())  // Prevent button styling
            
            // Title and tags
            VStack(alignment: .leading, spacing: 8) {
                if !marker.title.isEmpty {
                    Text(marker.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        Button(action: { onTagTap(marker.primary_tag.name) }) {
                            Text(marker.primary_tag.name)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(12)
                        }
                        
                        ForEach(marker.tags) { tag in
                            Button(action: { onTagTap(tag.name) }) {
                                Text(tag.name)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.2))
                                    .cornerRadius(12)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .onDisappear {
            stopPreview()
        }
    }
    
    private func startPreview() {
        if let streamURL = URL(string: marker.stream) {
            print("🔥 Starting preview for marker: \(marker.title)")
            let playerItem = AVPlayerItem(url: streamURL)
            previewPlayer.player.replaceCurrentItem(with: playerItem)
            previewPlayer.player.isMuted = isMuted
            previewPlayer.player.play()
        }
    }
    
    private func stopPreview() {
        print("🔥 Stopping preview for marker: \(marker.title)")
        previewPlayer.cleanup()
        isVisible = false
    }
    
    private func playSceneAtMarker() {
        // Construct URL with scene ID and time
        let sceneUrl = "\(serverAddress)/scene/\(marker.scene.id)?t=\(marker.seconds)"
        
        if let url = URL(string: sceneUrl) {
            let player = AVPlayer()
            let controller = AVPlayerViewController()
            controller.player = player
            controller.modalPresentationStyle = .fullScreen
            
            // Get the current window scene
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController {
                
                // Create HLS URL
                var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
                let streamPath = "/scene/\(marker.scene.id)/stream.m3u8"
                components.path = streamPath
                
                if let hlsURL = components.url {
                    let assetOptions = [
                        "AVURLAssetHTTPHeaderFieldsKey": [
                            "Accept": "*/*",
                            "Accept-Language": "en-US,en;q=0.9",
                            "Accept-Encoding": "identity",
                            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15",
                            "Connection": "keep-alive"
                        ]
                    ]
                    
                    let asset = AVURLAsset(url: hlsURL, options: assetOptions)
                    let playerItem = AVPlayerItem(asset: asset)
                    player.replaceCurrentItem(with: playerItem)
                    
                    rootViewController.present(controller, animated: true) {
                        // Seek to marker position and play
                        let time = CMTime(seconds: Double(marker.seconds), preferredTimescale: 1)
                        player.seek(to: time) { finished in
                            if finished {
                                player.play()
                            }
                        }
                    }
                }
            }
        }
    }
}

// Update MarkersView to use new fetchMarkers
struct MarkersView: View {
    @StateObject var api: StashAPI
    @State private var searchText = ""
    @State private var currentPage = 1
    @State private var isLoadingMore = false
    @State private var hasMorePages = true
    
    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)
    ]
    
    private var filteredMarkers: [SceneMarker] {
        if searchText.isEmpty {
            return api.markers
        }
        return api.markers.filter { marker in
            let titleMatch = marker.title.localizedCaseInsensitiveContains(searchText)
            let primaryTagMatch = marker.primary_tag.name.localizedCaseInsensitiveContains(searchText)
            let tagsMatch = marker.tags.contains { tag in
                tag.name.localizedCaseInsensitiveContains(searchText)
            }
            return titleMatch || primaryTagMatch || tagsMatch
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredMarkers) { marker in
                    MarkerRow(
                        marker: marker,
                        serverAddress: api.serverAddress,
                        onTitleTap: { _ in },
                        onTagTap: { tagName in
                            searchText = tagName
                        }
                    )
                    .onAppear {
                        if marker == api.markers.last && !isLoadingMore && hasMorePages {
                            Task {
                                await loadMoreMarkers()
                            }
                        }
                    }
                }
                
                if isLoadingMore {
                    ProgressView()
                        .gridCellColumns(columns.count)
                        .padding()
                }
            }
            .padding()
        }
        .navigationTitle("Markers")
        .task {
            if api.markers.isEmpty {
                await initialLoad()
            }
        }
    }
    
    private func initialLoad() async {
        currentPage = 1
        hasMorePages = true
        await api.fetchMarkers(page: currentPage, appendResults: false)
    }
    
    private func loadMoreMarkers() async {
        guard !isLoadingMore else { return }
        
        isLoadingMore = true
        currentPage += 1
        
        print("🔥 Loading more markers (page \(currentPage))")
        let previousCount = api.markers.count
        await api.fetchMarkers(page: currentPage, appendResults: true)
        
        hasMorePages = api.markers.count > previousCount
        isLoadingMore = false
    }
}

// Add a TagView component
struct TagView: View {
    let tag: StashScene.Tag
    let onTagSelected: (StashScene.Tag) -> Void
    
    var body: some View {
        Button(action: { onTagSelected(tag) }) {
            Text(tag.name)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(12)
        }
    }
}

// Add TaggedScenesView
struct TaggedScenesView: View {
    let tag: StashScene.Tag
    @StateObject private var api: StashAPI
    @State private var selectedScene: StashScene?
    
    init(tag: StashScene.Tag) {
        self.tag = tag
        let serverAddress = UserDefaults.standard.string(forKey: "serverAddress") ?? ""
        _api = StateObject(wrappedValue: StashAPI(serverAddress: serverAddress))
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: 16) {
                ForEach(api.scenes) { scene in
                    SceneRow(scene: scene, onTagSelected: { _ in })
                        .onTapGesture {
                            selectedScene = scene
                        }
                }
            }
            .padding()
        }
        .navigationTitle("Tag: \(tag.name)")
        .task {
            await api.fetchScenesByTag(tagId: tag.id)
        }
        .sheet(item: $selectedScene) { scene in
            VideoPlayerView(scene: scene)
        }
    }
}

// Add a TagEditView
struct TagEditView: View {
    let marker: SceneMarker
    @Environment(\.dismiss) private var dismiss
    @StateObject private var api: StashAPI
    @State private var selectedTags: Set<String>
    
    init(marker: SceneMarker) {
        self.marker = marker
        let serverAddress = UserDefaults.standard.string(forKey: "serverAddress") ?? ""
        _api = StateObject(wrappedValue: StashAPI(serverAddress: serverAddress))
        _selectedTags = State(initialValue: Set(marker.tags.map { $0.id }))
    }
    
    var body: some View {
        NavigationStack {
            List {
                Text("Tag selection coming soon")
            }
            .navigationTitle("Edit Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await api.updateMarkerTags(markerId: marker.id, tagIds: Array(selectedTags))
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

// Add updateMarkerTags to StashAPI
extension StashAPI {
    func updateMarkerTags(markerId: String, tagIds: [String]) async {
        print("🔥 Updating tags for marker \(markerId)")
        
        let query = """
        {
            "operationName": "MarkerUpdate",
            "variables": {
                "input": {
                    "id": "\(markerId)",
                    "tag_ids": \(tagIds)
                }
            },
            "query": "mutation MarkerUpdate($input: SceneMarkerUpdateInput!) { sceneMarkerUpdate(input: $input) { id tags { id name } } }"
        }
        """
        
        guard let url = URL(string: "\(serverAddress)/graphql") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = query.data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            print("🔥 Tag update response: \(String(data: data, encoding: .utf8) ?? "")")
        } catch {
            print("🔥 Error updating tags: \(error)")
        }
    }
}

// Add MarkerFilterView
struct MarkerFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var api: StashAPI
    @State private var searchText = ""
    @Binding var selectedTag: String?
    
    init(selectedTag: Binding<String?>) {
        let serverAddress = UserDefaults.standard.string(forKey: "serverAddress") ?? ""
        _api = StateObject(wrappedValue: StashAPI(serverAddress: serverAddress))
        _selectedTag = selectedTag
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(api.markerTags.sorted(), id: \.self) { tag in
                    Button(action: {
                        selectedTag = tag
                        dismiss()
                    }) {
                        Text(tag)
                    }
                }
            }
            .searchable(text: $searchText)
            .onChange(of: searchText) { _, newValue in
                api.markerTags = api.allMarkerTags.filter { 
                    newValue.isEmpty || $0.localizedCaseInsensitiveContains(newValue)
                }
            }
            .navigationTitle("Filter Markers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await fetchMarkerTags()
            }
        }
    }
    
    func fetchMarkerTags() async {
        let tags = Set(api.markers.flatMap { marker in
            var tags = marker.tags.map { $0.name }
            tags.append(marker.primary_tag.name)
            return tags
        })
        await MainActor.run {
            api.allMarkerTags = Array(tags)
            api.markerTags = api.allMarkerTags
        }
    }
}

// Add SceneMarkerTagsResponse struct
struct SceneMarkerTagsResponse: Decodable {
    let sceneMarkerTags: [SceneMarkerTag]
    
    struct SceneMarkerTag: Decodable {
        let tag: Tag
        let scene_markers: [SceneMarker]
        
        struct Tag: Decodable {
            let id: String
            let name: String
        }
    }
}

#Preview {
    ContentView()
}

