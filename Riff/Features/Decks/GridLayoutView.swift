import SwiftUI

struct GridLayoutView: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var portraitPreview = true

    var body: some View {
        @Bindable var store = store
        let dimensions = store.grid.dimensions(portrait: portraitPreview)
        let capacity = dimensions.columns * dimensions.rows
        let count = store.selectedDeck?.pads.count ?? 0
        let pagination = DeckPagination(pads: store.selectedDeck?.pads ?? [], capacity: capacity)
        let pages = pagination.pageCount
        Form {
            Section {
                VStack(spacing: 12) {
                    Picker("Preview orientation", selection: $portraitPreview) {
                        Text("Portrait").tag(true)
                        Text("Landscape").tag(false)
                    }.pickerStyle(.segmented)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: dimensions.columns), spacing: 7) {
                        ForEach(0..<capacity, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 7)
                                .fill(index < pagination.pinned.count ? Palette.color("purple") : index < count ? Palette.color("orange") : Palette.raised)
                                .frame(height: min(40, 120 / CGFloat(dimensions.rows)))
                        }
                    }.frame(maxWidth: portraitPreview ? 240 : 340)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(dimensions.columns) columns, \(dimensions.rows) rows")
                    Text("\(capacity) buttons per page").font(.headline)
                    Text("\(count) \(count == 1 ? "button" : "buttons") · \(pages) \(pages == 1 ? "page" : "pages")")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if pagination.pinned.count > 0 {
                        Label("\(pagination.pinned.count) pinned on every page", systemImage: "pin.fill").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            Section {
                Picker("Columns", selection: $store.grid.columns) {
                    Text("Automatic").tag(0)
                    ForEach(1...6, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Rows", selection: $store.grid.rows) {
                    Text("Automatic").tag(0)
                    ForEach(1...6, id: \.self) { Text("\($0)").tag($0) }
                }
                Button("Reset to automatic") { store.grid = GridPreferences() }
            } header: {
                Text(store.selectedDeck?.name ?? "This deck")
            } footer: {
                Text("Saved for this deck on your iPad. With both controls set to Automatic, 6 buttons fit per page and the grid adjusts when you rotate. Extra buttons move to another page; none are removed. Dense grids can scroll in smaller windows.")
            }
        }
        .scrollContentBackground(.hidden).background(Palette.background)
        .navigationTitle("Grid size").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
