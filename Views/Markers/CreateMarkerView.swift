import SwiftUI
import Foundation

struct CreateMarkerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appModel: AppModel
    // No longer needed: @ObservedObject var api: StashAPI
    @State private var primaryTagId: String = ""
    @State private var primaryTagName: String = ""
    @State private var seconds: String
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showingTagSelection = false
    @State private var allTags: [StashScene.Tag] = []
    
    var sceneID: String {
        return appModel.api.sceneID ?? appModel.currentScene?.id ?? ""
    }
    
    let onMarkerCreated: () -> Void
    
    init(initialSeconds: String = "", sceneID: String = "", onMarkerCreated: @escaping () -> Void = {}) {
        if !sceneID.isEmpty {
            // We'll set this in .onAppear
        }
        
        let formattedSeconds = if let doubleValue = Double(initialSeconds) {
            String(format: "%.3f", doubleValue)
        } else {
            initialSeconds
        }
        self._seconds = State(initialValue: formattedSeconds)
        self.onMarkerCreated = onMarkerCreated
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Timestamp:")
                        Spacer()
                        Text(formatTimestamp(seconds))
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button(action: {
                        Task {
                            do {
                                allTags = try await appModel.api.searchTags(query: "")
                                showingTagSelection = true
                            } catch {
                                print("❌ Error loading tags: \(error)")
                            }
                        }
                    }) {
                        if primaryTagName.isEmpty {
                            Text("Select Primary Tag")
                                .foregroundColor(.accentColor)
                        } else {
                            Text(primaryTagName)
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                
                Section {
                    Button(action: createMarker) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Create Marker")
                        }
                    }
                    .disabled(isLoading || !isValid)
                }
            }
            .navigationTitle("Create Marker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingTagSelection) {
                NavigationStack {
                    TagSelectionView(
                        selectedTagId: $primaryTagId,
                        selectedTagName: $primaryTagName
                    )
                }
            }
            .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK", role: .cancel) { }
            } message: { error in
                Text(error)
            }
            .onAppear {
                if !sceneID.isEmpty {
                    appModel.api.sceneID = sceneID
                }
            }
        }
    }
    
    private func formatTimestamp(_ timestamp: String) -> String {
        guard let seconds = Double(timestamp) else { return timestamp }
        let minutes = Int(seconds / 60)
        let remainingSeconds = Int(seconds.truncatingRemainder(dividingBy: 60))
        let milliseconds = Int((seconds * 1000).truncatingRemainder(dividingBy: 1000))
        return String(format: "%02d:%02d.%03d", minutes, remainingSeconds, milliseconds)
    }
    
    private var isValid: Bool {
        print("📍 Validation check - seconds: \(seconds), sceneID: \(sceneID), primaryTagId: \(primaryTagId)")
        
        let hasSeconds = !seconds.isEmpty
        let hasSceneID = !sceneID.isEmpty
        let hasTagID = !primaryTagId.isEmpty
        
        print("📍 Validation details - hasSeconds: \(hasSeconds), hasSceneID: \(hasSceneID), hasTagID: \(hasTagID)")
        
        let isValid = hasSeconds && hasSceneID && hasTagID
        print("📍 Is valid: \(isValid)")
        return isValid
    }
    
    private func createMarker() {
        guard let secondsFloat = Float(seconds) else {
            errorMessage = "Invalid time format"
            showError = true
            return
        }
        
        guard !sceneID.isEmpty else {
            errorMessage = "No scene selected"
            showError = true
            return
        }
        
        guard !primaryTagId.isEmpty else {
            errorMessage = "Please select a tag"
            showError = true
            return
        }
        
        isLoading = true
        
        Task {
            do {
                print("Creating marker for scene: \(sceneID) at \(seconds) with tag: \(primaryTagId)")
                _ = try await appModel.api.createSceneMarker(
                    sceneId: sceneID,
                    title: primaryTagName,  // Use tag name as title
                    seconds: secondsFloat,
                    primaryTagId: primaryTagId,
                    tagIds: [], // Empty array for additional tags
                    completion: { _ in }
                )
                await MainActor.run {
                    onMarkerCreated()
                    dismiss()
                }
            } catch {
                print("❌ Error creating marker: \(error)")
                errorMessage = error.localizedDescription
                showError = true
                isLoading = false
            }
        }
    }
} 