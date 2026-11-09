import Charts
import PuttCore
import SwiftData
import SwiftUI

/// The player's reference: how big a backswing rolls the ball how far.
struct StrokeChartView: View {
    enum Range: String, CaseIterable, Identifiable {
        case all = "All time"
        case month = "30 days"
        case session = "Last session"
        var id: Self { self }
    }

    @Environment(AppSettings.self) private var settings
    @Query(sort: \PuttStroke.recordedAt) private var strokes: [PuttStroke]
    @Query(sort: \PracticeSession.startedAt, order: .reverse) private var sessions: [PracticeSession]
    @State private var range: Range = .all
    @State private var selectedBack: Double?

    private struct Point: Identifiable {
        let id: UUID
        let back: Double   // display units
        let roll: Double   // display units
        let date: Date
        let speed: GreenSpeed?
        var seriesName: String { speed?.shortTitle ?? "Speed not set" }
    }

    private var filtered: [PuttStroke] {
        let rolled = strokes.filter { $0.distance != nil }
        switch range {
        case .all: return rolled
        case .month: return rolled.filter { $0.recordedAt > Date().addingTimeInterval(-30 * 86400) }
        case .session:
            guard let s = sessions.first(where: { $0.strokes.contains { $0.distance != nil } }) else { return [] }
            return rolled.filter { $0.session?.id == s.id }
        }
    }

    var body: some View {
        let u = settings.units, g = settings.geometry
        let picked = filtered
        let chart = picked.speedChart(geometry: g)
        let points = picked.compactMap { s -> Point? in
            guard let d = s.distance else { return nil }
            return Point(id: s.id, back: u.lengthValue(g.length(forAngle: s.backswingAngle)), roll: u.distanceValue(d),
                         date: s.recordedAt, speed: s.session?.greenSpeed)
        }

        NavigationStack {
            List {
                Section {
                    Picker("Range", selection: $range) {
                        ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    if points.isEmpty {
                        Text("Enter roll distances on the Practice tab and your chart builds here.")
                            .foregroundStyle(.secondary)
                    } else {
                        plot(points: points, chart: chart)
                            .frame(height: 280)
                            .padding(.vertical, 8)
                    }
                } header: {
                    Text("Roll vs. backswing")
                } footer: {
                    if let chart {
                        Text("Fitted from \(chart.combined.pointCount) putts. A solid curve comes from putts at that speed; a dashed one is estimated from your other greens.")
                    } else if !points.isEmpty {
                        Text("Needs \(DistanceModel.minimumPoints) putts of different lengths to fit a curve.")
                    }
                }

                if let chart {
                    CourseSpeedTable(chart: chart, speed: $courseSpeed)
                }
            }
            .navigationTitle("Stroke chart")
            .onAppear {
                if courseSpeed == nil, let usual = chart?.usualStimp { courseSpeed = GreenSpeed(stimp: usual) }
            }
        }
    }

    @State private var courseSpeed: GreenSpeed?

    @ViewBuilder
    private func plot(points: [Point], chart: SpeedChart?) -> some View {
        let u = settings.units
        let maxBack = (points.map(\.back).max() ?? 1) * 1.1
        let nearest = selectedBack.flatMap { x in points.min { abs($0.back - x) < abs($1.back - x) } }
        // Speeds with putts, plus the course speed picked below so its
        // estimated curve shows next to the ones you've measured.
        let speeds = GreenSpeed.allCases.filter { s in s == courseSpeed || points.contains { $0.speed == s } }

        Chart {
            if let chart {
                ForEach(speeds) { speed in
                    let measured = chart.isMeasured(speed)
                    ForEach(0...40, id: \.self) { i in
                        let back = maxBack * Double(i) / 40
                        let metres = back / u.lengthValue(1)
                        LineMark(
                            x: .value("Backswing", back),
                            y: .value("Roll", u.distanceValue(chart.distance(forBackswing: metres, stimp: speed.typicalStimp))),
                            series: .value("Curve", speed.shortTitle)
                        )
                        .foregroundStyle(by: .value("Green speed", speed.shortTitle))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: measured ? [] : [5, 4]))
                        .interpolationMethod(.catmullRom)
                    }
                }
            }
            ForEach(points) { p in
                PointMark(x: .value("Backswing", p.back), y: .value("Roll", p.roll))
                    .foregroundStyle(by: .value("Green speed", p.seriesName))
                    .symbol(by: .value("Green speed", p.seriesName))
                    .symbolSize(nearest?.id == p.id ? 120 : 55)
            }
            if let n = nearest {
                RuleMark(x: .value("Backswing", n.back))
                    .foregroundStyle(Color(.separator))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(String(format: "%.1f", n.back)) \(u.lengthUnit) → \(Units.paceNumber(n.roll)) \(u.distanceUnit)")
                                .font(.caption.weight(.semibold))
                            Text("\(n.seriesName) · \(n.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .monospacedDigit()
                        .padding(6)
                        .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    }
            }
        }
        .chartForegroundStyleScale(domain: Palette.speedSeries.map(\.name), range: Palette.speedSeries.map(\.color))
        .chartSymbolScale(domain: Palette.speedSeries.map(\.name), range: Palette.speedSeries.map(\.symbol))
        .chartLegend(position: .bottom, alignment: .leading)
        .chartXScale(domain: 0...maxBack)
        .chartXAxisLabel("Backswing (\(u.lengthUnit))")
        .chartYAxisLabel("Roll (\(u.distanceUnit))")
        .chartXSelection(value: $selectedBack)
        .chartYAxis { AxisMarks { _ in
            AxisGridLine().foregroundStyle(Color(.separator).opacity(0.5))
            AxisValueLabel()
        } }
        .chartXAxis { AxisMarks { _ in
            AxisGridLine().foregroundStyle(Color(.separator).opacity(0.5))
            AxisValueLabel()
        } }
    }
}

