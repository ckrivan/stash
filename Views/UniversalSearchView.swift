import SwiftUI

struct UniversalSearchView: View {
    @Binding var searchText: String
    @Binding var isSearching: Bool
    @Binding var searchScope: SearchScope
    var onSearch: ((String, SearchScope) -> Void)?
    
    // Filter actions for iOS inline button
    @Binding var currentFilter: String
    var onDefaultSelected: (() -> Void)?
    var onNewestSelected: (() -> Void)?
    var onOCounterSelected: (() -> Void)?
    var onRandomSelected: (() -> Void)?
    var onAdvancedFilters: (() -> Void)?
    var onReload: (() -> Void)?
    
    @FocusState private var isSearchFieldFocused: Bool
    @State private var showingCancelButton = false
    
    enum SearchScope: String, CaseIterable {
        case scenes = "Scenes"
        case performers = "Performers"
        case tags = "Tags"
        case markers = "Markers"
        
        var icon: String {
            switch self {
            case .scenes: return "film"
            case .performers: return "person.2"
            case .tags: return "tag"
            case .markers: return "bookmark"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 10) {
            // Search bar
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.purple)
                        .font(.system(size: 16, weight: .medium))
                    
                    TextField("Search \(searchScope.rawValue.lowercased())...", text: $searchText)
                        .focused($isSearchFieldFocused)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onSubmit {
                            onSearch?(searchText, searchScope)
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            onSearch?("", searchScope)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 16))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(UIColor.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSearchFieldFocused ? Color.purple : Color.clear, lineWidth: 2)
                        )
                )
                
                // Add compact filter button on iOS only
                if UIDevice.current.userInterfaceIdiom != .pad {
                    Menu {
                        Picker("Sorting", selection: $currentFilter) {
                            Text("Default").tag("default")
                            Text("Newest").tag("newest")
                            Text("O-Counter").tag("o_counter")
                            Text("Random").tag("random")
                        }
                        .pickerStyle(InlinePickerStyle())
                        .onChange(of: currentFilter) { _, newValue in
                            switch newValue {
                            case "default":
                                onDefaultSelected?()
                            case "newest":
                                onNewestSelected?()
                            case "o_counter":
                                onOCounterSelected?()
                            case "random":
                                onRandomSelected?()
                            default:
                                break
                            }
                        }
                        
                        Divider()
                        
                        Button(action: { onAdvancedFilters?() }) {
                            Label("Advanced Filters", systemImage: "slider.horizontal.3")
                        }
                        
                        Button(action: { onReload?() }) {
                            Label("Reload", systemImage: "arrow.clockwise")
                        }
                        
                        Button(action: {
                            // Navigate to settings - we'll need to handle this differently
                            NotificationCenter.default.post(name: Notification.Name("ShowSettings"), object: nil)
                        }) {
                            Label("Settings", systemImage: "gear")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundColor(.purple)
                            .font(.system(size: 18))
                    }
                }
                
                if showingCancelButton {
                    Button("Cancel") {
                        searchText = ""
                        isSearchFieldFocused = false
                        isSearching = false
                        showingCancelButton = false
                        onSearch?("", searchScope)
                    }
                    .foregroundColor(.purple)
                    .font(.system(size: 16, weight: .medium))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal)
            
            // Scope selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(SearchScope.allCases, id: \.self) { scope in
                        Button(action: {
                            searchScope = scope
                            if !searchText.isEmpty {
                                onSearch?(searchText, scope)
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: scope.icon)
                                    .font(.system(size: 14))
                                Text(scope.rawValue)
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                searchScope == scope ?
                                Color.purple :
                                Color(UIColor.secondarySystemBackground)
                            )
                            .foregroundColor(searchScope == scope ? .white : .primary)
                            .cornerRadius(15)
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingCancelButton)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: searchScope)
        .onChange(of: isSearchFieldFocused) { _, newValue in
            withAnimation {
                showingCancelButton = newValue
                isSearching = newValue
            }
        }
        .onChange(of: searchText) { _, newValue in
            // Debounce search
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                if !Task.isCancelled {
                    await MainActor.run {
                        onSearch?(newValue, searchScope)
                    }
                }
            }
        }
    }
}

// Preview
struct UniversalSearchView_Previews: PreviewProvider {
    @State static var searchText = ""
    @State static var isSearching = false
    @State static var searchScope = UniversalSearchView.SearchScope.scenes
    @State static var currentFilter = "default"
    
    static var previews: some View {
        VStack {
            UniversalSearchView(
                searchText: $searchText,
                isSearching: $isSearching,
                searchScope: $searchScope,
                onSearch: { query, scope in
                    print("Searching for: \(query) in \(scope)")
                },
                currentFilter: $currentFilter,
                onDefaultSelected: { print("Default selected") },
                onNewestSelected: { print("Newest selected") },
                onOCounterSelected: { print("O Counter selected") },
                onRandomSelected: { print("Random selected") },
                onAdvancedFilters: { print("Advanced filters") },
                onReload: { print("Reload") }
            )
            .padding()
            
            Spacer()
        }
        .preferredColorScheme(.dark)
    }
}