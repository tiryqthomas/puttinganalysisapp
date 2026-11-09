import Charts
import PuttCore
import SwiftData
import SwiftUI

/// Consistency over time, one session per point.
struct ProgressScreen: View {
    enum Metric: String, CaseIterable, Identifiable {
        case overall = "Overall"
        case tempo = "Tempo"
        case rhythm = "Rhythm"
        case proportion = "Proportion"
        case distance = "Distance"
        var id: Self { self }

        func value(_ r: ConsistencyReport) -> Double? {
            switch self {
            case .overall: r.overall
            case .tempo: r.tempo
            case .rhythm: r.rhythm
            case .proportion: r.proportion
            case .distance: r.distanceControl
            }
        }
    }

    @Environment(AppSettings.self) private var settings
    @Query(sort: \PracticeSession.startedAt, order: .reverse) private var sessions: [PracticeSession]
    @Query private var allStrokes: [PuttStroke]
    @State private var metric: Metric = .overall
    @State private var selectedDate: Date?

    private struct Row: Identifiable {
        let session: PracticeSession
        let report: ConsistencyReport
        var id: UUID { session.id }
    }

    var body: some View {
        let g = settings.geometry
        let chartModel = allStrokes.distanceModel(geometry: g)
        let rows = sessions
            .filter { !$0.strokes.isEmpty }
            .map { Row(session: $0, report: $0.orderedStrokes.report(geometry: g, model: chartModel)) }

        NavigationStack {
            List {
                if rows.isEmpty {
                    ContentUnavailableView("No sessions yet", systemImage: "chart.line.uptrend.xyaxis",
                                           description: Text("Each practice session adds a point here once it has \(Consistency.minimumStrokes) strokes."))
                } else {
                    Section {
                        Picker("Score", selection: $metric) {
                            ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        trend(rows: rows)
                            .frame(height: 200)
                            .padding(.vertical, 8)
                    } header: {
                        Text("\(metric.rawValue) score by session")
                    } footer: {
                        Text(footnote)
                    }

                    Section("Sessions") {
                        ForEach(rows) { row in
                            NavigationLink {
                                SessionDetail(session: row.session, chart: chartModel)
                            } label: {
                                SessionRow(session: row.session, report: row.report)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Progress")
        }
    }

    private var footnote: String {
        switch metric {
        case .overall: "Average of the scores below. 100 means every stroke matched."
        case .tempo: "How steady your backswing-to-downswing ratio stays, whatever the length."
        case .rhythm: "How steady your total stroke time stays. Good putters take about the same time for a 5 ft and a 40 ft putt."
        case .proportion: "How steady your follow-through is relative to your backswing."
        case .distance: "How closely each roll matched what your stroke chart predicts for that backswing."
        }
    }

    @ViewBuilder
    private func trend(rows: [Row]) -> some View {
        let pts = rows.compactMap { r in metric.value(r.report).map { (date: r.session.startedAt, score: $0) } }
            .sorted { $0.date < $1.date }
        let nearest = selectedDate.flatMap { d in pts.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) } }

        if pts.isEmpty {
            Text("Not enough strokes in any session for this score yet.")
                .foregroundStyle(.secondary)
        } else {
            Chart {
                ForEach(pts, id: \.date) { p in
                    LineMark(x: .value("Session", p.date), y: .value("Score", p.score))
                        .foregroundStyle(Palette.tint)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Session", p.date), y: .value("Score", p.score))
                        .foregroundStyle(Palette.tint)
                        .symbolSize(nearest?.date == p.date ? 110 : 50)
                }
                if let n = nearest {
                    RuleMark(x: .value("Session", n.date))
                        .foregroundStyle(Color(.separator))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Int(n.score.rounded()))").font(.caption.weight(.semibold))
                                Text(n.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary)
                            }
                            .monospacedDigit()
                            .padding(6)
                            .background(.background, in: RoundedRectangle(cornerRadius: 6))
                        }
                }
            }
            .chartYScale(domain: 0...100)
            .chartXSelection(value: $selectedDate)
            .chartYAxis { AxisMarks(values: [0, 50, 100]) { _ in
            AxisGridLine().foregroundStyle(Color(.separator).opacity(0.5))
            AxisValueLabel()
        } }
        }
    }
}

struct SessionRow: View {
    let session: PracticeSession
    let report: ConsistencyReport

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                Text(session.note.isEmpty ? "\(report.strokeCount) strokes" : "\(report.strokeCount) strokes · \(session.note)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(report.overall.map { "\(Int($0.rounded()))" } ?? "–")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .accessibilityLabel(report.overall.map { "Overall score \(Int($0.rounded()))" } ?? "No score yet")
        }
    }
}

struct SessionDetail: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Bindable var session: PracticeSession
    let chart: DistanceModel?
    @State private var editing: PuttStroke?

    var body: some View {
        let strokes = session.orderedStrokes
        List {
            Section {
                TextField("Where, green speed, anything to remember", text: $session.note, axis: .vertical)
            } header: {
                Text("Note")
            }
            Section("Consistency") {
                ConsistencyRows(report: strokes.report(geometry: settings.geometry, model: chart))
            }
            Section("Strokes") {
                ForEach(Array(strokes.enumerated()), id: \.element.id) { i, s in
                    Button { editing = s } label: { StrokeRow(number: i + 1, stroke: s) }
                        .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle(session.startedAt.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { try? context.save() }
        .sheet(item: $editing) { stroke in
            NavigationStack {
                List {
                    StrokeDetail(stroke: stroke)
                    DistanceEntry(stroke: stroke, suggestion: nil, suggestionLabel: "")
                }
                .navigationTitle("Stroke")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { editing = nil } }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
