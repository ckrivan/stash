import SwiftUI

struct SearchBarView: View {
  @Binding var searchText: String
  @Binding var isSearching: Bool
  var placeholder: String = "Search scenes..."
  var onSearch: ((String) -> Void)?

  @FocusState private var isSearchFieldFocused: Bool
  @State private var showingCancelButton = false

  var body: some View {
    HStack(spacing: 10) {
      HStack {
        Image(systemName: "magnifyingglass")
          .foregroundColor(.purple)
          .font(.system(size: 16, weight: .medium))

        TextField(placeholder, text: $searchText)
          .focused($isSearchFieldFocused)
          .textFieldStyle(PlainTextFieldStyle())
          .font(.system(size: 16))
          .foregroundColor(.primary)
          .autocapitalization(.none)
          .disableAutocorrection(true)
          .onSubmit {
            onSearch?(searchText)
          }

        if !searchText.isEmpty {
          Button(action: {
            searchText = ""
            onSearch?("")
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

      if showingCancelButton {
        Button("Cancel") {
          searchText = ""
          isSearchFieldFocused = false
          isSearching = false
          showingCancelButton = false
          onSearch?("")
        }
        .foregroundColor(.purple)
        .font(.system(size: 16, weight: .medium))
        .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .padding(.horizontal)
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingCancelButton)
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
            onSearch?(newValue)
          }
        }
      }
    }
  }
}

// Preview
struct SearchBarView_Previews: PreviewProvider {
  @State static var searchText = ""
  @State static var isSearching = false

  static var previews: some View {
    VStack {
      SearchBarView(
        searchText: $searchText,
        isSearching: $isSearching,
        placeholder: "Search scenes..."
      ) { query in
        print("Searching for: \(query)")
      }
      .padding()

      Spacer()
    }
    .preferredColorScheme(.dark)
  }
}
