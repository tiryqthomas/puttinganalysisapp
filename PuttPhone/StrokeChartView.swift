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
        let model = picked.distanceModel(geometry: g)
        let points = picked.compactMap { s -> Point? in
            guard let d = s.distance else { return nil }
            return Point(id: s.id, back: u.lengthValue(g.length(forAngle: s.backswingAngle)), roll: u.distanceValue(d), date: s.recordedAt)
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
                        chart(points: points, model: model)
                            .frame(height: 260)
                            .padding(.vertical, 8)
                    }
                } header: {
                    Text("Roll vs. backswing")
                } footer: {
                    if let model {
                        Text("Fitted from \(model.pointCount) putts. Fit quality \(Int((model.rSquared * 100).rounded()))%.")
                    } else if !points.isEmpty {
                        Text("Needs \(DistanceModel.minimumPoints) putts of different lengths to fit a curve.")
                    }
                }

                if let model {
                    LookupTable(model: model)
                }
            }
            .navigationTitle("Stroke chart")
        }
    }

    @ViewBuilder
    private func chart(points: [Point], model: DistanceModel?) -> some View {
        let u = settings.units
        let maxBack = (points.map(\.back).max() ?? 1) * 1.1
        let nearest = selectedBack.flatMap { x in points.min { abs($0.back - x) < abs($1.back - x) } }

        Chart {
            if let model {
                let steps = 40
                ForEach(0...steps, id: \.self) { i in
                    let back = maxBack * Double(i) / Double(steps)
                    let metres = back / u.lengthValue(1)  // display units back to metres
                    LineMark(
                        x: .value("Backswing", back),
                        y: .value("Roll", u.distanceValue(model.distance(forBackswing: metres)))
                    )
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
            }
            ForEach(points) { p in
                PointMark(x: .value("Backswing", p.back), y: .value("Roll", p.roll))
                    .foregroundStyle(Palette.tint)
                    .symbolSize(nearest?.id == p.id ? 120 : 60)
            }
            if let n = nearest {
                RuleMark(x: .value("Backswing", n.back))
                    .foregroundStyle(Color(.separator))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(String(format: "%.1f", n.back)) \(u.lengthUnit) → \(String(format: "%.1f", n.roll)) \(u.distanceUnit)")
                                .font(.caption.weight(.semibold))
                            Text(n.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .monospacedDigit()
                        .padding(6)
                        .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    }
            }
        }
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

/// "For a 20-footer, take it back 7.4 in": the chart read the other way.
struct LookupTable: View {
    @Environment(AppSettings.self) private var settings
    let model: DistanceModel

    var body: some View {
        let u = settings.units
        let targets: [Double] = u.metric ? [1, 2, 3, 5, 7, 10, 12] : [3, 6, 10, 15, 20, 30, 40]
        Section {
            ForEach(targets, id: \.self) { t in
                let metres = u.metres(fromDistanceValue: t)
                let back = model.backswing(forDistance: metres)
                let supported = model.isSupported(backswing: back)
                LabeledContent {
                    HStack(spacing: 6) {
                        Text(u.length(back))
                            .foregroundStyle(supported ? .primary : .secondary)
                        if !supported {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Outside the putts you've logged")
                        }
                    }
                    .monospacedDigit()
                } label: {
                    Text(u.distance(metres))
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Backswing for each distance")
        } footer: {
            Text("Marked lengths are outside the putts you've logged, so treat them as a guess. Log a few at those distances to firm them up.")
        }
    }
}
