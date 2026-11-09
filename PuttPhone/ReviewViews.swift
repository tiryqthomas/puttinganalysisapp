import PuttCore
import SwiftData
import SwiftUI

// MARK: - Start

/// Start a session from the phone. The watch opens and shows Ready, so the
/// player can pocket the phone and putt.
struct StartCard: View {
    @Environment(AppSettings.self) private var settings
    @Environment(StrokeInbox.self) private var inbox
    let lastSession: PracticeSession?
    let chart: SpeedChart?
    @State private var speed: GreenSpeed?
    @State private var loaded = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready to putt?").font(.headline)
                Text(summary).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            Picker(selection: $speed) {
                ForEach(GreenSpeed.allCases) { s in
                    VStack {
                        Text("\(s.title) (\(s.stimpRange))")
                        Text(s.example)
                    }
                    .tag(Optional(s))
                }
                Text("Not sure").tag(GreenSpeed?.none)
            } label: {
                Text("Green speed")
                if let speed { Text(speed.example) }
            }
            .pickerStyle(.menu)
            Button {
                inbox.startSession(speed: speed)
            } label: {
                Text("Start session")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        } footer: {
            Text("Your watch opens and shows Ready. You can also start on the watch.")
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            speed = lastSession?.greenSpeed
        }
    }

    private var summary: String {
        guard let s = lastSession else { return "Your first session" }
        var parts = ["Last session \(s.startedAt.formatted(.dateTime.month(.abbreviated).day()))", "\(s.strokes.count) putts"]
        if let overall = s.orderedStrokes.report(geometry: settings.geometry, chart: chart).overall {
            parts.append("score \(Int(overall.rounded()))")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Recap after End

/// What the session was like next to the player's own usual range, in
/// plain words first, then score by score.
struct RecapView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PracticeSession.startedAt, order: .reverse) private var sessions: [PracticeSession]
    @Query private var allStrokes: [PuttStroke]
    let session: PracticeSession
    var onShowChart: () -> Void = {}

    var body: some View {
        let g = settings.geometry
        let chart = allStrokes.speedChart(geometry: g)
        let report = session.orderedStrokes.report(geometry: g, chart: chart)
        // The last 10 sessions before this one with scores.
        let past = sessions
            .filter { $0.id != session.id && $0.startedAt < session.startedAt && !$0.strokes.isEmpty }
            .prefix(10)
            .map { $0.orderedStrokes.report(geometry: g, chart: chart) }
        let rows = ScoreKind.allCases.compactMap { kind -> RecapRow? in
            guard let v = kind.value(report) else { return nil }
            return RecapRow(kind: kind, score: v, range: Consistency.usualRange(of: past.compactMap(kind.value)))
        }
        let best = rows.first { row in
            let previous = past.compactMap(row.kind.value)
            return !previous.isEmpty && row.score > (previous.max() ?? 100)
        }
        let previousBest = best.flatMap { b in past.compactMap(b.kind.value).max() }

        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline(rows))
                            .font(.largeTitle.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle(report))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 4))
                }
                if rows.isEmpty {
                    Section {
                        Text("Scores appear after \(Consistency.minimumStrokes) strokes.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(rows) { RecapScoreRow(row: $0) }
                    } footer: {
                        Text(rows.contains { $0.range != nil }
                             ? "Scale runs from 50 to 100. The striped band is your usual range over your last \(past.count) sessions."
                             : "Your usual range shows after \(Consistency.minimumSessionsForRange) sessions.")
                    }
                }
                if let best, let previousBest {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("New best \(best.kind.title.lowercased())").font(.headline)
                                Text("\(Int(best.score.rounded())), up from \(Int(previousBest.rounded()))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "medal").foregroundStyle(Palette.tint)
                        }
                    }
                }
                Section {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done").font(.headline).frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("See stroke chart") {
                        dismiss()
                        onShowChart()
                    }
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func headline(_ rows: [RecapRow]) -> String {
        let placed = rows.compactMap { r in r.range.map { Consistency.placement(of: r.score, in: $0) } }
        guard !placed.isEmpty else { return "Session saved" }
        let above = placed.filter { $0 == .above }.count, below = placed.filter { $0 == .below }.count
        if above > below { return "Steadier than usual" }
        if below > above { return "A little off your usual" }
        return "Right on your usual"
    }

    private func subtitle(_ r: ConsistencyReport) -> String {
        var parts = [session.startedAt.formatted(date: .abbreviated, time: .shortened)]
        if let s = session.greenSpeed { parts.append("\(s.title) greens") }
        parts.append("\(r.strokeCount) putts")
        let s = session.orderedStrokes
        if let first = s.first?.recordedAt, let last = s.last?.recordedAt, last > first {
            parts.append("\(max(1, Int(last.timeIntervalSince(first) / 60))) min")
        }
        return parts.joined(separator: " · ")
    }
}

