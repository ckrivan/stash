import SwiftUI

struct PerformerSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @Binding var selectedPerformer: StashScene.Performer?
    @State private var searchText = ""
    @State private var performers: [StashScene.Performer] = []
    @State private var isLoading = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(performers) { performer in
                        Button(action: {
                            selectedPerformer = performer
                            dismiss()
                        }) {
                            PerformerRow(performer: performer)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            .searchable(text: $searchText)
            .onChange(of: searchText) { _, newValue in
                Task {
                    await searchPerformers(query: newValue)
                }
            }
            .navigationTitle("Select Performer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadPerformers()
        }
    }
    
    private func loadPerformers() async {
        isLoading = true
        await appModel.api.fetchPerformers(filter: .all, page: 1, appendResults: false, search: "", completion: { _ in })
        performers = appModel.api.performers
        isLoading = false
    }
    
    private func searchPerformers(query: String) async {
        guard !query.isEmpty else {
            await loadPerformers()
            return
        }
        
        // Implement performer search
        // This will be added in the next step
    }
} 