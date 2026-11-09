import PuttCore
import SwiftData
import SwiftUI

struct PracticeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(StrokeInbox.self) private var inbox
    @Environment(StrokeFaker.self) private var faker
    @Query(sort: \PracticeSession.startedAt, order: .reverse) private var sessions: [PracticeSession]
    @Query private var allStrokes: [PuttStroke]

    @State private var editing: PuttStroke?
    /// Roll distances the simulator suggests, keyed by stroke, so a
    /// simulated stroke can be confirmed with one tap.
    @State private var simulatedRolls: [UUID: Double] = [:]

    private var session: PracticeSession? { sessions.first }
    private var chart: DistanceModel? { allStrokes.distanceModel(geometry: settings.geometry) }

    var body: some View {
        NavigationStack {
            List {
                if let session, let latest = session.orderedStrokes.last {
                    Section {
                        StrokeDetail(stroke: latest)
                        DistanceEntry(
                            stroke: latest,
                            suggestion: suggestion(for: latest),
                            suggestionLabel: simulatedRolls[latest.id] != nil ? "Simulated roll" : "Your chart says"
                        )
                    } header: {
                        Text("Latest stroke")
                    }

                    SessionStrokes(session: session, chart: chart, onSelect: { editing = $0 })
                } else {
                    EmptyPractice()
                }
            }
            .navigationTitle("Practice")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        simulate()
                    } label: {
                        Label("Simulate stroke", systemImage: "waveform.path")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("New session", systemImage: "plus") {
                        context.insert(PracticeSession())
                        try? context.save()
                    }
                }
            }
            .sheet(item: $editing) { stroke in
                NavigationStack {
                    List {
                        StrokeDetail(stroke: stroke)
                        DistanceEntry(stroke: stroke, suggestion: suggestion(for: stroke), suggestionLabel: "Your chart says")
                    }
                    .navigationTitle("Stroke")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { editing = nil }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func suggestion(for stroke: PuttStroke) -> Double? {
        if let roll = simulatedRolls[stroke.id] { return roll }
        guard let chart else { return nil }
        let back = settings.geometry.length(forAngle: stroke.backswingAngle)
        return chart.isSupported(backswing: back) ? chart.distance(forBackswing: back) : nil
    }

    private func simulate() {
        guard let made = faker.stroke(geometry: settings.geometry) else { return }
        let (m, roll) = made
        simulatedRolls[m.id] = roll
        inbox.add(m, sessionID: nil, simulated: true)
    }
}

// MARK: - Latest stroke

struct StrokeDetail: View {
    @Environment(AppSettings.self) private var settings
    let stroke: PuttStroke

    var body: some View {
        let g = settings.geometry, u = settings.units, m = stroke.metrics
        VStack(alignment: .leading, spacing: 12) {
            StrokeShape(trace: m.angleTrace)
                .frame(height: 56)
                .accessibilityLabel("Stroke shape: backswing then follow-through")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Tempo").foregroundStyle(.secondary)
                    Text(Units.tempo(m.tempoRatio)).font(.title2.weight(.semibold))
                    Text(String(format: "%.2f s back · %.2f s down", m.backswingTime, m.downswingTime))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Back").foregroundStyle(.secondary)
                    Text(u.length(g.length(forAngle: m.backswingAngle)))
                    Color.clear.frame(height: 1)
                }
                GridRow {
                    Text("Through").foregroundStyle(.secondary)
                    Text(u.length(g.length(forAngle: m.throughAngle)))
                    Text(String(format: "%.0f%% of backswing", m.throughToBackRatio * 100))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            if stroke.simulated {
                Label("Simulated stroke", systemImage: "waveform.path")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// The arm angle over the stroke: time runs left to right, backswing is
/// above the dashed address line and follow-through below it.
struct StrokeShape: View {
    let trace: [Double]

    var body: some View {
        Canvas { ctx, size in
            guard trace.count > 1 else { return }
            let peak = max(trace.map(abs).max() ?? 1, 1e-6)
            let mid = size.height / 2
            // Address line.
            var base = Path()
            base.move(to: CGPoint(x: 0, y: mid))
            base.addLine(to: CGPoint(x: size.width, y: mid))
            ctx.stroke(base, with: .color(Color(.separator)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            var p = Path()
            for (i, v) in trace.enumerated() {
                let pt = CGPoint(
                    x: size.width * CGFloat(i) / CGFloat(trace.count - 1),
                    y: mid - CGFloat(v / peak) * (mid - 3)
                )
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            ctx.stroke(p, with: .color(Palette.tint), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Distance entry

struct DistanceEntry: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Bindable var stroke: PuttStroke
    let suggestion: Double?
    let suggestionLabel: String

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let u = settings.units
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Roll distance")
                Spacer()
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                    .frame(maxWidth: 90)
                    .monospacedDigit()
                Text(u.distanceUnit).foregroundStyle(.secondary)
            }
            .font(.title3)

            HStack(spacing: 12) {
                if let s = suggestion, stroke.distance == nil {
                    Button {
                        text = format(u.distanceValue(s))
                        save()
                    } label: {
                        Text("\(suggestionLabel) \(u.distance(s))")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button(stroke.distance == nil ? "Save" : "Update") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(parsed == nil)
            }
            .font(.subheadline)

            if stroke.distance == nil {
                Text("Leave it blank for a practice swing. It still counts toward tempo, but not your chart.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .onAppear(perform: load)
        .onChange(of: stroke.id) { load() }
    }

    private var parsed: Double? {
        let v = Double(text.replacingOccurrences(of: ",", with: "."))
        return v.flatMap { $0 > 0 ? $0 : nil }
    }

    private func load() {
        text = stroke.distance.map { format(settings.units.distanceValue($0)) } ?? ""
    }

    private func save() {
        guard let v = parsed else { return }
        stroke.distance = settings.units.metres(fromDistanceValue: v)
        try? context.save()
        focused = false
    }

    private func format(_ v: Double) -> String { String(format: v < 10 ? "%.1f" : "%.0f", v) }
}

// MARK: - Session list

struct SessionStrokes: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    let session: PracticeSession
    /// The all-time stroke chart, which distance control is measured against.
    let chart: DistanceModel?
    let onSelect: (PuttStroke) -> Void

    var body: some View {
        let strokes = session.orderedStrokes
        let r = strokes.report(geometry: settings.geometry, model: chart)
        Section {
            ConsistencyRows(report: r)
            ForEach(Array(strokes.enumerated().reversed()), id: \.element.id) { index, s in
                Button {
                    onSelect(s)
                } label: {
                    StrokeRow(number: index + 1, stroke: s)
                }
                .foregroundStyle(.primary)
            }
            .onDelete { offsets in
                let reversed = Array(strokes.reversed())
                for i in offsets { context.delete(reversed[i]) }
                try? context.save()
            }
        } header: {
            Text("This session · \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
        }
    }
}

struct StrokeRow: View {
    @Environment(AppSettings.self) private var settings
    let number: Int
    let stroke: PuttStroke

    var body: some View {
        let u = settings.units, g = settings.geometry, m = stroke.metrics
        HStack {
            Text("\(number)")
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Units.tempo(m.tempoRatio))  ·  \(u.length(g.length(forAngle: m.backswingAngle))) back")
                Text(u.length(g.length(forAngle: m.throughAngle)) + " through")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let d = stroke.distance {
                Text(u.distance(d)).fontWeight(.medium)
            } else {
                Text("Practice").foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}

struct ConsistencyRows: View {
    let report: ConsistencyReport

    var body: some View {
        if report.overall == nil {
            Text("Consistency scores appear after \(Consistency.minimumStrokes) strokes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ScoreRow(title: "Tempo", score: report.tempo, detail: report.meanTempoRatio.map { "avg " + Units.tempo($0) })
            ScoreRow(title: "Rhythm", score: report.rhythm, detail: "same total time")
            ScoreRow(title: "Proportion", score: report.proportion, detail: "through vs. back")
            ScoreRow(title: "Distance control", score: report.distanceControl, detail: report.distanceControl == nil ? "needs 4 rolls" : "vs. your chart")
        }
    }
}

struct ScoreRow: View {
    let title: String
    let score: Double?
    let detail: String?

    var body: some View {
        LabeledContent {
            Text(score.map { "\(Int($0.rounded()))" } ?? "–")
                .font(.body.weight(.semibold))
                .monospacedDigit()
        } label: {
            Text(title)
            if let detail { Text(detail) }
        }
    }
}

struct EmptyPractice: View {
    var body: some View {
        ContentUnavailableView {
            Label("No strokes yet", systemImage: "figure.golf")
        } description: {
            Text("Start a session on your watch and putt. Each stroke shows up here so you can enter how far the ball rolled. Tap the waveform button to try it with a simulated stroke.")
        }
    }
}
