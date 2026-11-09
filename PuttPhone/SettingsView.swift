import PuttCore
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \PuttStroke.recordedAt, order: .reverse) private var strokes: [PuttStroke]
    @State private var measured = ""
    @State private var calibrated = false

    var body: some View {
        @Bindable var settings = settings
        let u = settings.units

        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Units", selection: $settings.value.usesMetric) {
                        Text("Feet and inches").tag(false)
                        Text("Metres and centimetres").tag(true)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    Stepper(value: $settings.value.pivotToHead, in: 0.7...1.6, step: 0.01) {
                        LabeledContent("Pivot to putter head", value: u.length(settings.value.pivotToHead, decimals: 0))
                            .monospacedDigit()
                    }
                } header: {
                    Text("Stroke size")
                } footer: {
                    Text("The watch measures how far your arms rotate. This length turns that rotation into putter-head travel. Most players are close to \(u.length(1.1, decimals: 0)); calibrate below for an exact number.")
                }

                Section {
                    if let latest = strokes.first {
                        HStack {
                            Text("Measured backswing")
                            Spacer()
                            TextField("0", text: $measured)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 80)
                            Text(u.lengthUnit).foregroundStyle(.secondary)
                        }
                        Button("Calibrate from latest stroke") {
                            guard let v = Double(measured.replacingOccurrences(of: ",", with: ".")), v > 0 else { return }
                            let metres = u.metric ? v / 100 : v * 0.0254
                            if let g = StrokeGeometry.calibrated(from: latest.metrics, measuredBackswing: metres) {
                                settings.value.pivotToHead = min(max(g.pivotToHead, 0.7), 1.6)
                                calibrated = true
                                measured = ""
                            }
                        }
                        .disabled(Double(measured.replacingOccurrences(of: ",", with: ".")) == nil)
                        if calibrated {
                            Label("Calibrated", systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Make one stroke first.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Calibrate")
                } footer: {
                    Text("Lay a ruler or alignment stick behind the ball. Make a stroke, note how far back the putter head went, and enter it here.")
                }

                Section {
                    Toggle("Tap when a stroke is recorded", isOn: $settings.value.watchHaptics)
                } header: {
                    Text("Watch")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
