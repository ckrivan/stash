import SwiftUI

struct FilterMenuView: View {
    @Binding var currentFilter: String
    let onDefaultSelected: () -> Void
    let onNewestSelected: () -> Void
    let onOCounterSelected: () -> Void
    let onRandomSelected: () -> Void
    let onAdvancedFilters: () -> Void
    let onReload: () -> Void
    
    private var filterTitle: String {
        switch currentFilter {
        case "default": return "Default"
        case "newest": return "Newest"
        case "o_counter": return "Most Played"
        case "random": return "Random"
        default: return "Filter"
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Sorting", selection: $currentFilter) {
                    Text("Default").tag("default")
                    Text("Newest").tag("newest")
                    Text("Most Played").tag("o_counter")
                    Text("Random").tag("random")
                }
                .pickerStyle(InlinePickerStyle())
                .onChange(of: currentFilter) { newValue in
                    switch newValue {
                    case "default":
                        onDefaultSelected()
                    case "newest":
                        onNewestSelected()
                    case "o_counter":
                        onOCounterSelected()
                    case "random":
                        onRandomSelected()
                    default:
                        break
                    }
                }
                
                Divider()
                
                Button(action: onAdvancedFilters) {
                    Label("Advanced Filters", systemImage: "slider.horizontal.3")
                }
            } label: {
                HStack {
                    Text(filterTitle)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            
            Button(action: onReload) {
                Image(systemName: "arrow.clockwise")
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }
}

#Preview {
    FilterMenuView(
        currentFilter: .constant("default"),
        onDefaultSelected: {},
        onNewestSelected: {},
        onOCounterSelected: {},
        onRandomSelected: {},
        onAdvancedFilters: {},
        onReload: {}
    )
}