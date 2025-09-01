import Foundation
import os.log

extension Logger {
  private static var subsystem = Bundle.main.bundleIdentifier!

  static let networking = Logger(subsystem: subsystem, category: "networking")
  static let ui = Logger(subsystem: subsystem, category: "ui")
  static let player = Logger(subsystem: subsystem, category: "player")
  static let connection = Logger(subsystem: subsystem, category: "connection")

  func logRequest(_ request: URLRequest) {
    let method = request.httpMethod ?? "Unknown"
    let url = request.url?.absoluteString ?? "Unknown"
    let headers = request.allHTTPHeaders?.description ?? "None"
    let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "None"

    self.debug(
      """
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

    self.debug(
      """
      📥 HTTP Response:
      Status: \(status)
      Headers: \(headers)
      Body: \(body)
      """)
  }
}

extension URLRequest {
  var allHTTPHeaders: [String: String]? {
    return self.allHTTPHeaderFields
  }
}
