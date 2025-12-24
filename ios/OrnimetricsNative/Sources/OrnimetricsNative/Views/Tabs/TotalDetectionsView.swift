import Charts
import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#endif

struct TotalDetectionsView: View {
    let total: Int
    let speciesCounts: [String: Int]

    @State private var chartMode: ChartMode = .bar
    @State private var searchText = ""
    @State private var sortAlphabetical = false
    @State private var showPercentage = false
    @State private var minCountFilter: Double = 0
    @State private var showExporter = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                filterControls

                Text("\(total) total detections")
                    .font(.system(size: 36, weight: .bold))

                Picker("Chart mode", selection: $chartMode) {
                    Text("Bar").tag(ChartMode.bar)
                    Text("Pie").tag(ChartMode.pie)
                }
                .pickerStyle(.segmented)

                chartSection
            }
            .padding()
        }
        .navigationTitle("Total Detections")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    copyBreakdown()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                Button {
                    showExporter = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: CSVDocument(text: exportCsv()),
            contentType: .commaSeparatedText,
            defaultFilename: "ornimetrics_detections"
        ) { _ in }
    }

    private var filterControls: some View {
        GlassCard(title: "Filters", subtitle: "Search + sort") {
            TextField("Filter species…", text: $searchText)
                .textFieldStyle(.roundedBorder)
            Toggle("Sort A→Z", isOn: $sortAlphabetical)
            Toggle("Show percentage", isOn: $showPercentage)
            VStack(alignment: .leading) {
                Text("Min count: \(Int(minCountFilter))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $minCountFilter, in: 0...Double(max(1, total)), step: max(1, Double(total) / 10))
            }
        }
    }

    private var chartSection: some View {
        let items = filteredItems()
        if items.isEmpty {
            return AnyView(Text("No results match the current filters.").foregroundStyle(.secondary))
        }
        switch chartMode {
        case .bar:
            return AnyView(barChart(items: items))
        case .pie:
            return AnyView(pieChart(items: items))
        }
    }

    private func barChart(items: [(String, Int)]) -> some View {
        let maxCount = max(1, items.map { $0.1 }.max() ?? 1)
        return VStack(spacing: 12) {
            ForEach(items, id: \.0) { species, count in
                let fraction = Double(count) / Double(maxCount)
                HStack {
                    Text(species.replacingOccurrences(of: "_", with: " "))
                        .frame(width: 120, alignment: .leading)
                        .font(.subheadline)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(0.2))
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.mint)
                                .frame(width: proxy.size.width * fraction)
                        }
                    }
                    .frame(height: 16)
                    Text(valueLabel(count: count))
                        .frame(width: 60, alignment: .trailing)
                        .font(.caption)
                }
                .frame(height: 24)
            }
        }
    }

    private func pieChart(items: [(String, Int)]) -> some View {
        Chart(items, id: \.0) { item in
            SectorMark(
                angle: .value("Detections", item.1),
                innerRadius: .ratio(0.6),
                angularInset: 1
            )
            .foregroundStyle(by: .value("Species", item.0.replacingOccurrences(of: "_", with: " ")))
        }
        .chartLegend(position: .bottom)
        .frame(height: 300)
    }

    private func filteredItems() -> [(String, Int)] {
        var list = speciesCounts.filter { key, value in
            key.localizedCaseInsensitiveContains(searchText) && Double(value) >= minCountFilter
        }
        .map { ($0.key, $0.value) }
        if sortAlphabetical {
            list.sort { $0.0 < $1.0 }
        } else {
            list.sort { $0.1 > $1.1 }
        }
        return list
    }

    private func valueLabel(count: Int) -> String {
        if showPercentage {
            guard total > 0 else { return "0%" }
            return "\(Int((Double(count) / Double(total)) * 100))%"
        }
        return "\(count)"
    }

    private func copyBreakdown() {
        let breakdown = filteredItems().map { "\($0.0): \($0.1)" }.joined(separator: ", ")
        #if canImport(UIKit)
        UIPasteboard.general.string = "Total: \(total)\n\(breakdown)"
        #endif
    }

    private func exportCsv() -> String {
        let rows = filteredItems().map { "\($0.0),\($0.1)" }.joined(separator: "\n")
        return "species,count\n\(rows)"
    }
}

private enum ChartMode: String, CaseIterable, Identifiable {
    case bar
    case pie

    var id: String { rawValue }
}

private struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8) ?? Data()
        return .init(regularFileWithContents: data)
    }
}
