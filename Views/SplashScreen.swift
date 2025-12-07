import Foundation
import SwiftUI

struct SplashScreen: View {
  @State private var isActive = false
  @State private var scale: CGFloat = 0.8
  @State private var opacity: Double = 0
  @StateObject private var appModel = AppModel()

  var body: some View {
    if isActive {
      ContentView()
        .environmentObject(appModel)
    } else {
      ZStack {
        LinearGradient(
          gradient: Gradient(colors: [Color.black, Color(UIColor.systemBlue)]),
          startPoint: .top,
          endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack(spacing: 20) {
          Image(systemName: "play.rectangle.fill")
            .font(.system(size: 100))
            .foregroundStyle(
              .linearGradient(
                colors: [.white, .blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .symbolEffect(.pulse)

          Text("Stash")
            .font(.system(size: 50, weight: .bold, design: .rounded))
            .foregroundColor(.white)

          Text("Media Manager")
            .font(.title2)
            .fontWeight(.light)
            .foregroundColor(.white.opacity(0.8))
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
          // Initialize app state
          initializeAppState()

          withAnimation(.easeInOut(duration: 1.2)) {
            scale = 1.0
            opacity = 1.0
          }

          DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
              self.isActive = true
            }
          }
        }
      }
    }
  }

  private func initializeAppState() {
    print("🚀 Initializing app state in SplashScreen")

    // Check for saved server connection
    if let savedAddress = UserDefaults.standard.string(forKey: "serverAddress"),
      !savedAddress.isEmpty {
      appModel.serverAddress = savedAddress
      appModel.isConnected = true

      // Pre-load data while showing splash screen
      Task {
        do {
          // Add a slight delay to ensure networking is fully initialized
          try await Task.sleep(for: .milliseconds(800))

          // Check connection first
          try await appModel.api.checkServerConnection()

          // Prefetch some initial data to improve user experience
          if appModel.api.connectionStatus == .connected {
            print("🔄 Prefetching initial data...")

            // Fetch scenes
            await appModel.api.fetchScenes(
              page: 1, sort: "random", direction: "DESC", appendResults: false)
            print("✅ Prefetched \(appModel.api.scenes.count) scenes while in splash screen")

            // Also prefetch some performers
            if !appModel.api.scenes.isEmpty {
              await appModel.api.fetchPerformers(
                filter: .twoOrMore, page: 1, appendResults: false, search: ""
              ) { result in
                if case .success(let performers) = result {
                  print("✅ Prefetched \(performers.count) performers while in splash screen")
                }
              }
            }
          } else {
            print("⚠️ Connection check failed: \(appModel.api.connectionStatus)")
          }
        } catch {
          print("⚠️ Error during app initialization: \(error)")
        }
      }
    }
  }
}

#Preview {
  SplashScreen()
}
