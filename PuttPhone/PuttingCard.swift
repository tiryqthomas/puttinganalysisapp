import PuttCore
import SwiftUI

extension PuttingCardData {
    /// Rolls on the Lock Screen card. The in-app card shows more.
    static let lockScreenPaces: [Double] = [2, 4, 6, 8]
    static let cardPaces: [Double] = [1, 2, 3, 4, 6, 8, 10, 13]

    /// The green speed the card is for: the one picked on the Chart tab,
    /// else the player's usual speed.
    static func cardSpeed(chart: SpeedChart) -> GreenSpeed {
        UserDefaults.standard.string(forKey: "cardSpeed").flatMap(GreenSpeed.init(rawValue:))
            ?? GreenSpeed(stimp: chart.usualStimp)
    }

    static func setCardSpeed(_ speed: GreenSpeed, chart: SpeedChart, units: Units) {
        UserDefaults.standard.set(speed.rawValue, forKey: "cardSpeed")
        publish(chart: chart, units: units)
    }

    /// Updates the Lock Screen card from the stroke chart.
    static func publish(chart: SpeedChart?, units u: Units) {
        guard let chart else { save(nil); return }
        let speed = cardSpeed(chart: chart)
        let rows = lockScreenPaces.map { p in
            Row(paces: Units.paceNumber(p),
                backswing: u.length(chart.backswing(forDistance: u.metres(fromDistanceValue: p), stimp: speed.typicalStimp)))
        }
        save(PuttingCardData(speed: speed.shortTitle, rows: rows, updated: Date()))
    }
}

/// The cheat sheet: backswing for each roll at one green speed, on a dark
/// card that reads like the scorecard in your pocket.
struct PuttingCardView: View {
    @Environment(AppSettings.self) private var settings
    let chart: SpeedChart
    let speed: GreenSpeed
    @State private var showingLockHelp = false

    var body: some View {
        let u = settings.units
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Backswing for each roll").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(speed.shortTitle).font(.subheadline).foregroundStyle(.white.opacity(0.75))
                }
                .padding(.bottom, 10)
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(0..<2) { row in
                        if row > 0 { Divider().overlay(.white.opacity(0.2)) }
                        GridRow {
                            ForEach(PuttingCardData.cardPaces[(row * 4)..<(row * 4 + 4)], id: \.self) { p in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(Units.paceNumber(p)) \(p == 1 ? "pace" : "paces")")
                                        .font(.caption).foregroundStyle(.white.opacity(0.75))
                                    Text(u.length(chart.backswing(forDistance: u.metres(fromDistanceValue: p), stimp: speed.typicalStimp)))
                                        .font(.title3.weight(.semibold))
                                        .minimumScaleFactor(0.7)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
                .monospacedDigit()
            }
            .padding(16)
            .foregroundStyle(.white)
            .background(Color(red: 0.06, green: 0.29, blue: 0.20), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Putting card for \(speed.title.lowercased()) greens")

            HStack(spacing: 10) {
                Button {
                    PuttingCardData.setCardSpeed(speed, chart: chart, units: u)
                    showingLockHelp = true
                } label: {
                    Text("Add to Lock Screen").frame(maxWidth: .infinity)
                }
                ShareLink(item: shareText(u)) {
                    Text("Share").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .sheet(isPresented: $showingLockHelp) { LockScreenHelp(speed: speed) }
    }

    private func shareText(_ u: Units) -> String {
        let lines = PuttingCardData.cardPaces.map { p in
            "\(Units.paceNumber(p)) \(p == 1 ? "pace" : "paces"): \(u.length(chart.backswing(forDistance: u.metres(fromDistanceValue: p), stimp: speed.typicalStimp)))"
        }
        return (["My putting card, \(speed.title.lowercased()) greens (\(speed.stimpRange))"] + lines).joined(separator: "\n")
    }
}

/// Apps can't place a widget themselves, so this says how, once.
struct LockScreenHelp: View {
    @Environment(\.dismiss) private var dismiss
    let speed: GreenSpeed

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Touch and hold your Lock Screen, then tap Customize.", systemImage: "1.circle")
                    Label("Tap Lock Screen, then the space under the clock.", systemImage: "2.circle")
                    Label("Pick Putting, then Putting card.", systemImage: "3.circle")
                } footer: {
                    Text("The card shows your backswing for 2, 4, 6 and 8 paces on \(speed.title.lowercased()) greens. Change the speed on the Chart tab and it follows.")
                }
            }
            .navigationTitle("Add to Lock Screen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
