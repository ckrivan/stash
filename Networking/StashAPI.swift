import Foundation
import SwiftUI
import Combine

enum PerformerFilter {
    case all
    case lessThanTwo
    case twoOrMore
    case tenOrMore
}

struct ScenesResponseData: Decodable {
    let findScenes: FindScenesResult

    struct FindScenesResult: Decodable {
        let scenes: [StashScene]
        let count: Int
    }
}

struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T
    let errors: [GraphQLError]?
}

struct GraphQLError: Decodable, Identifiable, CustomStringConvertible {
    let message: String
    let path: [String]?
    let extensions: [String: String]?

    // For Identifiable conformance
    var id: String { message }

    // For easier debugging
    var description: String {
        if let path = path {
            return "GraphQL Error: \(message) (path: \(path.joined(separator: ".")))"
        }
        return "GraphQL Error: \(message)"
    }

    // Custom coding keys for flexible decoding
    enum CodingKeys: String, CodingKey {
        case message
        case path
        case extensions
    }

    // Custom init to handle optional fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        path = try container.decodeIfPresent([String].self, forKey: .path)
        extensions = try container.decodeIfPresent([String: String].self, forKey: .extensions)
    }
}

struct PerformersResponse: Decodable {
    let findPerformers: FindPerformersResult

    struct FindPerformersResult: Decodable {
        let count: Int
        let performers: [StashScene.Performer]
    }
}

struct ScenesResponse: Decodable {
    let data: ScenesData

    struct ScenesData: Decodable {
        let findScenes: FindScenesResult

        struct FindScenesResult: Decodable {
            let count: Int
            let scenes: [StashScene]
        }
    }
}

struct SceneResponse: Decodable {
    let findScene: StashScene
}

struct SystemStatus: Decodable {
    let databaseSchema: Int?
    let databasePath: String?
    let configPath: String?
    let appSchema: Int?
    let status: String?
    let appName: String?
    let appVersion: String?
    let logFile: String?
    let maxSessionAge: Int?
}

struct TagSearchResponse: Decodable {
    let data: TagData

    struct TagData: Decodable {
        let findTags: TagResults

        struct TagResults: Decodable {
            let count: Int
            let tags: [StashScene.Tag]
        }
    }
}

/// Stats data response from the Stash API
struct StatsDataResponse: Decodable {
    let stats: StashStats
}

class StashAPI: ObservableObject {
    // BEGIN NEW FETCHMARKERS

    /// Fetch markers filtered by performer using GraphQL
    /// - Parameters:
    ///   - performerId: The performer's ID
    ///   - page: The page number (default 1)
    /// - Returns: Array of SceneMarker
    // This version of fetchPerformerMarkersCore has been replaced by the private implementation below
    // It's kept as a reference for the API methodology but not executed
    private func fetchPerformerMarkersLegacy(performerId: String, page: Int = 1) async throws -> [SceneMarker] {
        // Build the GraphQL request payload
        let graphQLQuery = """
        {
            "operationName": "FindSceneMarkers",
            "variables": {
                "filter": {
                    "page": \(page),
                    "per_page": 100
                },
                "scene_marker_filter": {
                    "performers": {
                        "value": ["\(performerId)"],
                        "modifier": "INCLUDES_ALL"
                    }
                }
            },
            "query": "query FindSceneMarkers($filter: FindFilterType, $scene_marker_filter: SceneMarkerFilterType) { findSceneMarkers(filter: $filter, scene_marker_filter: $scene_marker_filter) { count scene_markers { id title seconds end_seconds stream preview screenshot scene { id title files { width height path __typename } performers { id name image_path __typename } __typename } primary_tag { id name __typename } tags { id name __typename } __typename } __typename } __typename }"
        }
        """

        // Prepare URL and request
        guard let url = URL(string: "\(serverAddress)/graphql") else {
            throw StashAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        configureRequestWithAuth(&request)
        request.httpBody = graphQLQuery.data(using: .utf8)

        // Execute network call
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw StashAPIError.serverError(httpResponse.statusCode)
        }

        // Decode response
        struct PerformerMarkersResponse: Decodable {
            struct Data: Decodable {
                struct FindSceneMarkers: Decodable {
                    let count: Int
                    let scene_markers: [SceneMarker]
                }
                let findSceneMarkers: FindSceneMarkers
            }
            let data: Data
            let errors: [GraphQLError]?
        }

        let result = try decoder.decode(PerformerMarkersResponse.self, from: data)
        if let errors = result.errors, !errors.isEmpty {
            let messages = errors.map { $0.message }.joined(separator: "\n")
            throw StashAPIError.graphQLError(messages)
        }

        return result.data.findSceneMarkers.scene_markers
    }
    // MARK: - Published Properties
    @Published var scenes: [StashScene] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var performers: [StashScene.Performer] = []
    @Published var markers: [SceneMarker] = []
    @Published var totalSceneCount: Int = 0
    @Published var totalPerformerCount: Int = 0
    @Published var connectionStatus: ConnectionStatus = .unknown
    @Published var sceneID: String?
    @Published var isAuthenticated = false
    @Published var isConnected = false
    @Published var systemStatus: SystemStatus?
    @Published var serverAddressPublic = ""
    @Published var preview: Bool = false
    
    // Add the StashAPI singleton reference
    static var shared: StashAPI? {
        get {
            return StashAPIManager.shared.api
        }
    }

    // MARK: - Properties
    let serverAddress: String
    private var currentTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // API Authentication
    private let apiKey: String
    
    // Public getter for apiKey to be used by VideoPlayerUtility
    var apiKeyForURLs: String {
        return apiKey
    }

    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    // MARK: - Connection Status
    enum ConnectionStatus: Equatable {
        case connected
        case disconnected
        case authenticationFailed
        case unknown
        case failed(Error)

        static func == (lhs: ConnectionStatus, rhs: ConnectionStatus) -> Bool {
            switch (lhs, rhs) {
            case (.connected, .connected),
                 (.disconnected, .disconnected),
                 (.authenticationFailed, .authenticationFailed),
                 (.unknown, .unknown):
                return true
            case (.failed(let lhsError), .failed(let rhsError)):
                return lhsError.localizedDescription == rhsError.localizedDescription
            default:
                return false
            }
        }
    }

    // MARK: - Initialization
    init(serverAddress: String, apiKey: String) {
        self.serverAddress = serverAddress
        self.apiKey = apiKey
        print("🔄 StashAPI initializing with server: \(serverAddress)")
        print("🔑 Using API key: \(apiKey.isEmpty ? "EMPTY" : "[\(apiKey.prefix(10))...]")")
        print("🔑 API key length: \(apiKey.count) characters")

        self.decoder.keyDecodingStrategy = .convertFromSnakeCase

        // Check if we have an API key
        if !apiKey.isEmpty {
            self.isAuthenticated = true
        } else {
            print("⚠️ WARNING: API key is empty!")
        }

        // Configure session
        URLSession.shared.configuration.timeoutIntervalForRequest = 30.0
        URLSession.shared.configuration.timeoutIntervalForResource = 60.0

        // Trigger a connection check asynchronously
        Task {
            try? await checkAndUpdateConnectionStatus()
        }
    }

    // Check server connection and update the connectionStatus property
    private func checkAndUpdateConnectionStatus() async {
        print("🔄 Checking connection status...")
        do {
            // Try to connect to the server
            try await checkServerConnection()
            await MainActor.run {
                self.connectionStatus = .connected
                self.isConnected = true
                self.error = nil
                print("✅ Connection successful")
            }
        } catch let error as StashAPIError {
            await MainActor.run {
                switch error {
                case .authenticationFailed:
                    print("🔒 Authentication failed - check API key")
                    self.connectionStatus = .authenticationFailed
                case .connectionFailed(let reason):
                    print("❌ Connection failed: \(reason)")
                    self.connectionStatus = .disconnected
                case .invalidURL:
                    print("❌ Invalid server URL configured")
                    self.connectionStatus = .failed(error)
                default:
                    print("❌ Connection error: \(error.localizedDescription)")
                    self.connectionStatus = .failed(error)
                }
                self.error = error
                self.isConnected = false
            }

            // Try to determine if server is reachable without authentication
            do {
                guard let url = URL(string: serverAddress) else {
                    return
                }

                var request = URLRequest(url: url)
                request.timeoutInterval = 5

                let (_, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    print("📡 Basic server check response: \(httpResponse.statusCode)")

                    await MainActor.run {
                        if (200...299).contains(httpResponse.statusCode) {
                            // Server is reachable but we had auth issues
                            if self.connectionStatus != .authenticationFailed {
                                self.connectionStatus = .authenticationFailed
                            }
                        } else if (500...599).contains(httpResponse.statusCode) {
                            self.connectionStatus = .failed(StashAPIError.serverError(httpResponse.statusCode))
                        }
                    }
                }
            } catch {
                print("❌ Server completely unreachable: \(error.localizedDescription)")
                await MainActor.run {
                    self.connectionStatus = .disconnected
                }
            }
        } catch {
            print("❌ Unexpected error during connection check: \(error.localizedDescription)")
            await MainActor.run {
                self.connectionStatus = .failed(error)
                self.error = error
                self.isConnected = false
            }
        }
    }

    // Helper method to retry connection
    func retryConnection() async {
        print("🔄 Retrying connection...")
        await checkAndUpdateConnectionStatus()
    }

    // Helper to get a user-friendly connection status message
    var connectionStatusMessage: String {
        switch connectionStatus {
        case .connected:
            return "Connected to server"
        case .disconnected:
            return "Unable to connect to server"
        case .authenticationFailed:
            return "Authentication failed - check API key"
        case .unknown:
            return "Checking connection..."
        case .failed(let error):
            if let stashError = error as? StashAPIError {
                return stashError.localizedDescription
            } else {
                return "Connection failed: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Authentication Methods
    private func configureRequestWithAuth(_ request: inout URLRequest, referer: String? = nil) {
        // Updated to use BOTH authentication methods
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        // IMPORTANT: Using BOTH auth methods for maximum compatibility
        request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(serverAddress, forHTTPHeaderField: "Origin")
        if let referer = referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        request.timeoutInterval = 30.0
        
        // Detailed debug logging
        print("🔐 Configuring auth:")
        print("   API Key: \(apiKey.isEmpty ? "EMPTY!" : "[\(apiKey.prefix(10))...] (\(apiKey.count) chars)")")
        print("   Server: \(serverAddress)")
        if apiKey.isEmpty {
            print("   ⚠️ WARNING: API key is empty!")
        }
    }
    
    // Test method to verify authentication
    func testAuthentication() async throws {
        print("🧪 Testing authentication with server: \(serverAddress)")
        print("🔑 API Key: \(apiKey.isEmpty ? "EMPTY" : "[\(apiKey.prefix(10))...] (\(apiKey.count) chars)")")
        
        guard let url = URL(string: "\(serverAddress)/graphql") else {
            throw StashAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        configureRequestWithAuth(&request)
        
        // Simple query to test auth
        let testQuery = """
        {
            "operationName": "Configuration",
            "query": "query Configuration { configuration { general { apiKey } } }"
        }
        """
        request.httpBody = testQuery.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("🧪 Test response status: \(httpResponse.statusCode)")
            if let responseStr = String(data: data, encoding: .utf8) {
                print("🧪 Response: \(responseStr)")
            }
            
            if httpResponse.statusCode == 401 {
                throw StashAPIError.authenticationFailed
            }
        }
    }

    // MARK: - Modern Async/Await GraphQL Methods

    /// Public method to execute GraphQL queries directly with async/await
    func executeGraphQLQueryAsync(_ query: String) async throws -> Data {
        guard let url = URL(string: "\(serverAddress)/graphql") else {
            throw StashAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        configureRequestWithAuth(&request)
        request.httpBody = query.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw StashAPIError.serverError(httpResponse.statusCode)
        }

        return data
    }

    /// Performs a GraphQL request using async/await
    private func performGraphQLRequest<T: Decodable>(query: String, variables: [String: Any]? = nil) async throws -> T {
        guard let url = URL(string: "\(serverAddress)/graphql") else {
            throw StashAPIError.invalidURL
        }

        // Create the request body
        var requestBody: [String: Any] = [
            "query": query
        ]
        if let variables = variables {
            requestBody["variables"] = variables
        }

        // Convert request body to JSON data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw StashAPIError.invalidData("Cannot serialize request body")
        }

        // Create and configure the request with both authentication methods
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        configureRequestWithAuth(&request)
        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                print("📡 GraphQL Response Status: \(httpResponse.statusCode)")

                // Show response preview for debugging
                if let responseStr = String(data: data, encoding: .utf8)?.prefix(100) {
                    print("📥 Response preview: \(responseStr)...")
                }

                if httpResponse.statusCode == 401 {
                    throw StashAPIError.authenticationFailed
                }

                if !(200...299).contains(httpResponse.statusCode) {
                    throw StashAPIError.serverError(httpResponse.statusCode)
                }
            }

            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("❌ GraphQL Error: \(error)")
            throw error
        }
    }

