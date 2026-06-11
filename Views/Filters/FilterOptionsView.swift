import SwiftUI

struct FilterOptionsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appModel: AppModel
  @Binding var filterOptions: FilterOptions
  let onApply: () -> Void

  // FilterOptions is an ObservableObject class — @StateObject (not @State) so
  // @Published edits actually re-render the rows (selection counts, pickers).
  @StateObject private var tempOptions = FilterOptions()
  @State private var selectedRating: Double = 0

  private let resolutions = ["Any", "240p", "480p", "720p", "1080p", "4K"]

  // Explicit optional tags: a dictionary lookup here produced Int?? tags that
  // never matched the Int? selection, so the duration pickers were dead.
  private let durationSteps: [(label: String, seconds: Int?)] = [
    ("Any", nil),
    ("5 min", 300),
    ("15 min", 900),
    ("30 min", 1800),
    ("60 min", 3600),
  ]

  var body: some View {
    NavigationStack {
      // One grouped Form on every size class (HIG) — the old iPad-only
      // two-List columns fought the system sheet layout.
      Form {
        Section("Sort By") {
          Picker("Field", selection: $tempOptions.sortField) {
            Text("Date").tag("date")
            Text("Title").tag("title")
            Text("Rating").tag("rating")
            Text("Duration").tag("duration")
            Text("Random").tag("random")
          }

          Picker("Direction", selection: $tempOptions.sortDirection) {
            Text("Descending").tag("DESC")
            Text("Ascending").tag("ASC")
          }
        }

        Section("Rating") {
          LabeledContent(
            "Minimum Rating",
            value: selectedRating > 0 ? "\(Int(selectedRating))" : "Any")
          Slider(value: $selectedRating, in: 0...100, step: 10)
            .onChange(of: selectedRating) { _, newValue in
              tempOptions.minimumRating = newValue > 0 ? Int(newValue) : nil
            }
        }

        Section("Video") {
          Picker("Resolution", selection: $tempOptions.selectedResolution) {
            ForEach(resolutions, id: \.self) { resolution in
              Text(resolution).tag(resolution == "Any" ? String?.none : resolution)
            }
          }

          Picker("Minimum Duration", selection: $tempOptions.minimumDuration) {
            ForEach(durationSteps, id: \.label) { step in
              Text(step.seconds == nil ? "Any" : "Over \(step.label)").tag(step.seconds)
            }
          }

          Picker("Maximum Duration", selection: $tempOptions.maximumDuration) {
            ForEach(durationSteps, id: \.label) { step in
              Text(step.seconds == nil ? "Any" : "Under \(step.label)").tag(step.seconds)
            }
          }
        }

        Section {
          Toggle("Favorite Performers Only", isOn: $tempOptions.isFavoritesOnly)
        }

        Section("Limit To") {
          // Pushed within the sheet's stack (HIG) instead of stacking sheets.
          NavigationLink {
            TagSelectionListView(selectedTagIds: $tempOptions.selectedTagIds)
              .environmentObject(appModel)
          } label: {
            LabeledContent("Tags") {
              Text(
                tempOptions.selectedTagIds.isEmpty
                  ? "Any" : "\(tempOptions.selectedTagIds.count) selected")
            }
          }

          NavigationLink {
            PerformerSelectionListView(selectedPerformerIds: $tempOptions.selectedPerformerIds)
              .environmentObject(appModel)
          } label: {
            LabeledContent("Performers") {
              Text(
                tempOptions.selectedPerformerIds.isEmpty
                  ? "Any" : "\(tempOptions.selectedPerformerIds.count) selected")
            }
          }
        }

        Section {
          Button("Reset All Filters", role: .destructive) {
            tempOptions.reset()
            selectedRating = 0
          }
          .frame(maxWidth: .infinity, alignment: .center)
        }
      }
      .navigationTitle("Filters")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Apply") {
            filterOptions.minimumRating = tempOptions.minimumRating
            filterOptions.selectedResolution = tempOptions.selectedResolution
            filterOptions.isFavoritesOnly = tempOptions.isFavoritesOnly
            filterOptions.minimumDuration = tempOptions.minimumDuration
            filterOptions.maximumDuration = tempOptions.maximumDuration
            filterOptions.selectedTagIds = tempOptions.selectedTagIds
            filterOptions.selectedPerformerIds = tempOptions.selectedPerformerIds
            filterOptions.sortField = tempOptions.sortField
            filterOptions.sortDirection = tempOptions.sortDirection

            onApply()
            dismiss()
          }
        }
      }
      .onAppear {
        tempOptions.minimumRating = filterOptions.minimumRating
        tempOptions.selectedResolution = filterOptions.selectedResolution
        tempOptions.isFavoritesOnly = filterOptions.isFavoritesOnly
        tempOptions.minimumDuration = filterOptions.minimumDuration
        tempOptions.maximumDuration = filterOptions.maximumDuration
        tempOptions.selectedTagIds = filterOptions.selectedTagIds
        tempOptions.selectedPerformerIds = filterOptions.selectedPerformerIds
        tempOptions.sortField = filterOptions.sortField
        tempOptions.sortDirection = filterOptions.sortDirection

        selectedRating = Double(tempOptions.minimumRating ?? 0)
      }
    }
  }
}

// MARK: - Preview
#Preview {
  FilterOptionsView(
    filterOptions: .constant(FilterOptions())
  ) {}
  .environmentObject(AppModel())
}
