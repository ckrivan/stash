import SwiftUI

struct FilterMenuSheet: View {
  @EnvironmentObject private var appModel: AppModel
  @State private var currentFilter: String = "default"
  @Environment(\.dismiss) private var dismiss

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

        Divider()
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

  private func filterButton(
    _ title: String, systemImage: String, filter: String, action: @escaping () -> Void
  ) -> some View {
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
}

#Preview {
  FilterMenuSheet()
    .environmentObject(AppModel())
}
