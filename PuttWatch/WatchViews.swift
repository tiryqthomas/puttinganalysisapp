import PuttCore
import SwiftUI

// MARK: - Start

struct StartView: View {
    @Environment(PracticeModel.self) private var model

    var body: some View {
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
                    LabeledContent("Tempo score", value: "\(Int(tempo.rounded()))")
                    LabeledContent("Rhythm score", value: "\(Int(rhythm.rounded()))")
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
