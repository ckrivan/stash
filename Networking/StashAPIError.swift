import Foundation

enum StashAPIError: Error, LocalizedError {
    case graphQLError(String)
    case networkError(Error)
    case decodingError(Error)
    case dataNotFound(String)
    case invalidURL
    case invalidResponse
    case serverError(Int)
    case connectionFailed(String)
    case authenticationFailed
    case emptyResponse
    case invalidData(String)
    case taskCancelled
    
    var errorDescription: String? {
        switch self {
        case .graphQLError(let message):
            return "GraphQL Error: \(message)"
        case .networkError(let error):
            return "Network Error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding Error: \(error.localizedDescription)"
        case .dataNotFound(let message):
            return "Data Not Found: \(message)"
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid Server Response"
        case .serverError(let code):
            return "Server Error (\(code))"
        case .connectionFailed(let reason):
            return "Connection Failed: \(reason)"
        case .authenticationFailed:
            return "Authentication Failed"
        case .emptyResponse:
            return "Server returned empty response"
        case .invalidData(let details):
            return "Invalid Data: \(details)"
        case .taskCancelled:
            return "Request was cancelled"
        }
    }
}