/// The four scores, in the order players read them.
enum ScoreKind: String, CaseIterable, Identifiable {
    case tempo, rhythm, proportion, distance
    var id: Self { self }

    var title: String { info.title }

    var info: ScoreInfo {
        switch self {
        case .tempo: .tempo
        case .rhythm: .rhythm
        case .proportion: .proportion
        case .distance: .distance
        }
    }

    func value(_ r: ConsistencyReport) -> Double? {
        switch self {
        case .tempo: r.tempo
        case .rhythm: r.rhythm
        case .proportion: r.proportion
        case .distance: r.distanceControl
        }
    }
}

struct RecapRow: Identifiable {
    let kind: ScoreKind
    let score: Double
    let range: ClosedRange<Double>?
    var id: ScoreKind { kind }
}

struct RecapScoreRow: View {
    let row: RecapRow

    var body: some View {
        let status: String = {
            guard let range = row.range else { return "No usual range yet" }
            switch Consistency.placement(of: row.score, in: range) {
            case .above: return "Above your usual range"
            case .within: return "In your usual range"
            case .below: return "Below your usual range"
            }
        }()
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.kind.title)
                Spacer()
                Text("\(Int(row.score.rounded()))").font(.body.weight(.semibold)).monospacedDigit()
            }
            Text(status).font(.footnote).foregroundStyle(.secondary)
            ScoreTrack(score: row.score, range: row.range)
                .frame(height: 14)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.kind.title) \(Int(row.score.rounded())). \(status)")
    }
}

/// A 50–100 track with the usual range striped and today's score as a dot.
struct ScoreTrack: View {
    let score: Double
    let range: ClosedRange<Double>?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = { (v: Double) in w * CGFloat(min(max((v - 50) / 50, 0), 1)) }
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemFill)).frame(height: 10)
                if let range {
                    Capsule()
                        .fill(Palette.tint.opacity(0.35))
                        .overlay(Stripes().stroke(Palette.tint.opacity(0.55), lineWidth: 2).clipShape(Capsule()))
                        .frame(width: max(x(range.upperBound) - x(range.lowerBound), 6), height: 10)
                        .offset(x: x(range.lowerBound))
                }
                Circle()
                    .fill(Palette.tint)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .frame(width: 14, height: 14)
                    .offset(x: x(score) - 7)
            }
            .frame(height: geo.size.height)
        }
    }
}

/// Diagonal hatching, so the band reads as a range without relying on color.
struct Stripes: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 6
        }
        return p
    }
}

// MARK: - Landmarks

/// Where to take the putter back to, against your own foot, for each roll.
/// Moves with green speed: faster greens need a shorter backswing, so the
/// landmark for the same roll moves toward the inside.
struct LandmarksView: View {
    @Environment(AppSettings.self) private var settings
    let chart: SpeedChart
    let map: LandmarkMap?
    @State var speed: GreenSpeed

