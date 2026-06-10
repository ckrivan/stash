import Foundation

/// Append-only on-device debug log (Documents/app_debug.log). Pullable from a
/// connected device via:
///   xcrun devicectl device copy from --domain-type appDataContainer
///     --domain-identifier <your.bundle.id> --source Documents/app_debug.log ...
/// Used for issues that only reproduce on hardware.
enum DebugLog {
    private static let url = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("app_debug.log")

    static func append(_ line: String) {
        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        guard let data = stamped.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