/// "For a 20-footer on fast greens, take it back 6.8 in": the chart read
/// the other way, at the speed of the course you're about to play.
struct CourseSpeedTable: View {
    @Environment(AppSettings.self) private var settings
    let chart: SpeedChart
    @Binding var speed: GreenSpeed?

    var body: some View {
        let u = settings.units
        let selected = speed ?? GreenSpeed(stimp: chart.usualStimp)
        let usual = GreenSpeed(stimp: chart.usualStimp)
        let targets: [Double] = [1, 2, 3, 4, 6, 8, 10, 13]
        Section {
            Picker("Course speed", selection: Binding(get: { selected }, set: { speed = $0 })) {
                // Five words don't fit a segmented control, so segments show the
                // Stimp range and the header names the speed.
                ForEach(GreenSpeed.allCases) { s in
                    Text(s == .verySlow ? "<7" : s.stimpRange)
                        .accessibilityLabel(s.title)
                        .tag(s)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            ForEach(targets, id: \.self) { t in
                let metres = u.metres(fromDistanceValue: t)
                let back = chart.backswing(forDistance: metres, stimp: selected.typicalStimp)
                let usualBack = chart.backswing(forDistance: metres, stimp: chart.usualStimp)
                let supported = chart.isSupported(backswing: back, stimp: selected.typicalStimp)
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(u.length(back))
                                .foregroundStyle(supported ? .primary : .secondary)
                            if !supported {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Outside the putts you've logged")
                            }
                        }
                        if selected != usual {
                            Text(change(back - usualBack, units: u))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .monospacedDigit()
                } label: {
                    Text(u.distance(metres)).monospacedDigit()
                }
            }
        } header: {
            Text("Backswing at \(selected.title.lowercased()) (\(selected.stimpRange))")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(chart.isMeasured(selected)
                     ? "Based on your \(chart.counts[selected] ?? 0) putts on greens this fast."
                     : "Estimated from your other greens: a roll goes about as much farther as the Stimp is higher. Log \(SpeedChart.minimumOwnPoints) putts at this speed to firm it up.")
                Text("Changes are compared with your usual greens, \(usual.title.lowercased()) (\(usual.stimpRange)). A ? means that length is outside the putts behind the curve.")
            }
        }
    }

    private func change(_ metres: Double, units u: Units) -> String {
        let v = abs(u.lengthValue(metres))
        if v < 0.05 { return "same as usual" }
        return String(format: "%.1f %@ %@ than usual", v, u.lengthUnit, metres < 0 ? "shorter" : "longer")
    }
}