    var body: some View {
        let u = settings.units
        List {
            if let map {
                Section {
                    Picker("Green speed", selection: $speed) {
                        ForEach(GreenSpeed.allCases) { s in
                            Text(s == .verySlow ? "<7" : s.stimpRange).accessibilityLabel(s.title).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    ForEach([2.0, 4, 6, 8, 10], id: \.self) { p in
                        let metres = u.metres(fromDistanceValue: p)
                        let back = chart.backswing(forDistance: metres, stimp: speed.typicalStimp)
                        LabeledContent {
                            HStack(spacing: 12) {
                                Text(u.length(back)).foregroundStyle(.secondary)
                                Text(map.landmark(forBackswing: back).title).fontWeight(.semibold)
                                    .frame(minWidth: 112, alignment: .trailing)
                            }
                            .monospacedDigit()
                        } label: {
                            Text(u.distance(metres)).monospacedDigit()
                        }
                    }
                } header: {
                    Text("\(speed.title) greens (\(speed.stimpRange))")
                } footer: {
                    Text("\(Landmark.explanation) " + (map.isMeasured(speed, chart: chart)
                         ? "Based on your \(map.counts[speed] ?? 0) landmark notes on greens this fast."
                         : "Estimated from your other greens. Note a landmark on \(LandmarkMap.minimumOwnPoints) putts at this speed to firm it up."))
                }

                Section("4 paces on each speed") {
                    ForEach(GreenSpeed.allCases) { s in
                        let back = chart.backswing(forDistance: u.metres(fromDistanceValue: 4), stimp: s.typicalStimp)
                        LabeledContent {
                            HStack(spacing: 12) {
                                Text(u.length(back)).foregroundStyle(.secondary)
                                Text(map.landmark(forBackswing: back).title).fontWeight(.semibold)
                                    .frame(minWidth: 112, alignment: .trailing)
                            }
                            .monospacedDigit()
                        } label: {
                            Text(s.title)
                        }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No landmarks yet", systemImage: "shoeprints.fill")
                } description: {
                    Text("When you save a roll, add where the putter stopped against your foot. \(Landmark.explanation) After a few, this shows the landmark for each roll at any green speed.")
                }
            }
        }
        .navigationTitle("Landmarks")
    }
}

// MARK: - Putt log

/// Every putt, newest first, grouped by session, with how it compared with
/// the chart.
struct PuttLogView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \PracticeSession.startedAt, order: .reverse) private var sessions: [PracticeSession]
    let chart: SpeedChart?
    @State private var speed: GreenSpeed?

    var body: some View {
        let u = settings.units, g = settings.geometry
        let shown = sessions.filter { !$0.strokes.isEmpty && (speed == nil || $0.greenSpeed == speed) }
        List {
            Section {
                Picker("Green speed", selection: $speed) {
                    Text("All speeds").tag(GreenSpeed?.none)
                    ForEach(GreenSpeed.allCases) { Text($0.title).tag(Optional($0)) }
                }
            }
            ForEach(shown) { session in
                Section {
                    ForEach(session.orderedStrokes.reversed()) { s in
                        PuttLogRow(stroke: s, chart: chart, units: u, geometry: g)
                    }
                } header: {
                    Text(([session.startedAt.formatted(date: .abbreviated, time: .omitted)] + [session.speedLabel].compactMap { $0 }).joined(separator: " · "))
                }
            }
            if shown.isEmpty {
                Text("No putts at this speed yet.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Putt log")
    }
}

struct PuttLogRow: View {
    let stroke: PuttStroke
    let chart: SpeedChart?
    let units: Units
    let geometry: StrokeGeometry

    var body: some View {
        let back = geometry.length(forAngle: stroke.backswingAngle)
        HStack(alignment: .firstTextBaseline) {
            Text(stroke.recordedAt.formatted(date: .omitted, time: .shortened))
                .font(.footnote).foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(units.length(back)) back · \(Units.tempo(stroke.metrics.tempoRatio))")
                if let l = stroke.landmark {
                    Text(l.title).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let d = stroke.distance {
                    Text(units.distance(d)).fontWeight(.medium)
                    Text(versusChart(d, back: back)).font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Practice").foregroundStyle(.secondary)
                }
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    /// "on chart", or how many paces long or short of it, to the half pace.
    private func versusChart(_ roll: Double, back: Double) -> String {
        guard let chart else { return "" }
        let expected = chart.distance(forBackswing: back, stimp: stroke.session?.stimp ?? chart.usualStimp)
        let diff = Units.roundedPacesSigned(units.distanceValue(roll - expected))
        if diff == 0 { return "on chart" }
        return (diff > 0 ? "+" : "−") + Units.paceNumber(abs(diff)) + " vs chart"
    }
}
