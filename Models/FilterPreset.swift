import Foundation

/// Predefined filter presets for common filtering scenarios
enum FilterPreset: String, CaseIterable, Identifiable {
    case all = "All"
    case recent = "Recent"
    case untagged = "Untagged"
    case unwatched = "Unwatched"
    case favorites = "Favorites"
    case popular = "Popular"
    case highest_rated = "Highest Rated"
    case longest = "Longest"
    case shortest = "Shortest"
    
    var id: String { rawValue }
    
    /// Returns a FilterOptions object configured for this preset
    func getFilterOptions() -> FilterOptions {
        let options = FilterOptions()
        
        switch self {
        case .all:
            // Default options - no filters
            options.sortField = "date"
            options.sortDirection = "DESC"
        
        case .recent:
            options.sortField = "date"
            options.sortDirection = "DESC"
            
        case .untagged:
            // No tags filter - handled separately in query
            options.sortField = "date"
            options.sortDirection = "DESC"
            
        case .unwatched:
            // O-counter is 0 - handled separately in query
            options.sortField = "date"
            options.sortDirection = "DESC"
            
        case .favorites:
            options.isFavoritesOnly = true
            options.sortField = "date"
            options.sortDirection = "DESC"
            
        case .popular:
            options.sortField = "o_counter"
            options.sortDirection = "DESC"
            
        case .highest_rated:
            options.sortField = "rating100"
            options.sortDirection = "DESC"
            
        case .longest:
            options.sortField = "duration"
            options.sortDirection = "DESC"
            
        case .shortest:
            options.sortField = "duration"
            options.sortDirection = "ASC"
        }
        
        return options
    }
    
    /// Returns a GraphQL query string for this preset
    func getGraphQLQuery(page: Int = 1, perPage: Int = 40) -> String {
        let randomSeed = Int.random(in: 0...999999)
        
        switch self {
        case .untagged:
            // Custom query for scenes with no tags
            return """
            {
                "operationName": "FindScenes",
                "variables": {
                    "filter": {
                        "page": \(page),
                        "per_page": \(perPage),
                        "sort": "date",
                        "direction": "DESC"
                    },
                    "scene_filter": {
                        "tags": {
                            "modifier": "EQUALS",
                            "value": []
                        }
                    }
                },
                "query": "query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) { findScenes(filter: $filter, scene_filter: $scene_filter) { count scenes { id title details url date rating100 organized o_counter paths { screenshot preview stream } files { size duration video_codec width height } performers { id name gender } tags { id name } studio { id name } stash_ids { endpoint stash_id } created_at updated_at } } }"
            }
            """
            
        case .unwatched:
            // Custom query for scenes that haven't been watched (o_counter = 0)
            return """
            {
                "operationName": "FindScenes",
                "variables": {
                    "filter": {
                        "page": \(page),
                        "per_page": \(perPage),
                        "sort": "date",
                        "direction": "DESC"
                    },
                    "scene_filter": {
                        "o_counter": {
                            "modifier": "EQUALS",
                            "value": 0
                        }
                    }
                },
                "query": "query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) { findScenes(filter: $filter, scene_filter: $scene_filter) { count scenes { id title details url date rating100 organized o_counter paths { screenshot preview stream } files { size duration video_codec width height } performers { id name gender } tags { id name } studio { id name } stash_ids { endpoint stash_id } created_at updated_at } } }"
            }
            """
            
        case .popular:
            // Custom query for popular scenes (highest o_counter)
            return """
            {
                "operationName": "FindScenes",
                "variables": {
                    "filter": {
                        "page": \(page),
                        "per_page": \(perPage),
                        "sort": "o_counter",
                        "direction": "DESC"
                    }
                },
                "query": "query FindScenes($filter: FindFilterType) { findScenes(filter: $filter) { count scenes { id title details url date rating100 organized o_counter paths { screenshot preview stream } files { size duration video_codec width height } performers { id name gender } tags { id name } studio { id name } stash_ids { endpoint stash_id } created_at updated_at } } }"
            }
            """
            
        case .highest_rated:
            // Custom query for highest rated scenes
            return """
            {
                "operationName": "FindScenes",
                "variables": {
                    "filter": {
                        "page": \(page),
                        "per_page": \(perPage),
                        "sort": "rating100",
                        "direction": "DESC"
                    },
                    "scene_filter": {
                        "rating100": {
                            "modifier": "GREATER_THAN",
                            "value": 0
                        }
                    }
                },
                "query": "query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) { findScenes(filter: $filter, scene_filter: $scene_filter) { count scenes { id title details url date rating100 organized o_counter paths { screenshot preview stream } files { size duration video_codec width height } performers { id name gender } tags { id name } studio { id name } stash_ids { endpoint stash_id } created_at updated_at } } }"
            }
            """
            
        case .longest, .shortest:
            // Custom query for duration sorting
            return """
            {
                "operationName": "FindScenes",
                "variables": {
                    "filter": {
                        "page": \(page),
                        "per_page": \(perPage),
                        "sort": "duration",
                        "direction": "\(self == .longest ? "DESC" : "ASC")"
                    }
                },
                "query": "query FindScenes($filter: FindFilterType) { findScenes(filter: $filter) { count scenes { id title details url date rating100 organized o_counter paths { screenshot preview stream } files { size duration video_codec width height } performers { id name gender } tags { id name } studio { id name } stash_ids { endpoint stash_id } created_at updated_at } } }"
            }
            """
            
        case .favorites:
            // Custom query for favorite scenes
            return """
            {
                "operationName": "FindScenes",
                "variables": {
                    "filter": {
                        "page": \(page),
                        "per_page": \(perPage),
                        "sort": "date",
                        "direction": "DESC"
                    },
                    "scene_filter": {
                        "favorite": {
                            "value": true
                        }
                    }
                },
                "query": "query FindScenes($filter: FindFilterType, $scene_filter: SceneFilterType) { findScenes(filter: $filter, scene_filter: $scene_filter) { count scenes { id title details url date rating100 organized o_counter paths { screenshot preview stream } files { size duration video_codec width height } performers { id name gender } tags { id name } studio { id name } stash_ids { endpoint stash_id } created_at updated_at } } }"
            }
            """
            
        default:
            // Default query for all scenes
            return """
            {
                "operationName": "FindScenes",
                "variables": {
                    "filter": {
                        "page": \(page),
                        "per_page": \(perPage),
                        "sort": "\(self == .all ? "date" : "random_\(randomSeed)")",
                        "direction": "DESC"
                    }
                },
                "query": "query FindScenes($filter: FindFilterType) { findScenes(filter: $filter) { count scenes { id title details url date rating100 organized o_counter paths { screenshot preview stream } files { size duration video_codec width height } performers { id name gender } tags { id name } studio { id name } stash_ids { endpoint stash_id } created_at updated_at } } }"
            }
            """
        }
    }
}
