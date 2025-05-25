//
//  stashApp.swift
//  stash
//
//  Created by Charles Krivan on 11/14/24.
//

import SwiftUI
import AVKit
import UIKit
import Foundation

// Import our central types file
@_exported import struct Foundation.URL

@main
struct stashApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var isReady = false
    
    var body: some SwiftUI.Scene {
        WindowGroup {
            SplashScreen()
                .preferredColorScheme(.dark)
                .environmentObject(appDelegate.appModel)
                .onAppear {
                    // Short delay to ensure the AppDelegate has completed its initialization
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isReady = true
                    }
                }
                .task {
                    // Wait for app to be ready before making network requests
                    while !isReady {
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                }
        }
    }
}
