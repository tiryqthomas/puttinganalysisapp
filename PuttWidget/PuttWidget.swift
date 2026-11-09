import SwiftUI
import WidgetKit

/// The Putting card on the Lock Screen: backswing for 2, 4, 6 and 8 paces
/// at the green speed picked on the Chart tab. It only changes when the
/// stroke chart does, so it never needs a refresh schedule.
@main
struct PuttWidgetBundle: WidgetBundle {
    var body: some Widget { PuttingCardWidget() }
}

struct PuttingCardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PuttingCard", provider: CardProvider()) { entry in
            CardWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(red: 0.06, green: 0.29, blue: 0.20) }
        }
        .configurationDisplayName("Putting card")
        .description("Your backswing for each roll, from your own stroke chart.")
        .supportedFamilies([.accessoryRectangular, .systemSmall])
    }
}

struct CardEntry: TimelineEntry {
    let date: Date
    let card: PuttingCardData?
}

struct CardProvider: TimelineProvider {
    func placeholder(in context: Context) -> CardEntry { CardEntry(date: Date(), card: .example) }

    func getSnapshot(in context: Context, completion: @escaping (CardEntry) -> Void) {
        completion(CardEntry(date: Date(), card: context.isPreview ? (PuttingCardData.stored ?? .example) : PuttingCardData.stored))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CardEntry>) -> Void) {
        // The phone app reloads the widget whenever the card changes.
        completion(Timeline(entries: [CardEntry(date: Date(), card: PuttingCardData.stored)], policy: .never))
    }
}

struct CardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CardEntry

    var body: some View {
        if let card = entry.card {
            switch family {
            case .accessoryRectangular: rectangular(card)
            default: small(card)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Putting card").font(.headline)
                Text("Log a few rolls to fill it in.").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Lock Screen: four columns, paces over backswing. The system tints it.
    private func rectangular(_ card: PuttingCardData) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Putting · \(card.speed)")
                .font(.caption.weight(.semibold))
                .widgetAccentable()
            HStack(spacing: 6) {
                ForEach(card.rows, id: \.self) { row in
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(row.paces)p").font(.caption2).foregroundStyle(.secondary)
                        Text(row.backswing.replacingOccurrences(of: " in", with: "″").replacingOccurrences(of: " cm", with: ""))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Putting card, \(card.speed) greens. " + card.rows.map { "\($0.paces) paces, \($0.backswing)" }.joined(separator: ". "))
    }

    private func small(_ card: PuttingCardData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Putting").font(.caption.weight(.semibold))
                Spacer()
                Text(card.speed).font(.caption).opacity(0.75)
            }
            ForEach(card.rows, id: \.self) { row in
                HStack {
                    Text("\(row.paces) paces").font(.caption).opacity(0.75)
                    Spacer()
                    Text(row.backswing).font(.subheadline.weight(.semibold))
                }
            }
        }
        .monospacedDigit()
        .foregroundStyle(.white)
    }
}
