import SwiftUI

struct FilterOptionsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appModel: AppModel
  @Binding var filterOptions: FilterOptions
  let onApply: () -> Void

  @State private var tempOptions = FilterOptions()
  @State private var selectedRating: Double = 0
  @State private var showingTagSelection = false
  @State private var showingPerformerSelection = false
  @State private var selectedResolutionIndex = 0

  private let resolutions = ["Any", "240p", "480p", "720p", "1080p", "4K"]
  private let durationOptions = [
    "Any": nil,
    "< 5 min": 300,
    "< 15 min": 900,
    "< 30 min": 1800,
    "< 60 min": 3600,
    "> 5 min": 300,
    "> 15 min": 900,
    "> 30 min": 1800,
    "> 60 min": 3600
  ]

  var body: some View {
    NavigationStack {
      Group {
        if UIDevice.current.userInterfaceIdiom == .pad {
          // Enhanced layout for iPad
          VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
              // Left column
              List {
                sortSection
                ratingSection
                resolutionSection
                favoritesSection
                durationSection
              }
              .frame(minWidth: 0, maxWidth: .infinity)

              // Right column
              List {
                tagsSection
                performersSection
              }
              .frame(minWidth: 0, maxWidth: .infinity)
            }
          }
        } else {
          // Standard layout for iPhone
          List {
            sortSection
            ratingSection
            resolutionSection
            favoritesSection
            durationSection
            tagsSection
            performersSection
          }
        }
      }
      .navigationTitle("Filter Options")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Reset") {
            tempOptions.reset()
            selectedRating = 0
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button("Apply") {
            // Copy temp options to the binding
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
        // Initialize temp options from binding
        tempOptions.minimumRating = filterOptions.minimumRating
        tempOptions.selectedResolution = filterOptions.selectedResolution
        tempOptions.isFavoritesOnly = filterOptions.isFavoritesOnly
        tempOptions.minimumDuration = filterOptions.minimumDuration
        tempOptions.maximumDuration = filterOptions.maximumDuration
        tempOptions.selectedTagIds = filterOptions.selectedTagIds
        tempOptions.selectedPerformerIds = filterOptions.selectedPerformerIds
        tempOptions.sortField = filterOptions.sortField
        tempOptions.sortDirection = filterOptions.sortDirection

        // Set UI state
        selectedRating = Double(tempOptions.minimumRating ?? 0)

        // Set resolution index
        if let resolution = tempOptions.selectedResolution,
          let index = resolutions.firstIndex(of: resolution) {
          selectedResolutionIndex = index
        } else {
          selectedResolutionIndex = 0
        }
      }
    }
    .sheet(isPresented: $showingTagSelection) {
      NavigationStack {
        TagSelectionListView(selectedTagIds: $tempOptions.selectedTagIds)
          .environmentObject(appModel)
      }
    }
    .sheet(isPresented: $showingPerformerSelection) {
      NavigationStack {
        PerformerSelectionListView(selectedPerformerIds: $tempOptions.selectedPerformerIds)
          .environmentObject(appModel)
      }
    }
  }

  // MARK: - Sections

  private var sortSection: some View {
    Section(header: Text("Sort By")) {
      Picker("Field", selection: $tempOptions.sortField) {
        Text("Date").tag("date")
        Text("Title").tag("title")
        Text("Rating").tag("rating")
        Text("Duration").tag("duration")
        Text("Random").tag("random")
      }
      .pickerStyle(.menu)

      Picker("Direction", selection: $tempOptions.sortDirection) {
        Text("Descending").tag("DESC")
        Text("Ascending").tag("ASC")
      }
      .pickerStyle(.menu)
    }
  }

  private var ratingSection: some View {
    Section(header: Text("Rating")) {
      VStack(alignment: .leading) {
        Text("Minimum Rating: \(Int(selectedRating))")
          .font(.subheadline)

        Slider(value: $selectedRating, in: 0...100, step: 10) { changed in
          if changed {
            tempOptions.minimumRating = selectedRating > 0 ? Int(selectedRating) : nil
          }
        }
        .onChange(of: selectedRating) { _, newValue in
          tempOptions.minimumRating = newValue > 0 ? Int(newValue) : nil
        }
      }
      .padding(.vertical, 8)
    }
  }

  private var resolutionSection: some View {
    Section(header: Text("Resolution")) {
      Picker("Select Resolution", selection: $selectedResolutionIndex) {
        ForEach(0..<resolutions.count, id: \.self) { index in
          Text(resolutions[index]).tag(index)
        }
      }
      .pickerStyle(.menu)
      .onChange(of: selectedResolutionIndex) { _, newValue in
        tempOptions.selectedResolution = newValue > 0 ? resolutions[newValue] : nil
      }
    }
  }

  private var favoritesSection: some View {
    Section {
      Toggle("Favorites Only", isOn: $tempOptions.isFavoritesOnly)
    }
  }

  private var durationSection: some View {
    Section(header: Text("Duration")) {
      Picker("Minimum Duration", selection: $tempOptions.minimumDuration) {
        ForEach(["Any", "> 5 min", "> 15 min", "> 30 min", "> 60 min"], id: \.self) { label in
          Text(label).tag(durationOptions[label])
        }
      }
      .pickerStyle(.menu)

      Picker("Maximum Duration", selection: $tempOptions.maximumDuration) {
        ForEach(["Any", "< 5 min", "< 15 min", "< 30 min", "< 60 min"], id: \.self) { label in
          Text(label).tag(durationOptions[label])
        }
      }
      .pickerStyle(.menu)
    }
  }

  private var tagsSection: some View {
    Section(header: Text("Tags")) {
      VStack(alignment: .leading) {
        if tempOptions.selectedTagIds.isEmpty {
          Text("No tags selected")
            .foregroundColor(.secondary)
            .padding(.vertical, 8)
        } else {
          Text("\(tempOptions.selectedTagIds.count) tags selected")
            .padding(.vertical, 8)
        }

        Button(action: {
          showingTagSelection = true
        }) {
          Label("Select Tags", systemImage: "tag")
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.bordered)
      }
    }
  }

  private var performersSection: some View {
    Section(header: Text("Performers")) {
      VStack(alignment: .leading) {
        if tempOptions.selectedPerformerIds.isEmpty {
          Text("No performers selected")
            .foregroundColor(.secondary)
            .padding(.vertical, 8)
        } else {
          Text("\(tempOptions.selectedPerformerIds.count) performers selected")
            .padding(.vertical, 8)
        }

        Button(action: {
          showingPerformerSelection = true
        }) {
          Label("Select Performers", systemImage: "person.2")
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.bordered)
      }
    }
  }
}

// MARK: - Preview
#Preview {
  NavigationStack {
    FilterOptionsView(
      filterOptions: .constant(FilterOptions())
    ) {}
    .environmentObject(AppModel())
  }
}
