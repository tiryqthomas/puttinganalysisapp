import PuttCore
import SwiftUI
import WatchKit

// MARK: - Start

struct StartView: View {
    @Environment(PracticeModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Putting")
                    .font(.title3.weight(.semibold))
                if model.sensorsAvailable {
                    Text("Wear the watch on your lead wrist. Hold still at address before each putt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label("Motion sensors aren't available on this device.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                GreenSpeedPicker()
                Button {
                    model.start()
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(.accentColor)
                .disabled(!model.sensorsAvailable)
                if !model.strokes.isEmpty {
                    Text("Last session: \(model.strokes.count) strokes")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

/// Picks the green speed before a session. Opens a list, one tap per range.
struct GreenSpeedPicker: View {
    @Environment(PracticeModel.self) private var model

    var body: some View {
        NavigationLink {
            List {
                ForEach(GreenSpeed.allCases) { s in
                    Button {
                        model.greenSpeed = s
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.shortTitle)
                                Text("Stimp \(s.stimpRange)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.greenSpeed == s {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
                Button("Not sure") { model.greenSpeed = nil }
            }
            .navigationTitle("Green speed")
        } label: {
            HStack {
                Text("Green").foregroundStyle(.secondary)
                Spacer()
                Text(model.greenSpeed.map { "\($0.shortTitle) \($0.stimpRange)" } ?? "Set speed")
                    .foregroundStyle(model.greenSpeed == nil ? Color.accentColor : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.footnote)
        }
    }
}

// MARK: - Practice

/// Vertical pages, driven by the Digital Crown: the live stroke, then the
/// session so far with the End control.
struct PracticePager: View {
    var body: some View {
        TabView {
            LiveStrokeView()
            SessionPage()
        }
        .tabViewStyle(.verticalPage)
    }
}

struct LiveStrokeView: View {
    @Environment(PracticeModel.self) private var model
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatusLine()

            if let m = model.latest {
                let g = model.settings.geometry
                VStack(alignment: .leading, spacing: 0) {
                    Text(Units.tempo(m.tempoRatio))
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("Tempo")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                    GridRow {
                        Text("Back").foregroundStyle(.secondary)
                        Text(model.units.length(g.length(forAngle: m.backswingAngle)))
                            .monospacedDigit()
                    }
                    GridRow {
                        Text("Through").foregroundStyle(.secondary)
                        Text(model.units.length(g.length(forAngle: m.throughAngle)))
                            .monospacedDigit()
                    }
                }
                .font(.body)
                .opacity(dimmed ? 0.6 : 1)

                RollButton(stroke: m)
            } else {
                Spacer(minLength: 0)
                Text("Make a stroke")
                    .font(.title3)
                Text("Tempo and length show here after each putt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .navigationTitle("Stroke \(max(model.strokes.count, 1))")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Shows the stroke's roll distance, or asks for it. Opens the roll picker.
struct RollButton: View {
    @Environment(PracticeModel.self) private var model
    let stroke: StrokeMetrics
    @State private var picking = false

    var body: some View {
        let roll = model.rolls[stroke.id]
        Button {
            picking = true
        } label: {
            HStack {
                Text("Roll").foregroundStyle(.secondary)
                Spacer()
                Text(roll.map { model.units.distance($0) } ?? "Add")
                    .monospacedDigit()
                    .foregroundStyle(roll == nil ? Color.accentColor : .primary)
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .sheet(isPresented: $picking) {
            RollPicker(stroke: stroke)
        }
    }
}

/// Sets how far the ball rolled with the Digital Crown, with − and +
/// buttons as a touch backup. Saving sends it to the phone.
struct RollPicker: View {
    @Environment(PracticeModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let stroke: StrokeMetrics
    /// In display units (feet or metres).
    @State private var value: Double = 10
    @State private var loaded = false

    private var step: Double { model.settings.usesMetric ? 0.5 : 1 }
    private var range: ClosedRange<Double> { model.settings.usesMetric ? 0.5...30 : 1...99 }

    var body: some View {
        let u = model.units
        VStack(spacing: 6) {
            Text("How far did it roll?")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button { nudge(-step) } label: { Image(systemName: "minus") }
                    .buttonStyle(.bordered)
                    .clipShape(Circle())
                    .accessibilityLabel("Shorter")
                Text(u.metric ? String(format: "%.1f", value) : String(format: "%.0f", value))
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .frame(minWidth: 70)
                    .contentTransition(.numericText())
                Button { nudge(step) } label: { Image(systemName: "plus") }
                    .buttonStyle(.bordered)
                    .clipShape(Circle())
                    .accessibilityLabel("Longer")
            }
            Text(u.distanceUnit)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button("Practice") {
                    model.setRoll(nil, for: stroke.id)
                    dismiss()
                }
                Button("Save") {
                    model.setRoll(u.metres(fromDistanceValue: value), for: stroke.id)
                    if model.settings.watchHaptics { WKInterfaceDevice.current().play(.success) }
                    dismiss()
                }
                .tint(.accentColor)
            }
        }
        .focusable()
        .digitalCrownRotation($value, from: range.lowerBound, through: range.upperBound, by: step,
                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let metres = model.rolls[stroke.id] ?? model.suggestedRoll(for: stroke)
            value = snap(u.distanceValue(metres))
        }
    }

    private func nudge(_ delta: Double) { value = snap(value + delta) }

    private func snap(_ v: Double) -> Double {
        min(max((v / step).rounded() * step, range.lowerBound), range.upperBound)
    }
}

/// A score with an info button that explains what it measures.
struct WatchScoreRow: View {
    let info: ScoreInfo
    let score: Double
    @State private var showingInfo = false

    var body: some View {
        Button {
            showingInfo = true
        } label: {
            HStack(spacing: 4) {
                Text(info.title)
                Image(systemName: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(score.rounded()))").monospacedDigit()
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows what \(info.title) means")
        .sheet(isPresented: $showingInfo) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(info.title).font(.headline)
                    Text(info.measures)
                    Text(info.scoring).foregroundStyle(.secondary)
                }
                .font(.footnote)
            }
        }
    }
}

/// Where the detector is, in words and a symbol, so it never relies on color.
struct StatusLine: View {
    @Environment(PracticeModel.self) private var model

    var body: some View {
        let (text, symbol): (String, String) = {
            if model.lastRejected != nil, model.status == .settling {
                return ("Not a stroke. Hold still", "xmark.circle")
            }
            switch model.status {
            case .settling, .idle: return ("Hold still at address", "hand.raised")
            case .ready: return ("Ready", "checkmark.circle")
            case .capturing: return ("Measuring", "waveform.path")
            }
        }()
        Label(text, systemImage: symbol)
            .font(.footnote.weight(.medium))
            .foregroundStyle(model.status == .ready ? Color.accentColor : .secondary)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.2), value: text)
    }
}

struct SessionPage: View {
    @Environment(PracticeModel.self) private var model

    var body: some View {
        let r = model.report
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Strokes", value: "\(r.strokeCount)")
                if let t = r.meanTempoRatio {
                    LabeledContent("Avg tempo", value: Units.tempo(t))
                }
                if let tempo = r.tempo, let rhythm = r.rhythm {
                    WatchScoreRow(info: .tempo, score: tempo)
                    WatchScoreRow(info: .rhythm, score: rhythm)
                    if let p = r.proportion { WatchScoreRow(info: .proportion, score: p) }
                } else {
                    Text("Scores appear after \(Consistency.minimumStrokes) strokes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    model.stop()
                } label: {
                    Label("End", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
            }
            .monospacedDigit()
        }
        .navigationTitle("Session")
    }
}
