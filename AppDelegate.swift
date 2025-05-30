import SwiftUI
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    var appModel: AppModel = AppModel()
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        print("📱 App launched - loading application state")

        // Configure URLSession for better performance
        configureNetworking()

        // Ensure AppModel is properly initialized and authenticates
        initializeAppModel()
        
        // Set up global audio management
        setupGlobalAudioManagement()

        return true
    }
    
    private func setupGlobalAudioManagement() {
        // Listen for when main video starts and stop all preview videos
        NotificationCenter.default.addObserver(
            forName: Notification.Name("MainVideoPlayerStarted"),
            object: nil,
            queue: .main
        ) { _ in
            print("🔇 AppDelegate: Main video started - stopping all preview players")
            GlobalVideoManager.shared.stopAllPreviews()
        }
        
        // Listen for app going to background and stop all audio
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            print("🔇 AppDelegate: App went to background - stopping all audio")
            GlobalVideoManager.shared.stopAllPreviews()
        }
    }

    private func initializeAppModel() {
        print("📱 Initializing AppModel")

        // Ensure app model has valid connection information
        if !appModel.isConnected && !appModel.serverAddress.isEmpty {
            print("📱 Server address is set but not connected, attempting connection")
            Task {
                appModel.attemptConnection()
            }
        } else if appModel.isConnected {
            print("📱 AppModel already connected to \(appModel.serverAddress)")

            // Pre-fetch markers for faster loading
            Task {
                print("📱 Pre-fetching markers data")
                await appModel.api.fetchMarkers(page: 1, appendResults: false)
                print("📱 Pre-fetched \(appModel.api.markers.count) markers")
            }
        } else {
            print("📱 AppModel not connected and no server address set")
        }
    }
    
    private func configureNetworking() {
        // Configure a better URLCache
        let cacheSize = 50 * 1024 * 1024 // 50 MB
        let cache = URLCache(memoryCapacity: cacheSize, diskCapacity: cacheSize * 5, directory: nil)
        URLCache.shared = cache
        
        // Configure default configuration
        let defaultConfig = URLSessionConfiguration.default
        defaultConfig.timeoutIntervalForRequest = 60.0
        defaultConfig.timeoutIntervalForResource = 120.0
        defaultConfig.requestCachePolicy = .useProtocolCachePolicy
        defaultConfig.httpMaximumConnectionsPerHost = 5
        defaultConfig.httpShouldUsePipelining = true
        defaultConfig.tlsMinimumSupportedProtocolVersion = .TLSv12
        defaultConfig.urlCache = cache
        
        // Apply the configuration to shared session connections
        URLSession.shared.configuration.timeoutIntervalForRequest = 60.0
        URLSession.shared.configuration.timeoutIntervalForResource = 120.0
        
        print("📱 Configured URLSession for increased reliability")
    }
}