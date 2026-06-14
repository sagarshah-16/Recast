import SwiftUI

struct HistoryView: View {
    @ObservedObject var store = HistoryStore.shared
    @State private var search = ""

    private var filtered: [HistoryEntry] {
        guard !search.isEmpty else { return store.entries }
        return store.entries.filter { entry in
            entry.original.localizedCaseInsensitiveContains(search)
                || entry.variants.contains { $0.text.localizedCaseInsensitiveContains(search) }
                || entry.appName.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        Group {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    "No rewrites yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Press your shortcut while typing anywhere to rewrite text. Everything you rewrite shows up here.")
                )
            } else {
                List(filtered) { entry in
                    HistoryRow(entry: entry)
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $search, prompt: "Search rewrites")
        .toolbar {
            Button("Clear history", role: .destructive) {
                store.clear()
            }
            .disabled(store.entries.isEmpty)
        }
        .frame(minWidth: 560, minHeight: 420)
        .navigationTitle("History")
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.appName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                Text(entry.date, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let picked = entry.pickedCategory {
                    Label(picked, systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Button(expanded ? "Hide" : "Show variants") {
                    expanded.toggle()
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            Text(entry.original)
                .font(.callout)
                .lineLimit(expanded ? nil : 2)

            if expanded {
                ForEach(entry.variants) { variant in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(variant.category)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(variant.text)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(.vertical, 4)
    }
}
