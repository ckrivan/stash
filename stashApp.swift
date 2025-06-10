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
        .commands {
            VideoPlayerCommands()
        }
    }
}

// MARK: - Video Player Commands for Mac Catalyst
struct VideoPlayerCommands: Commands {
    var body: some Commands {
        CommandMenu("Video Player") {
            Button("Next Scene") {
                VideoPlayerMenuHandler.handleNextScene()
            }
            .keyboardShortcut("v", modifiers: [])
            
            Button("Seek Backward 30s") {
                VideoPlayerMenuHandler.handleSeekBackward()
            }
            .keyboardShortcut("b", modifiers: [])
            
            Button("Random Position Jump") {
                VideoPlayerMenuHandler.handleRandomJump()
            }
            .keyboardShortcut("n", modifiers: [])
            
            Button("Performer Random Scene") {
                VideoPlayerMenuHandler.handlePerformerScene()
            }
            .keyboardShortcut("m", modifiers: [])
            
            Button("Library Random Shuffle") {
                VideoPlayerMenuHandler.handleLibraryRandom()
            }
            .keyboardShortcut(",", modifiers: [])
            
            Button("Restart from Beginning") {
                VideoPlayerMenuHandler.handleRestart()
            }
            .keyboardShortcut("r", modifiers: [])
            
            Divider()
            
            Button("Seek Backward 30s") {
                VideoPlayerMenuHandler.handleSeekBackward()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            
            Button("Seek Forward 30s") {
                VideoPlayerMenuHandler.handleSeekForward()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            
            Button("Toggle Play/Pause") {
                VideoPlayerMenuHandler.handlePlayPause()
            }
            .keyboardShortcut(.space, modifiers: [])
        }
    }
    
    static func sendKeyboardShortcut(_ keyCode: UIKeyboardHIDUsage) {
        // This method is now deprecated - use VideoPlayerMenuHandler methods instead
        NotificationCenter.default.post(
            name: NSNotification.Name("VideoPlayerKeyboardShortcut"),
            object: nil,
            userInfo: ["keyCode": CFIndex(keyCode.rawValue)]
        )
    }
}
