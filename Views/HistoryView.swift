import SwiftUI

struct HistoryView: View {
  @EnvironmentObject private var appModel: AppModel
  @ObservedObject private var historyManager = SessionHistoryManager.shared

  private var columns: [GridItem] {
    if UIDevice.current.userInterfaceIdiom == .pad {
      return [GridItem(.adaptive(minimum: 350, maximum: 450), spacing: 20)]
    } else {
      return [GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)]
    }
  }

  var body: some View {
    ScrollView {
      if historyManager.entries.isEmpty {
        VStack(spacing: 20) {
          Spacer().frame(height: 100)

          Image(systemName: "clock.arrow.circlepath")
            .font(.system(size: 80))
            .foregroundColor(.gray.opacity(0.5))

          Text("No Watch History")
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)

          Text("Videos you watch will appear here")
            .font(.body)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)

          Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
      } else {
        VStack(alignment: .leading, spacing: 20) {
          // Header with count and clear button
          HStack {
            Text("Watch History")
              .font(.largeTitle)
              .fontWeight(.bold)

            Spacer()

            Text("\(historyManager.entries.count) videos this session")
              .font(.caption)
              .foregroundColor(.secondary)

            Button(action: {
              historyManager.clearHistory()
            }) {
              Label("Clear History", systemImage: "trash")
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.red)
          }
          .padding(.horizontal)
          .padding(.top)

          // History grid
          LazyVGrid(columns: columns, spacing: 20) {
            ForEach(historyManager.entries) { entry in
              HistoryCard(entry: entry) {
                playEntry(entry)
              }
            }
          }
          .padding(.horizontal)
          .padding(.bottom, 100)  // Extra padding for tab bar
        }
      }
    }
    .background(Color(.systemBackground))
  }

  private func playEntry(_ entry: HistoryEntry) {
    if let startSeconds = entry.startSeconds {
      appModel.navigateToScene(entry.scene, startSeconds: startSeconds, skipHistory: true)
    } else {
      appModel.navigateToScene(entry.scene, skipHistory: true)
    }
  }
}

/// Card view for a history entry, adapted for iPad touch interaction
struct HistoryCard: View {
  let entry: HistoryEntry
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      VStack(alignment: .leading, spacing: 8) {
        // Thumbnail with resume position badge
        ZStack(alignment: .bottomTrailing) {
          if !entry.scene.paths.screenshot.isEmpty,
            let url = URL(string: entry.scene.paths.screenshot)
          {
            GeometryReader { geometry in
              CachedAsyncImage(url: url, width: 500) { image in
                image
                  .resizable()
                  .aspectRatio(16 / 9, contentMode: .fill)
              } placeholder: {
                Rectangle()
                  .fill(Color.gray.opacity(0.3))
                  .overlay {
                    Image(systemName: "film")
                      .font(.title)
                      .foregroundColor(.gray)
                  }
              }
              .frame(width: geometry.size.width, height: geometry.size.width * 9 / 16)
              .clipped()
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .cornerRadius(12)
            .overlay(
              RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green, lineWidth: 2)
            )
          } else {
            Rectangle()
              .fill(Color.gray.opacity(0.3))
              .aspectRatio(16 / 9, contentMode: .fit)
              .cornerRadius(12)
              .overlay(
                RoundedRectangle(cornerRadius: 12)
                  .stroke(Color.green, lineWidth: 2)
              )
              .overlay {
                Image(systemName: "film")
                  .font(.title)
                  .foregroundColor(.gray)
              }
          }

          // Resume position badge
          if let startSeconds = entry.startSeconds {
            Text(formatTimestamp(startSeconds))
              .font(.caption2)
              .fontWeight(.semibold)
              .padding(.horizontal, 6)
              .padding(.vertical, 3)
              .background(.ultraThinMaterial)
              .clipShape(Capsule())
              .padding(8)
          }
        }

        // Title
        Text(entry.scene.title ?? "Untitled")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.primary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)

        // Marker title if present
        if let markerTitle = entry.markerTitle {
          Label(markerTitle, systemImage: "bookmark.fill")
            .font(.caption)
            .foregroundColor(.accentColor)
            .lineLimit(1)
        }

        // Performers
        if !entry.scene.performers.isEmpty {
          Label(
            entry.scene.performers.map { $0.name }.joined(separator: ", "),
            systemImage: "person.2"
          )
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)
        }

        // Relative time
        Label(formatRelativeTime(entry.timestamp), systemImage: "clock")
          .font(.caption2)
          .foregroundColor(.secondary)
      }
    }
    .buttonStyle(.plain)
  }

  private func formatTimestamp(_ seconds: Double) -> String {
    let hours = Int(seconds) / 3600
    let minutes = (Int(seconds) % 3600) / 60
    let secs = Int(seconds) % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    } else {
      return String(format: "%d:%02d", minutes, secs)
    }
  }

  private func formatRelativeTime(_ date: Date) -> String {
    let now = Date()
    let interval = now.timeIntervalSince(date)

    if interval < 60 {
      return "Just now"
    } else if interval < 3600 {
      let minutes = Int(interval / 60)
      return "\(minutes) min ago"
    } else {
      let hours = Int(interval / 3600)
      return "\(hours) hour\(hours == 1 ? "" : "s") ago"
    }
  }
}

#Preview {
  HistoryView()
    .environmentObject(AppModel())
}
