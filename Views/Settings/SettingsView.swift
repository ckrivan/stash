import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var appModel: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var defaultPerPage = 20
  @State private var autoplayPreviews = true
  @State private var mutePreviews = true
  @State private var preferHLSStreaming = true
  @State private var showConfirmation = false

  var body: some View {
    NavigationStack {
      Form {
        Section("Server") {
          HStack {
            Text("Address")
            Spacer()
            Text(appModel.serverAddress)
              .foregroundColor(.secondary)
          }

          Button("Disconnect") {
            showConfirmation = true
          }
          .foregroundColor(.red)
        }

        Section("Display") {
          Stepper("Items per page: \(defaultPerPage)", value: $defaultPerPage, in: 10...50, step: 5)

          Toggle("Dark mode", isOn: .constant(true))
        }

        Section("Playback") {
          Toggle("Autoplay previews", isOn: $autoplayPreviews)
            .onChange(of: autoplayPreviews) { _, newValue in
              UserDefaults.standard.set(newValue, forKey: "autoplayPreviews")
            }

          Toggle("Mute previews by default", isOn: $mutePreviews)
            .onChange(of: mutePreviews) { _, newValue in
              UserDefaults.standard.set(newValue, forKey: "mutePreviews")
            }

          Toggle("Prefer HLS streaming", isOn: $preferHLSStreaming)
            .onChange(of: preferHLSStreaming) { _, newValue in
              UserDefaults.standard.set(newValue, forKey: "preferHLSStreaming")
            }
        }

        Section("About") {
          HStack {
            Text("Version")
            Spacer()
            Text("2.0.0")
              .foregroundColor(.secondary)
          }
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            dismiss()
          }
        }
      }
      .alert("Disconnect from Server?", isPresented: $showConfirmation) {
        Button("Cancel", role: .cancel) {}
        Button("Disconnect", role: .destructive) {
          appModel.disconnect()
        }
      } message: {
        Text("You will need to reconnect to access your media library.")
      }
      .onAppear {
        // Load user defaults
        defaultPerPage = UserDefaults.standard.integer(forKey: "defaultPerPage")
        if defaultPerPage == 0 {
          defaultPerPage = 20
          UserDefaults.standard.set(defaultPerPage, forKey: "defaultPerPage")
        }

        autoplayPreviews = UserDefaults.standard.bool(forKey: "autoplayPreviews")
        if !UserDefaults.standard.contains(key: "autoplayPreviews") {
          autoplayPreviews = true
          UserDefaults.standard.set(true, forKey: "autoplayPreviews")
        }

        mutePreviews = UserDefaults.standard.bool(forKey: "mutePreviews")
        if !UserDefaults.standard.contains(key: "mutePreviews") {
          mutePreviews = true
          UserDefaults.standard.set(true, forKey: "mutePreviews")
        }

        preferHLSStreaming = UserDefaults.standard.bool(forKey: "preferHLSStreaming")
        if !UserDefaults.standard.contains(key: "preferHLSStreaming") {
          preferHLSStreaming = true
          UserDefaults.standard.set(true, forKey: "preferHLSStreaming")
        }
      }
    }
  }
}

// Extension to check if a key exists in UserDefaults
extension UserDefaults {
  func contains(key: String) -> Bool {
    return object(forKey: key) != nil
  }
}

#Preview {
  SettingsView()
    .environmentObject(AppModel())
}