    // Add a version of performGraphQLRequest that returns raw Data
    private func performGraphQLRequest(query: String, variables: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: "\(serverAddress)/graphql") else {
            throw StashAPIError.invalidURL
        }

        // Create the request body
        var requestBody: [String: Any] = [
            "query": query
        ]
        if let variables = variables {
            requestBody["variables"] = variables
        }

        // Convert request body to JSON data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw StashAPIError.invalidData("Cannot serialize request body")
        }

        // Create and configure the request with both auth methods
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(serverAddress, forHTTPHeaderField: "Origin")
        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                print("📡 GraphQL Response Status: \(httpResponse.statusCode)")

                // Show response preview for debugging
                if let responseStr = String(data: data, encoding: .utf8)?.prefix(100) {
                    print("📥 Response preview: \(responseStr)...")
                }

                if httpResponse.statusCode == 401 {
                    throw StashAPIError.authenticationFailed
                }

                if !(200...299).contains(httpResponse.statusCode) {
                    throw StashAPIError.serverError(httpResponse.statusCode)
                }
            }

            return data
        } catch {
            print("❌ GraphQL Error: \(error)")
            throw error
        }
    }

    // Public method to execute GraphQL queries directly
    public func executeGraphQLQuery(_ query: String) async throws -> Data {
        guard let url = URL(string: "\(serverAddress)/graphql") else {
            throw StashAPIError.graphQLError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        configureRequestWithAuth(&request)
        request.httpBody = query.data(using: .utf8)

        print("📤 Executing GraphQL query with BOTH ApiKey and Bearer auth headers")
        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            print("📥 HTTP response: \(httpResponse.statusCode)")

            // Show response preview for debugging
            if let responseStr = String(data: data, encoding: .utf8)?.prefix(100) {
                print("📥 Response preview: \(responseStr)...")
            }

            if !(200...299).contains(httpResponse.statusCode) {
                print("❌ Error status: \(httpResponse.statusCode)")
                throw StashAPIError.serverError(httpResponse.statusCode)
            }
        }

        return data
    }
    
    // MARK: - Scenes Methods
    
    /// Fetch a specific scene by its ID
    /// - Parameter id: The scene ID to fetch
    /// - Returns: The scene if found, nil otherwise
    func fetchScene(byID id: String) async throws -> StashScene? {
        let query = """
        query FindScene($id: ID!) {
            findScene(id: $id) {
                id
                title
                details
                url
                date
                rating100
                organized
                o_counter
                paths {
                    screenshot
                    preview
                    stream
                    webp
                    vtt
                    sprite
                    funscript
                    interactive_heatmap
                }
                files {
                    size
                    duration
                    video_codec
                    width
                    height
                }
                performers {
                    id
                    name
                    gender
                    image_path
                }
                tags {
                    id
                    name
                }
                studio {
                    id
                    name
                }
                stash_ids {
                    endpoint
                    stash_id
                }
                created_at
                updated_at
            }
        }
        """
        
        let variables = ["id": id]
        
        do {
            let response: GraphQLResponse<SceneResponse> = try await performGraphQLRequest(query: query, variables: variables)
            if let errors = response.errors, !errors.isEmpty {
                print("❌ GraphQL Errors: \(errors)")
                throw StashAPIError.graphQLError(errors.map { $0.message }.joined(separator: ", "))
            }
            return response.data.findScene
        } catch {
            print("❌ Error fetching scene: \(error)")
            throw error
        }
    }
    
    /// Get available sprite image URL (for thumbnails in the video scrubber)
    func getSpriteURLForScene(sceneID: String) -> URL? {
        // Use the static helper method to avoid duplicate code
        return VideoPlayerUtility.getSpriteURL(forSceneID: sceneID)
    }
    
    /// Get VTT file URL for a scene (for video chapters/thumbnails)
    func getVTTURLForScene(sceneID: String) -> URL? {
        // Use the static helper method to avoid duplicate code
        return VideoPlayerUtility.getVTTURL(forSceneID: sceneID)
    }
    func fetchScenes(page: Int = 1, sort: String = "file_mod_time", direction: String = "DESC", appendResults: Bool = false, filterOptions: FilterOptions? = nil) async {
        do {
            // Generate random seed for random sorting
            let randomSeed = Int.random(in: 0...999999)
            let sortField = sort == "random" ? "random_\(randomSeed)" : sort
            
            // Prepare variables
            var queryVars: [String: Any] = [
                "filter": [
                    "page": page,
                    "per_page": 100,
                    "sort": sortField,
                    "direction": direction
                ]
            ]
            
            // Create scene filter
            var sceneFilter: [String: Any] = [:]

            // Refine the approach to tag exclusion - the error suggests there's an issue with the tag filtering
            // Instead of doing tag filtering here, we'll do it in memory after fetching the scenes
            // This is a workaround for the SQL error we're seeing with the EXCLUDES modifier

            // Add additional filters if provided
            if let filterOptions = filterOptions {
                let additionalFilters = filterOptions.generateSceneFilter()
                for (key, value) in additionalFilters {
                    // Don't overwrite the tags filter with INCLUDES modifier
                    if key != "tags" {
                        sceneFilter[key] = value
                    } else if let tagsFilter = value as? [String: Any],
                              let modifier = tagsFilter["modifier"] as? String,
                              modifier == "EXCLUDES" {
                        // If it's also an EXCLUDES filter, merge the values
                        if var existingTagsFilter = sceneFilter["tags"] as? [String: Any],
                           let existingValues = existingTagsFilter["value"] as? [String],
                           let newValues = tagsFilter["value"] as? [String] {
                            var combinedValues = existingValues
                            for newValue in newValues {
                                if !combinedValues.contains(newValue) {
                                    combinedValues.append(newValue)
                                }
                            }
                            existingTagsFilter["value"] = combinedValues
                            sceneFilter["tags"] = existingTagsFilter
                        }
                    }
                }
            }

            // Add scene filter to query variables
            if !sceneFilter.isEmpty {
                queryVars["scene_filter"] = sceneFilter
            }
            
            // Prepare GraphQL query
            let graphQLRequest: [String: Any] = [
                "operationName": "FindScenes",
                "variables": queryVars,
                "query": """
                query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) {
                    findScenes(filter: $filter, scene_filter: $scene_filter) {
                        count
                        scenes {
                            id
                            title
                            details
                            url
                            date
                            rating100
                            organized
                            o_counter
                            paths {
                                screenshot
                                preview
                                stream
                                webp
                                vtt
                                sprite
                                funscript
                                interactive_heatmap
                            }
                            files {
                                size
                                duration
                                video_codec
                                width
                                height
                            }
                            performers {
                                id
                                name
                                gender
                                image_path
                                scene_count
                            }
                            tags {
                                id
                                name
                            }
                            studio {
                                id
                                name
                            }
                            stash_ids {
                                endpoint
                                stash_id
                            }
                            created_at
                            updated_at
                        }
                    }
                }
                """
            ]
            
            // Convert to JSON data
            let jsonData = try JSONSerialization.data(withJSONObject: graphQLRequest)
            
            guard let url = URL(string: "\(serverAddress)/graphql") else {
                throw StashAPIError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            configureRequestWithAuth(&request)
            request.httpBody = jsonData

            print("📤 Fetching scenes page \(page) (sort: \(sort), direction: \(direction))")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check for task cancellation
            if Task.isCancelled {
                print("⚠️ Scene fetch task was cancelled")
                throw StashAPIError.taskCancelled
            }
            
            // Log HTTP response code for debugging
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 HTTP response: \(httpResponse.statusCode)")
                
                // Check for server errors
                if httpResponse.statusCode >= 400 {
                    throw StashAPIError.serverError(httpResponse.statusCode)
                }
            }
            
            // Debug output for investigating the issue
            print("📥 Response data length: \(data.count) bytes")
            if let jsonStr = String(data: data, encoding: .utf8) {
                print("📥 First 500 characters of response: \(jsonStr.prefix(500))")
            }

            // Try to decode first as ScenesResponse (direct wrapper)
            do {
                let decoder = JSONDecoder()
                let scenesResponse = try decoder.decode(ScenesResponse.self, from: data)

                // Update our data on the main thread
                await MainActor.run {
                    // Update total count
                    self.totalSceneCount = scenesResponse.data.findScenes.count

                    // Update scenes array
                    if appendResults {
                        // Filter out duplicates before appending
                        let newScenes = scenesResponse.data.findScenes.scenes.filter { newScene in
                            !self.scenes.contains { $0.id == newScene.id }
                        }
                        self.scenes.append(contentsOf: newScenes)
                        print("✅ Added \(newScenes.count) new scenes (total: \(self.scenes.count))")
                    } else {
                        // Filter out VR scenes in memory
                        let allScenes = scenesResponse.data.findScenes.scenes
                        self.scenes = allScenes.filter { scene in
                            // Filter out scenes with VR tag
                            !scene.tags.contains { tag in
                                tag.name.lowercased() == "vr"
                            }
                        }
                        print("✅ Loaded \(self.scenes.count) scenes (filtered from \(allScenes.count) total)")
                    }

                    // Update loading state
                    self.isLoading = false
                    self.error = nil
                }
            } catch let error as DecodingError {
                // If ScenesResponse direct decoding fails, try with GraphQLResponse wrapper
                print("📦 Direct decoding failed, trying with GraphQLResponse wrapper: \(error.localizedDescription)")

                // Try to decode with GraphQLResponse wrapper
                let scenesResponse = try JSONDecoder().decode(GraphQLResponse<ScenesResponseData>.self, from: data)

                // Check for GraphQL errors
                if let errors = scenesResponse.errors, !errors.isEmpty {
                    let errorMessages = errors.map { $0.message }.joined(separator: ", ")
                    throw StashAPIError.graphQLError(errorMessages)
                }

                // Update our data on the main thread
                await MainActor.run {
                    // Update total count
                    self.totalSceneCount = scenesResponse.data.findScenes.count

                    // Update scenes array
                    if appendResults {
                        // Filter out duplicates before appending
                        let newScenes = scenesResponse.data.findScenes.scenes.filter { newScene in
                            !self.scenes.contains { $0.id == newScene.id }
                        }
                        self.scenes.append(contentsOf: newScenes)
                        print("✅ Added \(newScenes.count) new scenes (total: \(self.scenes.count))")
                    } else {
                        // Filter out VR scenes in memory
                        let allScenes = scenesResponse.data.findScenes.scenes
                        self.scenes = allScenes.filter { scene in
                            // Filter out scenes with VR tag
                            !scene.tags.contains { tag in
                                tag.name.lowercased() == "vr"
                            }
                        }
                        print("✅ Loaded \(self.scenes.count) scenes (filtered from \(allScenes.count) total)")
                    }
                    // Update loading state and error
                    self.isLoading = false
                    self.error = nil
                }
            }
        } catch {
            // Only update UI state if task wasn't cancelled
            if !Task.isCancelled {
                // Detailed error logging to help diagnose issues
                print("❌ Error fetching scenes: \(error.localizedDescription)")

                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, let context):
                        print("❌ JSON key not found: \(key.stringValue), context: \(context.debugDescription)")
                    case .typeMismatch(let type, let context):
                        print("❌ JSON type mismatch: expected \(type), context: \(context.debugDescription)")
                    case .valueNotFound(let type, let context):
                        print("❌ JSON value not found: \(type), context: \(context.debugDescription)")
                    case .dataCorrupted(let context):
                        print("❌ JSON data corrupted: \(context.debugDescription)")
                    @unknown default:
                        print("❌ Unknown JSON decoding error")
                    }
                }

                await MainActor.run {
                    self.error = error
                    self.isLoading = false

                    // Try to recover by loading with a fallback method
                    Task {
                        // Try a direct GraphQL query without the complex response structure
                        print("🔄 Attempting fallback scene loading...")
                        await tryFallbackSceneLoading(page: page, sort: sort, direction: direction)
                    }
                }
            }
        }
    }

    // MARK: - Fallback Scene Loading

    /// Fallback method for loading scenes when the standard fetching fails
    private func tryFallbackSceneLoading(page: Int, sort: String, direction: String) async {
        do {
            // Simpler query structure using GraphQL query
            let randomSeed = Int.random(in: 0...999999)
            let sortField = sort == "random" ? "random_\(randomSeed)" : sort

            // Create a simpler query with minimal fields to test the API
            // Also include tags for VR filtering
            let query = """
            {
                "query": "{ findScenes(filter: {page: \(page), per_page: 100, sort: \\"date\\", direction: \\"DESC\\"}) { count scenes { id title paths { screenshot stream } tags { id name } } } }"
            }
            """

            let data = try await performGraphQLRequest(query: query)

            struct SimpleScenesResponse: Decodable {
                struct Data: Decodable {
                    struct FindScenes: Decodable {
                        let count: Int
                        let scenes: [SimpleScene]

                        struct SimpleScene: Decodable {
                            let id: String
                            let title: String?
                            let paths: ScenePaths
                            let tags: [SimpleTag]

                            struct SimpleTag: Decodable {
                                let id: String
                                let name: String
                            }

                            struct ScenePaths: Decodable {
                                let screenshot: String
                                let stream: String
                            }
                        }
                    }
                    let findScenes: FindScenes
                }
                let data: Data
            }

            // Try to decode the simpler response
            if let jsonStr = String(data: data, encoding: .utf8) {
                print("🔍 Fallback response: \(jsonStr.prefix(200))...")
            }

            let simpleResponse = try JSONDecoder().decode(SimpleScenesResponse.self, from: data)

            // If successful, convert simple scenes to full scenes with minimal data
            // Also filter out VR content
            let allSimpleScenes = simpleResponse.data.findScenes.scenes

            let filteredSimpleScenes = allSimpleScenes.filter { scene in
                // Filter out scenes with VR tag
                !scene.tags.contains { tag in
                    tag.name.lowercased() == "vr"
                }
            }

            print("🔍 Fallback filtered out \(allSimpleScenes.count - filteredSimpleScenes.count) VR scenes")

            let simpleScenes = filteredSimpleScenes.map { simpleScene -> StashScene in
                // Convert the simplified paths to the format used by StashScene
                let scenePaths = StashScene.ScenePaths(
                    screenshot: simpleScene.paths.screenshot,
                    preview: nil,
                    stream: simpleScene.paths.stream
                )

                // Create a new StashScene with the limited data we have
                return StashScene(
                    id: simpleScene.id,
                    title: simpleScene.title,
                    details: nil,
                    paths: scenePaths,
                    files: [],
                    performers: [],
                    tags: simpleScene.tags.map { StashScene.Tag(id: $0.id, name: $0.name) },
                    rating100: nil,
                    o_counter: nil
                )
            }

            // Update UI with the simple scenes
            await MainActor.run {
                self.scenes = simpleScenes
                self.totalSceneCount = simpleResponse.data.findScenes.count
                print("✅ Loaded \(simpleScenes.count) scenes using fallback method")
                self.isLoading = false
                self.error = nil
            }
        } catch {
            print("❌ Fallback loading also failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Execute GraphQL Query Methods

    // Add the missing executeGraphQLQuery method with generic type and completion handler
    func executeGraphQLQuery<T: Decodable>(_ query: String, variables: [String: Any]? = nil, completion: @escaping (Result<T, Error>) -> Void) {
        Task {
            do {
                let response: T = try await performGraphQLRequest(query: query, variables: variables)
                DispatchQueue.main.async {
                    completion(.success(response))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // Add overload that takes named parameters for better clarity
    func executeGraphQLQuery<T: Decodable>(query: String, variables: [String: Any]? = nil, completion: @escaping (Result<T, Error>) -> Void) {
        Task {
            do {
                let response: T = try await performGraphQLRequest(query: query, variables: variables)
                DispatchQueue.main.async {
                    completion(.success(response))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Performer Scenes Method
    func fetchPerformerScenes(performerId: String, page: Int = 1, perPage: Int = 100, sort: String = "date", direction: String = "DESC", appendResults: Bool = false) async {
        isLoading = true

        // Using structure similar to VisionPro implementation
        print("🔍 Fetching performer scenes (ID: \(performerId), page: \(page), sort: \(sort), direction: \(direction))")
        
        // Base performer filter - make sure we're using the correct performerId
        print("🔍 Using performer ID: \(performerId) for fetch request")
        
        // Construct the query with proper performer filtering
        let query = """
        {
            "operationName": "FindScenes",
            "variables": {
                "filter": {
                    "page": \(page),
                    "per_page": \(perPage),
                    "sort": "\(sort)",
                    "direction": "\(direction)"
                },
                "scene_filter": {
                    "performers": {
                        "modifier": "INCLUDES",
                        "value": ["\(performerId)"]
                    }
                }
            },
            "query": "query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) { findScenes(filter: $filter, scene_filter: $scene_filter) { count scenes { id title details paths { screenshot preview stream } files { size duration video_codec width height } performers { id name gender image_path scene_count } tags { id name } studio { id name } rating100 o_counter } } }"
        }
        """

        guard let url = URL(string: "\(serverAddress)/graphql") else {
            print("❌ Invalid URL for performer scenes")
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        configureRequestWithAuth(&request, referer: "\(serverAddress)/performers/\(performerId)/scenes?sortby=date")
        request.httpBody = query.data(using: .utf8)
        
        print("📤 Sending GraphQL request for performer \(performerId)...")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // Check for task cancellation
            if Task.isCancelled {
                print("⚠️ Performer scenes fetch task was cancelled")
                throw StashAPIError.taskCancelled
            }

            // Debug response
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📊 Performer scenes response preview: \(jsonString.prefix(200))...")
                
                // Check if the response contains scene data at all
                if !jsonString.contains("\"scenes\"") {
                    print("⚠️ Response doesn't contain scenes array!")
                }
                
                // Check for any errors in the response
                if jsonString.contains("\"errors\"") {
                    print("⚠️ Response contains GraphQL errors!")
                }
            }

            // Log HTTP response code for debugging
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 HTTP response: \(httpResponse.statusCode)")

                // Check for server errors
                if httpResponse.statusCode >= 400 {
                    throw StashAPIError.serverError(httpResponse.statusCode)
                }
            }

            // Define response structure matching exactly the API format
            struct SceneResponse: Decodable {
                struct Data: Decodable {
                    let findScenes: FindScenesResult

                    struct FindScenesResult: Decodable {
                        let count: Int
                        let scenes: [StashScene]
                    }
                }
                let data: Data
                let errors: [GraphQLError]?
            }

            // Decode the response
            let scenesResponse = try JSONDecoder().decode(SceneResponse.self, from: data)

            // Check for GraphQL errors
            if let errors = scenesResponse.errors, !errors.isEmpty {
                let errorMessages = errors.map { $0.message }.joined(separator: ", ")
                throw StashAPIError.graphQLError(errorMessages)
            }

            // Debug: Verify the scenes are actually for the requested performer
            let sceneCount = scenesResponse.data.findScenes.scenes.count
            print("📊 Received \(sceneCount) scenes for performer \(performerId)")
            
            // Verify at least the first few scenes contain the performer
            if sceneCount > 0 {
                let checkCount = min(3, sceneCount)
                for i in 0..<checkCount {
                    let scene = scenesResponse.data.findScenes.scenes[i]
                    let containsPerformer = scene.performers.contains(where: { $0.id == performerId })
                    print("📊 Scene \(i+1) (\(scene.id)): \(scene.title ?? "Untitled") - Contains performer: \(containsPerformer)")
                    
                    if !containsPerformer {
                        print("⚠️ Scene doesn't contain requested performer! Performer IDs in scene:")
                        for performer in scene.performers {
                            print("   - \(performer.id): \(performer.name)")
                        }
                    }
                }
            }

            // Update our data on the main thread
            await MainActor.run {
                // Update total count
                self.totalSceneCount = scenesResponse.data.findScenes.count

                // Extra verification step - filter out any scenes that don't actually include the performer
                // This is a safety check in case the API returns incorrect results
                let verifiedScenes = scenesResponse.data.findScenes.scenes.filter { scene in
                    scene.performers.contains(where: { $0.id == performerId })
                }
                
                if verifiedScenes.count < scenesResponse.data.findScenes.scenes.count {
                    print("⚠️ Filtered out \(scenesResponse.data.findScenes.scenes.count - verifiedScenes.count) scenes that didn't include performer \(performerId)")
                }

                // Update scenes array with the verified scenes
                if appendResults {
                    // Filter out duplicates before appending
                    let newScenes = verifiedScenes.filter { newScene in
                        !self.scenes.contains { $0.id == newScene.id }
                    }
                    self.scenes.append(contentsOf: newScenes)
                    print("✅ Added \(newScenes.count) new performer scenes (total: \(self.scenes.count))")
                } else {
                    self.scenes = verifiedScenes
                    print("✅ Loaded \(self.scenes.count) performer scenes")
                }

                // Update loading state
                self.isLoading = false
                self.error = nil
            }
        } catch {
            // Only update UI state if task wasn't cancelled
            if !Task.isCancelled {
                await MainActor.run {
                    print("❌ Error fetching performer scenes: \(error.localizedDescription)")
                    // Try to get more detailed error info
                    if let decodingError = error as? DecodingError {
                        switch decodingError {
                        case .keyNotFound(let key, let context):
                            print("Missing key: \(key) - \(context.debugDescription)")
                        case .typeMismatch(let type, let context):
                            print("Type mismatch: \(type) - \(context.debugDescription)")
                        case .valueNotFound(let type, let context):
                            print("Value not found: \(type) - \(context.debugDescription)")
                        case .dataCorrupted(let context):
                            print("Data corrupted: \(context.debugDescription)")
                        @unknown default:
                            print("Unknown decoding error")
                        }
                    }
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Tag Scenes Method
    func fetchTaggedScenes(tagId: String, page: Int = 1, perPage: Int = 40, sort: String = "date", direction: String = "DESC") async throws -> [StashScene] {
        print("🔍 Fetching scenes for tag ID: \(tagId), page: \(page)")
        
        let query = """
        {
            "operationName": "FindScenes",
            "variables": {
                "filter": {
                    "page": \(page),
                    "per_page": \(perPage),
                    "sort": "\(sort)",
                    "direction": "\(direction)"
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
        
        guard let url = URL(string: "\(serverAddress)/graphql") else { 
            throw StashAPIError.invalidURL 
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(serverAddress, forHTTPHeaderField: "Origin")
        request.setValue("nc_sameSiteCookielax=true; nc_sameSiteCookiestrict=true", forHTTPHeaderField: "Cookie")
        request.setValue("\(serverAddress)/scenes?c=(\"type\":\"tags\",\"value\":[\"\(tagId)\"],\"modifier\":\"INCLUDES\")&sortby=date", forHTTPHeaderField: "Referer")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.httpBody = query.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(GraphQLResponse<ScenesResponseData>.self, from: data)
        return response.data.findScenes.scenes
    }

    // MARK: - System Methods

    // Method to get system status with completion handler
    func getSystemStatus(completion: @escaping (Result<SystemStatus, Error>) -> Void) {
        let query = """
        query SystemStatus {
          systemStatus {
            databaseSchema
            databasePath
            configPath
            appSchema
            status
            appName
            appVersion
            logFile
            maxSessionAge
          }
        }
        """

        struct SystemStatusResponse: Decodable {
            let systemStatus: SystemStatus
        }

        // Added named parameter to fix trailing closure issue
        executeGraphQLQuery(query: query, variables: nil, completion: { (result: Result<SystemStatusResponse, Error>) in
            switch result {
            case .success(let response):
                self.systemStatus = response.systemStatus
                self.isConnected = true
                completion(.success(response.systemStatus))
            case .failure(let error):
                self.isConnected = false
                completion(.failure(error))
            }
        })
    }

    /// Checks if the Stash server is reachable and if the API key is valid
    func checkServerConnection() async throws {
        print("🔄 Checking server connection to \(serverAddress)")

        guard let url = URL(string: "\(serverAddress)/graphql") else {
            print("❌ Invalid server URL")
            throw StashAPIError.invalidURL
        }

        // Create a simple query to check server status
        let query = """
        {
            "operationName": "FindPerformers",
            "variables": {
                "filter": {
                    "page": 1,
                    "per_page": 1,
                    "sort": "name",
                    "direction": "ASC"
                }
            },
            "query": "query FindPerformers($filter: FindFilterType) { findPerformers(filter: $filter) { count performers { id name } } }"
        }
        """

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add both authentication methods to ensure compatibility
        request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        request.httpBody = query.data(using: .utf8)

        do {
            print("📤 Sending connection check request...")
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type")
                throw StashAPIError.invalidResponse
            }

            print("📡 Server responded with status code: \(httpResponse.statusCode)")

            switch httpResponse.statusCode {
            case 200:
                guard !data.isEmpty else {
                    print("❌ Empty response data")
                    throw StashAPIError.emptyResponse
                }

                // Try to decode the response
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📥 Response: \(jsonString.prefix(200))...")
                }

                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

                    // Check if we got a data field
                    guard let dataField = json?["data"] as? [String: Any] else {
                        print("❌ Response missing data field")
                        throw StashAPIError.invalidData("Response missing data field")
                    }

                    // Check if we have performers data
                    guard let findPerformers = dataField["findPerformers"] as? [String: Any] else {
                        print("❌ Response missing performers data")
                        throw StashAPIError.invalidData("Response missing performers data")
                    }

                    print("✅ Server connection successful")
                    print("📊 Performers data: \(findPerformers)")

                } catch {
                    print("❌ Failed to parse response: \(error)")
                    throw StashAPIError.decodingError(error)
                }

            case 401, 403:
                print("🔒 Authentication failed")
                throw StashAPIError.authenticationFailed

            case 404:
                print("❌ Server endpoint not found")
                throw StashAPIError.connectionFailed("Server endpoint not found")

            case 500...599:
                print("❌ Server error: \(httpResponse.statusCode)")
                throw StashAPIError.serverError(httpResponse.statusCode)

            default:
                print("❌ Unexpected status code: \(httpResponse.statusCode)")
                throw StashAPIError.invalidResponse
            }

        } catch let error as StashAPIError {
            print("❌ StashAPI Error: \(error.localizedDescription)")
            throw error
        } catch {
            print("❌ Network Error: \(error.localizedDescription)")
            throw StashAPIError.networkError(error)
        }
    }

    /// Fetches statistics from Stash server
    func fetchStats() async throws -> StashStats {
        do {
            let query = """
            query {
              stats {
                scene_count
                scenes_size
                scene_duration
                image_count
                images_size
                gallery_count
                performer_count
                studio_count
                movie_count
                tag_count
              }
            }
            """

            let response: GraphQLResponse<StatsDataResponse> = try await performGraphQLRequest(query: query)

            // Check for errors in the response
            if let errors = response.errors, !errors.isEmpty {
                let errorMessages = errors.map { $0.message }.joined(separator: ", ")
                throw StashAPIError.graphQLError(errorMessages)
            }

            DispatchQueue.main.async {
                self.connectionStatus = .connected
            }

            return response.data.stats
        } catch {
            DispatchQueue.main.async {
                self.connectionStatus = .failed(error)
            }

            NSLog("Error fetching stats: \(error)")
            throw error
        }
    }

    // MARK: - Random Scene/Performer Methods

    func fetchRandomScene(completion: @escaping (Result<StashScene, Error>) -> Void) {
        let query = """
        query FindRandomScene {
          findRandomScene {
            id
            title
            details
            url
            date
            rating100
            o_counter
            organized
            interactive
            files {
              id
              path
              size
              duration
              video_codec
              audio_codec
              width
              height
              frame_rate
              bit_rate
            }
            paths {
              screenshot
              preview
              stream
              webp
              vtt
              chapters_vtt
              sprite
              funscript
            }
            scene_markers {
              id
              scene {
                id
              }
              title
              seconds
              primary_tag {
                id
                name
              }
              tags {
                id
                name
              }
              stream
              preview
              screenshot
            }
            galleries {
              id
              title
              files {
                path
              }
              folder {
                path
              }
            }
            studio {
              id
              name
              image_path
            }
            movies {
              movie {
                id
                name
                front_image_path
              }
              scene_index
            }
            tags {
              id
              name
            }
            performers {
              id
              name
              gender
              favorite
              image_path
            }
            stash_ids {
              endpoint
              stash_id
            }
          }
        }
        """

        struct SceneResponse: Decodable {
            let findRandomScene: StashScene
        }

        // Added named parameter to fix trailing closure issue
        executeGraphQLQuery(query: query, variables: nil, completion: { (result: Result<SceneResponse, Error>) in
            switch result {
            case .success(let response):
                completion(.success(response.findRandomScene))
            case .failure(let error):
                completion(.failure(error))
            }
        })
    }

    func fetchRandomPerformer(completion: @escaping (Result<StashScene.Performer, Error>) -> Void) {
        let query = """
        query FindRandomPerformer {
          findRandomPerformer {
            id
            name
            gender
            url
            twitter
            instagram
            birthdate
            death_date
            ethnicity
            country
            eye_color
            height_cm
            measurements
            fake_tits
            penis_length
            circumcised
            hair_color
            weight
            created_at
            updated_at
            favorite
            ignore_auto_tag
            image_path
            scene_count
            image_count
            gallery_count
            movie_count
            tags {
              id
              name
            }
            stash_ids {
              stash_id
              endpoint
            }
            rating100
            details
            aliases
          }
        }
        """

        struct PerformerResponse: Decodable {
            let findRandomPerformer: StashScene.Performer
        }

        // Added named parameter to fix trailing closure issue
        executeGraphQLQuery(query: query, variables: nil, completion: { (result: Result<PerformerResponse, Error>) in
            switch result {
            case .success(let response):
                completion(.success(response.findRandomPerformer))
            case .failure(let error):
                completion(.failure(error))
            }
        })
    }

    // MARK: - Tag Methods
    
    /// Fetch all tags from the server
    /// - Returns: Array of tags
    func fetchTags() async throws -> [StashScene.Tag] {
        isLoading = true
        defer { isLoading = false }
        
        let graphQLQuery = """
        {
            "operationName": "FindTags",
            "variables": {
                "filter": {
                    "per_page": 1000,
                    "sort": "name",
                    "direction": "ASC"
                }
            },
            "query": "query FindTags($filter: FindFilterType) { findTags(filter: $filter) { count tags { id name scene_count } } }"
        }
        """
        
        guard let url = URL(string: "\(serverAddress)/graphql") else {
            throw StashAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
        request.httpBody = graphQLQuery.data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct TagsResponse: Decodable {
            let data: TagData
            
            struct TagData: Decodable {
                let findTags: TagResults
                
                struct TagResults: Decodable {
                    let count: Int
                    let tags: [StashScene.Tag]
                }
            }
        }
        
        let response = try JSONDecoder().decode(TagsResponse.self, from: data)
        return response.data.findTags.tags
    }
    
    /// Create a new tag
    /// - Parameter name: Tag name
    /// - Returns: The created tag
    func createTag(name: String) async throws -> StashScene.Tag {
        let query = """
        mutation TagCreate($input: TagCreateInput!) {
            tagCreate(input: $input) {
                id
                name
                aliases
                image_path
                scene_count
            }
        }
        """

        let input: [String: Any] = [
            "name": name
        ]

        let variables: [String: Any] = ["input": input]

        struct TagCreateResponse: Decodable {
            let tagCreate: StashScene.Tag
        }

        let response: TagCreateResponse = try await performGraphQLRequest(query: query, variables: variables)
        return response.tagCreate
    }


    func findTags(filter: TagFilter? = nil, completion: @escaping (Result<[StashScene.Tag], Error>) -> Void) {
        let query = """
        query FindTags($filter: TagFilterType) {
          findTags(tag_filter: $filter) {
            count
            tags {
              id
              name
              aliases
              image_path
              scene_count
            }
          }
        }
        """

        var variables: [String: Any] = [:]
        if let filter = filter {
            variables["filter"] = filter.toDictionary()
        }

        struct TagsResponse: Decodable {
            let findTags: TagsData

            struct TagsData: Decodable {
                let count: Int
                let tags: [StashScene.Tag]
            }
        }

        executeGraphQLQuery(query: query, variables: variables, completion: { (result: Result<TagsResponse, Error>) in
            switch result {
            case .success(let response):
                completion(.success(response.findTags.tags))
            case .failure(let error):
                completion(.failure(error))
            }
        })
    }

    /// Fetches a specific tag by its ID
    /// - Parameters:
    ///   - id: The tag ID to fetch
    ///   - completion: Callback with result
    func findTag(id: String, completion: @escaping (Result<StashScene.Tag, Error>) -> Void) {
        let query = """
        query FindTag($id: ID!) {
          findTag(id: $id) {
            id
            name
            aliases
            image_path
            scene_count
          }
        }
        """

        let variables: [String: Any] = ["id": id]

        struct TagResponse: Decodable {
            let findTag: StashScene.Tag
        }

        executeGraphQLQuery(query: query, variables: variables, completion: { (result: Result<TagResponse, Error>) in
            switch result {
            case .success(let response):
                completion(.success(response.findTag))
            case .failure(let error):
                completion(.failure(error))
            }
        })
    }

    // MARK: - Filtering Methods
    
    /// Fetch scenes using a filter preset
    /// - Parameters:
    ///   - preset: The filter preset to use
    ///   - page: Page number (1-based)
    ///   - perPage: Number of results per page
    ///   - appendResults: Whether to append to existing results
    func filterScenesByPreset(preset: FilterPreset, page: Int = 1, perPage: Int = 40, appendResults: Bool = false) async {
        isLoading = true
        
        // Get the GraphQL query for this preset
        let query = preset.getGraphQLQuery(page: page, perPage: perPage)
        
        guard let url = URL(string: "\(serverAddress)/graphql") else {
            print("❌ Invalid URL for filter preset")
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
        request.httpBody = query.data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            let scenesResponse = try JSONDecoder().decode(ScenesResponse.self, from: data)
            
            await MainActor.run {
                totalSceneCount = scenesResponse.data.findScenes.count
                
                if appendResults {
                    // Filter out duplicates before appending
                    let newScenes = scenesResponse.data.findScenes.scenes.filter { newScene in
                        !self.scenes.contains { $0.id == newScene.id }
                    }
                    self.scenes.append(contentsOf: newScenes)
                    print("✅ Added \(newScenes.count) new scenes (total: \(self.scenes.count))")
                } else {
                    // Filter out VR scenes in memory
                    let allScenes = scenesResponse.data.findScenes.scenes
                    self.scenes = allScenes.filter { scene in
                        // Filter out scenes with VR tag
                        !scene.tags.contains { tag in
                            tag.name.lowercased() == "vr"
                        }
                    }
                    print("✅ Loaded \(self.scenes.count) scenes for preset \(preset.rawValue) (filtered from \(allScenes.count) total)")
                }
                
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                print("❌ Error loading scenes for preset: \(error)")
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    // Extension to send method for GraphQL queries when using async/await
    func send<T: Decodable>(query: String) async throws -> GraphQLResponse<T> {
        // Use the existing performGraphQLRequest method
        return try await performGraphQLRequest(query: query)
    }

    // MARK: - Scene Tag Methods
    
    /// Delete a scene by its ID (also deletes the file and generated assets)
    /// - Parameter id: The scene ID to delete
    /// - Throws: StashAPIError on failure
    func deleteScene(id: String) async throws -> Bool {
        isLoading = true
        defer { isLoading = false }
        
        // Build GraphQL mutation for ScenesDestroy
        let deleteFile = true
        let deleteGenerated = true
        let variables: [String: Any] = [
            "ids": [id],
            "delete_file": deleteFile,
            "delete_generated": deleteGenerated
        ]
        
        // Construct JSON body
        let payload: [String: Any] = [
            "operationName": "ScenesDestroy",
            "variables": variables,
            "query": "mutation ScenesDestroy($ids: [ID!]!, $delete_file: Boolean, $delete_generated: Boolean) { scenesDestroy(input: {ids: $ids, delete_file: $delete_file, delete_generated: $delete_generated}) }"
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard let url = URL(string: "\(serverAddress)/graphql") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw StashAPIError.networkError(URLError(.badServerResponse))
        }
        
        // Decode GraphQL response
        struct ScenesDestroyResponse: Decodable {
            struct Data: Decodable {
                let scenesDestroy: Bool
            }
            let data: Data
            let errors: [GraphQLError]?
        }
        
        let resp = try JSONDecoder().decode(ScenesDestroyResponse.self, from: data)
        if let errors = resp.errors, !errors.isEmpty {
            let msgs = errors.map { $0.message }.joined(separator: "\n")
            throw StashAPIError.graphQLError(msgs)
        }
        
        return resp.data.scenesDestroy
    }

    func updateSceneTags(sceneID: String, tagIDs: [String]) async throws -> StashScene {
        let query = """
        mutation UpdateSceneTags($input: SceneUpdateInput!) {
            sceneUpdate(input: $input) {
                id
                title
                details
                url
                date
                rating100
                organized
                o_counter
                paths {
                    screenshot
                    preview
                    stream
                    webp
                    vtt
                    sprite
                    funscript
                    interactive_heatmap
                }
                files {
                    size
                    duration
                    video_codec
                    width
                    height
                }
                performers {
                    id
                    name
                    gender
                    image_path
                    scene_count
                }
                tags {
                    id
                    name
                }
                studio {
                    id
                    name
                }
                stash_ids {
                    endpoint
                    stash_id
                }
                created_at
                updated_at
            }
        }
        """

        let input: [String: Any] = [
            "id": sceneID,
            "tag_ids": tagIDs
        ]

        let variables: [String: Any] = ["input": input]

        struct SceneUpdateResponse: Decodable {
            let sceneUpdate: StashScene
        }

        let response: SceneUpdateResponse = try await performGraphQLRequest(query: query, variables: variables)
        return response.sceneUpdate
    }

    // Async version of searchTags
    func searchTags(query: String) async throws -> [StashScene.Tag] {
        let graphQLRequest: [String: Any] = [
            "operationName": "FindTags",
            "variables": [
                "filter": [
                    "q": query,
                    "per_page": 20,
                    "sort": "name",
                    "direction": "ASC"
                ]
            ],
            "query": """
            query FindTags($filter: FindFilterType) {
              findTags(filter: $filter) {
                count
                tags {
                  id
                  name
                  scene_count
                  image_count
                }
              }
            }
            """
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: graphQLRequest)
        
        guard let url = URL(string: "\(serverAddress)/graphql") else {
            throw StashAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        configureRequestWithAuth(&request)
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            throw StashAPIError.serverError(httpResponse.statusCode)
        }

        let tagResponse = try JSONDecoder().decode(TagSearchResponse.self, from: data)
        print("✅ Tag search successful for '\(query)', found \(tagResponse.data.findTags.count) tags")
        
        // Sort tags to prioritize exact matches
        let sortedTags = tagResponse.data.findTags.tags.sorted { tag1, tag2 in
            let query_lower = query.lowercased()
            let tag1_lower = tag1.name.lowercased()
            let tag2_lower = tag2.name.lowercased()
            
            // Exact match comes first
            if tag1_lower == query_lower && tag2_lower != query_lower {
                return true
            }
            if tag2_lower == query_lower && tag1_lower != query_lower {
                return false
            }
            
            // Then tags that start with the query
            if tag1_lower.hasPrefix(query_lower) && !tag2_lower.hasPrefix(query_lower) {
                return true
            }
            if tag2_lower.hasPrefix(query_lower) && !tag1_lower.hasPrefix(query_lower) {
                return false
            }
            
            // Finally, sort by name length (shorter names first)
            return tag1.name.count < tag2.name.count
        }
        
        return sortedTags
    }

    // MARK: - Additional Missing Methods

    func searchTags(query: String, completion: @escaping (Result<[StashScene.Tag], Error>) -> Void) {
        let graphQLQuery = """
        query FindTags($filter: FindFilterType) {
          findTags(filter: $filter) {
            count
            tags {
              id
              name
              scene_count
              image_count
            }
          }
        }
        """

        let variables: [String: Any] = [
            "filter": [
                "q": query,
                "per_page": 10,
                "sort": "name",
                "direction": "ASC"
            ]
        ]

        struct TagSearchResponse: Decodable {
            let findTags: TagsData

            struct TagsData: Decodable {
                let count: Int
                let tags: [StashScene.Tag]
            }
        }

        executeGraphQLQuery(query: graphQLQuery, variables: variables, completion: { (result: Result<TagSearchResponse, Error>) in
            switch result {
            case .success(let response):
                completion(.success(response.findTags.tags))
            case .failure(let error):
                completion(.failure(error))
            }
        })
    }

    // MARK: - DLNA Configuration
    
    /// Update DLNA settings in Stash
    /// - Parameter enabled: Whether DLNA should be enabled
    /// - Returns: The new state of DLNA (enabled/disabled)
    func updateDLNASettings(enabled: Bool) async throws -> Bool {
        let query = """
        mutation {
          configureDLNA(input: {
            enabled: \(enabled)
          }) {
            enabled
          }
        }
        """
        
        struct DLNAUpdateResponse: Decodable {
            struct Data: Decodable {
                struct ConfigureDLNA: Decodable {
                    let enabled: Bool
                }
                let configureDLNA: ConfigureDLNA
            }
            let data: Data
        }
        
        do {
            let data = try await performGraphQLRequest(query: query)
            let decoder = JSONDecoder()
            let response = try decoder.decode(DLNAUpdateResponse.self, from: data)
            return response.data.configureDLNA.enabled
        } catch {
            print("❌ Error updating DLNA settings: \(error)")
            throw error
        }
    }

    func fetchPerformers(filter: PerformerFilter = .all, page: Int = 1, appendResults: Bool = false, search: String = "", completion: @escaping (Result<[StashScene.Performer], Error>) -> Void) {
        isLoading = true

        let sceneCountValue: String
        switch filter {
        case .all:
            sceneCountValue = "0"
        case .lessThanTwo:
            sceneCountValue = "2"
        case .twoOrMore:
            sceneCountValue = "2"
        case .tenOrMore:
            sceneCountValue = "10"
        }

        let sceneCountModifier = filter == .lessThanTwo ? "LESS_THAN" : "GREATER_THAN"

        let escapedQuery = search.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

        // Use full JSON-formatted query for females with >2 scenes and all results (no pagination)
        let query = """
        {
            "operationName": "FindPerformers",
            "variables": {
                "filter": {
                    "q": "\(escapedQuery)",
                    "page": 1,
                    "per_page": 10000,
                    "sort": "name",
                    "direction": "ASC"
                },
                "performer_filter": {
                    "gender": {
                        "value": "FEMALE",
                        "modifier": "EQUALS"
                    },
                    "scene_count": {
                        "modifier": "GREATER_THAN",
                        "value": "2"
                    }
                }
            },
            "query": "query FindPerformers($filter: FindFilterType, $performer_filter: PerformerFilterType) { findPerformers(filter: $filter, performer_filter: $performer_filter) { count performers { id name gender image_path scene_count favorite } } }"
        }
        """

        print("📡 Fetching performers with query: \(query)")

        Task {
            do {
                let data = try await executeGraphQLQuery(query)

                struct PerformersResponseData: Decodable {
                    struct Data: Decodable {
                        let findPerformers: FindPerformersResult
                    }

                    struct FindPerformersResult: Decodable {
                        let count: Int
                        let performers: [StashScene.Performer]
                    }

                    let data: Data
                }

                let decoder = JSONDecoder()
                do {
                    let response = try decoder.decode(PerformersResponseData.self, from: data)

                    await MainActor.run {
                        if appendResults {
                            // Filter out duplicates before appending
                            let newPerformers = response.data.findPerformers.performers.filter { newPerformer in
                                !self.performers.contains { $0.id == newPerformer.id }
                            }
                            self.performers.append(contentsOf: newPerformers)
                            self.totalPerformerCount = response.data.findPerformers.count
                            completion(.success(self.performers))
                        } else {
                            // Clear logging to understand what's happening
                            print("📊 PerformersAPI: Setting performers array with \(response.data.findPerformers.performers.count) performers")
                            self.performers = response.data.findPerformers.performers
                            self.totalPerformerCount = response.data.findPerformers.count
                            print("📊 PerformersAPI: After setting, self.performers has \(self.performers.count) items")
                            completion(.success(response.data.findPerformers.performers))
                        }
                        self.isLoading = false
                    }
                } catch {
                    print("❌ Error decoding performers: \(error)")
                    await MainActor.run {
                        self.isLoading = false
                        completion(.failure(error))
                    }
                }
            } catch {
                print("❌ Error loading performers: \(error)")
                await MainActor.run {
                    self.isLoading = false
                    completion(.failure(error))
                }
            }
        }
    }

    func searchScenes(query: String, completion: @escaping (Result<[StashScene], Error>) -> Void) {
        // Escape special characters in the search term
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // Use filter.q for full-text search across scenes
        let graphQLQuery = """
        query FindScenes($filter: FindFilterType) {
            findScenes(filter: $filter) {
                count
                scenes {
                    id
                    title
                    details
                    url
                    date
                    rating100
                    organized
                    o_counter
                    paths {
                        screenshot
                        preview
                        stream
                    }
                    files {
                        size
                        duration
                        video_codec
                        width
                        height
                    }
                    performers {
                        id
                        name
                    }
                    tags {
                        id
                        name
                    }
                    studio {
                        id
                        name
                    }
                    stash_ids {
                        endpoint
                        stash_id
                    }
                    created_at
                    updated_at
                }
            }
        }
        """

        let variables: [String: Any] = [
            "filter": [
                "q": escaped,
                "page": 1,
                "per_page": 100,
                "sort": "title",
                "direction": "ASC"
            ]
        ]

        executeGraphQLQuery(query: graphQLQuery, variables: variables, completion: { (result: Result<ScenesResponseData, Error>) in
            switch result {
            case .success(let response):
                completion(.success(response.findScenes.scenes))
            case .failure(let error):
                completion(.failure(error))
            }
        })
    }

    // Async version of searchScenes
    func searchScenes(query: String, excludeVR: Bool = true) async throws -> [StashScene] {
        // Escape special characters in the search term
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        var variables: [String: Any] = [
            "filter": [
                "q": escaped,
                "page": 1,
                "per_page": 100,
                "sort": "title",
                "direction": "ASC"
            ]
        ]
        
        // Add scene filter to exclude VR paths if needed
        if excludeVR {
            variables["scene_filter"] = [
                "path": [
                    "value": "/Volumes/Backup/VR",
                    "modifier": "EXCLUDES"
                ]
            ]
        }
        
        let graphQLQuery = """
        query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) {
            findScenes(filter: $filter, scene_filter: $scene_filter) {
                count
                scenes {
                    id
                    title
                    details
                    url
                    date
                    rating100
                    organized
                    o_counter
                    paths {
                        screenshot
                        preview
                        stream
                    }
                    files {
                        size
                        duration
                        video_codec
                        width
                        height
                    }
                    performers {
                        id
                        name
                    }
                    tags {
                        id
                        name
                    }
                    studio {
                        id
                        name
                    }
                    stash_ids {
                        endpoint
                        stash_id
                    }
                    created_at
                    updated_at
                }
            }
        }
        """

        let scenesResponse: ScenesResponse = try await performGraphQLRequest(query: graphQLQuery, variables: variables)
        
        print("🔍 Search query: '\(query)' -> Escaped: '\(escaped)'")
        print("📊 Total scenes found: \(scenesResponse.data.findScenes.count)")
        print("📊 Returning \(scenesResponse.data.findScenes.scenes.count) scenes")
        
        // Debug: Print first few scene titles
        for (index, scene) in scenesResponse.data.findScenes.scenes.prefix(3).enumerated() {
            print("  Scene \(index): ID=\(scene.id), Title='\(scene.title ?? "")', Details=\(scene.details != nil ? "yes" : "no")")
        }
        
        return scenesResponse.data.findScenes.scenes
    }
    
    /// Find scenes with specified filters (tags, performers, etc.)
    /// - Parameters:
    ///   - filter: Scene filter options
    ///   - page: Page number
    ///   - perPage: Results per page
    /// - Returns: Tuple with scenes array and total count
    func findScenes(filter: SceneFilterType, page: Int = 1, perPage: Int = 20) async throws -> (scenes: [StashScene], count: Int) {
        // Create tag IDs filter if tags are provided
        var tagValues: [String] = []
        if let tags = filter.tags, !tags.isEmpty {
            tagValues = tags
            print("🏷️ Including tags with IDs: \(tagValues)")
        }

        // Note: The Stash API doesn't support tags_v2 field
        // We'll have to filter out VR tags in memory after fetching
        if let excludedTags = filter.excludedTags, !excludedTags.isEmpty {
            print("⚠️ Excluded tags will be filtered in memory as API doesn't support tags_v2")
            print("🏷️ Planning to exclude tags: \(excludedTags)")
        }

        // Create performer IDs filter if performers are provided
        var performerValues: [String] = []
        if let performers = filter.performers, !performers.isEmpty {
            performerValues = performers
        }

        // Create studio IDs filter if studios are provided
        var studioValues: [String] = []
        if let studios = filter.studios, !studios.isEmpty {
            studioValues = studios
        }
        
        // Create the variables dictionary properly
        var filterDict: [String: Any] = [
            "page": page,
            "per_page": perPage
        ]
        
        if let searchTerm = filter.searchTerm {
            filterDict["q"] = searchTerm
        }
        
        var sceneFilterDict: [String: Any] = [:]
        
        if !tagValues.isEmpty {
            sceneFilterDict["tags"] = [
                "value": tagValues,
                "modifier": "INCLUDES"
            ]
        }
        
        if !performerValues.isEmpty {
            sceneFilterDict["performers"] = [
                "value": performerValues,
                "modifier": "INCLUDES"
            ]
        }
        
        if !studioValues.isEmpty {
            sceneFilterDict["studios"] = [
                "value": studioValues,
                "modifier": "INCLUDES"
            ]
        }
        
        if let minRating = filter.minRating {
            sceneFilterDict["rating100"] = [
                "value": minRating,
                "modifier": "GREATER_THAN"
            ]
        }
        
        if filter.favoritesOnly == true {
            sceneFilterDict["favorite"] = ["value": true]
        }
        
        if let minDuration = filter.minDuration {
            sceneFilterDict["duration"] = [
                "value": minDuration,
                "modifier": "GREATER_THAN"
            ]
        }
        
        if let maxDuration = filter.maxDuration {
            sceneFilterDict["duration"] = [
                "value": maxDuration,
                "modifier": "LESS_THAN"
            ]
        }
        
        let variables: [String: Any] = [
            "filter": filterDict,
            "scene_filter": sceneFilterDict
        ]
        
        let graphQLQuery = """
        query FindTaggedScenes($filter: FindFilterType, $scene_filter: SceneFilterType) {
            findScenes(filter: $filter, scene_filter: $scene_filter) {
                count
                scenes {
                    id
                    title
                    details
                    date
                    rating100
                    o_counter
                    paths {
                        screenshot
                        stream
                        preview
                    }
                    tags {
                        id
                        name
                    }
                    performers {
                        id
                        name
                        image_path
                    }
                    studio {
                        id
                        name
                    }
                    files {
                        width
                        height
                        video_codec
                    }
                }
            }
        }
        """
        
        struct FindScenesResponse: Decodable {
            struct Data: Decodable {
                struct FindScenes: Decodable {
                    let count: Int
                    let scenes: [StashScene]
                }
                let findScenes: FindScenes
            }
            let data: Data
        }
        
        print("📤 Sending GraphQL query with variables: \(variables)")
        let response: FindScenesResponse = try await performGraphQLRequest(query: graphQLQuery, variables: variables)
        
        // Filter out excluded tags in memory if needed
        var filteredScenes = response.data.findScenes.scenes
        if let excludedTags = filter.excludedTags, !excludedTags.isEmpty {
            // Always exclude VR by default
            let tagsToExclude = Set(excludedTags + ["vr"])
            filteredScenes = filteredScenes.filter { scene in
                let sceneTags = Set(scene.tags.map { $0.name.lowercased() })
                let sceneTagIds = Set(scene.tags.map { $0.id })
                // Check both tag names and IDs
                return tagsToExclude.isDisjoint(with: sceneTags) && tagsToExclude.isDisjoint(with: sceneTagIds)
            }
            print("✅ Filtered to \(filteredScenes.count) scenes after excluding tags: \(tagsToExclude)")
        }
        
        return (scenes: filteredScenes, count: filteredScenes.count)
    }

    /// Fetch markers for a specific performer with completion handler
    /// - Parameters:
    ///   - performerId: The performer's ID
    ///   - page: Page number
    ///   - completion: Callback with result
    func fetchPerformerMarkers(performerId: String, page: Int = 1, completion: @escaping (Result<[SceneMarker], Error>) -> Void) {
        // Use Task to call the core implementation and return result via completion handler
        Task {
            do {
                let markers = try await fetchPerformerMarkersCore(performerId: performerId, page: page)
                DispatchQueue.main.async {
                    completion(.success(markers))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Search for markers by query string with completion handler
    /// - Parameters:
    ///   - query: Search term
    ///   - completion: Callback with result
    func searchMarkers(query: String, completion: @escaping (Result<[SceneMarker], Error>) -> Void) {
        // Use Task to call the core implementation and return result via completion handler
        Task {
            do {
                let markers = try await searchMarkersCore(query: query)
                DispatchQueue.main.async {
                    completion(.success(markers))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // Core implementation for searching markers
    private func searchMarkersCore(query: String) async throws -> [SceneMarker] {
        // Ensure the query is properly formatted
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🔎 Marker search query: '\(cleanQuery)'")
        
        // Check if this is a tag search (starts with #)
        if cleanQuery.hasPrefix("#") {
            let tagName = String(cleanQuery.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            print("🏷️ Performing exact tag search for: '\(tagName)'")
            return try await searchMarkersByExactTag(tagName: tagName)
        }
        
        let variables: [String: Any] = [
            "filter": [
                "q": cleanQuery,
                "page": 1,
                "per_page": 100,
                "sort": "title",
                "direction": "ASC"
            ]
        ]
        
        let graphQLQuery = """
        query FindSceneMarkers($filter: FindFilterType) {
            findSceneMarkers(filter: $filter) {
                count
                scene_markers {
                    id
                    title
                    seconds
                    stream
                    preview
                    screenshot
                    scene {
                        id
                        title
                        paths {
                            screenshot
                            preview
                            stream
                        }
                        performers {
                            id
                            name
                            image_path
                        }
                        studio {
                            id
                            name
                        }
                    }
                    primary_tag {
                        id
                        name
                    }
                    tags {
                        id
                        name
                    }
                }
            }
        }
        """

        struct SceneMarkersResponse: Decodable {
            struct Data: Decodable {
                struct FindSceneMarkers: Decodable {
                    let count: Int
                    let scene_markers: [SceneMarker]
                }
                let findSceneMarkers: FindSceneMarkers
            }
            let data: Data
            let errors: [GraphQLError]?
        }

        let markersResponse: SceneMarkersResponse = try await performGraphQLRequest(query: graphQLQuery, variables: variables)
        
        if let errors = markersResponse.errors, !errors.isEmpty {
            let errorMessages = errors.map { $0.message }.joined(separator: ", ")
            throw StashAPIError.graphQLError(errorMessages)
        }

        return markersResponse.data.findSceneMarkers.scene_markers
    }

    // Public async version of searchMarkers
    func searchMarkers(query: String) async throws -> [SceneMarker] {
        return try await searchMarkersCore(query: query)
    }
    
    // Search markers by exact tag name
    private func searchMarkersByExactTag(tagName: String) async throws -> [SceneMarker] {
        // First, find the tag by exact name
        let tagQuery = """
        query FindTags($filter: FindFilterType) {
            findTags(filter: $filter) {
                count
                tags {
                    id
                    name
                }
            }
        }
        """
        
        let tagVariables: [String: Any] = [
            "filter": [
                "q": "\"\(tagName)\"",  // Exact match with quotes
                "page": 1,
                "per_page": 10,
                "sort": "name",
                "direction": "ASC"
            ]
        ]
        
        struct TagResponse: Decodable {
            struct Data: Decodable {
                struct FindTags: Decodable {
                    let tags: [Tag]
                }
                let findTags: FindTags
            }
            let data: Data
        }
        
        struct Tag: Decodable {
            let id: String
            let name: String
        }
        
        let tagResponse: TagResponse = try await performGraphQLRequest(query: tagQuery, variables: tagVariables)
        
        // Find exact match
        guard let tag = tagResponse.data.findTags.tags.first(where: { $0.name.lowercased() == tagName.lowercased() }) else {
            print("❌ No tag found with exact name: '\(tagName)'")
            return []
        }
        
        print("✅ Found tag: \(tag.name) (ID: \(tag.id))")
        
        // Now search for markers with this tag ID
        let markerQuery = """
        query FindSceneMarkers($filter: FindFilterType, $scene_marker_filter: SceneMarkerFilterType) {
            findSceneMarkers(filter: $filter, scene_marker_filter: $scene_marker_filter) {
                count
                scene_markers {
                    id
                    title
                    seconds
                    stream
                    preview
                    screenshot
                    scene {
                        id
                        title
                        paths {
                            screenshot
                            preview
                            stream
                        }
                        performers {
                            id
                            name
                            image_path
                        }
                    }
                    primary_tag {
                        id
                        name
                    }
                    tags {
                        id
                        name
                    }
                }
            }
        }
        """
        
        let markerVariables: [String: Any] = [
            "filter": [
                "page": 1,
                "per_page": 100,
                "sort": "title",
                "direction": "ASC"
            ],
            "scene_marker_filter": [
                "tags": [
                    "value": [tag.id],
                    "modifier": "INCLUDES"
                ]
            ]
        ]
        
        struct MarkerResponse: Decodable {
            struct Data: Decodable {
                struct FindSceneMarkers: Decodable {
                    let count: Int
                    let scene_markers: [SceneMarker]
                }
                let findSceneMarkers: FindSceneMarkers
            }
            let data: Data
        }
        
        let markerResponse: MarkerResponse = try await performGraphQLRequest(query: markerQuery, variables: markerVariables)
        
        print("🔍 Found \(markerResponse.data.findSceneMarkers.count) markers with tag '\(tag.name)'")
        return markerResponse.data.findSceneMarkers.scene_markers
    }

    /// Helper method that updates the internal markers array with search results
    /// - Parameter query: Search term
    func updateMarkersFromSearch(query: String, page: Int = 1, appendResults: Bool = false) async {
        isLoading = true

        // Use proper JSON serialization to avoid format issues
        let graphQLBody: [String: Any] = [
            "operationName": "FindSceneMarkers",
            "variables": [
                "filter": [
                    "q": query,
                    "page": page,
                    "per_page": 500,
                    "sort": "title",
                    "direction": "ASC"
                ],
                "scene_marker_filter": [:]
            ],
            "query": "query FindSceneMarkers($filter: FindFilterType, $scene_marker_filter: SceneMarkerFilterType) { findSceneMarkers(filter: $filter, scene_marker_filter: $scene_marker_filter) { count scene_markers { id title seconds stream preview screenshot scene { id title paths { screenshot preview stream } performers { id name image_path } } primary_tag { id name } tags { id name } } } }"
        ]

        print("🔍 Searching markers with query: '\(query)'")

        do {
            guard let url = URL(string: "\(serverAddress)/graphql") else {
                throw StashAPIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            configureRequestWithAuth(&request)
            
            // Serialize to JSON properly
            let jsonData = try JSONSerialization.data(withJSONObject: graphQLBody, options: [])
            request.httpBody = jsonData
            
            // Debug the request
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("🔍 Request JSON: \(jsonString)")
            }

            let (data, urlResponse) = try await URLSession.shared.data(for: request)
            
            // Debug the response
            if let httpResponse = urlResponse as? HTTPURLResponse {
                print("🔍 Response status: \(httpResponse.statusCode)")
            }
            if let responseString = String(data: data, encoding: .utf8) {
                print("🔍 Response preview: \(responseString.prefix(200))...")
            }

            struct SceneMarkersResponse: Decodable {
                struct Data: Decodable {
                    struct FindSceneMarkers: Decodable {
                        let count: Int
                        let scene_markers: [SceneMarker]
                    }
                    let findSceneMarkers: FindSceneMarkers
                }
                let data: Data
            }

            let response = try JSONDecoder().decode(SceneMarkersResponse.self, from: data)

            await MainActor.run {
                let newMarkers = response.data.findSceneMarkers.scene_markers
                print("✅ Found \(newMarkers.count) markers matching '\(query)' on page \(page) (Searching with larger batch size of 500)")
                
                if appendResults {
                    // Filter out duplicates when appending
                    let uniqueNewMarkers = newMarkers.filter { newMarker in
                        !self.markers.contains { existingMarker in
                            existingMarker.id == newMarker.id
                        }
                    }
                    self.markers.append(contentsOf: uniqueNewMarkers)
                    print("✅ Added \(uniqueNewMarkers.count) new unique markers (total now: \(self.markers.count))")
                    
                    // Log out a sample marker from the new set for debugging
                    if let sampleMarker = uniqueNewMarkers.first {
                        print("📊 Sample new marker: \(sampleMarker.title) (ID: \(sampleMarker.id))")
                    }
                    
                    // Log total markers and page info
                    print("📊 Total markers after append: \(self.markers.count) (page \(page))")
                } else {
                    // Replace existing markers
                    self.markers = newMarkers
                    print("📊 Replaced markers with \(newMarkers.count) new markers (page \(page))")
                }
                
                // Include the total count in the log
                print("✅ Total available markers: \(response.data.findSceneMarkers.count)")
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                print("❌ Error searching markers: \(error)")
                self.markers = []
                self.error = error
                self.isLoading = false
            }
        }
    }

    func createSceneMarker(sceneId: String, title: String, seconds: Float, primaryTagId: String, tagIds: [String], completion: @escaping (Result<SceneMarker, Error>) -> Void) {
        let query = """
        mutation SceneMarkerCreate($input: SceneMarkerCreateInput!) {
            sceneMarkerCreate(input: $input) {
                id
                title
                seconds
                stream
                preview
                screenshot
                primary_tag {
                    id
                    name
                }
                tags {
                    id
                    name
                }
                scene {
                    id
                    title
                }
            }
        }
        """

        let input: [String: Any] = [
            "scene_id": sceneId,
            "title": title,
            "seconds": seconds,
            "primary_tag_id": primaryTagId,
            "tag_ids": tagIds
        ]

        let variables: [String: Any] = ["input": input]

        struct CreateMarkerResponse: Decodable {
            let sceneMarkerCreate: SceneMarker
        }

        executeGraphQLQuery(query: query, variables: variables, completion: { (result: Result<CreateMarkerResponse, Error>) in
            switch result {
            case .success(let response):
                completion(.success(response.sceneMarkerCreate))
            case .failure(let error):
                completion(.failure(error))
            }
        })
    }

    func testConnection(completion: @escaping (Bool) -> Void) {
        let query = """
        query SystemStatus {
          systemStatus {
            status
          }
        }
        """

        struct SystemStatusResponse: Decodable {
            let systemStatus: SystemStatus
        }

        executeGraphQLQuery(query: query, variables: nil, completion: { (result: Result<SystemStatusResponse, Error>) in
            switch result {
            case .success(_):
                completion(true)
            case .failure(_):
                completion(false)
            }
        })
    }

    // Helper method to encode dictionary to JSON string
    private func encodeJSON(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // Method for async/await calls and to support MarkersView
    func fetchMarkers(page: Int = 1, appendResults: Bool = false, performerId: String? = nil) async {
        isLoading = true
        
        // Generate a random seed for consistent random sorting
        let randomSeed = Int.random(in: 0...999999)
        
        let graphQLQuery = """
        {
            "operationName": "FindSceneMarkers",
            "variables": {
                "filter": {
                    "page": \(page),
                    "per_page": 500,
                    "sort": "random_\(randomSeed)",
                    "direction": "ASC"
                },
                "scene_marker_filter": {
                    \(performerId != nil ? "\"performers\": {\"value\": [\"\(performerId!)\"], \"modifier\": \"INCLUDES\"}" : "")
                }
            },
            "query": "query FindSceneMarkers($filter: FindFilterType, $scene_marker_filter: SceneMarkerFilterType) { findSceneMarkers(filter: $filter, scene_marker_filter: $scene_marker_filter) { count scene_markers { ...SceneMarkerData __typename } __typename } } fragment SceneMarkerData on SceneMarker { id title seconds end_seconds stream preview screenshot scene { ...SceneMarkerSceneData __typename } primary_tag { id name __typename } tags { id name __typename } __typename } fragment SceneMarkerSceneData on Scene { id title files { width height path __typename } performers { id name image_path __typename } __typename }"
        }
        """
        
        print("🔍 Fetching markers (page \(page)) from \(serverAddress)")
        
        guard let url = URL(string: "\(serverAddress)/graphql") else {
            print("❌ Invalid URL for markers")
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("u=3, i", forHTTPHeaderField: "Priority")
        request.setValue(serverAddress, forHTTPHeaderField: "Origin")
        request.setValue("nc_sameSiteCookielax=true; nc_sameSiteCookiestrict=true", forHTTPHeaderField: "Cookie")
        request.setValue("\(serverAddress)/scenes/markers", forHTTPHeaderField: "Referer")
        request.httpBody = graphQLQuery.data(using: .utf8)
        
        // Add API Key header which wasn't in the original but might be needed according to documentation
        request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            // Debug: Print the response data
            if let jsonString = String(data: data, encoding: .utf8)?.prefix(500) {
                print("🔍 Response data preview: \(jsonString)...")
            }

            // Define a structure that matches the JSON exactly
            struct GraphQLResponse: Decodable {
                struct Data: Decodable {
                    struct FindSceneMarkers: Decodable {
                        let count: Int
                        let scene_markers: [SceneMarker]
                    }
                    let findSceneMarkers: FindSceneMarkers
                }
                let data: Data
            }

            let response = try JSONDecoder().decode(GraphQLResponse.self, from: data)
            
            await MainActor.run {
                if appendResults {
                    // Filter out duplicates before appending
                    let newMarkers = response.data.findSceneMarkers.scene_markers.filter { newMarker in
                        !self.markers.contains { $0.id == newMarker.id }
                    }
                    self.markers.append(contentsOf: newMarkers)
                    print("✅ Added \(newMarkers.count) new markers")

                    // Debug log for first marker
                    if let firstMarker = self.markers.first {
                        print("📊 First marker details:")
                        print("  ID: \(firstMarker.id)")
                        print("  Title: \(firstMarker.title)")
                        print("  Scene ID: \(firstMarker.scene.id)")
                    }
                } else {
                    self.markers = response.data.findSceneMarkers.scene_markers
                    print("✅ Set \(response.data.findSceneMarkers.scene_markers.count) markers")

                    // Debug log for first marker
                    if let firstMarker = self.markers.first {
                        print("📊 First marker details:")
                        print("  ID: \(firstMarker.id)")
                        print("  Title: \(firstMarker.title)")
                        print("  Scene ID: \(firstMarker.scene.id)")
                    }
                }
                
                self.isLoading = false
            }
        } catch {
            print("❌ Error loading markers: \(error)")
            self.error = error
            isLoading = false
        }
    }// END NEW FETCHMARKERS
    func fetchMarkersByTag(tagId: String, page: Int = 1, appendResults: Bool = false) async {
        isLoading = true

        let query = """
        {
            "operationName": "FindSceneMarkers",
            "variables": {
                "filter": {
                    "page": \(page),
                    "per_page": 500,
                    "sort": "title",
                    "direction": "ASC"
                },
                "scene_marker_filter": {
                    "tags": {
                        "value": ["\(tagId)"],
                        "modifier": "INCLUDES"
                    }
                }
            },
            "query": "query FindSceneMarkers($filter: FindFilterType, $scene_marker_filter: SceneMarkerFilterType) { findSceneMarkers(filter: $filter, scene_marker_filter: $scene_marker_filter) { count scene_markers { id title seconds stream preview screenshot scene { id title paths { screenshot preview stream } performers { id name image_path } } primary_tag { id name } tags { id name } } } }"
        }
        """

        print("🔍 Fetching markers for tag \(tagId) (page \(page))")

        do {
            guard let url = URL(string: "\(serverAddress)/graphql") else {
                throw StashAPIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(serverAddress, forHTTPHeaderField: "Origin")
            request.httpBody = query.data(using: .utf8)

            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Debug the response
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 HTTP Status: \(httpResponse.statusCode)")
            }
            
            print("📊 Response data size: \(data.count) bytes")
            
            // Check if we have valid JSON data
            guard data.count > 0 else {
                throw StashAPIError.emptyResponse
            }
            
            // Try to convert to string for debugging if decoding fails
            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            print("📄 Response preview: \(String(responseString.prefix(200)))...")

            struct SceneMarkersResponse: Decodable {
                struct Data: Decodable {
                    struct FindSceneMarkers: Decodable {
                        let count: Int
                        let scene_markers: [SceneMarker]
                    }
                    let findSceneMarkers: FindSceneMarkers
                }
                let data: Data
            }

            let decodedResponse = try JSONDecoder().decode(SceneMarkersResponse.self, from: data)

            await MainActor.run {
                if appendResults {
                    // Filter out duplicates before appending
                    let newMarkers = decodedResponse.data.findSceneMarkers.scene_markers.filter { newMarker in
                        !self.markers.contains { $0.id == newMarker.id }
                    }
                    self.markers.append(contentsOf: newMarkers)
                    print("✅ Added \(newMarkers.count) new markers for tag \(tagId)")
                } else {
                    self.markers = decodedResponse.data.findSceneMarkers.scene_markers
                    print("✅ Set \(decodedResponse.data.findSceneMarkers.scene_markers.count) markers for tag \(tagId)")
                }

                self.isLoading = false
            }
        } catch let decodingError as DecodingError {
            print("❌ JSON Decoding Error: \(decodingError)")
            switch decodingError {
            case .dataCorrupted(let context):
                print("  - Data corrupted: \(context.debugDescription)")
                if let underlyingError = context.underlyingError {
                    print("  - Underlying error: \(underlyingError)")
                }
            case .keyNotFound(let key, let context):
                print("  - Key not found: \(key), context: \(context.debugDescription)")
            case .typeMismatch(let type, let context):
                print("  - Type mismatch: \(type), context: \(context.debugDescription)")
            case .valueNotFound(let type, let context):
                print("  - Value not found: \(type), context: \(context.debugDescription)")
            @unknown default:
                print("  - Unknown decoding error")
            }
            
            await MainActor.run {
                self.error = decodingError
                self.isLoading = false
            }
        } catch {
            print("❌ Error loading markers by tag: \(error)")
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    /// Simple search for markers by tag name - simplified version
    func searchMarkersByTagName(tagName: String) async {
        print("🏷️ Simplified tag search for: '\(tagName)'")
        isLoading = true
        
        // For now, just fall back to regular text search since that works
        // We can enhance this later if needed
        await updateMarkersFromSearch(query: tagName, page: 1, appendResults: false)
    }
    
    /// Fetch markers by tag and return them (used for shuffle system)
    func fetchMarkersByTagAllPages(tagId: String, page: Int = 1) async throws -> [SceneMarker] {
        let query = """
        {
            "operationName": "FindSceneMarkers",
            "variables": {
                "filter": {
                    "page": \(page),
                    "per_page": 500,
                    "sort": "title",
                    "direction": "ASC"
                },
                "scene_marker_filter": {
                    "tags": {
                        "value": ["\(tagId)"],
                        "modifier": "INCLUDES"
                    }
                }
            },
            "query": "query FindSceneMarkers($filter: FindFilterType, $scene_marker_filter: SceneMarkerFilterType) { findSceneMarkers(filter: $filter, scene_marker_filter: $scene_marker_filter) { count scene_markers { id title seconds stream preview screenshot scene { id title paths { screenshot preview stream } performers { id name image_path } } primary_tag { id name } tags { id name } } } }"
        }
        """

        guard let url = URL(string: "\(serverAddress)/graphql") else {
            throw StashAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(serverAddress, forHTTPHeaderField: "Origin")
        request.httpBody = query.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)

        struct SceneMarkersResponse: Decodable {
            struct Data: Decodable {
                struct FindSceneMarkers: Decodable {
                    let count: Int
                    let scene_markers: [SceneMarker]
                }
                let findSceneMarkers: FindSceneMarkers
            }
            let data: Data
        }

        let response = try JSONDecoder().decode(SceneMarkersResponse.self, from: data)
        return response.data.findSceneMarkers.scene_markers
    }

    // Core implementation for fetching performer markers
    private func fetchPerformerMarkersCore(performerId: String, page: Int = 1) async throws -> [SceneMarker] {
        print("🔍🔍🔍 DEBUG: Fetching markers for performer ID: \(performerId), page: \(page)")

        // Generate random seed for random sorting
        let randomSeed = Int.random(in: 0...999999)

        // Build the proper GraphQL body with both filter and scene_marker_filter variables
        let graphQLBody: [String: Any] = [
            "operationName": "FindSceneMarkers",
            "variables": [
                "filter": [
                    "page": page, 
                    "per_page": 50, 
                    "sort": "random_\(randomSeed)", 
                    "direction": "ASC"
                ],
                "scene_marker_filter": [
                    "performers": [
                        "value": [performerId],
                        "modifier": "INCLUDES_ALL"
                    ]
                ]
            ],
            "query": """
            query FindSceneMarkers($filter: FindFilterType, $scene_marker_filter: SceneMarkerFilterType) {
              findSceneMarkers(filter: $filter, scene_marker_filter: $scene_marker_filter) {
                count
                scene_markers { 
                  id 
                  title 
                  seconds 
                  end_seconds
                  stream
                  preview
                  screenshot
                  scene {
                    id
                    title
                    performers {
                      id
                      name
                      image_path
                    }
                  }
                  primary_tag {
                    id
                    name
                  }
                  tags {
                    id
                    name
                  }
                }
              }
            }
            """
        ]
        
        // Let the JSON encoder handle serialization properly
        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: graphQLBody, options: [])
        } catch {
            throw StashAPIError.invalidData("Failed to serialize GraphQL body: \(error)")
        }
        let graphQLQuery = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        // Log the complete request body to verify both filter and scene_marker_filter are included
        print("🔍 DEBUG: Performer markers GraphQL request:")
        print("📋 FULL GraphQL body: \(graphQLQuery)")
        print("📋 performerId being used: \(performerId)")

        guard let url = URL(string: "\(serverAddress)/graphql") else {
            throw StashAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        
        // Follow the successful pattern from executeGraphQLQuery
        // Set ApiKey header without prefix
        request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
        
        // Set Authorization header with Bearer prefix
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        request.setValue(serverAddress, forHTTPHeaderField: "Origin")
        request.httpBody = graphQLQuery.data(using: .utf8)
        
        // Log the final JSON payload right before sending it to verify it's well-formed
        if let requestBody = String(data: request.httpBody ?? Data(), encoding: .utf8) {
            print("📤 FINAL GraphQL request body:")
            print(requestBody)
            
            // Verify the performer ID is in the request
            if requestBody.contains(performerId) {
                print("✅ Performer ID \(performerId) found in request")
            } else {
                print("❌ ERROR: Performer ID not found in request!")
            }
            
            // Verify the INCLUDES_ALL modifier is in the request
            if requestBody.contains("INCLUDES_ALL") {
                print("✅ INCLUDES_ALL modifier found in request")
            } else {
                print("❌ ERROR: INCLUDES_ALL modifier not found in request!")
            }
            
            // Verify scene_marker_filter is in the request
            if requestBody.contains("scene_marker_filter") {
                print("✅ scene_marker_filter found in request")
            } else {
                print("❌ ERROR: scene_marker_filter not found in request!")
            }
        }
        
        print("🔑 Auth headers set with working pattern from executeGraphQLQuery")

        print("📤 Fetching performer markers for ID: \(performerId), page: \(page)")
        let dataResponse: (Data, URLResponse)
        do {
            dataResponse = try await URLSession.shared.data(for: request)
        } catch {
            throw StashAPIError.networkError(error)
        }
        let (data, response) = dataResponse

        // Log HTTP response code for debugging
        if let httpResponse = response as? HTTPURLResponse {
            print("📥 HTTP response: \(httpResponse.statusCode)")

            // Show FULL response for troubleshooting
            if let jsonStr = String(data: data, encoding: .utf8) {
                print("📥 DEBUG: FULL Response for performer \(performerId):")
                print("\(jsonStr)")
                
                // Log more detailed error info for GraphQL errors
                if jsonStr.contains("errors") {
                    print("❌ GraphQL error detected in response")
                }
            }

            // Check for server errors
            if httpResponse.statusCode >= 400 {
                // For 401 specifically, provide more detailed debugging
                if httpResponse.statusCode == 401 {
                    print("🔐 Authentication failure (401): Check API key configuration")
                    print("🔑 API Key Length: \(apiKey.count) characters")
                    print("🔑 API Key First 5 chars: \(apiKey.prefix(5))")
                    
                    // Check headers that were sent
                    print("📤 Auth headers sent: ApiKey=\(request.value(forHTTPHeaderField: "ApiKey")?.prefix(5) ?? "nil"), Authorization=\(request.value(forHTTPHeaderField: "Authorization")?.prefix(12) ?? "nil")")
                }
                
                let error = StashAPIError.serverError(httpResponse.statusCode)
                throw error
            }
        }

        // Define response structure matching our updated API query format
        struct MarkerResponse: Decodable {
            struct Data: Decodable {
                let findSceneMarkers: FindSceneMarkersResult
                
                struct FindSceneMarkersResult: Decodable {
                    let count: Int
                    let scene_markers: [SceneMarker]
                }
            }
            let data: Data
            let errors: [GraphQLError]?
        }

        // Decode the response with more detailed error handling
        do {
            let response = try JSONDecoder().decode(MarkerResponse.self, from: data)

            // Check for GraphQL errors
            if let errors = response.errors, !errors.isEmpty {
                let errorMessages = errors.map { $0.message }.joined(separator: ", ")
                throw StashAPIError.graphQLError(errorMessages)
            }

            // Get markers directly from response
            let markers = response.data.findSceneMarkers.scene_markers
            print("✅ Found \(markers.count) markers for performer ID: \(performerId)")
            
            // Log first 3 markers IDs and titles to verify results
            if !markers.isEmpty {
                let displayCount = min(3, markers.count)
                for i in 0..<displayCount {
                    let marker = markers[i]
                    print("🎯 Marker \(i+1): ID=\(marker.id), Title=\(marker.title), Seconds=\(marker.seconds)")
                }
            }
            
            return markers
        } catch {
            print("❌ JSON decoding error: \(error)")

            // Try to identify structure issues
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("Missing key: \(key) - \(context.debugDescription)")
                case .typeMismatch(let type, let context):
                    print("Type mismatch: \(type) - \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    print("Value not found: \(type) - \(context.debugDescription)")
                case .dataCorrupted(let context):
                    print("Data corrupted: \(context.debugDescription)")
                @unknown default:
                    print("Unknown decoding error")
                }
            }

            if let decodingError = error as? DecodingError {
                throw StashAPIError.decodingError(decodingError)
            } else {
                throw StashAPIError.invalidData("Unknown error: \(error)")
            }
        }
    }

    /// Public async method for fetching performer markers
    /// - Parameters:
    ///   - performerId: The performer ID
    ///   - page: Page number
    /// - Returns: Array of scene markers
    func fetchPerformerMarkers(performerId: String, page: Int = 1) async throws -> [SceneMarker] {
        return try await fetchPerformerMarkersCore(performerId: performerId, page: page)
    }

    /// Helper method that updates the internal markers array and handles state
    /// - Parameters:
    ///   - performerId: The performer ID
    ///   - page: Page number
    ///   - appendResults: Whether to append results or replace existing ones
    func fetchPerformerMarkers(performerId: String, page: Int = 1, appendResults: Bool = false) async {
        isLoading = true
        do {
            let newMarkers = try await fetchPerformerMarkersCore(performerId: performerId, page: page)
            await MainActor.run {
                if appendResults {
                    // Filter out duplicates before appending
                    let uniqueNewMarkers = newMarkers.filter { newMarker in
                        !markers.contains { $0.id == newMarker.id }
                    }
                    self.markers.append(contentsOf: uniqueNewMarkers)
                } else {
                    self.markers = newMarkers
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                print("Error loading performer markers: \(error)")
                self.error = error
                self.isLoading = false
            }
        }
    }
}

// MARK: - Additional Data Models

// StashStats model for stats endpoint
struct StashStats: Codable {
    let scene_count: Int
    let scenes_size: Int64
    let scene_duration: Double
    let image_count: Int
    let images_size: Int64
    let gallery_count: Int
    let performer_count: Int
    let studio_count: Int
    let movie_count: Int
    let tag_count: Int
}

// Additional filter models
struct TagFilter {
    var name: String?
    var sceneCount: Int?

    func toDictionary() -> [String: Any] {
        var result: [String: Any] = [:]
        if let name = name {
            result["name"] = ["modifier": "INCLUDES", "value": name]
        }
        if let sceneCount = sceneCount {
            result["scene_count"] = ["modifier": "GREATER_THAN", "value": sceneCount]
        }
        return result
    }
}

// Extension to remove duplicates from array
extension Array {
    func removingDuplicates<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        var seen = Set<T>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
    
    func removingDuplicates<T: Hashable>(by transform: (Element) -> T) -> [Element] {
        var seen = Set<T>()
        return filter { seen.insert(transform($0)).inserted }
    }
}