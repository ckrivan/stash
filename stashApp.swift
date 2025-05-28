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
                VideoPlayerCommands.sendKeyboardShortcut(.keyboardV)
            }
            .keyboardShortcut("v", modifiers: [])
            
            Button("Seek Backward 30s") {
                VideoPlayerCommands.sendKeyboardShortcut(.keyboardB)
            }
            .keyboardShortcut("b", modifiers: [])
            
            Button("Random Position Jump") {
                VideoPlayerCommands.sendKeyboardShortcut(.keyboardN)
            }
            .keyboardShortcut("n", modifiers: [])
            
            Button("Performer Random Scene") {
                VideoPlayerCommands.sendKeyboardShortcut(.keyboardM)
            }
            .keyboardShortcut("m", modifiers: [])
            
            Button("Library Random Shuffle") {
                VideoPlayerCommands.sendKeyboardShortcut(.keyboardComma)
            }
            .keyboardShortcut(",", modifiers: [])
            
            Divider()
            
            Button("Seek Backward 30s") {
                VideoPlayerCommands.sendKeyboardShortcut(.keyboardLeftArrow)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            
            Button("Seek Forward 30s") {
                VideoPlayerCommands.sendKeyboardShortcut(.keyboardRightArrow)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            
            Button("Toggle Play/Pause") {
                VideoPlayerCommands.sendKeyboardShortcut(.keyboardSpacebar)
            }
            .keyboardShortcut(.space, modifiers: [])
        }
    }
    
    static func sendKeyboardShortcut(_ keyCode: UIKeyboardHIDUsage) {
        // Send notification that can be picked up by the video player
        NotificationCenter.default.post(
            name: NSNotification.Name("VideoPlayerKeyboardShortcut"),
            object: nil,
            userInfo: ["keyCode": CFIndex(keyCode.rawValue)]
        )
    }
}
