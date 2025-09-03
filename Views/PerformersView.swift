import SwiftUI

struct PerformersView: View {
  @EnvironmentObject private var appModel: AppModel
  @State private var searchText = ""
  @State private var isLoading = false

  private let columns = [
    GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
  ]

  var filteredPerformers: [StashScene.Performer] {
    if searchText.isEmpty {
      return appModel.api.performers
    } else {
      return appModel.api.performers.filter { performer in
        performer.name.localizedCaseInsensitiveContains(searchText)
      }
    }
  }

  var body: some View {
    performersContent
      .navigationTitle("Performers")
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(action: {
            Task {
              await loadPerformers()
            }
          }) {
            Image(systemName: "arrow.clockwise")
          }
        }
      }
      .task {
        // Load performers immediately when view appears
        if appModel.api.performers.isEmpty && !isLoading {
          print("📱 Initial view task triggered - loading performers")
          await loadPerformers()
        }
      }
  }

  private var performersContent: some View {
    VStack {
      // Search bar
      TextField("Search performers", text: $searchText)
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.top, 8)

      ScrollView(.vertical, showsIndicators: true) {
        if appModel.api.performers.isEmpty || isLoading {
          VStack {
            LoadingRow()
              .padding(.top, 40)
            Text("Loading performers...")
              .foregroundColor(.secondary)
              .padding(.top, 8)
          }
        } else if filteredPerformers.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "person.slash")
              .font(.system(size: 36))
              .foregroundColor(.secondary)
              .scaleIn(from: 0.5, duration: 0.7)
            Text("No performers found")
              .font(.headline)
              .fadeIn(delay: 0.3)
            if searchText.isEmpty {
              Text("No female performers with over 2 scenes available")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fadeIn(delay: 0.6)
            } else {
              Text("Try a different search term")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fadeIn(delay: 0.6)
            }
          }
          .padding(.top, 40)
        } else {
          LazyVGrid(columns: columns, spacing: 16, pinnedViews: []) {
            ForEach(filteredPerformers, id: \.id) { performer in
              Button(action: {
                appModel.navigateToPerformer(performer)
              }) {
                PerformerRow(performer: performer)
                  .applyHoverEffect(scale: 1.03, shadowRadius: 6)
              }
              .buttonStyle(PlainButtonStyle())
            }
          }
          .padding(16)
        }
      }
    }
    .onAppear {
      print("📱 PerformersContent onAppear called")
      print("📱 Current performer count: \(appModel.api.performers.count)")
      print("📱 Is loading: \(isLoading)")

      // Clear any stale performer detail context when returning to performers list
      appModel.performerDetailViewPerformer = nil
      appModel.currentPerformer = nil
      print("🎯 PERFORMERS VIEW: Cleared stale performer context")

      // Immediate loading without task - this is important for first view appearance
      if appModel.api.performers.isEmpty && !isLoading {
        print("📱 Loading performers from content onAppear - DIRECT CALL")
        // Use immediate loading instead of task to ensure it happens right away
        isLoading = true
        appModel.api.fetchPerformers(
          filter: .twoOrMore,
          page: 1,
          appendResults: false,
          search: ""
        ) { result in
          DispatchQueue.main.async {
            self.isLoading = false
            print("📱 Direct loading completed with \(result)")
          }
        }
      }
    }
    .refreshable {
      await loadPerformers()
    }
  }

  private func loadPerformers() async {
    print("📱 loadPerformers called, setting isLoading = true")
    isLoading = true

    // Since we're using filter .twoOrMore and it already sets to > 2 scenes
    await appModel.api.fetchPerformers(
      filter: .twoOrMore,
      page: 1,
      appendResults: false,
      search: ""
    ) { result in
      print("📱 fetchPerformers completed with result: \(result)")

      // Always update UI on main thread
      DispatchQueue.main.async {
        self.isLoading = false

        switch result {
        case .success(let performers):
          print("📱 Successfully loaded \(performers.count) performers")
        // No need to set appModel.api.performers as it's already set in the API

        case .failure(let error):
          print("❌ Error loading performers: \(error)")
        }
      }
    }

    print("📱 loadPerformers: API call initiated")
  }
}

struct LoadingRow: View {
  var body: some View {
    HStack {
      Spacer()
      ProgressView()
        .scaleEffect(1.3)
        .pulse(duration: 1.2, minScale: 0.8, maxScale: 1.2)
      Spacer()
    }
    .padding()
    .listRowSeparator(.hidden)
  }
}
